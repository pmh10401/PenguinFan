import FanControlIPC
import Foundation

public final class AgentXPCService: NSObject, FanControllerXPCProtocol {
    public static let machServiceName =
        "com.local.PenguinFan.experimental.agent"
    public static let maximumRequestSize =
        ControlProtocolCodec.maximumMessageSize

    private static let malformedResponseData: Data = {
        let response = ControlResponse(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            result: .rejected(
                code: "malformed_request",
                message: "The XPC request could not be decoded."
            )
        )
        guard let data = try? XPCMessageAdapter.encodeResponse(response) else {
            preconditionFailure("The fixed malformed response must be encodable.")
        }
        return data
    }()

    private let server: AgentServer

    public init(server: AgentServer) {
        self.server = server
        super.init()
    }

    public func handle(
        _ requestData: Data,
        withReply reply: @escaping (Data) -> Void
    ) {
        guard requestData.count <= Self.maximumRequestSize else {
            reply(Self.malformedResponseData)
            return
        }
        do {
            let request = try XPCMessageAdapter.decodeRequest(requestData)
            let response = server.handle(request)
            reply(try XPCMessageAdapter.encodeResponse(response))
        } catch {
            reply(Self.malformedResponseData)
        }
    }
}

final class AgentXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: AgentXPCService
    private let validator: XPCClientValidator

    init(
        service: AgentXPCService,
        validator: XPCClientValidator
    ) {
        self.service = service
        self.validator = validator
        super.init()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard validator.accepts(newConnection) else {
            return false
        }

        newConnection.remoteObjectInterface = NSXPCInterface(
            with: FanControllerXPCProtocol.self
        )
        newConnection.exportedInterface = NSXPCInterface(
            with: FanControllerXPCProtocol.self
        )
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
