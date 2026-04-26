import Foundation
import MultipeerConnectivity

public struct CarrierPeer: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    init(peerID: MCPeerID) {
        id = peerID.displayName
        displayName = peerID.displayName
    }
}
