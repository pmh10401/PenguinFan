import Darwin
import FanControlIPC
import FanControllerCore
import Foundation
import SMCKit

@main
private enum FanWriteVerificationMain {
    private static let approvedArguments = [
        "--fan", "0",
        "--rpm", "1650",
        "--duration", "5",
    ]
    private static let approvedCurveArguments = [
        "--curve",
        "--duration", "8",
    ]

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments == approvedArguments
                || arguments == approvedCurveArguments
        else {
            fail(
                "Permitted tests: --fan 0 --rpm 1650 --duration 5 "
                    + "or --curve --duration 8"
            )
        }

        do {
            let evidence: any Encodable = arguments == approvedCurveArguments
                ? try runApprovedCurveTest()
                : try runApprovedTest()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(
                try evidence.encode(using: encoder)
            )
            FileHandle.standardOutput.write(Data("\n".utf8))
            let passed = (evidence as? WriteEvidence)?.passed
                ?? (evidence as? CurveWriteEvidence)?.passed
                ?? false
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            fail(String(reflecting: error))
        }
    }

    private static func runApprovedTest() throws -> WriteEvidence {
        let connection = try SMCConnection()
        let capabilities = try HardwareProbe(
            transport: connection
        ).probe()
        guard capabilities.modelIdentifier == "Mac14,6",
              let fan = capabilities.fans.first(
                where: { $0.index == 0 }
              ),
              fan.minimumRPM == 1_350,
              fan.maximumRPM == 5_349
        else {
            throw VerificationError.hardwareMismatch
        }

        let reader = SensorReader(
            transport: connection,
            capabilities: capabilities
        )
        let before = try reader.snapshot()
        let agentSession = try startAgent()
        let socketURL = agentSession.socketURL
        let client = UnixSocketClient(path: socketURL.path)
        var shouldCleanup = true

        defer {
            if shouldCleanup {
                _ = try? send(.restoreSystemAuto, client: client)
                _ = try? send(.shutdown, client: client)
            }
            try? FileManager.default.removeItem(
                at: socketURL.deletingLastPathComponent()
            )
            withExtendedLifetime(agentSession.process) {}
        }

        let status: AgentStatus
        do {
            status = try waitForStatus(client: client)
        } catch {
            for _ in 0..<20 where agentSession.process.isRunning {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if !agentSession.process.isRunning {
                let data = agentSession.errorPipe
                    .fileHandleForReading
                    .readDataToEndOfFile()
                throw VerificationError.agentExited(
                    status: agentSession.process.terminationStatus,
                    message: String(decoding: data, as: UTF8.self)
                )
            }
            throw error
        }
        guard status.modelIdentifier == "Mac14,6" else {
            throw VerificationError.invalidAgentStatus
        }
        try requireAcknowledged(send(.heartbeat, client: client))

        try requireAcknowledged(
            send(.setRPM(fan: 0, rpm: 1_650), client: client)
        )

        var samples: [RPMSample] = []
        for second in 1...5 {
            Thread.sleep(forTimeInterval: 1)
            if second == 2 || second == 4 {
                try requireAcknowledged(send(.heartbeat, client: client))
            }
            let snapshot = try reader.snapshot()
            let reading = snapshot.fans.first { $0.index == 0 }
            samples.append(
                RPMSample(
                    second: second,
                    actualRPM: reading?.actualRPM ?? -1,
                    targetRPM: reading?.targetRPM ?? -1
                )
            )
        }

        try requireAcknowledged(
            send(.restoreSystemAuto, client: client)
        )
        Thread.sleep(forTimeInterval: 1)
        let after = try reader.snapshot()
        let modeAfter = try connection.read(fan.modeKey)
        let modeValue = SMCDataFormat.decodeUInt8(modeAfter.bytes)
        try requireAcknowledged(send(.shutdown, client: client))
        shouldCleanup = false
        Thread.sleep(forTimeInterval: 0.1)

        let beforeReading = before.fans.first { $0.index == 0 }
        let afterReading = after.fans.first { $0.index == 0 }
        let responseObserved = samples.contains {
            abs($0.actualRPM - 1_650) <= 400
        }
        let restored = modeValue == 0

        return WriteEvidence(
            timestamp: Date(),
            modelIdentifier: capabilities.modelIdentifier,
            fanIndex: 0,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM,
            requestedRPM: 1_650,
            durationSeconds: 5,
            beforeActualRPM: beforeReading?.actualRPM ?? -1,
            beforeTargetRPM: beforeReading?.targetRPM ?? -1,
            samples: samples,
            afterActualRPM: afterReading?.actualRPM ?? -1,
            afterTargetRPM: afterReading?.targetRPM ?? -1,
            modeKey: fan.modeKey,
            modeValueAfterRestore: modeValue,
            responseObserved: responseObserved,
            restoredSystemAuto: restored,
            passed: responseObserved && restored
        )
    }

    private static func runApprovedCurveTest() throws -> CurveWriteEvidence {
        let connection = try SMCConnection()
        let capabilities = try HardwareProbe(
            transport: connection
        ).probe()
        guard capabilities.modelIdentifier == "Mac14,6",
              capabilities.fans.count == 2
        else {
            throw VerificationError.hardwareMismatch
        }

        let reader = SensorReader(
            transport: connection,
            capabilities: capabilities
        )
        let before = try reader.snapshot()
        guard let temperature = before.maximumTemperature,
              before.validTemperatureKeys == ["TCMz"]
        else {
            throw VerificationError.invalidTemperatureSource
        }

        let targets = try Dictionary(
            uniqueKeysWithValues: capabilities.fans.map { fan in
                (
                    fan.index,
                    try CurveEngine.targetRPM(
                        temperature: temperature,
                        points: FanSettings.safeDefaults.curve,
                        minimumRPM: fan.minimumRPM,
                        maximumRPM: fan.maximumRPM
                    )
                )
            }
        )

        let agentSession = try startAgent()
        let socketURL = agentSession.socketURL
        let client = UnixSocketClient(path: socketURL.path)
        var shouldCleanup = true

        defer {
            if shouldCleanup {
                _ = try? send(.restoreSystemAuto, client: client)
                _ = try? send(.shutdown, client: client)
            }
            try? FileManager.default.removeItem(
                at: socketURL.deletingLastPathComponent()
            )
            withExtendedLifetime(agentSession.process) {}
        }

        let status = try waitForStatus(client: client)
        guard status.modelIdentifier == "Mac14,6" else {
            throw VerificationError.invalidAgentStatus
        }
        try requireAcknowledged(send(.heartbeat, client: client))

        for fan in capabilities.fans {
            guard let target = targets[fan.index] else {
                throw VerificationError.invalidAgentStatus
            }
            try requireAcknowledged(
                send(.setRPM(fan: fan.index, rpm: target), client: client)
            )
        }

        var samples: [CurveRPMSample] = []
        for second in 1...8 {
            Thread.sleep(forTimeInterval: 1)
            if second.isMultiple(of: 2) {
                try requireAcknowledged(send(.heartbeat, client: client))
            }
            let snapshot = try reader.snapshot()
            samples.append(
                CurveRPMSample(
                    second: second,
                    readings: snapshot.fans
                )
            )
        }

        try requireAcknowledged(send(.restoreSystemAuto, client: client))
        Thread.sleep(forTimeInterval: 1)
        let after = try reader.snapshot()
        let modes = try Dictionary(
            uniqueKeysWithValues: capabilities.fans.map { fan in
                (
                    fan.index,
                    SMCDataFormat.decodeUInt8(
                        try connection.read(fan.modeKey).bytes
                    )
                )
            }
        )
        try requireAcknowledged(send(.shutdown, client: client))
        shouldCleanup = false
        Thread.sleep(forTimeInterval: 0.1)

        let responses = Dictionary(
            uniqueKeysWithValues: capabilities.fans.map { fan in
                let target = targets[fan.index] ?? -1
                let observed = samples.contains { sample in
                    sample.readings.contains {
                        $0.index == fan.index
                            && abs($0.actualRPM - target) <= 400
                    }
                }
                return (fan.index, observed)
            }
        )
        let restored = capabilities.fans.allSatisfy {
            modes[$0.index] == 0
        }

        return CurveWriteEvidence(
            timestamp: Date(),
            modelIdentifier: capabilities.modelIdentifier,
            temperatureKey: "TCMz",
            temperature: temperature,
            targets: targets,
            durationSeconds: 8,
            before: before.fans,
            samples: samples,
            after: after.fans,
            modeValuesAfterRestore: modes,
            responseObserved: responses,
            restoredSystemAuto: restored,
            passed: responses.values.allSatisfy { $0 } && restored
        )
    }

    private static func startAgent() throws -> AgentSession {
        let executable = URL(
            fileURLWithPath: CommandLine.arguments[0]
        )
        let agentURL = executable
            .deletingLastPathComponent()
            .appendingPathComponent("FanControllerAgent")
        guard FileManager.default.isExecutableFile(
            atPath: agentURL.path
        ) else {
            throw VerificationError.agentNotFound
        }

        let suffix = UUID().uuidString.prefix(8)
        let directory = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent(
                "fcv-\(getpid())-\(suffix)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else {
            throw POSIXError(.EACCES)
        }

        let socketURL = directory.appendingPathComponent("control.sock")
        let command = [
            "exec",
            shellQuote(agentURL.path),
            "--socket",
            shellQuote(socketURL.path),
            "--owner-uid",
            shellQuote(String(getuid())),
        ].joined(separator: " ")
        let script = "do shell script \"\(appleScriptQuote(command))\" with administrator privileges"
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = errorPipe
        try process.run()

        for _ in 0..<1_200 {
            if FileManager.default.fileExists(atPath: socketURL.path) {
                return AgentSession(
                    socketURL: socketURL,
                    process: process,
                    errorPipe: errorPipe
                )
            }
            if !process.isRunning {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                throw VerificationError.authorizationFailed(
                    String(decoding: data, as: UTF8.self)
                )
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        process.terminate()
        throw VerificationError.authorizationTimedOut
    }

    private static func send(
        _ command: ControlCommand,
        client: UnixSocketClient
    ) throws -> ControlResult {
        try client.send(
            ControlRequest(id: UUID(), command: command)
        ).result
    }

    private static func waitForStatus(
        client: UnixSocketClient
    ) throws -> AgentStatus {
        var failures: [String] = []
        for _ in 0..<30 {
            do {
                if case .status(let status) = try send(
                    .status,
                    client: client
                ) {
                    return status
                }
            } catch {
                failures.append(String(reflecting: error))
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw VerificationError.statusConnectionFailed(failures)
    }

    private static func requireAcknowledged(
        _ result: ControlResult
    ) throws {
        guard result == .acknowledged else {
            throw VerificationError.commandRejected(
                String(describing: result)
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(
            Data("FanWriteVerification: \(message)\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
}

private struct AgentSession {
    let socketURL: URL
    let process: Process
    let errorPipe: Pipe
}

private struct RPMSample: Codable {
    let second: Int
    let actualRPM: Int
    let targetRPM: Int
}

private struct CurveRPMSample: Codable {
    let second: Int
    let readings: [FanReading]
}

private struct WriteEvidence: Codable {
    let timestamp: Date
    let modelIdentifier: String
    let fanIndex: Int
    let minimumRPM: Int
    let maximumRPM: Int
    let requestedRPM: Int
    let durationSeconds: Int
    let beforeActualRPM: Int
    let beforeTargetRPM: Int
    let samples: [RPMSample]
    let afterActualRPM: Int
    let afterTargetRPM: Int
    let modeKey: String
    let modeValueAfterRestore: UInt8
    let responseObserved: Bool
    let restoredSystemAuto: Bool
    let passed: Bool
}

private struct CurveWriteEvidence: Codable {
    let timestamp: Date
    let modelIdentifier: String
    let temperatureKey: String
    let temperature: Double
    let targets: [Int: Int]
    let durationSeconds: Int
    let before: [FanReading]
    let samples: [CurveRPMSample]
    let after: [FanReading]
    let modeValuesAfterRestore: [Int: UInt8]
    let responseObserved: [Int: Bool]
    let restoredSystemAuto: Bool
    let passed: Bool
}

private enum VerificationError: Error, LocalizedError {
    case hardwareMismatch
    case agentNotFound
    case invalidAgentStatus
    case invalidTemperatureSource
    case authorizationFailed(String)
    case authorizationTimedOut
    case commandRejected(String)
    case agentExited(status: Int32, message: String)
    case statusConnectionFailed([String])

    var errorDescription: String? {
        switch self {
        case .hardwareMismatch:
            "Hardware does not match the approved Mac14,6 Fan 0 range."
        case .agentNotFound:
            "FanControllerAgent was not built beside this executable."
        case .invalidAgentStatus:
            "The privileged agent returned an invalid hardware status."
        case .invalidTemperatureSource:
            "TCMz was not available as the exclusive curve sensor."
        case .authorizationFailed(let message):
            "Administrator authorization failed: \(message)"
        case .authorizationTimedOut:
            "Administrator authorization timed out."
        case .commandRejected(let result):
            "The privileged agent rejected a command: \(result)"
        case .agentExited(let status, let message):
            "The privileged agent exited with status \(status): \(message)"
        case .statusConnectionFailed(let failures):
            "Agent status connection failed: \(failures.joined(separator: " | "))"
        }
    }
}

private extension Encodable {
    func encode(using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(self)
    }
}
