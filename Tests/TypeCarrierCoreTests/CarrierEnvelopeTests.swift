import XCTest
@testable import TypeCarrierCore

final class CarrierEnvelopeTests: XCTestCase {
    func testTextEnvelopeRoundTripsPlainAndRichText() throws {
        let payload = CarrierPayload(
            id: UUID(uuidString: "08E0C213-3C08-4F4C-9168-5EE7728AFA61")!,
            createdAt: Date(timeIntervalSince1970: 1_777_777_777),
            text: "你好 TypeCarrier\n- Markdown\nEmoji: 🚀"
        )
        let envelope = CarrierEnvelope.text(payload)

        let data = try CarrierCodec.encode(envelope)
        let decoded = try CarrierCodec.decode(data)

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.payload?.text, payload.text)
    }

    func testTextEnvelopeRoundTripsSenderDeviceName() throws {
        let payload = CarrierPayload(
            id: UUID(uuidString: "E74B7F27-84D1-4E37-82D9-20C48353F12A")!,
            createdAt: Date(timeIntervalSince1970: 1_778_111_111),
            text: "from a named device"
        )
        let sender = CarrierDeviceIdentity(displayName: "jzj iPhone")
        let envelope = CarrierEnvelope.text(payload, sender: sender)

        let decoded = try CarrierCodec.decode(try CarrierCodec.encode(envelope))

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(decoded.sender, sender)
    }

    func testTextEnvelopeRoundTripsPostPasteAction() throws {
        let payload = CarrierPayload(
            id: UUID(uuidString: "8AF58B20-9E92-4C0F-90F6-8E31B76F25E1")!,
            createdAt: Date(timeIntervalSince1970: 1_778_222_222),
            text: "send and return",
            postPasteAction: .pressReturn
        )
        let envelope = CarrierEnvelope.text(payload)

        let decoded = try CarrierCodec.decode(try CarrierCodec.encode(envelope))

        XCTAssertEqual(decoded.payload?.postPasteAction, .pressReturn)
    }

    func testLegacyTextEnvelopeDecodesWithoutSenderDeviceName() throws {
        let data = """
        {
          "kind": "text",
          "payload": {
            "createdAt": "2026-05-30T08:00:00Z",
            "id": "BA2F6F30-F78E-4F21-98AA-539C5E0B25FA",
            "text": "legacy text"
          },
          "version": 1
        }
        """.data(using: .utf8)!

        let decoded = try CarrierCodec.decode(data)

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.payload?.text, "legacy text")
        XCTAssertNil(decoded.sender)
        XCTAssertNil(decoded.payload?.postPasteAction)
    }

    func testPlainTextEnvelopeOmitsPostPasteAction() throws {
        let payload = CarrierPayload(
            id: UUID(uuidString: "30AD73DB-4B66-430F-B3ED-F49F2E2D33B5")!,
            createdAt: Date(timeIntervalSince1970: 1_778_333_333),
            text: "plain send"
        )
        let data = try CarrierCodec.encode(.text(payload))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("postPasteAction"))
    }

    func testDeviceIdentityFallsBackToSystemNameWhenCustomNameIsBlank() {
        XCTAssertEqual(
            CarrierDeviceIdentity.preferredDisplayName(customName: "  ", systemName: "iPhone"),
            "iPhone"
        )
        XCTAssertEqual(
            CarrierDeviceIdentity.preferredDisplayName(customName: "  jzj iPhone  ", systemName: "iPhone"),
            "jzj iPhone"
        )
    }

    func testAckEnvelopeRoundTripsPayloadIdentifier() throws {
        let id = UUID(uuidString: "BC796636-69B6-48AF-A65F-56A16B85BB31")!
        let envelope = CarrierEnvelope.ack(id)

        let decoded = try CarrierCodec.decode(try CarrierCodec.encode(envelope))

        XCTAssertEqual(decoded.kind, .ack)
        XCTAssertEqual(decoded.ackID, id)
        XCTAssertNil(decoded.payload)
    }

    func testReceiptEnvelopeRoundTripsPasteResult() throws {
        let payloadID = UUID(uuidString: "8E6D5DB2-6DAB-4F17-A0C7-4986F929992E")!
        let receipt = CarrierDeliveryReceipt(
            payloadID: payloadID,
            receivedAt: Date(timeIntervalSince1970: 1_777_888_999),
            pasteStatus: .failed,
            detail: "Accessibility permission required"
        )
        let envelope = CarrierEnvelope.receipt(receipt)

        let decoded = try CarrierCodec.decode(try CarrierCodec.encode(envelope))

        XCTAssertEqual(decoded.kind, .receipt)
        XCTAssertEqual(decoded.receipt, receipt)
        XCTAssertNil(decoded.payload)
    }

    func testReceiptEnvelopeRoundTripsUnverifiedPostedPasteResult() throws {
        let payloadID = UUID(uuidString: "B5F45AA9-675D-4742-A189-19CF4DB34D8B")!
        let receipt = CarrierDeliveryReceipt(
            payloadID: payloadID,
            receivedAt: Date(timeIntervalSince1970: 1_777_889_111),
            pasteStatus: .unverifiedPosted,
            detail: "Command-V posted, but target insertion could not be verified"
        )
        let envelope = CarrierEnvelope.receipt(receipt)

        let decoded = try CarrierCodec.decode(try CarrierCodec.encode(envelope))

        XCTAssertEqual(decoded.kind, .receipt)
        XCTAssertEqual(decoded.receipt, receipt)
    }

    func testBlankTextIsRejectedBeforeSending() {
        XCTAssertFalse(CarrierPayload.canSend(""))
        XCTAssertFalse(CarrierPayload.canSend(" \n\t "))
        XCTAssertTrue(CarrierPayload.canSend(" dictated text "))
    }
}

final class CarrierPayloadLengthLimitTests: XCTestCase {
    func testTextUpToTheCharacterLimitCanBeSentAndBeyondItCannot() {
        let atLimit = String(repeating: "字", count: CarrierPayload.maximumCharacterCount)
        XCTAssertTrue(CarrierPayload.canSend(atLimit))
        XCTAssertFalse(CarrierPayload.canSend(atLimit + "字"))
        XCTAssertTrue(CarrierPayload.hasContent(atLimit + "字"))
    }

    func testLongEmojiSequencesStayInsideOneEncryptedFrame() throws {
        // A family emoji is one character but 25 UTF-8 bytes.
        let family = "👨‍👩‍👧‍👦"
        let text = String(repeating: family, count: 2_000)
        XCTAssertLessThanOrEqual(text.count, CarrierPayload.maximumCharacterCount)
        XCTAssertFalse(CarrierPayload.canSend(text))

        let largestAllowed = String(repeating: "\u{01}", count: CarrierPayload.maximumCharacterCount)
        XCTAssertTrue(CarrierPayload.canSend(largestAllowed))
        let message = CarrierV2Message.envelope(.text(CarrierPayload(text: largestAllowed), sender: CarrierDeviceIdentity(displayName: String(repeating: "名", count: 60), deviceID: UUID().uuidString)))
        XCTAssertLessThan(try message.encoded().count + 16, NoiseCipherState.maxMessageLength)
    }

    func testIndicatorStaysHiddenUntilNearTheLimit() {
        XCTAssertEqual(CarrierTextLengthIndicator(text: String(repeating: "a", count: 8_999)), .hidden)
        XCTAssertEqual(CarrierTextLengthIndicator(text: String(repeating: "a", count: 9_000)), .nearLimit(count: 9_000, limit: 9_999))
        XCTAssertEqual(CarrierTextLengthIndicator(text: String(repeating: "a", count: 9_000)).displayText, "9000/9999")
        XCTAssertEqual(CarrierTextLengthIndicator(text: String(repeating: "a", count: 10_000)), .overLimit(count: 10_000, limit: 9_999))
        // 3,500 Chinese characters are over 9,000 UTF-8 bytes but far from the character limit.
        XCTAssertEqual(CarrierTextLengthIndicator(text: String(repeating: "字", count: 3_500)), .hidden)
    }
}
