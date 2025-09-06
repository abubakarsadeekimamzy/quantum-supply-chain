
;; title: quantum-component
;; version: 1.0.0
;; summary: Smart contract for managing quantum computing components in supply chain
;; description: This contract provides functionality for registering, verifying, and transferring
;;              ownership of quantum hardware components with full traceability.

;; traits
;;

;; token definitions
;;

;; constants
;;
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_COMPONENT_NOT_FOUND (err u101))
(define-constant ERR_COMPONENT_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_COMPONENT_TYPE (err u103))
(define-constant ERR_INVALID_QUALITY_SCORE (err u104))
(define-constant ERR_TRANSFER_TO_SELF (err u105))
(define-constant ERR_INVALID_BATCH_ID (err u106))
(define-constant ERR_COMPONENT_ALREADY_VERIFIED (err u107))
(define-constant ERR_INVALID_PARAMETERS (err u108))

(define-constant COMPONENT_TYPE_QUBIT u1)
(define-constant COMPONENT_TYPE_CONTROLLER u2)
(define-constant COMPONENT_TYPE_CRYOSTAT u3)
(define-constant COMPONENT_TYPE_AMPLIFIER u4)
(define-constant COMPONENT_TYPE_READOUT u5)

(define-constant MIN_QUALITY_SCORE u0)
(define-constant MAX_QUALITY_SCORE u100)
(define-constant CONTRACT_OWNER tx-sender)

;; data vars
;;
(define-data-var component-counter uint u0)
(define-data-var batch-counter uint u0)

;; data maps
;;
;; Main component registry
(define-map components
    { component-id: uint }
    {
        component-type: uint,
        manufacturer: principal,
        serial-number: (string-ascii 64),
        manufacturing-date: uint,
        batch-id: uint,
        current-owner: principal,
        quality-score: uint,
        is-verified: bool,
        verification-date: (optional uint),
        verifier: (optional principal),
        created-at: uint
    }
)

;; Component ownership history
(define-map ownership-history
    { component-id: uint, transfer-id: uint }
    {
        from: principal,
        to: principal,
        timestamp: uint,
        transfer-reason: (string-ascii 128)
    }
)

;; Component transfer counter for each component
(define-map transfer-counters
    { component-id: uint }
    { count: uint }
)

;; Manufacturing batch information
(define-map manufacturing-batches
    { batch-id: uint }
    {
        manufacturer: principal,
        batch-name: (string-ascii 64),
        production-date: uint,
        total-components: uint,
        quality-standard: (string-ascii 32),
        certification: (string-ascii 128)
    }
)

;; Quality verification records
(define-map quality-verifications
    { component-id: uint, verification-id: uint }
    {
        verifier: principal,
        quality-score: uint,
        verification-notes: (string-ascii 256),
        verification-date: uint,
        test-results: (string-ascii 512)
    }
)

;; Verification counter for each component
(define-map verification-counters
    { component-id: uint }
    { count: uint }
)

;; public functions
;;

;; Register a new quantum component
(define-public (register-component (component-type uint) (serial-number (string-ascii 64)) 
                                   (manufacturing-date uint) (batch-id uint))
    (let (
        (component-id (+ (var-get component-counter) u1))
        (caller tx-sender)
    )
        ;; Validate component type
        (asserts! (and (>= component-type u1) (<= component-type u5)) ERR_INVALID_COMPONENT_TYPE)
        ;; Validate batch exists
        (asserts! (is-some (map-get? manufacturing-batches { batch-id: batch-id })) ERR_INVALID_BATCH_ID)
        ;; Validate parameters
        (asserts! (> (len serial-number) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> manufacturing-date u0) ERR_INVALID_PARAMETERS)
        
        ;; Register the component
        (map-set components
            { component-id: component-id }
            {
                component-type: component-type,
                manufacturer: caller,
                serial-number: serial-number,
                manufacturing-date: manufacturing-date,
                batch-id: batch-id,
                current-owner: caller,
                quality-score: u0,
                is-verified: false,
                verification-date: none,
                verifier: none,
                created-at: block-height
            }
        )
        
        ;; Initialize transfer counter
        (map-set transfer-counters { component-id: component-id } { count: u0 })
        
        ;; Initialize verification counter
        (map-set verification-counters { component-id: component-id } { count: u0 })
        
        ;; Update component counter
        (var-set component-counter component-id)
        
        (ok component-id)
    )
)

;; Create a new manufacturing batch
(define-public (create-manufacturing-batch (batch-name (string-ascii 64)) (quality-standard (string-ascii 32))
                                           (certification (string-ascii 128)))
    (let (
        (batch-id (+ (var-get batch-counter) u1))
        (caller tx-sender)
    )
        ;; Validate parameters
        (asserts! (> (len batch-name) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len quality-standard) u0) ERR_INVALID_PARAMETERS)
        
        ;; Create batch
        (map-set manufacturing-batches
            { batch-id: batch-id }
            {
                manufacturer: caller,
                batch-name: batch-name,
                production-date: block-height,
                total-components: u0,
                quality-standard: quality-standard,
                certification: certification
            }
        )
        
        ;; Update batch counter
        (var-set batch-counter batch-id)
        
        (ok batch-id)
    )
)

;; Verify component quality
(define-public (verify-quality (component-id uint) (quality-score uint) 
                               (verification-notes (string-ascii 256)) (test-results (string-ascii 512)))
    (let (
        (component (unwrap! (map-get? components { component-id: component-id }) ERR_COMPONENT_NOT_FOUND))
        (verification-id (+ (default-to u0 (get count (map-get? verification-counters { component-id: component-id }))) u1))
        (caller tx-sender)
    )
        ;; Validate quality score
        (asserts! (and (>= quality-score MIN_QUALITY_SCORE) (<= quality-score MAX_QUALITY_SCORE)) ERR_INVALID_QUALITY_SCORE)
        ;; Validate parameters
        (asserts! (> (len verification-notes) u0) ERR_INVALID_PARAMETERS)
        
        ;; Add quality verification record
        (map-set quality-verifications
            { component-id: component-id, verification-id: verification-id }
            {
                verifier: caller,
                quality-score: quality-score,
                verification-notes: verification-notes,
                verification-date: block-height,
                test-results: test-results
            }
        )
        
        ;; Update component with verification info
        (map-set components
            { component-id: component-id }
            (merge component {
                quality-score: quality-score,
                is-verified: true,
                verification-date: (some block-height),
                verifier: (some caller)
            })
        )
        
        ;; Update verification counter
        (map-set verification-counters { component-id: component-id } { count: verification-id })
        
        (ok verification-id)
    )
)

;; Transfer component ownership
(define-public (transfer-ownership (component-id uint) (new-owner principal) (reason (string-ascii 128)))
    (let (
        (component (unwrap! (map-get? components { component-id: component-id }) ERR_COMPONENT_NOT_FOUND))
        (current-owner (get current-owner component))
        (transfer-id (+ (default-to u0 (get count (map-get? transfer-counters { component-id: component-id }))) u1))
        (caller tx-sender)
    )
        ;; Validate ownership
        (asserts! (is-eq caller current-owner) ERR_NOT_AUTHORIZED)
        ;; Validate not transferring to self
        (asserts! (not (is-eq caller new-owner)) ERR_TRANSFER_TO_SELF)
        ;; Validate reason provided
        (asserts! (> (len reason) u0) ERR_INVALID_PARAMETERS)
        
        ;; Record ownership transfer
        (map-set ownership-history
            { component-id: component-id, transfer-id: transfer-id }
            {
                from: current-owner,
                to: new-owner,
                timestamp: block-height,
                transfer-reason: reason
            }
        )
        
        ;; Update component ownership
        (map-set components
            { component-id: component-id }
            (merge component { current-owner: new-owner })
        )
        
        ;; Update transfer counter
        (map-set transfer-counters { component-id: component-id } { count: transfer-id })
        
        (ok transfer-id)
    )
)

;; read only functions
;;

;; Get component details
(define-read-only (get-component (component-id uint))
    (map-get? components { component-id: component-id })
)

;; Get manufacturing batch details
(define-read-only (get-manufacturing-batch (batch-id uint))
    (map-get? manufacturing-batches { batch-id: batch-id })
)

;; Get ownership history for a component
(define-read-only (get-ownership-record (component-id uint) (transfer-id uint))
    (map-get? ownership-history { component-id: component-id, transfer-id: transfer-id })
)

;; Get quality verification record
(define-read-only (get-quality-verification (component-id uint) (verification-id uint))
    (map-get? quality-verifications { component-id: component-id, verification-id: verification-id })
)

;; Get total number of transfers for a component
(define-read-only (get-transfer-count (component-id uint))
    (default-to u0 (get count (map-get? transfer-counters { component-id: component-id })))
)

;; Get total number of verifications for a component
(define-read-only (get-verification-count (component-id uint))
    (default-to u0 (get count (map-get? verification-counters { component-id: component-id })))
)

;; Get current component counter
(define-read-only (get-component-counter)
    (var-get component-counter)
)

;; Get current batch counter
(define-read-only (get-batch-counter)
    (var-get batch-counter)
)

;; Check if component exists
(define-read-only (component-exists (component-id uint))
    (is-some (map-get? components { component-id: component-id }))
)

;; Get component type name (helper function)
(define-read-only (get-component-type-name (component-type uint))
    (if (is-eq component-type COMPONENT_TYPE_QUBIT)
        "Qubit"
        (if (is-eq component-type COMPONENT_TYPE_CONTROLLER)
            "Controller"
            (if (is-eq component-type COMPONENT_TYPE_CRYOSTAT)
                "Cryostat"
                (if (is-eq component-type COMPONENT_TYPE_AMPLIFIER)
                    "Amplifier"
                    (if (is-eq component-type COMPONENT_TYPE_READOUT)
                        "Readout"
                        "Unknown"
                    )
                )
            )
        )
    )
)

;; private functions
;;

;; Validate component ownership
(define-private (is-component-owner (component-id uint) (user principal))
    (match (map-get? components { component-id: component-id })
        component (is-eq (get current-owner component) user)
        false
    )
)

;; Get latest verification for component
(define-private (get-latest-verification-id (component-id uint))
    (default-to u0 (get count (map-get? verification-counters { component-id: component-id })))
)
