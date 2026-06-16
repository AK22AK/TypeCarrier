import Foundation

public struct AndroidBridgeHandshake: Codable, Equatable, Sendable {
    public let version: Int
    public let deviceID: String
    public let deviceName: String
    public let pairingCode: String?
    public let tokenProof: String?
    public let challenge: String?

    public init(
        version: Int = 1,
        deviceID: String,
        deviceName: String,
        pairingCode: String?,
        tokenProof: String? = nil,
        challenge: String? = nil
    ) {
        self.version = version
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        self.tokenProof = tokenProof
        self.challenge = challenge
    }

    public var isPairingAttempt: Bool {
        pairingCode != nil && tokenProof == nil
    }

    public var isTokenAttempt: Bool {
        tokenProof != nil && pairingCode == nil
    }
}

public struct AndroidBridgeResponse: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case accepted
        case busy
        case invalidPairing
        case rejected
    }

    public let status: Status
    public let message: String
    public let trustToken: String?
    public let macID: String?
    public let macName: String?

    public init(status: Status, message: String, trustToken: String? = nil, macID: String? = nil, macName: String? = nil) {
        self.status = status
        self.message = message
        self.trustToken = trustToken
        self.macID = macID
        self.macName = macName
    }

    public static func busy(_ message: String) -> AndroidBridgeResponse {
        AndroidBridgeResponse(status: .busy, message: message)
    }
}

public struct AndroidPairingAssociationRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let macID: String
    public let macName: String
    public let pairingCode: String

    public init(version: Int = 1, macID: String, macName: String, pairingCode: String) {
        self.version = version
        self.macID = macID
        self.macName = macName
        self.pairingCode = pairingCode
    }
}

public struct AndroidPairingAssociationResponse: Codable, Equatable, Sendable {
    public let status: AndroidBridgeResponse.Status
    public let message: String
    public let deviceID: String?
    public let deviceName: String?
    public let trustToken: String?

    public init(
        status: AndroidBridgeResponse.Status,
        message: String,
        deviceID: String? = nil,
        deviceName: String? = nil,
        trustToken: String? = nil
    ) {
        self.status = status
        self.message = message
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.trustToken = trustToken
    }
}

public struct AndroidBridgeActiveSenderGate: Equatable, Sendable {
    public private(set) var activeDeviceID: String?

    public init(activeDeviceID: String? = nil) {
        self.activeDeviceID = activeDeviceID
    }

    @discardableResult
    public mutating func claim(deviceID: String) -> Bool {
        guard let activeDeviceID else {
            self.activeDeviceID = deviceID
            return true
        }

        return activeDeviceID == deviceID
    }

    public mutating func release(deviceID: String) {
        guard activeDeviceID == deviceID else {
            return
        }

        activeDeviceID = nil
    }
}

public struct AndroidBridgeListenerRecovery: Equatable, Sendable {
    private let maximumConsecutiveFailures: Int
    private let retryDelay: Duration
    private var consecutiveFailures = 0

    public init(maximumConsecutiveFailures: Int = 3, retryDelay: Duration = .seconds(2)) {
        self.maximumConsecutiveFailures = max(1, maximumConsecutiveFailures)
        self.retryDelay = retryDelay
    }

    public mutating func failed() -> Duration? {
        consecutiveFailures += 1
        return retryDelay.takeIf(consecutiveFailures <= maximumConsecutiveFailures)
    }

    public mutating func ready() {
        consecutiveFailures = 0
    }

    public mutating func stopped() {
        consecutiveFailures = 0
    }
}

private extension Duration {
    func takeIf(_ condition: Bool) -> Duration? {
        condition ? self : nil
    }
}
