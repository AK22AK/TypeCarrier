import Foundation

public final class CarrierRecordStore {
    public private(set) var records: [CarrierRecord]

    private let fileURL: URL
    private let limit: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, limit: Int = 200) throws {
        self.fileURL = fileURL
        self.limit = limit

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            records = try decoder.decode([CarrierRecord].self, from: data)
                .sorted(by: Self.newestFirst)
        } else {
            records = []
        }

        prune()
    }

    public static func defaultFileURL(fileName: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TypeCarrier", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    public func upsert(_ record: CarrierRecord) throws {
        var candidate = records
        if let index = candidate.firstIndex(where: { $0.id == record.id }) {
            candidate[index] = record
        } else {
            candidate.append(record)
        }

        candidate.sort(by: Self.newestFirst)
        if candidate.count > limit { candidate = Array(candidate.prefix(limit)) }
        try save(candidate)
        records = candidate
    }

    public func delete(id: UUID) throws {
        let candidate = records.filter { $0.id != id }
        try save(candidate)
        records = candidate
    }

    public func record(matchingPayloadID payloadID: UUID) -> CarrierRecord? {
        records.first { $0.payloadID == payloadID }
    }

    private func prune() {
        guard records.count > limit else {
            return
        }

        records = Array(records.prefix(limit))
    }

    private func save(_ records: [CarrierRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func newestFirst(_ lhs: CarrierRecord, _ rhs: CarrierRecord) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.updatedAt > rhs.updatedAt
    }
}
