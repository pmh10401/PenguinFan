import Darwin
import Foundation

public enum UnixSocketError: Error, Equatable, Sendable {
    case invalidPath
    case systemCall(name: String, code: Int32)
    case connectionClosed
}

public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler =
        @Sendable (ControlRequest) -> ControlResponse

    public let path: String

    private let lock = NSLock()
    private var descriptor: Int32 = -1

    public init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    public func start(handler: @escaping Handler) throws {
        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw systemError("socket")
        }

        do {
            var address = try unixAddress(path: path)
            unlink(path)
            let result = withUnsafePointer(to: &address.value) { pointer in
                pointer.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1
                ) {
                    Darwin.bind(socketDescriptor, $0, address.length)
                }
            }
            guard result == 0 else {
                throw systemError("bind")
            }
            guard chmod(path, 0o600) == 0 else {
                throw systemError("chmod")
            }
            guard Darwin.listen(socketDescriptor, 8) == 0 else {
                throw systemError("listen")
            }
        } catch {
            Darwin.close(socketDescriptor)
            unlink(path)
            throw error
        }

        lock.lock()
        descriptor = socketDescriptor
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop(handler: handler)
        }
    }

    public func close() {
        lock.lock()
        let socketDescriptor = descriptor
        descriptor = -1
        lock.unlock()

        if socketDescriptor >= 0 {
            Darwin.shutdown(socketDescriptor, SHUT_RDWR)
            Darwin.close(socketDescriptor)
        }
        unlink(path)
    }

    private func acceptLoop(handler: @escaping Handler) {
        while true {
            lock.lock()
            let socketDescriptor = descriptor
            lock.unlock()
            guard socketDescriptor >= 0 else {
                return
            }

            let client = Darwin.accept(socketDescriptor, nil, nil)
            guard client >= 0 else {
                if errno == EINTR {
                    continue
                }
                return
            }

            handle(client: client, handler: handler)
            Darwin.close(client)
        }
    }

    private func handle(client: Int32, handler: Handler) {
        do {
            let requestLine = try readLine(from: client)
            let request = try ControlProtocolCodec.decodeRequest(requestLine)
            let response = handler(request)
            try writeAll(
                ControlProtocolCodec.encode(response),
                to: client
            )
        } catch {
            return
        }
    }
}

public struct UnixSocketClient: Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func send(_ request: ControlRequest) throws -> ControlResponse {
        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw systemError("socket")
        }
        defer { Darwin.close(socketDescriptor) }

        var address = try unixAddress(path: path)
        let result = withUnsafePointer(to: &address.value) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketDescriptor, $0, address.length)
            }
        }
        guard result == 0 else {
            throw systemError("connect")
        }

        try writeAll(
            ControlProtocolCodec.encode(request),
            to: socketDescriptor
        )
        return try ControlProtocolCodec.decodeResponse(
            readLine(from: socketDescriptor)
        )
    }
}

private func unixAddress(
    path: String
) throws -> (value: sockaddr_un, length: socklen_t) {
    let pathBytes = Array(path.utf8CString)
    var address = sockaddr_un()
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= pathCapacity else {
        throw UnixSocketError.invalidPath
    }

    address.sun_family = sa_family_t(AF_UNIX)
    _ = path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            strlcpy(destination, source, pathCapacity)
        }
    }
    let length = socklen_t(
        MemoryLayout<sa_family_t>.size + pathBytes.count
    )
    address.sun_len = UInt8(length)
    return (address, length)
}

private func readLine(from descriptor: Int32) throws -> Data {
    var data = Data()
    var byte: UInt8 = 0

    while data.count <= ControlProtocolCodec.maximumMessageSize {
        let count = Darwin.read(descriptor, &byte, 1)
        if count == 0 {
            throw UnixSocketError.connectionClosed
        }
        if count < 0 {
            if errno == EINTR {
                continue
            }
            throw systemError("read")
        }
        data.append(byte)
        if byte == 0x0A {
            return data
        }
    }
    throw ControlProtocolError.messageTooLarge
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(
                descriptor,
                buffer.baseAddress!.advanced(by: offset),
                buffer.count - offset
            )
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw systemError("write")
            }
            offset += count
        }
    }
}

private func systemError(_ name: String) -> UnixSocketError {
    UnixSocketError.systemCall(name: name, code: errno)
}
