import CoreBluetooth
import HealthKit
import LoopKit
import os.log
import UIKit
import UserNotifications

public protocol EquilPumpManagerDelegate: AnyObject {
    func pumpManager(_ manager: EquilPumpManager, didUpdateState state: EquilState)
    func pumpManager(_ manager: EquilPumpManager, didReceiveAlert alert: EquilAlert)
}

public class EquilPumpManager: PumpManager {
    public static let pluginIdentifier: String = "Equil"
    public static let localizedTitle = "Equil"

    private let log = OSLog(category: "EquilPumpManager")

    // State management
    private var stateLock = NSLock()
    private var _state: EquilPumpManagerState

    public var state: EquilPumpManagerState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        set {
            stateLock.lock()
            _state = newValue
            stateLock.unlock()
            stateDidChange()
        }
    }

    private var equilState: EquilState? {
        get { state.equilState }
        set {
            state.equilState = newValue
            if let newState = newValue {
                delegate?.pumpManager(self, didUpdateState: newState)
            }
        }
    }

    // BLE Manager
    private let bleManager: EquilBLEManager

    // Delegates
    public weak var pumpManagerDelegate: PumpManagerDelegate?
    public weak var delegate: EquilPumpManagerDelegate?

    // Status update timer
    private var statusUpdateTimer: Timer?
    private let statusUpdateInterval: TimeInterval = 60 // Update every minute

    // Alert management
    private var alertTimer: Timer?
    private let alertCheckInterval: TimeInterval = 30 // Check alerts every 30 seconds

    // MARK: - Initialization

    public init(state: EquilPumpManagerState) {
        _state = state
        bleManager = EquilBLEManager()

        bleManager.delegate = self

        if let address = state.equilState?.address {
            bleManager.connectToDevice(address: address)
        }

        startStatusUpdateTimer()
        startAlertCheckTimer()
    }

    deinit {
        stopStatusUpdateTimer()
        stopAlertCheckTimer()
    }

    // MARK: - PumpManager Protocol

    public var pumpRecordsBasalProfileStartEvents: Bool { false }

    public var pumpReservoirCapacity: Double { EquilPod.reservoirCapacity }

    public var lastSync: Date? {
        equilState?.lastDataTime
    }

    public var status: PumpManagerStatus {
        let device = HKDevice(
            name: "Equil",
            manufacturer: "Equil",
            model: "Equil Patch Pump",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: equilState?.serialNumber,
            udiDeviceIdentifier: nil
        )

        let basalDeliveryState: PumpManagerStatus.BasalDeliveryState

        if let state = equilState {
            if state.isSuspended {
                basalDeliveryState = .suspended(Date())
            } else if let tempRate = state.tempBasalRate,
                      let tempStart = state.tempBasalStartTime,
                      let tempDuration = state.tempBasalDuration
            {
                let endDate = tempStart.addingTimeInterval(tempDuration)
                basalDeliveryState = .tempBasal(DoseEntry(
                    type: .tempBasal,
                    startDate: tempStart,
                    endDate: endDate,
                    value: tempRate,
                    unit: .unitsPerHour,
                    deliveredUnits: nil,
                    syncIdentifier: UUID().uuidString
                ))
            } else {
                basalDeliveryState = .active(Date())
            }
        } else {
            basalDeliveryState = .active(Date())
        }

        let bolusState: PumpManagerStatus.BolusState = equilState?.bolusInProgress == true ? .inProgress : .noBolus

        return PumpManagerStatus(
            timeZone: TimeZone.current,
            device: device,
            pumpBatteryChargeRemaining: equilState?.battery.map { Double($0) / 100.0 },
            basalDeliveryState: basalDeliveryState,
            bolusState: bolusState,
            insulinType: .novolog // Default, should be configurable
        )
    }

    // MARK: - Bolus Delivery

    public func enactBolus(units: Double, automatic _: Bool, completion: @escaping (PumpManagerResult<DoseEntry>) -> Void) {
        log.info("Enacting bolus: \(units)U")

        guard let state = equilState else {
            completion(.failure(EquilError.noPumpPaired))
            return
        }

        guard !state.isSuspended else {
            completion(.failure(EquilError.pumpError("Pump is suspended")))
            return
        }

        guard state.reservoirLevel >= units else {
            completion(.failure(EquilError.pumpError("Insufficient insulin in reservoir")))
            return
        }

        let command = BolusCommand(units: units, state: state)

        // Update state to indicate bolus in progress
        equilState?.bolusInProgress = true

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                let dose = DoseEntry(
                    type: .bolus,
                    startDate: Date(),
                    value: units,
                    unit: .units,
                    deliveredUnits: units,
                    syncIdentifier: UUID().uuidString
                )

                // Update state
                self.equilState?.lastBolusAmount = units
                self.equilState?.lastBolusTime = Date()
                self.equilState?.bolusInProgress = false
                self.equilState?.updateReservoir(units: Int((self.equilState!.reservoirLevel - units) / EquilPod.pulseSize))

                self.log.info("Bolus delivered successfully")
                completion(.success(dose))

            case let .failure(error):
                self.equilState?.bolusInProgress = false
                self.log.error("Bolus failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        log.info("Canceling bolus")

        guard let state = equilState else {
            completion(.failure(EquilError.noPumpPaired))
            return
        }

        let command = CancelBolusCommand(state: state)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.equilState?.bolusInProgress = false
                self.log.info("Bolus canceled successfully")
                completion(.success(nil))

            case let .failure(error):
                self.log.error("Cancel bolus failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Temp Basal

    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (PumpManagerResult<DoseEntry>) -> Void
    ) {
        log.info("Enacting temp basal: \(unitsPerHour)U/hr for \(duration / 60) minutes")

        guard let state = equilState else {
            completion(.failure(EquilError.noPumpPaired))
            return
        }

        guard !state.isSuspended else {
            completion(.failure(EquilError.pumpError("Pump is suspended")))
            return
        }

        let command = TempBasalCommand(rate: unitsPerHour, duration: duration, state: state)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                let startDate = Date()
                let dose = DoseEntry(
                    type: .tempBasal,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(duration),
                    value: unitsPerHour,
                    unit: .unitsPerHour,
                    syncIdentifier: UUID().uuidString
                )

                // Update state
                self.equilState?.tempBasalRate = unitsPerHour
                self.equilState?.tempBasalDuration = duration
                self.equilState?.tempBasalStartTime = startDate

                self.log.info("Temp basal enacted successfully")
                completion(.success(dose))

            case let .failure(error):
                self.log.error("Temp basal failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    public func cancelTempBasal(completion: @escaping (Error?) -> Void) {
        log.info("Canceling temp basal")

        guard let state = equilState else {
            completion(EquilError.noPumpPaired)
            return
        }

        let command = TempBasalCommand(rate: 0, duration: 0, state: state, cancel: true)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Clear temp basal state
                self.equilState?.tempBasalRate = nil
                self.equilState?.tempBasalDuration = nil
                self.equilState?.tempBasalStartTime = nil

                self.log.info("Temp basal canceled successfully")
                completion(nil)

            case let .failure(error):
                self.log.error("Cancel temp basal failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    // MARK: - Suspend/Resume

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        log.info("Suspending delivery")

        guard let state = equilState else {
            completion(EquilError.noPumpPaired)
            return
        }

        let command = SuspendCommand(state: state)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.equilState?.runMode = .suspend
                self.log.info("Delivery suspended successfully")
                self.sendNotification(title: "Pump Suspended", body: "Insulin delivery has been suspended")
                completion(nil)

            case let .failure(error):
                self.log.error("Suspend failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        log.info("Resuming delivery")

        guard let state = equilState else {
            completion(EquilError.noPumpPaired)
            return
        }

        let command = ResumeCommand(state: state)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.equilState?.runMode = .run
                self.log.info("Delivery resumed successfully")
                self.sendNotification(title: "Pump Resumed", body: "Insulin delivery has been resumed")
                completion(nil)

            case let .failure(error):
                self.log.error("Resume failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    // MARK: - Status Updates

    private func startStatusUpdateTimer() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: statusUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func stopStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
    }

    private func updateStatus() {
        guard let state = equilState, bleManager.isConnected else { return }

        log.debug("Updating pump status")

        let command = StatusCommand(state: state)

        bleManager.sendCommand(command) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Update state with new values
                if let battery = command.battery {
                    self.equilState?.updateBattery(percentage: battery)
                }

                if let reservoir = command.reservoir {
                    self.equilState?.updateReservoir(units: reservoir)
                }

                if let runMode = command.runMode {
                    self.equilState?.runMode = runMode
                }

                self.log.debug("Status updated: Battery \(command.battery ?? -1)%, Reservoir \(command.reservoir ?? -1) units")

            case let .failure(error):
                self.log.error("Status update failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Alert Management

    private func startAlertCheckTimer() {
        alertTimer = Timer.scheduledTimer(withTimeInterval: alertCheckInterval, repeats: true) { [weak self] _ in
            self?.checkAlerts()
        }
    }

    private func stopAlertCheckTimer() {
        alertTimer?.invalidate()
        alertTimer = nil
    }

    private func checkAlerts() {
        guard let state = equilState else { return }

        // Check for unacknowledged alerts
        for alert in state.unacknowledgedAlerts {
            handleAlert(alert)
        }

        // Check for expiration
        if state.isExpiringSoon {
            if let timeRemaining = state.timeUntilExpiration {
                let hoursRemaining = Int(timeRemaining / 3600)
                sendNotification(
                    title: "Pump Expiring Soon",
                    body: "Your Equil pump will expire in approximately \(hoursRemaining) hours. Please prepare a replacement."
                )
            }
        }
    }

    private func handleAlert(_ alert: EquilAlert) {
        log.info("Handling alert: \(alert.rawValue)")

        delegate?.pumpManager(self, didReceiveAlert: alert)

        switch alert {
        case .reservoirLow:
            sendNotification(
                title: "Low Reservoir",
                body: "Insulin reservoir is low (\(Int(equilState?.reservoirLevel ?? 0))U remaining). Consider changing soon."
            )

        case .reservoirCritical:
            sendNotification(
                title: "Critical Reservoir",
                body: "Insulin reservoir is critically low (\(Int(equilState?.reservoirLevel ?? 0))U remaining). Change immediately!",
                sound: UNNotificationSound.defaultCritical
            )

        case .batteryLow:
            sendNotification(
                title: "Low Battery",
                body: "Pump battery is low (\(equilState?.battery ?? 0)%). Consider changing soon."
            )

        case .batteryCritical:
            sendNotification(
                title: "Critical Battery",
                body: "Pump battery is critically low (\(equilState?.battery ?? 0)%). Change immediately!",
                sound: UNNotificationSound.defaultCritical
            )

        case .pumpExpiring:
            sendNotification(
                title: "Pump Expiring",
                body: "Your pump is approaching its expiration time."
            )

        case .pumpExpired:
            sendNotification(
                title: "Pump Expired",
                body: "Your pump has expired. Please change it immediately!",
                sound: UNNotificationSound.defaultCritical
            )

        case .occlusion:
            sendNotification(
                title: "Occlusion Detected",
                body: "Possible occlusion detected. Check your infusion site.",
                sound: UNNotificationSound.defaultCritical
            )

        case .pumpError:
            sendNotification(
                title: "Pump Error",
                body: "An error occurred with your pump. Check the app for details.",
                sound: UNNotificationSound.defaultCritical
            )

        case .communicationError:
            sendNotification(
                title: "Communication Error",
                body: "Unable to communicate with pump. Check Bluetooth connection."
            )
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String, sound: UNNotificationSound = .default) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.categoryIdentifier = "EQUIL_ALERT"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.log.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - State Management

    private func stateDidChange() {
        pumpManagerDelegate?.pumpManagerDidUpdateState(self)
    }

    public func acknowledgeAlert(_ alert: EquilAlert) {
        equilState?.acknowledgeAlert(alert)
    }
}

// MARK: - EquilBLEManagerDelegate

extension EquilPumpManager: EquilBLEManagerDelegate {
    func bleManager(_: EquilBLEManager, didUpdateState state: CBManagerState) {
        log.info("BLE state updated: \(state.rawValue)")
    }

    func bleManager(_: EquilBLEManager, didConnect _: CBPeripheral) {
        log.info("Connected to pump")
        equilState?.updateConnectionState(.connected)

        // Request status update after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.updateStatus()
        }
    }

    func bleManager(_: EquilBLEManager, didDisconnect _: CBPeripheral, error: Error?) {
        log.info("Disconnected from pump")
        equilState?.updateConnectionState(.disconnected)

        if let error = error {
            log.error("Disconnection error: \(error.localizedDescription)")
        }
    }

    func bleManager(_: EquilBLEManager, didReceiveData _: Data) {
        log.debug("Received data from pump")
    }
}

// Made with Bob
