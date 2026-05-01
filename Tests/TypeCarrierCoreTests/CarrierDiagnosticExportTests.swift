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
