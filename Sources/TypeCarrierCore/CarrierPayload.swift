import Foundation

public enum CarrierPostPasteAction: String, Codable, Equatable, Sendable {
    case pressReturn
}

public struct CarrierPayload: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let postPasteAction: CarrierPostPasteAction?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        postPasteAction: CarrierPostPasteAction? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.postPasteAction = postPasteAction
    }

    public static func canSend(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
