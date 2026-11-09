import Foundation
import XCTest
@testable import TypeCarrierCore

final class CarrierDiagnosticExportTests: XCTestCase {
    func testCreatesTimestampedCopyForDiagnosticLogExport() throws {
        let sourceURL = try temporaryFileURL(fileName: "ios-connection-events.jsonl")
        let exportDirectory = try temporaryDirectoryURL()
        let contents = """
        {"name":"service.start","timestamp":"2026-04-30T10:09:12Z"}
        {"name":"browser.start","timestamp":"2026-04-30T10:09:12Z"}

        """
        try contents.write(to: sourceURL, atomically: true, encoding: .utf8)

        let exportURL = try CarrierDiagnosticExport.createTimestampedCopy(
            sourceURL: sourceURL,
            directory: exportDirectory,
            prefix: "ios-connection-events",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-04-30T10:09:12Z")),
            timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!
        )

        XCTAssertEqual(exportURL.lastPathComponent, "ios-connection-events-20260430-180912.jsonl")
        XCTAssertEqual(try String(contentsOf: exportURL, encoding: .utf8), contents)
    }

    func testReadsRecentDiagnosticLogEntriesNewestFirst() throws {
        let sourceURL = try temporaryFileURL(fileName: "mac-connection-events.jsonl")
        let store = try CarrierDiagnosticLogStore(fileURL: sourceURL)
        let diagnostics = CarrierDiagnostics(
            role: "receiver",
            localPeerName: "Mac",
            serviceType: "typecarrier"
        )

        try store.append(
            event: CarrierDiagnosticEvent(
                timestamp: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-03T09:00:00Z")),
                name: "service.start",
                message: "Starting receiver",
                peerName: nil,
                connectionState: .advertising,
                connectedPeers: []
            ),
            diagnostics: diagnostics
        )
        try store.append(
            event: CarrierDiagnosticEvent(
                timestamp: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-03T09:01:00Z")),
                name: "advertiser.start",
                message: "Advertising typecarrier",
                peerName: nil,
                connectionState: .advertising,
                connectedPeers: []
            ),
            diagnostics: diagnostics
        )
        try store.append(
            event: CarrierDiagnosticEvent(
                timestamp: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-03T09:02:00Z")),
                name: "paste.command.posted",
                message: "已接收文本，已发送粘贴指令",
                peerName: "iPhone",
                connectionState: .connected("iPhone"),
                connectedPeers: ["iPhone"]
            ),
            diagnostics: diagnostics
        )

        let entries = try store.recentEntries(limit: 2)

        XCTAssertEqual(entries.map(\.name), ["paste.command.posted", "advertiser.start"])
    }

    func testDiagnosticLogKeepsMillisecondsAndReadsOlderWholeSecondEntries() throws {
        let sourceURL = try temporaryFileURL(fileName: "mac-connection-events.jsonl")
        try """
        {"connectedPeers":[],"connectionState":"Advertising","discoveredPeers":[],"invitedPeers":[],"localPeerName":"Mac","logSessionID":"E6D1F731-0A9A-4025-8DF0-8E49E95EE7D3","message":"Starting receiver","name":"service.start","role":"receiver","serviceType":"typecarrier","timestamp":"2026-06-03T09:00:00Z"}

        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        let store = try CarrierDiagnosticLogStore(fileURL: sourceURL)
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000.123)

        try store.append(
            event: CarrierDiagnosticEvent(
                timestamp: timestamp,
                name: "session.connected",
                message: "Connected",
                peerName: "iPhone",
                connectionState: .connected("iPhone"),
                connectedPeers: ["iPhone"]
            ),
            diagnostics: CarrierDiagnostics(role: "receiver", localPeerName: "Mac", serviceType: "typecarrier")
        )

        XCTAssertNotNil(try String(contentsOf: sourceURL, encoding: .utf8).range(of: #"T\d{2}:\d{2}:\d{2}\.\d{3}Z"#, options: .regularExpression))
        let entries = try store.recentEntries(limit: 2)
        XCTAssertEqual(entries.map(\.name), ["session.connected", "service.start"])
        XCTAssertEqual(try XCTUnwrap(entries.first).timestamp.timeIntervalSince1970, 1_780_000_000.123, accuracy: 0.001)
    }

    func testTailLinesReadsOnlyTheEndAcrossChunkBoundaries() throws {
        let url = try temporaryFileURL(fileName: "tail.jsonl")
        let lines = (1...500).map { "line-\($0)-" + String(repeating: "x", count: $0 % 37) }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)

        for chunkSize in [7, 64, 1_000, 1_000_000] {
            let tail = CarrierDiagnosticLogStore.tailLines(of: url, count: 3, chunkSize: chunkSize)
            XCTAssertEqual(tail.map { String(decoding: $0, as: UTF8.self) }, Array(lines.suffix(3)), "chunk \(chunkSize)")
        }
        XCTAssertEqual(CarrierDiagnosticLogStore.tailLines(of: url, count: 900, chunkSize: 100).count, 500)
    }

    func testDiagnosticLogRotatesPastTheSizeLimit() throws {
        let url = try temporaryFileURL(fileName: "rotate.jsonl")
        let filler = String(repeating: "a", count: Int(CarrierDiagnosticLogStore.maximumFileSize))
        try filler.write(to: url, atomically: true, encoding: .utf8)
        let store = try CarrierDiagnosticLogStore(fileURL: url)
        let event = CarrierDiagnosticEvent(name: "session.connected", message: "Connected", peerName: nil, connectionState: .idle, connectedPeers: [])
        let diagnostics = CarrierDiagnostics(role: "receiver", localPeerName: "Mac", serviceType: "typecarrier")

        try store.append(event: event, diagnostics: diagnostics)
        XCTAssertTrue(FileManager.default.fileExists(atPath: CarrierDiagnosticLogStore.rotatedFileURL(for: url).path))
        XCTAssertEqual(try Data(contentsOf: url).count, 0)

        try store.append(event: event, diagnostics: diagnostics)
        XCTAssertEqual(try store.recentEntries(limit: 5).map(\.name), ["session.connected"])
    }

    func testDiagnosticLogEntryCompactSummaryIncludesRouteAndConnectionState() throws {
        let entry = CarrierDiagnosticLogEntry(
            logSessionID: UUID(uuidString: "E6D1F731-0A9A-4025-8DF0-8E49E95EE7D3")!,
            timestamp: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-03T09:02:00Z")),
            role: "receiver.android",
            localPeerName: "MacBook Pro",
            serviceType: "typecarrier",
            name: "androidBridge.connection.ready",
            message: "Android bridge TCP connection is ready.",
            peerName: "Pixel",
            connectionState: "Connected to Pixel",
            discoveredPeers: ["Pixel"],
            invitedPeers: [],
            connectedPeers: ["Pixel"],
            lastErrorMessage: nil
        )

        XCTAssertEqual(
            entry.compactDiagnosticSummary,
            "receiver.android · peer=Pixel · state=Connected to Pixel · connected=Pixel"
        )
    }

    private func temporaryFileURL(fileName: String) throws -> URL {
        let directoryURL = try temporaryDirectoryURL()
        return directoryURL.appendingPathComponent(fileName)
    }

    private func temporaryDirectoryURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
