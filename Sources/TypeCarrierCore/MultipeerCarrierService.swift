import Combine
import Foundation
@preconcurrency import MultipeerConnectivity
import os

extension MCPeerID: @unchecked @retroactive Sendable {}
extension MCSessionState: @unchecked @retroactive Sendable {}

public enum CarrierReceiverDiscoveryInfo {
    static let availabilityKey = "receiverAvailability"
    static let availableValue = "available"
    static let busyValue = "busy"
    static let instanceStartedAtKey = "receiverInstanceStartedAt"
    public static let appBundleIDKey = "appBundleID"
    public static let appVariantKey = "appVariant"
}

private struct PeerDiscoveryIdentity: Equatable {
    let key: String
    let displayName: String
    let diagnosticSummary: String

    init(peerID: MCPeerID, discoveryInfo: [String: String]?) {
        self.init(
            displayName: peerID.displayName,
            discoveryInfo: discoveryInfo
        )
    }

    init(displayName: String, discoveryInfo: [String: String]?) {
        self.displayName = displayName
        let parts = Self.identityParts(displayName: displayName, discoveryInfo: discoveryInfo)
        key = parts.joined(separator: "|")
        diagnosticSummary = parts.joined(separator: " ")
    }

    init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
        diagnosticSummary = key
    }

    private static func identityParts(displayName: String, discoveryInfo: [String: String]?) -> [String] {
        if let macID = normalizedValue(AndroidBonjourAdvertisement.macIDKey, from: discoveryInfo) {
            var parts = ["macID=\(macID)"]
            append(CarrierReceiverDiscoveryInfo.appBundleIDKey, from: discoveryInfo, to: &parts)
            append(CarrierReceiverDiscoveryInfo.appVariantKey, from: discoveryInfo, to: &parts)
            return parts
        }

        var parts = ["name=\(displayName)"]
        append(CarrierReceiverDiscoveryInfo.appBundleIDKey, from: discoveryInfo, to: &parts)
        append(CarrierReceiverDiscoveryInfo.appVariantKey, from: discoveryInfo, to: &parts)
        return parts
    }

    private static func append(_ key: String, from discoveryInfo: [String: String]?, to parts: inout [String]) {
        guard let value = normalizedValue(key, from: discoveryInfo) else {
            return
        }

        parts.append("\(key)=\(value)")
    }

    private static func normalizedValue(_ key: String, from discoveryInfo: [String: String]?) -> String? {
        guard let value = discoveryInfo?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

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

    public var connectionRecoverySuggestion: String? {
        guard role == "sender",
              connectionState.isFailed else {
            return nil
        }

        let latestFailureEvent = events.last { $0.connectionState.isFailed }
        if latestFailureEvent?.name == "browser.foundBusyPeer" {
            return "Disconnect the other iPhone or simulator from this Mac, then retry here."
        }

        return nil
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

    public var receiverSessionInvalidatedHandler: ((_ peerName: String, _ previousState: ConnectionState) -> Void)?

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
    private let discoveryInviteDelay: Duration
    private let receiverDiscoveryInfoExtras: [String: String]
    private let receiverInstanceStartedAt: String
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private nonisolated(unsafe) var session: MCSession
    private nonisolated(unsafe) var activeReceiverPeerName: String?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var searchTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var connectionRetryTask: Task<Void, Never>?
    private var pendingPeerInviteTasks: [String: Task<Void, Never>] = [:]
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var peerDiscoveryFreshness: [String: Double] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var connectionAttemptCounts: [String: Int] = [:]
    private var peerIdentityKeysByObject: [ObjectIdentifier: String] = [:]
    private var peerDisplayNamesByIdentity: [String: String] = [:]
    private var connectingPeerName: String?
    private var connectingPeerIdentityKey: String?
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?
    private let logger = Logger(subsystem: "ak22ak.typecarrier", category: "MultipeerCarrierService")
    private let maxDiagnosticEventCount = 50
#if DEBUG
    private var usesSimulatedDiscoveryForTesting = false
#endif

    public init(
        role: Role,
        displayName: String? = nil,
        searchTimeout: Duration = .seconds(10),
        connectionTimeout: Duration = .seconds(6),
        connectionRetryDelay: Duration = .seconds(1),
        inviteTimeout: TimeInterval = 6,
        maxConnectionAttempts: Int = 3,
        discoveryInviteDelay: Duration = .milliseconds(250),
        receiverDiscoveryInfoExtras: [String: String] = [:],
        diagnosticLogFileURL: URL? = nil
    ) {
        self.role = role
        self.searchTimeout = searchTimeout
        self.connectionTimeout = connectionTimeout
        self.connectionRetryDelay = connectionRetryDelay
        self.inviteTimeout = inviteTimeout
        self.maxConnectionAttempts = max(1, maxConnectionAttempts)
        self.discoveryInviteDelay = discoveryInviteDelay
        self.receiverDiscoveryInfoExtras = receiverDiscoveryInfoExtras
        receiverInstanceStartedAt = String(Date().timeIntervalSince1970)
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
        cancelPendingPeerInvites()
        connectionState = .idle
        discoveredPeers = []
        knownPeerIDs = [:]
        peerDiscoveryFreshness = [:]
        invitedPeerIDs = []
        connectionAttemptCounts = [:]
        peerIdentityKeysByObject = [:]
        peerDisplayNamesByIdentity = [:]
        connectingPeerName = nil
        connectingPeerIdentityKey = nil
        activeReceiverPeerName = nil
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
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: receiverDiscoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser
        if !connectionState.isConnected {
            connectionState = .advertising
        }
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

    private static func receiverNeedsServiceRebuildAfterNotConnected(from previousState: ConnectionState) -> Bool {
        switch previousState {
        case .connected:
            true
        case .idle, .searching, .advertising, .connecting, .reconnecting, .failed:
            false
        }
    }

    private var receiverDiscoveryInfo: [String: String]? {
        guard case .receiver = role else {
            return nil
        }

        var info = receiverDiscoveryInfoExtras
        info[CarrierReceiverDiscoveryInfo.availabilityKey] = receiverAvailabilityDiscoveryValue
        info[CarrierReceiverDiscoveryInfo.instanceStartedAtKey] = receiverInstanceStartedAt
        return info
    }

    private var receiverAvailabilityDiscoveryValue: String {
        isReceiverBusyForDiscovery ? CarrierReceiverDiscoveryInfo.busyValue : CarrierReceiverDiscoveryInfo.availableValue
    }

    private var isReceiverBusyForDiscovery: Bool {
        !connectedPeerNames().isEmpty || activeReceiverPeerName != nil
    }

    private func refreshReceiverDiscoveryInfoIfAdvertising() {
        guard case .receiver = role, advertiser != nil else {
            return
        }

        startAdvertising()
        recordDiagnosticEvent(
            "advertiser.discoveryInfo.updated",
            message: "availability=\(receiverAvailabilityDiscoveryValue)"
        )
    }

    private func rememberDiscoveredPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]?) -> (identity: PeerDiscoveryIdentity, accepted: Bool) {
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: discoveryInfo)
        let accepted = shouldAcceptDiscoveredPeer(identity: identity, discoveryInfo: discoveryInfo)
        if accepted {
            remember(identity, for: peerID)
            knownPeerIDs[identity.key] = peerID
            if let freshness = Self.receiverInstanceStartedAt(from: discoveryInfo) {
                peerDiscoveryFreshness[identity.key] = freshness
            }
        }

        if let index = discoveredPeers.firstIndex(where: { $0.id == identity.key }) {
            if accepted, discoveredPeers[index].displayName != identity.displayName {
                discoveredPeers[index] = CarrierPeer(id: identity.key, displayName: identity.displayName)
                updateDiagnostics()
            }
        } else if accepted {
            discoveredPeers.append(CarrierPeer(id: identity.key, displayName: identity.displayName))
            updateDiagnostics()
        }

        return (identity, accepted)
    }

    private func rememberAndInvite(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        let rememberedPeer = rememberDiscoveredPeer(peerID, discoveryInfo: discoveryInfo)
        guard rememberedPeer.accepted else {
            recordDiagnosticEvent(
                "browser.ignoredStalePeer",
                message: "Ignored older discovery record \(rememberedPeer.identity.diagnosticSummary)",
                peerName: rememberedPeer.identity.displayName
            )
            return
        }

        inviteRememberedPeer(peerID, identity: rememberedPeer.identity)
    }

    private func scheduleRememberAndInvite(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        let rememberedPeer = rememberDiscoveredPeer(peerID, discoveryInfo: discoveryInfo)
        guard rememberedPeer.accepted else {
            recordDiagnosticEvent(
                "browser.ignoredStalePeer",
                message: "Ignored older discovery record \(rememberedPeer.identity.diagnosticSummary)",
                peerName: rememberedPeer.identity.displayName
            )
            return
        }

        pendingPeerInviteTasks[rememberedPeer.identity.key]?.cancel()
        let identityKey = rememberedPeer.identity.key
        pendingPeerInviteTasks[identityKey] = Task.detached { [weak self, discoveryInviteDelay] in
            do {
                try await Task.sleep(for: discoveryInviteDelay)
            } catch {
                return
            }

            await self?.finishPendingPeerInvite(identityKey: identityKey)
        }
    }

    private func finishPendingPeerInvite(identityKey: String) {
        pendingPeerInviteTasks[identityKey] = nil
        guard let peerID = knownPeerIDs[identityKey] else {
            return
        }

        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil)
        inviteRememberedPeer(peerID, identity: identity)
    }

    private func inviteRememberedPeer(_ peerID: MCPeerID, identity: PeerDiscoveryIdentity) {
        guard !invitedPeerIDs.contains(identity.key), session.connectedPeers.isEmpty else {
            logger.debug("Skipping invite peer=\(identity.displayName, privacy: .public) alreadyInvited=\(self.invitedPeerIDs.contains(identity.key), privacy: .public) connectedCount=\(self.session.connectedPeers.count, privacy: .public)")
            recordDiagnosticEvent("browser.inviteSkipped", message: "alreadyInvited=\(invitedPeerIDs.contains(identity.key)) connectedCount=\(session.connectedPeers.count) \(identity.diagnosticSummary)", peerName: identity.displayName)
            return
        }

        invitedPeerIDs.insert(identity.key)
        let attempt = (connectionAttemptCounts[identity.key] ?? 0) + 1
        connectionAttemptCounts[identity.key] = attempt
        cancelSearchTimeout()
        connectingPeerName = identity.displayName
        connectingPeerIdentityKey = identity.key
        connectionState = .connecting(peerID.displayName)
        scheduleConnectionTimeout(for: identity)
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: inviteTimeout)
        recordDiagnosticEvent("browser.invitePeer", message: "Invited peer attempt \(attempt)/\(maxConnectionAttempts) \(identity.diagnosticSummary)", peerName: identity.displayName)
        logger.info("Invited peer=\(identity.displayName, privacy: .public)")
    }

    private func handleBusyDiscoveredPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]?) {
        let rememberedPeer = rememberDiscoveredPeer(peerID, discoveryInfo: discoveryInfo)
        let identity = rememberedPeer.identity
        guard rememberedPeer.accepted else {
            recordDiagnosticEvent(
                "browser.ignoredStaleBusyPeer",
                message: "Ignored older busy discovery record \(identity.diagnosticSummary)",
                peerName: identity.displayName
            )
            return
        }

        pendingPeerInviteTasks[identity.key]?.cancel()
        pendingPeerInviteTasks[identity.key] = nil
        let isCurrentConnectionAttempt = connectingPeerIdentityKey == identity.key
        if isCurrentConnectionAttempt {
            cancelConnectionTimeout()
            connectingPeerName = nil
            connectingPeerIdentityKey = nil
        }
        invitedPeerIDs.remove(identity.key)
        lastErrorMessage = nil
        if case .failed = connectionState {
            connectionState = .searching
        }
        recordDiagnosticEvent(
            "browser.foundBusyPeer",
            message: "Receiver advertised busy availability \(identity.diagnosticSummary)",
            peerName: identity.displayName
        )
    }

    private func handleLostPeer(_ peerID: MCPeerID) {
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil)
        logger.info("Lost peer=\(identity.displayName, privacy: .public)")
        let lostPeerIsCurrentKnownPeer = knownPeerIDs[identity.key].map(ObjectIdentifier.init) == ObjectIdentifier(peerID)
        if lostPeerIsCurrentKnownPeer || knownPeerIDs[identity.key] == nil {
            discoveredPeers.removeAll { $0.id == identity.key }
        }
        peerIdentityKeysByObject[ObjectIdentifier(peerID)] = nil
        if lostPeerIsCurrentKnownPeer {
            knownPeerIDs[identity.key] = nil
            peerDiscoveryFreshness[identity.key] = nil
            invitedPeerIDs.remove(identity.key)
            connectionAttemptCounts[identity.key] = nil
            pendingPeerInviteTasks[identity.key]?.cancel()
            pendingPeerInviteTasks[identity.key] = nil
            peerDisplayNamesByIdentity[identity.key] = nil
        }
        if knownPeerIDs.isEmpty {
            cancelConnectionRetry()
        }
        recordDiagnosticEvent("browser.lostPeer", message: "Lost peer \(identity.diagnosticSummary)", peerName: identity.displayName)
    }

    private func handleSessionState(_ state: MCSessionState, peerID: MCPeerID) {
        logger.info("Session state peer=\(peerID.displayName, privacy: .public) state=\(self.sessionStateName(state), privacy: .public)")
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil)

        switch state {
        case .connected:
            knownPeerIDs[identity.key] = peerID
            cancelSearchTimeout()
            cancelConnectionTimeout()
            cancelConnectionRetry()
            connectingPeerName = nil
            connectingPeerIdentityKey = nil
            lastErrorMessage = nil
            connectionAttemptCounts[identity.key] = nil
            connectionState = .connected(identity.displayName)
            if case .receiver = role {
                activeReceiverPeerName = identity.displayName
                refreshReceiverDiscoveryInfoIfAdvertising()
            }
            recordDiagnosticEvent("session.connected", message: "Session connected \(identity.diagnosticSummary)", peerName: identity.displayName)
        case .connecting:
            knownPeerIDs[identity.key] = peerID
            cancelSearchTimeout()
            cancelConnectionRetry()
            connectingPeerName = identity.displayName
            connectingPeerIdentityKey = identity.key
            scheduleConnectionTimeout(for: identity)
            connectionState = .connecting(identity.displayName)
            recordDiagnosticEvent("session.connecting", message: "Session connecting \(identity.diagnosticSummary)", peerName: identity.displayName)
        case .notConnected:
            let previousState = connectionState
            invitedPeerIDs.remove(identity.key)
            cancelConnectionTimeout()
            connectingPeerName = nil
            connectingPeerIdentityKey = nil
            var shouldRequestReceiverRebuild = false

            if case .receiver = role {
                shouldRequestReceiverRebuild = Self.receiverNeedsServiceRebuildAfterNotConnected(from: previousState)
                if activeReceiverPeerName == identity.displayName {
                    activeReceiverPeerName = nil
                }
                connectionState = .advertising
                if shouldRequestReceiverRebuild {
                    refreshReceiverDiscoveryInfoIfAdvertising()
                }
            } else if case .connected = previousState {
                replaceSession(reason: "session.resetAfterNotConnected", peerName: identity.displayName)
                returnToSearchingAfterConnectionAttempt()
            } else if case .connecting = previousState {
                replaceSession(reason: "session.resetAfterNotConnected", peerName: identity.displayName)
                returnToSearchingAfterConnectionAttempt()
            } else if case .reconnecting = previousState {
                replaceSession(reason: "session.resetAfterNotConnected", peerName: identity.displayName)
                returnToSearchingAfterConnectionAttempt()
            }
            recordDiagnosticEvent("session.notConnected", message: "Previous state: \(previousState.displayText) \(identity.diagnosticSummary)", peerName: identity.displayName)
            if shouldRequestReceiverRebuild {
                recordDiagnosticEvent(
                    "receiver.rebuildRequested",
                    message: "Receiver session ended from \(previousState.displayText); requesting service rebuild.",
                    peerName: identity.displayName
                )
                receiverSessionInvalidatedHandler?(identity.displayName, previousState)
            }
        @unknown default:
            connectionState = .failed("Unknown connection state")
            recordDiagnosticEvent("session.unknownState", message: "Unknown connection state", peerName: identity.displayName)
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

    private func scheduleConnectionTimeout(for identity: PeerDiscoveryIdentity) {
        cancelConnectionTimeout()

        connectionTimeoutTask = Task { @MainActor [weak self, connectionTimeout] in
            do {
                try await Task.sleep(for: connectionTimeout)
            } catch {
                return
            }

            self?.connectionTimeoutTask = nil
            self?.handleConnectionTimeout(for: identity)
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

    private func cancelPendingPeerInvites() {
        for task in pendingPeerInviteTasks.values {
            task.cancel()
        }
        pendingPeerInviteTasks = [:]
    }

    private func retryKnownPeer() {
        guard case .sender = role,
              connectionState.isWaitingToRetryKnownPeer,
              session.connectedPeers.isEmpty,
              let knownPeer = nextKnownPeer() else {
            return
        }

        knownPeerIDs[knownPeer.identity.key] = nil
        peerDiscoveryFreshness[knownPeer.identity.key] = nil
        pendingPeerInviteTasks[knownPeer.identity.key]?.cancel()
        pendingPeerInviteTasks[knownPeer.identity.key] = nil
        invitedPeerIDs.remove(knownPeer.identity.key)
        discoveredPeers.removeAll { $0.id == knownPeer.identity.key }
        peerDisplayNamesByIdentity[knownPeer.identity.key] = nil
        updateDiagnostics()
        recordDiagnosticEvent(
            "browser.retryKnownPeer",
            message: "Refreshing known peer discovery before retry \(knownPeer.identity.diagnosticSummary)",
            peerName: knownPeer.identity.displayName
        )
#if DEBUG
        if usesSimulatedDiscoveryForTesting {
            connectionState = .searching
            scheduleSearchTimeout()
            updateDiagnostics()
            return
        }
#endif
        startBrowsing()
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
        recordDiagnosticEvent("search.timeout", message: "Search timed out after \(String(describing: searchTimeout))")
        refreshBrowsingAfterSearchTimeout()
    }

    private func refreshBrowsingAfterSearchTimeout() {
        cancelSearchTimeout()
#if DEBUG
        if usesSimulatedDiscoveryForTesting || browser == nil {
            connectionState = .searching
            scheduleSearchTimeout()
            updateDiagnostics()
            return
        }
#endif
        startBrowsing()
    }

    private func handleConnectionTimeout(for identity: PeerDiscoveryIdentity) {
        guard case .sender = role,
              case .connecting(let currentPeerName) = connectionState,
              currentPeerName == identity.displayName,
              connectingPeerIdentityKey == identity.key,
              session.connectedPeers.isEmpty else {
            return
        }

        logger.info("Connection timed out peer=\(identity.displayName, privacy: .public) after \(String(describing: self.connectionTimeout), privacy: .public)")
        invitedPeerIDs.remove(identity.key)
        connectingPeerName = nil
        connectingPeerIdentityKey = nil
        replaceSession(reason: "session.resetForRetry", peerName: identity.displayName)
        returnToSearchingAfterConnectionAttempt()
        recordDiagnosticEvent(
            "connection.timeout",
            message: "Connection timed out after \(String(describing: connectionTimeout)) \(identity.diagnosticSummary)",
            peerName: identity.displayName
        )
    }

    private func returnToSearchingAfterConnectionAttempt() {
        cancelConnectionTimeout()
        if session.connectedPeers.isEmpty,
           let knownPeer = nextKnownPeer() {
            guard (connectionAttemptCounts[knownPeer.identity.key] ?? 0) < maxConnectionAttempts else {
                failAfterConnectionRetryBudget(for: knownPeer.identity)
                return
            }

            connectionState = .reconnecting(knownPeer.identity.displayName)
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

    private func failAfterConnectionRetryBudget(for identity: PeerDiscoveryIdentity) {
        cancelSearchTimeout()
        cancelConnectionTimeout()
        cancelConnectionRetry()
        stopBrowsing()
        invitedPeerIDs.remove(identity.key)
        connectingPeerName = nil
        connectingPeerIdentityKey = nil
        lastErrorMessage = "Could not connect to \(identity.displayName)."
        connectionState = .failed(lastErrorMessage ?? "Could not connect.")
        recordDiagnosticEvent(
            "connection.retryBudgetExceeded",
            message: "Stopped after \(connectionAttemptCounts[identity.key] ?? maxConnectionAttempts) connection attempts \(identity.diagnosticSummary)",
            peerName: identity.displayName
        )
    }

#if DEBUG
    func startSearchingForTesting() {
        connectionState = .searching
        scheduleSearchTimeout()
    }

    func simulateFoundPeerForTesting(_ peerID: MCPeerID, discoveryInfo: [String: String]? = nil) {
        usesSimulatedDiscoveryForTesting = true
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: discoveryInfo)
        recordDiagnosticEvent("browser.foundPeer", message: "Found peer \(identity.diagnosticSummary)", peerName: identity.displayName)
        if Self.isBusyReceiverDiscoveryInfo(discoveryInfo) {
            handleBusyDiscoveredPeer(peerID, discoveryInfo: discoveryInfo)
        } else {
            rememberAndInvite(peerID, discoveryInfo: discoveryInfo)
        }
    }

    func simulateBrowserFoundPeerForTesting(_ peerID: MCPeerID, discoveryInfo: [String: String]? = nil) {
        usesSimulatedDiscoveryForTesting = true
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: discoveryInfo)
        recordDiagnosticEvent("browser.foundPeer", message: "Found peer \(identity.diagnosticSummary)", peerName: identity.displayName)
        if Self.isBusyReceiverDiscoveryInfo(discoveryInfo) {
            handleBusyDiscoveredPeer(peerID, discoveryInfo: discoveryInfo)
        } else {
            scheduleRememberAndInvite(peerID, discoveryInfo: discoveryInfo)
        }
    }

    func simulateLostPeerForTesting(_ peerID: MCPeerID) {
        usesSimulatedDiscoveryForTesting = true
        handleLostPeer(peerID)
    }

    func simulateSessionStateForTesting(_ state: MCSessionState, peerID: MCPeerID) {
        handleSessionState(state, peerID: peerID)
    }

    var discoveryInfoForTesting: [String: String]? {
        receiverDiscoveryInfo
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
            invitedPeers: invitedPeerDisplayNames(),
            connectedPeers: connectedPeerNames(),
            lastErrorMessage: lastErrorMessage
        )
    }

    private func recordDiagnosticEvent(_ name: String, message: String, peerName: String? = nil) {
        var updated = diagnostics.updating(
            connectionState: connectionState,
            discoveredPeers: discoveredPeers.map(\.displayName).sorted(),
            invitedPeers: invitedPeerDisplayNames(),
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

    nonisolated private func connectedPeerNames() -> [String] {
        session.connectedPeers.map(\.displayName).sorted()
    }

    nonisolated private func shouldRejectInvitationFromPeer(named peerName: String) -> Bool {
        let connectedPeerNames = connectedPeerNames()
        if !connectedPeerNames.isEmpty {
            return !connectedPeerNames.contains(peerName)
        }

        if let connectedPeerName = activeReceiverPeerName {
            return connectedPeerName != peerName
        }

        return false
    }

    nonisolated private func shouldReuseReceiverSessionForInvitation(from peerName: String) -> Bool {
        if connectedPeerNames().contains(peerName) {
            return true
        }

        return activeReceiverPeerName == peerName
    }

    private func isCurrentBrowser(_ browser: MCNearbyServiceBrowser) -> Bool {
        self.browser === browser
    }

    private static func isBusyReceiverDiscoveryInfo(_ info: [String: String]?) -> Bool {
        info?[CarrierReceiverDiscoveryInfo.availabilityKey] == CarrierReceiverDiscoveryInfo.busyValue
    }

    private static func receiverInstanceStartedAt(from discoveryInfo: [String: String]?) -> Double? {
        guard let value = discoveryInfo?[CarrierReceiverDiscoveryInfo.instanceStartedAtKey] else {
            return nil
        }

        return Double(value)
    }

    private func shouldAcceptDiscoveredPeer(identity: PeerDiscoveryIdentity, discoveryInfo: [String: String]?) -> Bool {
        guard let candidateFreshness = Self.receiverInstanceStartedAt(from: discoveryInfo) else {
            return peerDiscoveryFreshness[identity.key] == nil
        }

        guard let currentFreshness = peerDiscoveryFreshness[identity.key] else {
            return true
        }

        return candidateFreshness >= currentFreshness
    }

    private func peerDiscoveryIdentity(for peerID: MCPeerID, discoveryInfo: [String: String]?) -> PeerDiscoveryIdentity {
        if let discoveryInfo {
            return PeerDiscoveryIdentity(peerID: peerID, discoveryInfo: discoveryInfo)
        }

        let objectID = ObjectIdentifier(peerID)
        if let key = peerIdentityKeysByObject[objectID],
           let displayName = peerDisplayNamesByIdentity[key] {
            return PeerDiscoveryIdentity(key: key, displayName: displayName)
        }

        let identity = PeerDiscoveryIdentity(peerID: peerID, discoveryInfo: nil)
        remember(identity, for: peerID)
        return identity
    }

    private func remember(_ identity: PeerDiscoveryIdentity, for peerID: MCPeerID) {
        peerIdentityKeysByObject[ObjectIdentifier(peerID)] = identity.key
        peerDisplayNamesByIdentity[identity.key] = identity.displayName
    }

    private func nextKnownPeer() -> (identity: PeerDiscoveryIdentity, peerID: MCPeerID)? {
        knownPeerIDs
            .map { key, peerID in
                (
                    identity: PeerDiscoveryIdentity(
                        key: key,
                        displayName: peerDisplayNamesByIdentity[key] ?? peerID.displayName
                    ),
                    peerID: peerID
                )
            }
            .sorted {
                if $0.identity.displayName == $1.identity.displayName {
                    return $0.identity.key < $1.identity.key
                }

                return $0.identity.displayName < $1.identity.displayName
            }
            .first
    }

    private func invitedPeerDisplayNames() -> [String] {
        invitedPeerIDs
            .map { peerDisplayNamesByIdentity[$0] ?? $0 }
            .sorted()
    }
}

public enum CarrierServiceError: LocalizedError, Equatable, Sendable {
    case blankText
    case noConnectedPeer

    public var errorDescription: String? {
        switch self {
        case .blankText:
            "文本为空。"
        case .noConnectedPeer:
            "没有已连接设备。"
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

            let identity = self.peerDiscoveryIdentity(for: peerID, discoveryInfo: info)
            self.logger.info("Found peer=\(identity.displayName, privacy: .public)")
            self.recordDiagnosticEvent("browser.foundPeer", message: "Found peer \(identity.diagnosticSummary)", peerName: identity.displayName)
            if Self.isBusyReceiverDiscoveryInfo(info) {
                self.handleBusyDiscoveredPeer(peerID, discoveryInfo: info)
            } else {
                self.scheduleRememberAndInvite(peerID, discoveryInfo: info)
            }
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

            self.handleLostPeer(peerID)
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
        if shouldReuseReceiverSessionForInvitation(from: peerID.displayName) {
            let currentSession = session
            Task { @MainActor [weak self] in
                self?.recordDiagnosticEvent(
                    "advertiser.invitation.acceptedExistingSession",
                    message: "Accepted repeated invitation using current session",
                    peerName: peerID.displayName
                )
            }
            invitationHandler(true, currentSession)
            return
        }

        if shouldRejectInvitationFromPeer(named: peerID.displayName) {
            let connectedPeerName = activeReceiverPeerName ?? connectedPeerNames().joined(separator: ", ")
            Task { @MainActor [weak self] in
                self?.recordDiagnosticEvent(
                    "advertiser.invitation.rejectedBusy",
                    message: "Rejected invitation because receiver is already connected to \(connectedPeerName)",
                    peerName: peerID.displayName
                )
            }
            invitationHandler(false, nil)
            return
        }

        let previousPeerNames = session.connectedPeers.map(\.displayName).sorted()
        session.disconnect()
        session.delegate = nil
        let freshSession = Self.makeSession(peerID: self.peerID)
        freshSession.delegate = self
        session = freshSession
        activeReceiverPeerName = peerID.displayName

        Task { @MainActor [weak self] in
            self?.recordDiagnosticEvent(
                "advertiser.sessionResetForInvitation",
                message: "Created fresh session before accepting invitation. Previous connected peers: \(previousPeerNames.isEmpty ? "None" : previousPeerNames.joined(separator: ", "))",
                peerName: peerID.displayName
            )
            self?.recordDiagnosticEvent("advertiser.invitation.accepted", message: "Accepted invitation", peerName: peerID.displayName)
        }
        invitationHandler(true, freshSession)
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
