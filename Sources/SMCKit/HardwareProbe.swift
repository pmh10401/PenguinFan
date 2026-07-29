import Darwin
import FanControllerCore
import Foundation

public struct HardwareCapabilities: Codable, Equatable, Sendable {
    public let modelIdentifier: String
    public let fans: [FanDescriptor]
    public let ftstAvailable: Bool

    public init(
        modelIdentifier: String,
        fans: [FanDescriptor],
        ftstAvailable: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.fans = fans
        self.ftstAvailable = ftstAvailable
    }
}

public enum HardwareProbeError: Error, LocalizedError, Equatable {
    case fanCountUnavailable
    case fanValueUnavailable(String)
    case modeKeyUnavailable(Int)
    case invalidFanRange(Int)

    public var errorDescription: String? {
        switch self {
        case .fanCountUnavailable:
            "Unable to read the SMC fan count."
        case .fanValueUnavailable(let key):
            "Unable to read required fan key \(key)."
        case .modeKeyUnavailable(let fan):
            "No supported mode key was found for fan \(fan)."
        case .invalidFanRange(let fan):
            "Fan \(fan) reported an invalid RPM range."
        }
    }
}

public struct HardwareProbe: Sendable {
    private let transport: any SMCTransport
    private let modelIdentifier: String

    public init(
        transport: any SMCTransport,
        modelIdentifier: String = HardwareProbe.currentModelIdentifier()
    ) {
        self.transport = transport
        self.modelIdentifier = modelIdentifier
    }

    public func probe() throws -> HardwareCapabilities {
        let fanCountValue: SMCValue
        do {
            fanCountValue = try transport.read(SMCKeys.fanCount)
        } catch {
            throw HardwareProbeError.fanCountUnavailable
        }
        let fanCount = Int(SMCDataFormat.decodeUInt8(fanCountValue.bytes))
        guard fanCount > 0 else {
            throw HardwareProbeError.fanCountUnavailable
        }

        var fans: [FanDescriptor] = []
        for fan in 0..<fanCount {
            let minimum = try readRPM(SMCKeys.minimumRPM(fan: fan))
            let maximum = try readRPM(SMCKeys.maximumRPM(fan: fan))
            _ = try readRPM(SMCKeys.actualRPM(fan: fan))
            _ = try readRPM(SMCKeys.targetRPM(fan: fan))
            guard minimum > 0, maximum >= minimum else {
                throw HardwareProbeError.invalidFanRange(fan)
            }

            let modeKey: String
            if (try? transport.read(SMCKeys.lowercaseMode(fan: fan))) != nil {
                modeKey = SMCKeys.lowercaseMode(fan: fan)
            } else if (try? transport.read(SMCKeys.uppercaseMode(fan: fan))) != nil {
                modeKey = SMCKeys.uppercaseMode(fan: fan)
            } else {
                throw HardwareProbeError.modeKeyUnavailable(fan)
            }

            fans.append(
                FanDescriptor(
                    index: fan,
                    minimumRPM: minimum,
                    maximumRPM: maximum,
                    modeKey: modeKey
                )
            )
        }

        return HardwareCapabilities(
            modelIdentifier: modelIdentifier,
            fans: fans,
            ftstAvailable: (try? transport.read(SMCKeys.forceTest)) != nil
        )
    }

    public static func currentModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0 else {
            return "unknown"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let utf8 = bytes
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: utf8, as: UTF8.self)
    }

    private func readRPM(_ key: String) throws -> Int {
        do {
            let value = try transport.read(key)
            return Int(
                SMCDataFormat.decodeFloat(
                    value.bytes,
                    size: value.dataSize
                ).rounded()
            )
        } catch {
            throw HardwareProbeError.fanValueUnavailable(key)
        }
    }
}
