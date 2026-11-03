import CryptoKit
import Foundation
import XCTest
@testable import TypeCarrierCore

final class NoiseProtocolTests: XCTestCase {
    func testMatchesPublishedCacophonyVectors() throws {
        for vector in Self.vectors {
            try run(vector)
        }
    }

    func testXXThenIKBetweenFreshKeysAgreeOnTransportAndHash() throws {
        let phone = Curve25519.KeyAgreement.PrivateKey()
        let mac = Curve25519.KeyAgreement.PrivateKey()

        var pairingPhone = try NoiseHandshakeState(pattern: .xx, isInitiator: true, localStatic: phone, prologue: Data("hello".utf8))
        var pairingMac = try NoiseHandshakeState(pattern: .xx, isInitiator: false, localStatic: mac, prologue: Data("hello".utf8))
        _ = try pairingMac.readMessage(try pairingPhone.writeMessage())
        _ = try pairingPhone.readMessage(try pairingMac.writeMessage())
        _ = try pairingMac.readMessage(try pairingPhone.writeMessage())
        let phonePairing = try pairingPhone.transport()
        let macPairing = try pairingMac.transport()
        XCTAssertEqual(phonePairing.handshakeHash, macPairing.handshakeHash)
        XCTAssertEqual(phonePairing.remoteStaticKey.rawRepresentation, mac.publicKey.rawRepresentation)
        XCTAssertEqual(macPairing.remoteStaticKey.rawRepresentation, phone.publicKey.rawRepresentation)

        var phoneIK = try NoiseHandshakeState(pattern: .ik, isInitiator: true, localStatic: phone, remoteStatic: mac.publicKey)
        var macIK = try NoiseHandshakeState(pattern: .ik, isInitiator: false, localStatic: mac)
        XCTAssertEqual(try macIK.readMessage(try phoneIK.writeMessage(payload: Data("hi".utf8))), Data("hi".utf8))
        _ = try phoneIK.readMessage(try macIK.writeMessage())
        var phoneTransport = try phoneIK.transport()
        var macTransport = try macIK.transport()
        XCTAssertEqual(macTransport.remoteStaticKey.rawRepresentation, phone.publicKey.rawRepresentation)

        let frame = try phoneTransport.send.encrypt(Data("你好".utf8))
        XCTAssertEqual(try macTransport.receive.decrypt(frame), Data("你好".utf8))
        let reply = try macTransport.send.encrypt(Data("ok".utf8))
        XCTAssertEqual(try phoneTransport.receive.decrypt(reply), Data("ok".utf8))
    }

    func testIKResponderRejectsInitiatorThatGuessedTheWrongResponderKey() throws {
        let phone = Curve25519.KeyAgreement.PrivateKey()
        let mac = Curve25519.KeyAgreement.PrivateKey()
        let impostor = Curve25519.KeyAgreement.PrivateKey()
        var phoneIK = try NoiseHandshakeState(pattern: .ik, isInitiator: true, localStatic: phone, remoteStatic: mac.publicKey)
        var impostorIK = try NoiseHandshakeState(pattern: .ik, isInitiator: false, localStatic: impostor)

        XCTAssertThrowsError(try impostorIK.readMessage(try phoneIK.writeMessage())) { error in
            XCTAssertEqual(error as? NoiseError, .decryptionFailed)
        }
    }

    func testMismatchedProloguesFailTheHandshake() throws {
        let phone = Curve25519.KeyAgreement.PrivateKey()
        let mac = Curve25519.KeyAgreement.PrivateKey()
        var phoneIK = try NoiseHandshakeState(pattern: .ik, isInitiator: true, localStatic: phone, remoteStatic: mac.publicKey, prologue: Data("v2".utf8))
        var macIK = try NoiseHandshakeState(pattern: .ik, isInitiator: false, localStatic: mac, prologue: Data("v1".utf8))

        XCTAssertThrowsError(try macIK.readMessage(try phoneIK.writeMessage()))
    }

    func testTamperedTransportFrameIsRejectedWithoutDesyncingTheSession() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = NoiseCipherState(key: key)
        var receiver = NoiseCipherState(key: key)
        var frame = try sender.encrypt(Data("one".utf8))
        frame[0] ^= 0x01

        XCTAssertThrowsError(try receiver.decrypt(frame)) { error in
            XCTAssertEqual(error as? NoiseError, .decryptionFailed)
        }
        frame[0] ^= 0x01
        XCTAssertEqual(try receiver.decrypt(frame), Data("one".utf8))
    }

    private func run(_ vector: NoiseVector) throws {
        let initiatorStatic = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: vector.initiatorStatic.hexData)
        let responderStatic = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: vector.responderStatic.hexData)
        var initiator = try NoiseHandshakeState(
            pattern: vector.pattern,
            isInitiator: true,
            localStatic: initiatorStatic,
            remoteStatic: try vector.initiatorRemoteStatic.map { try Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0.hexData) },
            prologue: vector.prologue.hexData,
            ephemeral: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: vector.initiatorEphemeral.hexData)
        )
        var responder = try NoiseHandshakeState(
            pattern: vector.pattern,
            isInitiator: false,
            localStatic: responderStatic,
            prologue: vector.prologue.hexData,
            ephemeral: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: vector.responderEphemeral.hexData)
        )

        var initiatorTransport: NoiseTransport?
        var responderTransport: NoiseTransport?
        for (index, message) in vector.messages.enumerated() {
            let initiatorSends = index % 2 == 0
            let payload = message.payload.hexData
            let ciphertext: Data
            let received: Data
            if !initiator.isComplete {
                if initiatorSends {
                    ciphertext = try initiator.writeMessage(payload: payload)
                    received = try responder.readMessage(ciphertext)
                } else {
                    ciphertext = try responder.writeMessage(payload: payload)
                    received = try initiator.readMessage(ciphertext)
                }
                if initiator.isComplete {
                    XCTAssertTrue(responder.isComplete)
                    XCTAssertEqual(initiator.handshakeHash.hexString, vector.handshakeHash, vector.pattern.protocolName)
                    initiatorTransport = try initiator.transport()
                    responderTransport = try responder.transport()
                }
            } else if initiatorSends {
                ciphertext = try initiatorTransport!.send.encrypt(payload)
                received = try responderTransport!.receive.decrypt(ciphertext)
            } else {
                ciphertext = try responderTransport!.send.encrypt(payload)
                received = try initiatorTransport!.receive.decrypt(ciphertext)
            }
            XCTAssertEqual(ciphertext.hexString, message.ciphertext, "\(vector.pattern.protocolName) message \(index)")
            XCTAssertEqual(received, payload)
        }
    }

    private struct NoiseVector {
        let pattern: NoisePattern
        let prologue: String
        let initiatorStatic: String
        let initiatorEphemeral: String
        let initiatorRemoteStatic: String?
        let responderStatic: String
        let responderEphemeral: String
        let handshakeHash: String
        let messages: [(payload: String, ciphertext: String)]
    }

    // From the cacophony test vectors (github.com/haskell-cryptography/cacophony, vectors/cacophony.txt).
    private static let vectors: [NoiseVector] = [
        NoiseVector(
            pattern: .ik,
            prologue: "4a6f686e2047616c74",
            initiatorStatic: "e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1",
            initiatorEphemeral: "893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a",
            initiatorRemoteStatic: "31e0303fd6418d2f8c0e78b91f22e8caed0fbe48656dcf4767e4834f701b8f62",
            responderStatic: "4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893",
            responderEphemeral: "bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b",
            handshakeHash: "0b0f68fb0c27e03ce9b97565995ed4838cc0581b762ef72b062f6a546419fad7",
            messages: [
                ("4c756477696720766f6e204d69736573", "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c7944718da798efbcd91528520204f904b9bd6c7413dccdc214d951e15253e39987f18146e8cd0873654207148333479d4d16c289f0294b29960a72f48e0b7bba2e89083169825e59642148d492020664ccf7"),
                ("4d757272617920526f746862617264", "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f1448088435361e70b2ed446e6c9ec387d1d6b3b840f194e373979d241b203c4acafccf5"),
                ("462e20412e20486179656b", "050e9f3c8fac16b68dbce8f8c4bfbf6617c897f9ada4aa29aa19c8"),
                ("4361726c204d656e676572", "344233a6cabb7141d80f3da2fedc311d9646bbb0f505afe403a667"),
                ("4a65616e2d426170746973746520536179", "62cdeeb172ad7ade7aa7d9e069da5790f12331bfa00177787a1d0810c67dc3b2b4"),
                ("457567656e2042f6686d20766f6e2042617765726b", "029bead1b40992327044d409d9a1f3ad8f36c3c452775d557e18bbeb2e8dfcead32d514024")
            ]
        ),
        NoiseVector(
            pattern: .xx,
            prologue: "4a6f686e2047616c74",
            initiatorStatic: "e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1",
            initiatorEphemeral: "893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a",
            initiatorRemoteStatic: nil,
            responderStatic: "4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893",
            responderEphemeral: "bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b",
            handshakeHash: "c8e5f64e846193be2a834104c2a009868d6c9f3bd3c186299888b488b2f1f58e",
            messages: [
                ("4c756477696720766f6e204d69736573", "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c79444c756477696720766f6e204d69736573"),
                ("4d757272617920526f746862617264", "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f14480884381cbad1f276e038c48378ffce2b65285e08d6b68aaa3629a5a8639392490e5b9bd5269c2f1e4f488ed8831161f19b7815528f8982ffe09be9b5c412f8a0db50f8814c7194e83f23dbd8d162c9326ad"),
                ("462e20412e20486179656b", "c7195ffacac1307ff99046f219750fc47693e23c3cb08b89c2af808b444850a80ae475b9df0f169ae80a89be0865b57f58c9fea0d4ec82a286427402f113e4b6ae769a1d95941d49b25030"),
                ("4361726c204d656e676572", "96763ed773f8e47bb3712f0e29b3060ffc956ffc146cee53d5e1df"),
                ("4a65616e2d426170746973746520536179", "3e40f15f6f3a46ae446b253bf8b1d9ffb6ed9b174d272328ff91a7e2e5c79c07f5"),
                ("457567656e2042f6686d20766f6e2042617765726b", "eb3f3515110702e047a6c9da4478b6ead94873c11c0f2d710ddb3f09fce024b3a58502ae3f")
            ]
        )
    ]
}

private extension String {
    var hexData: Data {
        var data = Data(capacity: count / 2)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: 2)
            data.append(UInt8(self[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
