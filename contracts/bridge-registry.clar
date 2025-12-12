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
