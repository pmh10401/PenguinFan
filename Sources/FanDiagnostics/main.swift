import Darwin
import FanControllerCore
import Foundation
import SMCKit

private struct DiagnosticReport: Codable {
    let check: String
    let modelIdentifier: String
    let smcConnected: Bool
    let fans: [FanDescriptor]
    let snapshot: SensorSnapshot
    let ftstAvailable: Bool
}

private struct DiagnosticFailure: Encodable {
    let check: String
    let error: String

    init(error: String) {
        self.check = "failed"
        self.error = error
    }
}

private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

do {
    let connection = try SMCConnection()
    let capabilities = try HardwareProbe(transport: connection).probe()
    let snapshot = try SensorReader(
        transport: connection,
        capabilities: capabilities
    ).snapshot()
    let report = DiagnosticReport(
        check: "ok",
        modelIdentifier: capabilities.modelIdentifier,
        smcConnected: true,
        fans: capabilities.fans,
        snapshot: snapshot,
        ftstAvailable: capabilities.ftstAvailable
    )
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
} catch {
    let data = try encoder.encode(
        DiagnosticFailure(error: error.localizedDescription)
    )
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data([0x0A]))
    exit(EXIT_FAILURE)
}
