import Foundation

/// Swift-side names for protocol v2. The protocol itself (framing, hello, Noise handshake, pairing
/// codes, heartbeats, messages) lives in the shared Rust core, Core/carrier-core.
public enum CarrierProtocolV2 {
    public static let version = 2
}

public enum CarrierHello {
    public enum Mode: String, Codable, Sendable {
        /// First connection between two devices: Noise XX plus a pairing code check.
        case pair
        /// Reconnect to a paired device: Noise IK.
        case connect
    }

    /// Raw values are stored in the Keychain pairing list; keep them stable.
    public enum Platform: String, Codable, Sendable {
        case iOS, macOS, android, windows, linux, harmonyOS
    }

    public static let capabilitySendText = "send.text"
    public static let capabilityReceivePaste = "receive.paste"
    public static let capabilityReceipt = "receipt"
}

/// What a device tells the other side about itself inside the encrypted handshake.
public struct CarrierV2DeviceInfo: Codable, Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String

    public init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
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

// MARK: - Mapping to the Rust core's types

extension CarrierHello.Platform {
    init(_ platform: CorePlatform) {
        switch platform {
        case .ios: self = .iOS
        case .macOs: self = .macOS
        case .android: self = .android
        case .windows: self = .windows
        case .linux: self = .linux
        case .harmonyOs: self = .harmonyOS
        }
    }

    var core: CorePlatform {
        switch self {
        case .iOS: .ios
        case .macOS: .macOs
        case .android: .android
        case .windows: .windows
        case .linux: .linux
        case .harmonyOS: .harmonyOs
        }
    }
}

extension CarrierHello.Mode {
    var core: CoreHelloMode {
        switch self {
        case .pair: .pair
        case .connect: .connect
        }
    }
}

extension CarrierV2CloseReason {
    init(_ reason: CoreCloseReason) {
        switch reason {
        case .unsupportedVersion: self = .unsupportedVersion
        case .notPaired: self = .notPaired
        case .pairingNotOpen: self = .pairingNotOpen
        case .pairingRejected: self = .pairingRejected
        case .handshakeFailed: self = .handshakeFailed
        case .protocolViolation: self = .protocolViolation
        case .replaced: self = .replaced
        case .heartbeatTimeout: self = .heartbeatTimeout
        case .shutdown: self = .shutdown
        }
    }
}
