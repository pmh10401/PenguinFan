import Foundation

@objc public protocol FanControllerXPCProtocol {
    func handle(
        _ requestData: Data,
        withReply reply: @escaping (Data) -> Void
    )
}
