import Foundation

public enum CarrierDiagnosticExport {
    public static func createTimestampedCopy(
        sourceURL: URL,
        directory: URL,
        prefix: String,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent(
            "\(prefix)-\(timestampString(for: now, timeZone: timeZone)).jsonl"
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    public static func defaultExportDirectory(fileManager: FileManager = .default) throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent("TypeCarrier", isDirectory: true)
            .appendingPathComponent("ConnectionDiagnostics", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    private static func timestampString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

public enum CarrierDiagnosticExportError: LocalizedError, Equatable, Sendable {
    case missingLogFile

    public var errorDescription: String? {
        switch self {
        case .missingLogFile:
            "Connection diagnostic log is unavailable."
        }
    }
}
