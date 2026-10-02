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
    public static let deviceIDKey = "deviceID"
    public static let roleKey = "role"
}

private struct PeerDiscoveryIdentity: Equatable {
    let key: String
    let displayName: String
    let diagnosticSummary: String

    init(peerID: MCPeerID, discoveryInfo: [String: String]?) {
        let advertisedName = discoveryInfo?[AndroidBonjourAdvertisement.macNameKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = advertisedName.flatMap { $0.isEmpty ? nil : $0 } ?? peerID.displayName
        if discoveryInfo == nil {
            self.init(key: "legacy=\(peerID.hash)", displayName: peerID.displayName)
        } else if discoveryInfo?[AndroidBonjourAdvertisement.macIDKey] != nil || discoveryInfo?[CarrierReceiverDiscoveryInfo.deviceIDKey] != nil {
            self.init(displayName: name, discoveryInfo: discoveryInfo)
        } else {
            self.init(key: "legacy=\(peerID.hash)", displayName: peerID.displayName)
        }
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

        if let deviceID = normalizedValue(CarrierReceiverDiscoveryInfo.deviceIDKey, from: discoveryInfo) {
            return ["deviceID=\(deviceID)"]
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
    /// Ordered by successful connection, with reconnects appended as new connections.
    @Published public private(set) var connectedPeers: [CarrierPeer] = []
    @Published public private(set) var connectingPeers: [CarrierPeer] = []
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
    private var peerSessions: [String: MCSession] = [:]
    private var peerStates: [String: MCSessionState] = [:]
    private var connectedPeerOrder: [String] = []
    private var peerRoles: [String: CarrierPeer.Role] = [:]
    private let localDeviceID: String
    private let localDisplayName: String
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var searchTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var connectionRetryTask: Task<Void, Never>?
    private var pendingPeerInviteTasks: [String: Task<Void, Never>] = [:]
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var peerDiscoveryFreshness: [String: Double] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var connectionAttemptCounts: [String: Int] = [:]
    private var peerIdentityKeysByObject: [ObjectIdentifier: String] = [:]
    private var peerDisplayNamesByIdentity: [String: String] = [:]
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?
    private let logger = Logger(subsystem: "ak22ak.typecarrier", category: "MultipeerCarrierService")
    private let maxDiagnosticEventCount = 50
#if DEBUG
    private var usesSimulatedDiscoveryForTesting = false
#endif

    public init(
        role: Role,
        displayName: String? = nil,
        deviceID: String? = nil,
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
        localDeviceID = deviceID ?? UUID().uuidString
        self.searchTimeout = searchTimeout
        self.connectionTimeout = connectionTimeout
        self.connectionRetryDelay = connectionRetryDelay
        self.inviteTimeout = inviteTimeout
        self.maxConnectionAttempts = max(1, maxConnectionAttempts)
        self.discoveryInviteDelay = discoveryInviteDelay
        self.receiverDiscoveryInfoExtras = receiverDiscoveryInfoExtras
        receiverInstanceStartedAt = String(Date().timeIntervalSince1970)
        diagnosticLogStore = diagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
        localDisplayName = CarrierDeviceIdentity.preferredDisplayName(
            customName: nil, systemName: displayName ?? ProcessInfo.processInfo.processName, fallbackName: "TypeCarrier"
        )
        let localPeerID = MCPeerID(displayName: CarrierDeviceIdentity.multipeerDisplayName(localDisplayName))
        peerID = localPeerID
        diagnostics = CarrierDiagnostics(
            role: Self.roleName(for: role),
            localPeerName: localDisplayName,
            serviceType: Self.serviceType
        )
        super.init()
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
        for session in peerSessions.values {
            session.delegate = nil
            session.disconnect()
        }
        peerSessions = [:]
        peerStates = [:]
        connectedPeerOrder = []
        connectingPeers = []
        peerRoles = [:]
        connectedPeers = []
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
        recordDiagnosticEvent("service.stop", message: "Stopped \(roleName)")
    }

    public func sendText(_ text: String) throws {
        guard CarrierPayload.canSend(text) else {
            throw CarrierServiceError.blankText
        }

        try send(.text(CarrierPayload(text: text)))
    }

    /// Compatibility entry point: never infer a target when several devices are connected.
    public func send(_ envelope: CarrierEnvelope) throws {
        guard connectedPeers.count == 1, let target = connectedPeers.first else {
            throw connectedPeers.isEmpty ? CarrierServiceError.noConnectedPeer : .targetRequired
        }
        try send(envelope, to: target.id)
    }

    public func send(_ envelope: CarrierEnvelope, to targetID: String) throws {
        guard let peer = connectedPeers.first(where: { $0.id == targetID }),
              let remote = knownPeerIDs[targetID], let session = peerSessions[targetID] else {
            throw CarrierServiceError.noConnectedPeer
        }
        let data = try CarrierCodec.encode(envelope)
#if DEBUG
        if let sendForTesting {
            try sendForTesting(data, [remote])
        } else {
            guard session.connectedPeers.contains(remote) else { throw CarrierServiceError.noConnectedPeer }
            try session.send(data, toPeers: [remote], with: .reliable)
        }
#else
        guard session.connectedPeers.contains(remote) else { throw CarrierServiceError.noConnectedPeer }
        try session.send(data, toPeers: [remote], with: .reliable)
#endif
        recordDiagnosticEvent("session.send", message: "Sent \(envelope.kind.rawValue) to \(targetID)", peerName: peer.displayName)
    }

    public func peerIdentity(for remote: MCPeerID) -> CarrierPeer {
        let identity = peerDiscoveryIdentity(for: remote, discoveryInfo: nil)
        return CarrierPeer(id: identity.key, displayName: identity.displayName, role: peerRoles[identity.key] ?? .unknown)
    }

    public func recordDiagnosticMarker(_ name: String, message: String, peerName: String? = nil) {
        recordDiagnosticEvent(name, message: message, peerName: peerName)
    }

    public func extendCurrentSearchTimeoutForResumeRecovery(to timeout: Duration) {
        guard case .sender = role, connectionState.isSearchTimeoutEligible, connectedPeers.isEmpty else {
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
        refreshAggregateState()
        browser.startBrowsingForPeers()
        if connectedPeers.isEmpty { scheduleSearchTimeout() }
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

    private func dropSession(for key: String) {
        if let session = peerSessions.removeValue(forKey: key) {
            session.delegate = nil
            session.disconnect()
        }
        peerStates[key] = nil
        refreshConnectedPeers()
    }

    private func refreshConnectedPeers() {
        connectedPeerOrder.removeAll { peerStates[$0] != .connected }
        connectingPeers = peerStates.compactMap { key, state in
            guard state == .connecting, let peer = knownPeerIDs[key] else { return nil }
            return CarrierPeer(id: key, displayName: peerDisplayNamesByIdentity[key] ?? peer.displayName, role: peerRoles[key] ?? .unknown)
        }.sorted { $0.id < $1.id }
        connectedPeers = connectedPeerOrder.compactMap { key in
            guard let peer = knownPeerIDs[key] else { return nil }
            return CarrierPeer(id: key, displayName: peerDisplayNamesByIdentity[key] ?? peer.displayName, role: peerRoles[key] ?? .unknown)
        }
    }

    private func refreshAggregateState() {
        refreshConnectedPeers()
        if !connectedPeers.isEmpty {
            connectionState = .connected(connectedPeers.map(\.displayName).joined(separator: ", "))
        } else if let key = peerStates.first(where: { $0.value == .connecting })?.key {
            connectionState = .connecting(peerDisplayNamesByIdentity[key] ?? key)
        } else if case .receiver = role {
            connectionState = .advertising
        } else {
            connectionState = .searching
        }
    }

    private var receiverDiscoveryInfo: [String: String]? {
        guard case .receiver = role else {
            return nil
        }

        var info = receiverDiscoveryInfoExtras
        info[CarrierReceiverDiscoveryInfo.availabilityKey] = CarrierReceiverDiscoveryInfo.availableValue
        info[CarrierReceiverDiscoveryInfo.roleKey] = "receiver"
        info[CarrierReceiverDiscoveryInfo.instanceStartedAtKey] = receiverInstanceStartedAt
        return info
    }

    private func rememberDiscoveredPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]?) -> (identity: PeerDiscoveryIdentity, accepted: Bool) {
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: discoveryInfo)
        let accepted = shouldAcceptDiscoveredPeer(identity: identity, discoveryInfo: discoveryInfo)
        if accepted {
            let newerInstance = Self.receiverInstanceStartedAt(from: discoveryInfo).map { $0 > (peerDiscoveryFreshness[identity.key] ?? 0) } ?? false
            if let previous = knownPeerIDs[identity.key], previous != peerID, newerInstance {
                cancelConnectionTimeout(for: identity.key)
                invitedPeerIDs.remove(identity.key)
                dropSession(for: identity.key)
            }
            remember(identity, for: peerID)
            if peerStates[identity.key] == nil || knownPeerIDs[identity.key] == peerID {
                knownPeerIDs[identity.key] = peerID
            }
            peerRoles[identity.key] = .receiver
            if let freshness = Self.receiverInstanceStartedAt(from: discoveryInfo) {
                peerDiscoveryFreshness[identity.key] = freshness
            }
        }

        if let index = discoveredPeers.firstIndex(where: { $0.id == identity.key }) {
            if accepted, discoveredPeers[index].displayName != identity.displayName {
                discoveredPeers[index] = CarrierPeer(id: identity.key, displayName: identity.displayName, role: .receiver)
                updateDiagnostics()
            }
        } else if accepted {
            discoveredPeers.append(CarrierPeer(id: identity.key, displayName: identity.displayName, role: .receiver))
            updateDiagnostics()
        }

        if accepted { refreshConnectedPeers() }
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
        guard !invitedPeerIDs.contains(identity.key), peerStates[identity.key] != .connected else {
            logger.debug("Skipping invite peer=\(identity.displayName, privacy: .public) alreadyInvited=\(self.invitedPeerIDs.contains(identity.key), privacy: .public) connectedCount=\(self.connectedPeers.count, privacy: .public)")
            recordDiagnosticEvent("browser.inviteSkipped", message: "alreadyInvited=\(invitedPeerIDs.contains(identity.key)) connectedCount=\(connectedPeers.count) \(identity.diagnosticSummary)", peerName: identity.displayName)
            return
        }

        invitedPeerIDs.insert(identity.key)
        let attempt = (connectionAttemptCounts[identity.key] ?? 0) + 1
        connectionAttemptCounts[identity.key] = attempt
        cancelSearchTimeout()
        peerStates[identity.key] = .connecting
        let session = Self.makeSession(peerID: self.peerID)
        session.delegate = self
        peerSessions[identity.key] = session
        refreshAggregateState()
        scheduleConnectionTimeout(for: identity)
        let context = try? JSONEncoder().encode(CarrierDeviceIdentity(displayName: localDisplayName, deviceID: localDeviceID))
        browser?.invitePeer(peerID, to: session, withContext: context, timeout: inviteTimeout)
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
        if peerStates[identity.key] == .connecting {
            cancelConnectionTimeout(for: identity.key)
        }
        invitedPeerIDs.remove(identity.key)
        if peerStates[identity.key] == .connecting { dropSession(for: identity.key) }
        refreshAggregateState()
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
        if lostPeerIsCurrentKnownPeer, peerStates[identity.key] == nil {
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
        let identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil)
        knownPeerIDs[identity.key] = peerID
        if peerRoles[identity.key] == nil { peerRoles[identity.key] = role == .sender ? .receiver : .sender }
        switch state {
        case .connected:
            if !connectedPeerOrder.contains(identity.key) {
                connectedPeerOrder.append(identity.key)
            }
            peerStates[identity.key] = .connected
            cancelConnectionTimeout(for: identity.key)
            invitedPeerIDs.remove(identity.key)
            connectionAttemptCounts[identity.key] = nil
            lastErrorMessage = nil
            refreshAggregateState()
            cancelSearchTimeout()
            recordDiagnosticEvent("session.connected", message: "Connected \(identity.diagnosticSummary)", peerName: identity.displayName)
        case .connecting:
            peerStates[identity.key] = .connecting
            scheduleConnectionTimeout(for: identity)
            refreshAggregateState()
            recordDiagnosticEvent("session.connecting", message: "Connecting \(identity.diagnosticSummary)", peerName: identity.displayName)
        case .notConnected:
            cancelConnectionTimeout(for: identity.key)
            invitedPeerIDs.remove(identity.key)
            dropSession(for: identity.key)
            refreshAggregateState()
            if case .sender = role { returnToSearchingAfterConnectionAttempt() }
            recordDiagnosticEvent("session.notConnected", message: "Disconnected only \(identity.diagnosticSummary)", peerName: identity.displayName)
        @unknown default:
            recordDiagnosticEvent("session.unknownState", message: "Unknown state", peerName: identity.displayName)
        }
    }

    private func acceptInvitation(from peerID: MCPeerID, context: Data?, reply: InvitationReply) {
        let sender = context.flatMap { try? JSONDecoder().decode(CarrierDeviceIdentity.self, from: $0) }
        let identity: PeerDiscoveryIdentity
        if let sender, let deviceID = sender.deviceID, !deviceID.isEmpty {
            identity = PeerDiscoveryIdentity(key: "deviceID=\(deviceID)", displayName: sender.displayName.isEmpty ? peerID.displayName : sender.displayName)
        } else {
            identity = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil)
        }
        if let previous = knownPeerIDs[identity.key], previous != peerID {
            dropSession(for: identity.key)
        }
        remember(identity, for: peerID)
        knownPeerIDs[identity.key] = peerID
        peerRoles[identity.key] = .sender
        if let existing = peerSessions[identity.key] {
            recordDiagnosticEvent("advertiser.invitation.acceptedExistingSession", message: "Accepted repeated invitation", peerName: peerID.displayName)
            reply.handler(true, existing)
            return
        }
        let session = Self.makeSession(peerID: self.peerID)
        session.delegate = self
        peerSessions[identity.key] = session
        peerStates[identity.key] = .connecting
        scheduleConnectionTimeout(for: identity)
        refreshAggregateState()
        recordDiagnosticEvent("advertiser.sessionResetForInvitation", message: "Created isolated peer session", peerName: peerID.displayName)
        recordDiagnosticEvent("advertiser.invitation.accepted", message: "Accepted invitation", peerName: peerID.displayName)
        reply.handler(true, session)
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
            try? send(.error(error.localizedDescription), to: peerIdentity(for: peerID).id)
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
        cancelConnectionTimeout(for: identity.key)
        connectionTimeoutTasks[identity.key] = Task { @MainActor [weak self, connectionTimeout] in
            do { try await Task.sleep(for: connectionTimeout) } catch { return }
            self?.connectionTimeoutTasks[identity.key] = nil
            self?.handleConnectionTimeout(for: identity)
        }
    }

    private func cancelConnectionTimeout(for key: String? = nil) {
        if let key {
            connectionTimeoutTasks.removeValue(forKey: key)?.cancel()
        } else {
            for task in connectionTimeoutTasks.values { task.cancel() }
            connectionTimeoutTasks = [:]
        }
    }

    private func scheduleConnectionRetry() {
        guard case .sender = role,
              nextKnownPeer() != nil else {
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
            refreshAggregateState()
            if connectedPeers.isEmpty { scheduleSearchTimeout() }
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
        guard case .sender = role, connectionState.isSearchTimeoutEligible, connectedPeers.isEmpty else {
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
        guard peerStates[identity.key] == .connecting else { return }
        invitedPeerIDs.remove(identity.key)
        dropSession(for: identity.key)
        refreshAggregateState()
        if case .receiver = role {
            recordDiagnosticEvent("connection.timeout", message: "Receiver connection timed out for \(identity.diagnosticSummary)", peerName: identity.displayName)
            return
        }
        recordDiagnosticEvent("session.resetForRetry", message: "Reset isolated peer session", peerName: identity.displayName)
        returnToSearchingAfterConnectionAttempt()
        if (connectionAttemptCounts[identity.key] ?? 0) >= maxConnectionAttempts {
            lastErrorMessage = "Could not connect to \(identity.displayName)."
            if connectedPeers.isEmpty && !peerStates.values.contains(.connecting) { connectionState = .failed(lastErrorMessage ?? "Connection failed") }
            recordDiagnosticEvent("connection.retryBudgetExceeded", message: "Stopped retrying only \(identity.diagnosticSummary)", peerName: identity.displayName)
        }
        recordDiagnosticEvent("connection.timeout", message: "Connection timed out for \(identity.diagnosticSummary)", peerName: identity.displayName)
    }

    private func returnToSearchingAfterConnectionAttempt() {
        refreshAggregateState()
        if connectedPeers.isEmpty, !peerStates.values.contains(.connecting), let knownPeer = nextKnownPeer() {
            connectionState = .reconnecting(knownPeer.identity.displayName)
        }
        if connectedPeers.isEmpty { scheduleSearchTimeout() }
        scheduleConnectionRetry()
        updateDiagnostics()
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

    func simulateInvitationForTesting(from peerID: MCPeerID, context: Data? = nil, reply: @escaping (Bool, MCSession?) -> Void) {
        acceptInvitation(from: peerID, context: context, reply: InvitationReply(reply))
    }

    var sendForTesting: ((Data, [MCPeerID]) throws -> Void)?

    func sessionForTesting(peerID: MCPeerID) -> MCSession? {
        peerSessions[peerIdentity(for: peerID).id]
    }

    func simulateSessionStateForTesting(_ state: MCSessionState, peerID: MCPeerID) {
        let key = peerDiscoveryIdentity(for: peerID, discoveryInfo: nil).key
        if state != .notConnected, peerSessions[key] == nil {
            let session = Self.makeSession(peerID: self.peerID)
            session.delegate = self
            peerSessions[key] = session
        }
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

    private func connectedPeerNames() -> [String] {
        connectedPeers.map(\.displayName).sorted()
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

        if let entry = knownPeerIDs.first(where: { $0.value == peerID }) {
            let identity = PeerDiscoveryIdentity(key: entry.key, displayName: peerDisplayNamesByIdentity[entry.key] ?? peerID.displayName)
            remember(identity, for: peerID)
            return identity
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
            .filter { peerStates[$0.key] != .connected && peerStates[$0.key] != .connecting &&
                (connectionAttemptCounts[$0.key] ?? 0) < maxConnectionAttempts }
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
    case targetRequired

    public var errorDescription: String? {
        switch self {
        case .blankText:
            "文本为空。"
        case .noConnectedPeer:
            "没有已连接设备。"
        case .targetRequired:
            "请选择发送目标。"
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
        let reply = InvitationReply(invitationHandler)
        Task { @MainActor [weak self] in
            guard let self else { reply.handler(false, nil); return }
            guard self.advertiser === advertiser else { reply.handler(false, nil); return }
            self.acceptInvitation(from: peerID, context: context, reply: reply)
        }
    }

    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.advertiser === advertiser else { return }
            self.fail(error.localizedDescription)
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

            guard let owner = self.peerSessions.first(where: { $0.value === session }),
                  self.knownPeerIDs[owner.key] == peerID else {
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
            guard let self,
                  let owner = self.peerSessions.first(where: { $0.value === session }),
                  self.knownPeerIDs[owner.key] == peerID else {
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

private final class InvitationReply: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void
    init(_ handler: @escaping (Bool, MCSession?) -> Void) { self.handler = handler }
}
