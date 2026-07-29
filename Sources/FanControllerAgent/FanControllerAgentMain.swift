import Darwin
import FanControlIPC
import Foundation
import SMCKit

@main
private enum FanControllerAgentMain {
    static func main() {
        do {
            let arguments = try AgentArguments.parse(
                Array(CommandLine.arguments.dropFirst())
            )
            try validateSocketParent(
                path: arguments.socketPath,
                ownerUID: arguments.ownerUID
            )

            let connection = try SMCConnection()
            let capabilities = try HardwareProbe(
                transport: connection
            ).probe()
            let writer = FanWriter(
                transport: connection,
                ftstAvailable: capabilities.ftstAvailable
            )
            let agent = AgentServer(
                writer: writer,
                capabilities: capabilities
            )
            let socket = UnixSocketServer(path: arguments.socketPath)
            try socket.start { request in
                agent.handle(request)
            }
            guard chown(
                arguments.socketPath,
                arguments.ownerUID,
                gid_t(bitPattern: -1)
            ) == 0 else {
                throw AgentStartupError.systemCall("chown", errno)
            }
            guard chmod(arguments.socketPath, 0o600) == 0 else {
                throw AgentStartupError.systemCall("chmod", errno)
            }

            agent.startWatchdog {
                socket.close()
                CFRunLoopStop(CFRunLoopGetMain())
            }
            let signals = installSignalHandlers {
                agent.cleanup()
                socket.close()
                CFRunLoopStop(CFRunLoopGetMain())
            }
            withExtendedLifetime(signals) {
                CFRunLoopRun()
            }
            agent.cleanup()
            socket.close()
        } catch {
            let message = "FanControllerAgent: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}

private struct AgentArguments {
    let socketPath: String
    let ownerUID: uid_t

    static func parse(_ arguments: [String]) throws -> AgentArguments {
        guard arguments.count == 4,
              arguments[0] == "--socket",
              arguments[2] == "--owner-uid",
              arguments[1].hasPrefix("/"),
              let ownerUID = uid_t(arguments[3])
        else {
            throw AgentStartupError.invalidArguments
        }
        return AgentArguments(
            socketPath: arguments[1],
            ownerUID: ownerUID
        )
    }
}

private enum AgentStartupError: Error {
    case invalidArguments
    case invalidSocketParent
    case systemCall(String, Int32)
}

private func validateSocketParent(
    path: String,
    ownerUID: uid_t
) throws {
    let parent = URL(fileURLWithPath: path)
        .deletingLastPathComponent()
        .path
    let attributes = try FileManager.default.attributesOfItem(
        atPath: parent
    )
    guard let owner = attributes[.ownerAccountID] as? NSNumber,
          owner.uint32Value == ownerUID,
          let permissions = attributes[.posixPermissions] as? NSNumber,
          permissions.uint16Value & 0o777 == 0o700
    else {
        throw AgentStartupError.invalidSocketParent
    }
}

private func installSignalHandlers(
    _ handler: @escaping @Sendable () -> Void
) -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: signalNumber,
            queue: .main
        )
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }
}
