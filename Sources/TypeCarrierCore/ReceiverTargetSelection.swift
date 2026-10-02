import Foundation

/// Selects from receivers ordered by their current connection's success time.
/// Selection changes affect future sends; callers retain each in-flight target separately.
public struct ReceiverTargetSelection: Equatable, Sendable {
    public private(set) var selectedID: String?

    public init() {}

    public mutating func reconcile(connected: [CarrierPeer]) {
        guard target(in: connected) == nil else { return }
        selectedID = connected.first { $0.role == .receiver }?.id
    }

    public mutating func select(_ peer: CarrierPeer) {
        guard peer.role == .receiver else { return }
        selectedID = peer.id
    }

    public func target(in connected: [CarrierPeer]) -> CarrierPeer? {
        connected.first { $0.id == selectedID && $0.role == .receiver }
    }
}
