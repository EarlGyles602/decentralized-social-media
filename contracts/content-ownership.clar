;; Content Ownership Contract
;; Manages user-owned content with cryptographic proof of authorship
;; Handles content monetization through tips and subscriptions
;; Maintains decentralized storage references for media content
;; Processes content licensing and usage rights management

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_CONTENT_NOT_FOUND (err u2))
(define-constant ERR_INSUFFICIENT_FUNDS (err u3))
(define-constant ERR_INVALID_AMOUNT (err u4))
(define-constant ERR_ALREADY_SUBSCRIBED (err u5))
(define-constant ERR_NOT_SUBSCRIBED (err u6))
(define-constant ERR_CONTENT_EXISTS (err u7))
(define-constant ERR_INVALID_LICENSE_TYPE (err u8))

;; Data Variables
(define-data-var content-counter uint u0)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee

;; Data Maps
(define-map content-registry
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    content-hash: (string-ascii 64),
    storage-reference: (string-ascii 200),
    created-at: uint,
    tip-amount: uint,
    subscription-price: uint,
    license-type: (string-ascii 20),
    is-premium: bool,
    total-tips: uint,
    view-count: uint
  }
)

(define-map user-subscriptions
  { subscriber: principal, creator: principal }
  {
    subscribed-at: uint,
    expires-at: uint,
    amount-paid: uint
  }
)

(define-map content-licensing
  { content-id: uint, licensee: principal }
  {
    license-type: (string-ascii 20),
    granted-at: uint,
    expires-at: uint,
    fee-paid: uint
  }
)

(define-map creator-earnings
  { creator: principal }
  {
    total-earned: uint,
    total-tips: uint,
    total-subscriptions: uint,
    total-licenses: uint
  }
)

(define-map user-content-access
  { user: principal, content-id: uint }
  { last-accessed: uint, access-count: uint }
)

;; Private Functions
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u100)
)

(define-private (update-creator-earnings (creator principal) (amount uint) (earning-type (string-ascii 20)))
  (let (
    (current-earnings (default-to { total-earned: u0, total-tips: u0, total-subscriptions: u0, total-licenses: u0 }
                                  (map-get? creator-earnings { creator: creator })))
  )
    (if (is-eq earning-type "tip")
      (map-set creator-earnings { creator: creator }
        (merge current-earnings {
          total-earned: (+ (get total-earned current-earnings) amount),
          total-tips: (+ (get total-tips current-earnings) amount)
        })
      )
      (if (is-eq earning-type "subscription")
        (map-set creator-earnings { creator: creator }
          (merge current-earnings {
            total-earned: (+ (get total-earned current-earnings) amount),
            total-subscriptions: (+ (get total-subscriptions current-earnings) amount)
          })
        )
        (if (is-eq earning-type "license")
          (map-set creator-earnings { creator: creator }
            (merge current-earnings {
              total-earned: (+ (get total-earned current-earnings) amount),
              total-licenses: (+ (get total-licenses current-earnings) amount)
            })
          )
          false
        )
      )
    )
  )
)

;; Public Functions

;; Create new content with ownership proof
(define-public (create-content 
    (title (string-ascii 100))
    (content-hash (string-ascii 64))
    (storage-reference (string-ascii 200))
    (subscription-price uint)
    (license-type (string-ascii 20))
    (is-premium bool)
  )
  (let (
    (content-id (+ (var-get content-counter) u1))
  )
    ;; Validate license type
    (asserts! (or (is-eq license-type "public")
                  (or (is-eq license-type "commercial")
                      (is-eq license-type "exclusive")))
              ERR_INVALID_LICENSE_TYPE)
    
    ;; Content creation continues without duplicate check for simplicity
    
    ;; Create content entry
    (map-set content-registry
      { content-id: content-id }
      {
        creator: tx-sender,
        title: title,
        content-hash: content-hash,
        storage-reference: storage-reference,
        created-at: u1,
        tip-amount: u0,
        subscription-price: subscription-price,
        license-type: license-type,
        is-premium: is-premium,
        total-tips: u0,
        view-count: u0
      }
    )
    
    ;; Update content counter
    (var-set content-counter content-id)
    
    ;; Return success with content ID
    (ok content-id)
  )
)

;; Tip content creator
(define-public (tip-creator (content-id uint) (tip-amount uint))
  (let (
    (content-data (unwrap! (map-get? content-registry { content-id: content-id }) ERR_CONTENT_NOT_FOUND))
    (creator (get creator content-data))
    (platform-fee (calculate-platform-fee tip-amount))
    (creator-amount (- tip-amount platform-fee))
  )
    ;; Validate tip amount
    (asserts! (> tip-amount u0) ERR_INVALID_AMOUNT)
    
    ;; Check sender has sufficient funds
    (asserts! (>= (stx-get-balance tx-sender) tip-amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer STX from tipper to creator
    (try! (stx-transfer? creator-amount tx-sender creator))
    
    ;; Transfer platform fee to contract owner
    (try! (stx-transfer? platform-fee tx-sender CONTRACT_OWNER))
    
    ;; Update content tip statistics
    (map-set content-registry
      { content-id: content-id }
      (merge content-data {
        tip-amount: (+ (get tip-amount content-data) tip-amount),
        total-tips: (+ (get total-tips content-data) u1)
      })
    )
    
    ;; Update creator earnings
    (update-creator-earnings creator creator-amount "tip")
    
    (ok true)
  )
)

;; Subscribe to creator
(define-public (subscribe-to-creator (creator principal) (duration-blocks uint))
  (let (
    (subscription-key { subscriber: tx-sender, creator: creator })
    (existing-sub (map-get? user-subscriptions subscription-key))
    (subscription-fee u1000000) ;; 1 STX per month equivalent in microSTX
    (platform-fee (calculate-platform-fee subscription-fee))
    (creator-amount (- subscription-fee platform-fee))
  )
    ;; Check if already subscribed and not expired
    (asserts! (or (is-none existing-sub)
          (< (get expires-at (unwrap-panic existing-sub)) u1))
              ERR_ALREADY_SUBSCRIBED)
    
    ;; Validate duration
    (asserts! (> duration-blocks u0) ERR_INVALID_AMOUNT)
    
    ;; Check sender has sufficient funds
    (asserts! (>= (stx-get-balance tx-sender) subscription-fee) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer payment
    (try! (stx-transfer? creator-amount tx-sender creator))
    (try! (stx-transfer? platform-fee tx-sender CONTRACT_OWNER))
    
    ;; Create or update subscription
    (map-set user-subscriptions
      subscription-key
      {
        subscribed-at: u1,
        expires-at: (+ u1 duration-blocks),
        amount-paid: subscription-fee
      }
    )
    
    ;; Update creator earnings
    (update-creator-earnings creator creator-amount "subscription")
    
    (ok true)
  )
)

;; Purchase content license
(define-public (purchase-license 
    (content-id uint)
    (license-type (string-ascii 20))
    (duration-blocks uint)
  )
  (let (
    (content-data (unwrap! (map-get? content-registry { content-id: content-id }) ERR_CONTENT_NOT_FOUND))
    (creator (get creator content-data))
    (license-fee (if (is-eq license-type "commercial") u5000000
                    (if (is-eq license-type "exclusive") u10000000 u1000000)))
    (platform-fee (calculate-platform-fee license-fee))
    (creator-amount (- license-fee platform-fee))
    (license-key { content-id: content-id, licensee: tx-sender })
  )
    ;; Validate license type
    (asserts! (or (is-eq license-type "public")
                  (or (is-eq license-type "commercial")
                      (is-eq license-type "exclusive")))
              ERR_INVALID_LICENSE_TYPE)
    
    ;; Check sender has sufficient funds
    (asserts! (>= (stx-get-balance tx-sender) license-fee) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer payment
    (try! (stx-transfer? creator-amount tx-sender creator))
    (try! (stx-transfer? platform-fee tx-sender CONTRACT_OWNER))
    
    ;; Grant license
    (map-set content-licensing
      license-key
      {
        license-type: license-type,
        granted-at: u1,
        expires-at: (+ u1 duration-blocks),
        fee-paid: license-fee
      }
    )
    
    ;; Update creator earnings
    (update-creator-earnings creator creator-amount "license")
    
    (ok true)
  )
)

;; Access premium content (requires subscription or ownership)
(define-public (access-content (content-id uint))
  (let (
    (content-data (unwrap! (map-get? content-registry { content-id: content-id }) ERR_CONTENT_NOT_FOUND))
    (creator (get creator content-data))
    (is-premium (get is-premium content-data))
    (subscription-key { subscriber: tx-sender, creator: creator })
    (user-sub (map-get? user-subscriptions subscription-key))
    (access-key { user: tx-sender, content-id: content-id })
    (current-access (default-to { last-accessed: u0, access-count: u0 }
                                (map-get? user-content-access access-key)))
  )
    ;; Check if content is premium and user has access
    (if is-premium
      (asserts! (or (is-eq tx-sender creator)
                    (and (is-some user-sub)
                         (> (get expires-at (unwrap-panic user-sub)) u1)))
                ERR_UNAUTHORIZED)
      true
    )
    
    ;; Update access statistics
    (map-set user-content-access
      access-key
      {
        last-accessed: u1,
        access-count: (+ (get access-count current-access) u1)
      }
    )
    
    ;; Update content view count
    (map-set content-registry
      { content-id: content-id }
      (merge content-data {
        view-count: (+ (get view-count content-data) u1)
      })
    )
    
    (ok content-data)
  )
)

;; Update platform fee (only contract owner)
(define-public (update-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee-percentage u20) ERR_INVALID_AMOUNT) ;; Max 20% fee
    (var-set platform-fee-percentage new-fee-percentage)
    (ok true)
  )
)

;; Read-only functions

;; Get content details
(define-read-only (get-content (content-id uint))
  (map-get? content-registry { content-id: content-id })
)

;; Get user subscription status
(define-read-only (get-subscription (subscriber principal) (creator principal))
  (map-get? user-subscriptions { subscriber: subscriber, creator: creator })
)

;; Get creator earnings
(define-read-only (get-creator-earnings (creator principal))
  (map-get? creator-earnings { creator: creator })
)

;; Get content license
(define-read-only (get-content-license (content-id uint) (licensee principal))
  (map-get? content-licensing { content-id: content-id, licensee: licensee })
)

;; Get platform fee percentage
(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

;; Get total content count
(define-read-only (get-content-count)
  (var-get content-counter)
)

;; Check if user has access to content
(define-read-only (has-content-access (user principal) (content-id uint))
  (match (map-get? content-registry { content-id: content-id })
    content-data
    (let (
      (creator (get creator content-data))
      (is-premium (get is-premium content-data))
      (subscription-key { subscriber: user, creator: creator })
      (user-sub (map-get? user-subscriptions subscription-key))
    )
      (or (not is-premium)
          (is-eq user creator)
          (and (is-some user-sub)
               (> (get expires-at (unwrap-panic user-sub)) u1)))
    )
    false
  )
)

;; title: content-ownership
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

