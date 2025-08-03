;; Energy Generation Tracking Contract
;; Monitors electricity production from renewable sources

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-DEVICE-NOT-FOUND (err u101))
(define-constant ERR-DEVICE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-DEVICE-OFFLINE (err u104))
(define-constant ERR-INSUFFICIENT-CAPACITY (err u105))

;; Data Variables
(define-data-var total-devices uint u0)
(define-data-var total-generation uint u0)
(define-data-var system-efficiency uint u95)

;; Data Maps
(define-map devices
  { device-id: (string-ascii 64) }
  {
    owner: principal,
    device-type: (string-ascii 32),
    capacity: uint,
    efficiency: uint,
    status: (string-ascii 16),
    total-generated: uint,
    last-reading: uint,
    installation-date: uint
  }
)

(define-map daily-production
  { device-id: (string-ascii 64), date: uint }
  { production: uint, peak-output: uint, hours-active: uint }
)

(define-map device-maintenance
  { device-id: (string-ascii 64) }
  { last-maintenance: uint, next-maintenance: uint, maintenance-count: uint }
)

;; Public Functions

;; Register a new renewable energy device
(define-public (register-device (device-id (string-ascii 64))
                               (device-type (string-ascii 32))
                               (capacity uint)
                               (efficiency uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> capacity u0) ERR-INVALID-INPUT)
    (asserts! (and (>= efficiency u1) (<= efficiency u100)) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? devices { device-id: device-id })) ERR-DEVICE-ALREADY-EXISTS)

    (map-set devices
      { device-id: device-id }
      {
        owner: tx-sender,
        device-type: device-type,
        capacity: capacity,
        efficiency: efficiency,
        status: "active",
        total-generated: u0,
        last-reading: u0,
        installation-date: block-height
      }
    )

    (map-set device-maintenance
      { device-id: device-id }
      { last-maintenance: block-height, next-maintenance: (+ block-height u8760), maintenance-count: u0 }
    )

    (var-set total-devices (+ (var-get total-devices) u1))
    (ok device-id)
  )
)

;; Record energy production for a device
(define-public (record-production (device-id (string-ascii 64))
                                 (production uint)
                                 (peak-output uint)
                                 (hours-active uint))
  (let ((device (unwrap! (map-get? devices { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-eq (get owner device) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status device) "active") ERR-DEVICE-OFFLINE)
    (asserts! (<= peak-output (get capacity device)) ERR-INSUFFICIENT-CAPACITY)
    (asserts! (<= hours-active u24) ERR-INVALID-INPUT)

    (map-set devices
      { device-id: device-id }
      (merge device {
        total-generated: (+ (get total-generated device) production),
        last-reading: production
      })
    )

    (map-set daily-production
      { device-id: device-id, date: block-height }
      { production: production, peak-output: peak-output, hours-active: hours-active }
    )

    (var-set total-generation (+ (var-get total-generation) production))
    (ok production)
  )
)

;; Update device status
(define-public (update-device-status (device-id (string-ascii 64)) (new-status (string-ascii 16)))
  (let ((device (unwrap! (map-get? devices { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-eq (get owner device) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set devices
      { device-id: device-id }
      (merge device { status: new-status })
    )
    (ok new-status)
  )
)

;; Record maintenance activity
(define-public (record-maintenance (device-id (string-ascii 64)))
  (let ((device (unwrap! (map-get? devices { device-id: device-id }) ERR-DEVICE-NOT-FOUND))
        (maintenance (unwrap! (map-get? device-maintenance { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-eq (get owner device) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set device-maintenance
      { device-id: device-id }
      {
        last-maintenance: block-height,
        next-maintenance: (+ block-height u8760),
        maintenance-count: (+ (get maintenance-count maintenance) u1)
      }
    )
    (ok true)
  )
)

;; Update system efficiency
(define-public (update-system-efficiency (new-efficiency uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-efficiency u1) (<= new-efficiency u100)) ERR-INVALID-INPUT)
    (var-set system-efficiency new-efficiency)
    (ok new-efficiency)
  )
)

;; Read-only Functions

;; Get device information
(define-read-only (get-device (device-id (string-ascii 64)))
  (map-get? devices { device-id: device-id })
)

;; Get daily production data
(define-read-only (get-daily-production (device-id (string-ascii 64)) (date uint))
  (map-get? daily-production { device-id: device-id, date: date })
)

;; Get device maintenance info
(define-read-only (get-maintenance-info (device-id (string-ascii 64)))
  (map-get? device-maintenance { device-id: device-id })
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-devices: (var-get total-devices),
    total-generation: (var-get total-generation),
    system-efficiency: (var-get system-efficiency)
  }
)

;; Calculate device efficiency rating
(define-read-only (calculate-efficiency-rating (device-id (string-ascii 64)))
  (match (map-get? devices { device-id: device-id })
    device (let ((actual-efficiency (/ (* (get total-generated device) u100)
                                      (* (get capacity device) u8760))))
             (if (> actual-efficiency u0)
               (some actual-efficiency)
               (some u0)))
    none
  )
)

;; Check if device needs maintenance
(define-read-only (needs-maintenance (device-id (string-ascii 64)))
  (match (map-get? device-maintenance { device-id: device-id })
    maintenance (>= block-height (get next-maintenance maintenance))
    false
  )
)

;; Get total capacity of all active devices
(define-read-only (get-total-active-capacity)
  (var-get total-devices)
)
