import XCTest
@testable import TypeCarrierCore

final class ConnectionStateTests: XCTestCase {
    func testConnectionStateDisplayTextIsStableForUI() {
        XCTAssertEqual(ConnectionState.idle.displayText, "Idle")
        XCTAssertEqual(ConnectionState.searching.displayText, "Searching")
        XCTAssertEqual(ConnectionState.advertising.displayText, "Advertising")
        XCTAssertEqual(ConnectionState.connecting("MacBook Pro").displayText, "Connecting to MacBook Pro")
        XCTAssertEqual(ConnectionState.reconnecting("MacBook Pro").displayText, "Reconnecting to MacBook Pro")
        XCTAssertEqual(ConnectionState.connected("MacBook Pro").displayText, "Connected to MacBook Pro")
        XCTAssertEqual(ConnectionState.failed("No peer").displayText, "No peer")
    }

    func testConnectionStateSemanticFlags() {
        XCTAssertTrue(ConnectionState.connected("Mac").isConnected)
        XCTAssertFalse(ConnectionState.searching.isConnected)
        XCTAssertTrue(ConnectionState.failed("Denied").isFailed)
        XCTAssertFalse(ConnectionState.advertising.isFailed)
    }

    func testPeerNameIsAvailableOnlyAfterFindingADevice() {
        XCTAssertNil(ConnectionState.idle.peerName)
        XCTAssertNil(ConnectionState.searching.peerName)
        XCTAssertEqual(ConnectionState.connecting("MacBook Pro").peerName, "MacBook Pro")
        XCTAssertEqual(ConnectionState.reconnecting("MacBook Pro").peerName, "MacBook Pro")
        XCTAssertEqual(ConnectionState.connected("MacBook Pro").peerName, "MacBook Pro")
    }

    func testSenderFailureSuggestionExplainsMacReceiverRestartWhenPeerWasFound() {
        let diagnostics = CarrierDiagnostics(
            role: "sender",
            localPeerName: "iPhone",
            serviceType: "typecarrier",
            connectionState: .failed("Could not connect to MacBook Pro."),
            discoveredPeers: ["MacBook Pro"],
            lastErrorMessage: "Could not connect to MacBook Pro."
        )

        XCTAssertEqual(
            diagnostics.connectionRecoverySuggestion,
            "MacBook Pro was found, but the connection did not complete. Try opening TypeCarrier on the Mac, choosing Restart Receiver, then retry here."
        )
    }

    func testSenderFailureSuggestionIsHiddenBeforeDiscovery() {
        let diagnostics = CarrierDiagnostics(
            role: "sender",
            localPeerName: "iPhone",
            serviceType: "typecarrier",
            connectionState: .failed("No nearby Mac found."),
            lastErrorMessage: "No nearby Mac found."
        )

        XCTAssertNil(diagnostics.connectionRecoverySuggestion)
    }
}
