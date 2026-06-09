import Foundation

public enum EquilPod {
    // Insulin delivery constants
    public static let pulseSize: Double = 0.05
    public static let pulsesPerUnit: Double = 1 / EquilPod.pulseSize

    // Delivery rates
    public static let bolusDeliveryRate: Double = EquilPod.pulseSize / 2.0 // 2 seconds per pulse
    public static let primeDeliveryRate: Double = EquilPod.pulseSize / 1.0 // 1 second per pulse

    // Reservoir capacity
    public static let reservoirCapacity: Double = 200.0
    public static let maximumReservoirReading: Double = 200.0

    // Supported rates
    public static let supportedBasalRates: [Double] = (0 ... 600).map { Double($0) / Double(pulsesPerUnit) }
    public static let supportedTempBasalRates: [Double] = (0 ... 600).map { Double($0) / Double(pulsesPerUnit) }

    // Basal schedule constraints
    public static let maximumBasalScheduleEntryCount: Int = 24
    public static let minimumBasalScheduleEntryDuration = TimeInterval.minutes(30)

    // Temp basal durations (30m to 12h)
    public static let supportedTempBasalDurations: [TimeInterval] = (1 ... 24).map { Double($0) * TimeInterval(minutes: 30) }

    // Priming and insertion
    public static let primeUnits = 2.6
    public static let cannulaInsertionUnits = 0.5

    // Battery thresholds
    public static let batteryLowThreshold = 20
    public static let batteryCriticalThreshold = 10

    // Reservoir alert thresholds
    public static let defaultLowReservoirReminder: Double = 10.0
    public static let reservoirCriticalThreshold: Double = 5.0

    // Service duration (Equil typically 3 days)
    public static let serviceDuration = TimeInterval(hours: 72)
    public static let expirationWarningThreshold = TimeInterval(hours: 12)
}

// Made with Bob
