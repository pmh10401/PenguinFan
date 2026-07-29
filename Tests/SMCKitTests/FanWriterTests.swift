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
            ftstAvailable: false
        )

        try writer.setRPM(3_200, for: fan())

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
            ftstAvailable: false
        )

        XCTAssertThrowsError(try writer.setRPM(6_000, for: fan())) { error in
            XCTAssertEqual(
                error as? FanWriterError,
                .rpmOutOfRange(fan: 0, requested: 6_000, minimum: 1_350, maximum: 5_349)
            )
        }
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testFirmwareRejectionUsesFtstThenRetriesManualMode() throws {
        let rejectedModeWrite = RecordingSMC.Write(
            key: "F0Md",
            bytes: [1]
        )
        let fake = RecordingSMC(
            values: ["F0Tg": .float(1_350)],
            failOnceWrites: [rejectedModeWrite]
        )
        var sleeps: [TimeInterval] = []
        let writer = FanWriter(
            transport: fake,
            ftstAvailable: true,
            sleep: { sleeps.append($0) }
        )

        try writer.setRPM(3_200, for: fan())

        XCTAssertEqual(
            fake.attemptedWriteKeys,
            ["F0Md", "Ftst", "F0Md", "F0Tg"]
        )
        XCTAssertEqual(fake.writes.map(\.key), ["Ftst", "F0Md", "F0Tg"])
        XCTAssertEqual(sleeps, [0.5])
    }

    func testRestoreAttemptsEveryFanAndFtstAfterAnIndividualFailure() {
        let manualWrite = RecordingSMC.Write(key: "F0Md", bytes: [1])
        let failedRestore = RecordingSMC.Write(key: "F0Md", bytes: [0])
        let fake = RecordingSMC(
            values: ["F0Tg": .float(1_350)],
            failOnceWrites: [manualWrite],
            alwaysFailWrites: [failedRestore]
        )
        let writer = FanWriter(
            transport: fake,
            ftstAvailable: true,
            sleep: { _ in }
        )
        XCTAssertNoThrow(try writer.setRPM(3_200, for: fan()))
        fake.resetRecording()

        XCTAssertThrowsError(
            try writer.restoreSystemAuto([
                fan(),
                FanDescriptor(
                    index: 1,
                    minimumRPM: 1_522,
                    maximumRPM: 5_777,
                    modeKey: "F1Md"
                ),
            ])
        )
        XCTAssertEqual(fake.attemptedWriteKeys, ["F0Md", "F1Md", "Ftst"])
        XCTAssertEqual(fake.writes.map(\.key), ["F1Md", "Ftst"])
        XCTAssertEqual(fake.writes.map(\.bytes), [[0], [0]])
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

private final class RecordingSMC: SMCTransport, @unchecked Sendable {
    struct Write: Hashable {
        let key: String
        let bytes: [UInt8]
    }

    private let values: [String: SMCValue]
    private var failOnceWrites: Set<Write>
    private let alwaysFailWrites: Set<Write>
    private(set) var attemptedWriteKeys: [String] = []
    private(set) var writes: [Write] = []

    init(
        values: [String: SMCValue],
        failOnceWrites: Set<Write> = [],
        alwaysFailWrites: Set<Write> = []
    ) {
        self.values = values
        self.failOnceWrites = failOnceWrites
        self.alwaysFailWrites = alwaysFailWrites
    }

    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else {
            throw SMCError.firmware(0x84)
        }
        return value
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        attemptedWriteKeys.append(key)
        let write = Write(key: key, bytes: bytes)
        if failOnceWrites.remove(write) != nil
            || alwaysFailWrites.contains(write) {
            throw SMCError.firmware(0x85)
        }
        writes.append(write)
    }

    func resetRecording() {
        attemptedWriteKeys = []
        writes = []
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
