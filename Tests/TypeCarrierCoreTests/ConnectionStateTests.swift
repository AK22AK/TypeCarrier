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

    func testManualRestartEligibilityIncludesInFlightConnectionStates() {
        XCTAssertTrue(ConnectionState.idle.isManualRestartEligible)
        XCTAssertTrue(ConnectionState.searching.isManualRestartEligible)
        XCTAssertTrue(ConnectionState.connecting("Mac").isManualRestartEligible)
        XCTAssertTrue(ConnectionState.reconnecting("Mac").isManualRestartEligible)
        XCTAssertTrue(ConnectionState.failed("Denied").isManualRestartEligible)
        XCTAssertFalse(ConnectionState.connected("Mac").isManualRestartEligible)
        XCTAssertFalse(ConnectionState.advertising.isManualRestartEligible)
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

    func testSenderFailureSuggestionIgnoresStaleBusyEvents() {
        let diagnostics = CarrierDiagnostics(
            role: "sender",
            localPeerName: "iPhone",
            serviceType: "typecarrier",
            connectionState: .failed("Could not connect to MacBook Pro."),
            discoveredPeers: ["MacBook Pro"],
            lastErrorMessage: "Could not connect to MacBook Pro.",
            events: [
                CarrierDiagnosticEvent(
                    name: "browser.foundBusyPeer",
                    message: "Receiver advertised busy availability",
                    peerName: "MacBook Pro",
                    connectionState: .failed("MacBook Pro is already connected to another device."),
                    connectedPeers: []
                ),
                CarrierDiagnosticEvent(
                    name: "connection.retryBudgetExceeded",
                    message: "Stopped after 2 connection attempts",
                    peerName: "MacBook Pro",
                    connectionState: .failed("Could not connect to MacBook Pro."),
                    connectedPeers: []
                )
            ]
        )

        XCTAssertNil(diagnostics.connectionRecoverySuggestion)
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

    func testIPhoneAndAndroidDevicesShareTheOneReceiver() {
        let summary = ReceiverStatusSummary(
            connectionState: .connected("iPhone15Pro"),
            connectedDevices: [
                ReceiverConnectedDevice(name: "iPhone15Pro", platform: .apple),
                ReceiverConnectedDevice(name: "Pixel", platform: .android),
            ]
        )

        XCTAssertEqual(summary.overallHealth, .ok)
        XCTAssertFalse(summary.requiresGlobalAttention)
        XCTAssertEqual(summary.connectedDevices.map(\.name), ["iPhone15Pro", "Pixel"])
    }

    func testReceiverFailureRequiresGlobalAttention() {
        let summary = ReceiverStatusSummary(connectionState: .failed("Address already in use"), connectedDevices: [])

        XCTAssertEqual(summary.overallHealth, .actionRequired)
        XCTAssertTrue(summary.requiresGlobalAttention)
        XCTAssertFalse(summary.hasUsableEndpoint)
        XCTAssertEqual(summary.issues.map(\.impact), [.receiver])
    }

    func testSharedExecutionIssueRequiresGlobalAttention() {
        let summary = ReceiverStatusSummary(
            connectionState: .connected("iPhone15Pro"),
            connectedDevices: [ReceiverConnectedDevice(name: "iPhone15Pro", platform: .apple)],
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

    func testListeningReceiverWithoutDevicesIsReady() {
        let summary = ReceiverStatusSummary(connectionState: .advertising, connectedDevices: [])
        XCTAssertTrue(summary.hasUsableEndpoint)
        XCTAssertTrue(summary.connectedDevices.isEmpty)
        XCTAssertEqual(summary.overallHealth, .ok)
    }

    func testStoppedReceiverIsUnavailableEvenWithoutReportedErrors() {
        let summary = ReceiverStatusSummary(connectionState: .idle, connectedDevices: [])
        XCTAssertFalse(summary.hasUsableEndpoint)
        XCTAssertTrue(summary.issues.isEmpty)
    }
}
