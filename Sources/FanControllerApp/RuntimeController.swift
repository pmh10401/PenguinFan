import AppKit
import FanControllerCore
import Foundation
import SMCKit

@MainActor
final class RuntimeController: ObservableObject {
    private let launcher = AuthorizationLauncher()
    private let terminationBox = TerminationCoordinatorBox()
    private var coordinator: ControlCoordinator?
    private var sensorTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var lastSnapshotAt: Date?
    private weak var model: AppModel?

    func start(model: AppModel) {
        guard !started else {
            return
        }
        started = true
        self.model = model
        model.modeRequestHandler = { [weak self, weak model] mode in
            guard let self, let model else {
                return
            }
            Task { await self.request(mode: mode, model: model) }
        }
        installLifecycleObservers()
        startReadOnlySensors(model: model)
    }

    private func startReadOnlySensors(model: AppModel) {
        sensorTask?.cancel()
        do {
            let connection = try SMCConnection()
            let capabilities = try HardwareProbe(
                transport: connection
            ).probe()
            let reader = SensorReader(
                transport: connection,
                capabilities: capabilities
            )
            model.capabilities = capabilities
            model.diagnosticMessage = nil

            let poller = SensorPoller {
                try reader.snapshot()
            }
            sensorTask = Task { [weak self, weak model] in
                await poller.run { snapshot in
                    guard let self, let model else {
                        return
                    }
                    self.lastSnapshotAt = snapshot.timestamp
                    model.record(snapshot)
                    Task {
                        await self.process(
                            snapshot: snapshot,
                            model: model
                        )
                    }
                } reportError: { message in
                    guard let self, let model else {
                        return
                    }
                    model.diagnosticMessage = message
                    self.handleSensorErrorIfStale(model: model)
                }
            }
        } catch {
            model.diagnosticMessage = error.localizedDescription
            model.capabilities = nil
        }
    }

    private func request(
        mode: ControlMode,
        model: AppModel
    ) async {
        if mode == .systemAuto {
            if let coordinator {
                do {
                    try await coordinator.restoreSystemAuto()
                    model.markSystemAuto()
                } catch {
                    await failControl(error, model: model)
                }
            } else {
                model.markSystemAuto()
            }
            return
        }

        do {
            let coordinator = try await ensureCoordinator(model: model)
            await coordinator.update(settings: model.settings)
            if let snapshot = model.snapshot {
                try await coordinator.apply(snapshot: snapshot)
            }
            model.controlStatus = mode == .curve ? .curve : .manual
            model.diagnosticMessage = nil
        } catch {
            await failControl(error, model: model)
        }
    }

    private func ensureCoordinator(
        model: AppModel
    ) async throws -> ControlCoordinator {
        if let coordinator {
            return coordinator
        }
        guard let fans = model.capabilities?.fans, !fans.isEmpty else {
            throw AuthorizationLauncherError.agentFailed(
                "읽기 전용 하드웨어 진단이 먼저 성공해야 합니다."
            )
        }

        let socketURL = try await launcher.startAgent()
        let coordinator = ControlCoordinator(
            client: UnixSocketControlClient(path: socketURL.path),
            settings: model.settings,
            fans: fans
        )
        _ = try await coordinator.status()
        self.coordinator = coordinator
        terminationBox.set(coordinator)
        model.ipcConnected = true
        startHeartbeat(coordinator: coordinator, model: model)
        return coordinator
    }

    private func startHeartbeat(
        coordinator: ControlCoordinator,
        model: AppModel
    ) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak model] in
            while !Task.isCancelled {
                do {
                    try await coordinator.heartbeat()
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    guard let self, let model else {
                        return
                    }
                    await self.failControl(error, model: model)
                    return
                }
            }
        }
    }

    private func process(
        snapshot: SensorSnapshot,
        model: AppModel
    ) async {
        guard let coordinator,
              model.settings.mode != .systemAuto
        else {
            return
        }
        do {
            try await coordinator.verifyFanResponse(snapshot: snapshot)
            await coordinator.update(settings: model.settings)
            try await coordinator.apply(snapshot: snapshot)
        } catch {
            await failControl(error, model: model)
        }
    }

    private func handleSensorErrorIfStale(model: AppModel) {
        guard model.settings.mode != .systemAuto,
              let lastSnapshotAt,
              Date().timeIntervalSince(lastSnapshotAt) > 5
        else {
            return
        }
        Task { await failControl(ControlCoordinatorError.missingTemperature, model: model) }
    }

    private func failControl(
        _ error: Error,
        model: AppModel
    ) async {
        if let coordinator {
            try? await coordinator.restoreSystemAuto()
        }
        model.controlStatus = .failed
        model.settings.mode = .systemAuto
        model.diagnosticMessage = error.localizedDescription
    }

    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.restoreAndShutdown()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let model = self.model else {
                        return
                    }
                    model.markSystemAuto()
                    self.startReadOnlySensors(model: model)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [terminationBox] _ in
                guard let coordinator = terminationBox.get() else {
                    return
                }
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    await coordinator.restoreAndShutdown()
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 1)
            }
        )
    }

    private func restoreAndShutdown() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let coordinator {
            await coordinator.restoreAndShutdown()
        }
        self.coordinator = nil
        terminationBox.set(nil)
        model?.ipcConnected = false
        model?.markSystemAuto()
    }
}

private final class TerminationCoordinatorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: ControlCoordinator?

    func set(_ coordinator: ControlCoordinator?) {
        lock.lock()
        self.coordinator = coordinator
        lock.unlock()
    }

    func get() -> ControlCoordinator? {
        lock.lock()
        defer { lock.unlock() }
        return coordinator
    }
}
