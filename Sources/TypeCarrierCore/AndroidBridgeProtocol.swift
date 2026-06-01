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

    public init(status: Status, message: String, trustToken: String? = nil) {
        self.status = status
        self.message = message
        self.trustToken = trustToken
    }

    public static func busy(_ message: String) -> AndroidBridgeResponse {
        AndroidBridgeResponse(status: .busy, message: message)
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
