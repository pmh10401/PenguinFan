import AppKit
import FanControllerCore
import Foundation
import SMCKit

@MainActor
final class RuntimeController: ObservableObject {
    private let launcher = AuthorizationLauncher()
    private let injectedServiceManager: PrivilegedServiceManager?
    private let legacyFallbackEnabled: () -> Bool
    private let terminationBox = TerminationCoordinatorBox()
    private var coordinator: ControlCoordinator?
    private var sensorTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var lastSnapshotAt: Date?
    private weak var model: AppModel?

    private lazy var defaultServiceManager = PrivilegedServiceManager(
        restoreSystemModeAndDisconnect: { [weak self] in
            await self?.restoreAndShutdown()
        },
        connectionFailureHandler: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleConnectionFailure()
            }
        }
    )

    private var serviceManager: PrivilegedServiceManager {
        injectedServiceManager ?? defaultServiceManager
    }

    init(
        serviceManager: PrivilegedServiceManager? = nil,
        legacyFallbackEnabled: @escaping () -> Bool = { false }
    ) {
        injectedServiceManager = serviceManager
        self.legacyFallbackEnabled = legacyFallbackEnabled
    }

    func start(model: AppModel, startSensors: Bool = true) {
        guard !started else {
            return
        }
        started = true
        self.model = model
        serviceManager.refreshStatus()
        model.privilegedServiceState = serviceManager.state
        model.modeRequestGenerationHandler = {
            [weak self, weak model] mode, generation in
            guard let self, let model else {
                return
            }
            Task {
                await self.request(
                    mode: mode,
                    generation: generation,
                    model: model
                )
            }
        }
        model.privilegedApprovalHandler = {
            [weak self, weak model] generation in
            guard let self, let model else {
                return
            }
            await self.confirmPrivilegedControl(
                generation: generation,
                model: model
            )
        }
        model.privilegedApprovalSettingsHandler = {
            [weak self] in
            self?.serviceManager.openApprovalSettings()
        }
        installLifecycleObservers()
        if startSensors {
            startReadOnlySensors(model: model)
        }
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
        generation: UInt64,
        model: AppModel
    ) async {
        guard model.isCurrentModeRequest(generation) else {
            return
        }

        if mode == .systemAuto {
            if let coordinator {
                do {
                    try await coordinator.restoreSystemAuto()
                    model.markSystemAuto(ifCurrent: generation)
                } catch {
                    await failControl(
                        error,
                        generation: generation,
                        model: model
                    )
                }
            } else {
                model.markSystemAuto(ifCurrent: generation)
            }
            return
        }

        do {
            let coordinator = try await ensureCoordinator(
                generation: generation,
                model: model
            )
            guard model.isCurrentModeRequest(generation) else {
                return
            }
            await coordinator.update(settings: model.settings)
            guard model.isCurrentModeRequest(generation) else {
                return
            }
            if let snapshot = model.snapshot {
                try await coordinator.apply(snapshot: snapshot)
            }
            guard model.isCurrentModeRequest(generation) else {
                return
            }
            startHeartbeat(
                coordinator: coordinator,
                generation: generation,
                model: model
            )
            model.controlStatus = mode == .curve ? .curve : .manual
            model.diagnosticMessage = nil
        } catch is StaleModeRequestError {
            return
        } catch {
            await failControl(
                error,
                generation: generation,
                model: model
            )
        }
    }

    private func confirmPrivilegedControl(
        generation: UInt64,
        model: AppModel
    ) async {
        guard model.isCurrentModeRequest(generation),
              model.pendingPrivilegedMode != nil
        else {
            return
        }

        serviceManager.refreshStatus()
        if serviceManager.state == .notRegistered {
            serviceManager.register()
        }
        guard model.isCurrentModeRequest(generation) else {
            return
        }
        model.privilegedServiceState = serviceManager.state

        switch serviceManager.state {
        case .enabled:
            guard let mode = model.applyPendingPrivilegedMode(
                generation: generation
            ) else {
                return
            }
            await request(
                mode: mode,
                generation: generation,
                model: model
            )
        case .requiresApproval:
            guard model.isCurrentModeRequest(generation) else {
                return
            }
            model.settings.mode = .systemAuto
            model.controlStatus = .authorizing
            model.isPrivilegedApprovalPresented = true
            model.diagnosticMessage =
                "시스템 설정의 로그인 항목에서 PenguinFan 권한 서비스를 승인한 뒤 계속을 다시 선택하세요."
        case .failed(let message):
            if legacyFallbackEnabled(),
               let mode = model.applyPendingPrivilegedMode(
                   generation: generation
               ) {
                await request(
                    mode: mode,
                    generation: generation,
                    model: model
                )
            } else {
                await failPendingApproval(
                    message,
                    generation: generation,
                    model: model
                )
            }
        case .notFound:
            if legacyFallbackEnabled(),
               let mode = model.applyPendingPrivilegedMode(
                   generation: generation
               ) {
                await request(
                    mode: mode,
                    generation: generation,
                    model: model
                )
            } else {
                await failPendingApproval(
                    "앱에 실험적 권한 서비스가 포함되어 있지 않습니다.",
                    generation: generation,
                    model: model
                )
            }
        case .notRegistered, .registering:
            await failPendingApproval(
                "권한 서비스 등록이 완료되지 않았습니다.",
                generation: generation,
                model: model
            )
        }
    }

    private func ensureCoordinator(
        generation: UInt64,
        model: AppModel
    ) async throws -> ControlCoordinator {
        guard model.isCurrentModeRequest(generation) else {
            throw StaleModeRequestError()
        }
        if let coordinator {
            return coordinator
        }
        guard let fans = model.capabilities?.fans, !fans.isEmpty else {
            throw AuthorizationLauncherError.agentFailed(
                "읽기 전용 하드웨어 진단이 먼저 성공해야 합니다."
            )
        }

        let client: any ControlClient
        if legacyFallbackEnabled() {
            let socketURL = try await launcher.startAgent()
            client = UnixSocketControlClient(path: socketURL.path)
        } else {
            guard serviceManager.state == .enabled else {
                throw AuthorizationLauncherError.agentFailed(
                    "권한 서비스가 활성화되지 않았습니다."
                )
            }
            client = serviceManager.makeControlClient()
        }
        let coordinator = ControlCoordinator(
            client: client,
            settings: model.settings,
            fans: fans
        )
        _ = try await coordinator.status()
        guard model.isCurrentModeRequest(generation) else {
            throw StaleModeRequestError()
        }
        self.coordinator = coordinator
        terminationBox.set(coordinator)
        model.ipcConnected = true
        return coordinator
    }

    private func startHeartbeat(
        coordinator: ControlCoordinator,
        generation: UInt64,
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
                    await self.failControl(
                        error,
                        generation: generation,
                        model: model
                    )
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
            await failControl(
                error,
                generation: model.modeRequestGeneration,
                model: model
            )
        }
    }

    private func handleSensorErrorIfStale(model: AppModel) {
        guard model.settings.mode != .systemAuto,
              let lastSnapshotAt,
              Date().timeIntervalSince(lastSnapshotAt) > 5
        else {
            return
        }
        let generation = model.modeRequestGeneration
        Task {
            await failControl(
                ControlCoordinatorError.missingTemperature,
                generation: generation,
                model: model
            )
        }
    }

    private func failControl(
        _ error: Error,
        generation: UInt64,
        model: AppModel
    ) async {
        guard model.isCurrentModeRequest(generation) else {
            return
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let coordinator {
            try? await coordinator.restoreSystemAuto()
        }
        self.coordinator = nil
        terminationBox.set(nil)
        model.ipcConnected = false
        model.controlStatus = .failed
        model.settings.mode = .systemAuto
        model.privilegedServiceState = .failed(
            error.localizedDescription
        )
        model.diagnosticMessage =
            "팬 제어 권한 서비스에 연결하지 못했습니다. \(error.localizedDescription) 시스템 설정을 확인하세요. 읽기 전용 모드를 유지합니다."
    }

    private func failPendingApproval(
        _ message: String,
        generation: UInt64,
        model: AppModel
    ) async {
        await failControl(
            AuthorizationLauncherError.agentFailed(message),
            generation: generation,
            model: model
        )
        guard model.isCurrentModeRequest(generation) else {
            return
        }
        model.pendingPrivilegedMode = nil
        model.isPrivilegedApprovalPresented = false
    }

    private func handleConnectionFailure() async {
        guard let model else {
            return
        }
        await failControl(
            XPCControlClientError.invalidated,
            generation: model.modeRequestGeneration,
            model: model
        )
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

private struct StaleModeRequestError: Error {}

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
