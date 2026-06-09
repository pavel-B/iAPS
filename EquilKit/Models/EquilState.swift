import Foundation

public enum ActivationProgress: String, Codable, Equatable {
    case none
    case pairing
    case priming
    case filling
    case attaching
    case ready
    case active
}

public enum RunMode: String, Codable, Equatable {
    case none
    case run
    case suspend
    case stop
}

public enum BluetoothConnectionState: String, Codable, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

public struct EquilState: Codable, Equatable {
    // Device identification
    public var address: String
    public var serialNumber: String
    public var password: String
    public var deviceKey: String?

    // Connection state
    public var bluetoothConnectionState: BluetoothConnectionState
    public var lastConnection: Date?
    public var lastDataTime: Date?

    // Activation and operation
    public var activationProgress: ActivationProgress
    public var runMode: RunMode
    public var activationDate: Date?

    // Insulin and reservoir
    public var currentInsulin: Int // in 0.05U units
    public var reservoirLevel: Double {
        Double(currentInsulin) * EquilPod.pulseSize
    }

    public var lastReservoirReading: Date?

    // Battery
    public var battery: Int? // percentage 0-100
    public var lastBatteryReading: Date?

    // Basal delivery
    public var basalSchedule: BasalSchedule?
    public var activeBasalRate: Double?

    // Temp basal
    public var tempBasalRate: Double?
    public var tempBasalDuration: TimeInterval?
    public var tempBasalStartTime: Date?

    // Bolus
    public var lastBolusAmount: Double?
    public var lastBolusTime: Date?
    public var bolusInProgress: Bool

    // Alerts and alarms
    public var activeAlerts: Set<EquilAlert>
    public var acknowledgedAlerts: Set<EquilAlert>

    // Suspension
    public var isSuspended: Bool {
        runMode == .suspend || runMode == .stop
    }

    // Expiration
    public var expirationDate: Date? {
        guard let activationDate = activationDate else { return nil }
        return activationDate.addingTimeInterval(EquilPod.serviceDuration)
    }

    public var timeUntilExpiration: TimeInterval? {
        guard let expirationDate = expirationDate else { return nil }
        return expirationDate.timeIntervalSinceNow
    }

    public var isExpiringSoon: Bool {
        guard let timeRemaining = timeUntilExpiration else { return false }
        return timeRemaining <= EquilPod.expirationWarningThreshold
    }

    // Initialization
    public init(address: String, serialNumber: String, password: String) {
        self.address = address
        self.serialNumber = serialNumber
        self.password = password
        bluetoothConnectionState = .disconnected
        activationProgress = .none
        runMode = .none
        currentInsulin = 0
        bolusInProgress = false
        activeAlerts = []
        acknowledgedAlerts = []
    }

    // Update methods
    public mutating func updateReservoir(units: Int) {
        currentInsulin = units
        lastReservoirReading = Date()
        lastDataTime = Date()

        // Check for low reservoir alert
        if reservoirLevel <= EquilPod.reservoirCriticalThreshold {
            activeAlerts.insert(.reservoirCritical)
        } else if reservoirLevel <= EquilPod.defaultLowReservoirReminder {
            activeAlerts.insert(.reservoirLow)
        } else {
            activeAlerts.remove(.reservoirLow)
            activeAlerts.remove(.reservoirCritical)
        }
    }

    public mutating func updateBattery(percentage: Int) {
        battery = percentage
        lastBatteryReading = Date()
        lastDataTime = Date()

        // Check for low battery alert
        if percentage <= EquilPod.batteryCriticalThreshold {
            activeAlerts.insert(.batteryCritical)
        } else if percentage <= EquilPod.batteryLowThreshold {
            activeAlerts.insert(.batteryLow)
        } else {
            activeAlerts.remove(.batteryLow)
            activeAlerts.remove(.batteryCritical)
        }
    }

    public mutating func updateConnectionState(_ state: BluetoothConnectionState) {
        bluetoothConnectionState = state
        if state == .connected {
            lastConnection = Date()
            lastDataTime = Date()
        }
    }

    public mutating func acknowledgeAlert(_ alert: EquilAlert) {
        acknowledgedAlerts.insert(alert)
    }

    public var unacknowledgedAlerts: Set<EquilAlert> {
        activeAlerts.subtracting(acknowledgedAlerts)
    }
}

public enum EquilAlert: String, Codable, Hashable {
    case reservoirLow
    case reservoirCritical
    case batteryLow
    case batteryCritical
    case pumpExpiring
    case pumpExpired
    case occlusion
    case pumpError
    case communicationError
}

public struct BasalSchedule: Codable, Equatable {
    public var entries: [BasalScheduleEntry]

    public init(entries: [BasalScheduleEntry]) {
        self.entries = entries
    }

    public func rateAt(time: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let minutesFromMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        for entry in entries {
            let entryStart = entry.startTime
            let entryEnd = entryStart + Int(entry.duration / 60)

            if minutesFromMidnight >= entryStart, minutesFromMidnight < entryEnd {
                return entry.rate
            }
        }

        return entries.first?.rate ?? 0.0
    }

    public static func mapProfileToBasalSchedule(profile: [BasalScheduleEntry]) -> BasalSchedule {
        BasalSchedule(entries: profile)
    }
}

public struct BasalScheduleEntry: Codable, Equatable {
    public var startTime: Int // minutes from midnight
    public var rate: Double // U/hr
    public var duration: TimeInterval // seconds

    public init(startTime: Int, rate: Double, duration: TimeInterval) {
        self.startTime = startTime
        self.rate = rate
        self.duration = duration
    }
}

public struct EquilPumpManagerState: Codable {
    public var equilState: EquilState?

    public init(equilState: EquilState? = nil) {
        self.equilState = equilState
    }
}

// Made with Bob
