import XCTest

@testable import SMCKit

final class SMCDataFormatTests: XCTestCase {
    func testAppleSiliconFloatRoundTrip() {
        let bytes = SMCDataFormat.encodeFloat(3_475, size: 4)

        XCTAssertEqual(
            SMCDataFormat.decodeFloat(bytes, size: 4),
            3_475,
            accuracy: 0.01
        )
    }

    func testBigEndianUInt32Decode() {
        XCTAssertEqual(
            SMCDataFormat.decodeUInt32([0x00, 0x00, 0x01, 0x00]),
            256
        )
    }

    func testSMCParameterStructureMatchesKernelABI() {
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
    }
}
