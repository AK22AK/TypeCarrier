import CryptoKit
import Foundation

/// A device's long-term identity: its Noise static key plus what it tells paired peers about itself.
public struct CarrierV2Identity {
    public let staticKey: Curve25519.KeyAgreement.PrivateKey
    public let info: CarrierV2DeviceInfo
    public let platform: CarrierHello.Platform
    public let capabilities: [String]

    public init(
        staticKey: Curve25519.KeyAgreement.PrivateKey,
        info: CarrierV2DeviceInfo,
        platform: CarrierHello.Platform,
        capabilities: [String]
    ) {
        self.staticKey = staticKey
        self.info = info
        self.platform = platform
        self.capabilities = capabilities
    }

    var core: CoreIdentity {
        CoreIdentity(
            staticPrivateKey: staticKey.rawRepresentation,
            deviceId: info.deviceID,
            deviceName: info.deviceName,
            platform: platform.core,
            capabilities: capabilities
        )
    }
}

/// The other end of a session.
public struct CarrierV2Peer: Equatable, Sendable {
    public let info: CarrierV2DeviceInfo
    public let publicKey: Data
    public let platform: CarrierHello.Platform
    public let capabilities: [String]

    init(_ peer: CorePeer) {
        info = CarrierV2DeviceInfo(deviceID: peer.deviceId, deviceName: peer.deviceName)
        publicKey = peer.publicKey
        platform = CarrierHello.Platform(peer.platform)
        capabilities = peer.capabilities
    }
}

public enum CarrierV2SessionEvent: Equatable {
    /// Bytes to write to the connection, already framed.
    case write(Data)
    /// Pairing only: show this code. The receiver then calls `confirmPairing()` or `rejectPairing()`;
    /// the sender waits for that answer.
    case pairingCodeReady(code: String, peer: CarrierV2Peer)
    /// The session is ready for messages. For a pairing, the app stores `peer.publicKey` now.
    case established(peer: CarrierV2Peer)
    case received(CarrierEnvelope)
    /// The session is over; close the connection after writing any preceding `write` events.
    case closed(CarrierV2CloseReason)
}

/// One protocol v2 connection. The protocol runs in the shared Rust core (`CoreSession`); this
/// wrapper converts its events to Swift types and envelopes to and from their JSON.
public struct CarrierV2Session {
    public enum Role: Equatable {
        /// Opens the connection (the sender). `connect` needs the paired receiver's key.
        case initiator(CarrierHello.Mode, remoteStaticKey: Data?)
        /// Accepts connections (the receiver).
        case responder
    }

    public static let pingInterval: TimeInterval = 10
    public static let peerSilenceTimeout: TimeInterval = 25

    public let role: Role
    private let core: CoreSession

    /// - Parameters:
    ///   - isTrusted: Responder only: whether a reconnecting device's public key is paired.
    ///   - isPairingOpen: Responder only: whether the person opened pairing on this device.
    public init(
        role: Role,
        identity: CarrierV2Identity,
        now: Date = Date(),
        isTrusted: @escaping (Data) -> Bool = { _ in false },
        isPairingOpen: @escaping () -> Bool = { false }
    ) {
        self.role = role
        let coreRole: CoreRole
        let policy: CoreResponderPolicy?
        switch role {
        case .initiator(let mode, let remoteStaticKey):
            coreRole = .initiator(mode: mode.core, remoteStaticKey: remoteStaticKey)
            policy = nil
        case .responder:
            coreRole = .responder
            policy = ResponderPolicy(isTrusted: isTrusted, isPairingOpen: isPairingOpen)
        }
        core = CoreSession(role: coreRole, identity: identity.core, nowMs: Self.milliseconds(now), policy: policy)
    }

    public var isEstablished: Bool { core.isEstablished() }
    public var isClosed: Bool { core.isClosed() }
    public var peer: CarrierV2Peer? { core.peer().map(CarrierV2Peer.init) }

    /// The initiator speaks first; the responder waits for its hello.
    public func start() -> [CarrierV2SessionEvent] {
        Self.convert(core.start())
    }

    public func receive(_ data: Data, now: Date = Date()) -> [CarrierV2SessionEvent] {
        Self.convert(core.receive(bytes: data, nowMs: Self.milliseconds(now)))
    }

    public func send(_ envelope: CarrierEnvelope) throws -> [CarrierV2SessionEvent] {
        let json = String(decoding: try CarrierCodec.encode(envelope), as: UTF8.self)
        do {
            return Self.convert(try core.sendEnvelope(envelopeJson: json))
        } catch CoreSessionError.NotConnected {
            throw CarrierServiceError.noConnectedPeer
        } catch CoreSessionError.MessageTooLarge {
            throw CarrierServiceError.textTooLong
        }
    }

    /// Receiver: the person saw the same code on both screens.
    public func confirmPairing() -> [CarrierV2SessionEvent] {
        Self.convert(core.confirmPairing())
    }

    public func rejectPairing() -> [CarrierV2SessionEvent] {
        Self.convert(core.rejectPairing())
    }

    /// Call periodically (every few seconds). Sends heartbeats and detects a silent peer.
    public func tick(now: Date = Date()) -> [CarrierV2SessionEvent] {
        Self.convert(core.tick(nowMs: Self.milliseconds(now)))
    }

    public func shutdown() -> [CarrierV2SessionEvent] {
        Self.convert(core.shutdown())
    }

    // MARK: - Conversion

    private static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970 * 1_000))
    }

    private static func convert(_ events: [CoreSessionEvent]) -> [CarrierV2SessionEvent] {
        events.map { event in
            switch event {
            case .write(let bytes):
                return .write(bytes)
            case .pairingCodeReady(let code, let peer):
                return .pairingCodeReady(code: code, peer: CarrierV2Peer(peer))
            case .established(let peer):
                return .established(peer: CarrierV2Peer(peer))
            case .received(let json):
                // An envelope this app cannot read is a peer speaking a newer envelope format.
                guard let envelope = try? CarrierCodec.decode(Data(json.utf8)) else {
                    return .received(.error("Unreadable envelope"))
                }
                return .received(envelope)
            case .closed(let reason):
                return .closed(CarrierV2CloseReason(reason))
            }
        }
    }
}

private final class ResponderPolicy: CoreResponderPolicy, @unchecked Sendable {
    // The session only calls back synchronously from the thread driving it.
    private let trusted: (Data) -> Bool
    private let pairingOpen: () -> Bool

    init(isTrusted: @escaping (Data) -> Bool, isPairingOpen: @escaping () -> Bool) {
        trusted = isTrusted
        pairingOpen = isPairingOpen
    }

    func isTrusted(publicKey: Data) -> Bool { trusted(publicKey) }
    func isPairingOpen() -> Bool { pairingOpen() }
}
