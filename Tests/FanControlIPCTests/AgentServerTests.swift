import FanControllerCore
import XCTest

@testable import FanControlIPC
@testable import FanControllerAgent
@testable import SMCKit

final class AgentServerTests: XCTestCase {
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
