import XCTest

@testable import FanControllerCore

final class CurveEngineTests: XCTestCase {
    func testCurveInterpolatesAndClampsToHardwareRange() throws {
        let points = [
            CurvePoint(temperature: 50, rpm: 2_200),
            CurvePoint(temperature: 90, rpm: 6_200),
        ]

        XCTAssertEqual(
            try CurveEngine.targetRPM(
                temperature: 70,
                points: points,
                minimumRPM: 2_300,
                maximumRPM: 6_000
            ),
            4_200
        )
        XCTAssertEqual(
            try CurveEngine.targetRPM(
                temperature: 95,
                points: points,
                minimumRPM: 2_300,
                maximumRPM: 6_000
            ),
            6_000
        )
    }

    func testCurveRejectsRPMDecreaseAsTemperatureRises() {
        let points = [
            CurvePoint(temperature: 60, rpm: 4_000),
            CurvePoint(temperature: 80, rpm: 3_000),
        ]

        XCTAssertThrowsError(try CurveEngine.validate(points))
    }

    func testLimitedRPMRestrictsRiseAndFallToOneStep() {
        XCTAssertEqual(CurveEngine.limitedRPM(previous: 3_000, proposed: 4_000, maximumStep: 300), 3_300)
        XCTAssertEqual(CurveEngine.limitedRPM(previous: 4_000, proposed: 3_000, maximumStep: 300), 3_700)
    }
}
