import Darwin
import FanControllerCore
import Foundation

public final class SensorReader: @unchecked Sendable {
    public static let m2ProMaxTemperatureKeys = [
        "TCMz",
        "TC10", "TC11", "TC12", "TC13",
        "TC20", "TC21", "TC22", "TC23",
        "TC30", "TC31", "TC32", "TC33",
        "TC40", "TC41", "TC42", "TC43",
        "TC50", "TC51", "TC52", "TC53",
        "Tg04", "Tg05", "Tg0C", "Tg0D",
        "Tg0K", "Tg0L", "Tg0S", "Tg0T",
    ]

    private let transport: any SMCTransport
    private let capabilities: HardwareCapabilities
    private let temperatureKeys: [String]
    private let thermalPressure: @Sendable () -> ThermalPressureLevel
    private let lock = NSLock()
    private var cachedTemperatureKeys: [String]?
    private var lastFullProbe: Date?

    public init(
        transport: any SMCTransport,
        capabilities: HardwareCapabilities,
        temperatureKeys: [String] = SensorReader.m2ProMaxTemperatureKeys,
        thermalPressure: @escaping @Sendable () -> ThermalPressureLevel = {
            ThermalPressureReader.shared.read()
        }
    ) {
        self.transport = transport
        self.capabilities = capabilities
        self.temperatureKeys = temperatureKeys
        self.thermalPressure = thermalPressure
    }

    public func snapshot(at date: Date = Date()) throws -> SensorSnapshot {
        let fans = try capabilities.fans.map { fan in
            FanReading(
                index: fan.index,
                actualRPM: try readRPM(SMCKeys.actualRPM(fan: fan.index)),
                targetRPM: try readRPM(SMCKeys.targetRPM(fan: fan.index))
            )
        }

        let temperatureResult = readTemperatures(at: date)
        return SensorSnapshot(
            timestamp: date,
            maximumTemperature: temperatureResult.values.max(),
            thermalPressure: thermalPressure(),
            fans: fans,
            validTemperatureKeys: temperatureResult.keys
        )
    }

    private func readTemperatures(at date: Date) -> (keys: [String], values: [Double]) {
        lock.lock()
        defer { lock.unlock() }

        if let cachedTemperatureKeys, !cachedTemperatureKeys.isEmpty {
            let cached = validTemperatures(for: cachedTemperatureKeys)
            if !cached.keys.isEmpty {
                return cached
            }
            self.cachedTemperatureKeys = nil
        }

        if let cachedTemperatureKeys,
           cachedTemperatureKeys.isEmpty,
           let lastFullProbe,
           date.timeIntervalSince(lastFullProbe) < 60 {
            return ([], [])
        }

        let result = validTemperatures(for: candidateTemperatureKeys())
        cachedTemperatureKeys = result.keys
        lastFullProbe = date
        return result
    }

    private func validTemperatures(for keys: [String]) -> (keys: [String], values: [Double]) {
        var validKeys: [String] = []
        var values: [Double] = []
        for key in keys {
            guard let value = try? transport.read(key) else {
                continue
            }
            guard value.dataType == "flt ", value.dataSize == 4 else {
                continue
            }
            let temperature = Double(
                SMCDataFormat.decodeFloat(value.bytes, size: value.dataSize)
            )
            guard temperature.isFinite, (10...120).contains(temperature) else {
                continue
            }
            validKeys.append(key)
            values.append(temperature)
        }
        return (validKeys, values)
    }

    private func candidateTemperatureKeys() -> [String] {
        if !temperatureKeys.isEmpty {
            return temperatureKeys
        }
        if let enumerator = transport as? any SMCKeyEnumerating,
           let keys = try? enumerator.enumerateKeys() {
            let dynamicKeys = keys.filter { $0.first == "T" }
            if !dynamicKeys.isEmpty {
                return dynamicKeys
            }
        }
        return []
    }

    private func readRPM(_ key: String) throws -> Int {
        let value = try transport.read(key)
        return Int(
            SMCDataFormat.decodeFloat(
                value.bytes,
                size: value.dataSize
            ).rounded()
        )
    }
}

public final class ThermalPressureReader: @unchecked Sendable {
    public static let shared = ThermalPressureReader()

    private var token: Int32 = 0
    private let isRegistered: Bool

    private init() {
        isRegistered =
            notify_register_check(
                "com.apple.system.thermalpressurelevel",
                &token
            ) == 0
    }

    deinit {
        if isRegistered {
            notify_cancel(token)
        }
    }

    public func read() -> ThermalPressureLevel {
        guard isRegistered else {
            return .unknown
        }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == 0 else {
            return .unknown
        }
        switch state {
        case 0: return .nominal
        case 1: return .elevated
        case 2: return .hot
        case 3...4: return .critical
        default: return .unknown
        }
    }
}

@_silgen_name("notify_register_check")
private func notify_register_check(
    _ name: UnsafePointer<CChar>,
    _ token: UnsafeMutablePointer<Int32>
) -> UInt32

@_silgen_name("notify_get_state")
private func notify_get_state(
    _ token: Int32,
    _ state: UnsafeMutablePointer<UInt64>
) -> UInt32

@_silgen_name("notify_cancel")
@discardableResult
private func notify_cancel(_ token: Int32) -> UInt32
