import Foundation
import ServiceManagement
import XCTest

@testable import FanControlIPC
@testable import FanControllerApp

@MainActor
final class PrivilegedServiceManagerTests: XCTestCase {
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

    func testRegisterDoesNotMutateReadOnlyServiceStatuses() {
        let cases: [(SMAppService.Status, PrivilegedServiceState)] = [
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .notFound),
        ]

        for (serviceStatus, expectedState) in cases {
            let service = FakeServiceRegistration(status: serviceStatus)
            let manager = makeManager(service: service)

            manager.register()

            XCTAssertEqual(service.registerCallCount, 0)
            XCTAssertEqual(manager.state, expectedState)
        }
    }

    func testRegisterFailureRemainsReadOnlyUntilExplicitRefresh() {
        let service = FakeServiceRegistration(status: .notRegistered)
        service.registerError = TestFailure.expected
        let manager = makeManager(service: service)

        manager.register()
        service.registerError = nil
        manager.register()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(manager.state, .failed("expected failure"))

        manager.refreshStatus()
        manager.register()
        XCTAssertEqual(service.registerCallCount, 2)
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
        XCTAssertEqual(manager.state, .failed("expected failure"))
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

    private let behavior: Behavior
    private let lock = NSLock()
    private var heldRequestID: UUID?
    private var heldReply: (@Sendable (Data) -> Void)?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func resume() {
        didResume = true
    }

    func invalidate() {
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
            heldRequestID = request.id
            heldReply = reply
            lock.unlock()

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
        let requestID = heldRequestID
        let reply = heldReply
        lock.unlock()
        let response = ControlResponse(
            id: try XCTUnwrap(requestID),
            result: result
        )
        reply?(try XPCMessageAdapter.encodeResponse(response))
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
