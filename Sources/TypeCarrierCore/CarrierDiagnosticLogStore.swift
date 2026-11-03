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
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
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

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .suffix(limit)
            .reversed()
            .compactMap { line in
                guard let data = line.data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(CarrierDiagnosticLogEntry.self, from: data)
            }
    }
}
