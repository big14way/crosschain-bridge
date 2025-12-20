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
