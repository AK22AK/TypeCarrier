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

    /// The most characters one send may carry. TypeCarrier relays dictated and typed text, not documents.
    public static let maximumCharacterCount = 9_999
    /// The character count appears only from here on, so it stays out of the way in normal use.
    public static let characterCountHintThreshold = 9_000
    /// Keeps one send inside a single encrypted v2 frame (65,535 bytes) with room for the envelope,
    /// even when the characters are long emoji sequences or JSON-escaped control characters.
    public static let maximumUTF8ByteCount = 48_000

    public static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isWithinLengthLimit(_ text: String) -> Bool {
        text.utf8.count <= maximumUTF8ByteCount && text.count <= maximumCharacterCount
    }

    public static func canSend(_ text: String) -> Bool {
        hasContent(text) && isWithinLengthLimit(text)
    }
}

/// What the editor shows about the text's length.
public enum CarrierTextLengthIndicator: Equatable, Sendable {
    case hidden
    case nearLimit(count: Int, limit: Int)
    case overLimit(count: Int, limit: Int)

    public init(text: String) {
        let limit = CarrierPayload.maximumCharacterCount
        // Cheap byte check first: below the threshold in UTF-8 bytes means below it in characters.
        guard text.utf8.count >= CarrierPayload.characterCountHintThreshold else {
            self = .hidden
            return
        }
        let count = text.count
        if !CarrierPayload.isWithinLengthLimit(text) {
            self = .overLimit(count: count, limit: limit)
        } else if count >= CarrierPayload.characterCountHintThreshold {
            self = .nearLimit(count: count, limit: limit)
        } else {
            self = .hidden
        }
    }

    public var displayText: String? {
        switch self {
        case .hidden: nil
        case .nearLimit(let count, let limit), .overLimit(let count, let limit): "\(count)/\(limit)"
        }
    }

    public var isOverLimit: Bool {
        if case .overLimit = self { return true }
        return false
    }
}
