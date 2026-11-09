import Foundation

public struct CarrierDiagnosticEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let name: String
    public let message: String
    public let peerName: String?
    public let connectionState: ConnectionState
    public let connectedPeers: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String,
        message: String,
        peerName: String?,
        connectionState: ConnectionState,
        connectedPeers: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.message = message
        self.peerName = peerName
        self.connectionState = connectionState
        self.connectedPeers = connectedPeers
    }
}

public struct CarrierDiagnostics: Equatable, Sendable {
    public let role: String
    public let localPeerName: String
    public let serviceType: String
    public var connectionState: ConnectionState
    public var discoveredPeers: [String]
    public var invitedPeers: [String]
    public var connectedPeers: [String]
    public var lastErrorMessage: String?
    public var events: [CarrierDiagnosticEvent]

    public init(
        role: String,
        localPeerName: String,
        serviceType: String,
        connectionState: ConnectionState = .idle,
        discoveredPeers: [String] = [],
        invitedPeers: [String] = [],
        connectedPeers: [String] = [],
        lastErrorMessage: String? = nil,
        events: [CarrierDiagnosticEvent] = []
    ) {
        self.role = role
        self.localPeerName = localPeerName
        self.serviceType = serviceType
        self.connectionState = connectionState
        self.discoveredPeers = discoveredPeers
        self.invitedPeers = invitedPeers
        self.connectedPeers = connectedPeers
        self.lastErrorMessage = lastErrorMessage
        self.events = events
    }

    var emptyPlaceholder: String {
        "None"
    }

    public var discoveredPeersText: String {
        discoveredPeers.isEmpty ? emptyPlaceholder : discoveredPeers.joined(separator: ", ")
    }

    public var invitedPeersText: String {
        invitedPeers.isEmpty ? emptyPlaceholder : invitedPeers.joined(separator: ", ")
    }

    public var connectedPeersText: String {
        connectedPeers.isEmpty ? emptyPlaceholder : connectedPeers.joined(separator: ", ")
    }

    public var connectionRecoverySuggestion: String? {
        guard role == "sender",
              connectionState.isFailed else {
            return nil
        }

        let latestFailureEvent = events.last { $0.connectionState.isFailed }
        if latestFailureEvent?.name == "browser.foundBusyPeer" {
            return "Disconnect the other iPhone or simulator from this Mac, then retry here."
        }

        return nil
    }
}

public enum CarrierServiceError: LocalizedError, Equatable, Sendable {
    case blankText
    case noConnectedPeer
    case targetRequired
    case textTooLong

    public var errorDescription: String? {
        switch self {
        case .blankText:
            "文本为空。"
        case .noConnectedPeer:
            "没有已连接设备。"
        case .targetRequired:
            "请选择发送目标。"
        case .textTooLong:
            "文本太长，请删减后再发送。"
        }
    }
}
