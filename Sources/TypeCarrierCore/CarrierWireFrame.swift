import Foundation

public enum CarrierWireFrameError: Error, Equatable, Sendable {
    case payloadTooLarge(Int)
}

public enum CarrierWireFrame {
    public static let maxPayloadSize = 1_048_576
    private static let headerSize = 4

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxPayloadSize else {
            throw CarrierWireFrameError.payloadTooLarge(payload.count)
        }

        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: headerSize)
        frame.append(payload)
        return frame
    }

    public static func nextPayload(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= headerSize else {
            return nil
        }

        let length = buffer.prefix(headerSize).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        guard length <= maxPayloadSize else {
            throw CarrierWireFrameError.payloadTooLarge(Int(length))
        }

        let frameSize = headerSize + Int(length)
        guard buffer.count >= frameSize else {
            return nil
        }

        let payload = buffer.subdata(in: headerSize..<frameSize)
        buffer.removeSubrange(0..<frameSize)
        return payload
    }
}
