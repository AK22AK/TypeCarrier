import XCTest
@testable import TypeCarrierCore

final class ReceiverTargetSelectionTests: XCTestCase {
    private let a = CarrierPeer(id: "A", displayName: "Mac", role: .receiver)
    private let b = CarrierPeer(id: "B", displayName: "Mac", role: .receiver)

    func testSingletonAutoSelectsButMultipleWithoutHistoryRequireChoice() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [a], availableCount: 1)
        XCTAssertEqual(selection.target(in: [a]), a)
        selection.reconcile(connected: [a, b], availableCount: 2)
        XCTAssertNil(selection.selectedID)
        selection.select(b)
        selection.reconcile(connected: [a, b], availableCount: 2)
        XCTAssertEqual(selection.target(in: [a, b]), b)
    }

    func testOfflineSelectionStaysSelectedWithoutFallbackAndReconnects() {
        var selection = ReceiverTargetSelection(lastSuccessfulID: "A", selectedName: "Mac")
        selection.reconcile(connected: [b], availableCount: 1)
        XCTAssertEqual(selection.selectedID, "A")
        XCTAssertNil(selection.target(in: [b]))
        selection.reconcile(connected: [a, b], availableCount: 2)
        XCTAssertEqual(selection.target(in: [a, b]), a)
    }

    func testConnectedTargetsStillRequireChoiceAfterOneDisappearsFromDiscovery() {
        var selection = ReceiverTargetSelection()
        selection.reconcile(connected: [a], availableCount: 1)
        selection.reconcile(connected: [a, b], availableCount: 1)
        XCTAssertNil(selection.selectedID)
    }

    func testUserSelectionSwitchesNextTargetAndSuccessfulTargetIsRemembered() {
        var selection = ReceiverTargetSelection()
        XCTAssertNil(selection.target(in: []))
        selection.select(a)
        let capturedTarget = selection.target(in: [a, b])
        selection.select(b)
        XCTAssertEqual(capturedTarget, a)
        XCTAssertEqual(selection.target(in: [a, b]), b)
        selection.didConfirm(a)
        XCTAssertEqual(selection.lastSuccessfulID, "A")
        XCTAssertEqual(selection.selectedID, "B")
    }
}
