import XCTest
@testable import TypeCarrierCore

final class ComposerRecordStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMigrationReadsCompleteLegacyBeforeSeparatingAndNeverPrunesDrafts() throws {
        let directory = try temporaryDirectory()
        let drafts = (0..<140).map { record(.draft, index: $0, date: now.addingTimeInterval(-10_000)) }
        let history = (0..<300).map { record(.outgoing, index: $0, date: now.addingTimeInterval(Double($0))) }
        try writeLegacy(drafts + history, directory: directory)
        let store = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
        XCTAssertEqual(Set(store.drafts.map(\.id)), Set(drafts.map(\.id)))
        XCTAssertEqual(store.history.count, 200)
        XCTAssertEqual(Set(store.history.map(\.id)), Set(history.suffix(200).map(\.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ios-records.json").path))
        XCTAssertThrowsError(try store.upsert(record(.draft), now: now))
        var edited = drafts[0]
        edited.text = "editing an existing over-limit draft"
        try store.upsert(edited, now: now)
        let reloaded = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
        XCTAssertEqual(reloaded.drafts.count, 140)
        XCTAssertEqual(reloaded.drafts.first(where: { $0.id == edited.id })?.text, edited.text)
    }

    func testFailedPartialMigrationPreservesLegacyAndRetryIsIdempotent() throws {
        let directory = try temporaryDirectory()
        let records = [record(.draft), record(.outgoing)]
        let legacy = try writeLegacy(records, directory: directory)
        let source = try Data(contentsOf: legacy)
        XCTAssertThrowsError(try ComposerRecordStore(directory: directory, now: now, calendar: calendar) { data, url in
            if url.lastPathComponent == "ios-send-history.json" { throw TestError.writeFailed }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertEqual(try Data(contentsOf: legacy), source)
        let recovered = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
        XCTAssertEqual(Set(recovered.records.map(\.id)), Set(records.map(\.id)))
        let again = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
        XCTAssertEqual(again.records, recovered.records)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testMalformedLegacyIsNotRemovedOrOverwritten() throws {
        let directory = try temporaryDirectory()
        let legacy = directory.appendingPathComponent("ios-records.json")
        let source = Data("not json".utf8)
        try source.write(to: legacy)
        XCTAssertThrowsError(try ComposerRecordStore(directory: directory, now: now))
        XCTAssertEqual(try Data(contentsOf: legacy), source)
    }

    func testDraftLimitAndHistoryClearingAreIndependent() throws {
        let directory = try temporaryDirectory()
        let store = try ComposerRecordStore(directory: directory, now: now)
        for index in 0..<99 { try store.upsert(record(.draft, index: index), now: now) }
        XCTAssertThrowsError(try store.upsert(record(.draft), now: now))
        for index in 0..<220 { try store.upsert(record(.outgoing, index: index), now: now) }
        XCTAssertEqual(store.drafts.count, 99)
        XCTAssertEqual(store.history.count, 200)
        try store.clearHistory()
        XCTAssertEqual(store.drafts.count, 99)
        XCTAssertTrue(store.history.isEmpty)
        try store.upsert(record(.outgoing), now: now)
        try store.clearDrafts()
        XCTAssertEqual(store.history.count, 1)
        XCTAssertTrue(store.drafts.isEmpty)
    }

    func testEachCountOptionRetainsNewestHistoryAndPersistsSetting() throws {
        for count in SendHistoryRetention.Count.allCases {
            let directory = try temporaryDirectory()
            let store = try ComposerRecordStore(directory: directory, now: now)
            try store.setRetention(.count(count), now: now)
            let records = (0..<1100).map { record(.outgoing, index: $0, date: now.addingTimeInterval(Double($0))) }
            try writeLegacy(records, directory: directory)
            let migrated = try ComposerRecordStore(directory: directory, now: now)
            XCTAssertEqual(migrated.retention, .count(count))
            XCTAssertEqual(migrated.history.count, count.rawValue)
            XCTAssertEqual(Set(migrated.history.map(\.id)), Set(records.suffix(count.rawValue).map(\.id)))
        }
    }

    func testTimeOptionsUseCreationBoundaryAndHaveNoCountCap() throws {
        for age in SendHistoryRetention.Age.allCases {
            let directory = try temporaryDirectory()
            let cutoff = age.cutoff(from: now, calendar: calendar)
            let store = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
            try store.setRetention(.age(age), now: now)
            var expired = record(.outgoing, date: cutoff.addingTimeInterval(-1))
            expired.updatedAt = now // Editing must not extend a time-based retention period.
            let boundary = record(.outgoing, date: cutoff)
            let fresh = (0..<1100).map { record(.outgoing, index: $0, date: now) }
            let draft = record(.draft, date: cutoff.addingTimeInterval(-10_000))
            try writeLegacy([expired, boundary, draft] + fresh, directory: directory)
            let migrated = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
            XCTAssertEqual(migrated.retention, .age(age))
            XCTAssertEqual(migrated.history.count, 1101)
            XCTAssertTrue(migrated.history.contains(where: { $0.id == boundary.id }))
            XCTAssertFalse(migrated.history.contains(where: { $0.id == expired.id }))
            XCTAssertEqual(migrated.drafts, [draft])
            let reloaded = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
            XCTAssertEqual(reloaded.history.count, 1101)
            try reloaded.cleanHistory(now: now.addingTimeInterval(1))
            XCTAssertFalse(reloaded.history.contains(where: { $0.id == boundary.id }))
        }
    }

    func testCalendarMonthAndYearPeriodsAtMonthEnd() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        let expected: [(SendHistoryRetention.Age, DateComponents)] = [
            (.week, DateComponents(year: 2026, month: 10, day: 24, hour: 12)),
            (.month, DateComponents(year: 2026, month: 9, day: 30, hour: 12)),
            (.halfYear, DateComponents(year: 2026, month: 4, day: 30, hour: 12)),
            (.year, DateComponents(year: 2025, month: 10, day: 31, hour: 12))
        ]
        for (age, components) in expected {
            XCTAssertEqual(age.cutoff(from: anchor, calendar: calendar), calendar.date(from: components))
        }
    }

    func testFailedSettingAndWriteLeaveMemoryAndDiskUnchanged() throws {
        let directory = try temporaryDirectory()
        var fails = false
        let store = try ComposerRecordStore(directory: directory, now: now, calendar: calendar) { data, url in
            if fails { throw TestError.writeFailed }
            try data.write(to: url, options: .atomic)
        }
        let original = record(.outgoing, date: now.addingTimeInterval(-40 * 86400))
        try store.upsert(original, now: now)
        fails = true
        XCTAssertThrowsError(try store.setRetention(.age(.week), now: now))
        XCTAssertEqual(store.retention, .default)
        XCTAssertEqual(store.history, [original])
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertThrowsError(try store.upsert(record(.draft), now: now))
        XCTAssertTrue(store.drafts.isEmpty)
        let reloaded = try ComposerRecordStore(directory: directory, now: now)
        XCTAssertEqual(reloaded.history, [original])
        XCTAssertEqual(reloaded.retention, .default)
    }

    func testStartupAndHistoryWritesApplyRetention() throws {
        let directory = try temporaryDirectory()
        let store = try ComposerRecordStore(directory: directory, now: now, calendar: calendar)
        try store.setRetention(.age(.week), now: now)
        let old = record(.outgoing, date: now.addingTimeInterval(-6 * 86400))
        try store.upsert(old, now: now)
        try store.upsert(record(.outgoing, date: now), now: now.addingTimeInterval(2 * 86400))
        XCTAssertFalse(store.history.contains(where: { $0.id == old.id }))
        let reloaded = try ComposerRecordStore(directory: directory, now: now.addingTimeInterval(8 * 86400), calendar: calendar)
        XCTAssertTrue(reloaded.history.isEmpty)
    }

    private func record(_ kind: CarrierRecord.Kind, index: Int = 0, date: Date? = nil) -> CarrierRecord {
        let date = date ?? now
        return CarrierRecord(kind: kind, status: kind == .draft ? .draft : .sent, text: "text \(index)", createdAt: date, updatedAt: date)
    }

    @discardableResult
    private func writeLegacy(_ records: [CarrierRecord], directory: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("ios-records.json")
        try encoder.encode(records).write(to: url, options: .atomic)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private enum TestError: Error { case writeFailed }
}
