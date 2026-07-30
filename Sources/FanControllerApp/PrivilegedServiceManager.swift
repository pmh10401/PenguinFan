import FanControlIPC
import Foundation
import ServiceManagement

enum PrivilegedServiceState: Equatable {
    case notRegistered
    case registering
    case requiresApproval
    case enabled
    case notFound
    case failed(String)
}

struct PrivilegedServiceUnregisterFailure: Equatable {
    enum Stage: Equatable {
        case restore
        case unregister
    }

    let stage: Stage
    let message: String
}

@MainActor
protocol PrivilegedServiceRegistering: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

extension SMAppService: PrivilegedServiceRegistering {}

@MainActor
final class PrivilegedServiceManager {
    static let daemonPlistName =
        "com.local.PenguinFan.experimental.agent.plist"

    private(set) var state: PrivilegedServiceState
    private(set) var lastUnregisterFailure:
        PrivilegedServiceUnregisterFailure?

    var lastUnregisterError: String? {
        lastUnregisterFailure?.message
    }

    private let service: any PrivilegedServiceRegistering
    private let restoreSystemModeAndDisconnect: () async throws -> Void
    private let connectionFactory: () -> any XPCControlConnection
    private let connectionFailureHandler: @Sendable () -> Void
    private let requestTimeout: TimeInterval
    private let approvalSettingsOpener: () -> Void

    init(
        service: any PrivilegedServiceRegistering = SMAppService.daemon(
            plistName: PrivilegedServiceManager.daemonPlistName
        ),
        restoreSystemModeAndDisconnect: @escaping () async throws -> Void,
        connectionFactory: @escaping () -> any XPCControlConnection = {
            SystemXPCControlConnection()
        },
        connectionFailureHandler: @escaping @Sendable () -> Void,
        requestTimeout: TimeInterval = 3,
        approvalSettingsOpener: @escaping () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.service = service
        self.restoreSystemModeAndDisconnect =
            restoreSystemModeAndDisconnect
        self.connectionFactory = connectionFactory
        self.connectionFailureHandler = connectionFailureHandler
        self.requestTimeout = requestTimeout
        self.approvalSettingsOpener = approvalSettingsOpener
        state = Self.map(service.status)
    }

    func register() {
        guard state == .notRegistered || state == .notFound else {
            return
        }

        state = .registering
        do {
            try service.register()
            refreshStatus()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func unregister() async {
        guard state == .enabled || state == .requiresApproval else {
            return
        }

        lastUnregisterFailure = nil
        do {
            try await restoreSystemModeAndDisconnect()
        } catch {
            lastUnregisterFailure = PrivilegedServiceUnregisterFailure(
                stage: .restore,
                message: error.localizedDescription
            )
            refreshStatus()
            return
        }

        do {
            try service.unregister()
            refreshStatus()
        } catch {
            lastUnregisterFailure = PrivilegedServiceUnregisterFailure(
                stage: .unregister,
                message: error.localizedDescription
            )
            refreshStatus()
        }
    }

    func refreshStatus() {
        state = Self.map(service.status)
    }

    func openApprovalSettings() {
        approvalSettingsOpener()
    }

    func makeControlClient(
        connectionFailureHandler: (@Sendable () -> Void)? = nil
    ) -> any ControlClient {
        XPCControlClient(
            connection: connectionFactory(),
            requestTimeout: requestTimeout,
            connectionFailureHandler:
                connectionFailureHandler ?? self.connectionFailureHandler
        )
    }

    private static func map(
        _ status: SMAppService.Status
    ) -> PrivilegedServiceState {
        switch status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .failed("Unknown privileged service status.")
        }
    }
}

enum XPCControlClientError: Error, Equatable {
    case timedOut
    case interrupted
    case invalidated
    case proxyUnavailable
    case responseIDMismatch
    case transport(String)
}

protocol XPCControlConnection: AnyObject, Sendable {
    var interruptionHandler: (@Sendable () -> Void)? { get set }
    var invalidationHandler: (@Sendable () -> Void)? { get set }

    func resume()
    func invalidate()
    func send(
        _ requestData: Data,
        reply: @escaping @Sendable (Data) -> Void,
        error: @escaping @Sendable (Error) -> Void
    )
}

protocol XPCRequestTimeoutScheduling: Sendable {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @Sendable () -> Void
    )
}

private struct DispatchXPCRequestTimeoutScheduler:
    XPCRequestTimeoutScheduling
{
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + max(0, delay),
            execute: operation
        )
    }
}

final class XPCControlClient: ControlClient, @unchecked Sendable {
    static let machServiceName =
        "com.local.PenguinFan.experimental.agent"

    private typealias Continuation =
        CheckedContinuation<ControlResult, Error>

    private let connection: any XPCControlConnection
    private let requestTimeout: TimeInterval
    private let connectionFailureHandler: @Sendable () -> Void
    private let timeoutScheduler: any XPCRequestTimeoutScheduling
    private let lock = NSLock()
    private var pending: [UUID: Continuation] = [:]
    private var connectionFailure: XPCControlClientError?

    init(
        connection: any XPCControlConnection,
        requestTimeout: TimeInterval,
        connectionFailureHandler: @escaping @Sendable () -> Void,
        timeoutScheduler: any XPCRequestTimeoutScheduling =
            DispatchXPCRequestTimeoutScheduler()
    ) {
        self.connection = connection
        self.requestTimeout = max(0, requestTimeout)
        self.connectionFailureHandler = connectionFailureHandler
        self.timeoutScheduler = timeoutScheduler

        connection.interruptionHandler = { [weak self] in
            self?.failConnection(with: .interrupted)
        }
        connection.invalidationHandler = { [weak self] in
            self?.failConnection(with: .invalidated)
        }
        connection.resume()
    }

    func send(_ command: ControlCommand) async throws -> ControlResult {
        let request = ControlRequest(id: UUID(), command: command)
        let requestData = try XPCMessageAdapter.encodeRequest(request)

        return try await withCheckedThrowingContinuation {
            continuation in
            if let connectionFailure = store(
                continuation,
                for: request.id
            ) {
                continuation.resume(throwing: connectionFailure)
                return
            }

            connection.send(
                requestData,
                reply: { responseData in
                    self.receive(responseData, for: request.id)
                },
                error: { error in
                    self.complete(
                        request.id,
                        with: .failure(
                            XPCControlClientError.transport(
                                error.localizedDescription
                            )
                        )
                    )
                }
            )

            timeoutScheduler.schedule(after: requestTimeout) {
                self.failConnection(
                    with: .timedOut,
                    onlyIfRequestIsPending: request.id,
                    invalidateConnection: true
                )
            }
        }
    }

    private func store(
        _ continuation: Continuation,
        for requestID: UUID
    ) -> XPCControlClientError? {
        lock.lock()
        defer { lock.unlock() }
        if let connectionFailure {
            return connectionFailure
        }
        pending[requestID] = continuation
        return nil
    }

    private func receive(_ data: Data, for requestID: UUID) {
        do {
            let response = try XPCMessageAdapter.decodeResponse(data)
            guard response.id == requestID else {
                complete(
                    requestID,
                    with: .failure(
                        XPCControlClientError.responseIDMismatch
                    )
                )
                return
            }
            complete(requestID, with: .success(response.result))
        } catch {
            complete(requestID, with: .failure(error))
        }
    }

    private func complete(
        _ requestID: UUID,
        with result: Result<ControlResult, Error>
    ) {
        lock.lock()
        let continuation = pending.removeValue(forKey: requestID)
        lock.unlock()

        continuation?.resume(with: result)
    }

    private func failConnection(
        with error: XPCControlClientError,
        onlyIfRequestIsPending requestID: UUID? = nil,
        invalidateConnection: Bool = false
    ) {
        lock.lock()
        guard connectionFailure == nil else {
            lock.unlock()
            return
        }
        if let requestID, pending[requestID] == nil {
            lock.unlock()
            return
        }
        connectionFailure = error
        let continuations = Array(pending.values)
        pending.removeAll()
        lock.unlock()

        if invalidateConnection {
            connection.invalidate()
        }
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        connectionFailureHandler()
    }
}

private final class SystemXPCControlConnection:
    XPCControlConnection,
    @unchecked Sendable
{
    var interruptionHandler: (@Sendable () -> Void)? {
        didSet {
            connection.interruptionHandler = interruptionHandler
        }
    }

    var invalidationHandler: (@Sendable () -> Void)? {
        didSet {
            connection.invalidationHandler = invalidationHandler
        }
    }

    private let connection: NSXPCConnection

    init() {
        connection = NSXPCConnection(
            machServiceName: XPCControlClient.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: FanControllerXPCProtocol.self
        )
    }

    func resume() {
        connection.resume()
    }

    func invalidate() {
        connection.invalidate()
    }

    func send(
        _ requestData: Data,
        reply: @escaping @Sendable (Data) -> Void,
        error failure: @escaping @Sendable (Error) -> Void
    ) {
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(
            failure
        ) as? FanControllerXPCProtocol else {
            failure(XPCControlClientError.proxyUnavailable)
            return
        }
        proxy.handle(requestData, withReply: reply)
    }
}
