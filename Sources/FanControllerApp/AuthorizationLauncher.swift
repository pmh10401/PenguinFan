import Darwin
import Foundation

enum AuthorizationLauncherError: Error, LocalizedError {
    case helperNotFound
    case authorizationCancelled
    case agentFailed(String)
    case socketTimeout

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            "FanControllerAgent helper를 찾지 못했습니다."
        case .authorizationCancelled:
            "관리자 승인이 취소되어 읽기 전용 모드로 유지합니다."
        case .agentFailed(let message):
            "관리자 에이전트를 시작하지 못했습니다: \(message)"
        case .socketTimeout:
            "관리자 에이전트 연결 시간이 초과되었습니다."
        }
    }
}

actor AuthorizationLauncher {
    private var process: Process?
    private var sessionDirectory: URL?

    func startAgent() async throws -> URL {
        if let sessionDirectory,
           process?.isRunning == true {
            return sessionDirectory.appendingPathComponent("control.sock")
        }

        let agentURL = try locateAgent()
        let directory = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "fc-\(UUID().uuidString)",
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

        self.process = process
        sessionDirectory = directory

        var processExitObservedAt: Date?
        for _ in 0..<300 {
            if socketIsReady(
                socketURL,
                ownerUID: getuid()
            ) {
                process.terminate()
                self.process = nil
                return socketURL
            }
            if !process.isRunning {
                if processExitObservedAt == nil {
                    processExitObservedAt = Date()
                }
                if Date().timeIntervalSince(processExitObservedAt!) >= 1 {
                    let data = errorPipe.fileHandleForReading
                        .readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if process.terminationStatus == -128
                        || output.localizedCaseInsensitiveContains("cancel") {
                        throw AuthorizationLauncherError
                            .authorizationCancelled
                    }
                    let message = output.isEmpty
                        ? "권한 소켓이 준비되기 전에 에이전트가 종료되었습니다."
                        : output
                    throw AuthorizationLauncherError.agentFailed(message)
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        process.terminate()
        throw AuthorizationLauncherError.socketTimeout
    }

    private func locateAgent() throws -> URL {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/FanControllerAgent")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let executable = Bundle.main.executableURL {
            let development = executable
                .deletingLastPathComponent()
                .appendingPathComponent("FanControllerAgent")
            if FileManager.default.isExecutableFile(
                atPath: development.path
            ) {
                return development
            }
        }
        throw AuthorizationLauncherError.helperNotFound
    }

    private func socketIsReady(
        _ url: URL,
        ownerUID: uid_t
    ) -> Bool {
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == ownerUID,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.uint16Value & 0o777 == 0o600
        else {
            return false
        }
        return true
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
