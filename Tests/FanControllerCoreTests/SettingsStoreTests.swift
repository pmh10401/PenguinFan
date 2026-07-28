import Foundation
import XCTest

@testable import FanControllerCore

final class SettingsStoreTests: XCTestCase {
    func testPersistedCopyKeepsCurveButStartsInSystemAuto() throws {
        let settings = FanSettings(
            mode: .manual,
            manualRPM: 3_200,
            curve: [
                CurvePoint(temperature: 55, rpm: 2_300),
                CurvePoint(temperature: 90, rpm: 6_200),
            ]
        )

        let data = try JSONEncoder().encode(settings.persistedCopy)
        let restored = try JSONDecoder().decode(FanSettings.self, from: data)

        XCTAssertEqual(restored.mode, .systemAuto)
        XCTAssertEqual(restored.manualRPM, 3_200)
        XCTAssertEqual(restored.curve, settings.curve)
    }

    func testStoreRoundTripNeverRestoresActiveControl() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(fileURL: fileURL)
        let settings = FanSettings(
            mode: .curve,
            manualRPM: 3_600,
            curve: [
                CurvePoint(temperature: 55, rpm: 2_400),
                CurvePoint(temperature: 90, rpm: 6_000),
            ]
        )

        try await store.save(settings)
        let restored = try await store.load()

        XCTAssertEqual(restored.mode, .systemAuto)
        XCTAssertEqual(restored.manualRPM, 3_600)
        XCTAssertEqual(restored.curve, settings.curve)
    }
}
