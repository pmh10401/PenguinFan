import Foundation
import XCTest

@testable import FanControlIPC

final class XPCMessageAdapterTests: XCTestCase {
    func testRequestRoundTripPreservesIDAndCommand() throws {
        let request = ControlRequest(
            id: UUID(),
            command: .setRPM(fan: 1, rpm: 3_400)
        )

        let encoded = try XPCMessageAdapter.encodeRequest(request)
        let decoded = try XPCMessageAdapter.decodeRequest(encoded)

        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.command, request.command)
    }

    func testResponseRoundTripPreservesIDAndCommandResult() throws {
        let response = ControlResponse(
            id: UUID(),
            result: .rejected(
                code: "unknown_fan",
                message: "Fan index 4 is not available."
            )
        )

        let encoded = try XPCMessageAdapter.encodeResponse(response)
        let decoded = try XPCMessageAdapter.decodeResponse(encoded)

        XCTAssertEqual(decoded.id, response.id)
        XCTAssertEqual(decoded.result, response.result)
    }

    func testMalformedMessageIsRejected() {
        let malformed = Data(#"{"id":"not-a-uuid","command":"status"}"#.utf8) + Data([0x0A])

        XCTAssertThrowsError(try XPCMessageAdapter.decodeRequest(malformed)) {
            XCTAssertEqual($0 as? ControlProtocolError, .malformedMessage)
        }
    }

    func testMissingNewlineIsRejected() throws {
        let request = ControlRequest(id: UUID(), command: .heartbeat)
        let missingNewline = try ControlProtocolCodec.encode(request).dropLast()

        XCTAssertThrowsError(try XPCMessageAdapter.decodeRequest(Data(missingNewline))) {
            XCTAssertEqual($0 as? ControlProtocolError, .missingNewline)
        }
    }

    func testOversizedMessageIsRejected() {
        let oversized = Data(
            repeating: 0x20,
            count: ControlProtocolCodec.maximumMessageSize + 1
        )

        XCTAssertThrowsError(try XPCMessageAdapter.decodeRequest(oversized)) {
            XCTAssertEqual($0 as? ControlProtocolError, .messageTooLarge)
        }
    }
}
