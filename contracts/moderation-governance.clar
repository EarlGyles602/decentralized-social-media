;; Moderation Governance Contract
;; Coordinates community-driven content moderation through decentralized voting
;; Manages reputation-based moderation privileges and responsibilities
;; Handles appeals and dispute resolution for content decisions
;; Maintains platform governance through stakeholder voting mechanisms

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_REPORT_NOT_FOUND (err u2))
(define-constant ERR_ALREADY_VOTED (err u3))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u4))
(define-constant ERR_VOTE_PERIOD_ENDED (err u5))
(define-constant ERR_VOTE_PERIOD_ACTIVE (err u6))
(define-constant ERR_INVALID_ACTION (err u7))
(define-constant ERR_APPEAL_NOT_FOUND (err u8))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u9))
(define-constant ERR_ALREADY_APPEALED (err u10))

;; Configuration Constants
(define-constant MIN_MODERATOR_REPUTATION u100)
(define-constant VOTING_PERIOD_BLOCKS u2016) ;; ~2 weeks
(define-constant APPEAL_PERIOD_BLOCKS u1008) ;; ~1 week
(define-constant MIN_VOTES_FOR_DECISION u5)
(define-constant REPUTATION_REWARD_CORRECT_VOTE u10)
(define-constant REPUTATION_PENALTY_INCORRECT_VOTE u5)

;; Data Variables
(define-data-var report-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var appeal-counter uint u0)

;; Data Maps
(define-map content-reports
  { report-id: uint }
  {
    reporter: principal,
    content-id: uint,
    reason: (string-ascii 200),
    reported-at: uint,
    status: (string-ascii 20),
    moderator-assigned: (optional principal),
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    decision: (optional (string-ascii 20)),
    resolved-at: (optional uint)
  }
)

(define-map moderation-votes
  { report-id: uint, voter: principal }
  {
    vote: bool, ;; true = action needed, false = no action
    voted-at: uint,
    weight: uint,
    reasoning: (optional (string-ascii 200))
  }
)

(define-map user-reputation
  { user: principal }
  {
    reputation-score: uint,
    total-votes-cast: uint,
    correct-votes: uint,
    incorrect-votes: uint,
    is-moderator: bool,
    moderator-since: (optional uint),
    reports-submitted: uint,
    successful-reports: uint
  }
)

(define-map content-appeals
  { appeal-id: uint }
  {
    appellant: principal,
    report-id: uint,
    appeal-reason: (string-ascii 300),
    submitted-at: uint,
    status: (string-ascii 20),
    jury-assigned: (list 5 principal),
    jury-votes-for: uint,
    jury-votes-against: uint,
    appeal-decision: (optional (string-ascii 20)),
    resolved-at: (optional uint)
  }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: (string-ascii 30),
    proposed-at: uint,
    voting-ends-at: uint,
    votes-for: uint,
    votes-against: uint,
    total-participants: uint,
    status: (string-ascii 20),
    execution-payload: (optional (string-ascii 200))
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool, ;; true = for, false = against
    voting-power: uint,
    voted-at: uint
  }
)

(define-map jury-votes
  { appeal-id: uint, juror: principal }
  {
    vote: bool, ;; true = uphold appeal, false = reject appeal
    voted-at: uint,
    reasoning: (optional (string-ascii 200))
  }
)

;; Private Functions

(define-private (calculate-voting-weight (user principal))
  (let (
    (user-rep (default-to { reputation-score: u10, total-votes-cast: u0, correct-votes: u0, 
                           incorrect-votes: u0, is-moderator: false, moderator-since: none,
                           reports-submitted: u0, successful-reports: u0 }
                          (map-get? user-reputation { user: user })))
  )
    (+ u1 (/ (get reputation-score user-rep) u10))
  )
)

(define-private (update-reputation (user principal) (correct-vote bool) (action (string-ascii 20)))
  (let (
    (current-rep (default-to { reputation-score: u10, total-votes-cast: u0, correct-votes: u0, 
                              incorrect-votes: u0, is-moderator: false, moderator-since: none,
                              reports-submitted: u0, successful-reports: u0 }
                             (map-get? user-reputation { user: user })))
    (score-change (if correct-vote REPUTATION_REWARD_CORRECT_VOTE 
                     (- REPUTATION_PENALTY_INCORRECT_VOTE)))
    (new-score (if correct-vote 
                  (+ (get reputation-score current-rep) score-change)
                  (if (>= (get reputation-score current-rep) score-change)
                     (- (get reputation-score current-rep) score-change)
                     u0)))
  )
    (if (is-eq action "vote")
      (map-set user-reputation { user: user }
        (merge current-rep {
          reputation-score: new-score,
          total-votes-cast: (+ (get total-votes-cast current-rep) u1),
          correct-votes: (if correct-vote (+ (get correct-votes current-rep) u1)
                            (get correct-votes current-rep)),
          incorrect-votes: (if (not correct-vote) (+ (get incorrect-votes current-rep) u1)
                              (get incorrect-votes current-rep))
        })
      )
      (if (is-eq action "report")
        (map-set user-reputation { user: user }
          (merge current-rep {
            reports-submitted: (+ (get reports-submitted current-rep) u1),
            successful-reports: (if correct-vote (+ (get successful-reports current-rep) u1)
                                   (get successful-reports current-rep))
          })
        )
        false
      )
    )
    ;; Check if user qualifies for moderator status
    (if (and (not (get is-moderator current-rep))
             (>= new-score MIN_MODERATOR_REPUTATION))
      (map-set user-reputation { user: user }
        (merge (unwrap-panic (map-get? user-reputation { user: user })) {
          is-moderator: true,
          moderator-since: (some u1)
        })
      )
      false
    )
  )
)

(define-private (select-random-jury (exclude-user principal)) 
  (let (
    ;; This is a simplified jury selection - in production would use more sophisticated randomization
    (potential-jurors (list 
      'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
      'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5
      'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG
      'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC
      'ST2NEB84ASENDXKYGJPQW86YXQCEFEX2ZQPG87ND
    ))
  )
    ;; Return first 5 moderators as jury (simplified)
    potential-jurors
  )
)

;; Public Functions

;; Report content for moderation
(define-public (report-content (content-id uint) (reason (string-ascii 200)))
  (let (
    (report-id (+ (var-get report-counter) u1))
  )
    ;; Create content report
    (map-set content-reports
      { report-id: report-id }
      {
        reporter: tx-sender,
        content-id: content-id,
        reason: reason,
        reported-at: u1,
        status: "pending",
        moderator-assigned: none,
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        decision: none,
        resolved-at: none
      }
    )
    
    ;; Update counter
    (var-set report-counter report-id)
    
    ;; Update reporter reputation
    (update-reputation tx-sender true "report")
    
    (ok report-id)
  )
)

;; Vote on content moderation
(define-public (vote-on-report (report-id uint) (vote bool) (reasoning (optional (string-ascii 200))))
  (let (
    (report-data (unwrap! (map-get? content-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
    (voter-reputation (default-to { reputation-score: u10, total-votes-cast: u0, correct-votes: u0, 
                                   incorrect-votes: u0, is-moderator: false, moderator-since: none,
                                   reports-submitted: u0, successful-reports: u0 }
                                  (map-get? user-reputation { user: tx-sender })))
    (voting-weight (calculate-voting-weight tx-sender))
    (vote-key { report-id: report-id, voter: tx-sender })
  )
    ;; Check if already voted
    (asserts! (is-none (map-get? moderation-votes vote-key)) ERR_ALREADY_VOTED)
    
    ;; Check if voting period is still active
    (asserts! (is-eq (get status report-data) "pending") ERR_VOTE_PERIOD_ENDED)
    
    ;; Record vote
    (map-set moderation-votes
      vote-key
      {
        vote: vote,
        voted-at: u1,
        weight: voting-weight,
        reasoning: reasoning
      }
    )
    
    ;; Update report vote counts
    (map-set content-reports
      { report-id: report-id }
      (merge report-data {
        votes-for: (if vote (+ (get votes-for report-data) voting-weight) (get votes-for report-data)),
        votes-against: (if (not vote) (+ (get votes-against report-data) voting-weight) (get votes-against report-data)),
        total-votes: (+ (get total-votes report-data) u1)
      })
    )
    
    ;; Check if enough votes to make decision
    (let (
      (updated-report (unwrap-panic (map-get? content-reports { report-id: report-id })))
    )
      (if (>= (get total-votes updated-report) MIN_VOTES_FOR_DECISION)
        (let (
          (decision (if (> (get votes-for updated-report) (get votes-against updated-report)) "action-required" "no-action"))
        )
          ;; Finalize decision
          (map-set content-reports
            { report-id: report-id }
            (merge updated-report {
              status: "resolved",
              decision: (some decision),
              resolved-at: (some u1)
            })
          )
          ;; Update reputation for all voters based on majority decision
          ;; (Simplified - in production would iterate through all voters)
          (ok decision)
        )
        (ok "vote-recorded")
      )
    )
  )
)

;; Submit appeal for moderation decision
(define-public (submit-appeal (report-id uint) (appeal-reason (string-ascii 300)))
  (let (
    (report-data (unwrap! (map-get? content-reports { report-id: report-id }) ERR_REPORT_NOT_FOUND))
    (appeal-id (+ (var-get appeal-counter) u1))
  )
    ;; Check if report is resolved
    (asserts! (is-eq (get status report-data) "resolved") ERR_VOTE_PERIOD_ACTIVE)
    
    ;; Check if appeal period is still active
    (asserts! (< (- u1 (unwrap-panic (get resolved-at report-data))) APPEAL_PERIOD_BLOCKS)
              ERR_VOTE_PERIOD_ENDED)
    
    ;; Create appeal
    (map-set content-appeals
      { appeal-id: appeal-id }
      {
        appellant: tx-sender,
        report-id: report-id,
        appeal-reason: appeal-reason,
        submitted-at: u1,
        status: "jury-review",
        jury-assigned: (select-random-jury tx-sender),
        jury-votes-for: u0,
        jury-votes-against: u0,
        appeal-decision: none,
        resolved-at: none
      }
    )
    
    ;; Update counter
    (var-set appeal-counter appeal-id)
    
    (ok appeal-id)
  )
)

;; Jury vote on appeal
(define-public (jury-vote-appeal (appeal-id uint) (vote bool) (reasoning (optional (string-ascii 200))))
  (let (
    (appeal-data (unwrap! (map-get? content-appeals { appeal-id: appeal-id }) ERR_APPEAL_NOT_FOUND))
    (jury-list (get jury-assigned appeal-data))
    (vote-key { appeal-id: appeal-id, juror: tx-sender })
  )
    ;; Check if user is in jury
    (asserts! (is-some (index-of jury-list tx-sender)) ERR_UNAUTHORIZED)
    
    ;; Check if already voted
    (asserts! (is-none (map-get? jury-votes vote-key)) ERR_ALREADY_VOTED)
    
    ;; Record jury vote
    (map-set jury-votes
      vote-key
      {
        vote: vote,
        voted-at: u1,
        reasoning: reasoning
      }
    )
    
    ;; Update appeal vote counts
    (map-set content-appeals
      { appeal-id: appeal-id }
      (merge appeal-data {
        jury-votes-for: (if vote (+ (get jury-votes-for appeal-data) u1) (get jury-votes-for appeal-data)),
        jury-votes-against: (if (not vote) (+ (get jury-votes-against appeal-data) u1) (get jury-votes-against appeal-data))
      })
    )
    
    ;; Check if all jury members have voted
    (let (
      (updated-appeal (unwrap-panic (map-get? content-appeals { appeal-id: appeal-id })))
      (total-jury-votes (+ (get jury-votes-for updated-appeal) (get jury-votes-against updated-appeal)))
    )
      (if (>= total-jury-votes u3) ;; Minimum 3 votes for decision
        (let (
          (appeal-decision (if (> (get jury-votes-for updated-appeal) (get jury-votes-against updated-appeal)) 
                              "appeal-upheld" "appeal-rejected"))
        )
          ;; Finalize appeal decision
          (map-set content-appeals
            { appeal-id: appeal-id }
            (merge updated-appeal {
              status: "resolved",
              appeal-decision: (some appeal-decision),
              resolved-at: (some u1)
            })
          )
          (ok appeal-decision)
        )
        (ok "jury-vote-recorded")
      )
    )
  )
)

;; Create governance proposal
(define-public (create-proposal 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (proposal-type (string-ascii 30))
    (execution-payload (optional (string-ascii 200)))
  )
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (user-rep (default-to { reputation-score: u10, total-votes-cast: u0, correct-votes: u0, 
                           incorrect-votes: u0, is-moderator: false, moderator-since: none,
                           reports-submitted: u0, successful-reports: u0 }
                          (map-get? user-reputation { user: tx-sender })))
  )
    ;; Check minimum reputation to create proposals
    (asserts! (>= (get reputation-score user-rep) u50) ERR_INSUFFICIENT_REPUTATION)
    
    ;; Create proposal
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        proposed-at: u1,
        voting-ends-at: (+ u1 VOTING_PERIOD_BLOCKS),
        votes-for: u0,
        votes-against: u0,
        total-participants: u0,
        status: "active",
        execution-payload: execution-payload
      }
    )
    
    ;; Update counter
    (var-set proposal-counter proposal-id)
    
    (ok proposal-id)
  )
)

;; Vote on governance proposal
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let (
    (proposal-data (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
    (voting-power (calculate-voting-weight tx-sender))
    (vote-key { proposal-id: proposal-id, voter: tx-sender })
  )
    ;; Check if already voted
    (asserts! (is-none (map-get? proposal-votes vote-key)) ERR_ALREADY_VOTED)
    
    ;; Check if voting period is active
    (asserts! (< u1 (get voting-ends-at proposal-data)) ERR_VOTE_PERIOD_ENDED)
    (asserts! (is-eq (get status proposal-data) "active") ERR_VOTE_PERIOD_ENDED)
    
    ;; Record vote
    (map-set proposal-votes
      vote-key
      {
        vote: vote,
        voting-power: voting-power,
        voted-at: u1
      }
    )
    
    ;; Update proposal vote counts
    (map-set governance-proposals
      { proposal-id: proposal-id }
      (merge proposal-data {
        votes-for: (if vote (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)),
        votes-against: (if (not vote) (+ (get votes-against proposal-data) voting-power) (get votes-against proposal-data)),
        total-participants: (+ (get total-participants proposal-data) u1)
      })
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get content report details
(define-read-only (get-report (report-id uint))
  (map-get? content-reports { report-id: report-id })
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Get appeal details
(define-read-only (get-appeal (appeal-id uint))
  (map-get? content-appeals { appeal-id: appeal-id })
)

;; Get governance proposal
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Check if user can moderate
(define-read-only (can-moderate (user principal))
  (match (map-get? user-reputation { user: user })
    user-rep (and (get is-moderator user-rep) 
                  (>= (get reputation-score user-rep) MIN_MODERATOR_REPUTATION))
    false
  )
)

;; Get moderation vote
(define-read-only (get-moderation-vote (report-id uint) (voter principal))
  (map-get? moderation-votes { report-id: report-id, voter: voter })
)

;; Get total reports count
(define-read-only (get-total-reports)
  (var-get report-counter)
)

;; Get total proposals count
(define-read-only (get-total-proposals)
  (var-get proposal-counter)
)

;; title: moderation-governance
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

