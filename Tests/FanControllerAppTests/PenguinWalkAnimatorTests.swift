import XCTest
@testable import FanControllerApp

@MainActor
final class PenguinWalkAnimatorTests: XCTestCase {
    func testAverageRPMUsesValidMeasuredValues() {
        XCTAssertNil(PenguinWalkAnimator.averageRPM([]))
        XCTAssertEqual(PenguinWalkAnimator.averageRPM([2_000, 4_000]), 3_000)
        XCTAssertEqual(PenguinWalkAnimator.averageRPM([-1, 3_000]), 3_000)
        XCTAssertNil(PenguinWalkAnimator.averageRPM([-.infinity, .nan]))
    }

    func testFrameIntervalsMatchWalkingSpeedCurve() {
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: nil), 0.90, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 1_500), 0.90, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 3_000), 0.55, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 4_500), 0.32, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 6_000), 0.18, accuracy: 0.001)
    }

    func testFrameIntervalInterpolatesAndClamps() {
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 750), 0.90, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 2_250), 0.725, accuracy: 0.001)
        XCTAssertEqual(PenguinWalkAnimator.frameInterval(for: 7_000), 0.18, accuracy: 0.001)
    }
}
