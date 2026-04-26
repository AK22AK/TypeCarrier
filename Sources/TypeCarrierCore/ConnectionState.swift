import Foundation

public enum ConnectionState: Equatable, Sendable {
    case idle
    case searching
    case advertising
    case connecting(String)
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
        case .connected(let peerName):
            "Connected to \(peerName)"
        case .failed(let message):
            message
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
}
