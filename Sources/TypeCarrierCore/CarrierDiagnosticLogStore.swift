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
}

public final class CarrierDiagnosticLogStore {
    public let fileURL: URL

    private let logSessionID = UUID()
    private let encoder: JSONEncoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
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
}
