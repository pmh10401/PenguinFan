import Foundation
import FanControllerCore
import ServiceManagement
import SMCKit
import XCTest

@testable import FanControlIPC
@testable import FanControllerApp

@MainActor
final class PrivilegedServiceManagerTests: XCTestCase {
    func testTask5ServiceStatusLabelsAndActionVisibility() {
        let cases: [
            (
                PrivilegedServiceState,
                String,
                canApprove: Bool,
                canRemove: Bool
            )
        ] = [
            (.notRegistered, "미등록", false, false),
            (.registering, "미등록", false, false),
            (.requiresApproval, "승인 대기", true, true),
            (.enabled, "활성", false, true),
            (.notFound, "등록 확인 필요", false, false),
            (.failed("expected"), "오류", false, false),
        ]
        let model = AppModel()

        for item in cases {
            model.privilegedServiceState = item.0

            XCTAssertEqual(model.privilegedServiceStatusLabel, item.1)
            XCTAssertEqual(
                model.canOpenPrivilegedApprovalSettings,
                item.canApprove
            )
            XCTAssertEqual(
                model.canRemovePrivilegedService,
                item.canRemove
            )
        }
    }

    func testTask5LegacyFallbackIsExplicitAndOffByDefault() {
        let model = AppModel()

        XCTAssertFalse(model.legacyFallbackEnabled)

        model.legacyFallbackEnabled = true

        XCTAssertTrue(model.legacyFallbackEnabled)
    }

    func testTask5RemovalRequiresConfirmationAndRestoresBeforeUnregister()
        async
    {
        let events = EventRecorder()
        let service = FakeServiceRegistration(status: .enabled)
        service.onUnregister = {
            events.append("unregister")
            service.status = .notRegistered
        }
        let manager = makeManager(
            service: service,
            restoreAndDisconnect: {
                events.append("restore-and-disconnect")
            }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        model.privilegedServiceState = .enabled
        model.settings.mode = .manual
        runtime.start(model: model, startSensors: false)

        await model.confirmPrivilegedServiceRemoval()
        XCTAssertEqual(service.unregisterCallCount, 0)

        model.requestPrivilegedServiceRemoval()
        XCTAssertTrue(
            model.isPrivilegedServiceRemovalConfirmationPresented
        )

        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(
            events.values,
            ["restore-and-disconnect", "unregister"]
        )
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertFalse(model.ipcConnected)
        XCTAssertEqual(model.privilegedServiceState, .notRegistered)
        XCTAssertFalse(model.isPrivilegedServiceRemovalInProgress)
    }

    func testTask5RemovalInvalidatesAnOlderModeGeneration() async {
        let service = FakeServiceRegistration(status: .enabled)
        service.onUnregister = { service.status = .notRegistered }
        let manager = makeManager(service: service)
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)
        model.privilegedServiceState = .enabled
        model.selectMode(.manual)
        let customModeGeneration = model.modeRequestGeneration

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertFalse(
            model.isCurrentModeRequest(customModeGeneration)
        )
        XCTAssertEqual(model.settings.mode, .systemAuto)
    }

    func testTask5RestoreFailureAbortsUnregisterAndKeepsServiceUsable()
        async
    {
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            restoreAndDisconnect: {
                throw TestFailure.expected
            }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)
        model.settings.mode = .manual
        model.controlStatus = .manual
        model.ipcConnected = true

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.state, .enabled)
        XCTAssertEqual(model.privilegedServiceState, .enabled)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertFalse(model.ipcConnected)
        XCTAssertTrue(model.requiresFreshPrivilegedConfirmation)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertTrue(
            model.diagnosticMessage?.contains("제거하지 않았습니다")
                == true
        )
    }

    func testTask5RestoreTimeoutFailsClosedWithoutUnregister() async {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let status = AgentStatus(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            manualFanIndices: []
        )
        let connection = FakeXPCConnection(
            behaviors: [.reply(.status(status)), .hold]
        )
        let service = FakeServiceRegistration(status: .enabled)
        var runtime: RuntimeController!
        let manager = PrivilegedServiceManager(
            service: service,
            restoreSystemModeAndDisconnect: {
                try await runtime.restoreForPrivilegedServiceRemoval()
            },
            connectionFactory: { connection },
            connectionFailureHandler: {},
            requestTimeout: 0.01
        )
        runtime = RuntimeController(serviceManager: manager)
        let requestCompleted = expectation(
            description: "Initial manual request completed"
        )
        runtime.modeRequestCompletionObserver = { _ in
            requestCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)
        model.selectMode(.manual)
        await fulfillment(of: [requestCompleted], timeout: 1)
        XCTAssertEqual(model.controlStatus, .manual)

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertTrue(model.requiresFreshPrivilegedConfirmation)
        XCTAssertFalse(model.ipcConnected)
    }

    func testTask5RestoreInvalidationFailsClosedWithoutUnregister()
        async
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let status = AgentStatus(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            manualFanIndices: []
        )
        let connection = FakeXPCConnection(
            behaviors: [.reply(.status(status)), .invalidate]
        )
        let service = FakeServiceRegistration(status: .enabled)
        var runtime: RuntimeController!
        let manager = PrivilegedServiceManager(
            service: service,
            restoreSystemModeAndDisconnect: {
                try await runtime.restoreForPrivilegedServiceRemoval()
            },
            connectionFactory: { connection },
            connectionFailureHandler: {},
            requestTimeout: 1
        )
        runtime = RuntimeController(serviceManager: manager)
        let requestCompleted = expectation(
            description: "Initial curve request completed"
        )
        runtime.modeRequestCompletionObserver = { _ in
            requestCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)
        model.selectMode(.curve)
        await fulfillment(of: [requestCompleted], timeout: 1)

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertTrue(model.requiresFreshPrivilegedConfirmation)
        XCTAssertFalse(model.ipcConnected)
    }

    func testTask5UnregisterFailureAfterTeardownStaysSystem() async {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let status = AgentStatus(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            manualFanIndices: []
        )
        let connection = FakeXPCConnection(
            behaviors: [
                .reply(.status(status)),
                .reply(.acknowledged),
                .reply(.acknowledged),
                .reply(.acknowledged),
            ]
        )
        let service = FakeServiceRegistration(status: .enabled)
        service.unregisterError = TestFailure.expected
        var runtime: RuntimeController!
        let manager = PrivilegedServiceManager(
            service: service,
            restoreSystemModeAndDisconnect: {
                try await runtime.restoreForPrivilegedServiceRemoval()
            },
            connectionFactory: { connection },
            connectionFailureHandler: {},
            requestTimeout: 1
        )
        runtime = RuntimeController(serviceManager: manager)
        let requestCompleted = expectation(
            description: "Initial custom request completed"
        )
        runtime.modeRequestCompletionObserver = { _ in
            requestCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)
        model.selectMode(.manual)
        await fulfillment(of: [requestCompleted], timeout: 1)

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(manager.state, .enabled)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertTrue(model.requiresFreshPrivilegedConfirmation)
        XCTAssertFalse(model.ipcConnected)
        XCTAssertFalse(
            model.diagnosticMessage?.contains(
                "실험적 권한 서비스를 제거했습니다"
            ) == true
        )
    }

    func testTask5MissingCoordinatorFailsClosedWithoutUnregister()
        async
    {
        let service = FakeServiceRegistration(status: .enabled)
        var runtime: RuntimeController!
        let manager = PrivilegedServiceManager(
            service: service,
            restoreSystemModeAndDisconnect: {
                try await runtime.restoreForPrivilegedServiceRemoval()
            },
            connectionFailureHandler: {}
        )
        runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)

        model.requestPrivilegedServiceRemoval()
        await model.confirmPrivilegedServiceRemoval()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.state, .enabled)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertTrue(model.requiresFreshPrivilegedConfirmation)
        XCTAssertTrue(
            model.diagnosticMessage?.contains("제거하지 않았습니다")
                == true
        )
    }

    func testTask5RemovalBlocksConcurrentAndInflightCustomModes()
        async throws
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let connection = FakeXPCConnection(behavior: .hold)
        let restoreStarted = expectation(
            description: "Removal restore started"
        )
        let restoreGate = ManualAsyncGate()
        let service = FakeServiceRegistration(status: .enabled)
        service.onUnregister = { service.status = .notRegistered }
        let manager = makeManager(
            service: service,
            restoreAndDisconnect: {
                restoreStarted.fulfill()
                await restoreGate.wait()
            },
            connectionFactory: { connection }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let staleRequestCompleted = expectation(
            description: "Stale request completed"
        )
        runtime.modeRequestCompletionObserver = { _ in
            staleRequestCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)

        model.selectMode(.curve)
        await waitForRequest(connection)
        XCTAssertEqual(connection.requestCount, 1)

        model.requestPrivilegedServiceRemoval()
        let removal = Task {
            await model.confirmPrivilegedServiceRemoval()
        }
        await fulfillment(of: [restoreStarted], timeout: 1)
        let removalGeneration = model.modeRequestGeneration

        model.selectMode(.manual)

        XCTAssertEqual(
            model.modeRequestGeneration,
            removalGeneration
        )
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(connection.requestCount, 1)

        await restoreGate.open()
        await removal.value
        try connection.replyToHeldRequest(
            with: .status(
                AgentStatus(
                    modelIdentifier: "Mac14,6",
                    fans: [fan],
                    manualFanIndices: []
                )
            )
        )
        await fulfillment(of: [staleRequestCompleted], timeout: 1)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(model.privilegedServiceState, .notRegistered)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertFalse(model.ipcConnected)
    }

    func testSelectingCustomModeWithoutEnabledServiceDefersRuntimeRequest() {
        let model = AppModel()
        var requestedModes: [ControlMode] = []
        model.modeRequestHandler = { requestedModes.append($0) }

        model.selectMode(.curve)

        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.pendingPrivilegedMode, .curve)
        XCTAssertTrue(model.isPrivilegedApprovalPresented)
        XCTAssertEqual(model.controlStatus, .authorizing)
        XCTAssertTrue(requestedModes.isEmpty)
    }

    func testCancellingApprovalReturnsToSystemWithoutRuntimeRequest() {
        let model = AppModel()
        var requestedModes: [ControlMode] = []
        model.modeRequestHandler = { requestedModes.append($0) }
        model.selectMode(.manual)

        model.cancelPrivilegedApproval()

        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.isPrivilegedApprovalPresented)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertTrue(requestedModes.isEmpty)
    }

    func testEnabledServiceAppliesCustomSelectionWithoutApproval() {
        let model = AppModel()
        var requestedModes: [ControlMode] = []
        model.modeRequestHandler = { requestedModes.append($0) }
        model.privilegedServiceState = .enabled

        model.selectMode(.manual)

        XCTAssertEqual(model.settings.mode, .manual)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.isPrivilegedApprovalPresented)
        XCTAssertEqual(requestedModes, [.manual])
    }

    func testNotFoundExplicitConfirmationWaitsForReadinessBeforePendingMode()
        async throws
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let status = AgentStatus(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            manualFanIndices: []
        )
        let connection = FakeXPCConnection(behavior: .hold)
        let service = FakeServiceRegistration(status: .notFound)
        service.onRegister = { service.status = .enabled }
        let manager = makeManager(
            service: service,
            connectionFactory: { connection }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)
        model.selectMode(.curve)

        XCTAssertEqual(service.registerCallCount, 0)

        let confirmation = Task {
            await model.confirmPrivilegedApproval()
        }
        await waitForRequest(connection)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.pendingPrivilegedMode, .curve)
        XCTAssertNotEqual(model.controlStatus, .curve)

        try connection.replyToHeldRequest(with: .status(status))
        await confirmation.value

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(model.privilegedServiceState, .enabled)
        XCTAssertEqual(model.settings.mode, .curve)
        XCTAssertEqual(model.controlStatus, .curve)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.isPrivilegedApprovalPresented)
        XCTAssertTrue(model.ipcConnected)
    }

    func testApprovalRequiredKeepsPendingModeAndOffersSystemSettings() async {
        let service = FakeServiceRegistration(status: .notRegistered)
        service.onRegister = { service.status = .requiresApproval }
        var openSettingsCount = 0
        let manager = makeManager(
            service: service,
            approvalSettingsOpener: {
                openSettingsCount += 1
            }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)
        model.selectMode(.manual)

        await model.confirmPrivilegedApproval()

        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.pendingPrivilegedMode, .manual)
        XCTAssertTrue(model.isPrivilegedApprovalPresented)
        XCTAssertEqual(model.privilegedServiceState, .requiresApproval)
        XCTAssertTrue(
            model.diagnosticMessage?.contains("시스템 설정") == true
        )

        model.openPrivilegedApprovalSettings()
        XCTAssertEqual(openSettingsCount, 1)
    }

    func testRegistrationFailureReturnsSafelyToSystemWithActionableStatus()
        async
    {
        let service = FakeServiceRegistration(status: .notFound)
        service.registerError = TestFailure.expected
        let manager = makeManager(service: service)
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)
        model.selectMode(.curve)

        await model.confirmPrivilegedApproval()
        await model.confirmPrivilegedApproval()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .failed)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.isPrivilegedApprovalPresented)
        XCTAssertTrue(
            model.diagnosticMessage?.contains("읽기 전용") == true
        )
        XCTAssertFalse(model.ipcConnected)
    }

    func testStaleConfirmationAfterSystemSelectionDoesNotRegister() async {
        let service = FakeServiceRegistration(status: .notFound)
        let manager = makeManager(service: service)
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        runtime.start(model: model, startSensors: false)
        model.selectMode(.curve)
        model.selectMode(.systemAuto)

        await model.confirmPrivilegedApproval()

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.ipcConnected)
    }

    func testSystemSelectionWinsOverInFlightCurveReadiness() async throws {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let connection = FakeXPCConnection(behavior: .hold)
        let service = FakeServiceRegistration(status: .notFound)
        service.onRegister = { service.status = .enabled }
        let manager = makeManager(
            service: service,
            connectionFactory: { connection }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)
        model.selectMode(.curve)

        let confirmation = Task {
            await model.confirmPrivilegedApproval()
        }
        await waitForRequest(connection)
        model.selectMode(.systemAuto)
        try connection.replyToHeldRequest(
            with: .status(
                AgentStatus(
                    modelIdentifier: "Mac14,6",
                    fans: [fan],
                    manualFanIndices: []
                )
            )
        )
        await confirmation.value

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertFalse(model.ipcConnected)
    }

    func testLatestRepeatedCustomModeWinsWhenReadinessCompletesOutOfOrder()
        async throws
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let curveConnection = FakeXPCConnection(behavior: .hold)
        let manualConnection = FakeXPCConnection(behavior: .hold)
        var connections = [curveConnection, manualConnection]
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            connectionFactory: { connections.removeFirst() }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let requestsCompleted = expectation(
            description: "Both out-of-order requests completed"
        )
        requestsCompleted.expectedFulfillmentCount = 2
        runtime.modeRequestCompletionObserver = { _ in
            requestsCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)

        model.selectMode(.curve)
        await waitForRequest(curveConnection)
        model.selectMode(.manual)
        await waitForRequest(manualConnection)

        let status = AgentStatus(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            manualFanIndices: []
        )
        try manualConnection.replyToHeldRequest(with: .status(status))
        try curveConnection.replyToHeldRequest(with: .status(status))
        await fulfillment(of: [requestsCompleted], timeout: 1)

        XCTAssertEqual(model.settings.mode, .manual)
        XCTAssertEqual(model.controlStatus, .manual)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertTrue(model.ipcConnected)
    }

    func testStaleReadinessFailureDoesNotReplaceNewerSystemStatus()
        async throws
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let connection = FakeXPCConnection(behavior: .hold)
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            connectionFactory: { connection }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let requestsCompleted = expectation(
            description: "System and stale Curve requests completed"
        )
        requestsCompleted.expectedFulfillmentCount = 2
        runtime.modeRequestCompletionObserver = { _ in
            requestsCompleted.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)

        model.selectMode(.curve)
        await waitForRequest(connection)
        model.selectMode(.systemAuto)
        try connection.replyToHeldRequest(
            with: .rejected(
                code: "denied",
                message: "stale failure"
            )
        )
        await fulfillment(of: [requestsCompleted], timeout: 1)

        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertNil(model.diagnosticMessage)
        XCTAssertFalse(model.ipcConnected)
    }

    func testOldConnectionInvalidationDoesNotOverwriteNewerSystemSelection()
        async
    {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let oldConnection = FakeXPCConnection(behavior: .hold)
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            connectionFactory: { oldConnection }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let staleEventProcessed = expectation(
            description: "Old invalidation processed"
        )
        let oldCurveRequestCompleted = expectation(
            description: "Old Curve request completed after invalidation"
        )
        let systemRequestCompleted = expectation(
            description: "Newer System request completed"
        )
        let oldCurveGeneration = modelGeneration(after: 0)
        let systemGeneration = modelGeneration(after: oldCurveGeneration)
        runtime.modeRequestCompletionObserver = { generation in
            switch generation {
            case oldCurveGeneration:
                oldCurveRequestCompleted.fulfill()
            case systemGeneration:
                systemRequestCompleted.fulfill()
            default:
                XCTFail("Unexpected mode request generation \(generation)")
            }
        }
        runtime.connectionFailureEventObserver = { isActive in
            XCTAssertFalse(isActive)
            staleEventProcessed.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)

        model.selectMode(.curve)
        await waitForRequest(oldConnection)
        model.selectMode(.systemAuto)
        await fulfillment(of: [systemRequestCompleted], timeout: 1)
        oldConnection.invalidationHandler?()
        await fulfillment(
            of: [staleEventProcessed, oldCurveRequestCompleted],
            timeout: 1
        )

        XCTAssertEqual(model.settings.mode, .systemAuto)
        XCTAssertEqual(model.controlStatus, .systemAuto)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertNil(model.diagnosticMessage)
        XCTAssertFalse(model.ipcConnected)
    }

    func testOldConnectionInvalidationDoesNotOverwriteNewerManualSuccess()
        async throws
    {
        try await assertOldConnectionEventDoesNotOverwriteNewerManual(
            .invalidation
        )
    }

    func testOldConnectionInterruptionDoesNotOverwriteNewerManualSuccess()
        async throws
    {
        try await assertOldConnectionEventDoesNotOverwriteNewerManual(
            .interruption
        )
    }

    private func assertOldConnectionEventDoesNotOverwriteNewerManual(
        _ event: StaleConnectionEvent
    ) async throws {
        let fan = FanDescriptor(
            index: 0,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            modeKey: "F0Md"
        )
        let oldConnection = FakeXPCConnection(behavior: .hold)
        let currentConnection = FakeXPCConnection(behavior: .hold)
        var connections = [oldConnection, currentConnection]
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            connectionFactory: { connections.removeFirst() }
        )
        let runtime = RuntimeController(serviceManager: manager)
        let staleEventProcessed = expectation(
            description: "Old connection event processed"
        )
        let oldCurveRequestCompleted = expectation(
            description: "Old Curve request completed after stale event"
        )
        let manualRequestCompleted = expectation(
            description: "Newer Manual request completed"
        )
        let oldCurveGeneration = modelGeneration(after: 0)
        let manualGeneration = modelGeneration(after: oldCurveGeneration)
        runtime.modeRequestCompletionObserver = { generation in
            switch generation {
            case oldCurveGeneration:
                oldCurveRequestCompleted.fulfill()
            case manualGeneration:
                manualRequestCompleted.fulfill()
            default:
                XCTFail("Unexpected mode request generation \(generation)")
            }
        }
        runtime.connectionFailureEventObserver = { isActive in
            XCTAssertFalse(isActive)
            staleEventProcessed.fulfill()
        }
        let model = AppModel()
        model.capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan],
            ftstAvailable: true
        )
        runtime.start(model: model, startSensors: false)

        model.selectMode(.curve)
        await waitForRequest(oldConnection)
        model.selectMode(.manual)
        await waitForRequest(currentConnection)
        try currentConnection.replyToHeldRequest(
            with: .status(
                AgentStatus(
                    modelIdentifier: "Mac14,6",
                    fans: [fan],
                    manualFanIndices: []
                )
            )
        )
        await fulfillment(of: [manualRequestCompleted], timeout: 1)
        event.deliver(to: oldConnection)
        await fulfillment(
            of: [staleEventProcessed, oldCurveRequestCompleted],
            timeout: 1
        )

        XCTAssertEqual(model.settings.mode, .manual)
        XCTAssertEqual(model.controlStatus, .manual)
        XCTAssertNil(model.pendingPrivilegedMode)
        XCTAssertNil(model.diagnosticMessage)
        XCTAssertTrue(model.ipcConnected)
    }

    func testControlClientsUseConnectionScopedFailureHandlers() {
        let oldConnection = FakeXPCConnection(behavior: .hold)
        let currentConnection = FakeXPCConnection(behavior: .hold)
        var connections = [oldConnection, currentConnection]
        let manager = makeManager(
            connectionFactory: { connections.removeFirst() }
        )
        let oldFailureCount = LockedCounter()
        let currentFailureCount = LockedCounter()

        let oldClient = manager.makeControlClient {
            oldFailureCount.increment()
        }
        let currentClient = manager.makeControlClient {
            currentFailureCount.increment()
        }
        withExtendedLifetime((oldClient, currentClient)) {
            oldConnection.invalidationHandler?()
        }

        XCTAssertEqual(oldFailureCount.value, 1)
        XCTAssertEqual(currentFailureCount.value, 0)
    }

    func testRefreshStatusMapsEveryKnownServiceStatus() {
        let cases: [(SMAppService.Status, PrivilegedServiceState)] = [
            (.notRegistered, .notRegistered),
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .notFound),
        ]

        for (serviceStatus, expectedState) in cases {
            let service = FakeServiceRegistration(status: serviceStatus)
            let manager = makeManager(service: service)

            manager.refreshStatus()

            XCTAssertEqual(manager.state, expectedState)
        }
    }

    func testRegisterTransitionsThroughRegisteringAndRefreshesStatus() {
        let service = FakeServiceRegistration(status: .notRegistered)
        let manager = makeManager(service: service)
        var stateDuringRegistration: PrivilegedServiceState?
        service.onRegister = {
            stateDuringRegistration = manager.state
            service.status = .enabled
        }

        manager.register()

        XCTAssertEqual(stateDuringRegistration, .registering)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(manager.state, .enabled)
    }

    func testRefreshEnabledRegistrationKeepsExistingApproval() async {
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(service: service)

        await manager.refreshEnabledRegistration()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(manager.state, .enabled)
    }

    func testRegisterDoesNotMutateReadOnlyServiceStatuses() {
        let cases: [(SMAppService.Status, PrivilegedServiceState)] = [
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
        ]

        for (serviceStatus, expectedState) in cases {
            let service = FakeServiceRegistration(status: serviceStatus)
            let manager = makeManager(service: service)

            manager.register()

            XCTAssertEqual(service.registerCallCount, 0)
            XCTAssertEqual(manager.state, expectedState)
        }
    }

    func testNotFoundRegistrationRefreshesToApprovalOrEnabled() {
        let statuses: [SMAppService.Status] = [
            .requiresApproval,
            .enabled,
        ]

        for status in statuses {
            let service = FakeServiceRegistration(status: .notFound)
            let manager = makeManager(service: service)
            service.onRegister = {
                service.status = status
            }

            manager.register()

            XCTAssertEqual(service.registerCallCount, 1)
            XCTAssertEqual(
                manager.state,
                status == .enabled ? .enabled : .requiresApproval
            )
        }
    }

    func testNotFoundRegistrationErrorBecomesActionableFailure() {
        let service = FakeServiceRegistration(status: .notFound)
        service.registerError = TestFailure.expected
        let manager = makeManager(service: service)

        manager.register()
        manager.register()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(manager.state, .failed("expected failure"))
    }

    func testRegisteringAndFailedStatesDoNotDuplicateRegistration() {
        let service = FakeServiceRegistration(status: .notFound)
        service.registerError = TestFailure.expected
        let manager = makeManager(service: service)
        service.onRegister = {
            manager.register()
        }

        manager.register()
        manager.register()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(manager.state, .failed("expected failure"))
    }

    func testUnregisterRestoresAndDisconnectsBeforeRemovingService() async {
        let events = EventRecorder()
        let service = FakeServiceRegistration(status: .enabled)
        service.onUnregister = {
            events.append("unregister")
            service.status = .notRegistered
        }
        let manager = makeManager(
            service: service,
            restoreAndDisconnect: {
                events.append("restore-and-disconnect")
            }
        )

        await manager.unregister()

        XCTAssertEqual(
            events.values,
            ["restore-and-disconnect", "unregister"]
        )
        XCTAssertEqual(manager.state, .notRegistered)
    }

    func testUnregisterStopsWhenRuntimePreparationFails() async {
        let service = FakeServiceRegistration(status: .enabled)
        let manager = makeManager(
            service: service,
            restoreAndDisconnect: {
                throw TestFailure.expected
            }
        )

        await manager.unregister()

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.state, .enabled)
        XCTAssertEqual(manager.lastUnregisterError, "expected failure")
    }

    func testOpenApprovalSettingsUsesInjectedOpener() {
        var openCount = 0
        let manager = makeManager(
            approvalSettingsOpener: {
                openCount += 1
            }
        )

        manager.openApprovalSettings()

        XCTAssertEqual(openCount, 1)
    }

    func testMakeControlClientUsesInjectedConnection() async throws {
        let connection = FakeXPCConnection(behavior: .reply(.acknowledged))
        let manager = makeManager(
            connectionFactory: { connection }
        )

        let result = try await manager.makeControlClient().send(.heartbeat)

        XCTAssertEqual(result, .acknowledged)
        XCTAssertTrue(connection.didResume)
    }

    func testControlClientTimesOutAndIgnoresLateReply() async throws {
        let connection = FakeXPCConnection(behavior: .hold)
        let client = XPCControlClient(
            connection: connection,
            requestTimeout: 0.01,
            connectionFailureHandler: {}
        )

        await assertSendFails(client, as: .timedOut)
        try connection.replyToHeldRequest(with: .acknowledged)
    }

    func testOneTimeoutDrainsAllPendingRequestsAndIgnoresLateEvents()
        async throws
    {
        let connection = FakeXPCConnection(behavior: .hold)
        let timeoutScheduler = ManualTimeoutScheduler()
        let recoveryCount = LockedCounter()
        let client = XPCControlClient(
            connection: connection,
            requestTimeout: 60,
            connectionFailureHandler: {
                recoveryCount.increment()
            },
            timeoutScheduler: timeoutScheduler
        )
        let requestsCompleted = expectation(
            description: "Both pending requests complete"
        )
        requestsCompleted.expectedFulfillmentCount = 2
        let first = Task.detached {
            defer { requestsCompleted.fulfill() }
            do {
                _ = try await client.send(.heartbeat)
                return Optional<XPCControlClientError>.none
            } catch {
                return error as? XPCControlClientError
            }
        }
        let second = Task.detached {
            defer { requestsCompleted.fulfill() }
            do {
                _ = try await client.send(.heartbeat)
                return Optional<XPCControlClientError>.none
            } catch {
                return error as? XPCControlClientError
            }
        }
        XCTAssertEqual(
            connection.requestReceived.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            connection.requestReceived.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            timeoutScheduler.operationScheduled.wait(
                timeout: .now() + 1
            ),
            .success
        )
        XCTAssertEqual(
            timeoutScheduler.operationScheduled.wait(
                timeout: .now() + 1
            ),
            .success
        )

        timeoutScheduler.fireFirst()

        let completionResult = await XCTWaiter.fulfillment(
            of: [requestsCompleted],
            timeout: 1
        )
        if completionResult != .completed {
            connection.invalidate()
        }
        let firstError = await first.value
        let secondError = await second.value
        XCTAssertEqual(
            completionResult,
            .completed,
            "One timeout must complete every pending request."
        )
        XCTAssertEqual(firstError, .timedOut)
        XCTAssertEqual(secondError, .timedOut)
        XCTAssertEqual(connection.invalidateCallCount, 1)
        XCTAssertEqual(recoveryCount.value, 1)

        try connection.replyToAllHeldRequests(with: .acknowledged)
        timeoutScheduler.fireAll()
    }

    func testTimeoutForCompletedRequestDoesNotBreakConnection() async throws {
        let connection = FakeXPCConnection(
            behavior: .reply(.acknowledged)
        )
        let timeoutScheduler = ManualTimeoutScheduler()
        let recoveryCount = LockedCounter()
        let client = XPCControlClient(
            connection: connection,
            requestTimeout: 60,
            connectionFailureHandler: {
                recoveryCount.increment()
            },
            timeoutScheduler: timeoutScheduler
        )

        let result = try await client.send(.heartbeat)
        XCTAssertEqual(result, .acknowledged)
        XCTAssertEqual(
            timeoutScheduler.operationScheduled.wait(
                timeout: .now() + 1
            ),
            .success
        )

        timeoutScheduler.fireFirst()

        XCTAssertEqual(connection.invalidateCallCount, 0)
        XCTAssertEqual(recoveryCount.value, 0)
    }

    func testControlClientInterruptionFailsPendingReplyAndRequestsRecovery()
        async throws
    {
        let connection = FakeXPCConnection(behavior: .interrupt)
        let recoveryCount = LockedCounter()
        let client = XPCControlClient(
            connection: connection,
            requestTimeout: 1,
            connectionFailureHandler: {
                recoveryCount.increment()
            }
        )

        await assertSendFails(client, as: .interrupted)
        try connection.replyToHeldRequest(with: .acknowledged)

        XCTAssertEqual(recoveryCount.value, 1)
    }

    func testControlClientInvalidationFailsPendingReplyAndRequestsRecovery()
        async throws
    {
        let connection = FakeXPCConnection(behavior: .invalidate)
        let recoveryCount = LockedCounter()
        let client = XPCControlClient(
            connection: connection,
            requestTimeout: 1,
            connectionFailureHandler: {
                recoveryCount.increment()
            }
        )

        await assertSendFails(client, as: .invalidated)
        try connection.replyToHeldRequest(with: .acknowledged)

        XCTAssertEqual(recoveryCount.value, 1)
    }

    private func makeManager(
        service: FakeServiceRegistration = FakeServiceRegistration(
            status: .notRegistered
        ),
        restoreAndDisconnect: @escaping () async throws -> Void = {},
        connectionFactory: @escaping () -> any XPCControlConnection = {
            FakeXPCConnection(behavior: .hold)
        },
        approvalSettingsOpener: @escaping () -> Void = {}
    ) -> PrivilegedServiceManager {
        PrivilegedServiceManager(
            service: service,
            restoreSystemModeAndDisconnect: restoreAndDisconnect,
            connectionFactory: connectionFactory,
            connectionFailureHandler: {},
            requestTimeout: 0.1,
            approvalSettingsOpener: approvalSettingsOpener
        )
    }

    private func assertSendFails(
        _ client: XPCControlClient,
        as expectedError: XPCControlClientError
    ) async {
        do {
            _ = try await client.send(.heartbeat)
            XCTFail("Expected the control request to fail.")
        } catch {
            XCTAssertEqual(error as? XPCControlClientError, expectedError)
        }
    }

    private func waitForRequest(
        _ connection: FakeXPCConnection
    ) async {
        let received = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: connection.requestReceived.wait(
                        timeout: .now() + 1
                    ) == .success
                )
            }
        }
        XCTAssertTrue(received)
    }

    private func modelGeneration(after generation: UInt64) -> UInt64 {
        generation &+ 1
    }
}

@MainActor
private final class FakeServiceRegistration:
    PrivilegedServiceRegistering
{
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    var onRegister: (() -> Void)?
    var onUnregister: (() -> Void)?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        onRegister?()
        if let registerError {
            throw registerError
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        onUnregister?()
        if let unregisterError {
            throw unregisterError
        }
    }
}

private final class FakeXPCConnection:
    XPCControlConnection,
    @unchecked Sendable
{
    enum Behavior {
        case reply(ControlResult)
        case hold
        case interrupt
        case invalidate
    }

    var interruptionHandler: (@Sendable () -> Void)?
    var invalidationHandler: (@Sendable () -> Void)?
    private(set) var didResume = false

    let requestReceived = DispatchSemaphore(value: 0)

    private var behaviors: [Behavior]
    private let lock = NSLock()
    private var heldRequests: [
        UUID: @Sendable (Data) -> Void
    ] = [:]
    private var storedInvalidateCallCount = 0
    private var storedRequestCount = 0

    init(behavior: Behavior) {
        behaviors = [behavior]
    }

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    var invalidateCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInvalidateCallCount
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    func resume() {
        didResume = true
    }

    func invalidate() {
        lock.lock()
        storedInvalidateCallCount += 1
        lock.unlock()
        invalidationHandler?()
    }

    func send(
        _ requestData: Data,
        reply: @escaping @Sendable (Data) -> Void,
        error failure: @escaping @Sendable (Error) -> Void
    ) {
        do {
            let request = try XPCMessageAdapter.decodeRequest(requestData)
            lock.lock()
            heldRequests[request.id] = reply
            storedRequestCount += 1
            let behavior = behaviors.count > 1
                ? behaviors.removeFirst()
                : behaviors.first ?? .hold
            lock.unlock()
            requestReceived.signal()

            switch behavior {
            case .reply(let result):
                try replyToHeldRequest(with: result)
            case .hold:
                return
            case .interrupt:
                interruptionHandler?()
            case .invalidate:
                invalidationHandler?()
            }
        } catch {
            failure(error)
        }
    }

    func replyToHeldRequest(with result: ControlResult) throws {
        lock.lock()
        let request = heldRequests.first
        if let request {
            heldRequests.removeValue(forKey: request.key)
        }
        lock.unlock()
        let response = ControlResponse(
            id: try XCTUnwrap(request?.key),
            result: result
        )
        request?.value(try XPCMessageAdapter.encodeResponse(response))
    }

    func replyToAllHeldRequests(with result: ControlResult) throws {
        lock.lock()
        let requests = heldRequests
        heldRequests.removeAll()
        lock.unlock()

        for (requestID, reply) in requests {
            let response = ControlResponse(id: requestID, result: result)
            reply(try XPCMessageAdapter.encodeResponse(response))
        }
    }
}

private final class ManualTimeoutScheduler:
    XPCRequestTimeoutScheduling,
    @unchecked Sendable
{
    let operationScheduled = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []

    func schedule(
        after delay: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        operations.append(operation)
        lock.unlock()
        operationScheduled.signal()
    }

    func fireFirst() {
        lock.lock()
        let operation = operations.isEmpty
            ? nil
            : operations.removeFirst()
        lock.unlock()
        operation?()
    }

    func fireAll() {
        lock.lock()
        let pendingOperations = operations
        operations.removeAll()
        lock.unlock()
        for operation in pendingOperations {
            operation()
        }
    }
}

private actor ManualAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private enum TestFailure: LocalizedError {
    case expected

    var errorDescription: String? {
        "expected failure"
    }
}

private enum StaleConnectionEvent {
    case invalidation
    case interruption

    func deliver(to connection: FakeXPCConnection) {
        switch self {
        case .invalidation:
            connection.invalidationHandler?()
        case .interruption:
            connection.interruptionHandler?()
        }
    }
}
