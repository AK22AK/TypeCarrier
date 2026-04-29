import Foundation

public struct CarrierDeliveryReceipt: Codable, Equatable, Sendable {
    public enum PasteStatus: String, Codable, Sendable {
        case received
        case posted
        case failed
    }

    public let payloadID: UUID
    public let receivedAt: Date
    public let pasteStatus: PasteStatus
    public let detail: String?

    public init(
        payloadID: UUID,
        receivedAt: Date = Date(),
        pasteStatus: PasteStatus,
        detail: String? = nil
    ) {
        self.payloadID = payloadID
        self.receivedAt = receivedAt
        self.pasteStatus = pasteStatus
        self.detail = detail
    }
}
