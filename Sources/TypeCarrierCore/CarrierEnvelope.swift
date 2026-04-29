import Foundation

public struct CarrierEnvelope: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case ack
        case receipt
        case error
    }

    public let version: Int
    public let kind: Kind
    public let payload: CarrierPayload?
    public let ackID: UUID?
    public let receipt: CarrierDeliveryReceipt?
    public let message: String?

    public init(
        version: Int = 1,
        kind: Kind,
        payload: CarrierPayload? = nil,
        ackID: UUID? = nil,
        receipt: CarrierDeliveryReceipt? = nil,
        message: String? = nil
    ) {
        self.version = version
        self.kind = kind
        self.payload = payload
        self.ackID = ackID
        self.receipt = receipt
        self.message = message
    }

    public static func text(_ payload: CarrierPayload) -> CarrierEnvelope {
        CarrierEnvelope(kind: .text, payload: payload)
    }

    public static func ack(_ id: UUID) -> CarrierEnvelope {
        CarrierEnvelope(kind: .ack, ackID: id)
    }

    public static func receipt(_ receipt: CarrierDeliveryReceipt) -> CarrierEnvelope {
        CarrierEnvelope(kind: .receipt, receipt: receipt)
    }

    public static func error(_ message: String) -> CarrierEnvelope {
        CarrierEnvelope(kind: .error, message: message)
    }
}

public enum CarrierCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode(_ envelope: CarrierEnvelope) throws -> Data {
        try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> CarrierEnvelope {
        try decoder.decode(CarrierEnvelope.self, from: data)
    }
}
