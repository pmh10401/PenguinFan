import FanControllerCore
import XCTest

@testable import FanControllerApp

@MainActor
final class AppModelTests: XCTestCase {
    func testHistoryKeepsOnlyTenMinutes() {
        let model = AppModel()

        model.record(.fixture(date: Date(timeIntervalSince1970: 0)))
        model.record(.fixture(date: Date(timeIntervalSince1970: 601)))

        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(
            model.history.first?.timestamp,
            Date(timeIntervalSince1970: 601)
        )
    }

    func testRecordPublishesLatestSnapshotAndMenuBarTemperature() {
        let model = AppModel()

        model.record(
            .fixture(
                date: Date(timeIntervalSince1970: 100),
                temperature: 72.4
            )
        )

        XCTAssertEqual(model.snapshot?.maximumTemperature, 72.4)
        XCTAssertEqual(model.menuBarTitle, "72°")
    }
}

private extension SensorSnapshot {
    static func fixture(
        date: Date,
        temperature: Double = 60
    ) -> SensorSnapshot {
        SensorSnapshot(
            timestamp: date,
            maximumTemperature: temperature,
            thermalPressure: .nominal,
            fans: [],
            validTemperatureKeys: ["Tp1h"]
        )
    }
}
