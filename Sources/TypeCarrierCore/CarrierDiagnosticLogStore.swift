import Foundation

public struct CarrierDiagnosticLogEntry: Codable, Equatable, Sendable {
    public let logSessionID: UUID
    public let timestamp: Date
    public let role: String
    public let localPeerName: String
    public let serviceType: String
    public let name: String
    public let message: String
    public let peerName: String?
    public let connectionState: String
    public let discoveredPeers: [String]
    public let invitedPeers: [String]
    public let connectedPeers: [String]
    public let lastErrorMessage: String?

    public var compactDiagnosticSummary: String {
        var parts = [role]
        if let peerName, !peerName.isEmpty {
            parts.append("peer=\(peerName)")
        }
        parts.append("state=\(connectionState)")
        if !connectedPeers.isEmpty {
            parts.append("connected=\(connectedPeers.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}

public final class CarrierDiagnosticLogStore {
    public let fileURL: URL

    private let logSessionID = UUID()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = Self.timestampEncodingStrategy
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.decoder = Self.makeDecoder()

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    // Millisecond timestamps let connection soak runs measure sub-second connects;
    // entries written before this change have whole seconds and still decode.
    private static let millisecondTimestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let timestampEncodingStrategy = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(date.formatted(CarrierDiagnosticLogStore.millisecondTimestampStyle))
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: millisecondTimestampStyle) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 timestamp: \(text)")
        }
        return decoder
    }

    public static func defaultFileURL(fileName: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TypeCarrier", isDirectory: true)
        .appendingPathComponent("ConnectionDiagnostics", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    public func append(event: CarrierDiagnosticEvent, diagnostics: CarrierDiagnostics) throws {
        let entry = CarrierDiagnosticLogEntry(
            logSessionID: logSessionID,
            timestamp: event.timestamp,
            role: diagnostics.role,
            localPeerName: diagnostics.localPeerName,
            serviceType: diagnostics.serviceType,
            name: event.name,
            message: event.message,
            peerName: event.peerName,
            connectionState: event.connectionState.displayText,
            discoveredPeers: diagnostics.discoveredPeers,
            invitedPeers: diagnostics.invitedPeers,
            connectedPeers: event.connectedPeers,
            lastErrorMessage: diagnostics.lastErrorMessage
        )
        let data = try encoder.encode(entry) + Data([0x0A])

        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }
        let size = try handle.seekToEnd()
        try handle.write(contentsOf: data)
        if size + UInt64(data.count) > Self.maximumFileSize {
            try? handle.close()
            try Self.rotate(fileURL)
        }
    }

    /// Past this size the log moves to `<name>.1` (replacing the previous one) and starts fresh,
    /// so reading and exporting it stays cheap however long the app runs.
    public static let maximumFileSize: UInt64 = 5_000_000

    public static func rotatedFileURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("1")
    }

    private static func rotate(_ fileURL: URL) throws {
        let manager = FileManager.default
        let rotatedURL = rotatedFileURL(for: fileURL)
        try? manager.removeItem(at: rotatedURL)
        try manager.moveItem(at: fileURL, to: rotatedURL)
        _ = manager.createFile(atPath: fileURL.path, contents: nil)
    }

    public func recentEntries(limit: Int) throws -> [CarrierDiagnosticLogEntry] {
        try Self.recentEntries(fileURL: fileURL, limit: limit, decoder: decoder)
    }

    public static func recentEntries(fileURL: URL, limit: Int) throws -> [CarrierDiagnosticLogEntry] {
        try recentEntries(fileURL: fileURL, limit: limit, decoder: makeDecoder())
    }

    private static func recentEntries(
        fileURL: URL,
        limit: Int,
        decoder: JSONDecoder
    ) throws -> [CarrierDiagnosticLogEntry] {
        guard limit > 0 else {
            return []
        }

        return tailLines(of: fileURL, count: limit)
            .reversed()
            .compactMap { try? decoder.decode(CarrierDiagnosticLogEntry.self, from: $0) }
    }
}

extension CarrierDiagnosticLogStore {
    /// The last `count` lines, read backwards from the end in chunks instead of loading the whole file.
    static func tailLines(of fileURL: URL, count: Int, chunkSize: Int = 64 * 1024) -> [Data] {
        guard count > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return [] }

        var buffer = Data()
        var offset = fileSize
        // One more newline than lines wanted guarantees the oldest kept line is complete.
        while offset > 0, buffer.reduce(0, { $1 == 0x0A ? $0 + 1 : $0 }) <= count {
            let readSize = UInt64(min(UInt64(chunkSize), offset))
            offset -= readSize
            try? handle.seek(toOffset: offset)
            guard let chunk = try? handle.read(upToCount: Int(readSize)) else { break }
            buffer = chunk + buffer
        }
        let lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: true)
        let complete = offset == 0 ? lines[...] : lines.dropFirst()
        return complete.suffix(count).map { Data($0) }
    }
}
