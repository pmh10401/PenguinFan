import Foundation
import IOKit

public struct SMCValue: Equatable, Sendable {
    public let bytes: [UInt8]
    public let dataSize: UInt32
    public let dataType: String

    public init(bytes: [UInt8], dataSize: UInt32, dataType: String) {
        self.bytes = bytes
        self.dataSize = dataSize
        self.dataType = dataType
    }
}

public protocol SMCTransport: Sendable {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, bytes: [UInt8]) throws
}

public protocol SMCKeyEnumerating: Sendable {
    func enumerateKeys() throws -> [String]
}

public final class SMCConnection: SMCTransport, SMCKeyEnumerating, @unchecked Sendable {
    private static let kernelSelector: UInt32 = 2
    private let connection: io_connect_t

    public init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCError.connectionFailed(kIOReturnNotFound)
        }

        var iterator: io_iterator_t = 0
        let matchingResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        )
        guard matchingResult == kIOReturnSuccess else {
            throw SMCError.connectionFailed(matchingResult)
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw SMCError.connectionFailed(kIOReturnNotFound)
        }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = 0
        let openResult = IOServiceOpen(
            service,
            mach_task_self_,
            0,
            &openedConnection
        )
        guard openResult == kIOReturnSuccess else {
            throw SMCError.connectionFailed(openResult)
        }
        connection = openedConnection
    }

    deinit {
        IOServiceClose(connection)
    }

    public func read(_ key: String) throws -> SMCValue {
        let (base, info) = try readKeyInfo(key)
        let size = info.keyInfo.dataSize
        guard size <= 32 else {
            throw SMCError.invalidDataSize(size)
        }

        var input = base
        input.keyInfo.dataSize = size
        input.data8 = SMCCommand.readBytes.rawValue
        let output = try call(input)
        let bytes = tupleBytes(output.bytes, count: Int(size))
        return SMCValue(
            bytes: bytes,
            dataSize: size,
            dataType: fourCharacterString(info.keyInfo.dataType)
        )
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        let (base, info) = try readKeyInfo(key)
        let size = info.keyInfo.dataSize
        guard size <= 32, bytes.count == Int(size) else {
            throw SMCError.invalidDataSize(size)
        }

        var input = base
        input.keyInfo = info.keyInfo
        input.data8 = SMCCommand.writeBytes.rawValue
        input.bytes = bytesTuple(bytes)
        _ = try call(input)
    }

    public func enumerateKeys() throws -> [String] {
        let countValue = try read("#KEY")
        let count = SMCDataFormat.decodeUInt32(countValue.bytes)
        var keys: [String] = []
        keys.reserveCapacity(Int(count))

        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = SMCCommand.readIndex.rawValue
            input.data32 = index
            let output = try call(input)
            keys.append(fourCharacterString(output.key))
        }
        return keys
    }

    private func readKeyInfo(_ key: String) throws -> (SMCParamStruct, SMCParamStruct) {
        var input = SMCParamStruct()
        input.key = try fourCharacterCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        return (input, try call(input))
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var inputCopy = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            Self.kernelSelector,
            &inputCopy,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw SMCError.ioKit(result)
        }
        guard output.result == 0 else {
            throw SMCError.firmware(output.result)
        }
        return output
    }

    private func fourCharacterCode(_ value: String) throws -> UInt32 {
        let bytes = Array(value.utf8)
        guard bytes.count == 4 else {
            throw SMCError.invalidKey(value)
        }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharacterString(_ value: UInt32) -> String {
        let bigEndian = value.bigEndian
        return withUnsafeBytes(of: bigEndian) { buffer in
            String(decoding: buffer, as: UTF8.self)
        }
    }

    private func tupleBytes(_ tuple: SMCParamStruct.Bytes32, count: Int) -> [UInt8] {
        withUnsafeBytes(of: tuple) { buffer in
            Array(buffer.prefix(count))
        }
    }

    private func bytesTuple(_ input: [UInt8]) -> SMCParamStruct.Bytes32 {
        let bytes = input + Array(repeating: 0, count: 32 - input.count)
        return (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
            bytes[16], bytes[17], bytes[18], bytes[19],
            bytes[20], bytes[21], bytes[22], bytes[23],
            bytes[24], bytes[25], bytes[26], bytes[27],
            bytes[28], bytes[29], bytes[30], bytes[31]
        )
    }
}
