import FanControllerCore
import XCTest

@testable import SMCKit

final class FanWriterTests: XCTestCase {
    func testManualModeIsWrittenBeforeTargetRPM() throws {
        let fake = RecordingSMC(values: [
            "F0Tg": .float(1_350),
        ])
        let writer = FanWriter(
            transport: fake,
            capabilities: capabilities()
        )

        try writer.setManualRPM(3_200)

        XCTAssertEqual(fake.writes.map(\.key), ["F0Md", "F0Tg"])
        XCTAssertEqual(fake.writes[0].bytes, [1])
        XCTAssertEqual(
            SMCDataFormat.decodeFloat(fake.writes[1].bytes, size: 4),
            3_200,
            accuracy: 0.01
        )
    }

    func testManualRPMOutsideFanRangeIsRejectedBeforeWriting() {
        let fake = RecordingSMC(values: [
            "F0Tg": .float(1_350),
        ])
        let writer = FanWriter(
            transport: fake,
            capabilities: capabilities()
        )

        XCTAssertThrowsError(try writer.setManualRPM(6_000)) { error in
            XCTAssertEqual(
                error as? FanWriterError,
                .rpmOutOfRange(fan: 0, requested: 6_000, minimum: 1_350, maximum: 5_349)
            )
        }
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testRestoreAttemptsEveryFanAndFtstAfterAnIndividualFailure() {
        let fake = RecordingSMC(
            values: [:],
            failingWriteKeys: ["F0Md"]
        )
        let capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [
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
            ],
            ftstAvailable: true
        )
        let writer = FanWriter(
            transport: fake,
            capabilities: capabilities
        )

        XCTAssertThrowsError(try writer.restoreSystemAuto())
        XCTAssertEqual(fake.attemptedWriteKeys, ["F0Md", "F1Md", "Ftst"])
        XCTAssertEqual(fake.writes.map(\.key), ["F1Md", "Ftst"])
        XCTAssertEqual(fake.writes.map(\.bytes), [[0], [0]])
    }

    private func capabilities() -> HardwareCapabilities {
        HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [
                FanDescriptor(
                    index: 0,
                    minimumRPM: 1_350,
                    maximumRPM: 5_349,
                    modeKey: "F0Md"
                ),
            ],
            ftstAvailable: false
        )
    }
}

private final class RecordingSMC: SMCTransport, @unchecked Sendable {
    struct Write: Equatable {
        let key: String
        let bytes: [UInt8]
    }

    private let values: [String: SMCValue]
    private let failingWriteKeys: Set<String>
    private(set) var attemptedWriteKeys: [String] = []
    private(set) var writes: [Write] = []

    init(
        values: [String: SMCValue],
        failingWriteKeys: Set<String> = []
    ) {
        self.values = values
        self.failingWriteKeys = failingWriteKeys
    }

    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else {
            throw SMCError.firmware(0x84)
        }
        return value
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        attemptedWriteKeys.append(key)
        if failingWriteKeys.contains(key) {
            throw SMCError.firmware(0x85)
        }
        writes.append(Write(key: key, bytes: bytes))
    }
}

private extension SMCValue {
    static func float(_ value: Float) -> SMCValue {
        SMCValue(
            bytes: SMCDataFormat.encodeFloat(value, size: 4),
            dataSize: 4,
            dataType: "flt "
        )
    }
}
