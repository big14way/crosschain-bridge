;; bridge-governance.clar
;; Decentralized governance system for bridge parameters and upgrades
;; Uses Clarity 4 features with comprehensive Chainhook event emission

;; ========================================
;; Constants
;; ========================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u20001))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u20002))
(define-constant ERR_PROPOSAL_EXISTS (err u20003))
(define-constant ERR_INVALID_PROPOSAL (err u20004))
(define-constant ERR_VOTING_ENDED (err u20005))
(define-constant ERR_VOTING_NOT_ENDED (err u20006))
(define-constant ERR_ALREADY_VOTED (err u20007))
(define-constant ERR_INSUFFICIENT_VOTING_POWER (err u20008))
(define-constant ERR_PROPOSAL_EXECUTED (err u20009))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u20010))
(define-constant ERR_INVALID_DELEGATION (err u20011))
(define-constant ERR_QUORUM_NOT_REACHED (err u20012))

;; Proposal types
(define-constant PROPOSAL_TYPE_FEE_CHANGE u1)
(define-constant PROPOSAL_TYPE_BRIDGE_ACTIVATION u2)
(define-constant PROPOSAL_TYPE_RISK_SCORE_UPDATE u3)
(define-constant PROPOSAL_TYPE_INSURANCE_CONFIG u4)
(define-constant PROPOSAL_TYPE_GENERAL u5)

;; Voting parameters
(define-constant VOTING_PERIOD_BLOCKS u1440) ;; ~10 days
(define-constant QUORUM_PERCENTAGE u20) ;; 20% of total voting power
(define-constant APPROVAL_THRESHOLD u51) ;; 51% of votes must be "yes"

;; ========================================
;; Data Variables
;; ========================================

(define-data-var proposal-counter uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var governance-token-contract principal tx-sender)
(define-data-var min-proposal-deposit uint u1000000) ;; 1 STX
(define-data-var proposal-execution-delay uint u144) ;; ~1 day
(define-data-var contract-vault principal tx-sender)

;; ========================================
;; Data Maps
;; ========================================

;; Governance proposals
(define-map proposals
    uint
    {
        proposer: principal,
        proposal-type: uint,
        title: (string-ascii 128),
        description: (string-utf8 512),
        target-bridge-id: uint,
        proposed-value: uint,
        created-at: uint,
        voting-ends-at: uint,
        executed-at: uint,
        executed: bool,
        canceled: bool,
        deposit: uint,
        votes-for: uint,
        votes-against: uint,
        votes-abstain: uint,
        total-votes: uint,
        quorum-reached: bool,
        passed: bool
    }
)

;; User votes on proposals
(define-map proposal-votes
    { proposal-id: uint, voter: principal }
    {
        vote-type: (string-ascii 8), ;; "for", "against", "abstain"
        voting-power: uint,
        voted-at: uint,
        delegated-from: (optional principal)
    }
)

;; User voting power (based on bridge usage, liquidity provision, etc.)
(define-map user-voting-power
    principal
    {
        base-power: uint,
        bonus-power: uint,
        delegated-power: uint,
        total-power: uint,
        last-updated: uint
    }
)

;; Vote delegation
(define-map vote-delegation
    principal ;; delegator
    {
        delegate: principal,
        delegated-amount: uint,
        delegated-at: uint,
        active: bool
    }
)

;; Track delegation received
(define-map delegation-received
    principal ;; delegate
    {
        total-delegated: uint,
        delegator-count: uint
    }
)

;; Proposal execution queue
(define-map execution-queue
    uint ;; proposal-id
    {
        queued-at: uint,
        executable-at: uint,
        executed: bool
    }
)

;; User proposal participation tracking
(define-map user-governance-stats
    principal
    {
        proposals-created: uint,
        proposals-voted: uint,
        last-vote-at: uint,
        participation-score: uint
    }
)

;; Proposal comments/discussion
(define-map proposal-comments
    { proposal-id: uint, comment-id: uint }
    {
        author: principal,
        comment: (string-utf8 256),
        created-at: uint
    }
)

(define-data-var comment-counter uint u0)

;; ========================================
;; Read-Only Functions
;; ========================================

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get user's vote on a proposal
(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; Get user's voting power
(define-read-only (get-voting-power (user principal))
    (default-to
        { base-power: u0, bonus-power: u0, delegated-power: u0, total-power: u0, last-updated: u0 }
        (map-get? user-voting-power user)
    )
)

;; Get effective voting power (including delegations)
(define-read-only (get-effective-voting-power (user principal))
    (let
        (
            (power (get-voting-power user))
            (delegation (map-get? vote-delegation user))
            (delegated-to-others (match delegation
                d (if (get active d) (get delegated-amount d) u0)
                u0))
        )
        {
            own-power: (- (get total-power power) delegated-to-others),
            delegated-from-others: (get delegated-power power),
            total-effective-power: (+ (- (get total-power power) delegated-to-others) (get delegated-power power))
        }
    )
)

;; Check if user has voted on proposal
(define-read-only (has-voted (proposal-id uint) (user principal))
    (is-some (get-user-vote proposal-id user))
)

;; Calculate current quorum threshold
(define-read-only (calculate-quorum-threshold)
    (/ (* (var-get total-voting-power) QUORUM_PERCENTAGE) u100)
)

;; Check if proposal reached quorum
(define-read-only (check-quorum (proposal-id uint))
    (match (get-proposal proposal-id)
        proposal (>= (get total-votes proposal) (calculate-quorum-threshold))
        false)
)

;; Check if proposal passed
(define-read-only (check-proposal-passed (proposal-id uint))
    (match (get-proposal proposal-id)
        proposal (let
            (
                (total-decisive-votes (+ (get votes-for proposal) (get votes-against proposal)))
                (approval-percentage (if (is-eq total-decisive-votes u0)
                    u0
                    (/ (* (get votes-for proposal) u100) total-decisive-votes)))
            )
            (and
                (>= approval-percentage APPROVAL_THRESHOLD)
                (check-quorum proposal-id))
        )
        false)
)

;; Get proposal status
(define-read-only (get-proposal-status (proposal-id uint))
    (match (get-proposal proposal-id)
        proposal (let
            (
                (current-time stacks-block-time)
                (voting-ended (>= current-time (get voting-ends-at proposal)))
            )
            {
                proposal-id: proposal-id,
                active: (and (not voting-ended) (not (get canceled proposal))),
                voting-ended: voting-ended,
                quorum-reached: (check-quorum proposal-id),
                passed: (check-proposal-passed proposal-id),
                executed: (get executed proposal),
                canceled: (get canceled proposal),
                votes-for: (get votes-for proposal),
                votes-against: (get votes-against proposal),
                votes-abstain: (get votes-abstain proposal),
                total-votes: (get total-votes proposal)
            }
        )
        {
            proposal-id: proposal-id,
            active: false,
            voting-ended: true,
            quorum-reached: false,
            passed: false,
            executed: false,
            canceled: false,
            votes-for: u0,
            votes-against: u0,
            votes-abstain: u0,
            total-votes: u0
        })
)

;; Get user's delegation info
(define-read-only (get-delegation (user principal))
    (map-get? vote-delegation user)
)

;; Get delegations received by a user
(define-read-only (get-delegations-received (delegate principal))
    (default-to
        { total-delegated: u0, delegator-count: u0 }
        (map-get? delegation-received delegate)
    )
)

;; Get user governance statistics
(define-read-only (get-user-governance-stats (user principal))
    (default-to
        { proposals-created: u0, proposals-voted: u0, last-vote-at: u0, participation-score: u0 }
        (map-get? user-governance-stats user)
    )
)

;; Get proposal comment
(define-read-only (get-proposal-comment (proposal-id uint) (comment-id uint))
    (map-get? proposal-comments { proposal-id: proposal-id, comment-id: comment-id })
)

;; ========================================
;; Public Functions - Voting Power Management
;; ========================================

;; Update user's voting power (called by bridge registry or token contracts)
(define-public (update-voting-power (user principal) (base-power uint) (bonus-power uint))
    (let
        (
            (current-power (get-voting-power user))
            (delegated (get delegated-power current-power))
            (new-total (+ base-power bonus-power))
        )
        ;; In production, verify caller is authorized
        (asserts! (> new-total u0) ERR_INSUFFICIENT_VOTING_POWER)

        (map-set user-voting-power user {
            base-power: base-power,
            bonus-power: bonus-power,
            delegated-power: delegated,
            total-power: new-total,
            last-updated: stacks-block-time
        })

        ;; Update total voting power
        (var-set total-voting-power
            (+ (- (var-get total-voting-power) (get total-power current-power)) new-total))

        (print {
            event: "voting-power-updated",
            user: user,
            base-power: base-power,
            bonus-power: bonus-power,
            total-power: new-total,
            total-voting-power: (var-get total-voting-power),
            timestamp: stacks-block-time
        })

        (ok new-total)
    )
)

;; ========================================
;; Public Functions - Delegation
;; ========================================

;; Delegate voting power to another user
(define-public (delegate-votes (delegate principal) (amount uint))
    (let
        (
            (delegator tx-sender)
            (delegator-power (get-voting-power delegator))
            (delegate-power (get-voting-power delegate))
            (existing-delegation (get-delegation delegator))
            (delegations-rcvd (get-delegations-received delegate))
        )
        (asserts! (not (is-eq delegator delegate)) ERR_INVALID_DELEGATION)
        (asserts! (<= amount (get total-power delegator-power)) ERR_INSUFFICIENT_VOTING_POWER)
        (asserts! (> amount u0) ERR_INVALID_DELEGATION)

        ;; If already delegating, revert previous delegation
        (match existing-delegation
            prev-del (if (get active prev-del)
                (let
                    (
                        (prev-delegate (get delegate prev-del))
                        (prev-del-power (get-voting-power prev-delegate))
                    )
                    ;; Remove from previous delegate
                    (map-set user-voting-power prev-delegate
                        (merge prev-del-power {
                            delegated-power: (- (get delegated-power prev-del-power) (get delegated-amount prev-del))
                        }))
                )
                true)
            true)

        ;; Create/update delegation
        (map-set vote-delegation delegator {
            delegate: delegate,
            delegated-amount: amount,
            delegated-at: stacks-block-time,
            active: true
        })

        ;; Update delegate's received power
        (map-set user-voting-power delegate
            (merge delegate-power {
                delegated-power: (+ (get delegated-power delegate-power) amount),
                total-power: (+ (get total-power delegate-power) amount)
            }))

        ;; Update delegation received tracking
        (map-set delegation-received delegate {
            total-delegated: (+ (get total-delegated delegations-rcvd) amount),
            delegator-count: (+ (get delegator-count delegations-rcvd) u1)
        })

        (print {
            event: "votes-delegated",
            delegator: delegator,
            delegate: delegate,
            amount: amount,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Revoke vote delegation
(define-public (revoke-delegation)
    (let
        (
            (delegator tx-sender)
            (delegation (unwrap! (get-delegation delegator) ERR_INVALID_DELEGATION))
            (delegate (get delegate delegation))
            (amount (get delegated-amount delegation))
            (delegate-power (get-voting-power delegate))
            (delegations-rcvd (get-delegations-received delegate))
        )
        (asserts! (get active delegation) ERR_INVALID_DELEGATION)

        ;; Mark delegation as inactive
        (map-set vote-delegation delegator
            (merge delegation { active: false }))

        ;; Remove from delegate's power
        (map-set user-voting-power delegate
            (merge delegate-power {
                delegated-power: (- (get delegated-power delegate-power) amount),
                total-power: (- (get total-power delegate-power) amount)
            }))

        ;; Update delegation received tracking
        (map-set delegation-received delegate {
            total-delegated: (- (get total-delegated delegations-rcvd) amount),
            delegator-count: (- (get delegator-count delegations-rcvd) u1)
        })

        (print {
            event: "delegation-revoked",
            delegator: delegator,
            delegate: delegate,
            amount: amount,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; ========================================
;; Public Functions - Proposal Management
;; ========================================

;; Create a new governance proposal
(define-public (create-proposal
    (proposal-type uint)
    (title (string-ascii 128))
    (description (string-utf8 512))
    (target-bridge-id uint)
    (proposed-value uint))
    (let
        (
            (proposer tx-sender)
            (proposal-id (+ (var-get proposal-counter) u1))
            (proposer-power (get-voting-power proposer))
            (deposit (var-get min-proposal-deposit))
            (current-time stacks-block-time)
            (voting-ends-at (+ current-time VOTING_PERIOD_BLOCKS))
            (user-stats (get-user-governance-stats proposer))
        )
        ;; Validate proposer has voting power
        (asserts! (> (get total-power proposer-power) u0) ERR_INSUFFICIENT_VOTING_POWER)

        ;; Validate proposal type
        (asserts! (and (>= proposal-type PROPOSAL_TYPE_FEE_CHANGE)
                      (<= proposal-type PROPOSAL_TYPE_GENERAL)) ERR_INVALID_PROPOSAL)

        ;; Transfer deposit (deposits held in contract)
        ;; Note: In production, implement proper escrow mechanism
        (asserts! (>= (stx-get-balance proposer) deposit) ERR_INVALID_PROPOSAL)

        ;; Create proposal
        (map-set proposals proposal-id {
            proposer: proposer,
            proposal-type: proposal-type,
            title: title,
            description: description,
            target-bridge-id: target-bridge-id,
            proposed-value: proposed-value,
            created-at: current-time,
            voting-ends-at: voting-ends-at,
            executed-at: u0,
            executed: false,
            canceled: false,
            deposit: deposit,
            votes-for: u0,
            votes-against: u0,
            votes-abstain: u0,
            total-votes: u0,
            quorum-reached: false,
            passed: false
        })

        ;; Update proposal counter
        (var-set proposal-counter proposal-id)

        ;; Update user stats
        (map-set user-governance-stats proposer
            (merge user-stats {
                proposals-created: (+ (get proposals-created user-stats) u1),
                participation-score: (+ (get participation-score user-stats) u10)
            }))

        (print {
            event: "proposal-created",
            proposal-id: proposal-id,
            proposer: proposer,
            proposal-type: proposal-type,
            title: title,
            target-bridge-id: target-bridge-id,
            proposed-value: proposed-value,
            voting-ends-at: voting-ends-at,
            deposit: deposit,
            timestamp: current-time
        })

        (ok proposal-id)
    )
)

;; Cast vote on a proposal
(define-public (vote (proposal-id uint) (vote-type (string-ascii 8)))
    (let
        (
            (voter tx-sender)
            (proposal (unwrap! (get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (effective-power (get-effective-voting-power voter))
            (voting-power (get total-effective-power effective-power))
            (current-time stacks-block-time)
            (user-stats (get-user-governance-stats voter))
        )
        ;; Validate voting is still open
        (asserts! (< current-time (get voting-ends-at proposal)) ERR_VOTING_ENDED)
        (asserts! (not (get canceled proposal)) ERR_PROPOSAL_NOT_FOUND)

        ;; Validate voter hasn't voted yet
        (asserts! (not (has-voted proposal-id voter)) ERR_ALREADY_VOTED)

        ;; Validate voting power
        (asserts! (> voting-power u0) ERR_INSUFFICIENT_VOTING_POWER)

        ;; Validate vote type
        (asserts! (or (is-eq vote-type "for")
                     (or (is-eq vote-type "against") (is-eq vote-type "abstain")))
                 ERR_INVALID_PROPOSAL)

        ;; Record vote
        (map-set proposal-votes
            { proposal-id: proposal-id, voter: voter }
            {
                vote-type: vote-type,
                voting-power: voting-power,
                voted-at: current-time,
                delegated-from: none
            }
        )

        ;; Update proposal vote counts
        (map-set proposals proposal-id
            (merge proposal {
                votes-for: (if (is-eq vote-type "for")
                    (+ (get votes-for proposal) voting-power)
                    (get votes-for proposal)),
                votes-against: (if (is-eq vote-type "against")
                    (+ (get votes-against proposal) voting-power)
                    (get votes-against proposal)),
                votes-abstain: (if (is-eq vote-type "abstain")
                    (+ (get votes-abstain proposal) voting-power)
                    (get votes-abstain proposal)),
                total-votes: (+ (get total-votes proposal) voting-power)
            })
        )

        ;; Update user stats
        (map-set user-governance-stats voter
            (merge user-stats {
                proposals-voted: (+ (get proposals-voted user-stats) u1),
                last-vote-at: current-time,
                participation-score: (+ (get participation-score user-stats) u5)
            }))

        (print {
            event: "vote-cast",
            proposal-id: proposal-id,
            voter: voter,
            vote-type: vote-type,
            voting-power: voting-power,
            new-votes-for: (if (is-eq vote-type "for")
                (+ (get votes-for proposal) voting-power)
                (get votes-for proposal)),
            new-votes-against: (if (is-eq vote-type "against")
                (+ (get votes-against proposal) voting-power)
                (get votes-against proposal)),
            new-total-votes: (+ (get total-votes proposal) voting-power),
            timestamp: current-time
        })

        (ok true)
    )
)

;; Queue proposal for execution after voting ends
(define-public (queue-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (current-time stacks-block-time)
            (delay (var-get proposal-execution-delay))
        )
        ;; Validate voting has ended
        (asserts! (>= current-time (get voting-ends-at proposal)) ERR_VOTING_NOT_ENDED)

        ;; Validate proposal passed
        (asserts! (check-proposal-passed proposal-id) ERR_PROPOSAL_NOT_PASSED)

        ;; Validate not already executed
        (asserts! (not (get executed proposal)) ERR_PROPOSAL_EXECUTED)

        ;; Add to execution queue
        (map-set execution-queue proposal-id {
            queued-at: current-time,
            executable-at: (+ current-time delay),
            executed: false
        })

        ;; Update proposal
        (map-set proposals proposal-id
            (merge proposal {
                quorum-reached: true,
                passed: true
            }))

        (print {
            event: "proposal-queued",
            proposal-id: proposal-id,
            queued-at: current-time,
            executable-at: (+ current-time delay),
            votes-for: (get votes-for proposal),
            votes-against: (get votes-against proposal),
            total-votes: (get total-votes proposal),
            timestamp: current-time
        })

        (ok true)
    )
)

;; Execute a passed proposal (simplified - would integrate with bridge-registry)
(define-public (execute-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (queue-entry (unwrap! (map-get? execution-queue proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (current-time stacks-block-time)
        )
        ;; Validate execution time has passed
        (asserts! (>= current-time (get executable-at queue-entry)) ERR_VOTING_NOT_ENDED)

        ;; Validate not already executed
        (asserts! (not (get executed proposal)) ERR_PROPOSAL_EXECUTED)
        (asserts! (not (get executed queue-entry)) ERR_PROPOSAL_EXECUTED)

        ;; Mark as executed
        (map-set proposals proposal-id
            (merge proposal {
                executed: true,
                executed-at: current-time
            }))

        (map-set execution-queue proposal-id
            (merge queue-entry { executed: true }))

        ;; Note: Deposit return would be handled by contract treasury in production
        ;; For now, we skip the transfer as deposits are conceptual

        (print {
            event: "proposal-executed",
            proposal-id: proposal-id,
            proposal-type: (get proposal-type proposal),
            target-bridge-id: (get target-bridge-id proposal),
            proposed-value: (get proposed-value proposal),
            executed-at: current-time,
            timestamp: current-time
        })

        (ok true)
    )
)

;; Cancel a proposal (only by proposer before voting ends)
(define-public (cancel-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (current-time stacks-block-time)
        )
        (asserts! (is-eq tx-sender (get proposer proposal)) ERR_NOT_AUTHORIZED)
        (asserts! (< current-time (get voting-ends-at proposal)) ERR_VOTING_ENDED)
        (asserts! (not (get executed proposal)) ERR_PROPOSAL_EXECUTED)
        (asserts! (not (get canceled proposal)) ERR_PROPOSAL_NOT_FOUND)

        ;; Mark as canceled
        (map-set proposals proposal-id
            (merge proposal { canceled: true }))

        ;; Note: Partial deposit refund would be handled by contract treasury in production

        (print {
            event: "proposal-canceled",
            proposal-id: proposal-id,
            proposer: (get proposer proposal),
            timestamp: current-time
        })

        (ok true)
    )
)

;; Add comment to proposal
(define-public (add-proposal-comment (proposal-id uint) (comment (string-utf8 256)))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
            (comment-id (+ (var-get comment-counter) u1))
            (author tx-sender)
            (current-time stacks-block-time)
        )
        (asserts! (not (get canceled proposal)) ERR_PROPOSAL_NOT_FOUND)

        (map-set proposal-comments
            { proposal-id: proposal-id, comment-id: comment-id }
            {
                author: author,
                comment: comment,
                created-at: current-time
            }
        )

        (var-set comment-counter comment-id)

        (print {
            event: "proposal-comment-added",
            proposal-id: proposal-id,
            comment-id: comment-id,
            author: author,
            timestamp: current-time
        })

        (ok comment-id)
    )
)

;; ========================================
;; Admin Functions
;; ========================================

;; Update governance parameters
(define-public (update-governance-params (min-deposit uint) (execution-delay uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> min-deposit u0) ERR_INVALID_PROPOSAL)
        (asserts! (> execution-delay u0) ERR_INVALID_PROPOSAL)

        (var-set min-proposal-deposit min-deposit)
        (var-set proposal-execution-delay execution-delay)

        (print {
            event: "governance-params-updated",
            min-deposit: min-deposit,
            execution-delay: execution-delay,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)
