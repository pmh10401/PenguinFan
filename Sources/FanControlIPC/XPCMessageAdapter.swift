import Foundation

public enum XPCMessageAdapter {
    public static func encodeRequest(_ request: ControlRequest) throws -> Data {
        try ControlProtocolCodec.encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> ControlRequest {
        try ControlProtocolCodec.decodeRequest(data)
    }

    public static func encodeResponse(_ response: ControlResponse) throws -> Data {
        try ControlProtocolCodec.encode(response)
    }

    public static func decodeResponse(_ data: Data) throws -> ControlResponse {
        try ControlProtocolCodec.decodeResponse(data)
    }
}
