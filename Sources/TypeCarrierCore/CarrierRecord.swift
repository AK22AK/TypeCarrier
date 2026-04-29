import Foundation

public struct CarrierRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case draft
        case outgoing
        case incoming
    }

    public enum Status: String, Codable, Sendable {
        case draft
        case queued
        case sent
        case received
        case pastePosted
        case pasteFailed
        case failed
    }

    public let id: UUID
    public let payloadID: UUID?
    public let kind: Kind
    public var status: Status
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date
    public var detail: String?

    public init(
        id: UUID = UUID(),
        payloadID: UUID? = nil,
        kind: Kind,
        status: Status,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        detail: String? = nil
    ) {
        self.id = id
        self.payloadID = payloadID
        self.kind = kind
        self.status = status
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.detail = detail
    }
}
