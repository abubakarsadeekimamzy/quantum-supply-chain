
;; title: research-collaboration
;; version: 1.0.0
;; summary: Smart contract for managing quantum research collaborations and projects
;; description: This contract facilitates secure collaboration between research institutions,
;;              managing project proposals, resource allocation, and intellectual property rights.

;; traits
;;

;; token definitions
;;

;; constants
;;
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_PROJECT_NOT_FOUND (err u201))
(define-constant ERR_RESEARCHER_NOT_FOUND (err u202))
(define-constant ERR_MILESTONE_NOT_FOUND (err u203))
(define-constant ERR_INSUFFICIENT_FUNDING (err u204))
(define-constant ERR_PROJECT_ALREADY_EXISTS (err u205))
(define-constant ERR_RESEARCHER_ALREADY_EXISTS (err u206))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u207))
(define-constant ERR_INVALID_PARAMETERS (err u208))
(define-constant ERR_PROJECT_NOT_ACTIVE (err u209))
(define-constant ERR_INVALID_ROLE (err u210))
(define-constant ERR_FUNDING_NOT_AVAILABLE (err u211))
(define-constant ERR_MILESTONE_NOT_READY (err u212))

(define-constant ROLE_PRINCIPAL_INVESTIGATOR u1)
(define-constant ROLE_RESEARCHER u2)
(define-constant ROLE_POSTDOC u3)
(define-constant ROLE_GRAD_STUDENT u4)
(define-constant ROLE_COLLABORATOR u5)

(define-constant PROJECT_STATUS_PROPOSED u1)
(define-constant PROJECT_STATUS_ACTIVE u2)
(define-constant PROJECT_STATUS_COMPLETED u3)
(define-constant PROJECT_STATUS_CANCELLED u4)

(define-constant MILESTONE_STATUS_PENDING u1)
(define-constant MILESTONE_STATUS_IN_PROGRESS u2)
(define-constant MILESTONE_STATUS_COMPLETED u3)
(define-constant MILESTONE_STATUS_DELAYED u4)

(define-constant MAX_RESEARCHERS_PER_PROJECT u50)
(define-constant MIN_FUNDING_AMOUNT u1000)

;; data vars
;;
(define-data-var project-counter uint u0)
(define-data-var milestone-counter uint u0)
(define-data-var total-funding-allocated uint u0)
(define-data-var contract-admin principal tx-sender)

;; data maps
;;
;; Research project registry
(define-map research-projects
    { project-id: uint }
    {
        title: (string-ascii 128),
        description: (string-ascii 512),
        principal-investigator: principal,
        institution: (string-ascii 64),
        research-field: (string-ascii 64),
        start-date: uint,
        expected-end-date: uint,
        actual-end-date: (optional uint),
        status: uint,
        total-funding: uint,
        allocated-funding: uint,
        remaining-funding: uint,
        researcher-count: uint,
        milestone-count: uint,
        created-at: uint
    }
)

;; Project researchers and their roles
(define-map project-researchers
    { project-id: uint, researcher: principal }
    {
        role: uint,
        joined-date: uint,
        contribution-score: uint,
        is-active: bool,
        expertise: (string-ascii 128),
        allocation-percentage: uint
    }
)

;; Research milestones
(define-map project-milestones
    { project-id: uint, milestone-id: uint }
    {
        title: (string-ascii 128),
        description: (string-ascii 256),
        target-date: uint,
        completion-date: (optional uint),
        status: uint,
        funding-allocation: uint,
        deliverables: (string-ascii 256),
        responsible-researcher: principal,
        created-by: principal,
        created-at: uint
    }
)

;; Project funding allocations
(define-map funding-allocations
    { project-id: uint, allocation-id: uint }
    {
        amount: uint,
        purpose: (string-ascii 128),
        allocated-by: principal,
        allocation-date: uint,
        is-released: bool,
        milestone-id: (optional uint)
    }
)

;; Allocation counters per project
(define-map allocation-counters
    { project-id: uint }
    { count: uint }
)

;; Intellectual property records
(define-map intellectual-property
    { project-id: uint, ip-id: uint }
    {
        title: (string-ascii 128),
        description: (string-ascii 256),
        creator: principal,
        creation-date: uint,
        ip-type: (string-ascii 32),
        patent-number: (optional (string-ascii 64)),
        publication-reference: (optional (string-ascii 128))
    }
)

;; IP counters per project
(define-map ip-counters
    { project-id: uint }
    { count: uint }
)

;; public functions
;;

;; Create a new research project
(define-public (create-project (title (string-ascii 128)) (description (string-ascii 512)) 
                               (institution (string-ascii 64)) (research-field (string-ascii 64))
                               (expected-duration uint) (initial-funding uint))
    (let (
        (project-id (+ (var-get project-counter) u1))
        (caller tx-sender)
        (expected-end (+ block-height expected-duration))
    )
        ;; Validate parameters
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len description) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len institution) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> expected-duration u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= initial-funding MIN_FUNDING_AMOUNT) ERR_INSUFFICIENT_FUNDING)
        
        ;; Create project
        (map-set research-projects
            { project-id: project-id }
            {
                title: title,
                description: description,
                principal-investigator: caller,
                institution: institution,
                research-field: research-field,
                start-date: block-height,
                expected-end-date: expected-end,
                actual-end-date: none,
                status: PROJECT_STATUS_PROPOSED,
                total-funding: initial-funding,
                allocated-funding: u0,
                remaining-funding: initial-funding,
                researcher-count: u1,
                milestone-count: u0,
                created-at: block-height
            }
        )
        
        ;; Add principal investigator as first researcher
        (map-set project-researchers
            { project-id: project-id, researcher: caller }
            {
                role: ROLE_PRINCIPAL_INVESTIGATOR,
                joined-date: block-height,
                contribution-score: u0,
                is-active: true,
                expertise: research-field,
                allocation-percentage: u100
            }
        )
        
        ;; Initialize counters
        (map-set allocation-counters { project-id: project-id } { count: u0 })
        (map-set ip-counters { project-id: project-id } { count: u0 })
        
        ;; Update project counter
        (var-set project-counter project-id)
        
        ;; Update total funding
        (var-set total-funding-allocated (+ (var-get total-funding-allocated) initial-funding))
        
        (ok project-id)
    )
)

;; Add researcher to project
(define-public (add-researcher (project-id uint) (researcher principal) (role uint) 
                               (expertise (string-ascii 128)) (allocation-percentage uint))
    (let (
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR_PROJECT_NOT_FOUND))
        (pi (get principal-investigator project))
        (current-count (get researcher-count project))
        (caller tx-sender)
    )
        ;; Validate authorization (only PI can add researchers)
        (asserts! (is-eq caller pi) ERR_NOT_AUTHORIZED)
        ;; Validate project is active
        (asserts! (is-eq (get status project) PROJECT_STATUS_ACTIVE) ERR_PROJECT_NOT_ACTIVE)
        ;; Validate role
        (asserts! (and (>= role u1) (<= role u5)) ERR_INVALID_ROLE)
        ;; Validate researcher limit
        (asserts! (< current-count MAX_RESEARCHERS_PER_PROJECT) ERR_INVALID_PARAMETERS)
        ;; Validate researcher not already in project
        (asserts! (is-none (map-get? project-researchers { project-id: project-id, researcher: researcher })) ERR_RESEARCHER_ALREADY_EXISTS)
        ;; Validate allocation percentage
        (asserts! (<= allocation-percentage u100) ERR_INVALID_PARAMETERS)
        
        ;; Add researcher
        (map-set project-researchers
            { project-id: project-id, researcher: researcher }
            {
                role: role,
                joined-date: block-height,
                contribution-score: u0,
                is-active: true,
                expertise: expertise,
                allocation-percentage: allocation-percentage
            }
        )
        
        ;; Update researcher count
        (map-set research-projects
            { project-id: project-id }
            (merge project { researcher-count: (+ current-count u1) })
        )
        
        (ok true)
    )
)

;; Create project milestone
(define-public (create-milestone (project-id uint) (title (string-ascii 128)) (description (string-ascii 256))
                                 (target-date uint) (funding-allocation uint) (deliverables (string-ascii 256))
                                 (responsible-researcher principal))
    (let (
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR_PROJECT_NOT_FOUND))
        (pi (get principal-investigator project))
        (milestone-id (+ (get milestone-count project) u1))
        (caller tx-sender)
    )
        ;; Validate authorization
        (asserts! (is-eq caller pi) ERR_NOT_AUTHORIZED)
        ;; Validate project is active
        (asserts! (is-eq (get status project) PROJECT_STATUS_ACTIVE) ERR_PROJECT_NOT_ACTIVE)
        ;; Validate responsible researcher is in project
        (asserts! (is-some (map-get? project-researchers { project-id: project-id, researcher: responsible-researcher })) ERR_RESEARCHER_NOT_FOUND)
        ;; Validate funding available
        (asserts! (<= funding-allocation (get remaining-funding project)) ERR_INSUFFICIENT_FUNDING)
        ;; Validate parameters
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> target-date block-height) ERR_INVALID_PARAMETERS)
        
        ;; Create milestone
        (map-set project-milestones
            { project-id: project-id, milestone-id: milestone-id }
            {
                title: title,
                description: description,
                target-date: target-date,
                completion-date: none,
                status: MILESTONE_STATUS_PENDING,
                funding-allocation: funding-allocation,
                deliverables: deliverables,
                responsible-researcher: responsible-researcher,
                created-by: caller,
                created-at: block-height
            }
        )
        
        ;; Update project milestone count and funding
        (map-set research-projects
            { project-id: project-id }
            (merge project {
                milestone-count: milestone-id,
                allocated-funding: (+ (get allocated-funding project) funding-allocation),
                remaining-funding: (- (get remaining-funding project) funding-allocation)
            })
        )
        
        (ok milestone-id)
    )
)

;; Complete milestone
(define-public (complete-milestone (project-id uint) (milestone-id uint) (completion-notes (string-ascii 256)))
    (let (
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR_PROJECT_NOT_FOUND))
        (milestone (unwrap! (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
        (responsible-researcher (get responsible-researcher milestone))
        (pi (get principal-investigator project))
        (caller tx-sender)
    )
        ;; Validate authorization (either PI or responsible researcher)
        (asserts! (or (is-eq caller pi) (is-eq caller responsible-researcher)) ERR_NOT_AUTHORIZED)
        ;; Validate milestone not already completed
        (asserts! (not (is-eq (get status milestone) MILESTONE_STATUS_COMPLETED)) ERR_MILESTONE_ALREADY_COMPLETED)
        ;; Validate parameters
        (asserts! (> (len completion-notes) u0) ERR_INVALID_PARAMETERS)
        
        ;; Update milestone status
        (map-set project-milestones
            { project-id: project-id, milestone-id: milestone-id }
            (merge milestone {
                status: MILESTONE_STATUS_COMPLETED,
                completion-date: (some block-height)
            })
        )
        
        (ok true)
    )
)

;; Allocate funding to specific purpose
(define-public (allocate-funding (project-id uint) (amount uint) (purpose (string-ascii 128)) 
                                 (milestone-id (optional uint)))
    (let (
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR_PROJECT_NOT_FOUND))
        (pi (get principal-investigator project))
        (allocation-id (+ (default-to u0 (get count (map-get? allocation-counters { project-id: project-id }))) u1))
        (caller tx-sender)
    )
        ;; Validate authorization
        (asserts! (is-eq caller pi) ERR_NOT_AUTHORIZED)
        ;; Validate funding available
        (asserts! (<= amount (get remaining-funding project)) ERR_INSUFFICIENT_FUNDING)
        ;; Validate parameters
        (asserts! (> amount u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len purpose) u0) ERR_INVALID_PARAMETERS)
        
        ;; Create funding allocation
        (map-set funding-allocations
            { project-id: project-id, allocation-id: allocation-id }
            {
                amount: amount,
                purpose: purpose,
                allocated-by: caller,
                allocation-date: block-height,
                is-released: false,
                milestone-id: milestone-id
            }
        )
        
        ;; Update allocation counter
        (map-set allocation-counters { project-id: project-id } { count: allocation-id })
        
        ;; Update project funding
        (map-set research-projects
            { project-id: project-id }
            (merge project {
                allocated-funding: (+ (get allocated-funding project) amount),
                remaining-funding: (- (get remaining-funding project) amount)
            })
        )
        
        (ok allocation-id)
    )
)

;; Activate project (change status to active)
(define-public (activate-project (project-id uint))
    (let (
        (project (unwrap! (map-get? research-projects { project-id: project-id }) ERR_PROJECT_NOT_FOUND))
        (pi (get principal-investigator project))
        (caller tx-sender)
    )
        ;; Validate authorization
        (asserts! (is-eq caller pi) ERR_NOT_AUTHORIZED)
        ;; Validate project status
        (asserts! (is-eq (get status project) PROJECT_STATUS_PROPOSED) ERR_INVALID_PARAMETERS)
        
        ;; Activate project
        (map-set research-projects
            { project-id: project-id }
            (merge project { status: PROJECT_STATUS_ACTIVE })
        )
        
        (ok true)
    )
)

;; read only functions
;;

;; Get project details
(define-read-only (get-project (project-id uint))
    (map-get? research-projects { project-id: project-id })
)

;; Get researcher details in project
(define-read-only (get-project-researcher (project-id uint) (researcher principal))
    (map-get? project-researchers { project-id: project-id, researcher: researcher })
)

;; Get milestone details
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
    (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Get funding allocation details
(define-read-only (get-funding-allocation (project-id uint) (allocation-id uint))
    (map-get? funding-allocations { project-id: project-id, allocation-id: allocation-id })
)

;; Get project counter
(define-read-only (get-project-counter)
    (var-get project-counter)
)

;; Get total funding allocated across all projects
(define-read-only (get-total-funding)
    (var-get total-funding-allocated)
)

;; Check if user is project member
(define-read-only (is-project-member (project-id uint) (user principal))
    (is-some (map-get? project-researchers { project-id: project-id, researcher: user }))
)

;; Get role name helper
(define-read-only (get-role-name (role uint))
    (if (is-eq role ROLE_PRINCIPAL_INVESTIGATOR)
        "Principal Investigator"
        (if (is-eq role ROLE_RESEARCHER)
            "Researcher"
            (if (is-eq role ROLE_POSTDOC)
                "Postdoc"
                (if (is-eq role ROLE_GRAD_STUDENT)
                    "Graduate Student"
                    (if (is-eq role ROLE_COLLABORATOR)
                        "Collaborator"
                        "Unknown"
                    )
                )
            )
        )
    )
)

;; Get project status name helper
(define-read-only (get-project-status-name (status uint))
    (if (is-eq status PROJECT_STATUS_PROPOSED)
        "Proposed"
        (if (is-eq status PROJECT_STATUS_ACTIVE)
            "Active"
            (if (is-eq status PROJECT_STATUS_COMPLETED)
                "Completed"
                (if (is-eq status PROJECT_STATUS_CANCELLED)
                    "Cancelled"
                    "Unknown"
                )
            )
        )
    )
)

;; private functions
;;

;; Validate project exists and is active
(define-private (is-project-active (project-id uint))
    (match (map-get? research-projects { project-id: project-id })
        project (is-eq (get status project) PROJECT_STATUS_ACTIVE)
        false
    )
)

;; Check if user is principal investigator
(define-private (is-principal-investigator (project-id uint) (user principal))
    (match (map-get? research-projects { project-id: project-id })
        project (is-eq (get principal-investigator project) user)
        false
    )
)

;; Calculate project completion percentage
(define-private (calculate-completion-percentage (project-id uint))
    (let (
        (project (unwrap-panic (map-get? research-projects { project-id: project-id })))
        (total-milestones (get milestone-count project))
    )
        (if (is-eq total-milestones u0)
            u0
            ;; This is a simplified calculation - in practice you'd iterate through milestones
            (/ (* (get allocated-funding project) u100) (get total-funding project))
        )
    )
)
