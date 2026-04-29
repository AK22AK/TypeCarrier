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

    func testBlankTextIsRejectedBeforeSending() {
        XCTAssertFalse(CarrierPayload.canSend(""))
        XCTAssertFalse(CarrierPayload.canSend(" \n\t "))
        XCTAssertTrue(CarrierPayload.canSend(" dictated text "))
    }
}
