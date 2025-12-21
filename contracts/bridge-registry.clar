;; bridge-registry.clar
;; Registry of verified bridge contracts and supported chains
;; Uses Clarity 4 features: contract-hash?, to-ascii?, stacks-block-time

;; ========================================
;; Constants
;; ========================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u10001))
(define-constant ERR_BRIDGE_NOT_FOUND (err u10002))
(define-constant ERR_BRIDGE_EXISTS (err u10003))
(define-constant ERR_INVALID_CHAIN (err u10004))
(define-constant ERR_INVALID_PERFORMANCE (err u10005))
(define-constant ERR_INSUFFICIENT_POINTS (err u10006))
(define-constant ERR_INVALID_REDEMPTION (err u10007))
(define-constant ERR_POOL_NOT_FOUND (err u10008))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u10009))
(define-constant ERR_POOL_EXISTS (err u10010))
(define-constant ERR_INVALID_DEPOSIT (err u10011))
(define-constant ERR_INSURANCE_NOT_FOUND (err u10012))
(define-constant ERR_INSURANCE_EXISTS (err u10013))
(define-constant ERR_INVALID_COVERAGE (err u10014))
(define-constant ERR_CLAIM_NOT_FOUND (err u10015))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u10016))
(define-constant ERR_INSUFFICIENT_POOL (err u10017))

;; Chain identifiers
(define-constant CHAIN_STACKS u1)
(define-constant CHAIN_BITCOIN u2)
(define-constant CHAIN_ETHEREUM u3)
(define-constant CHAIN_POLYGON u4)
(define-constant CHAIN_ARBITRUM u5)
(define-constant CHAIN_OPTIMISM u6)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var bridge-counter uint u0)
(define-data-var total-verified uint u0)

;; ========================================
;; Data Maps
;; ========================================

;; Bridge registry by ID
(define-map bridges
    uint
    {
        contract: principal,
        name: (string-ascii 64),
        contract-hash: (buff 32),
        source-chain: uint,
        dest-chains: (list 10 uint),
        fee-bps: uint,
        verified-at: uint,
        verified-by: principal,
        active: bool,
        total-volume: uint
    }
)

;; Lookup by contract address
(define-map bridge-by-contract
    principal
    uint
)

;; Chain names for readable output
(define-map chain-names
    uint
    (string-ascii 32)
)

;; Route availability (source -> dest -> bridge-id)
(define-map routes
    { source: uint, dest: uint }
    (list 5 uint)
)

;; Bridge performance tracking
(define-map bridge-performance
    uint
    {
        total-transactions: uint,
        successful-transactions: uint,
        failed-transactions: uint,
        total-processing-time: uint,
        last-updated: uint
    }
)

;; Individual transaction records for detailed tracking
(define-map transaction-records
    { bridge-id: uint, tx-index: uint }
    {
        success: bool,
        processing-time: uint,
        recorded-at: uint
    }
)

(define-data-var transaction-counter uint u0)

;; Reward system configuration
(define-data-var reward-points-per-transaction uint u10)
(define-data-var points-to-discount-rate uint u100) ;; 100 points = 1 bps discount
(define-data-var max-discount-bps uint u500) ;; Max 5% discount
(define-data-var redemption-counter uint u0)

;; ========================================
;; Reward System Maps
;; ========================================

;; User reward points balance
(define-map user-reward-points principal uint)

;; Points redemption history
(define-map points-redemption-history
    { user: principal, redemption-id: uint }
    {
        points-used: uint,
        discount-earned: uint,
        redeemed-at: uint,
        bridge-id: uint
    }
)

;; Track total points earned per user
(define-map user-points-earned principal uint)

;; Track total points redeemed per user
(define-map user-points-redeemed principal uint)

;; ========================================
;; Liquidity Pool System
;; ========================================

(define-data-var pool-counter uint u0)
(define-data-var contract-principal principal tx-sender)
(define-data-var total-pool-liquidity uint u0)

;; Liquidity pools for specific bridge routes
(define-map liquidity-pools
    { bridge-id: uint }
    {
        total-liquidity: uint,
        total-shares: uint,
        fee-bps: uint,
        total-fees-collected: uint,
        created-at: uint,
        active: bool
    }
)

;; User liquidity positions
(define-map user-liquidity-positions
    { user: principal, bridge-id: uint }
    {
        shares: uint,
        deposited-amount: uint,
        fees-earned: uint,
        deposited-at: uint,
        last-claim-at: uint
    }
)

;; Track liquidity events
(define-map liquidity-events
    { pool-id: uint, event-id: uint }
    {
        event-type: (string-ascii 32),
        user: principal,
        amount: uint,
        shares: uint,
        timestamp: uint
    }
)

(define-data-var liquidity-event-counter uint u0)

;; ========================================
;; Bridge Insurance System
;; ========================================

(define-data-var insurance-counter uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var claim-counter uint u0)
(define-data-var base-premium-bps uint u50) ;; 0.5% base premium
(define-data-var coverage-to-premium-ratio uint u100) ;; 100:1 ratio

;; Insurance policies for bridge transactions
(define-map insurance-policies
    { user: principal, policy-id: uint }
    {
        bridge-id: uint,
        coverage-amount: uint,
        premium-paid: uint,
        purchased-at: uint,
        expires-at: uint,
        active: bool,
        claimed: bool
    }
)

;; User's active policies by bridge
(define-map user-active-policies
    { user: principal, bridge-id: uint }
    (list 10 uint)
)

;; Insurance claims
(define-map insurance-claims
    uint
    {
        policy-id: uint,
        user: principal,
        bridge-id: uint,
        claim-amount: uint,
        filed-at: uint,
        processed-at: uint,
        approved: bool,
        processed: bool,
        payout-amount: uint
    }
)

;; Bridge risk ratings (affects premiums)
(define-map bridge-risk-ratings
    uint
    {
        risk-score: uint, ;; 0-100, higher = riskier
        total-claims: uint,
        total-payouts: uint,
        last-updated: uint
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

;; Get bridge by ID
(define-read-only (get-bridge (bridge-id uint))
    (map-get? bridges bridge-id)
)

;; Get bridge by contract address
(define-read-only (get-bridge-by-contract (bridge-contract principal))
    (match (map-get? bridge-by-contract bridge-contract)
        bridge-id (map-get? bridges bridge-id)
        none
    )
)

;; Verify bridge contract hash matches stored hash
(define-read-only (verify-bridge-integrity (bridge-contract principal))
    (match (map-get? bridge-by-contract bridge-contract)
        bridge-id (match (map-get? bridges bridge-id)
            bridge (match (contract-hash? bridge-contract)
                current-hash (is-eq current-hash (get contract-hash bridge))
                hash-err false
            )
            false
        )
        false
    )
)

;; Get available routes for a chain pair
(define-read-only (get-routes (source-chain uint) (dest-chain uint))
    (default-to (list) (map-get? routes { source: source-chain, dest: dest-chain }))
)

;; Get chain name
(define-read-only (get-chain-name (chain-identifier uint))
    (default-to "Unknown" (map-get? chain-names chain-identifier))
)

;; Generate bridge info message using to-ascii?
(define-read-only (get-bridge-info-message (bridge-id uint))
    (match (map-get? bridges bridge-id)
        bridge (let
            (
                (id-str (unwrap-panic (to-ascii? bridge-id)))
                (volume-str (unwrap-panic (to-ascii? (get total-volume bridge))))
                (fee-str (unwrap-panic (to-ascii? (get fee-bps bridge))))
            )
            (concat 
                (concat (concat "Bridge #" id-str) (concat ": " (get name bridge)))
                (concat (concat " | Volume: " volume-str) (concat " | Fee: " (concat fee-str "bps")))
            )
        )
        "Bridge not found"
    )
)

;; Get route description
(define-read-only (describe-route (source-chain uint) (dest-chain uint))
    (let
        (
            (source-name (get-chain-name source-chain))
            (dest-name (get-chain-name dest-chain))
        )
        (concat (concat source-name " -> ") dest-name)
    )
)

;; Get registry stats
(define-read-only (get-registry-stats)
    {
        total-bridges: (var-get bridge-counter),
        total-verified: (var-get total-verified),
        current-time: stacks-block-time
    }
)

;; Get bridge performance metrics
(define-read-only (get-bridge-performance (bridge-id uint))
    (default-to
        { total-transactions: u0, successful-transactions: u0, failed-transactions: u0, total-processing-time: u0, last-updated: u0 }
        (map-get? bridge-performance bridge-id)
    )
)

;; Calculate success rate (in basis points, 10000 = 100%)
(define-read-only (get-success-rate (bridge-id uint))
    (let
        (
            (perf (get-bridge-performance bridge-id))
            (total (get total-transactions perf))
        )
        (if (is-eq total u0)
            u0
            (/ (* (get successful-transactions perf) u10000) total)
        )
    )
)

;; Calculate average processing time
(define-read-only (get-average-processing-time (bridge-id uint))
    (let
        (
            (perf (get-bridge-performance bridge-id))
            (total (get total-transactions perf))
        )
        (if (is-eq total u0)
            u0
            (/ (get total-processing-time perf) total)
        )
    )
)

;; Get bridge reliability score (0-100)
(define-read-only (get-reliability-score (bridge-id uint))
    (let
        (
            (success-rate (get-success-rate bridge-id))
            (perf (get-bridge-performance bridge-id))
        )
        ;; Score based on success rate, higher if more transactions
        (if (< (get total-transactions perf) u10)
            u0  ;; Not enough data
            (/ success-rate u100)  ;; Convert from bps to percentage
        )
    )
)

;; ========================================
;; Reward System Read-Only Functions
;; ========================================

;; Get user's current reward points balance
(define-read-only (get-user-points (user principal))
    (default-to u0 (map-get? user-reward-points user))
)

;; Get total points earned by user
(define-read-only (get-user-points-earned (user principal))
    (default-to u0 (map-get? user-points-earned user))
)

;; Get total points redeemed by user
(define-read-only (get-user-points-redeemed (user principal))
    (default-to u0 (map-get? user-points-redeemed user))
)

;; Calculate discount available for given points
(define-read-only (calculate-discount (points uint))
    (let
        (
            (rate (var-get points-to-discount-rate))
            (max-discount (var-get max-discount-bps))
            (calculated-discount (/ points rate))
        )
        (if (> calculated-discount max-discount)
            max-discount
            calculated-discount
        )
    )
)

;; Get redemption history entry
(define-read-only (get-redemption-history (user principal) (redemption-id uint))
    (map-get? points-redemption-history { user: user, redemption-id: redemption-id })
)

;; Get user's reward statistics
(define-read-only (get-user-reward-stats (user principal))
    {
        current-balance: (get-user-points user),
        total-earned: (get-user-points-earned user),
        total-redeemed: (get-user-points-redeemed user),
        available-discount-bps: (calculate-discount (get-user-points user))
    }
)

;; ========================================
;; Liquidity Pool Read-Only Functions
;; ========================================

;; Get liquidity pool info
(define-read-only (get-liquidity-pool (bridge-id uint))
    (map-get? liquidity-pools { bridge-id: bridge-id })
)

;; Get user's liquidity position
(define-read-only (get-user-position (user principal) (bridge-id uint))
    (map-get? user-liquidity-positions { user: user, bridge-id: bridge-id })
)

;; Calculate user's share of pool (in basis points)
(define-read-only (calculate-user-pool-share (user principal) (bridge-id uint))
    (match (get-liquidity-pool bridge-id)
        pool (match (get-user-position user bridge-id)
            position (if (is-eq (get total-shares pool) u0)
                u0
                (/ (* (get shares position) u10000) (get total-shares pool)))
            u0)
        u0)
)

;; Calculate claimable fees for user
(define-read-only (calculate-claimable-fees (user principal) (bridge-id uint))
    (match (get-liquidity-pool bridge-id)
        pool (match (get-user-position user bridge-id)
            position (let
                (
                    (user-share-bps (calculate-user-pool-share user bridge-id))
                    (total-fees (get total-fees-collected pool))
                    (already-earned (get fees-earned position))
                )
                (if (is-eq user-share-bps u0)
                    u0
                    (- (/ (* total-fees user-share-bps) u10000) already-earned)))
            u0)
        u0)
)

;; Get pool statistics
(define-read-only (get-pool-stats (bridge-id uint))
    (match (get-liquidity-pool bridge-id)
        pool {
            total-liquidity: (get total-liquidity pool),
            total-shares: (get total-shares pool),
            fee-bps: (get fee-bps pool),
            total-fees-collected: (get total-fees-collected pool),
            active: (get active pool),
            apr-estimate: u0  ;; Would calculate based on fee history
        }
        {
            total-liquidity: u0,
            total-shares: u0,
            fee-bps: u0,
            total-fees-collected: u0,
            active: false,
            apr-estimate: u0
        })
)

;; Get user's full liquidity info
(define-read-only (get-user-liquidity-info (user principal) (bridge-id uint))
    (match (get-user-position user bridge-id)
        position {
            shares: (get shares position),
            deposited-amount: (get deposited-amount position),
            fees-earned: (get fees-earned position),
            claimable-fees: (calculate-claimable-fees user bridge-id),
            pool-share-bps: (calculate-user-pool-share user bridge-id),
            deposited-at: (get deposited-at position),
            last-claim-at: (get last-claim-at position)
        }
        {
            shares: u0,
            deposited-amount: u0,
            fees-earned: u0,
            claimable-fees: u0,
            pool-share-bps: u0,
            deposited-at: u0,
            last-claim-at: u0
        })
)

;; ========================================
;; Insurance Read-Only Functions
;; ========================================

;; Get insurance policy
(define-read-only (get-insurance-policy (user principal) (policy-id uint))
    (map-get? insurance-policies { user: user, policy-id: policy-id })
)

;; Get user's active policies for a bridge
(define-read-only (get-user-active-policies (user principal) (bridge-id uint))
    (default-to (list) (map-get? user-active-policies { user: user, bridge-id: bridge-id }))
)

;; Get insurance claim
(define-read-only (get-insurance-claim (claim-id uint))
    (map-get? insurance-claims claim-id)
)

;; Get bridge risk rating
(define-read-only (get-bridge-risk-rating (bridge-id uint))
    (default-to
        { risk-score: u50, total-claims: u0, total-payouts: u0, last-updated: u0 }
        (map-get? bridge-risk-ratings bridge-id)
    )
)

;; Calculate premium for coverage amount
(define-read-only (calculate-premium (bridge-id uint) (coverage-amount uint))
    (let
        (
            (base-premium (var-get base-premium-bps))
            (risk-rating (get-bridge-risk-rating bridge-id))
            (risk-score (get risk-score risk-rating))
            ;; Base premium + risk adjustment (risk-score / 100 adds 0-100% to base)
            (risk-adjusted-premium (+ base-premium (/ (* base-premium risk-score) u100)))
        )
        ;; Calculate premium as percentage of coverage
        (/ (* coverage-amount risk-adjusted-premium) u10000)
    )
)

;; Get insurance pool stats
(define-read-only (get-insurance-pool-stats)
    {
        pool-balance: (var-get insurance-pool-balance),
        total-policies: (var-get insurance-counter),
        total-claims: (var-get claim-counter),
        base-premium-bps: (var-get base-premium-bps)
    }
)

;; Check if user has active coverage for bridge
(define-read-only (has-active-coverage (user principal) (bridge-id uint))
    (let
        (
            (active-policies (get-user-active-policies user bridge-id))
            (current-time stacks-block-time)
        )
        (> (len active-policies) u0)
    )
)

;; ========================================
;; Admin Functions
;; ========================================

;; Initialize chain names
(define-public (initialize-chains)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set chain-names CHAIN_STACKS "Stacks")
        (map-set chain-names CHAIN_BITCOIN "Bitcoin")
        (map-set chain-names CHAIN_ETHEREUM "Ethereum")
        (map-set chain-names CHAIN_POLYGON "Polygon")
        (map-set chain-names CHAIN_ARBITRUM "Arbitrum")
        (map-set chain-names CHAIN_OPTIMISM "Optimism")
        
        (ok true)
    )
)

;; Register and verify a bridge
(define-public (register-bridge
    (bridge-contract principal)
    (name (string-ascii 64))
    (source-chain uint)
    (dest-chains (list 10 uint))
    (fee-bps uint))
    (let
        (
            (bridge-id (+ (var-get bridge-counter) u1))
            (current-time stacks-block-time)
            (bridge-hash (unwrap! (contract-hash? bridge-contract) ERR_BRIDGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (map-get? bridge-by-contract bridge-contract)) ERR_BRIDGE_EXISTS)
        
        ;; Register bridge
        (map-set bridges bridge-id {
            contract: bridge-contract,
            name: name,
            contract-hash: bridge-hash,
            source-chain: source-chain,
            dest-chains: dest-chains,
            fee-bps: fee-bps,
            verified-at: current-time,
            verified-by: tx-sender,
            active: true,
            total-volume: u0
        })
        
        ;; Add contract lookup
        (map-set bridge-by-contract bridge-contract bridge-id)
        
        ;; Update counters
        (var-set bridge-counter bridge-id)
        (var-set total-verified (+ (var-get total-verified) u1))
        
        ;; Print info
        (print (get-bridge-info-message bridge-id))
        
        (ok bridge-id)
    )
)

;; Add route for chain pair
(define-public (add-route (source-chain uint) (dest-chain uint) (bridge-id uint))
    (let
        (
            (existing-routes (get-routes source-chain dest-chain))
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (get active bridge) ERR_BRIDGE_NOT_FOUND)
        
        ;; Add bridge to routes (if not already present and list not full)
        (map-set routes { source: source-chain, dest: dest-chain }
            (unwrap! (as-max-len? (append existing-routes bridge-id) u5) ERR_INVALID_CHAIN)
        )
        
        (ok true)
    )
)

;; Update bridge status
(define-public (set-bridge-active (bridge-id uint) (active bool))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set bridges bridge-id (merge bridge { active: active }))
        
        (if active
            (var-set total-verified (+ (var-get total-verified) u1))
            (var-set total-verified (- (var-get total-verified) u1))
        )
        
        (ok true)
    )
)

;; Update bridge fee
(define-public (set-bridge-fee (bridge-id uint) (new-fee-bps uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set bridges bridge-id (merge bridge { fee-bps: new-fee-bps }))
        
        (ok true)
    )
)

;; Record volume (called by intent bridge)
(define-public (record-volume (bridge-id uint) (amount uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
        )
        ;; In production, would verify caller is authorized
        
        (map-set bridges bridge-id (merge bridge {
            total-volume: (+ (get total-volume bridge) amount)
        }))
        
        (ok true)
    )
)

;; Re-verify bridge (check hash still matches)
(define-public (reverify-bridge (bridge-id uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (current-hash (unwrap! (contract-hash? (get contract bridge)) ERR_BRIDGE_NOT_FOUND))
        )
        (if (is-eq current-hash (get contract-hash bridge))
            (ok true)
            (begin
                ;; Hash changed - deactivate bridge
                (map-set bridges bridge-id (merge bridge { active: false }))
                (var-set total-verified (- (var-get total-verified) u1))
                ERR_NOT_AUTHORIZED
            )
        )
    )
)

;; ========================================
;; Performance Tracking Functions
;; ========================================

;; Record transaction outcome
(define-public (record-transaction-outcome (bridge-id uint) (success bool) (processing-time uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (perf (get-bridge-performance bridge-id))
            (tx-index (var-get transaction-counter))
            (current-time stacks-block-time)
        )
        ;; Verify bridge exists and is active
        (asserts! (get active bridge) ERR_BRIDGE_NOT_FOUND)
        (asserts! (> processing-time u0) ERR_INVALID_PERFORMANCE)

        ;; Record individual transaction
        (map-set transaction-records
            { bridge-id: bridge-id, tx-index: tx-index }
            {
                success: success,
                processing-time: processing-time,
                recorded-at: current-time
            }
        )

        ;; Update performance metrics
        (map-set bridge-performance bridge-id {
            total-transactions: (+ (get total-transactions perf) u1),
            successful-transactions: (if success (+ (get successful-transactions perf) u1) (get successful-transactions perf)),
            failed-transactions: (if success (get failed-transactions perf) (+ (get failed-transactions perf) u1)),
            total-processing-time: (+ (get total-processing-time perf) processing-time),
            last-updated: current-time
        })

        (var-set transaction-counter (+ tx-index u1))

        ;; Emit event for Chainhook
        (print {
            event: "transaction-outcome-recorded",
            bridge-id: bridge-id,
            tx-index: tx-index,
            success: success,
            processing-time: processing-time,
            success-rate: (get-success-rate bridge-id),
            avg-processing-time: (get-average-processing-time bridge-id),
            reliability-score: (get-reliability-score bridge-id),
            timestamp: current-time
        })

        (ok tx-index)
    )
)

;; Reset bridge performance metrics (admin only)
(define-public (reset-bridge-performance (bridge-id uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)

        (map-set bridge-performance bridge-id {
            total-transactions: u0,
            successful-transactions: u0,
            failed-transactions: u0,
            total-processing-time: u0,
            last-updated: stacks-block-time
        })

        (print {
            event: "bridge-performance-reset",
            bridge-id: bridge-id,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; ========================================
;; Reward System Public Functions
;; ========================================

;; Award points to user for successful bridge transaction
(define-public (award-reward-points (user principal) (bridge-id uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (current-balance (get-user-points user))
            (total-earned (get-user-points-earned user))
            (points-per-tx (var-get reward-points-per-transaction))
            (reliability (get-reliability-score bridge-id))
        )
        ;; Verify bridge exists and is active
        (asserts! (get active bridge) ERR_BRIDGE_NOT_FOUND)

        ;; Only award points for bridges with good reliability (>= 80%)
        (asserts! (>= reliability u80) ERR_INVALID_PERFORMANCE)

        ;; Update user's points balance
        (map-set user-reward-points user (+ current-balance points-per-tx))

        ;; Update total earned tracking
        (map-set user-points-earned user (+ total-earned points-per-tx))

        ;; Emit event for Chainhook
        (print {
            event: "reward-points-awarded",
            user: user,
            bridge-id: bridge-id,
            points-awarded: points-per-tx,
            new-balance: (+ current-balance points-per-tx),
            total-earned: (+ total-earned points-per-tx),
            timestamp: stacks-block-time
        })

        (ok points-per-tx)
    )
)

;; Redeem points for fee discount
(define-public (redeem-points-for-discount (points uint) (bridge-id uint))
    (let
        (
            (user tx-sender)
            (current-balance (get-user-points user))
            (total-redeemed (get-user-points-redeemed user))
            (discount-bps (calculate-discount points))
            (redemption-id (var-get redemption-counter))
        )
        ;; Verify user has sufficient points
        (asserts! (>= current-balance points) ERR_INSUFFICIENT_POINTS)

        ;; Verify points amount is valid (must be positive and result in discount)
        (asserts! (and (> points u0) (> discount-bps u0)) ERR_INVALID_REDEMPTION)

        ;; Update user's points balance
        (map-set user-reward-points user (- current-balance points))

        ;; Update total redeemed tracking
        (map-set user-points-redeemed user (+ total-redeemed points))

        ;; Record redemption in history
        (map-set points-redemption-history
            { user: user, redemption-id: redemption-id }
            {
                points-used: points,
                discount-earned: discount-bps,
                redeemed-at: stacks-block-time,
                bridge-id: bridge-id
            }
        )

        ;; Increment redemption counter
        (var-set redemption-counter (+ redemption-id u1))

        ;; Emit event for Chainhook
        (print {
            event: "reward-points-redeemed",
            user: user,
            redemption-id: redemption-id,
            points-redeemed: points,
            discount-earned-bps: discount-bps,
            new-balance: (- current-balance points),
            total-redeemed: (+ total-redeemed points),
            bridge-id: bridge-id,
            timestamp: stacks-block-time
        })

        (ok { redemption-id: redemption-id, discount-bps: discount-bps })
    )
)

;; Admin: Update reward configuration
(define-public (set-reward-config (points-per-tx uint) (points-to-discount uint) (max-discount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> points-per-tx u0) ERR_INVALID_PERFORMANCE)
        (asserts! (> points-to-discount u0) ERR_INVALID_PERFORMANCE)
        (asserts! (<= max-discount u10000) ERR_INVALID_PERFORMANCE)

        (var-set reward-points-per-transaction points-per-tx)
        (var-set points-to-discount-rate points-to-discount)
        (var-set max-discount-bps max-discount)

        (print {
            event: "reward-config-updated",
            points-per-tx: points-per-tx,
            points-to-discount: points-to-discount,
            max-discount: max-discount,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; ========================================
;; Liquidity Pool Public Functions
;; ========================================

;; Create liquidity pool for a bridge
(define-public (create-liquidity-pool (bridge-id uint) (fee-bps uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (pool-id (+ (var-get pool-counter) u1))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (get-liquidity-pool bridge-id)) ERR_POOL_EXISTS)
        (asserts! (get active bridge) ERR_BRIDGE_NOT_FOUND)
        (asserts! (<= fee-bps u10000) ERR_INVALID_DEPOSIT)

        (map-set liquidity-pools
            { bridge-id: bridge-id }
            {
                total-liquidity: u0,
                total-shares: u0,
                fee-bps: fee-bps,
                total-fees-collected: u0,
                created-at: stacks-block-time,
                active: true
            }
        )

        (var-set pool-counter pool-id)

        (print {
            event: "liquidity-pool-created",
            bridge-id: bridge-id,
            pool-id: pool-id,
            fee-bps: fee-bps,
            timestamp: stacks-block-time
        })

        (ok pool-id)
    )
)

;; Deposit liquidity into a pool
(define-public (deposit-liquidity (bridge-id uint) (amount uint))
    (let
        (
            (pool (unwrap! (get-liquidity-pool bridge-id) ERR_POOL_NOT_FOUND))
            (user tx-sender)
            (existing-position (get-user-position user bridge-id))
            (current-time stacks-block-time)
            (event-id (var-get liquidity-event-counter))
            (shares-to-mint (if (is-eq (get total-shares pool) u0)
                amount  ;; First deposit: 1:1 shares
                (/ (* amount (get total-shares pool)) (get total-liquidity pool))))
        )
        (asserts! (get active pool) ERR_POOL_NOT_FOUND)
        (asserts! (> amount u0) ERR_INVALID_DEPOSIT)

        ;; Transfer STX to contract
        (unwrap! (stx-transfer? amount tx-sender (var-get contract-principal)) ERR_INVALID_DEPOSIT)

        ;; Update pool
        (map-set liquidity-pools
            { bridge-id: bridge-id }
            (merge pool {
                total-liquidity: (+ (get total-liquidity pool) amount),
                total-shares: (+ (get total-shares pool) shares-to-mint)
            })
        )

        ;; Update or create user position
        (match existing-position
            position (map-set user-liquidity-positions
                { user: user, bridge-id: bridge-id }
                (merge position {
                    shares: (+ (get shares position) shares-to-mint),
                    deposited-amount: (+ (get deposited-amount position) amount)
                }))
            (map-set user-liquidity-positions
                { user: user, bridge-id: bridge-id }
                {
                    shares: shares-to-mint,
                    deposited-amount: amount,
                    fees-earned: u0,
                    deposited-at: current-time,
                    last-claim-at: current-time
                })
        )

        ;; Record event
        (map-set liquidity-events
            { pool-id: bridge-id, event-id: event-id }
            {
                event-type: "deposit",
                user: user,
                amount: amount,
                shares: shares-to-mint,
                timestamp: current-time
            }
        )

        (var-set liquidity-event-counter (+ event-id u1))
        (var-set total-pool-liquidity (+ (var-get total-pool-liquidity) amount))

        (print {
            event: "liquidity-deposited",
            user: user,
            bridge-id: bridge-id,
            amount: amount,
            shares-minted: shares-to-mint,
            new-total-liquidity: (+ (get total-liquidity pool) amount),
            timestamp: current-time
        })

        (ok shares-to-mint)
    )
)

;; Withdraw liquidity from pool
(define-public (withdraw-liquidity (bridge-id uint) (shares uint))
    (let
        (
            (pool (unwrap! (get-liquidity-pool bridge-id) ERR_POOL_NOT_FOUND))
            (user tx-sender)
            (position (unwrap! (get-user-position user bridge-id) ERR_POOL_NOT_FOUND))
            (current-time stacks-block-time)
            (event-id (var-get liquidity-event-counter))
            (withdrawal-amount (/ (* shares (get total-liquidity pool)) (get total-shares pool)))
        )
        (asserts! (>= (get shares position) shares) ERR_INSUFFICIENT_LIQUIDITY)
        (asserts! (> shares u0) ERR_INVALID_DEPOSIT)
        (asserts! (>= (get total-liquidity pool) withdrawal-amount) ERR_INSUFFICIENT_LIQUIDITY)

        ;; Transfer STX back to user
        (unwrap! (stx-transfer? withdrawal-amount (var-get contract-principal) user) ERR_INSUFFICIENT_LIQUIDITY)

        ;; Update pool
        (map-set liquidity-pools
            { bridge-id: bridge-id }
            (merge pool {
                total-liquidity: (- (get total-liquidity pool) withdrawal-amount),
                total-shares: (- (get total-shares pool) shares)
            })
        )

        ;; Update user position
        (map-set user-liquidity-positions
            { user: user, bridge-id: bridge-id }
            (merge position {
                shares: (- (get shares position) shares),
                deposited-amount: (if (> (get deposited-amount position) withdrawal-amount)
                    (- (get deposited-amount position) withdrawal-amount)
                    u0)
            })
        )

        ;; Record event
        (map-set liquidity-events
            { pool-id: bridge-id, event-id: event-id }
            {
                event-type: "withdrawal",
                user: user,
                amount: withdrawal-amount,
                shares: shares,
                timestamp: current-time
            }
        )

        (var-set liquidity-event-counter (+ event-id u1))
        (var-set total-pool-liquidity (- (var-get total-pool-liquidity) withdrawal-amount))

        (print {
            event: "liquidity-withdrawn",
            user: user,
            bridge-id: bridge-id,
            amount: withdrawal-amount,
            shares-burned: shares,
            new-total-liquidity: (- (get total-liquidity pool) withdrawal-amount),
            timestamp: current-time
        })

        (ok withdrawal-amount)
    )
)

;; Claim accumulated fees from liquidity provision
(define-public (claim-liquidity-fees (bridge-id uint))
    (let
        (
            (pool (unwrap! (get-liquidity-pool bridge-id) ERR_POOL_NOT_FOUND))
            (user tx-sender)
            (position (unwrap! (get-user-position user bridge-id) ERR_POOL_NOT_FOUND))
            (claimable-fees (calculate-claimable-fees user bridge-id))
            (current-time stacks-block-time)
        )
        (asserts! (> claimable-fees u0) ERR_INSUFFICIENT_LIQUIDITY)

        ;; Transfer fees to user
        (unwrap! (stx-transfer? claimable-fees (var-get contract-principal) user) ERR_INSUFFICIENT_LIQUIDITY)

        ;; Update user position
        (map-set user-liquidity-positions
            { user: user, bridge-id: bridge-id }
            (merge position {
                fees-earned: (+ (get fees-earned position) claimable-fees),
                last-claim-at: current-time
            })
        )

        (print {
            event: "liquidity-fees-claimed",
            user: user,
            bridge-id: bridge-id,
            fees-claimed: claimable-fees,
            total-fees-earned: (+ (get fees-earned position) claimable-fees),
            timestamp: current-time
        })

        (ok claimable-fees)
    )
)

;; Record bridge transaction fee (called when bridge is used)
(define-public (record-bridge-fee (bridge-id uint) (fee-amount uint))
    (let
        (
            (pool (unwrap! (get-liquidity-pool bridge-id) ERR_POOL_NOT_FOUND))
        )
        ;; In production, verify caller is authorized bridge contract
        (asserts! (get active pool) ERR_POOL_NOT_FOUND)
        (asserts! (> fee-amount u0) ERR_INVALID_DEPOSIT)

        ;; Update pool with collected fees
        (map-set liquidity-pools
            { bridge-id: bridge-id }
            (merge pool {
                total-fees-collected: (+ (get total-fees-collected pool) fee-amount)
            })
        )

        (print {
            event: "bridge-fee-recorded",
            bridge-id: bridge-id,
            fee-amount: fee-amount,
            total-fees-collected: (+ (get total-fees-collected pool) fee-amount),
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Admin: Set pool active status
(define-public (set-pool-active (bridge-id uint) (active bool))
    (let
        (
            (pool (unwrap! (get-liquidity-pool bridge-id) ERR_POOL_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)

        (map-set liquidity-pools
            { bridge-id: bridge-id }
            (merge pool { active: active })
        )

        (print {
            event: "pool-status-changed",
            bridge-id: bridge-id,
            active: active,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)
;; ========================================
;; Insurance Public Functions
;; ========================================

;; Purchase insurance coverage for bridge transaction
(define-public (purchase-insurance (bridge-id uint) (coverage-amount uint) (duration-hours uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (user tx-sender)
            (policy-id (+ (var-get insurance-counter) u1))
            (premium (calculate-premium bridge-id coverage-amount))
            (current-time stacks-block-time)
            (expiry-time (+ current-time (* duration-hours u3600)))
            (existing-policies (get-user-active-policies user bridge-id))
        )
        (asserts! (get active bridge) ERR_BRIDGE_NOT_FOUND)
        (asserts! (> coverage-amount u0) ERR_INVALID_COVERAGE)
        (asserts! (> duration-hours u0) ERR_INVALID_COVERAGE)
        (asserts! (<= duration-hours u168) ERR_INVALID_COVERAGE) ;; Max 7 days

        ;; Transfer premium to contract
        (unwrap! (stx-transfer? premium user (var-get contract-principal)) ERR_INVALID_COVERAGE)

        ;; Create insurance policy
        (map-set insurance-policies
            { user: user, policy-id: policy-id }
            {
                bridge-id: bridge-id,
                coverage-amount: coverage-amount,
                premium-paid: premium,
                purchased-at: current-time,
                expires-at: expiry-time,
                active: true,
                claimed: false
            }
        )

        ;; Add to user's active policies
        (map-set user-active-policies
            { user: user, bridge-id: bridge-id }
            (unwrap! (as-max-len? (append existing-policies policy-id) u10) ERR_INVALID_COVERAGE)
        )

        ;; Add premium to insurance pool
        (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) premium))
        (var-set insurance-counter policy-id)

        (print {
            event: "insurance-purchased",
            user: user,
            policy-id: policy-id,
            bridge-id: bridge-id,
            coverage-amount: coverage-amount,
            premium-paid: premium,
            expires-at: expiry-time,
            timestamp: current-time
        })

        (ok policy-id)
    )
)

;; File insurance claim for failed bridge transaction
(define-public (file-insurance-claim (policy-id uint) (claim-amount uint))
    (let
        (
            (user tx-sender)
            (policy (unwrap! (get-insurance-policy user policy-id) ERR_INSURANCE_NOT_FOUND))
            (claim-id (+ (var-get claim-counter) u1))
            (current-time stacks-block-time)
            (bridge-id (get bridge-id policy))
        )
        (asserts! (get active policy) ERR_INSURANCE_NOT_FOUND)
        (asserts! (not (get claimed policy)) ERR_CLAIM_ALREADY_PROCESSED)
        (asserts! (>= (get expires-at policy) current-time) ERR_INSURANCE_NOT_FOUND)
        (asserts! (<= claim-amount (get coverage-amount policy)) ERR_INVALID_COVERAGE)
        (asserts! (> claim-amount u0) ERR_INVALID_COVERAGE)

        ;; Create claim
        (map-set insurance-claims claim-id
            {
                policy-id: policy-id,
                user: user,
                bridge-id: bridge-id,
                claim-amount: claim-amount,
                filed-at: current-time,
                processed-at: u0,
                approved: false,
                processed: false,
                payout-amount: u0
            }
        )

        (var-set claim-counter claim-id)

        (print {
            event: "insurance-claim-filed",
            claim-id: claim-id,
            user: user,
            policy-id: policy-id,
            bridge-id: bridge-id,
            claim-amount: claim-amount,
            timestamp: current-time
        })

        (ok claim-id)
    )
)

;; Process insurance claim (admin function)
(define-public (process-insurance-claim (claim-id uint) (approved bool))
    (let
        (
            (claim (unwrap! (get-insurance-claim claim-id) ERR_CLAIM_NOT_FOUND))
            (policy (unwrap! (get-insurance-policy (get user claim) (get policy-id claim)) ERR_INSURANCE_NOT_FOUND))
            (current-time stacks-block-time)
            (payout (if approved (get claim-amount claim) u0))
            (pool-balance (var-get insurance-pool-balance))
            (bridge-id (get bridge-id claim))
            (risk-rating (get-bridge-risk-rating bridge-id))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (not (get processed claim)) ERR_CLAIM_ALREADY_PROCESSED)
        (asserts! (>= pool-balance payout) ERR_INSUFFICIENT_POOL)

        ;; Update claim
        (map-set insurance-claims claim-id
            (merge claim {
                processed: true,
                approved: approved,
                processed-at: current-time,
                payout-amount: payout
            })
        )

        ;; If approved, process payout
        (if approved
            (begin
                ;; Transfer payout to user
                (unwrap! (stx-transfer? payout (var-get contract-principal) (get user claim)) ERR_INSUFFICIENT_POOL)

                ;; Update insurance pool balance
                (var-set insurance-pool-balance (- pool-balance payout))

                ;; Mark policy as claimed
                (map-set insurance-policies
                    { user: (get user claim), policy-id: (get policy-id claim) }
                    (merge policy { claimed: true, active: false })
                )

                ;; Update bridge risk rating
                (map-set bridge-risk-ratings bridge-id
                    (merge risk-rating {
                        total-claims: (+ (get total-claims risk-rating) u1),
                        total-payouts: (+ (get total-payouts risk-rating) payout),
                        last-updated: current-time
                    })
                )
            )
            true
        )

        (print {
            event: "insurance-claim-processed",
            claim-id: claim-id,
            user: (get user claim),
            policy-id: (get policy-id claim),
            bridge-id: bridge-id,
            approved: approved,
            payout-amount: payout,
            timestamp: current-time
        })

        (ok payout)
    )
)

;; Update bridge risk score (admin function)
(define-public (update-bridge-risk-score (bridge-id uint) (risk-score uint))
    (let
        (
            (bridge (unwrap! (map-get? bridges bridge-id) ERR_BRIDGE_NOT_FOUND))
            (current-rating (get-bridge-risk-rating bridge-id))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= risk-score u100) ERR_INVALID_COVERAGE)

        (map-set bridge-risk-ratings bridge-id
            (merge current-rating {
                risk-score: risk-score,
                last-updated: stacks-block-time
            })
        )

        (print {
            event: "bridge-risk-score-updated",
            bridge-id: bridge-id,
            risk-score: risk-score,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Admin: Update insurance configuration
(define-public (set-insurance-config (base-premium uint) (coverage-ratio uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> base-premium u0) ERR_INVALID_COVERAGE)
        (asserts! (<= base-premium u1000) ERR_INVALID_COVERAGE) ;; Max 10%
        (asserts! (> coverage-ratio u0) ERR_INVALID_COVERAGE)

        (var-set base-premium-bps base-premium)
        (var-set coverage-to-premium-ratio coverage-ratio)

        (print {
            event: "insurance-config-updated",
            base-premium-bps: base-premium,
            coverage-ratio: coverage-ratio,
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Cancel expired policy (cleanup function)
(define-public (cancel-expired-policy (user principal) (policy-id uint))
    (let
        (
            (policy (unwrap! (get-insurance-policy user policy-id) ERR_INSURANCE_NOT_FOUND))
            (current-time stacks-block-time)
        )
        (asserts! (< (get expires-at policy) current-time) ERR_INSURANCE_EXISTS)
        (asserts! (get active policy) ERR_INSURANCE_NOT_FOUND)

        (map-set insurance-policies
            { user: user, policy-id: policy-id }
            (merge policy { active: false })
        )

        (print {
            event: "insurance-policy-expired",
            user: user,
            policy-id: policy-id,
            timestamp: current-time
        })

        (ok true)
    )
)

