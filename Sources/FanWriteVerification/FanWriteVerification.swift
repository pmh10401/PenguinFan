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

    static func main() {
        guard Array(CommandLine.arguments.dropFirst())
            == approvedArguments else {
            fail(
                "This build permits only: --fan 0 --rpm 1650 --duration 5"
            )
        }

        do {
            let evidence = try runApprovedTest()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(
                try encoder.encode(evidence)
            )
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(evidence.passed ? EXIT_SUCCESS : EXIT_FAILURE)
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

private enum VerificationError: Error, LocalizedError {
    case hardwareMismatch
    case agentNotFound
    case invalidAgentStatus
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
