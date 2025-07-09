(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DISPUTE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-NOT-JUROR (err u105))
(define-constant ERR-DISPUTE-EXPIRED (err u106))

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
