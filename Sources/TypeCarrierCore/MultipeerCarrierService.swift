import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

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
    private nonisolated(unsafe) let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var knownPeerIDs: [String: MCPeerID] = [:]
    private var invitedPeerIDs: Set<String> = []
    private var envelopeHandler: ((CarrierEnvelope, MCPeerID) -> Void)?

    public init(role: Role, displayName: String? = nil) {
        self.role = role
        peerID = MCPeerID(displayName: displayName ?? ProcessInfo.processInfo.processName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public func start(onEnvelope: ((CarrierEnvelope, MCPeerID) -> Void)? = nil) {
        envelopeHandler = onEnvelope

        switch role {
        case .sender:
            startBrowsing()
        case .receiver:
            startAdvertising()
        }
    }

    public func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session.disconnect()
        connectionState = .idle
        discoveredPeers = []
        knownPeerIDs = [:]
        invitedPeerIDs = []
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
    }

    private func startAdvertising() {
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        connectionState = .advertising
        advertiser.startAdvertisingPeer()
    }

    private func rememberAndInvite(_ peerID: MCPeerID) {
        let key = peerID.displayName
        knownPeerIDs[key] = peerID

        if !discoveredPeers.contains(where: { $0.id == key }) {
            discoveredPeers.append(CarrierPeer(peerID: peerID))
        }

        guard !invitedPeerIDs.contains(key), session.connectedPeers.isEmpty else {
            return
        }

        invitedPeerIDs.insert(key)
        connectionState = .connecting(peerID.displayName)
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    private func handleSessionState(_ state: MCSessionState, peerID: MCPeerID) {
        switch state {
        case .connected:
            connectionState = .connected(peerID.displayName)
        case .connecting:
            connectionState = .connecting(peerID.displayName)
        case .notConnected:
            if case .receiver = role {
                connectionState = .advertising
            } else {
                connectionState = .searching
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
        lastErrorMessage = message
        connectionState = .failed(message)
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
            self?.rememberAndInvite(peerID)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.knownPeerIDs[peerID.displayName] = nil
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
