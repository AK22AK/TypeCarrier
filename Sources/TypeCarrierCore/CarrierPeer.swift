import Foundation
import MultipeerConnectivity

public struct CarrierPeer: Identifiable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case sender, receiver, unknown }
    public let id: String
    public let displayName: String
    public let role: Role

    public init(id: String, displayName: String, role: Role = .unknown) {
        self.id = id
        self.displayName = displayName
        self.role = role
    }

    init(peerID: MCPeerID) {
        id = "legacy=\(peerID.hash)"
        displayName = peerID.displayName
        role = .unknown
    }
}
