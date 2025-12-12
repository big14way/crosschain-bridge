;; intent-executor.clar
;; Executor contract for processing cross-chain intents
;; Uses Clarity 4 features: stacks-block-time, to-ascii?, contract-hash?

;; ========================================
;; Constants
;; ========================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u11001))
(define-constant ERR_EXECUTION_FAILED (err u11002))
(define-constant ERR_INVALID_PROOF (err u11003))
(define-constant ERR_ALREADY_EXECUTED (err u11004))
(define-constant ERR_TIMEOUT (err u11005))

;; Execution status
(define-constant EXEC_PENDING u0)
(define-constant EXEC_COMPLETED u1)
(define-constant EXEC_FAILED u2)
(define-constant EXEC_TIMEOUT u3)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var execution-counter uint u0)
(define-data-var execution-timeout uint u86400) ;; 24 hours default

;; ========================================
;; Data Maps
;; ========================================

;; Execution records
(define-map executions
    uint
    {
        intent-id: uint,
        executor: principal,
        source-tx-hash: (buff 32),
        dest-tx-hash: (optional (buff 32)),
        status: uint,
        started-at: uint,
        completed-at: (optional uint),
        gas-used: (optional uint)
    }
)

;; Intent to execution mapping
(define-map intent-executions
    uint
    uint
)

;; Executor whitelist
(define-map authorized-executors
    principal
    {
        authorized-at: uint,
        total-executions: uint,
        successful: uint,
        failed: uint,
        active: bool
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

;; Get execution record
(define-read-only (get-execution (exec-id uint))
    (map-get? executions exec-id)
)

;; Get execution for intent
(define-read-only (get-intent-execution (intent-id uint))
    (match (map-get? intent-executions intent-id)
        exec-id (map-get? executions exec-id)
        none
    )
)

;; Check if executor is authorized
(define-read-only (is-executor-authorized (executor principal))
    (match (map-get? authorized-executors executor)
        exec-info (get active exec-info)
        false
    )
)

;; Generate execution status message using to-ascii?
(define-read-only (get-execution-status-message (exec-id uint))
    (match (map-get? executions exec-id)
        exec (let
            (
                (id-str (unwrap-panic (to-ascii? exec-id)))
                (intent-str (unwrap-panic (to-ascii? (get intent-id exec))))
                (status-str (unwrap-panic (to-ascii? (get status exec))))
            )
            (concat 
                (concat (concat "Execution #" id-str) (concat " for Intent #" intent-str))
                (concat " | Status: " status-str)
            )
        )
        "Execution not found"
    )
)

;; Check if execution timed out
(define-read-only (is-execution-timed-out (exec-id uint))
    (match (map-get? executions exec-id)
        exec (and 
            (is-eq (get status exec) EXEC_PENDING)
            (> (- stacks-block-time (get started-at exec)) (var-get execution-timeout))
        )
        false
    )
)

;; Get executor stats
(define-read-only (get-executor-stats (executor principal))
    (map-get? authorized-executors executor)
)

;; ========================================
;; Admin Functions
;; ========================================

;; Authorize an executor
(define-public (authorize-executor (executor principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set authorized-executors executor {
            authorized-at: stacks-block-time,
            total-executions: u0,
            successful: u0,
            failed: u0,
            active: true
        })
        
        (ok true)
    )
)

;; Revoke executor authorization
(define-public (revoke-executor (executor principal))
    (let
        (
            (exec-info (unwrap! (map-get? authorized-executors executor) ERR_NOT_AUTHORIZED))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set authorized-executors executor (merge exec-info { active: false }))
        
        (ok true)
    )
)

;; Update execution timeout
(define-public (set-execution-timeout (new-timeout uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set execution-timeout new-timeout)
        (ok true)
    )
)

;; ========================================
;; Execution Functions
;; ========================================

;; Start execution of an intent
(define-public (start-execution (intent-id uint) (source-tx-hash (buff 32)))
    (let
        (
            (caller tx-sender)
            (current-time stacks-block-time)
            (exec-id (+ (var-get execution-counter) u1))
        )
        ;; Verify executor is authorized
        (asserts! (is-executor-authorized caller) ERR_NOT_AUTHORIZED)
        
        ;; Check intent hasn't been executed
        (asserts! (is-none (map-get? intent-executions intent-id)) ERR_ALREADY_EXECUTED)
        
        ;; Create execution record
        (map-set executions exec-id {
            intent-id: intent-id,
            executor: caller,
            source-tx-hash: source-tx-hash,
            dest-tx-hash: none,
            status: EXEC_PENDING,
            started-at: current-time,
            completed-at: none,
            gas-used: none
        })
        
        ;; Link intent to execution
        (map-set intent-executions intent-id exec-id)
        
        ;; Update counter
        (var-set execution-counter exec-id)
        
        ;; Update executor stats
        (match (map-get? authorized-executors caller)
            exec-info (map-set authorized-executors caller (merge exec-info {
                total-executions: (+ (get total-executions exec-info) u1)
            }))
            true
        )
        
        ;; Print status
        (print (get-execution-status-message exec-id))
        
        (ok exec-id)
    )
)

;; Complete execution with proof
(define-public (complete-execution (exec-id uint) (dest-tx-hash (buff 32)) (gas-used uint))
    (let
        (
            (caller tx-sender)
            (current-time stacks-block-time)
            (exec (unwrap! (map-get? executions exec-id) ERR_EXECUTION_FAILED))
        )
        ;; Verify caller is the executor
        (asserts! (is-eq caller (get executor exec)) ERR_NOT_AUTHORIZED)
        
        ;; Verify execution is pending
        (asserts! (is-eq (get status exec) EXEC_PENDING) ERR_ALREADY_EXECUTED)
        
        ;; Check not timed out
        (asserts! (not (is-execution-timed-out exec-id)) ERR_TIMEOUT)
        
        ;; Update execution record
        (map-set executions exec-id (merge exec {
            dest-tx-hash: (some dest-tx-hash),
            status: EXEC_COMPLETED,
            completed-at: (some current-time),
            gas-used: (some gas-used)
        }))
        
        ;; Update executor stats
        (match (map-get? authorized-executors caller)
            exec-info (map-set authorized-executors caller (merge exec-info {
                successful: (+ (get successful exec-info) u1)
            }))
            true
        )
        
        ;; Print completion status
        (print (get-execution-status-message exec-id))
        
        (ok true)
    )
)

;; Mark execution as failed
(define-public (fail-execution (exec-id uint) (reason (string-ascii 128)))
    (let
        (
            (caller tx-sender)
            (exec (unwrap! (map-get? executions exec-id) ERR_EXECUTION_FAILED))
        )
        ;; Verify caller is the executor or admin
        (asserts! (or 
            (is-eq caller (get executor exec))
            (is-eq caller CONTRACT_OWNER)
        ) ERR_NOT_AUTHORIZED)
        
        ;; Update execution record
        (map-set executions exec-id (merge exec {
            status: EXEC_FAILED
        }))
        
        ;; Update executor stats
        (match (map-get? authorized-executors (get executor exec))
            exec-info (map-set authorized-executors (get executor exec) (merge exec-info {
                failed: (+ (get failed exec-info) u1)
            }))
            true
        )
        
        ;; Print failure
        (print reason)
        
        (ok true)
    )
)

;; Mark timed out executions
(define-public (mark-timeout (exec-id uint))
    (let
        (
            (exec (unwrap! (map-get? executions exec-id) ERR_EXECUTION_FAILED))
        )
        ;; Anyone can mark a timed out execution
        (asserts! (is-execution-timed-out exec-id) ERR_NOT_AUTHORIZED)
        
        ;; Update execution record
        (map-set executions exec-id (merge exec {
            status: EXEC_TIMEOUT
        }))
        
        ;; Update executor stats (count as failed)
        (match (map-get? authorized-executors (get executor exec))
            exec-info (map-set authorized-executors (get executor exec) (merge exec-info {
                failed: (+ (get failed exec-info) u1)
            }))
            true
        )
        
        (ok true)
    )
)
