import Foundation
import FanControllerCore
import XCTest

@testable import FanControlIPC
@testable import FanControllerAgent
@testable import SMCKit

final class AgentServerTests: XCTestCase {
    func testXPCServiceRoutesStatusRequestThroughAgentServer() throws {
        let server = AgentServer(
            writer: RecordingFanWriter(),
            capabilities: capabilities(),
            clock: { 100 }
        )
        let service = AgentXPCService(server: server)
        let request = ControlRequest(id: UUID(), command: .status)
        var replyData: Data?

        service.handle(try XPCMessageAdapter.encodeRequest(request)) {
            replyData = $0
        }

        let response = try XPCMessageAdapter.decodeResponse(
            XCTUnwrap(replyData)
        )
        XCTAssertEqual(response.id, request.id)
        guard case .status(let status) = response.result else {
            return XCTFail("Expected a status response.")
        }
        XCTAssertEqual(status.modelIdentifier, "Mac14,6")
        XCTAssertEqual(status.fans, [fan()])
        XCTAssertEqual(status.manualFanIndices, [])
    }

    func testXPCServiceReturnsDeterministicRejectionForMalformedInput() throws {
        let service = AgentXPCService(
            server: AgentServer(
                writer: RecordingFanWriter(),
                capabilities: capabilities(),
                clock: { 100 }
            )
        )
        let malformed = Data("not-a-control-request".utf8)
        var firstReply: Data?
        var secondReply: Data?

        service.handle(malformed) { firstReply = $0 }
        service.handle(malformed) { secondReply = $0 }

        let first = try XCTUnwrap(firstReply)
        XCTAssertEqual(first, try XCTUnwrap(secondReply))
        let response = try XPCMessageAdapter.decodeResponse(first)
        XCTAssertEqual(response.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(
            response.result,
            .rejected(
                code: "malformed_request",
                message: "The XPC request could not be decoded."
            )
        )
    }

    func testXPCServiceRejectsOversizedInputBeforeDecode() throws {
        XCTAssertEqual(
            AgentXPCService.maximumRequestSize,
            ControlProtocolCodec.maximumMessageSize
        )
        let service = AgentXPCService(
            server: AgentServer(
                writer: RecordingFanWriter(),
                capabilities: capabilities(),
                clock: { 100 }
            )
        )
        var replyData: Data?

        service.handle(
            Data(
                repeating: 0x20,
                count: AgentXPCService.maximumRequestSize + 1
            )
        ) {
            replyData = $0
        }

        let response = try XPCMessageAdapter.decodeResponse(
            XCTUnwrap(replyData)
        )
        XCTAssertEqual(
            response.result,
            .rejected(
                code: "malformed_request",
                message: "The XPC request could not be decoded."
            )
        )
    }

    func testXPCClientValidatorRequiresExactClientIdentity() {
        let connection = NSXPCConnection(serviceName: "test.invalid")
        defer { connection.invalidate() }

        XCTAssertTrue(makeValidator().accepts(connection))
        XCTAssertFalse(makeValidator(effectiveUID: 502).accepts(connection))
        XCTAssertFalse(makeValidator(consoleUID: 502).accepts(connection))
        XCTAssertFalse(
            makeValidator(
                executablePath: "/Applications/Other.app/Contents/MacOS/Other"
            ).accepts(connection)
        )
        XCTAssertFalse(
            makeValidator(signingIdentifier: "com.local.Other").accepts(connection)
        )
        XCTAssertFalse(
            makeValidator(filesystemObjectsSecure: false).accepts(connection)
        )
    }

    func testXPCClientValidatorRejectsInspectionErrors() {
        let connection = NSXPCConnection(serviceName: "test.invalid")
        defer { connection.invalidate() }
        let validator = XPCClientValidator(
            securityIdentity: { _ in throw ValidationTestError.failed },
            consoleUserUID: { 501 },
            processCodeIdentity: { _ in
                (
                    executablePath: XPCClientValidator.requiredExecutablePath,
                    signingIdentifier: XPCClientValidator.requiredSigningIdentifier
                )
            },
            filesystemObjectIsSecure: { _, _ in true },
            logFailure: { _ in }
        )

        XCTAssertFalse(validator.accepts(connection))
    }

    func testXPCListenerDelegateConfiguresAndExportsSharedService() {
        let service = AgentXPCService(
            server: AgentServer(
                writer: RecordingFanWriter(),
                capabilities: capabilities(),
                clock: { 100 }
            )
        )
        let delegate = AgentXPCListenerDelegate(
            service: service,
            validator: makeValidator()
        )
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(
            listenerEndpoint: listener.endpoint
        )
        defer { connection.invalidate() }

        XCTAssertTrue(
            delegate.listener(
                listener,
                shouldAcceptNewConnection: connection
            )
        )
        XCTAssertNotNil(connection.remoteObjectInterface)
        XCTAssertNotNil(connection.exportedInterface)
        XCTAssertTrue(
            (connection.exportedObject as? AgentXPCService) === service
        )
    }

    func testCleanupQuiescesInflightWriteBeforeFinalRestore() {
        let writer = BlockingFanWriter()
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { 100 }
        )
        let requestFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = server.handle(
                ControlRequest(
                    id: UUID(),
                    command: .setRPM(fan: 0, rpm: 3_000)
                )
            )
            requestFinished.signal()
        }
        XCTAssertEqual(
            writer.writeStarted.wait(timeout: .now() + 1),
            .success
        )

        let cleanupStarted = DispatchSemaphore(value: 0)
        let cleanupFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            cleanupStarted.signal()
            server.cleanup()
            cleanupFinished.signal()
        }
        XCTAssertEqual(
            cleanupStarted.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            cleanupFinished.wait(timeout: .now() + 0.1),
            .timedOut
        )

        writer.allowWrite.signal()
        XCTAssertEqual(
            requestFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            cleanupFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(writer.events, [.setRPM, .restore])

        let response = server.handle(
            ControlRequest(
                id: UUID(),
                command: .setRPM(fan: 0, rpm: 3_100)
            )
        )
        XCTAssertEqual(
            response.result,
            .rejected(
                code: "terminated",
                message: "The control agent is terminating."
            )
        )
        XCTAssertEqual(writer.events, [.setRPM, .restore])
    }

    func testProcessLockRejectsSecondOwner() throws {
        let path = temporaryLockPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try AgentProcessLock(path: path)
        defer { first.release() }

        XCTAssertThrowsError(try AgentProcessLock(path: path)) { error in
            XCTAssertEqual(
                error as? AgentProcessLockError,
                .alreadyRunning
            )
        }
    }

    func testProcessLockCanBeReacquiredAfterRelease() throws {
        let path = temporaryLockPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try AgentProcessLock(path: path)

        first.release()

        let second = try AgentProcessLock(path: path)
        second.release()
    }

    func testWatchdogRestoresAndTerminatesAfterSixSeconds() {
        let writer = RecordingFanWriter()
        var now: TimeInterval = 100
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { now }
        )

        now += 6.1
        server.checkWatchdog()

        XCTAssertEqual(writer.restoreCalls, [[fan()]])
        XCTAssertTrue(server.isTerminated)
    }

    func testDuplicateRequestIDIsRejected() {
        let writer = RecordingFanWriter()
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { 100 }
        )
        let request = ControlRequest(id: UUID(), command: .heartbeat)

        XCTAssertEqual(server.handle(request).result, .acknowledged)
        XCTAssertEqual(
            server.handle(request).result,
            .rejected(
                code: "duplicate_request",
                message: "Request ID was already processed."
            )
        )
    }

    func testUnknownFanIndexIsRejectedWithoutWriting() {
        let writer = RecordingFanWriter()
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { 100 }
        )
        let request = ControlRequest(
            id: UUID(),
            command: .setRPM(fan: 9, rpm: 3_000)
        )

        XCTAssertEqual(
            server.handle(request).result,
            .rejected(
                code: "unknown_fan",
                message: "Fan index 9 is not available."
            )
        )
        XCTAssertTrue(writer.setCalls.isEmpty)
    }

    func testShutdownRestoresAndInvokesTerminationHandler() {
        let writer = RecordingFanWriter()
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { 100 }
        )
        let terminated = DispatchSemaphore(value: 0)
        server.startWatchdog {
            terminated.signal()
        }

        let response = server.handle(
            ControlRequest(id: UUID(), command: .shutdown)
        )

        XCTAssertEqual(response.result, .acknowledged)
        XCTAssertEqual(
            terminated.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(writer.restoreCalls, [[fan()]])
    }

    func testStatusRequestRefreshesInitialWatchdogGrace() {
        let writer = RecordingFanWriter()
        var now: TimeInterval = 100
        let server = AgentServer(
            writer: writer,
            capabilities: capabilities(),
            clock: { now }
        )
        now = 105.5
        _ = server.handle(
            ControlRequest(id: UUID(), command: .status)
        )

        now = 110.5
        server.checkWatchdog()

        XCTAssertFalse(server.isTerminated)
        XCTAssertTrue(writer.restoreCalls.isEmpty)
    }

    private func capabilities() -> HardwareCapabilities {
        HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [fan()],
            ftstAvailable: false
        )
    }

    private func fan() -> FanDescriptor {
        FanDescriptor(
            index: 0,
            minimumRPM: 1_350,
            maximumRPM: 5_349,
            modeKey: "F0Md"
        )
    }

    private func temporaryLockPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "fan-controller-agent-\(UUID().uuidString).lock"
            )
            .path
    }

    private func makeValidator(
        effectiveUID: uid_t = 501,
        consoleUID: uid_t = 501,
        executablePath: String = XPCClientValidator.requiredExecutablePath,
        signingIdentifier: String = XPCClientValidator.requiredSigningIdentifier,
        filesystemObjectsSecure: Bool = true
    ) -> XPCClientValidator {
        XPCClientValidator(
            securityIdentity: { _ in
                (effectiveUID: effectiveUID, processID: 42)
            },
            consoleUserUID: { consoleUID },
            processCodeIdentity: { _ in
                (
                    executablePath: executablePath,
                    signingIdentifier: signingIdentifier
                )
            },
            filesystemObjectIsSecure: { _, _ in
                filesystemObjectsSecure
            },
            logFailure: { _ in }
        )
    }
}

private enum ValidationTestError: Error {
    case failed
}

private final class BlockingFanWriter: FanWriting, @unchecked Sendable {
    enum Event: Equatable {
        case setRPM
        case restore
    }

    let writeStarted = DispatchSemaphore(value: 0)
    let allowWrite = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func setRPM(_ rpm: Int, for fan: FanDescriptor) throws {
        writeStarted.signal()
        allowWrite.wait()
        lock.withLock {
            recordedEvents.append(.setRPM)
        }
    }

    func restoreSystemAuto(_ fans: [FanDescriptor]) throws {
        lock.withLock {
            recordedEvents.append(.restore)
        }
    }
}

private final class RecordingFanWriter: FanWriting, @unchecked Sendable {
    struct SetCall: Equatable {
        let rpm: Int
        let fan: FanDescriptor
    }

    private(set) var setCalls: [SetCall] = []
    private(set) var restoreCalls: [[FanDescriptor]] = []

    func setRPM(_ rpm: Int, for fan: FanDescriptor) throws {
        setCalls.append(SetCall(rpm: rpm, fan: fan))
    }

    func restoreSystemAuto(_ fans: [FanDescriptor]) throws {
        restoreCalls.append(fans)
    }
}
