import Foundation

public enum ControlMode: String, Codable, Sendable {
    case systemAuto
    case curve
    case manual
}

public enum ThermalPressureLevel: String, Codable, Sendable {
    case nominal
    case elevated
    case hot
    case critical
    case unknown
}

public enum ControlStatus: String, Codable, Sendable {
    case systemAuto
    case authorizing
    case curve
    case manual
    case restoring
    case failed
}

public struct CurvePoint: Codable, Equatable, Sendable {
    public var temperature: Double
    public var rpm: Int

    public init(temperature: Double, rpm: Int) {
        self.temperature = temperature
        self.rpm = rpm
    }
}

public struct FanSettings: Codable, Equatable, Sendable {
    public var mode: ControlMode
    public var manualRPM: Int
    public var curve: [CurvePoint]

    public init(mode: ControlMode, manualRPM: Int, curve: [CurvePoint]) {
        self.mode = mode
        self.manualRPM = manualRPM
        self.curve = curve
    }

    public static let safeDefaults = FanSettings(
        mode: .systemAuto,
        manualRPM: 3_000,
        curve: [
            CurvePoint(temperature: 55, rpm: 2_300),
            CurvePoint(temperature: 75, rpm: 4_200),
            CurvePoint(temperature: 90, rpm: 6_200),
        ]
    )

    public var persistedCopy: FanSettings {
        FanSettings(mode: .systemAuto, manualRPM: manualRPM, curve: curve)
    }
}

public struct FanDescriptor: Codable, Equatable, Sendable {
    public let index: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let modeKey: String

    public init(index: Int, minimumRPM: Int, maximumRPM: Int, modeKey: String) {
        self.index = index
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.modeKey = modeKey
    }
}

public struct FanReading: Codable, Equatable, Sendable {
    public let index: Int
    public let actualRPM: Int
    public let targetRPM: Int

    public init(index: Int, actualRPM: Int, targetRPM: Int) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
    }
}

public struct SensorSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let maximumTemperature: Double?
    public let thermalPressure: ThermalPressureLevel
    public let fans: [FanReading]
    public let validTemperatureKeys: [String]

    public init(
        timestamp: Date,
        maximumTemperature: Double?,
        thermalPressure: ThermalPressureLevel,
        fans: [FanReading],
        validTemperatureKeys: [String]
    ) {
        self.timestamp = timestamp
        self.maximumTemperature = maximumTemperature
        self.thermalPressure = thermalPressure
        self.fans = fans
        self.validTemperatureKeys = validTemperatureKeys
    }
}
