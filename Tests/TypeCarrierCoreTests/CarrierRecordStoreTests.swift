import XCTest
@testable import TypeCarrierCore

final class CarrierRecordStoreTests: XCTestCase {
    func testStorePersistsAndReloadsRecords() throws {
        let url = try temporaryStoreURL()
        let store = try CarrierRecordStore(fileURL: url, limit: 200)
        let payloadID = UUID(uuidString: "15D6C0CC-F19A-4E6D-8589-69DE93C3C3B7")!
        let record = CarrierRecord(
            id: UUID(uuidString: "52346F5C-8F9C-4D2B-A79A-D5CF86244B90")!,
            payloadID: payloadID,
            kind: .outgoing,
            status: .queued,
            text: "important dictated text",
            createdAt: Date(timeIntervalSince1970: 1_777_777_001),
            updatedAt: Date(timeIntervalSince1970: 1_777_777_001),
            detail: nil,
            sourceDeviceName: "jzj iPhone"
        )

        try store.upsert(record)

        let reloaded = try CarrierRecordStore(fileURL: url, limit: 200)
        XCTAssertEqual(reloaded.records, [record])
        XCTAssertEqual(reloaded.records.first?.sourceDeviceName, "jzj iPhone")
    }

    func testStoreUpdatesDeletesAndPrunesNewestRecords() throws {
        let url = try temporaryStoreURL()
        let store = try CarrierRecordStore(fileURL: url, limit: 3)
        let baseDate = Date(timeIntervalSince1970: 1_777_777_100)

        for index in 0..<5 {
            try store.upsert(CarrierRecord(
                payloadID: UUID(),
                kind: .incoming,
                status: .received,
                text: "message \(index)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(index)),
                updatedAt: baseDate.addingTimeInterval(TimeInterval(index)),
                detail: nil
            ))
        }

        XCTAssertEqual(store.records.map(\.text), ["message 4", "message 3", "message 2"])

        var updated = store.records[1]
        updated.status = .pasteUnverified
        updated.detail = "Command-V posted, but target insertion could not be verified"
        updated.updatedAt = baseDate.addingTimeInterval(10)
        try store.upsert(updated)

        XCTAssertEqual(store.records[0].id, updated.id)
        XCTAssertEqual(store.records[0].status, .pasteUnverified)
        XCTAssertEqual(store.records[0].detail, "Command-V posted, but target insertion could not be verified")

        try store.delete(id: updated.id)

        XCTAssertFalse(store.records.contains { $0.id == updated.id })
        XCTAssertEqual(store.records.count, 2)
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("records.json")
    }

    func testFailedUpdateAndPruneDoNotLeakIntoLaterSave() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try CarrierRecordStore(fileURL: url, limit: 2)
        let first = fixtureRecord("original", time: 1_777_777_001)
        let second = fixtureRecord("second", time: 1_777_777_002)
        try store.upsert(first)
        try store.upsert(second)
        let originalRecords = store.records
        try withBlockedDestination(url) {
            var edited = first
            edited.text = "unsaved edit"
            edited.updatedAt = Date(timeIntervalSince1970: 1_777_777_010)
            XCTAssertThrowsError(try store.upsert(edited))
            XCTAssertEqual(store.records, originalRecords)
            XCTAssertThrowsError(try store.upsert(fixtureRecord("would prune", time: 1_777_777_020)))
            XCTAssertEqual(store.records, originalRecords)
        }
        try store.upsert(second)
        XCTAssertEqual(try CarrierRecordStore(fileURL: url).records, originalRecords)
    }

    func testFailedDeleteDoesNotLeakIntoLaterSave() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try CarrierRecordStore(fileURL: url)
        let original = fixtureRecord("keep after failed delete", time: 1_777_777_001)
        try store.upsert(original)
        try withBlockedDestination(url) {
            XCTAssertThrowsError(try store.delete(id: original.id))
            XCTAssertEqual(store.records, [original])
        }
        try store.upsert(fixtureRecord("later successful write", time: 1_777_777_002))
        XCTAssertTrue(try CarrierRecordStore(fileURL: url).records.contains(original))
    }

    private func fixtureRecord(_ text: String, time: TimeInterval) -> CarrierRecord {
        CarrierRecord(kind: .incoming, status: .received, text: text,
                      createdAt: Date(timeIntervalSince1970: time), updatedAt: Date(timeIntervalSince1970: time))
    }

    private func withBlockedDestination(_ url: URL, body: () throws -> Void) throws {
        let backup = url.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: url, to: backup)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(at: backup, to: url)
        }
        try body()
    }
}
