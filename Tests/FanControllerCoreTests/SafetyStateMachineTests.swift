import XCTest

@testable import FanControllerCore

final class SafetyStateMachineTests: XCTestCase {
    func testStaleSensorForcesAutomaticControl() {
        var machine = SafetyStateMachine()
        XCTAssertEqual(machine.handle(.controlEnabled), [])

        XCTAssertEqual(
            machine.handle(.sensorAge(seconds: 5.1)),
            [.restoreSystemAuto, .stopControl]
        )
    }

    func testSleepForcesAutomaticControl() {
        var machine = SafetyStateMachine()
        _ = machine.handle(.controlEnabled)

        XCTAssertEqual(
            machine.handle(.willSleep),
            [.restoreSystemAuto, .stopControl]
        )
    }

    func testInactiveMachineDoesNotIssueDuplicateRestore() {
        var machine = SafetyStateMachine()

        XCTAssertEqual(machine.handle(.heartbeatLost), [])
    }
}
