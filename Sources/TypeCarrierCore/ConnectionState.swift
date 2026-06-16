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

public enum ReceiverEndpoint: Equatable, Sendable {
    case appleMultipeer
    case androidBridge
}

public enum ReceiverDevicePlatform: Equatable, Sendable {
    case apple
    case android
}

public struct ReceiverConnectedDevice: Equatable, Sendable {
    public let name: String
    public let platform: ReceiverDevicePlatform
    public let endpoint: ReceiverEndpoint

    public init(name: String, platform: ReceiverDevicePlatform, endpoint: ReceiverEndpoint) {
        self.name = name
        self.platform = platform
        self.endpoint = endpoint
    }
}

public enum ReceiverEndpointConnectionState: Equatable, Sendable {
    case idle
    case listening
    case connected(String)
    case failed(String)

    var isUsable: Bool {
        switch self {
        case .listening, .connected:
            true
        case .idle, .failed:
            false
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
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
    case allDevices
    case endpoint(ReceiverEndpoint)
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

public struct ReceiverStatusSummary: Equatable, Sendable {
    public let overallHealth: ReceiverOverallHealth
    public let connectedDevices: [ReceiverConnectedDevice]
    public let issues: [ReceiverStatusIssue]

    public var requiresGlobalAttention: Bool {
        overallHealth == .actionRequired
    }

    public init(
        appleConnectionState: ConnectionState,
        appleConnectedDeviceNames: [String],
        androidConnectionState: ReceiverEndpointConnectionState,
        androidConnectedDeviceNames: [String],
        sharedIssue: ReceiverStatusIssue? = nil
    ) {
        connectedDevices = appleConnectedDeviceNames.map {
            ReceiverConnectedDevice(name: $0, platform: .apple, endpoint: .appleMultipeer)
        } + androidConnectedDeviceNames.map {
            ReceiverConnectedDevice(name: $0, platform: .android, endpoint: .androidBridge)
        }

        var collectedIssues: [ReceiverStatusIssue] = []
        if case .failed(let message) = appleConnectionState {
            collectedIssues.append(ReceiverStatusIssue(
                severity: .warning,
                impact: .endpoint(.appleMultipeer),
                message: message,
                suggestedAction: .restartReceiver
            ))
        }
        if let message = androidConnectionState.failureMessage {
            collectedIssues.append(ReceiverStatusIssue(
                severity: .warning,
                impact: .endpoint(.androidBridge),
                message: message,
                suggestedAction: .restartReceiver
            ))
        }
        if let sharedIssue {
            collectedIssues.append(sharedIssue)
        }
        issues = collectedIssues

        if collectedIssues.contains(where: { $0.impact == .allDevices && $0.severity == .actionRequired }) {
            overallHealth = .actionRequired
        } else if !Self.hasAnyUsableEndpoint(
            appleConnectionState: appleConnectionState,
            androidConnectionState: androidConnectionState
        ), !collectedIssues.isEmpty {
            overallHealth = .actionRequired
        } else if collectedIssues.isEmpty {
            overallHealth = .ok
        } else {
            overallHealth = .degraded
        }
    }

    private static func hasAnyUsableEndpoint(
        appleConnectionState: ConnectionState,
        androidConnectionState: ReceiverEndpointConnectionState
    ) -> Bool {
        switch appleConnectionState {
        case .advertising, .connected:
            return true
        case .idle, .searching, .connecting, .reconnecting, .failed:
            return androidConnectionState.isUsable
        }
    }
}
