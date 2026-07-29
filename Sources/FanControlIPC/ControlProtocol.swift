import FanControllerCore
import Foundation

public enum ControlCommand: Codable, Equatable, Sendable {
    case status
    case heartbeat
    case setRPM(fan: Int, rpm: Int)
    case restoreSystemAuto
    case shutdown
}

public struct ControlRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let command: ControlCommand

    public init(id: UUID, command: ControlCommand) {
        self.id = id
        self.command = command
    }
}

public struct AgentStatus: Codable, Equatable, Sendable {
    public let modelIdentifier: String
    public let fans: [FanDescriptor]
    public let manualFanIndices: [Int]

    public init(
        modelIdentifier: String,
        fans: [FanDescriptor],
        manualFanIndices: [Int]
    ) {
        self.modelIdentifier = modelIdentifier
        self.fans = fans
        self.manualFanIndices = manualFanIndices
    }
}

public enum ControlResult: Codable, Equatable, Sendable {
    case acknowledged
    case status(AgentStatus)
    case rejected(code: String, message: String)
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public let id: UUID
    public let result: ControlResult

    public init(id: UUID, result: ControlResult) {
        self.id = id
        self.result = result
    }
}

public enum ControlProtocolError: Error, Equatable, Sendable {
    case messageTooLarge
    case malformedMessage
    case missingNewline
}

public enum ControlProtocolCodec {
    public static let maximumMessageSize = 16 * 1_024

    public static func encode<T: Encodable>(_ message: T) throws -> Data {
        var data = try JSONEncoder().encode(message)
        guard data.count <= maximumMessageSize else {
            throw ControlProtocolError.messageTooLarge
        }
        data.append(0x0A)
        return data
    }

    public static func decodeRequest(_ line: Data) throws -> ControlRequest {
        try decode(ControlRequest.self, from: line)
    }

    public static func decodeResponse(_ line: Data) throws -> ControlResponse {
        try decode(ControlResponse.self, from: line)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from line: Data
    ) throws -> T {
        guard line.count <= maximumMessageSize + 1 else {
            throw ControlProtocolError.messageTooLarge
        }
        guard line.last == 0x0A else {
            if line.count > maximumMessageSize {
                throw ControlProtocolError.messageTooLarge
            }
            throw ControlProtocolError.missingNewline
        }

        let payload = line.dropLast()
        guard payload.count <= maximumMessageSize else {
            throw ControlProtocolError.messageTooLarge
        }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw ControlProtocolError.malformedMessage
        }
    }
}
