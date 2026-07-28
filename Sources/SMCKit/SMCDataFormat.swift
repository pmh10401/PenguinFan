import Foundation

public enum SMCDataFormat {
    public static func decodeFloat(_ bytes: [UInt8], size: UInt32) -> Float {
        if size == 4, bytes.count >= 4 {
            return bytes.withUnsafeBytes { buffer in
                buffer.loadUnaligned(as: Float.self)
            }
        }
        if size == 2, bytes.count >= 2 {
            return Float(decodeUInt16(bytes)) / 4
        }
        return 0
    }

    public static func encodeFloat(_ value: Float, size: UInt32) -> [UInt8] {
        if size == 4 {
            return withUnsafeBytes(of: value) { Array($0) }
        }
        if size == 2 {
            let raw = UInt16(max(0, value * 4))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        }
        return []
    }

    public static func decodeUInt8(_ bytes: [UInt8]) -> UInt8 {
        bytes.first ?? 0
    }

    public static func decodeUInt16(_ bytes: [UInt8]) -> UInt16 {
        guard bytes.count >= 2 else {
            return 0
        }
        return bytes.withUnsafeBytes { buffer in
            UInt16(bigEndian: buffer.loadUnaligned(as: UInt16.self))
        }
    }

    public static func decodeUInt32(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else {
            return 0
        }
        return bytes.withUnsafeBytes { buffer in
            UInt32(bigEndian: buffer.loadUnaligned(as: UInt32.self))
        }
    }
}
