;; intent-bridge.clar
;; Cross-chain intent bridge with contract verification
;; Uses Clarity 4 features: to-ascii?, contract-hash?, stacks-block-time

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u9001))
(define-constant ERR_INTENT_NOT_FOUND (err u9002))
(define-constant ERR_INTENT_EXPIRED (err u9003))
(define-constant ERR_INTENT_FILLED (err u9004))
(define-constant ERR_INVALID_AMOUNT (err u9005))
(define-constant ERR_UNVERIFIED_BRIDGE (err u9006))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u9008))
(define-constant ERR_CONTRACT_PAUSED (err u9009))
(define-constant ERR_INVALID_EXTENSION (err u9010))
(define-constant ERR_WITHDRAWAL_COOLDOWN (err u9011))
(define-constant ERR_REPUTATION_TOO_LOW (err u9012))
(define-constant ERR_SLASH_AMOUNT_TOO_HIGH (err u9013))

(define-constant INTENT_PENDING u0)
(define-constant INTENT_FILLED u1)
(define-constant INTENT_CANCELLED u2)
(define-constant CHAIN_STACKS u1)
(define-constant CHAIN_BITCOIN u2)
(define-constant CHAIN_ETHEREUM u3)
(define-constant CHAIN_POLYGON u4)

(define-data-var intent-counter uint u0)
(define-data-var total-volume uint u0)
(define-data-var protocol-fee-bps uint u30)
(define-data-var min-collateral-ratio uint u150)
(define-data-var contract-vault principal tx-sender)
(define-data-var contract-paused bool false)
(define-data-var withdrawal-cooldown uint u86400)
(define-data-var min-reputation-score uint u50)
(define-data-var max-slash-percentage uint u50)

(define-map chain-volume uint uint)

(define-map intents uint {
    creator: principal, source-chain: uint, dest-chain: uint,
    source-amount: uint, dest-amount: uint, recipient: (string-ascii 128),
    expiry: uint, status: uint, created-at: uint,
    filled-by: (optional principal), intent-hash: (buff 32)
})

(define-map verified-bridges principal {
    name: (string-ascii 64), contract-hash: (buff 32),
    verified-at: uint, active: bool
})

(define-map solvers principal {
    collateral: uint, total-filled: uint, successful-fills: uint,
    reputation-score: uint, registered-at: uint, active: bool,
    last-withdrawal: uint
})

(define-trait ft-trait (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
))

(define-read-only (get-current-time) stacks-block-time)

(define-read-only (get-intent (intent-id uint)) (map-get? intents intent-id))

(define-read-only (get-solver (solver principal)) (map-get? solvers solver))

(define-read-only (is-bridge-verified (bridge-contract principal))
    (match (map-get? verified-bridges bridge-contract)
        bridge (and (get active bridge)
            (match (contract-hash? bridge-contract)
                current-hash (is-eq current-hash (get contract-hash bridge))
                hash-err false))
        false))

(define-read-only (generate-intent-message (intent-id uint))
    (match (map-get? intents intent-id)
        intent (let ((id-str (unwrap-panic (to-ascii? intent-id)))
                    (amount-str (unwrap-panic (to-ascii? (get source-amount intent)))))
            (concat (concat "Intent #" id-str) (concat " for " amount-str)))
        "Intent not found"))

(define-read-only (generate-cross-chain-payload (intent-id uint) (source-chain uint) (dest-chain uint) (amount uint))
    (let ((intent-str (unwrap-panic (to-ascii? intent-id)))
          (source-str (unwrap-panic (to-ascii? source-chain)))
          (dest-str (unwrap-panic (to-ascii? dest-chain)))
          (amount-str (unwrap-panic (to-ascii? amount))))
        (concat (concat (concat "BRIDGE:" intent-str) (concat "|SRC:" source-str))
                (concat (concat "|DST:" dest-str) (concat "|AMT:" amount-str)))))

(define-read-only (calculate-intent-hash (creator principal) (source-chain uint) (dest-chain uint) (source-amount uint) (dest-amount uint) (nonce uint))
    (sha256 (concat (concat (unwrap-panic (to-consensus-buff? creator)) (unwrap-panic (to-consensus-buff? source-chain)))
        (concat (concat (unwrap-panic (to-consensus-buff? dest-chain)) (unwrap-panic (to-consensus-buff? source-amount)))
                (concat (unwrap-panic (to-consensus-buff? dest-amount)) (unwrap-panic (to-consensus-buff? nonce)))))))

(define-read-only (is-intent-fillable (intent-id uint))
    (match (map-get? intents intent-id)
        intent (and (is-eq (get status intent) INTENT_PENDING) (< stacks-block-time (get expiry intent)))
        false))

(define-read-only (get-required-collateral (intent-id uint))
    (match (map-get? intents intent-id)
        intent (/ (* (get source-amount intent) (var-get min-collateral-ratio)) u100)
        u0))

(define-read-only (get-protocol-stats)
    { total-intents: (var-get intent-counter), total-volume: (var-get total-volume),
      fee-bps: (var-get protocol-fee-bps), min-collateral-ratio: (var-get min-collateral-ratio) })

(define-read-only (get-chain-volume (target-chain uint))
    (default-to u0 (map-get? chain-volume target-chain)))

(define-read-only (get-all-chain-volumes)
    {
        stacks: (get-chain-volume CHAIN_STACKS),
        bitcoin: (get-chain-volume CHAIN_BITCOIN),
        ethereum: (get-chain-volume CHAIN_ETHEREUM),
        polygon: (get-chain-volume CHAIN_POLYGON)
    })

(define-public (verify-bridge (bridge-contract principal) (name (string-ascii 64)))
    (let ((bridge-hash (unwrap! (contract-hash? bridge-contract) ERR_UNVERIFIED_BRIDGE)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set verified-bridges bridge-contract {
            name: name, contract-hash: bridge-hash, verified-at: stacks-block-time, active: true })
        (ok true)))

(define-public (set-protocol-fee (new-fee-bps uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= new-fee-bps u100) ERR_INVALID_AMOUNT)
        (var-set protocol-fee-bps new-fee-bps)
        (ok true)))

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set contract-paused (not (var-get contract-paused)))
        (ok (var-get contract-paused))))

(define-public (register-solver (collateral uint))
    (begin
        (asserts! (> collateral u0) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? collateral tx-sender (var-get contract-vault)))
        (map-set solvers tx-sender {
            collateral: collateral, total-filled: u0, successful-fills: u0,
            reputation-score: u100, registered-at: stacks-block-time, active: true,
            last-withdrawal: u0 })
        (ok true)))

(define-public (add-collateral (amount uint))
    (let ((solver (unwrap! (map-get? solvers tx-sender) ERR_NOT_AUTHORIZED)))
        (try! (stx-transfer? amount tx-sender (var-get contract-vault)))
        (map-set solvers tx-sender (merge solver { collateral: (+ (get collateral solver) amount) }))
        (ok true)))

(define-public (create-intent (source-asset <ft-trait>) (dest-chain uint) (source-amount uint) (dest-amount uint) (recipient (string-ascii 128)) (expiry-duration uint))
    (let ((intent-id (+ (var-get intent-counter) u1))
          (expiry (+ stacks-block-time expiry-duration))
          (intent-hash (calculate-intent-hash tx-sender CHAIN_STACKS dest-chain source-amount dest-amount intent-id)))
        (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
        (asserts! (> source-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> expiry-duration u3600) ERR_INVALID_AMOUNT)
        (try! (contract-call? source-asset transfer source-amount tx-sender (var-get contract-vault) none))
        (map-set intents intent-id {
            creator: tx-sender, source-chain: CHAIN_STACKS, dest-chain: dest-chain,
            source-amount: source-amount, dest-amount: dest-amount, recipient: recipient,
            expiry: expiry, status: INTENT_PENDING, created-at: stacks-block-time,
            filled-by: none, intent-hash: intent-hash })
        (var-set intent-counter intent-id)
        (print (generate-intent-message intent-id))
        (ok intent-id)))

(define-public (fill-intent (intent-id uint))
    (let ((caller tx-sender)
          (intent (unwrap! (map-get? intents intent-id) ERR_INTENT_NOT_FOUND))
          (solver (unwrap! (map-get? solvers caller) ERR_NOT_AUTHORIZED))
          (required-collateral (get-required-collateral intent-id)))
        (asserts! (is-eq (get status intent) INTENT_PENDING) ERR_INTENT_FILLED)
        (asserts! (< stacks-block-time (get expiry intent)) ERR_INTENT_EXPIRED)
        (asserts! (get active solver) ERR_NOT_AUTHORIZED)
        (asserts! (>= (get reputation-score solver) (var-get min-reputation-score)) ERR_REPUTATION_TOO_LOW)
        (asserts! (>= (get collateral solver) required-collateral) ERR_INSUFFICIENT_COLLATERAL)
        (map-set solvers caller (merge solver { collateral: (- (get collateral solver) required-collateral) }))
        (map-set intents intent-id (merge intent { status: INTENT_FILLED, filled-by: (some caller) }))
        (var-set total-volume (+ (var-get total-volume) (get source-amount intent)))
        (map-set chain-volume (get dest-chain intent)
            (+ (default-to u0 (map-get? chain-volume (get dest-chain intent))) (get dest-amount intent)))
        (ok true)))

(define-public (cancel-intent (intent-id uint) (token <ft-trait>))
    (let ((intent (unwrap! (map-get? intents intent-id) ERR_INTENT_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get creator intent)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status intent) INTENT_PENDING) ERR_INTENT_FILLED)
        (try! (contract-call? token transfer (get source-amount intent) (var-get contract-vault) tx-sender none))
        (map-set intents intent-id (merge intent { status: INTENT_CANCELLED }))
        (ok true)))

(define-read-only (get-solver-stats (solver principal))
    (match (map-get? solvers solver)
        solver-data {
            collateral: (get collateral solver-data),
            total-filled: (get total-filled solver-data),
            successful-fills: (get successful-fills solver-data),
            reputation-score: (get reputation-score solver-data),
            success-rate: (if (> (get total-filled solver-data) u0)
                (/ (* (get successful-fills solver-data) u100) (get total-filled solver-data))
                u0)
        }
        { collateral: u0, total-filled: u0, successful-fills: u0, reputation-score: u0, success-rate: u0 }))

(define-public (extend-intent-expiry (intent-id uint) (extension-duration uint))
    (let ((intent (unwrap! (map-get? intents intent-id) ERR_INTENT_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get creator intent)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status intent) INTENT_PENDING) ERR_INTENT_FILLED)
        (asserts! (> extension-duration u0) ERR_INVALID_EXTENSION)
        (asserts! (<= extension-duration u86400) ERR_INVALID_EXTENSION)
        (map-set intents intent-id (merge intent { expiry: (+ (get expiry intent) extension-duration) }))
        (ok true)))

(define-public (withdraw-collateral (amount uint))
    (let ((solver (unwrap! (map-get? solvers tx-sender) ERR_NOT_AUTHORIZED)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (get collateral solver)) ERR_INSUFFICIENT_COLLATERAL)
        (asserts! (>= (- stacks-block-time (get last-withdrawal solver)) (var-get withdrawal-cooldown)) ERR_WITHDRAWAL_COOLDOWN)
        (try! (stx-transfer? amount (var-get contract-vault) tx-sender))
        (map-set solvers tx-sender (merge solver {
            collateral: (- (get collateral solver) amount),
            last-withdrawal: stacks-block-time
        }))
        (ok true)))

(define-public (slash-solver-reputation (solver principal) (slash-percentage uint))
    (let ((solver-data (unwrap! (map-get? solvers solver) ERR_NOT_AUTHORIZED))
          (current-reputation (get reputation-score solver-data))
          (max-slash (var-get max-slash-percentage)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= slash-percentage max-slash) ERR_SLASH_AMOUNT_TOO_HIGH)
        (asserts! (> slash-percentage u0) ERR_INVALID_AMOUNT)
        (let ((slash-amount (/ (* current-reputation slash-percentage) u100))
              (new-reputation (if (>= current-reputation slash-amount)
                                (- current-reputation slash-amount)
                                u0)))
            (map-set solvers solver (merge solver-data {
                reputation-score: new-reputation
            }))
            (ok {slashed: slash-amount, new-reputation: new-reputation}))))

(define-public (restore-solver-reputation (solver principal) (restore-amount uint))
    (let ((solver-data (unwrap! (map-get? solvers solver) ERR_NOT_AUTHORIZED))
          (current-reputation (get reputation-score solver-data)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> restore-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= (+ current-reputation restore-amount) u100) ERR_INVALID_AMOUNT)
        (map-set solvers solver (merge solver-data {
            reputation-score: (+ current-reputation restore-amount)
        }))
        (ok true)))

(define-read-only (can-solver-fill (solver principal))
    (match (map-get? solvers solver)
        solver-data (and (get active solver-data)
                        (>= (get reputation-score solver-data) (var-get min-reputation-score)))
        false))

(define-read-only (get-reputation-threshold)
    (var-get min-reputation-score))

(define-read-only (get-max-slash-percentage)
    (var-get max-slash-percentage))
