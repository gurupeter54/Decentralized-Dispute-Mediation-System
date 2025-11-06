(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DISPUTE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-NOT-JUROR (err u105))
(define-constant ERR-DISPUTE-EXPIRED (err u106))

(define-constant ERR-EVIDENCE-ALREADY-EXISTS (err u107))
(define-constant ERR-EVIDENCE-DEADLINE-PASSED (err u108))
(define-constant ERR-INVALID-HASH (err u109))
(define-constant ERR-EVIDENCE-NOT-FOUND (err u110))

(define-constant ERR-INSUFFICIENT-STAKE (err u111))
(define-constant ERR-ARBITRATOR-NOT-STAKED (err u112))
(define-constant ERR-STAKE-LOCKED (err u113))

(define-constant ERR-APPEAL-WINDOW-CLOSED (err u114))
(define-constant ERR-ALREADY-APPEALED (err u115))
(define-constant ERR-INSUFFICIENT-APPEAL-BOND (err u116))

(define-constant ERR-TEMPLATE-NOT-FOUND (err u117))
(define-constant ERR-INVALID-TEMPLATE (err u118))

(define-data-var template-counter uint u0)

(define-data-var appeal-window-blocks uint u72)
(define-data-var appeal-bond-multiplier uint u2)

(define-data-var minimum-arbitrator-stake uint u5000000)
(define-data-var stake-lock-duration uint u1008)
(define-data-var penalty-rate uint u10)
(define-data-var reward-rate uint u5)

(define-data-var evidence-deadline-blocks uint u72)

(define-data-var dispute-counter uint u0)
(define-data-var juror-pool-size uint u0)
(define-data-var dispute-fee uint u1000000)
(define-data-var voting-duration uint u144)

(define-map disputes
  uint
  {
    plaintiff: principal,
    defendant: principal,
    arbitrator: principal,
    amount: uint,
    description: (string-utf8 500),
    status: (string-ascii 20),
    created-at: uint,
    jurors: (list 5 principal),
    votes-for: uint,
    votes-against: uint,
    resolved-at: (optional uint)
  }
)

(define-map juror-pool principal bool)
(define-map dispute-votes { dispute-id: uint, juror: principal } bool)
(define-map arbitrator-ratings principal uint)

(define-public (register-as-juror)
  (begin
    (map-set juror-pool tx-sender true)
    (var-set juror-pool-size (+ (var-get juror-pool-size) u1))
    (ok true)
  )
)

(define-public (unregister-as-juror)
  (begin
    (asserts! (is-some (map-get? juror-pool tx-sender)) ERR-NOT-JUROR)
    (map-delete juror-pool tx-sender)
    (var-set juror-pool-size (- (var-get juror-pool-size) u1))
    (ok true)
  )
)

(define-public (create-dispute (defendant principal) (arbitrator principal) (description (string-utf8 500)))
  (let ((dispute-id (+ (var-get dispute-counter) u1))
        (current-block stacks-block-height)
        (selected-jurors (select-random-jurors)))
    (asserts! (>= (stx-get-balance tx-sender) (var-get dispute-fee)) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? (var-get dispute-fee) tx-sender (as-contract tx-sender)))
    (map-set disputes dispute-id {
      plaintiff: tx-sender,
      defendant: defendant,
      arbitrator: arbitrator,
      amount: (var-get dispute-fee),
      description: description,
      status: "pending",
      created-at: current-block,
      jurors: selected-jurors,
      votes-for: u0,
      votes-against: u0,
      resolved-at: none
    })
    (var-set dispute-counter dispute-id)
    (ok dispute-id)
  )
)

(define-public (cast-vote (dispute-id uint) (vote-for bool))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (current-block stacks-block-height)
        (vote-key {dispute-id: dispute-id, juror: tx-sender}))
    (asserts! (is-eq (get status dispute) "pending") ERR-INVALID-STATUS)
    (asserts! (< current-block (+ (get created-at dispute) (var-get voting-duration))) ERR-DISPUTE-EXPIRED)
    (asserts! (is-some (index-of (get jurors dispute) tx-sender)) ERR-NOT-JUROR)
    (asserts! (is-none (map-get? dispute-votes vote-key)) ERR-ALREADY-VOTED)
    (map-set dispute-votes vote-key vote-for)
    (if vote-for
      (map-set disputes dispute-id (merge dispute {votes-for: (+ (get votes-for dispute) u1)}))
      (map-set disputes dispute-id (merge dispute {votes-against: (+ (get votes-against dispute) u1)}))
    )
    (ok true)
  )
)

(define-public (resolve-dispute (dispute-id uint))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (current-block stacks-block-height)
        (total-votes (+ (get votes-for dispute) (get votes-against dispute))))
    (asserts! (is-eq tx-sender (get arbitrator dispute)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "pending") ERR-INVALID-STATUS)
    (asserts! (>= current-block (+ (get created-at dispute) (var-get voting-duration))) ERR-DISPUTE-EXPIRED)
    (asserts! (>= total-votes u3) ERR-INVALID-STATUS)
    (let ((winner (if (> (get votes-for dispute) (get votes-against dispute)) "plaintiff" "defendant")))
      (map-set disputes dispute-id (merge dispute {
        status: winner,
        resolved-at: (some current-block)
      }))
      (if (is-eq winner "plaintiff")
        (try! (as-contract (stx-transfer? (get amount dispute) tx-sender (get plaintiff dispute))))
        (try! (as-contract (stx-transfer? (get amount dispute) tx-sender (get defendant dispute))))
      )
      (update-arbitrator-rating (get arbitrator dispute) true)
      (ok winner)
    )
  )
)

(define-public (emergency-resolve (dispute-id uint) (winner (string-ascii 20)))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status dispute) "pending") ERR-INVALID-STATUS)
    (map-set disputes dispute-id (merge dispute {
      status: winner,
      resolved-at: (some stacks-block-height)
    }))
    (if (is-eq winner "plaintiff")
      (try! (as-contract (stx-transfer? (get amount dispute) tx-sender (get plaintiff dispute))))
      (try! (as-contract (stx-transfer? (get amount dispute) tx-sender (get defendant dispute))))
    )
    (ok winner)
  )
)

(define-public (set-dispute-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set dispute-fee new-fee)
    (ok true)
  )
)

(define-public (set-voting-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set voting-duration new-duration)
    (ok true)
  )
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

(define-read-only (get-dispute-vote (dispute-id uint) (juror principal))
  (map-get? dispute-votes {dispute-id: dispute-id, juror: juror})
)

(define-read-only (is-juror (address principal))
  (default-to false (map-get? juror-pool address))
)

(define-read-only (get-arbitrator-rating (arbitrator principal))
  (default-to u0 (map-get? arbitrator-ratings arbitrator))
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-dispute-fee)
  (var-get dispute-fee)
)

(define-read-only (get-voting-duration)
  (var-get voting-duration)
)

(define-read-only (get-juror-pool-size)
  (var-get juror-pool-size)
)

(define-private (select-random-jurors)
  (list tx-sender tx-sender tx-sender tx-sender tx-sender)
)

(define-private (update-arbitrator-rating (arbitrator principal) (successful bool))
  (let ((current-rating (default-to u0 (map-get? arbitrator-ratings arbitrator))))
    (map-set arbitrator-ratings arbitrator 
      (if successful (+ current-rating u1) current-rating))
  )
)

(define-map evidence-storage
  { dispute-id: uint, submitter: principal, evidence-index: uint }
  {
    hash: (buff 32),
    description: (string-utf8 200),
    submitted-at: uint,
    evidence-type: (string-ascii 10)
  }
)

(define-map dispute-evidence-count uint uint)

(define-public (submit-evidence 
  (dispute-id uint) 
  (evidence-hash (buff 32)) 
  (description (string-utf8 200)) 
  (evidence-type (string-ascii 10)))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (current-block stacks-block-height)
        (evidence-count (default-to u0 (map-get? dispute-evidence-count dispute-id)))
        (evidence-key { dispute-id: dispute-id, submitter: tx-sender, evidence-index: evidence-count }))
    (asserts! (is-eq (get status dispute) "pending") ERR-INVALID-STATUS)
    (asserts! (< current-block (+ (get created-at dispute) (var-get evidence-deadline-blocks))) ERR-EVIDENCE-DEADLINE-PASSED)
    (asserts! (> (len evidence-hash) u0) ERR-INVALID-HASH)
    (asserts! (or (is-eq tx-sender (get plaintiff dispute)) (is-eq tx-sender (get defendant dispute))) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? evidence-storage evidence-key)) ERR-EVIDENCE-ALREADY-EXISTS)
    (map-set evidence-storage evidence-key {
      hash: evidence-hash,
      description: description,
      submitted-at: current-block,
      evidence-type: evidence-type
    })
    (map-set dispute-evidence-count dispute-id (+ evidence-count u1))
    (ok evidence-count)
  )
)

(define-public (set-evidence-deadline (new-deadline uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set evidence-deadline-blocks new-deadline)
    (ok true)
  )
)

(define-read-only (get-evidence (dispute-id uint) (submitter principal) (evidence-index uint))
  (map-get? evidence-storage { dispute-id: dispute-id, submitter: submitter, evidence-index: evidence-index })
)

(define-read-only (get-dispute-evidence-count (dispute-id uint))
  (default-to u0 (map-get? dispute-evidence-count dispute-id))
)

(define-read-only (verify-evidence-hash (dispute-id uint) (submitter principal) (evidence-index uint) (provided-hash (buff 32)))
  (let ((evidence (map-get? evidence-storage { dispute-id: dispute-id, submitter: submitter, evidence-index: evidence-index })))
    (match evidence
      stored-evidence (is-eq (get hash stored-evidence) provided-hash)
      false
    )
  )
)

(define-read-only (get-evidence-deadline)
  (var-get evidence-deadline-blocks)
)


(define-map arbitrator-stakes
  principal
  {
    amount: uint,
    locked-until: uint,
    disputes-handled: uint,
    successful-resolutions: uint,
    total-earned: uint,
    total-penalized: uint
  }
)

(define-map dispute-arbitrator-rewards uint uint)

(define-public (stake-as-arbitrator (amount uint))
  (let ((current-stake (default-to {amount: u0, locked-until: u0, disputes-handled: u0, 
                                   successful-resolutions: u0, total-earned: u0, 
                                   total-penalized: u0} 
                                  (map-get? arbitrator-stakes tx-sender)))
        (total-stake (+ (get amount current-stake) amount)))
    (asserts! (>= total-stake (var-get minimum-arbitrator-stake)) ERR-INSUFFICIENT-STAKE)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set arbitrator-stakes tx-sender 
      (merge current-stake {amount: total-stake}))
    (ok total-stake)
  )
)

(define-public (unstake-arbitrator)
  (let ((stake-data (unwrap! (map-get? arbitrator-stakes tx-sender) ERR-ARBITRATOR-NOT-STAKED))
        (current-block stacks-block-height))
    (asserts! (< (get locked-until stake-data) current-block) ERR-STAKE-LOCKED)
    (try! (as-contract (stx-transfer? (get amount stake-data) tx-sender tx-sender)))
    (map-delete arbitrator-stakes tx-sender)
    (ok (get amount stake-data))
  )
)

(define-public (process-arbitrator-performance (dispute-id uint) (performance-score uint))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (arbitrator (get arbitrator dispute))
        (stake-data (unwrap! (map-get? arbitrator-stakes arbitrator) ERR-ARBITRATOR-NOT-STAKED))
        (amount (get amount dispute))
        (reward-amount (/ (* amount (var-get reward-rate)) u100))
        (penalty-amount (/ (* amount (var-get penalty-rate)) u100)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (if (>= performance-score u70)
      (begin
        (try! (as-contract (stx-transfer? reward-amount tx-sender arbitrator)))
        (map-set arbitrator-stakes arbitrator
          (merge stake-data {
            disputes-handled: (+ (get disputes-handled stake-data) u1),
            successful-resolutions: (+ (get successful-resolutions stake-data) u1),
            total-earned: (+ (get total-earned stake-data) reward-amount)
          }))
        (map-set dispute-arbitrator-rewards dispute-id reward-amount))
      (begin
        (let ((penalty (if (> performance-score u70) penalty-amount (get amount stake-data))))
          (map-set arbitrator-stakes arbitrator
            (merge stake-data {
              amount: (- (get amount stake-data) penalty),
              disputes-handled: (+ (get disputes-handled stake-data) u1),
              total-penalized: (+ (get total-penalized stake-data) penalty),
              locked-until: (+ stacks-block-height (var-get stake-lock-duration))
            }))
          (map-set dispute-arbitrator-rewards dispute-id u0))))
    (ok performance-score)
  )
)

(define-read-only (get-arbitrator-stake (arbitrator principal))
  (map-get? arbitrator-stakes arbitrator)
)

(define-read-only (get-arbitrator-reputation (arbitrator principal))
  (let ((stake-data (map-get? arbitrator-stakes arbitrator)))
    (match stake-data
      data (if (> (get disputes-handled data) u0)
             (/ (* (get successful-resolutions data) u100) (get disputes-handled data))
             u0)
      u0)
  )
)

(define-read-only (is-qualified-arbitrator (arbitrator principal))
  (let ((stake-data (map-get? arbitrator-stakes arbitrator)))
    (match stake-data
      data (and (>= (get amount data) (var-get minimum-arbitrator-stake))
               (< (get locked-until data) stacks-block-height))
      false)
  )
)

(define-map dispute-appeals uint {
  appealed-by: principal,
  appeal-bond: uint,
  appealed-at: uint,
  new-jurors: (list 5 principal),
  appeal-votes-for: uint,
  appeal-votes-against: uint,
  appeal-resolved: bool
})

(define-map appeal-votes { dispute-id: uint, juror: principal } bool)

(define-public (appeal-dispute (dispute-id uint))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (current-block stacks-block-height)
        (appeal-bond (* (get amount dispute) (var-get appeal-bond-multiplier)))
        (selected-jurors (select-random-jurors)))
    (asserts! (is-some (get resolved-at dispute)) ERR-INVALID-STATUS)
    (asserts! (< current-block (+ (unwrap-panic (get resolved-at dispute)) (var-get appeal-window-blocks))) ERR-APPEAL-WINDOW-CLOSED)
    (asserts! (is-none (map-get? dispute-appeals dispute-id)) ERR-ALREADY-APPEALED)
    (asserts! (or (is-eq tx-sender (get plaintiff dispute)) (is-eq tx-sender (get defendant dispute))) ERR-UNAUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) appeal-bond) ERR-INSUFFICIENT-APPEAL-BOND)
    (try! (stx-transfer? appeal-bond tx-sender (as-contract tx-sender)))
    (map-set dispute-appeals dispute-id {
      appealed-by: tx-sender,
      appeal-bond: appeal-bond,
      appealed-at: current-block,
      new-jurors: selected-jurors,
      appeal-votes-for: u0,
      appeal-votes-against: u0,
      appeal-resolved: false
    })
    (ok appeal-bond)
  )
)

(define-public (cast-appeal-vote (dispute-id uint) (vote-for bool))
  (let ((appeal (unwrap! (map-get? dispute-appeals dispute-id) ERR-DISPUTE-NOT-FOUND))
        (vote-key {dispute-id: dispute-id, juror: tx-sender}))
    (asserts! (is-some (index-of (get new-jurors appeal) tx-sender)) ERR-NOT-JUROR)
    (asserts! (is-none (map-get? appeal-votes vote-key)) ERR-ALREADY-VOTED)
    (asserts! (is-eq (get appeal-resolved appeal) false) ERR-INVALID-STATUS)
    (map-set appeal-votes vote-key vote-for)
    (if vote-for
      (map-set dispute-appeals dispute-id (merge appeal {appeal-votes-for: (+ (get appeal-votes-for appeal) u1)}))
      (map-set dispute-appeals dispute-id (merge appeal {appeal-votes-against: (+ (get appeal-votes-against appeal) u1)}))
    )
    (ok true)
  )
)

(define-public (resolve-appeal (dispute-id uint))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
        (appeal (unwrap! (map-get? dispute-appeals dispute-id) ERR-DISPUTE-NOT-FOUND))
        (original-winner (get status dispute))
        (appeal-winner (if (> (get appeal-votes-for appeal) (get appeal-votes-against appeal)) "plaintiff" "defendant")))
    (asserts! (is-eq (get appeal-resolved appeal) false) ERR-INVALID-STATUS)
    (map-set dispute-appeals dispute-id (merge appeal {appeal-resolved: true}))
    (if (is-eq appeal-winner original-winner)
      (try! (as-contract (stx-transfer? (get appeal-bond appeal) tx-sender (get appealed-by appeal))))
      (begin
        (map-set disputes dispute-id (merge dispute {status: appeal-winner}))
        (try! (as-contract (stx-transfer? (get appeal-bond appeal) tx-sender (get appealed-by appeal))))
      )
    )
    (ok appeal-winner)
  )
)

(define-read-only (get-appeal-info (dispute-id uint))
  (map-get? dispute-appeals dispute-id)
)

(define-map dispute-templates
  uint
  {
    name: (string-ascii 30),
    base-fee: uint,
    percentage-fee: uint,
    min-fee: uint,
    max-fee: uint,
    active: bool
  }
)

(define-map dispute-template-usage uint uint)

(define-public (create-dispute-template 
  (name (string-ascii 30))
  (base-fee uint)
  (percentage-fee uint)
  (min-fee uint)
  (max-fee uint))
  (let ((template-id (+ (var-get template-counter) u1)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set dispute-templates template-id {
      name: name,
      base-fee: base-fee,
      percentage-fee: percentage-fee,
      min-fee: min-fee,
      max-fee: max-fee,
      active: true
    })
    (var-set template-counter template-id)
    (map-set dispute-template-usage template-id u0)
    (ok template-id)
  )
)

(define-public (toggle-template (template-id uint))
  (let ((template (unwrap! (map-get? dispute-templates template-id) ERR-TEMPLATE-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set dispute-templates template-id 
      (merge template {active: (not (get active template))}))
    (ok (not (get active template)))
  )
)

(define-read-only (calculate-template-fee (template-id uint) (disputed-amount uint))
  (let ((template (unwrap! (map-get? dispute-templates template-id) ERR-TEMPLATE-NOT-FOUND)))
    (let ((calculated-fee (+ (get base-fee template) 
                             (/ (* disputed-amount (get percentage-fee template)) u10000))))
      (ok (if (< calculated-fee (get min-fee template))
            (get min-fee template)
            (if (> calculated-fee (get max-fee template))
              (get max-fee template)
              calculated-fee)))
    )
  )
)

(define-read-only (get-template (template-id uint))
  (map-get? dispute-templates template-id)
)

(define-read-only (get-template-usage (template-id uint))
  (default-to u0 (map-get? dispute-template-usage template-id))
)