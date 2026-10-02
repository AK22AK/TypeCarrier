import XCTest
@testable import TypeCarrierCore

final class ReceiverTargetSelectionTests: XCTestCase {
    private let z = CarrierPeer(id: "Z", displayName: "Mac", role: .receiver)
    private let a = CarrierPeer(id: "A", displayName: "Mac", role: .receiver)
    private let b = CarrierPeer(id: "B", displayName: "Mac", role: .receiver)

    func testFirstConnectedWinsAndNewConnectionsDoNotStealSelection() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [z])
        XCTAssertEqual(selection.selectedID, z.id)
        selection.reconcile(connected: [z, a])
        XCTAssertEqual(selection.selectedID, z.id)
        selection.select(a)
        selection.reconcile(connected: [z, a, b])
        XCTAssertEqual(selection.selectedID, a.id)
    }

    func testDisconnectFallsBackToEarliestSurvivorAndReconnectDoesNotSteal() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [z, a, b])
        selection.select(b)
        selection.reconcile(connected: [z, a])
        XCTAssertEqual(selection.selectedID, z.id)
        selection.reconcile(connected: [a])
        XCTAssertEqual(selection.selectedID, a.id)
        selection.reconcile(connected: [a, b])
        XCTAssertEqual(selection.selectedID, a.id)
        selection.reconcile(connected: [a])
        XCTAssertEqual(selection.selectedID, a.id)
        selection.reconcile(connected: [])
        XCTAssertNil(selection.selectedID)
        selection.reconcile(connected: [z, a])
        XCTAssertEqual(selection.selectedID, z.id)
    }

    func testSelectionChangesDoNotMutateCapturedInFlightTarget() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [a, b])
        let capturedTarget = selection.target(in: [a, b])
        selection.select(b)
        selection.reconcile(connected: [b])
        XCTAssertEqual(capturedTarget, a)
        XCTAssertEqual(selection.target(in: [b]), b)
    }

    func testNewSessionDoesNotRestorePreviousSessionSelection() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [a, z])
        selection.select(a)
        selection = ReceiverTargetSelection()
        selection.reconcile(connected: [z, a])
        XCTAssertEqual(selection.selectedID, z.id)
    }

    func testOnlyReceiverCanBecomeTarget() {
        let sender = CarrierPeer(id: "sender", displayName: "Phone", role: .sender)
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [sender, z])
        selection.select(sender)
        XCTAssertEqual(selection.selectedID, z.id)
        selection.reconcile(connected: [sender])
        XCTAssertNil(selection.selectedID)
    }
}
