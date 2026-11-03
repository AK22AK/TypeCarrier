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
}

/// The other end of an established session.
public struct CarrierV2Peer: Equatable, Sendable {
    public let info: CarrierV2DeviceInfo
    public let publicKey: Data
    public let hello: CarrierHello
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

/// Protocol logic for one v2 connection, independent of sockets and clocks so it can be tested
/// in memory and reused by any transport. Feed it received bytes and timer ticks; it returns the
/// bytes to write and what happened.
public struct CarrierV2Session {
    public enum Role: Equatable {
        /// Opens the connection (the sender today). `connect` needs the paired receiver's key.
        case initiator(CarrierHello.Mode, remoteStaticKey: Data?)
        /// Accepts connections (the receiver today).
        case responder
    }

    public static let pingInterval: TimeInterval = 10
    public static let peerSilenceTimeout: TimeInterval = 25

    private enum State {
        case awaitingHello
        case handshaking(NoiseHandshakeState)
        case awaitingPairingDecision(NoiseTransport, CarrierV2Peer)
        case established(NoiseTransport, CarrierV2Peer)
        case closed
    }

    public let role: Role
    private let identity: CarrierV2Identity
    private let isTrusted: (Data) -> Bool
    private let isPairingOpen: () -> Bool
    private var state = State.awaitingHello
    private var buffer = Data()
    private var localHelloData: Data?
    private var remoteHello: CarrierHello?
    /// The peer's info from whichever handshake message carried it. In XX the initiator finishes on
    /// its own write, so message 2's payload has to be kept until then.
    private var remotePeerInfo: CarrierV2DeviceInfo?
    private var lastReceived: Date
    private var lastPingSent: Date?
    private var nextPingID: UInt64 = 1

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
        self.identity = identity
        self.isTrusted = isTrusted
        self.isPairingOpen = isPairingOpen
        lastReceived = now
    }

    public var isEstablished: Bool {
        if case .established = state { return true }
        return false
    }

    public var isClosed: Bool {
        if case .closed = state { return true }
        return false
    }

    public var peer: CarrierV2Peer? {
        switch state {
        case .established(_, let peer), .awaitingPairingDecision(_, let peer): return peer
        default: return nil
        }
    }

    /// The initiator speaks first; the responder waits for its hello.
    public mutating func start() -> [CarrierV2SessionEvent] {
        guard case .initiator(let mode, _) = role else { return [] }
        return sendHello(mode: mode)
    }

    public mutating func receive(_ data: Data, now: Date = Date()) -> [CarrierV2SessionEvent] {
        guard !isClosed else { return [] }
        lastReceived = now
        buffer.append(data)
        var events: [CarrierV2SessionEvent] = []
        do {
            while !isClosed, let frame = try CarrierWireFrame.nextPayload(from: &buffer) {
                events += try handle(frame)
            }
        } catch let reason as CarrierV2CloseReason {
            events += close(reason, notifyPeer: true)
        } catch NoiseError.decryptionFailed, NoiseError.invalidPublicKey, NoiseError.messageTooShort {
            events += close(.handshakeFailed, notifyPeer: !isEstablished)
        } catch {
            events += close(.protocolViolation, notifyPeer: true)
        }
        return events
    }

    public mutating func send(_ envelope: CarrierEnvelope) throws -> [CarrierV2SessionEvent] {
        guard case .established = state else { throw CarrierServiceError.noConnectedPeer }
        return try encrypted(.envelope(envelope))
    }

    /// Receiver: the person saw the same code on both screens.
    public mutating func confirmPairing() -> [CarrierV2SessionEvent] {
        guard case .awaitingPairingDecision(let transport, let peer) = state else { return [] }
        state = .established(transport, peer)
        do {
            return try encrypted(.pairingConfirmed) + [.established(peer: peer)]
        } catch {
            return close(.protocolViolation, notifyPeer: false)
        }
    }

    public mutating func rejectPairing() -> [CarrierV2SessionEvent] {
        guard case .awaitingPairingDecision = state else { return [] }
        let notice = (try? encrypted(.pairingRejected)) ?? []
        state = .closed
        return notice + [.closed(.pairingRejected)]
    }

    /// Call periodically (every few seconds). Sends heartbeats and detects a silent peer.
    public mutating func tick(now: Date = Date()) -> [CarrierV2SessionEvent] {
        guard case .established = state else { return [] }
        if now.timeIntervalSince(lastReceived) >= Self.peerSilenceTimeout {
            return close(.heartbeatTimeout, notifyPeer: false)
        }
        guard now.timeIntervalSince(max(lastReceived, lastPingSent ?? .distantPast)) >= Self.pingInterval else {
            return []
        }
        lastPingSent = now
        defer { nextPingID += 1 }
        return (try? encrypted(.ping(nextPingID))) ?? []
    }

    public mutating func shutdown() -> [CarrierV2SessionEvent] {
        guard !isClosed else { return [] }
        return close(.shutdown, notifyPeer: true)
    }

    // MARK: - Handling frames

    private mutating func handle(_ frame: Data) throws -> [CarrierV2SessionEvent] {
        switch state {
        case .awaitingHello:
            return try handleHello(frame)
        case .handshaking(var handshake):
            if let reason = plaintextClose(frame) {
                state = .closed
                return [.closed(reason)]
            }
            let payload = try handshake.readMessage(frame)
            return try advance(handshake, receivedPayload: payload)
        case .awaitingPairingDecision(var transport, let peer):
            let message = try CarrierV2Message.decode(try transport.receive.decrypt(frame))
            state = .awaitingPairingDecision(transport, peer)
            return try handlePairingDecision(message)
        case .established(var transport, let peer):
            let message = try CarrierV2Message.decode(try transport.receive.decrypt(frame))
            state = .established(transport, peer)
            return try handleEstablished(message)
        case .closed:
            return []
        }
    }

    private mutating func handleHello(_ frame: Data) throws -> [CarrierV2SessionEvent] {
        if let reason = plaintextClose(frame) {
            state = .closed
            return [.closed(reason)]
        }
        let hello: CarrierHello
        do {
            hello = try CarrierHello.decode(frame)
        } catch {
            throw CarrierV2CloseReason.protocolViolation
        }
        remoteHello = hello

        switch role {
        case .initiator(let mode, let remoteKey):
            guard let localHelloData else { throw CarrierV2CloseReason.protocolViolation }
            guard try localHello().negotiatedVersion(with: hello) != nil else {
                throw CarrierV2CloseReason.unsupportedVersion
            }
            let prologue = CarrierProtocolV2.prologue(initiatorHello: localHelloData, responderHello: frame)
            var handshake = try NoiseHandshakeState(
                pattern: mode == .pair ? .xx : .ik,
                isInitiator: true,
                localStatic: identity.staticKey,
                remoteStatic: try remoteKey.map { try Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) },
                prologue: prologue
            )
            let payload = mode == .pair ? Data() : try JSONEncoder().encode(identity.info)
            let message = try handshake.writeMessage(payload: payload)
            state = .handshaking(handshake)
            return [.write(try CarrierWireFrame.encode(message))]

        case .responder:
            let events = sendHello(mode: hello.mode)
            guard !isClosed else { return events }
            guard let localHelloData, try localHello().negotiatedVersion(with: hello) != nil else {
                throw CarrierV2CloseReason.unsupportedVersion
            }
            if hello.mode == .pair, !isPairingOpen() {
                throw CarrierV2CloseReason.pairingNotOpen
            }
            let handshake = try NoiseHandshakeState(
                pattern: hello.mode == .pair ? .xx : .ik,
                isInitiator: false,
                localStatic: identity.staticKey,
                prologue: CarrierProtocolV2.prologue(initiatorHello: frame, responderHello: localHelloData)
            )
            state = .handshaking(handshake)
            return events
        }
    }

    /// After reading a handshake message: write the next one if it is our turn, then finish.
    private mutating func advance(_ handshake: NoiseHandshakeState, receivedPayload: Data) throws -> [CarrierV2SessionEvent] {
        var handshake = handshake
        var events: [CarrierV2SessionEvent] = []
        if !receivedPayload.isEmpty {
            guard let info = try? JSONDecoder().decode(CarrierV2DeviceInfo.self, from: receivedPayload) else {
                throw CarrierV2CloseReason.protocolViolation
            }
            remotePeerInfo = info
        }

        // IK responder: the first message revealed who is connecting.
        if case .responder = role, handshake.pattern == .ik,
           let remoteKey = handshake.remoteStaticKey, !isTrusted(remoteKey.rawRepresentation) {
            throw CarrierV2CloseReason.notPaired
        }

        if !handshake.isComplete, handshake.isMyTurnToWrite {
            let message = try handshake.writeMessage(payload: try JSONEncoder().encode(identity.info))
            events.append(.write(try CarrierWireFrame.encode(message)))
        }
        guard handshake.isComplete else {
            state = .handshaking(handshake)
            return events
        }

        let transport = try handshake.transport()
        guard let remoteInfo = remotePeerInfo, let remoteHello else { throw CarrierV2CloseReason.protocolViolation }
        let peer = CarrierV2Peer(info: remoteInfo, publicKey: transport.remoteStaticKey.rawRepresentation, hello: remoteHello)

        if handshake.pattern == .xx {
            state = .awaitingPairingDecision(transport, peer)
            events.append(.pairingCodeReady(code: CarrierProtocolV2.pairingCode(handshakeHash: transport.handshakeHash), peer: peer))
        } else {
            state = .established(transport, peer)
            events.append(.established(peer: peer))
        }
        return events
    }

    private mutating func handlePairingDecision(_ message: CarrierV2Message) throws -> [CarrierV2SessionEvent] {
        guard case .initiator = role, case .awaitingPairingDecision(let transport, let peer) = state else {
            throw CarrierV2CloseReason.protocolViolation
        }
        switch message {
        case .pairingConfirmed:
            state = .established(transport, peer)
            return [.established(peer: peer)]
        case .pairingRejected:
            state = .closed
            return [.closed(.pairingRejected)]
        case .close(let reason):
            state = .closed
            return [.closed(reason)]
        default:
            throw CarrierV2CloseReason.protocolViolation
        }
    }

    private mutating func handleEstablished(_ message: CarrierV2Message) throws -> [CarrierV2SessionEvent] {
        switch message {
        case .envelope(let envelope):
            return [.received(envelope)]
        case .ping(let id):
            return try encrypted(.pong(id))
        case .pong:
            return []
        case .close(let reason):
            state = .closed
            return [.closed(reason)]
        case .pairingConfirmed, .pairingRejected:
            throw CarrierV2CloseReason.protocolViolation
        }
    }

    // MARK: - Helpers

    private func localHello() throws -> CarrierHello {
        guard let localHelloData else { throw CarrierV2CloseReason.protocolViolation }
        return try CarrierHello.decode(localHelloData)
    }

    private mutating func sendHello(mode: CarrierHello.Mode) -> [CarrierV2SessionEvent] {
        let hello = CarrierHello(mode: mode, platform: identity.platform, capabilities: identity.capabilities)
        guard let data = try? hello.encoded(), let frame = try? CarrierWireFrame.encode(data) else {
            return close(.protocolViolation, notifyPeer: false)
        }
        localHelloData = data
        return [.write(frame)]
    }

    private func plaintextClose(_ frame: Data) -> CarrierV2CloseReason? {
        guard case .close(let reason)? = try? CarrierV2Message.decode(frame) else { return nil }
        return reason
    }

    private mutating func encrypted(_ message: CarrierV2Message) throws -> [CarrierV2SessionEvent] {
        switch state {
        case .established(var transport, let peer):
            let frame = try CarrierWireFrame.encode(try transport.send.encrypt(try message.encoded()))
            state = .established(transport, peer)
            return [.write(frame)]
        case .awaitingPairingDecision(var transport, let peer):
            let frame = try CarrierWireFrame.encode(try transport.send.encrypt(try message.encoded()))
            state = .awaitingPairingDecision(transport, peer)
            return [.write(frame)]
        default:
            throw CarrierServiceError.noConnectedPeer
        }
    }

    /// Before the handshake finishes, a close goes out in plaintext; afterwards it is encrypted.
    private mutating func close(_ reason: CarrierV2CloseReason, notifyPeer: Bool) -> [CarrierV2SessionEvent] {
        var events: [CarrierV2SessionEvent] = []
        if notifyPeer {
            switch state {
            case .established, .awaitingPairingDecision:
                events += (try? encrypted(.close(reason))) ?? []
            case .awaitingHello, .handshaking:
                if let data = try? CarrierV2Message.close(reason).encoded(), let frame = try? CarrierWireFrame.encode(data) {
                    events.append(.write(frame))
                }
            case .closed:
                break
            }
        }
        state = .closed
        events.append(.closed(reason))
        return events
    }
}
