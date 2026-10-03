import Foundation

public enum SendHistoryRetention: Codable, Equatable, Sendable {
    public enum Count: Int, CaseIterable, Codable, Sendable {
        case hundred = 100
        case twoHundred = 200
        case fiveHundred = 500
        case thousand = 1000
    }

    public enum Age: Int, CaseIterable, Codable, Sendable {
        case week, month, halfYear, year

        public func cutoff(from now: Date, calendar: Calendar) -> Date {
            switch self {
            case .week:
                calendar.date(byAdding: .day, value: -7, to: now) ?? now
            case .month:
                calendar.date(byAdding: .month, value: -1, to: now) ?? now
            case .halfYear:
                calendar.date(byAdding: .month, value: -6, to: now) ?? now
            case .year:
                calendar.date(byAdding: .year, value: -1, to: now) ?? now
            }
        }
    }

    case count(Count)
    case age(Age)

    public static let `default`: SendHistoryRetention = .count(.twoHundred)
}

/// iOS draft and send-history storage. Other clients keep CarrierRecordStore semantics.
public final class ComposerRecordStore {
    public static let maximumDraftCount = 99
    public private(set) var drafts: [CarrierRecord]
    public private(set) var history: [CarrierRecord]
    public private(set) var retention: SendHistoryRetention

    private struct HistoryFile: Codable {
        var retention: SendHistoryRetention
        var records: [CarrierRecord]
    }

    private let draftsURL: URL
    private let historyURL: URL
    private let calendar: Calendar
    private let encoder: JSONEncoder
    private let writer: (Data, URL) throws -> Void

    public convenience init(directory: URL, now: Date = Date(), calendar: Calendar = .current) throws {
        try self.init(directory: directory, now: now, calendar: calendar) { data, url in
            try data.write(to: url, options: .atomic)
        }
    }

    init(
        directory: URL,
        now: Date,
        calendar: Calendar,
        writer: @escaping (Data, URL) throws -> Void
    ) throws {
        draftsURL = directory.appendingPathComponent("ios-drafts.json")
        historyURL = directory.appendingPathComponent("ios-send-history.json")
        self.calendar = calendar
        self.writer = writer
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        drafts = try Self.read([CarrierRecord].self, at: draftsURL, decoder: decoder) ?? []
        let savedHistory = try Self.read(HistoryFile.self, at: historyURL, decoder: decoder)
        history = savedHistory?.records ?? []
        retention = savedHistory?.retention ?? .default

        let legacyURL = directory.appendingPathComponent("ios-records.json")
        if let legacy = try Self.read([CarrierRecord].self, at: legacyURL, decoder: decoder) {
            // Decode every legacy record directly. Never pass through the old 200-record pruning initializer.
            drafts = Self.merge(existing: drafts, migrated: legacy.filter { $0.kind == .draft })
            history = Self.merge(existing: history, migrated: legacy.filter { $0.kind != .draft })
            // A partial migration remains retryable: preserve the legacy source until both writes succeed.
            try writer(encoder.encode(drafts), draftsURL)
            try writeHistory(history, retention: retention)
            try FileManager.default.removeItem(at: legacyURL)
        }
        drafts.sort(by: Self.newestFirst)
        history.sort(by: Self.newestFirst)
        try cleanHistory(now: now)
    }

    public var records: [CarrierRecord] {
        (drafts + history).sorted(by: Self.newestFirst)
    }

    public func upsert(_ record: CarrierRecord, now: Date = Date()) throws {
        if record.kind == .draft {
            var next = drafts
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else {
                guard next.count < Self.maximumDraftCount else { throw ComposerRecordStoreError.draftLimitReached }
                next.append(record)
            }
            next.sort(by: Self.newestFirst)
            try writer(encoder.encode(next), draftsURL)
            drafts = next
        } else {
            var next = history
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else {
                next.append(record)
            }
            next = retained(next, policy: retention, now: now)
            try writeHistory(next, retention: retention)
            history = next
        }
    }

    public func delete(id: UUID) throws {
        if drafts.contains(where: { $0.id == id }) {
            let next = drafts.filter { $0.id != id }
            try writer(encoder.encode(next), draftsURL)
            drafts = next
        } else {
            let next = history.filter { $0.id != id }
            try writeHistory(next, retention: retention)
            history = next
        }
    }

    public func clearDrafts() throws {
        try writer(encoder.encode([CarrierRecord]()), draftsURL)
        drafts = []
    }

    public func clearHistory() throws {
        try writeHistory([], retention: retention)
        history = []
    }

    public func setRetention(_ policy: SendHistoryRetention, now: Date = Date()) throws {
        let next = retained(history, policy: policy, now: now)
        // The setting and the resulting history are committed in the same atomic file write.
        try writeHistory(next, retention: policy)
        retention = policy
        history = next
    }

    public func cleanHistory(now: Date = Date()) throws {
        let next = retained(history, policy: retention, now: now)
        guard next != history else { return }
        try writeHistory(next, retention: retention)
        history = next
    }

    private func retained(_ records: [CarrierRecord], policy: SendHistoryRetention, now: Date) -> [CarrierRecord] {
        let sorted = records.sorted(by: Self.newestFirst)
        switch policy {
        case .count(let count):
            return Array(sorted.prefix(count.rawValue))
        case .age(let age):
            let cutoff = age.cutoff(from: now, calendar: calendar)
            return sorted.filter { $0.createdAt >= cutoff }
        }
    }

    private func writeHistory(_ records: [CarrierRecord], retention: SendHistoryRetention) throws {
        try writer(encoder.encode(HistoryFile(retention: retention, records: records)), historyURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, at url: URL, decoder: JSONDecoder) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private static func merge(existing: [CarrierRecord], migrated: [CarrierRecord]) -> [CarrierRecord] {
        let existingIDs = Set(existing.map(\.id))
        return (existing + migrated.filter { !existingIDs.contains($0.id) }).sorted(by: newestFirst)
    }

    private static func newestFirst(_ lhs: CarrierRecord, _ rhs: CarrierRecord) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.createdAt > rhs.createdAt : lhs.updatedAt > rhs.updatedAt
    }
}

public enum ComposerRecordStoreError: Error {
    case draftLimitReached
}
