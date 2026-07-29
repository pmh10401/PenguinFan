import FanControllerCore
import Foundation

public protocol FanWriting: Sendable {
    func setRPM(_ rpm: Int, for fan: FanDescriptor) throws
    func restoreSystemAuto(_ fans: [FanDescriptor]) throws
}

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

public final class FanWriter: FanWriting, @unchecked Sendable {
    private let transport: any SMCTransport
    private let ftstAvailable: Bool
    private let sleep: (TimeInterval) -> Void
    private var ftstWasEnabled = false

    public init(
        transport: any SMCTransport,
        ftstAvailable: Bool
    ) {
        self.transport = transport
        self.ftstAvailable = ftstAvailable
        self.sleep = Thread.sleep(forTimeInterval:)
    }

    init(
        transport: any SMCTransport,
        ftstAvailable: Bool,
        sleep: @escaping (TimeInterval) -> Void
    ) {
        self.transport = transport
        self.ftstAvailable = ftstAvailable
        self.sleep = sleep
    }

    public func setRPM(_ rpm: Int, for fan: FanDescriptor) throws {
        guard (fan.minimumRPM...fan.maximumRPM).contains(rpm) else {
            throw FanWriterError.rpmOutOfRange(
                fan: fan.index,
                requested: rpm,
                minimum: fan.minimumRPM,
                maximum: fan.maximumRPM
            )
        }

        let target = try transport.read(SMCKeys.targetRPM(fan: fan.index))
        guard target.dataSize == 2 || target.dataSize == 4 else {
            throw FanWriterError.unsupportedTargetFormat(
                fan: fan.index,
                size: target.dataSize
            )
        }

        do {
            try enableManualMode(for: fan)
            try transport.write(
                SMCKeys.targetRPM(fan: fan.index),
                bytes: SMCDataFormat.encodeFloat(
                    Float(rpm),
                    size: target.dataSize
                )
            )
        } catch {
            try? restoreSystemAuto([fan])
            throw error
        }
    }

    public func restoreSystemAuto(_ fans: [FanDescriptor]) throws {
        var failedKeys: [String] = []

        for fan in fans {
            do {
                try transport.write(fan.modeKey, bytes: [0])
            } catch {
                failedKeys.append(fan.modeKey)
            }
        }

        if ftstWasEnabled {
            do {
                try transport.write(SMCKeys.forceTest, bytes: [0])
                ftstWasEnabled = false
            } catch {
                failedKeys.append(SMCKeys.forceTest)
            }
        }

        if !failedKeys.isEmpty {
            throw FanWriterError.restoreFailed(keys: failedKeys)
        }
    }

    private func enableManualMode(for fan: FanDescriptor) throws {
        do {
            try transport.write(fan.modeKey, bytes: [1])
            return
        } catch {
            guard ftstAvailable, isFirmwareRejection(error) else {
                throw error
            }
        }

        try transport.write(SMCKeys.forceTest, bytes: [1])
        ftstWasEnabled = true
        sleep(0.5)

        for attempt in 0..<100 {
            do {
                try transport.write(fan.modeKey, bytes: [1])
                return
            } catch {
                guard isFirmwareRejection(error), attempt < 99 else {
                    throw error
                }
                sleep(0.1)
            }
        }
    }

    private func isFirmwareRejection(_ error: Error) -> Bool {
        if case SMCError.firmware = error {
            return true
        }
        return false
    }
}
