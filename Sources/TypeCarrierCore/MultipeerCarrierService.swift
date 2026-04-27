import Combine
import Foundation
@preconcurrency import MultipeerConnectivity
import os

extension MCPeerID: @unchecked @retroactive Sendable {}
extension MCSessionState: @unchecked @retroactive Sendable {}

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

    private let role: Role
    private let peerID: MCPeerID
    private let searchTimeout: Duration
    private let connectionTimeout: Duration
    private nonisolated(unsafe) let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var searchTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var connectingPeerName: String?
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?
    private let logger = Logger(subsystem: "ak22ak.typecarrier", category: "MultipeerCarrierService")

    public init(
        role: Role,
        displayName: String? = nil,
        searchTimeout: Duration = .seconds(30),
        connectionTimeout: Duration = .seconds(15)
    ) {
        self.role = role
        self.searchTimeout = searchTimeout
        self.connectionTimeout = connectionTimeout
        peerID = MCPeerID(displayName: displayName ?? ProcessInfo.processInfo.processName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public func start(onEnvelope: ((CarrierEnvelope, MCPeerID) -> Void)? = nil) {
        envelopeHandler = onEnvelope
        logger.info("Starting service role=\(self.roleName, privacy: .public)")

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
        connectionState = .idle
        discoveredPeers = []
        knownPeerIDs = [:]
        invitedPeerIDs = []
        connectingPeerName = nil
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
    }

    private func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
        connectionState = .searching
        browser.startBrowsingForPeers()
        scheduleSearchTimeout()
        logger.info("Started browsing for peers")
    }

    private func startAdvertising() {
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        connectionState = .advertising
        advertiser.startAdvertisingPeer()
        logger.info("Started advertising peer")
    }

    private func rememberAndInvite(_ peerID: MCPeerID) {
        let key = peerID.displayName
        knownPeerIDs[key] = peerID

        if !discoveredPeers.contains(where: { $0.id == key }) {
            discoveredPeers.append(CarrierPeer(peerID: peerID))
        }

        guard !invitedPeerIDs.contains(key), session.connectedPeers.isEmpty else {
            logger.debug("Skipping invite peer=\(key, privacy: .public) alreadyInvited=\(self.invitedPeerIDs.contains(key), privacy: .public) connectedCount=\(self.session.connectedPeers.count, privacy: .public)")
            return
        }

        invitedPeerIDs.insert(key)
        cancelSearchTimeout()
        connectingPeerName = key
        connectionState = .connecting(peerID.displayName)
        scheduleConnectionTimeout(for: key)
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        logger.info("Invited peer=\(key, privacy: .public)")
    }

    private func handleSessionState(_ state: MCSessionState, peerID: MCPeerID) {
        logger.info("Session state peer=\(peerID.displayName, privacy: .public) state=\(self.sessionStateName(state), privacy: .public)")

        switch state {
        case .connected:
            knownPeerIDs[peerID.displayName] = peerID
            cancelSearchTimeout()
            cancelConnectionTimeout()
            connectingPeerName = nil
            connectionState = .connected(peerID.displayName)
        case .connecting:
            knownPeerIDs[peerID.displayName] = peerID
            cancelSearchTimeout()
            connectingPeerName = peerID.displayName
            scheduleConnectionTimeout(for: peerID.displayName)
            connectionState = .connecting(peerID.displayName)
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
            }
        @unknown default:
            connectionState = .failed("Unknown connection state")
        }
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        do {
            let envelope = try CarrierCodec.decode(data)
            lastReceivedEnvelope = envelope
            envelopeHandler?(envelope, peerID)

            if envelope.kind == .text, let payloadID = envelope.payload?.id {
                try? send(.ack(payloadID))
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            try? send(.error(error.localizedDescription))
        }
    }

    private func fail(_ message: String) {
        logger.error("Service failed message=\(message, privacy: .public)")
        cancelSearchTimeout()
        cancelConnectionTimeout()
        lastErrorMessage = message
        connectionState = .failed(message)
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

    private func handleSearchTimeout() {
        guard case .sender = role, case .searching = connectionState, session.connectedPeers.isEmpty else {
            return
        }

        logger.info("Search timed out after \(String(describing: self.searchTimeout), privacy: .public)")
        stopBrowsingAndDisconnect()
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
    }

    private func returnToSearchingAfterConnectionAttempt() {
        cancelConnectionTimeout()
        connectionState = .searching
        scheduleSearchTimeout()
    }

    private func stopBrowsingAndDisconnect() {
        cancelSearchTimeout()
        cancelConnectionTimeout()
        browser?.stopBrowsingForPeers()
        connectionState = .idle
    }

#if DEBUG
    func startSearchingForTesting() {
        connectionState = .searching
        scheduleSearchTimeout()
    }
#endif

    private var roleName: String {
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
            self?.rememberAndInvite(peerID)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.logger.info("Lost peer=\(peerID.displayName, privacy: .public)")
            self?.knownPeerIDs[peerID.displayName] = nil
            self?.invitedPeerIDs.remove(peerID.displayName)
            self?.discoveredPeers.removeAll { $0.id == peerID.displayName }
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
