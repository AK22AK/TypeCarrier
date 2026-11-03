import CryptoKit
import Foundation

/// Noise Protocol Framework (revision 34) for the 25519 / ChaChaPoly / SHA256 suite,
/// implementing the two handshake patterns TypeCarrier uses:
/// - `XX` for first-time pairing, when neither side knows the other's static key.
/// - `IK` for every later connection, when the initiator already knows the responder's key.
/// The spec lives at https://noiseprotocol.org/noise.html; names below follow it.
public enum NoisePattern: String, Sendable {
    case xx = "XX"
    case ik = "IK"

    public var protocolName: String {
        "Noise_\(rawValue)_25519_ChaChaPoly_SHA256"
    }

    fileprivate enum Token {
        case e, s, ee, es, se, ss
    }

    fileprivate var messagePatterns: [[Token]] {
        switch self {
        case .xx:
            return [[.e], [.e, .ee, .s, .es], [.s, .se]]
        case .ik:
            return [[.e, .es, .s, .ss], [.e, .ee, .se]]
        }
    }
}

public enum NoiseError: Error, Equatable, Sendable {
    case missingRemoteStatic
    case handshakeAlreadyComplete
    case handshakeIncomplete
    case notYourTurn
    case messageTooShort
    case messageTooLarge
    case decryptionFailed
    case nonceExhausted
    case invalidPublicKey
}

public struct NoiseCipherState: Sendable {
    public static let maxMessageLength = 65_535
    private static let tagLength = 16

    private var key: SymmetricKey?
    private var nonce: UInt64 = 0

    init(key: SymmetricKey? = nil) {
        self.key = key
    }

    var hasKey: Bool { key != nil }

    mutating func encrypt(_ plaintext: Data, associatedData: Data = Data()) throws -> Data {
        guard let key else { return plaintext }
        guard plaintext.count + Self.tagLength <= Self.maxMessageLength else { throw NoiseError.messageTooLarge }
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: try nextNonce(), authenticating: associatedData)
        // Rebase to index 0: the sealed box fields are slices of its combined representation.
        return Data(sealed.ciphertext) + Data(sealed.tag)
    }

    mutating func decrypt(_ ciphertext: Data, associatedData: Data = Data()) throws -> Data {
        guard let key else { return ciphertext }
        guard ciphertext.count >= Self.tagLength else { throw NoiseError.messageTooShort }
        let nonce = try nextNonce()
        let box = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext.prefix(ciphertext.count - Self.tagLength),
            tag: ciphertext.suffix(Self.tagLength)
        )
        do {
            return try ChaChaPoly.open(box, using: key, authenticating: associatedData)
        } catch {
            // A failed decryption must not advance the nonce, or a forged frame would desync the session.
            self.nonce -= 1
            throw NoiseError.decryptionFailed
        }
    }

    public mutating func encrypt(_ plaintext: Data) throws -> Data {
        try encrypt(plaintext, associatedData: Data())
    }

    public mutating func decrypt(_ ciphertext: Data) throws -> Data {
        try decrypt(ciphertext, associatedData: Data())
    }

    private mutating func nextNonce() throws -> ChaChaPoly.Nonce {
        // 2^64-1 is reserved by the spec.
        guard nonce < UInt64.max else { throw NoiseError.nonceExhausted }
        var bytes = Data(count: 4)
        withUnsafeBytes(of: nonce.littleEndian) { bytes.append(contentsOf: $0) }
        nonce += 1
        return try ChaChaPoly.Nonce(data: bytes)
    }
}

struct NoiseSymmetricState {
    private(set) var chainingKey: Data
    private(set) var handshakeHash: Data
    private var cipher = NoiseCipherState()

    init(protocolName: String) {
        let name = Data(protocolName.utf8)
        handshakeHash = name.count <= 32 ? name + Data(count: 32 - name.count) : Self.hash(name)
        chainingKey = handshakeHash
    }

    mutating func mixKey(_ inputKeyMaterial: Data) {
        let (nextChainingKey, key) = Self.hkdf2(chainingKey: chainingKey, inputKeyMaterial: inputKeyMaterial)
        chainingKey = nextChainingKey
        cipher = NoiseCipherState(key: SymmetricKey(data: key))
    }

    mutating func mixHash(_ data: Data) {
        handshakeHash = Self.hash(handshakeHash + data)
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ciphertext = try cipher.encrypt(plaintext, associatedData: handshakeHash)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext = try cipher.decrypt(ciphertext, associatedData: handshakeHash)
        mixHash(ciphertext)
        return plaintext
    }

    var hasKey: Bool { cipher.hasKey }

    func split() -> (NoiseCipherState, NoiseCipherState) {
        let (first, second) = Self.hkdf2(chainingKey: chainingKey, inputKeyMaterial: Data())
        return (NoiseCipherState(key: SymmetricKey(data: first)), NoiseCipherState(key: SymmetricKey(data: second)))
    }

    static func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func hkdf2(chainingKey: Data, inputKeyMaterial: Data) -> (Data, Data) {
        let tempKey = hmac(key: chainingKey, data: inputKeyMaterial)
        let output1 = hmac(key: tempKey, data: Data([0x01]))
        let output2 = hmac(key: tempKey, data: output1 + Data([0x02]))
        return (output1, output2)
    }
}

/// Transport keys produced by a finished handshake.
public struct NoiseTransport: Sendable {
    public var send: NoiseCipherState
    public var receive: NoiseCipherState
    /// Unique per session; both sides derive the same value. Pairing shows a short code from it.
    public let handshakeHash: Data
    public let remoteStaticKey: Curve25519.KeyAgreement.PublicKey
}

public struct NoiseHandshakeState {
    public let pattern: NoisePattern
    public let isInitiator: Bool

    private var symmetric: NoiseSymmetricState
    private let localStatic: Curve25519.KeyAgreement.PrivateKey
    private var localEphemeral: Curve25519.KeyAgreement.PrivateKey?
    private var pendingEphemeral: Curve25519.KeyAgreement.PrivateKey?
    private var remoteStatic: Curve25519.KeyAgreement.PublicKey?
    private var remoteEphemeral: Curve25519.KeyAgreement.PublicKey?
    private var messageIndex = 0

    /// - Parameters:
    ///   - prologue: Data both sides must agree on (TypeCarrier binds the plaintext hello exchange here).
    ///   - remoteStatic: Required for an `IK` initiator.
    ///   - ephemeral: Only for deterministic tests; production code lets each handshake generate one.
    public init(
        pattern: NoisePattern,
        isInitiator: Bool,
        localStatic: Curve25519.KeyAgreement.PrivateKey,
        remoteStatic: Curve25519.KeyAgreement.PublicKey? = nil,
        prologue: Data = Data(),
        ephemeral: Curve25519.KeyAgreement.PrivateKey? = nil
    ) throws {
        if pattern == .ik, isInitiator, remoteStatic == nil {
            throw NoiseError.missingRemoteStatic
        }
        self.pattern = pattern
        self.isInitiator = isInitiator
        self.localStatic = localStatic
        self.remoteStatic = remoteStatic
        pendingEphemeral = ephemeral
        symmetric = NoiseSymmetricState(protocolName: pattern.protocolName)
        symmetric.mixHash(prologue)
        // IK pre-message: <- s
        if pattern == .ik {
            let responderStatic = isInitiator ? remoteStatic! : localStatic.publicKey
            symmetric.mixHash(responderStatic.rawRepresentation)
        }
    }

    public var isComplete: Bool {
        messageIndex >= pattern.messagePatterns.count
    }

    public var isMyTurnToWrite: Bool {
        (messageIndex % 2 == 0) == isInitiator
    }

    public var handshakeHash: Data { symmetric.handshakeHash }

    /// Known up front for an IK initiator, otherwise once the handshake message carrying it is read.
    public var remoteStaticKey: Curve25519.KeyAgreement.PublicKey? { remoteStatic }

    public mutating func writeMessage(payload: Data = Data()) throws -> Data {
        guard !isComplete else { throw NoiseError.handshakeAlreadyComplete }
        guard isMyTurnToWrite else { throw NoiseError.notYourTurn }

        var message = Data()
        for token in pattern.messagePatterns[messageIndex] {
            switch token {
            case .e:
                let ephemeral = pendingEphemeral ?? Curve25519.KeyAgreement.PrivateKey()
                pendingEphemeral = nil
                localEphemeral = ephemeral
                message += ephemeral.publicKey.rawRepresentation
                symmetric.mixHash(ephemeral.publicKey.rawRepresentation)
            case .s:
                message += try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation)
            default:
                try mixDH(token)
            }
        }
        message += try symmetric.encryptAndHash(payload)
        guard message.count <= NoiseCipherState.maxMessageLength else { throw NoiseError.messageTooLarge }
        messageIndex += 1
        return message
    }

    public mutating func readMessage(_ message: Data) throws -> Data {
        guard !isComplete else { throw NoiseError.handshakeAlreadyComplete }
        guard !isMyTurnToWrite else { throw NoiseError.notYourTurn }
        guard message.count <= NoiseCipherState.maxMessageLength else { throw NoiseError.messageTooLarge }

        var remaining = message[...]
        func take(_ count: Int) throws -> Data {
            guard remaining.count >= count else { throw NoiseError.messageTooShort }
            defer { remaining = remaining.dropFirst(count) }
            return Data(remaining.prefix(count))
        }

        for token in pattern.messagePatterns[messageIndex] {
            switch token {
            case .e:
                let bytes = try take(32)
                remoteEphemeral = try publicKey(bytes)
                symmetric.mixHash(bytes)
            case .s:
                let bytes = try take(symmetric.hasKey ? 48 : 32)
                remoteStatic = try publicKey(try symmetric.decryptAndHash(bytes))
            default:
                try mixDH(token)
            }
        }
        let payload = try symmetric.decryptAndHash(Data(remaining))
        messageIndex += 1
        return payload
    }

    /// Call once `isComplete` is true. The initiator sends with the first key.
    public func transport() throws -> NoiseTransport {
        guard isComplete else { throw NoiseError.handshakeIncomplete }
        guard let remoteStatic else { throw NoiseError.missingRemoteStatic }
        let (first, second) = symmetric.split()
        return NoiseTransport(
            send: isInitiator ? first : second,
            receive: isInitiator ? second : first,
            handshakeHash: symmetric.handshakeHash,
            remoteStaticKey: remoteStatic
        )
    }

    private mutating func mixDH(_ token: NoisePattern.Token) throws {
        // Token names are written from the initiator's view: "es" = initiator ephemeral x responder static.
        let (localKey, remoteKey): (Curve25519.KeyAgreement.PrivateKey?, Curve25519.KeyAgreement.PublicKey?)
        switch (token, isInitiator) {
        case (.ee, _):
            (localKey, remoteKey) = (localEphemeral, remoteEphemeral)
        case (.ss, _):
            (localKey, remoteKey) = (localStatic, remoteStatic)
        case (.es, true), (.se, false):
            (localKey, remoteKey) = (localEphemeral, remoteStatic)
        case (.es, false), (.se, true):
            (localKey, remoteKey) = (localStatic, remoteEphemeral)
        default:
            return
        }
        guard let localKey, let remoteKey else { throw NoiseError.missingRemoteStatic }
        let shared = try localKey.sharedSecretFromKeyAgreement(with: remoteKey)
        symmetric.mixKey(shared.withUnsafeBytes { Data($0) })
    }

    private func publicKey(_ bytes: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
        } catch {
            throw NoiseError.invalidPublicKey
        }
    }
}
