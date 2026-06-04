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

    func testSenderFailureSuggestionIsHiddenWhenPeerWasFoundWithoutConfirmedCause() {
        let diagnostics = CarrierDiagnostics(
            role: "sender",
            localPeerName: "iPhone",
            serviceType: "typecarrier",
            connectionState: .failed("Could not connect to MacBook Pro."),
            discoveredPeers: ["MacBook Pro"],
            lastErrorMessage: "Could not connect to MacBook Pro."
        )

        XCTAssertNil(diagnostics.connectionRecoverySuggestion)
    }

    func testSenderFailureSuggestionExplainsConfirmedBusyReceiver() {
        let diagnostics = CarrierDiagnostics(
            role: "sender",
            localPeerName: "iPhone",
            serviceType: "typecarrier",
            connectionState: .failed("MacBook Pro is already connected to another device."),
            discoveredPeers: ["MacBook Pro"],
            lastErrorMessage: "MacBook Pro is already connected to another device.",
            events: [
                CarrierDiagnosticEvent(
                    name: "browser.foundBusyPeer",
                    message: "Receiver advertised busy availability",
                    peerName: "MacBook Pro",
                    connectionState: .failed("MacBook Pro is already connected to another device."),
                    connectedPeers: []
                )
            ]
        )

        XCTAssertEqual(
            diagnostics.connectionRecoverySuggestion,
            "Disconnect the other iPhone or simulator from this Mac, then retry here."
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

    func testAndroidBridgeFailureIsDegradedWhenAppleReceiverIsConnected() {
        let summary = ReceiverStatusSummary(
            appleConnectionState: .connected("iPhone15Pro"),
            appleConnectedDeviceNames: ["iPhone15Pro"],
            androidConnectionState: .failed("Address already in use"),
            androidConnectedDeviceNames: []
        )

        XCTAssertEqual(summary.overallHealth, .degraded)
        XCTAssertFalse(summary.requiresGlobalAttention)
        XCTAssertEqual(
            summary.connectedDevices,
            [
                ReceiverConnectedDevice(
                    name: "iPhone15Pro",
                    platform: .apple,
                    endpoint: .appleMultipeer
                )
            ]
        )
        XCTAssertEqual(summary.issues.map(\.impact), [.endpoint(.androidBridge)])
    }

    func testMultipleConnectedEndpointsShowAllDevices() {
        let summary = ReceiverStatusSummary(
            appleConnectionState: .connected("iPhone15Pro"),
            appleConnectedDeviceNames: ["iPhone15Pro"],
            androidConnectionState: .connected("Pixel"),
            androidConnectedDeviceNames: ["Pixel"]
        )

        XCTAssertEqual(summary.overallHealth, .ok)
        XCTAssertFalse(summary.requiresGlobalAttention)
        XCTAssertEqual(summary.connectedDevices.map(\.name), ["iPhone15Pro", "Pixel"])
    }

    func testEveryEndpointFailedRequiresGlobalAttention() {
        let summary = ReceiverStatusSummary(
            appleConnectionState: .failed("Multipeer failed"),
            appleConnectedDeviceNames: [],
            androidConnectionState: .failed("Address already in use"),
            androidConnectedDeviceNames: []
        )

        XCTAssertEqual(summary.overallHealth, .actionRequired)
        XCTAssertTrue(summary.requiresGlobalAttention)
        XCTAssertEqual(summary.issues.map(\.impact), [.endpoint(.appleMultipeer), .endpoint(.androidBridge)])
    }

    func testSharedExecutionIssueRequiresGlobalAttention() {
        let summary = ReceiverStatusSummary(
            appleConnectionState: .connected("iPhone15Pro"),
            appleConnectedDeviceNames: ["iPhone15Pro"],
            androidConnectionState: .listening,
            androidConnectedDeviceNames: [],
            sharedIssue: ReceiverStatusIssue(
                severity: .actionRequired,
                impact: .allDevices,
                message: "历史记录存储不可用",
                suggestedAction: .restartReceiver
            )
        )

        XCTAssertEqual(summary.overallHealth, .actionRequired)
        XCTAssertTrue(summary.requiresGlobalAttention)
        XCTAssertEqual(summary.issues.map(\.impact), [.allDevices])
    }
}
