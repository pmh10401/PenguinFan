import FanControlIPC
import FanControllerCore
import Foundation
import SMCKit

public final class AgentServer: @unchecked Sendable {
    private let writer: any FanWriting
    private let capabilities: HardwareCapabilities?
    private let clock: () -> TimeInterval
    private let operationLock = NSLock()
    private let lock = NSLock()
    private let restorationQueue = DispatchQueue(
        label: "com.local.PenguinFan.agent.restoration",
        qos: .userInitiated
    )
    private let restorationGroup = DispatchGroup()

    private var processedRequestIDs: Set<UUID> = []
    private var manualFanIndices: Set<Int> = []
    private var lastHeartbeat: TimeInterval
    private var terminated = false
    private var restorationCompleted = false
    private var watchdog: DispatchSourceTimer?
    private var terminationHandler: (@Sendable () -> Void)?

    public init(
        writer: any FanWriting,
        capabilities: HardwareCapabilities?,
        clock: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.writer = writer
        self.capabilities = capabilities
        self.clock = clock
        self.lastHeartbeat = clock()
    }

    public var isTerminated: Bool {
        lock.withLock { terminated }
    }

    public func handle(_ request: ControlRequest) -> ControlResponse {
        if let response = terminatedResponse(for: request.id) {
            return response
        }

        operationLock.lock()
        defer {
            restoreAfterTerminationIfNeeded()
            operationLock.unlock()
        }
        return handleWhileHoldingOperationGate(request)
    }

    private func handleWhileHoldingOperationGate(
        _ request: ControlRequest
    ) -> ControlResponse {
        let duplicateOrTerminated = lock.withLock { () -> ControlResult? in
            if terminated {
                return .rejected(
                    code: "terminated",
                    message: "The control agent is terminating."
                )
            }
            guard processedRequestIDs.insert(request.id).inserted else {
                return .rejected(
                    code: "duplicate_request",
                    message: "Request ID was already processed."
                )
            }
            return nil
        }
        if let result = duplicateOrTerminated {
            return ControlResponse(id: request.id, result: result)
        }

        guard let capabilities else {
            return ControlResponse(
                id: request.id,
                result: .rejected(
                    code: "hardware_unavailable",
                    message: "Hardware probing has not succeeded."
                )
            )
        }

        switch request.command {
        case .status:
            lock.withLock {
                lastHeartbeat = clock()
            }
            let active = lock.withLock {
                manualFanIndices.sorted()
            }
            return ControlResponse(
                id: request.id,
                result: .status(
                    AgentStatus(
                        modelIdentifier: capabilities.modelIdentifier,
                        fans: capabilities.fans,
                        manualFanIndices: active
                    )
                )
            )

        case .heartbeat:
            lock.withLock {
                lastHeartbeat = clock()
            }
            return ControlResponse(
                id: request.id,
                result: .acknowledged
            )

        case .setRPM(let fanIndex, let rpm):
            guard let fan = capabilities.fans.first(
                where: { $0.index == fanIndex }
            ) else {
                return ControlResponse(
                    id: request.id,
                    result: .rejected(
                        code: "unknown_fan",
                        message: "Fan index \(fanIndex) is not available."
                    )
                )
            }
            do {
                try writer.setRPM(rpm, for: fan)
                _ = lock.withLock {
                    manualFanIndices.insert(fanIndex)
                }
                return ControlResponse(
                    id: request.id,
                    result: .acknowledged
                )
            } catch {
                return failureResponse(request.id, error: error)
            }

        case .restoreSystemAuto:
            do {
                try writer.restoreSystemAuto(capabilities.fans)
                lock.withLock {
                    manualFanIndices.removeAll()
                }
                return ControlResponse(
                    id: request.id,
                    result: .acknowledged
                )
            } catch {
                return failureResponse(request.id, error: error)
            }

        case .shutdown:
            let transition = beginTerminationIfNeeded(
                watchdogMustBeExpired: false
            )
            if transition.didBegin {
                scheduleRestoration()
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + 0.05
            ) {
                transition.handler?()
            }
            return ControlResponse(
                id: request.id,
                result: .acknowledged
            )
        }
    }

    public func startWatchdog(
        terminationHandler: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            self.terminationHandler = terminationHandler
        }
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.checkWatchdog()
        }
        lock.withLock {
            watchdog = timer
        }
        timer.resume()
    }

    public func checkWatchdog() {
        let transition = beginTerminationIfNeeded(
            watchdogMustBeExpired: true
        )
        guard transition.didBegin else {
            return
        }
        scheduleRestoration()
        transition.handler?()
    }

    public func cleanup() {
        let transition = beginTerminationIfNeeded(
            watchdogMustBeExpired: false
        )
        if transition.didBegin {
            scheduleRestoration()
        }
    }

    func waitForTerminationRestoration(
        timeout: DispatchTime
    ) -> Bool {
        restorationGroup.wait(timeout: timeout) == .success
    }

    private func terminatedResponse(
        for id: UUID
    ) -> ControlResponse? {
        lock.withLock {
            guard terminated else {
                return nil
            }
            return ControlResponse(
                id: id,
                result: .rejected(
                    code: "terminated",
                    message: "The control agent is terminating."
                )
            )
        }
    }

    private func beginTerminationIfNeeded(
        watchdogMustBeExpired: Bool
    ) -> (
        didBegin: Bool,
        handler: (@Sendable () -> Void)?
    ) {
        lock.withLock {
            guard !terminated else {
                return (false, nil)
            }
            if watchdogMustBeExpired,
               clock() - lastHeartbeat < 6 {
                return (false, nil)
            }
            terminated = true
            watchdog?.cancel()
            watchdog = nil
            restorationGroup.enter()
            return (true, terminationHandler)
        }
    }

    private func scheduleRestoration() {
        restorationQueue.async { [self] in
            operationLock.lock()
            restoreAfterTerminationIfNeeded()
            operationLock.unlock()
            restorationGroup.leave()
        }
    }

    private func restoreAfterTerminationIfNeeded() {
        let shouldRestore = lock.withLock {
            terminated && !restorationCompleted
        }
        guard shouldRestore else {
            return
        }
        guard let fans = capabilities?.fans else {
            lock.withLock {
                restorationCompleted = true
            }
            return
        }
        do {
            try writer.restoreSystemAuto(fans)
        } catch {
            return
        }
        lock.withLock {
            manualFanIndices.removeAll()
            restorationCompleted = true
        }
    }

    private func failureResponse(
        _ id: UUID,
        error: Error
    ) -> ControlResponse {
        ControlResponse(
            id: id,
            result: .rejected(
                code: "control_failed",
                message: error.localizedDescription
            )
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
