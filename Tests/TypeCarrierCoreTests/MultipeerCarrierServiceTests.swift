import MultipeerConnectivity
import XCTest
@testable import TypeCarrierCore

@MainActor
final class MultipeerCarrierServiceTests: XCTestCase {
    func testSenderStopsSearchingAfterSearchTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(20)
        )

        service.startSearchingForTesting()
        XCTAssertEqual(service.connectionState, .searching)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderCanExtendCurrentSearchTimeoutForResumeRecovery() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(20)
        )

        service.startSearchingForTesting()
        service.extendCurrentSearchTimeoutForResumeRecovery(to: .milliseconds(80))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .searching)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderShowsReconnectingKnownPeerAfterConnectionTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(80),
            connectionTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()
        XCTAssertEqual(service.connectionState, .connecting("MacBook Pro"))

        let state = try await waitForConnectionState(.reconnecting("MacBook Pro"), in: service)
        XCTAssertEqual(state, .reconnecting("MacBook Pro"))
    }

    func testSenderRetriesKnownPeerAfterConnectionTimeoutWithoutNewDiscoveryEvent() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(160),
            connectionTimeout: .milliseconds(20),
            connectionRetryDelay: .milliseconds(10)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()

        let inviteCount = try await waitForDiagnosticEventCount(
            in: service,
            eventName: "browser.invitePeer",
            minimumCount: 2
        )
        XCTAssertGreaterThanOrEqual(inviteCount, 2)
    }

    func testSenderResetsSessionBeforeRetryingKnownPeerAfterConnectionTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(160),
            connectionTimeout: .milliseconds(20),
            connectionRetryDelay: .milliseconds(10)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()

        let events = try await waitForDiagnosticEvents(in: service, containing: "browser.retryKnownPeer")
        let resetIndex = try XCTUnwrap(events.firstIndex(of: "session.resetForRetry"), events.joined(separator: ", "))
        let retryIndex = try XCTUnwrap(events.firstIndex(of: "browser.retryKnownPeer"), events.joined(separator: ", "))
        XCTAssertLessThan(resetIndex, retryIndex)
    }

    func testSenderStopsRetryingKnownPeerAfterRetryBudgetIsExhausted() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(200),
            connectionTimeout: .milliseconds(20),
            connectionRetryDelay: .milliseconds(10),
            maxConnectionAttempts: 2
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()

        _ = try await waitForDiagnosticEvents(in: service, containing: "connection.retryBudgetExceeded")
        let inviteCount = service.diagnostics.events.filter { $0.name == "browser.invitePeer" }.count
        XCTAssertEqual(inviteCount, 2)
        XCTAssertEqual(service.connectionState, .failed("Could not connect to MacBook Pro."))
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "connection.retryBudgetExceeded" && $0.peerName == "MacBook Pro" })
    }

    func testSenderClearsPreviousConnectionErrorAfterSuccessfulConnection() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(200),
            connectionTimeout: .milliseconds(20),
            connectionRetryDelay: .milliseconds(10),
            maxConnectionAttempts: 1
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        _ = try await waitForDiagnosticEvents(in: service, containing: "connection.retryBudgetExceeded")
        XCTAssertEqual(service.diagnostics.lastErrorMessage, "Could not connect to MacBook Pro.")

        service.simulateSessionStateForTesting(.connected, peerID: peerID)

        XCTAssertNil(service.diagnostics.lastErrorMessage)
    }

    func testSenderShowsReconnectingKnownPeerWhenCurrentConnectionAttemptFails() async {
        let service = MultipeerCarrierService(role: .sender, displayName: "iPhone")
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()

        XCTAssertEqual(service.connectionState, .connecting("MacBook Pro"))

        service.simulateSessionStateForTesting(.notConnected, peerID: peerID)

        XCTAssertEqual(service.connectionState, .reconnecting("MacBook Pro"))
    }

    private func waitForDiagnosticEvents(
        in service: MultipeerCarrierService,
        containing eventName: String,
        attempts: Int = 100
    ) async throws -> [String] {
        for _ in 0..<attempts {
            let events = service.diagnostics.events.map(\.name)
            if events.contains(eventName) {
                return events
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return service.diagnostics.events.map(\.name)
    }

    private func waitForDiagnosticEventCount(
        in service: MultipeerCarrierService,
        eventName: String,
        minimumCount: Int,
        attempts: Int = 100
    ) async throws -> Int {
        for _ in 0..<attempts {
            let count = service.diagnostics.events.filter { $0.name == eventName }.count
            if count >= minimumCount {
                return count
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return service.diagnostics.events.filter { $0.name == eventName }.count
    }

    private func waitForConnectionState(
        _ expectedState: ConnectionState,
        in service: MultipeerCarrierService,
        attempts: Int = 100
    ) async throws -> ConnectionState {
        for _ in 0..<attempts {
            if service.connectionState == expectedState {
                return service.connectionState
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return service.connectionState
    }

    func testSenderShowsReconnectingKnownPeerAfterEstablishedConnectionDrops() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateSessionStateForTesting(.connected, peerID: peerID)

        service.simulateSessionStateForTesting(.notConnected, peerID: peerID)

        XCTAssertEqual(service.connectionState, .reconnecting("MacBook Pro"))

        let state = try await waitForConnectionState(.idle, in: service)
        XCTAssertEqual(state, .idle)
    }

    func testSenderDiagnosticsRecordDiscoveryInvitationAndTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(80),
            connectionTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        await Task.yield()

        XCTAssertEqual(service.diagnostics.discoveredPeers, ["MacBook Pro"])
        XCTAssertEqual(service.diagnostics.invitedPeers, ["MacBook Pro"])
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "browser.foundPeer" && $0.peerName == "MacBook Pro" })
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "browser.invitePeer" && $0.peerName == "MacBook Pro" })

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "connection.timeout" && $0.peerName == "MacBook Pro" })
        XCTAssertEqual(service.diagnostics.connectionState, .reconnecting("MacBook Pro"))
    }

    func testDiagnosticsAppendConnectionEventsToLogFile() async throws {
        let logURL = try temporaryFileURL(fileName: "connection-events.jsonl")
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(80),
            connectionTimeout: .milliseconds(20),
            diagnosticLogFileURL: logURL
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.simulateFoundPeerForTesting(peerID)
        _ = try await waitForDiagnosticEvents(in: service, containing: "connection.timeout")

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"name\":\"browser.foundPeer\""), contents)
        XCTAssertTrue(contents.contains("\"name\":\"browser.invitePeer\""), contents)
        XCTAssertTrue(contents.contains("\"name\":\"connection.timeout\""), contents)
        XCTAssertTrue(contents.contains("\"peerName\":\"MacBook Pro\""), contents)
        XCTAssertTrue(contents.contains("\"connectionState\":\"Reconnecting to MacBook Pro\""), contents)
    }

    func testReceiverDiagnosticsRecordAcceptedInvitation() async {
        let service = MultipeerCarrierService(role: .receiver, displayName: "MacBook Pro")
        let peerID = MCPeerID(displayName: "iPhone")
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test Advertiser"),
            discoveryInfo: nil,
            serviceType: MultipeerCarrierService.serviceType
        )
        var accepted = false
        var sessionWasProvided = false

        service.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: peerID,
            withContext: nil
        ) { shouldAccept, session in
            accepted = shouldAccept
            sessionWasProvided = session != nil
        }
        await Task.yield()

        XCTAssertTrue(accepted)
        XCTAssertTrue(sessionWasProvided)
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "advertiser.invitation.accepted" && $0.peerName == "iPhone" })
    }

    func testSenderIgnoresBrowserCallbacksAfterStop() async {
        let service = MultipeerCarrierService(role: .sender, displayName: "iPhone")
        let peerID = MCPeerID(displayName: "MacBook Pro")
        let staleBrowser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Test Browser"),
            serviceType: MultipeerCarrierService.serviceType
        )

        service.start()
        service.stop()
        service.browser(staleBrowser, foundPeer: peerID, withDiscoveryInfo: nil)
        await Task.yield()

        XCTAssertEqual(service.connectionState, .idle)
        XCTAssertFalse(service.diagnostics.events.contains { $0.name == "browser.invitePeer" && $0.peerName == "MacBook Pro" })
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "browser.ignoredStaleCallback" && $0.peerName == "MacBook Pro" })
    }

    func testReceiverUsesFreshSessionForEveryInvitation() async {
        let service = MultipeerCarrierService(role: .receiver, displayName: "MacBook Pro")
        let peerID = MCPeerID(displayName: "iPhone")
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test Advertiser"),
            discoveryInfo: nil,
            serviceType: MultipeerCarrierService.serviceType
        )
        var firstSession: MCSession?
        var secondSession: MCSession?

        service.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: peerID,
            withContext: nil
        ) { _, session in
            firstSession = session
        }
        service.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: peerID,
            withContext: nil
        ) { _, session in
            secondSession = session
        }
        await Task.yield()

        XCTAssertNotNil(firstSession)
        XCTAssertNotNil(secondSession)
        XCTAssertFalse(firstSession === secondSession)
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "advertiser.sessionResetForInvitation" && $0.peerName == "iPhone" })
    }

    func testReceiverRejectsInvitationFromDifferentPeerWhileConnected() async {
        let service = MultipeerCarrierService(role: .receiver, displayName: "MacBook Pro")
        let connectedPeer = MCPeerID(displayName: "iPhone 17 Pro")
        let secondPeer = MCPeerID(displayName: "iPhone")
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test Advertiser"),
            discoveryInfo: nil,
            serviceType: MultipeerCarrierService.serviceType
        )
        var accepted = true
        var sessionWasProvided = true

        service.simulateSessionStateForTesting(.connected, peerID: connectedPeer)

        service.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: secondPeer,
            withContext: nil
        ) { shouldAccept, session in
            accepted = shouldAccept
            sessionWasProvided = session != nil
        }
        await Task.yield()

        XCTAssertFalse(accepted)
        XCTAssertFalse(sessionWasProvided)
        XCTAssertEqual(service.connectionState, .connected("iPhone 17 Pro"))
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "advertiser.invitation.rejectedBusy" && $0.peerName == "iPhone" })
    }

    private func temporaryFileURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }
}
