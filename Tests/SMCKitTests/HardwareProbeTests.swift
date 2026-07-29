import FanControllerCore
import XCTest

@testable import SMCKit

final class HardwareProbeTests: XCTestCase {
    func testProbeFindsTwoFansAndUppercaseModeKeys() throws {
        let fake = FakeSMC(values: [
            "FNum": .uint8(2),
            "F0Mn": .float(2_317),
            "F0Mx": .float(7_826),
            "F0Ac": .float(2_500),
            "F0Tg": .float(2_600),
            "F0Md": .uint8(3),
            "F1Mn": .float(2_317),
            "F1Mx": .float(7_826),
            "F1Ac": .float(2_550),
            "F1Tg": .float(2_650),
            "F1Md": .uint8(3),
            "Ftst": .uint8(0),
        ])

        let result = try HardwareProbe(
            transport: fake,
            modelIdentifier: "Mac14,6"
        ).probe()

        XCTAssertEqual(result.modelIdentifier, "Mac14,6")
        XCTAssertEqual(result.fans.count, 2)
        XCTAssertEqual(result.fans[0].modeKey, "F0Md")
        XCTAssertEqual(result.fans[1].modeKey, "F1Md")
        XCTAssertTrue(result.ftstAvailable)
    }

    func testSensorReaderFiltersInvalidTemperaturesAndUsesMaximum() throws {
        let fake = FakeSMC(values: [
            "F0Ac": .float(2_500),
            "F0Tg": .float(2_600),
            "TC10": .float(72),
            "TC11": .float(180),
            "Tg04": .float(68),
        ])
        let capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [
                FanDescriptor(
                    index: 0,
                    minimumRPM: 2_317,
                    maximumRPM: 7_826,
                    modeKey: "F0Md"
                ),
            ],
            ftstAvailable: true
        )
        let reader = SensorReader(
            transport: fake,
            capabilities: capabilities,
            temperatureKeys: ["TC10", "TC11", "Tg04"],
            thermalPressure: { .elevated }
        )

        let snapshot = try reader.snapshot(
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.maximumTemperature, 72)
        XCTAssertEqual(snapshot.validTemperatureKeys, ["TC10", "Tg04"])
        XCTAssertEqual(snapshot.thermalPressure, .elevated)
        XCTAssertEqual(snapshot.fans[0].actualRPM, 2_500)
    }

    func testSensorReaderUsesDynamicallyEnumeratedTemperatureKeys() throws {
        let fake = FakeSMC(
            values: [
                "F0Ac": .float(2_500),
                "F0Tg": .float(2_600),
                "Tp1h": .float(74),
            ],
            enumeratedKeys: ["F0Ac", "Tp1h", "PSTR"]
        )
        let capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [
                FanDescriptor(
                    index: 0,
                    minimumRPM: 2_317,
                    maximumRPM: 7_826,
                    modeKey: "F0Md"
                ),
            ],
            ftstAvailable: false
        )
        let reader = SensorReader(
            transport: fake,
            capabilities: capabilities,
            temperatureKeys: [],
            thermalPressure: { .nominal }
        )

        let snapshot = try reader.snapshot()

        XCTAssertEqual(snapshot.maximumTemperature, 74)
        XCTAssertEqual(snapshot.validTemperatureKeys, ["Tp1h"])
    }

    func testSensorReaderPrefersConfiguredCPUHotspotKey() throws {
        let fake = FakeSMC(
            values: [
                "F0Ac": .float(2_500),
                "F0Tg": .float(2_600),
                "TCMz": .float(71),
                "TaTP": .float(106),
            ],
            enumeratedKeys: ["TCMz", "TaTP"]
        )
        let capabilities = HardwareCapabilities(
            modelIdentifier: "Mac14,6",
            fans: [
                FanDescriptor(
                    index: 0,
                    minimumRPM: 2_317,
                    maximumRPM: 7_826,
                    modeKey: "F0Md"
                ),
            ],
            ftstAvailable: false
        )
        let reader = SensorReader(
            transport: fake,
            capabilities: capabilities,
            temperatureKeys: ["TCMz"],
            thermalPressure: { .nominal }
        )

        let snapshot = try reader.snapshot()

        XCTAssertEqual(snapshot.maximumTemperature, 71)
        XCTAssertEqual(snapshot.validTemperatureKeys, ["TCMz"])
    }
}

private final class FakeSMC: SMCTransport, SMCKeyEnumerating, @unchecked Sendable {
    private let values: [String: SMCValue]
    private let enumeratedKeys: [String]

    init(values: [String: SMCValue], enumeratedKeys: [String] = []) {
        self.values = values
        self.enumeratedKeys = enumeratedKeys
    }

    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else {
            throw SMCError.firmware(0x84)
        }
        return value
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        XCTFail("Read-only test attempted a write to \(key)")
    }

    func enumerateKeys() throws -> [String] {
        enumeratedKeys
    }
}

private extension SMCValue {
    static func uint8(_ value: UInt8) -> SMCValue {
        SMCValue(bytes: [value], dataSize: 1, dataType: "ui8 ")
    }

    static func float(_ value: Float) -> SMCValue {
        SMCValue(
            bytes: SMCDataFormat.encodeFloat(value, size: 4),
            dataSize: 4,
            dataType: "flt "
        )
    }
}
