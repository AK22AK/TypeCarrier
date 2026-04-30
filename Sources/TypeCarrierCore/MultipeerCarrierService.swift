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

    public var diagnosticLogFileURL: URL? {
        diagnosticLogStore?.fileURL
    }

    private let role: Role
    private let peerID: MCPeerID
    private let searchTimeout: Duration
    private let connectionTimeout: Duration
    private let connectionRetryDelay: Duration
    private let inviteTimeout: TimeInterval
    private let maxConnectionAttempts: Int
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private nonisolated(unsafe) var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var searchTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var connectionRetryTask: Task<Void, Never>?
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var connectionAttemptCounts: [String: Int] = [:]
    private var connectingPeerName: String?
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?
    private let logger = Logger(subsystem: "ak22ak.typecarrier", category: "MultipeerCarrierService")
    private let maxDiagnosticEventCount = 50

    public init(
        role: Role,
        displayName: String? = nil,
        searchTimeout: Duration = .seconds(10),
        connectionTimeout: Duration = .seconds(6),
        connectionRetryDelay: Duration = .seconds(1),
        inviteTimeout: TimeInterval = 6,
        maxConnectionAttempts: Int = 3,
        diagnosticLogFileURL: URL? = nil
    ) {
        self.role = role
        self.searchTimeout = searchTimeout
        self.connectionTimeout = connectionTimeout
        self.connectionRetryDelay = connectionRetryDelay
        self.inviteTimeout = inviteTimeout
        self.maxConnectionAttempts = max(1, maxConnectionAttempts)
        diagnosticLogStore = diagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
        let localPeerID = MCPeerID(displayName: displayName ?? ProcessInfo.processInfo.processName)
        peerID = localPeerID
        session = Self.makeSession(peerID: localPeerID)
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
        lastErrorMessage = nil
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
        stopBrowsing()
        stopAdvertising()
        session.disconnect()
        session.delegate = nil
        session = Self.makeSession(peerID: peerID)
        session.delegate = self
        cancelSearchTimeout()
        cancelConnectionTimeout()
        cancelConnectionRetry()
        connectionState = .idle
        discoveredPeers = []
        knownPeerIDs = [:]
        invitedPeerIDs = []
        connectionAttemptCounts = [:]
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

    public func recordDiagnosticMarker(_ name: String, message: String, peerName: String? = nil) {
        recordDiagnosticEvent(name, message: message, peerName: peerName)
    }

    public func extendCurrentSearchTimeoutForResumeRecovery(to timeout: Duration) {
        guard case .sender = role, connectionState.isSearchTimeoutEligible, session.connectedPeers.isEmpty else {
            return
        }

        scheduleSearchTimeout(timeout: timeout)
        recordDiagnosticEvent(
            "search.resumeTimeoutExtended",
            message: "Extended current search timeout to \(String(describing: timeout))"
        )
    }

    private func startBrowsing() {
        stopBrowsing()
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
        stopAdvertising()
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        connectionState = .advertising
        advertiser.startAdvertisingPeer()
        recordDiagnosticEvent("advertiser.start", message: "Advertising \(Self.serviceType)")
        logger.info("Started advertising peer")
    }

    private func stopBrowsing() {
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    private func stopAdvertising() {
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    nonisolated private static func makeSession(peerID: MCPeerID) -> MCSession {
        MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    }

    private func replaceSession(reason: String, peerName: String? = nil) {
        let previousPeerNames = connectedPeerNames()
        session.disconnect()
        session.delegate = nil
        let newSession = Self.makeSession(peerID: peerID)
        newSession.delegate = self
        session = newSession
        recordDiagnosticEvent(
            reason,
            message: "Created fresh session; previous connected peers: \(previousPeerNames.isEmpty ? "None" : previousPeerNames.joined(separator: ", "))",
            peerName: peerName
        )
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
        let attempt = (connectionAttemptCounts[key] ?? 0) + 1
        connectionAttemptCounts[key] = attempt
        cancelSearchTimeout()
        connectingPeerName = key
        connectionState = .connecting(peerID.displayName)
        scheduleConnectionTimeout(for: key)
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: inviteTimeout)
        recordDiagnosticEvent("browser.invitePeer", message: "Invited peer attempt \(attempt)/\(maxConnectionAttempts)", peerName: key)
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
            lastErrorMessage = nil
            connectionAttemptCounts[peerID.displayName] = nil
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
                replaceSession(reason: "session.resetAfterNotConnected", peerName: peerID.displayName)
                returnToSearchingAfterConnectionAttempt()
            } else if case .connecting = previousState {
                replaceSession(reason: "session.resetAfterNotConnected", peerName: peerID.displayName)
                returnToSearchingAfterConnectionAttempt()
            } else if case .reconnecting = previousState {
                replaceSession(reason: "session.resetAfterNotConnected", peerName: peerID.displayName)
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

    private func scheduleSearchTimeout(timeout: Duration? = nil) {
        cancelSearchTimeout()

        let timeout = timeout ?? searchTimeout
        searchTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
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

            self?.connectionTimeoutTask = nil
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
        recordDiagnosticEvent("connection.retryScheduled", message: "Retrying in \(String(describing: connectionRetryDelay))", peerName: connectionState.peerName)
        connectionRetryTask = Task.detached { [weak self, connectionRetryDelay] in
            do {
                try await Task.sleep(for: connectionRetryDelay)
            } catch {
                return
            }

            await self?.finishConnectionRetryDelay()
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

    private func finishConnectionRetryDelay() {
        connectionRetryTask = nil
        retryKnownPeer()
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
        replaceSession(reason: "session.resetForRetry", peerName: peerName)
        returnToSearchingAfterConnectionAttempt()
        recordDiagnosticEvent("connection.timeout", message: "Connection timed out after \(String(describing: connectionTimeout))", peerName: peerName)
    }

    private func returnToSearchingAfterConnectionAttempt() {
        cancelConnectionTimeout()
        if session.connectedPeers.isEmpty,
           let peerID = knownPeerIDs.values.sorted(by: { $0.displayName < $1.displayName }).first {
            guard (connectionAttemptCounts[peerID.displayName] ?? 0) < maxConnectionAttempts else {
                failAfterConnectionRetryBudget(for: peerID.displayName)
                return
            }

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
        stopBrowsing()
        connectionState = .idle
        updateDiagnostics()
    }

    private func failAfterConnectionRetryBudget(for peerName: String) {
        cancelSearchTimeout()
        cancelConnectionTimeout()
        cancelConnectionRetry()
        stopBrowsing()
        invitedPeerIDs.remove(peerName)
        connectingPeerName = nil
        lastErrorMessage = "Could not connect to \(peerName)."
        connectionState = .failed(lastErrorMessage ?? "Could not connect.")
        recordDiagnosticEvent(
            "connection.retryBudgetExceeded",
            message: "Stopped after \(connectionAttemptCounts[peerName] ?? maxConnectionAttempts) connection attempts",
            peerName: peerName
        )
    }

#if DEBUG
    func startSearchingForTesting() {
        connectionState = .searching
        scheduleSearchTimeout()
    }

    func simulateFoundPeerForTesting(_ peerID: MCPeerID) {
        recordDiagnosticEvent("browser.foundPeer", message: "Found peer", peerName: peerID.displayName)
        rememberAndInvite(peerID)
    }

    func simulateSessionStateForTesting(_ state: MCSessionState, peerID: MCPeerID) {
        handleSessionState(state, peerID: peerID)
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
        let event = CarrierDiagnosticEvent(
            name: name,
            message: message,
            peerName: peerName,
            connectionState: connectionState,
            connectedPeers: connectedPeerNames()
        )
        updated.events.append(event)

        if updated.events.count > maxDiagnosticEventCount {
            updated.events.removeFirst(updated.events.count - maxDiagnosticEventCount)
        }

        diagnostics = updated
        try? diagnosticLogStore?.append(event: event, diagnostics: updated)
    }

    private func connectedPeerNames() -> [String] {
        session.connectedPeers.map(\.displayName).sorted()
    }

    private func isCurrentBrowser(_ browser: MCNearbyServiceBrowser) -> Bool {
        self.browser === browser
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
            guard let self else {
                return
            }

            guard self.isCurrentBrowser(browser) else {
                self.recordDiagnosticEvent(
                    "browser.ignoredStaleCallback",
                    message: "Ignored foundPeer from inactive browser",
                    peerName: peerID.displayName
                )
                return
            }

            self.logger.info("Found peer=\(peerID.displayName, privacy: .public)")
            self.recordDiagnosticEvent("browser.foundPeer", message: "Found peer", peerName: peerID.displayName)
            self.rememberAndInvite(peerID)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard self.isCurrentBrowser(browser) else {
                self.recordDiagnosticEvent(
                    "browser.ignoredStaleCallback",
                    message: "Ignored lostPeer from inactive browser",
                    peerName: peerID.displayName
                )
                return
            }

            self.logger.info("Lost peer=\(peerID.displayName, privacy: .public)")
            self.knownPeerIDs[peerID.displayName] = nil
            self.invitedPeerIDs.remove(peerID.displayName)
            self.connectionAttemptCounts[peerID.displayName] = nil
            self.discoveredPeers.removeAll { $0.id == peerID.displayName }
            if self.knownPeerIDs.isEmpty {
                self.cancelConnectionRetry()
            }
            self.recordDiagnosticEvent("browser.lostPeer", message: "Lost peer", peerName: peerID.displayName)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentBrowser(browser) else {
                return
            }

            self.fail(error.localizedDescription)
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
        let previousPeerNames = session.connectedPeers.map(\.displayName).sorted()
        session.disconnect()
        session.delegate = nil
        let freshSession = Self.makeSession(peerID: self.peerID)
        freshSession.delegate = self
        session = freshSession
        let acceptedSession = freshSession

        Task { @MainActor [weak self] in
            self?.recordDiagnosticEvent(
                "advertiser.sessionResetForInvitation",
                message: "Created fresh session before accepting invitation. Previous connected peers: \(previousPeerNames.isEmpty ? "None" : previousPeerNames.joined(separator: ", "))",
                peerName: peerID.displayName
            )
            self?.recordDiagnosticEvent("advertiser.invitation.accepted", message: "Accepted invitation", peerName: peerID.displayName)
        }
        invitationHandler(true, acceptedSession)
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
        Task { @MainActor [weak self, session] in
            guard let self else {
                return
            }

            guard session === self.session else {
                self.recordDiagnosticEvent(
                    "session.ignoredStaleCallback",
                    message: "Ignored \(self.sessionStateName(state)) from replaced session",
                    peerName: peerID.displayName
                )
                return
            }

            self.handleSessionState(state, peerID: peerID)
        }
    }

    nonisolated public func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        Task { @MainActor [weak self, session] in
            guard let self, session === self.session else {
                return
            }

            self.handleData(data, from: peerID)
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
