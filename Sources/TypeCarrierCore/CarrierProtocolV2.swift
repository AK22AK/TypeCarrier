import CryptoKit
import Foundation

/// Wire protocol v2, shared by every platform. A connection is:
///
/// 1. Each side sends one plaintext `CarrierHello` frame (version negotiation, no secrets).
/// 2. A Noise handshake: XX when pairing, IK when reconnecting to a paired device. Both hellos are
///    bound into the Noise prologue, so a tampered hello fails the handshake.
/// 3. Encrypted `CarrierV2Message` frames.
///
/// Every step is length-prefixed with `CarrierWireFrame`.
public enum CarrierProtocolV2 {
    public static let version = 2
    public static let minimumVersion = 2
    static let prologueLabel = Data("TypeCarrier/2".utf8)

    public static func prologue(initiatorHello: Data, responderHello: Data) -> Data {
        var prologue = prologueLabel
        for hello in [initiatorHello, responderHello] {
            withUnsafeBytes(of: UInt32(hello.count).bigEndian) { prologue.append(contentsOf: $0) }
            prologue.append(hello)
        }
        return prologue
    }

    /// The 6-digit code both screens show while pairing. It is derived from the Noise handshake hash,
    /// so a device in the middle ends up with different codes on each side.
    public static func pairingCode(handshakeHash: Data) -> String {
        let digest = SHA256.hash(data: Data("TypeCarrier pairing code".utf8) + handshakeHash)
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }
}

public struct CarrierHello: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// First connection between two devices: Noise XX plus a pairing code check.
        case pair
        /// Reconnect to a paired device: Noise IK.
        case connect
    }

    public enum Platform: String, Codable, Sendable {
        case iOS, macOS, android, windows, linux
    }

    public static let capabilitySendText = "send.text"
    public static let capabilityReceivePaste = "receive.paste"
    public static let capabilityReceipt = "receipt"

    public let proto: Int
    public let minProto: Int
    public let mode: Mode
    public let platform: Platform
    public let capabilities: [String]

    public init(
        proto: Int = CarrierProtocolV2.version,
        minProto: Int = CarrierProtocolV2.minimumVersion,
        mode: Mode,
        platform: Platform,
        capabilities: [String]
    ) {
        self.proto = proto
        self.minProto = minProto
        self.mode = mode
        self.platform = platform
        self.capabilities = capabilities
    }

    /// The highest version both sides speak, or nil when their ranges do not overlap.
    public func negotiatedVersion(with remote: CarrierHello) -> Int? {
        let version = min(proto, remote.proto)
        return version >= max(minProto, remote.minProto) ? version : nil
    }

    public func encoded() throws -> Data {
        try CarrierHello.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> CarrierHello {
        try JSONDecoder().decode(CarrierHello.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// Sent inside the Noise handshake payloads, so it is only readable by the other party.
public struct CarrierV2DeviceInfo: Codable, Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String

    public init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

/// Encrypted application messages after the handshake.
public enum CarrierV2Message: Codable, Equatable, Sendable {
    case envelope(CarrierEnvelope)
    case ping(UInt64)
    case pong(UInt64)
    /// Responder -> initiator after the person confirmed matching pairing codes on the receiver.
    case pairingConfirmed
    case pairingRejected
    case close(CarrierV2CloseReason)

    // Explicit {"type": ...} JSON rather than Swift's synthesized enum coding, so other platforms
    // can read and write it without mirroring Swift conventions.
    private enum CodingKeys: String, CodingKey {
        case type, envelope, id, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "envelope": self = .envelope(try container.decode(CarrierEnvelope.self, forKey: .envelope))
        case "ping": self = .ping(try container.decode(UInt64.self, forKey: .id))
        case "pong": self = .pong(try container.decode(UInt64.self, forKey: .id))
        case "pairingConfirmed": self = .pairingConfirmed
        case "pairingRejected": self = .pairingRejected
        case "close": self = .close(try container.decode(CarrierV2CloseReason.self, forKey: .reason))
        case let type:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .envelope(let envelope):
            try container.encode("envelope", forKey: .type)
            try container.encode(envelope, forKey: .envelope)
        case .ping(let id):
            try container.encode("ping", forKey: .type)
            try container.encode(id, forKey: .id)
        case .pong(let id):
            try container.encode("pong", forKey: .type)
            try container.encode(id, forKey: .id)
        case .pairingConfirmed:
            try container.encode("pairingConfirmed", forKey: .type)
        case .pairingRejected:
            try container.encode("pairingRejected", forKey: .type)
        case .close(let reason):
            try container.encode("close", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> CarrierV2Message {
        try decoder.decode(CarrierV2Message.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum CarrierV2CloseReason: String, Codable, Error, Equatable, Sendable {
    case unsupportedVersion
    case notPaired
    case pairingNotOpen
    case pairingRejected
    case handshakeFailed
    case protocolViolation
    case replaced
    case heartbeatTimeout
    case shutdown
}
