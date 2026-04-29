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
            detail: nil
        )

        try store.upsert(record)

        let reloaded = try CarrierRecordStore(fileURL: url, limit: 200)
        XCTAssertEqual(reloaded.records, [record])
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
        updated.status = .pastePosted
        updated.detail = "Pasted 9 characters"
        updated.updatedAt = baseDate.addingTimeInterval(10)
        try store.upsert(updated)

        XCTAssertEqual(store.records[0].id, updated.id)
        XCTAssertEqual(store.records[0].status, .pastePosted)
        XCTAssertEqual(store.records[0].detail, "Pasted 9 characters")

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
}
