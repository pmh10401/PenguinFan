import Darwin
import FanControlIPC
import Foundation
import SMCKit

@main
private enum FanControllerAgentMain {
    static func main() {
        do {
            let mode = try AgentMode.parse(
                Array(CommandLine.arguments.dropFirst())
            )
            if case .legacySocket(let arguments) = mode {
                try validateSocketParent(
                    path: arguments.socketPath,
                    ownerUID: arguments.ownerUID
                )
            }
            let processLock = try AgentProcessLock()
            defer {
                withExtendedLifetime(processLock) {}
            }

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
            let endpoint = try startEndpoint(mode: mode, agent: agent)

            let shutdown = DispatchSemaphore(value: 0)
            agent.startWatchdog {
                endpoint.close()
                shutdown.signal()
            }
            let signals = installSignalHandlers {
                agent.cleanup()
                endpoint.close()
                shutdown.signal()
            }
            shutdown.wait()
            withExtendedLifetime((signals, endpoint)) {
                agent.cleanup()
                endpoint.close()
            }
        } catch {
            let message = "FanControllerAgent: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}

private enum AgentMode {
    case machService
    case legacySocket(AgentArguments)

    static func parse(_ arguments: [String]) throws -> AgentMode {
        if arguments.isEmpty {
            return .machService
        }
        return .legacySocket(try AgentArguments.parse(arguments))
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

private final class AgentEndpoint: @unchecked Sendable {
    private let retainedObjects: [AnyObject]
    private let closeHandler: () -> Void
    private let lock = NSLock()
    private var isClosed = false

    init(
        retaining retainedObjects: [AnyObject],
        close: @escaping () -> Void
    ) {
        self.retainedObjects = retainedObjects
        self.closeHandler = close
    }

    func close() {
        let shouldClose = lock.withLock { () -> Bool in
            guard !isClosed else {
                return false
            }
            isClosed = true
            return true
        }
        if shouldClose {
            closeHandler()
        }
        withExtendedLifetime(retainedObjects) {}
    }
}

private enum AgentStartupError: Error {
    case invalidArguments
    case invalidSocketParent
    case systemCall(String, Int32)
}

private func startEndpoint(
    mode: AgentMode,
    agent: AgentServer
) throws -> AgentEndpoint {
    switch mode {
    case .machService:
        let service = AgentXPCService(server: agent)
        let delegate = AgentXPCListenerDelegate(
            service: service,
            validator: XPCClientValidator()
        )
        let listener = NSXPCListener(
            machServiceName: AgentXPCService.machServiceName
        )
        listener.delegate = delegate
        listener.resume()
        return AgentEndpoint(
            retaining: [service, delegate, listener],
            close: { listener.invalidate() }
        )

    case .legacySocket(let arguments):
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
        return AgentEndpoint(
            retaining: [socket],
            close: { socket.close() }
        )
    }
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
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }
}
