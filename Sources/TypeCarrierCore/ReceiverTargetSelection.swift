import Foundation

/// Keeps an offline selection rather than silently redirecting a send.
public struct ReceiverTargetSelection: Equatable, Sendable {
    public private(set) var selectedID: String?
    public private(set) var lastSuccessfulID: String?
    public private(set) var selectedName: String?
    private var automaticallySelected = false

    public init(lastSuccessfulID: String? = nil, selectedName: String? = nil) {
        self.lastSuccessfulID = lastSuccessfulID
        selectedID = lastSuccessfulID
        self.selectedName = selectedName
    }

    public mutating func reconcile(connected: [CarrierPeer], availableCount: Int) {
        let availableCount = max(availableCount, connected.count)
        if automaticallySelected, lastSuccessfulID == nil, availableCount > 1 {
            selectedID = nil
            selectedName = nil
            automaticallySelected = false
        }
        if selectedID == nil, availableCount == 1, connected.count == 1 {
            select(connected[0])
            automaticallySelected = true
        }
        if let peer = target(in: connected) { selectedName = peer.displayName }
    }

    public mutating func select(_ peer: CarrierPeer) {
        selectedID = peer.id
        selectedName = peer.displayName
        automaticallySelected = false
    }

    public mutating func didConfirm(_ peer: CarrierPeer) {
        lastSuccessfulID = peer.id
    }

    public func target(in connected: [CarrierPeer]) -> CarrierPeer? {
        connected.first { $0.id == selectedID && $0.role == .receiver }
    }
}
