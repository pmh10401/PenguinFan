import FanControlIPC
import FanControllerCore
import XCTest

@testable import FanControllerApp

final class ControlCoordinatorTests: XCTestCase {
    func testCurveModeSendsClampedRPMToBothFans() async throws {
        let client = RecordingControlClient()
        let coordinator = ControlCoordinator(
            client: client,
            settings: .curveFixture,
            fans: fans()
        )

        try await coordinator.apply(snapshot: .hotFixture)

        let commands = await client.rpmCommands
        XCTAssertEqual(
            commands,
            [
                RPMCommand(fan: 0, rpm: 5_000),
                RPMCommand(fan: 1, rpm: 5_000),
            ]
        )
    }

    func testWriteFailureImmediatelyRequestsAuto() async {
        let client = RecordingControlClient(failSetRPM: true)
        let coordinator = ControlCoordinator(
            client: client,
            settings: .curveFixture,
            fans: fans()
        )

        do {
            try await coordinator.apply(snapshot: .hotFixture)
            XCTFail("Expected the injected write failure.")
        } catch {
            // Expected.
        }

        let restoreCount = await client.restoreCount
        XCTAssertEqual(restoreCount, 1)
    }

    func testCriticalPressureUsesEachFansMaximumRPM() async throws {
        let client = RecordingControlClient()
        let coordinator = ControlCoordinator(
            client: client,
            settings: .curveFixture,
            fans: fans()
        )

        try await coordinator.apply(snapshot: .criticalFixture)

        let commands = await client.rpmCommands
        XCTAssertEqual(
            commands,
            [
                RPMCommand(fan: 0, rpm: 5_349),
                RPMCommand(fan: 1, rpm: 5_777),
            ]
        )
    }

    private func fans() -> [FanDescriptor] {
        [
            FanDescriptor(
                index: 0,
                minimumRPM: 1_350,
                maximumRPM: 5_349,
                modeKey: "F0Md"
            ),
            FanDescriptor(
                index: 1,
                minimumRPM: 1_522,
                maximumRPM: 5_777,
                modeKey: "F1Md"
            ),
        ]
    }
}

private struct RPMCommand: Equatable, Sendable {
    let fan: Int
    let rpm: Int
}

private actor RecordingControlClient: ControlClient {
    private(set) var rpmCommands: [RPMCommand] = []
    private(set) var restoreCount = 0
    private let failSetRPM: Bool

    init(failSetRPM: Bool = false) {
        self.failSetRPM = failSetRPM
    }

    func send(_ command: ControlCommand) async throws -> ControlResult {
        switch command {
        case .setRPM(let fan, let rpm):
            if failSetRPM {
                throw TestError.writeFailed
            }
            rpmCommands.append(RPMCommand(fan: fan, rpm: rpm))
        case .restoreSystemAuto:
            restoreCount += 1
        default:
            break
        }
        return .acknowledged
    }

    private enum TestError: Error {
        case writeFailed
    }
}

private extension FanSettings {
    static let curveFixture = FanSettings(
        mode: .curve,
        manualRPM: 3_000,
        curve: [
            CurvePoint(temperature: 50, rpm: 2_000),
            CurvePoint(temperature: 80, rpm: 5_000),
        ]
    )
}

private extension SensorSnapshot {
    static let hotFixture = SensorSnapshot(
        timestamp: Date(),
        maximumTemperature: 80,
        thermalPressure: .hot,
        fans: [],
        validTemperatureKeys: ["Tp1h"]
    )

    static let criticalFixture = SensorSnapshot(
        timestamp: Date(),
        maximumTemperature: 60,
        thermalPressure: .critical,
        fans: [],
        validTemperatureKeys: ["Tp1h"]
    )
}
