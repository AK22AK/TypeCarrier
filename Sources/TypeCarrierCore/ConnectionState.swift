import Foundation

public enum ConnectionState: Equatable, Sendable {
    case idle
    case searching
    case advertising
    case connecting(String)
    case reconnecting(String)
    case connected(String)
    case failed(String)

    public var displayText: String {
        switch self {
        case .idle:
            "Idle"
        case .searching:
            "Searching"
        case .advertising:
            "Advertising"
        case .connecting(let peerName):
            "Connecting to \(peerName)"
        case .reconnecting(let peerName):
            "Reconnecting to \(peerName)"
        case .connected(let peerName):
            "Connected to \(peerName)"
        case .failed(let message):
            message
        }
    }

    public var peerName: String? {
        switch self {
        case .connecting(let peerName), .reconnecting(let peerName), .connected(let peerName):
            peerName
        default:
            nil
        }
    }

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    public var isManualRestartEligible: Bool {
        switch self {
        case .idle, .searching, .connecting, .reconnecting, .failed:
            true
        case .advertising, .connected:
            false
        }
    }

    var isWaitingToRetryKnownPeer: Bool {
        switch self {
        case .searching, .reconnecting:
            true
        default:
            false
        }
    }

    var isSearchTimeoutEligible: Bool {
        switch self {
        case .searching, .reconnecting:
            true
        default:
            false
        }
    }
}

public enum ReceiverDevicePlatform: Equatable, Sendable {
    case apple
    case android
}

public struct ReceiverConnectedDevice: Equatable, Sendable {
    public let name: String
    public let platform: ReceiverDevicePlatform

    public init(name: String, platform: ReceiverDevicePlatform) {
        self.name = name
        self.platform = platform
    }
}

public enum ReceiverOverallHealth: Equatable, Sendable {
    case ok
    case degraded
    case actionRequired
}

public enum ReceiverIssueSeverity: Equatable, Sendable {
    case warning
    case actionRequired
}

public enum ReceiverIssueImpact: Equatable, Sendable {
    /// Something every device depends on, such as record storage.
    case allDevices
    /// The receiver's network entry, which every paired device connects through.
    case receiver
}

public enum ReceiverIssueAction: Equatable, Sendable {
    case restartReceiver
}

public struct ReceiverStatusIssue: Equatable, Sendable {
    public let severity: ReceiverIssueSeverity
    public let impact: ReceiverIssueImpact
    public let message: String
    public let suggestedAction: ReceiverIssueAction?

    public init(
        severity: ReceiverIssueSeverity,
        impact: ReceiverIssueImpact,
        message: String,
        suggestedAction: ReceiverIssueAction? = nil
    ) {
        self.severity = severity
        self.impact = impact
        self.message = message
        self.suggestedAction = suggestedAction
    }
}

/// The receiver's state as the Mac UI presents it. iPhone and Android devices all connect through
/// the one protocol v2 receiver.
public struct ReceiverStatusSummary: Equatable, Sendable {
    public let overallHealth: ReceiverOverallHealth
    public let hasUsableEndpoint: Bool
    public let connectedDevices: [ReceiverConnectedDevice]
    public let issues: [ReceiverStatusIssue]

    public var requiresGlobalAttention: Bool {
        overallHealth == .actionRequired
    }

    public init(
        connectionState: ConnectionState,
        connectedDevices: [ReceiverConnectedDevice],
        sharedIssue: ReceiverStatusIssue? = nil
    ) {
        switch connectionState {
        case .advertising, .connected:
            hasUsableEndpoint = true
        case .idle, .searching, .connecting, .reconnecting, .failed:
            hasUsableEndpoint = false
        }
        self.connectedDevices = connectedDevices

        var collectedIssues: [ReceiverStatusIssue] = []
        if case .failed(let message) = connectionState {
            collectedIssues.append(ReceiverStatusIssue(
                severity: .actionRequired,
                impact: .receiver,
                message: message,
                suggestedAction: .restartReceiver
            ))
        }
        if let sharedIssue {
            collectedIssues.append(sharedIssue)
        }
        issues = collectedIssues

        if collectedIssues.contains(where: { $0.severity == .actionRequired }) || (!hasUsableEndpoint && !collectedIssues.isEmpty) {
            overallHealth = .actionRequired
        } else if collectedIssues.isEmpty {
            overallHealth = .ok
        } else {
            overallHealth = .degraded
        }
    }
}
