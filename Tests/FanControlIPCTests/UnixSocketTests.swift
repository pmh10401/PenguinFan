import Foundation
import XCTest

@testable import FanControlIPC

final class UnixSocketTests: XCTestCase {
    func testStatusRoundTripAndSocketCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appendingPathComponent("control.sock")
        let server = UnixSocketServer(path: socketURL.path)
        try server.start { request in
            ControlResponse(
                id: request.id,
                result: .acknowledged
            )
        }
        defer { server.close() }

        let request = ControlRequest(id: UUID(), command: .status)
        let response = try UnixSocketClient(path: socketURL.path)
            .send(request)

        XCTAssertEqual(
            response,
            ControlResponse(id: request.id, result: .acknowledged)
        )

        server.close()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: socketURL.path)
        )
    }
}
