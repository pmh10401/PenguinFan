import Foundation
import IOKit

public enum SMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

public struct SMCParamStruct {
    public typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    public struct Version {
        public var major: UInt8 = 0
        public var minor: UInt8 = 0
        public var build: UInt8 = 0
        public var reserved: UInt8 = 0
        public var release: UInt16 = 0
    }

    public struct PowerLimitData {
        public var version: UInt16 = 0
        public var length: UInt16 = 0
        public var cpuLimit: UInt32 = 0
        public var gpuLimit: UInt32 = 0
        public var memoryLimit: UInt32 = 0
    }

    public struct KeyInfo {
        public var dataSize: UInt32 = 0
        public var dataType: UInt32 = 0
        public var dataAttributes: UInt8 = 0
    }

    public var key: UInt32 = 0
    public var version = Version()
    public var powerLimit = PowerLimitData()
    public var keyInfo = KeyInfo()
    public var padding: UInt16 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}
}

public enum SMCError: Error, LocalizedError, Equatable {
    case connectionFailed(kern_return_t)
    case invalidKey(String)
    case invalidDataSize(UInt32)
    case ioKit(kern_return_t)
    case firmware(UInt8)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let code):
            "Unable to open AppleSMC: 0x\(String(code, radix: 16))"
        case .invalidKey(let key):
            "SMC key must contain exactly four ASCII bytes: \(key)"
        case .invalidDataSize(let size):
            "Unsupported SMC data size: \(size)"
        case .ioKit(let code):
            "AppleSMC IOKit call failed: 0x\(String(code, radix: 16))"
        case .firmware(let code):
            "AppleSMC firmware rejected the request: 0x\(String(code, radix: 16))"
        }
    }
}
