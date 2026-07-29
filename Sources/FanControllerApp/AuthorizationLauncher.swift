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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "fan-controller-\(UUID().uuidString)",
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

        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: socketURL.path) {
                return socketURL
            }
            if !process.isRunning {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                if process.terminationStatus == -128
                    || message.localizedCaseInsensitiveContains("cancel") {
                    throw AuthorizationLauncherError.authorizationCancelled
                }
                throw AuthorizationLauncherError.agentFailed(message)
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

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
