import FanControllerCore
import Foundation

public enum FanWriterError: Error, Equatable, Sendable {
    case rpmOutOfRange(
        fan: Int,
        requested: Int,
        minimum: Int,
        maximum: Int
    )
    case unsupportedTargetFormat(fan: Int, size: UInt32)
    case restoreFailed(keys: [String])
}

public struct FanWriter: Sendable {
    private let transport: any SMCTransport
    private let capabilities: HardwareCapabilities

    public init(
        transport: any SMCTransport,
        capabilities: HardwareCapabilities
    ) {
        self.transport = transport
        self.capabilities = capabilities
    }

    public func setManualRPM(_ rpm: Int) throws {
        let targets = try capabilities.fans.map { fan in
            guard (fan.minimumRPM...fan.maximumRPM).contains(rpm) else {
                throw FanWriterError.rpmOutOfRange(
                    fan: fan.index,
                    requested: rpm,
                    minimum: fan.minimumRPM,
                    maximum: fan.maximumRPM
                )
            }

            let target = try transport.read(
                SMCKeys.targetRPM(fan: fan.index)
            )
            guard target.dataSize == 2 || target.dataSize == 4 else {
                throw FanWriterError.unsupportedTargetFormat(
                    fan: fan.index,
                    size: target.dataSize
                )
            }
            return (fan, target.dataSize)
        }

        do {
            for (fan, size) in targets {
                try transport.write(fan.modeKey, bytes: [1])
                try transport.write(
                    SMCKeys.targetRPM(fan: fan.index),
                    bytes: SMCDataFormat.encodeFloat(
                        Float(rpm),
                        size: size
                    )
                )
            }
        } catch {
            try? restoreSystemAuto()
            throw error
        }
    }

    public func restoreSystemAuto() throws {
        var failedKeys: [String] = []

        for fan in capabilities.fans {
            do {
                try transport.write(fan.modeKey, bytes: [0])
            } catch {
                failedKeys.append(fan.modeKey)
            }
        }

        if capabilities.ftstAvailable {
            do {
                try transport.write(SMCKeys.forceTest, bytes: [0])
            } catch {
                failedKeys.append(SMCKeys.forceTest)
            }
        }

        if !failedKeys.isEmpty {
            throw FanWriterError.restoreFailed(keys: failedKeys)
        }
    }
}
