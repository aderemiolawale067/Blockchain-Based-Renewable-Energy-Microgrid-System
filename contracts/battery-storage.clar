;; Battery Storage Coordination Contract
;; Manages community energy storage systems

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-BATTERY-NOT-FOUND (err u401))
(define-constant ERR-BATTERY-ALREADY-EXISTS (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-INSUFFICIENT-CAPACITY (err u404))
(define-constant ERR-BATTERY-BUSY (err u405))
(define-constant ERR-CHARGING-LIMIT-EXCEEDED (err u406))

;; Data Variables
(define-data-var total-batteries uint u0)
(define-data-var total-capacity uint u0)
(define-data-var total-stored-energy uint u0)
(define-data-var emergency-reserve-percentage uint u25) ;; 25% reserve
(define-data-var default-efficiency uint u95) ;; 95% efficiency

;; Data Maps
(define-map batteries
  { battery-id: (string-ascii 64) }
  {
    owner: principal,
    capacity: uint,
    current-charge: uint,
    charge-rate: uint,
    discharge-rate: uint,
    efficiency: uint,
    status: (string-ascii 16),
    cycles: uint,
    last-maintenance: uint
  }
)

(define-map charging-sessions
  { battery-id: (string-ascii 64), session-id: uint }
  {
    start-time: uint,
    end-time: uint,
    energy-amount: uint,
    source: (string-ascii 32),
    status: (string-ascii 16),
    efficiency-achieved: uint
  }
)

(define-map discharging-sessions
  { battery-id: (string-ascii 64), session-id: uint }
  {
    start-time: uint,
    end-time: uint,
    energy-amount: uint,
    destination: (string-ascii 32),
    status: (string-ascii 16),
    efficiency-achieved: uint
  }
)

(define-map battery-health
  { battery-id: (string-ascii 64) }
  {
    health-percentage: uint,
    degradation-rate: uint,
    temperature-avg: uint,
    voltage-stability: uint,
    last-health-check: uint
  }
)

(define-map grid-services
  { battery-id: (string-ascii 64) }
  {
    frequency-regulation: bool,
    voltage-support: bool,
    peak-shaving: bool,
    load-following: bool,
    services-revenue: uint
  }
)

;; Public Functions

;; Register a battery storage system
(define-public (register-battery (battery-id (string-ascii 64))
                                (capacity uint)
                                (charge-rate uint)
                                (discharge-rate uint))
  (begin
    (asserts! (> capacity u0) ERR-INVALID-INPUT)
    (asserts! (> charge-rate u0) ERR-INVALID-INPUT)
    (asserts! (> discharge-rate u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? batteries { battery-id: battery-id })) ERR-BATTERY-ALREADY-EXISTS)

    (map-set batteries
      { battery-id: battery-id }
      {
        owner: tx-sender,
        capacity: capacity,
        current-charge: u0,
        charge-rate: charge-rate,
        discharge-rate: discharge-rate,
        efficiency: (var-get default-efficiency),
        status: "idle",
        cycles: u0,
        last-maintenance: block-height
      }
    )

    (map-set battery-health
      { battery-id: battery-id }
      {
        health-percentage: u100,
        degradation-rate: u1,
        temperature-avg: u25,
        voltage-stability: u100,
        last-health-check: block-height
      }
    )

    (map-set grid-services
      { battery-id: battery-id }
      {
        frequency-regulation: false,
        voltage-support: false,
        peak-shaving: false,
        load-following: false,
        services-revenue: u0
      }
    )

    (var-set total-batteries (+ (var-get total-batteries) u1))
    (var-set total-capacity (+ (var-get total-capacity) capacity))
    (ok battery-id)
  )
)

;; Start charging session
(define-public (start-charging (battery-id (string-ascii 64))
                              (energy-amount uint)
                              (source (string-ascii 32)))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND))
        (session-id (get-next-session-id battery-id)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status battery) "idle") ERR-BATTERY-BUSY)
    (asserts! (> energy-amount u0) ERR-INVALID-INPUT)

    ;; Check if battery has capacity for charging
    (let ((available-capacity (- (get capacity battery) (get current-charge battery))))
      (asserts! (<= energy-amount available-capacity) ERR-INSUFFICIENT-CAPACITY)
    )

    ;; Check charging rate limits
    (asserts! (<= energy-amount (get charge-rate battery)) ERR-CHARGING-LIMIT-EXCEEDED)

    (map-set batteries
      { battery-id: battery-id }
      (merge battery { status: "charging" })
    )

    (map-set charging-sessions
      { battery-id: battery-id, session-id: session-id }
      {
        start-time: block-height,
        end-time: u0,
        energy-amount: energy-amount,
        source: source,
        status: "active",
        efficiency-achieved: u0
      }
    )

    (ok session-id)
  )
)

;; Complete charging session
(define-public (complete-charging (battery-id (string-ascii 64)) (session-id uint))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND))
        (session (unwrap! (map-get? charging-sessions { battery-id: battery-id, session-id: session-id }) ERR-INVALID-INPUT)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status session) "active") ERR-INVALID-INPUT)

    (let ((actual-energy (/ (* (get energy-amount session) (get efficiency battery)) u100))
          (new-charge (+ (get current-charge battery) actual-energy)))

      ;; Update battery state
      (map-set batteries
        { battery-id: battery-id }
        (merge battery {
          current-charge: new-charge,
          status: "idle",
          cycles: (+ (get cycles battery) u1)
        })
      )

      ;; Complete charging session
      (map-set charging-sessions
        { battery-id: battery-id, session-id: session-id }
        (merge session {
          end-time: block-height,
          status: "completed",
          efficiency-achieved: (get efficiency battery)
        })
      )

      (var-set total-stored-energy (+ (var-get total-stored-energy) actual-energy))
      (ok actual-energy)
    )
  )
)

;; Start discharging session
(define-public (start-discharging (battery-id (string-ascii 64))
                                 (energy-amount uint)
                                 (destination (string-ascii 32)))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND))
        (session-id (get-next-session-id battery-id)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status battery) "idle") ERR-BATTERY-BUSY)
    (asserts! (> energy-amount u0) ERR-INVALID-INPUT)

    ;; Check available energy (considering emergency reserve)
    (let ((reserve-amount (/ (* (get capacity battery) (var-get emergency-reserve-percentage)) u100))
          (available-energy (- (get current-charge battery) reserve-amount)))
      (asserts! (>= available-energy energy-amount) ERR-INSUFFICIENT-CAPACITY)
    )

    ;; Check discharge rate limits
    (asserts! (<= energy-amount (get discharge-rate battery)) ERR-CHARGING-LIMIT-EXCEEDED)

    (map-set batteries
      { battery-id: battery-id }
      (merge battery { status: "discharging" })
    )

    (map-set discharging-sessions
      { battery-id: battery-id, session-id: session-id }
      {
        start-time: block-height,
        end-time: u0,
        energy-amount: energy-amount,
        destination: destination,
        status: "active",
        efficiency-achieved: u0
      }
    )

    (ok session-id)
  )
)

;; Complete discharging session
(define-public (complete-discharging (battery-id (string-ascii 64)) (session-id uint))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND))
        (session (unwrap! (map-get? discharging-sessions { battery-id: battery-id, session-id: session-id }) ERR-INVALID-INPUT)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status session) "active") ERR-INVALID-INPUT)

    (let ((energy-delivered (/ (* (get energy-amount session) (get efficiency battery)) u100))
          (new-charge (- (get current-charge battery) (get energy-amount session))))

      ;; Update battery state
      (map-set batteries
        { battery-id: battery-id }
        (merge battery {
          current-charge: new-charge,
          status: "idle",
          cycles: (+ (get cycles battery) u1)
        })
      )

      ;; Complete discharging session
      (map-set discharging-sessions
        { battery-id: battery-id, session-id: session-id }
        (merge session {
          end-time: block-height,
          status: "completed",
          efficiency-achieved: (get efficiency battery)
        })
      )

      (var-set total-stored-energy (- (var-get total-stored-energy) (get energy-amount session)))
      (ok energy-delivered)
    )
  )
)

;; Update battery health metrics
(define-public (update-battery-health (battery-id (string-ascii 64))
                                     (health-percentage uint)
                                     (temperature uint)
                                     (voltage-stability uint))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= health-percentage u100) ERR-INVALID-INPUT)
    (asserts! (<= voltage-stability u100) ERR-INVALID-INPUT)

    (map-set battery-health
      { battery-id: battery-id }
      {
        health-percentage: health-percentage,
        degradation-rate: (calculate-degradation-rate (get cycles battery)),
        temperature-avg: temperature,
        voltage-stability: voltage-stability,
        last-health-check: block-height
      }
    )
    (ok true)
  )
)

;; Enable grid services
(define-public (enable-grid-service (battery-id (string-ascii 64)) (service-type (string-ascii 32)))
  (let ((battery (unwrap! (map-get? batteries { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND))
        (services (unwrap! (map-get? grid-services { battery-id: battery-id }) ERR-BATTERY-NOT-FOUND)))
    (asserts! (is-eq (get owner battery) tx-sender) ERR-NOT-AUTHORIZED)

    (let ((updated-services
           (if (is-eq service-type "frequency-regulation")
             (merge services { frequency-regulation: true })
             (if (is-eq service-type "voltage-support")
               (merge services { voltage-support: true })
               (if (is-eq service-type "peak-shaving")
                 (merge services { peak-shaving: true })
                 (merge services { load-following: true }))))))

      (map-set grid-services
        { battery-id: battery-id }
        updated-services
      )
      (ok service-type)
    )
  )
)

;; Update emergency reserve percentage
(define-public (update-emergency-reserve (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-percentage u50) ERR-INVALID-INPUT)
    (var-set emergency-reserve-percentage new-percentage)
    (ok new-percentage)
  )
)

;; Private Functions

;; Get next session ID
(define-private (get-next-session-id (battery-id (string-ascii 64)))
  u1 ;; Simplified - in production would track per battery
)

;; Calculate degradation rate based on cycles
(define-private (calculate-degradation-rate (cycles uint))
  (if (< cycles u1000)
    u1
    (if (< cycles u5000)
      u2
      u3))
)

;; Read-only Functions

;; Get battery information
(define-read-only (get-battery (battery-id (string-ascii 64)))
  (map-get? batteries { battery-id: battery-id })
)

;; Get charging session
(define-read-only (get-charging-session (battery-id (string-ascii 64)) (session-id uint))
  (map-get? charging-sessions { battery-id: battery-id, session-id: session-id })
)

;; Get discharging session
(define-read-only (get-discharging-session (battery-id (string-ascii 64)) (session-id uint))
  (map-get? discharging-sessions { battery-id: battery-id, session-id: session-id })
)

;; Get battery health
(define-read-only (get-battery-health (battery-id (string-ascii 64)))
  (map-get? battery-health { battery-id: battery-id })
)

;; Get grid services info
(define-read-only (get-grid-services (battery-id (string-ascii 64)))
  (map-get? grid-services { battery-id: battery-id })
)

;; Get system storage statistics
(define-read-only (get-storage-stats)
  {
    total-batteries: (var-get total-batteries),
    total-capacity: (var-get total-capacity),
    total-stored-energy: (var-get total-stored-energy),
    emergency-reserve-percentage: (var-get emergency-reserve-percentage),
    default-efficiency: (var-get default-efficiency)
  }
)

;; Calculate available storage capacity
(define-read-only (get-available-capacity (battery-id (string-ascii 64)))
  (match (map-get? batteries { battery-id: battery-id })
    battery (- (get capacity battery) (get current-charge battery))
    u0
  )
)

;; Calculate state of charge percentage
(define-read-only (get-state-of-charge (battery-id (string-ascii 64)))
  (match (map-get? batteries { battery-id: battery-id })
    battery (/ (* (get current-charge battery) u100) (get capacity battery))
    u0
  )
)

;; Check if battery needs maintenance
(define-read-only (needs-maintenance (battery-id (string-ascii 64)))
  (match (map-get? batteries { battery-id: battery-id })
    battery (> (- block-height (get last-maintenance battery)) u8760) ;; 1 year
    false
  )
)

;; Get emergency reserve amount
(define-read-only (get-emergency-reserve (battery-id (string-ascii 64)))
  (match (map-get? batteries { battery-id: battery-id })
    battery (/ (* (get capacity battery) (var-get emergency-reserve-percentage)) u100)
    u0
  )
)
