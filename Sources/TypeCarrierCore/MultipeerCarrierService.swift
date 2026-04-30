import Combine
import Foundation
@preconcurrency import MultipeerConnectivity
import os

extension MCPeerID: @unchecked @retroactive Sendable {}
extension MCSessionState: @unchecked @retroactive Sendable {}

public struct CarrierDiagnosticEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let name: String
    public let message: String
    public let peerName: String?
    public let connectionState: ConnectionState
    public let connectedPeers: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String,
        message: String,
        peerName: String?,
        connectionState: ConnectionState,
        connectedPeers: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.message = message
        self.peerName = peerName
        self.connectionState = connectionState
        self.connectedPeers = connectedPeers
    }
}

public struct CarrierDiagnostics: Equatable, Sendable {
    public let role: String
    public let localPeerName: String
    public let serviceType: String
    public var connectionState: ConnectionState
    public var discoveredPeers: [String]
    public var invitedPeers: [String]
    public var connectedPeers: [String]
    public var lastErrorMessage: String?
    public var events: [CarrierDiagnosticEvent]

    public init(
        role: String,
        localPeerName: String,
        serviceType: String,
        connectionState: ConnectionState = .idle,
        discoveredPeers: [String] = [],
        invitedPeers: [String] = [],
        connectedPeers: [String] = [],
        lastErrorMessage: String? = nil,
        events: [CarrierDiagnosticEvent] = []
    ) {
        self.role = role
        self.localPeerName = localPeerName
        self.serviceType = serviceType
        self.connectionState = connectionState
        self.discoveredPeers = discoveredPeers
        self.invitedPeers = invitedPeers
        self.connectedPeers = connectedPeers
        self.lastErrorMessage = lastErrorMessage
        self.events = events
    }

    var emptyPlaceholder: String {
        "None"
    }

    public var discoveredPeersText: String {
        discoveredPeers.isEmpty ? emptyPlaceholder : discoveredPeers.joined(separator: ", ")
    }

    public var invitedPeersText: String {
        invitedPeers.isEmpty ? emptyPlaceholder : invitedPeers.joined(separator: ", ")
    }

    public var connectedPeersText: String {
        connectedPeers.isEmpty ? emptyPlaceholder : connectedPeers.joined(separator: ", ")
    }

    fileprivate func updating(
        connectionState: ConnectionState,
        discoveredPeers: [String],
        invitedPeers: [String],
        connectedPeers: [String],
        lastErrorMessage: String?
    ) -> CarrierDiagnostics {
        var copy = self
        copy.connectionState = connectionState
        copy.discoveredPeers = discoveredPeers
        copy.invitedPeers = invitedPeers
        copy.connectedPeers = connectedPeers
        copy.lastErrorMessage = lastErrorMessage
        return copy
    }
}

@MainActor
public final class MultipeerCarrierService: NSObject, ObservableObject {
    public enum Role: Sendable {
        case sender
        case receiver
    }

    public static let serviceType = "typecarrier"

    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var discoveredPeers: [CarrierPeer] = []
    @Published public private(set) var lastReceivedEnvelope: CarrierEnvelope?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var diagnostics: CarrierDiagnostics

    private let role: Role
    private let peerID: MCPeerID
    private let searchTimeout: Duration
    private let connectionTimeout: Duration
    private let connectionRetryDelay: Duration
    private nonisolated(unsafe) let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var searchTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var connectionRetryTask: Task<Void, Never>?
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var connectingPeerName: String?
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?
    private let logger = Logger(subsystem: "ak22ak.typecarrier", category: "MultipeerCarrierService")
    private let maxDiagnosticEventCount = 50

    public init(
        role: Role,
        displayName: String? = nil,
        searchTimeout: Duration = .seconds(30),
        connectionTimeout: Duration = .seconds(15),
        connectionRetryDelay: Duration = .seconds(2)
    ) {
        self.role = role
        self.searchTimeout = searchTimeout
        self.connectionTimeout = connectionTimeout
        self.connectionRetryDelay = connectionRetryDelay
        let localPeerID = MCPeerID(displayName: displayName ?? ProcessInfo.processInfo.processName)
        peerID = localPeerID
        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        diagnostics = CarrierDiagnostics(
            role: Self.roleName(for: role),
            localPeerName: localPeerID.displayName,
            serviceType: Self.serviceType
        )
        super.init()
        session.delegate = self
    }

    public func start(onEnvelope: ((CarrierEnvelope, MCPeerID) -> Void)? = nil) {
        envelopeHandler = onEnvelope
        logger.info("Starting service role=\(self.roleName, privacy: .public)")
        recordDiagnosticEvent("service.start", message: "Starting \(roleName)")

        switch role {
        case .sender:
            startBrowsing()
        case .receiver:
            startAdvertising()
        }
    }

    public func stop() {
        logger.info("Stopping service role=\(self.roleName, privacy: .public)")
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session.disconnect()
        cancelSearchTimeout()
        cancelConnectionTimeout()
        cancelConnectionRetry()
        connectionState = .idle
        discoveredPeers = []
        knownPeerIDs = [:]
        invitedPeerIDs = []
        connectingPeerName = nil
        recordDiagnosticEvent("service.stop", message: "Stopped \(roleName)")
    }

    public func sendText(_ text: String) throws {
        guard CarrierPayload.canSend(text) else {
            throw CarrierServiceError.blankText
        }

        try send(.text(CarrierPayload(text: text)))
    }

    public func send(_ envelope: CarrierEnvelope) throws {
        guard !session.connectedPeers.isEmpty else {
            throw CarrierServiceError.noConnectedPeer
        }

        let data = try CarrierCodec.encode(envelope)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        recordDiagnosticEvent("session.send", message: "Sent \(envelope.kind.rawValue)", peerName: session.connectedPeers.first?.displayName)
    }

    private func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
        connectionState = .searching
        browser.startBrowsingForPeers()
        scheduleSearchTimeout()
        recordDiagnosticEvent("browser.start", message: "Browsing for \(Self.serviceType)")
        logger.info("Started browsing for peers")
    }

    private func startAdvertising() {
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        connectionState = .advertising
        advertiser.startAdvertisingPeer()
        recordDiagnosticEvent("advertiser.start", message: "Advertising \(Self.serviceType)")
        logger.info("Started advertising peer")
    }

    private func rememberAndInvite(_ peerID: MCPeerID) {
        let key = peerID.displayName
        knownPeerIDs[key] = peerID

        if !discoveredPeers.contains(where: { $0.id == key }) {
            discoveredPeers.append(CarrierPeer(peerID: peerID))
            updateDiagnostics()
        }

        guard !invitedPeerIDs.contains(key), session.connectedPeers.isEmpty else {
            logger.debug("Skipping invite peer=\(key, privacy: .public) alreadyInvited=\(self.invitedPeerIDs.contains(key), privacy: .public) connectedCount=\(self.session.connectedPeers.count, privacy: .public)")
            recordDiagnosticEvent("browser.inviteSkipped", message: "alreadyInvited=\(invitedPeerIDs.contains(key)) connectedCount=\(session.connectedPeers.count)", peerName: key)
            return
        }

        invitedPeerIDs.insert(key)
        cancelSearchTimeout()
        connectingPeerName = key
        connectionState = .connecting(peerID.displayName)
        scheduleConnectionTimeout(for: key)
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        recordDiagnosticEvent("browser.invitePeer", message: "Invited peer", peerName: key)
        logger.info("Invited peer=\(key, privacy: .public)")
    }

    private func handleSessionState(_ state: MCSessionState, peerID: MCPeerID) {
        logger.info("Session state peer=\(peerID.displayName, privacy: .public) state=\(self.sessionStateName(state), privacy: .public)")

        switch state {
        case .connected:
            knownPeerIDs[peerID.displayName] = peerID
            cancelSearchTimeout()
            cancelConnectionTimeout()
            cancelConnectionRetry()
            connectingPeerName = nil
            connectionState = .connected(peerID.displayName)
            recordDiagnosticEvent("session.connected", message: "Session connected", peerName: peerID.displayName)
        case .connecting:
            knownPeerIDs[peerID.displayName] = peerID
            cancelSearchTimeout()
            cancelConnectionRetry()
            connectingPeerName = peerID.displayName
            scheduleConnectionTimeout(for: peerID.displayName)
            connectionState = .connecting(peerID.displayName)
            recordDiagnosticEvent("session.connecting", message: "Session connecting", peerName: peerID.displayName)
        case .notConnected:
            let previousState = connectionState
            invitedPeerIDs.remove(peerID.displayName)
            cancelConnectionTimeout()
            connectingPeerName = nil

            if case .receiver = role {
                connectionState = .advertising
            } else if case .connected = previousState {
                returnToSearchingAfterConnectionAttempt()
            } else if case .connecting = previousState {
                returnToSearchingAfterConnectionAttempt()
            } else if case .reconnecting = previousState {
                returnToSearchingAfterConnectionAttempt()
            }
            recordDiagnosticEvent("session.notConnected", message: "Previous state: \(previousState.displayText)", peerName: peerID.displayName)
        @unknown default:
            connectionState = .failed("Unknown connection state")
            recordDiagnosticEvent("session.unknownState", message: "Unknown connection state", peerName: peerID.displayName)
        }
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        do {
            let envelope = try CarrierCodec.decode(data)
            lastReceivedEnvelope = envelope
            envelopeHandler?(envelope, peerID)
            recordDiagnosticEvent("session.receive", message: "Received \(envelope.kind.rawValue)", peerName: peerID.displayName)
        } catch {
            lastErrorMessage = error.localizedDescription
            recordDiagnosticEvent("session.decodeFailed", message: error.localizedDescription, peerName: peerID.displayName)
            try? send(.error(error.localizedDescription))
        }
    }

    private func fail(_ message: String) {
        logger.error("Service failed message=\(message, privacy: .public)")
        cancelSearchTimeout()
        cancelConnectionTimeout()
        lastErrorMessage = message
        connectionState = .failed(message)
        recordDiagnosticEvent("service.failed", message: message)
    }

    private func scheduleSearchTimeout() {
        cancelSearchTimeout()

        searchTimeoutTask = Task { @MainActor [weak self, searchTimeout] in
            do {
                try await Task.sleep(for: searchTimeout)
            } catch {
                return
            }

            self?.handleSearchTimeout()
        }
    }

    private func cancelSearchTimeout() {
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
    }

    private func scheduleConnectionTimeout(for peerName: String) {
        cancelConnectionTimeout()

        connectionTimeoutTask = Task { @MainActor [weak self, connectionTimeout] in
            do {
                try await Task.sleep(for: connectionTimeout)
            } catch {
                return
            }

            self?.handleConnectionTimeout(for: peerName)
        }
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    private func scheduleConnectionRetry() {
        guard case .sender = role,
              connectionState.isWaitingToRetryKnownPeer,
              !knownPeerIDs.isEmpty,
              session.connectedPeers.isEmpty else {
            return
        }

        cancelConnectionRetry()
        connectionRetryTask = Task { @MainActor [weak self, connectionRetryDelay] in
            do {
                try await Task.sleep(for: connectionRetryDelay)
            } catch {
                return
            }

            self?.retryKnownPeer()
        }
    }

    private func cancelConnectionRetry() {
        connectionRetryTask?.cancel()
        connectionRetryTask = nil
    }

    private func retryKnownPeer() {
        guard case .sender = role,
              connectionState.isWaitingToRetryKnownPeer,
              session.connectedPeers.isEmpty,
              let peerID = knownPeerIDs.values.sorted(by: { $0.displayName < $1.displayName }).first else {
            return
        }

        recordDiagnosticEvent("browser.retryKnownPeer", message: "Retrying known peer", peerName: peerID.displayName)
        rememberAndInvite(peerID)
    }

    private func handleSearchTimeout() {
        guard case .sender = role, connectionState.isSearchTimeoutEligible, session.connectedPeers.isEmpty else {
            return
        }

        logger.info("Search timed out after \(String(describing: self.searchTimeout), privacy: .public)")
        stopBrowsingAndDisconnect()
        recordDiagnosticEvent("search.timeout", message: "Search timed out after \(String(describing: searchTimeout))")
    }

    private func handleConnectionTimeout(for peerName: String) {
        guard case .sender = role,
              case .connecting(let currentPeerName) = connectionState,
              currentPeerName == peerName,
              session.connectedPeers.isEmpty else {
            return
        }

        logger.info("Connection timed out peer=\(peerName, privacy: .public) after \(String(describing: self.connectionTimeout), privacy: .public)")
        invitedPeerIDs.remove(peerName)
        connectingPeerName = nil
        returnToSearchingAfterConnectionAttempt()
        recordDiagnosticEvent("connection.timeout", message: "Connection timed out after \(String(describing: connectionTimeout))", peerName: peerName)
    }

    private func returnToSearchingAfterConnectionAttempt() {
        cancelConnectionTimeout()
        if session.connectedPeers.isEmpty,
           let peerID = knownPeerIDs.values.sorted(by: { $0.displayName < $1.displayName }).first {
            connectionState = .reconnecting(peerID.displayName)
        } else {
            connectionState = .searching
        }
        scheduleSearchTimeout()
        scheduleConnectionRetry()
        updateDiagnostics()
    }

    private func stopBrowsingAndDisconnect() {
        cancelSearchTimeout()
        cancelConnectionTimeout()
        cancelConnectionRetry()
        browser?.stopBrowsingForPeers()
        connectionState = .idle
        updateDiagnostics()
    }

#if DEBUG
    func startSearchingForTesting() {
        connectionState = .searching
        scheduleSearchTimeout()
    }
#endif

    private var roleName: String {
        Self.roleName(for: role)
    }

    private static func roleName(for role: Role) -> String {
        switch role {
        case .sender:
            "sender"
        case .receiver:
            "receiver"
        }
    }

    private func sessionStateName(_ state: MCSessionState) -> String {
        switch state {
        case .notConnected:
            "notConnected"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        @unknown default:
            "unknown"
        }
    }

    private func updateDiagnostics() {
        diagnostics = diagnostics.updating(
            connectionState: connectionState,
            discoveredPeers: discoveredPeers.map(\.displayName).sorted(),
            invitedPeers: invitedPeerIDs.sorted(),
            connectedPeers: connectedPeerNames(),
            lastErrorMessage: lastErrorMessage
        )
    }

    private func recordDiagnosticEvent(_ name: String, message: String, peerName: String? = nil) {
        var updated = diagnostics.updating(
            connectionState: connectionState,
            discoveredPeers: discoveredPeers.map(\.displayName).sorted(),
            invitedPeers: invitedPeerIDs.sorted(),
            connectedPeers: connectedPeerNames(),
            lastErrorMessage: lastErrorMessage
        )
        updated.events.append(
            CarrierDiagnosticEvent(
                name: name,
                message: message,
                peerName: peerName,
                connectionState: connectionState,
                connectedPeers: connectedPeerNames()
            )
        )

        if updated.events.count > maxDiagnosticEventCount {
            updated.events.removeFirst(updated.events.count - maxDiagnosticEventCount)
        }

        diagnostics = updated
    }

    private func connectedPeerNames() -> [String] {
        session.connectedPeers.map(\.displayName).sorted()
    }
}

public enum CarrierServiceError: LocalizedError, Equatable, Sendable {
    case blankText
    case noConnectedPeer

    public var errorDescription: String? {
        switch self {
        case .blankText:
            "Text is empty."
        case .noConnectedPeer:
            "No connected peer."
        }
    }
}

extension MultipeerCarrierService: MCNearbyServiceBrowserDelegate {
    nonisolated public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor [weak self] in
            self?.logger.info("Found peer=\(peerID.displayName, privacy: .public)")
            self?.recordDiagnosticEvent("browser.foundPeer", message: "Found peer", peerName: peerID.displayName)
            self?.rememberAndInvite(peerID)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.logger.info("Lost peer=\(peerID.displayName, privacy: .public)")
            self?.knownPeerIDs[peerID.displayName] = nil
            self?.invitedPeerIDs.remove(peerID.displayName)
            self?.discoveredPeers.removeAll { $0.id == peerID.displayName }
            if self?.knownPeerIDs.isEmpty == true {
                self?.cancelConnectionRetry()
            }
            self?.recordDiagnosticEvent("browser.lostPeer", message: "Lost peer", peerName: peerID.displayName)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(error.localizedDescription)
        }
    }
}

extension MultipeerCarrierService: MCNearbyServiceAdvertiserDelegate {
    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.recordDiagnosticEvent("advertiser.invitation.accepted", message: "Accepted invitation", peerName: peerID.displayName)
        }
        invitationHandler(true, session)
    }

    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.fail(error.localizedDescription)
        }
    }
}

extension MultipeerCarrierService: MCSessionDelegate {
    nonisolated public func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor [weak self] in
            self?.handleSessionState(state, peerID: peerID)
        }
    }

    nonisolated public func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        Task { @MainActor [weak self] in
            self?.handleData(data, from: peerID)
        }
    }

    nonisolated public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
