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
