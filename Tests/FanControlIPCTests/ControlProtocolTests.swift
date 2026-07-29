import XCTest

@testable import FanControlIPC

final class ControlProtocolTests: XCTestCase {
    func testProtocolRoundTrip() throws {
        let request = ControlRequest(
            id: UUID(),
            command: .setRPM(fan: 1, rpm: 3_400)
        )

        let line = try ControlProtocolCodec.encode(request)
        let decoded = try ControlProtocolCodec.decodeRequest(line)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(line.last, 0x0A)
    }

    func testProtocolDoesNotExposeArbitrarySMCKeys() {
        XCTAssertFalse(
            String(describing: ControlCommand.self).contains("writeKey")
        )
    }

    func testOversizedMessageIsRejected() {
        let data = Data(
            repeating: 0x20,
            count: ControlProtocolCodec.maximumMessageSize + 1
        )

        XCTAssertThrowsError(try ControlProtocolCodec.decodeRequest(data)) {
            XCTAssertEqual(
                $0 as? ControlProtocolError,
                .messageTooLarge
            )
        }
    }
}
