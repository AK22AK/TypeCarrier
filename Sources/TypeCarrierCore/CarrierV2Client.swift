import Foundation
import Network

/// A receiver seen on the network that this device has not paired with.
public struct CarrierV2DiscoveredReceiver: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
}

public enum CarrierV2PairingState: Equatable, Sendable {
    case connecting(receiverName: String)
    /// Show `code`; the person confirms on the receiver.
    case comparing(code: String, receiverName: String)
    case failed(String)
}

/// The sending side of protocol v2. It keeps one session to each paired receiver it can reach:
/// on start it dials the receiver's last known address right away and browses Bonjour in parallel,
/// then reconnects with backoff whenever a session drops while running. Its surface mirrors what the
/// iOS composer used from the earlier Multipeer sender, so the composer only swapped the type.
///
/// Searching is bounded: when nothing connects within `searchTimeout`, it stops browsing and
/// dialing and reports `searchTimedOut` until the person retries. A search hold (the Mac list)
/// keeps it searching for as long as the hold lasts.
@MainActor
public final class CarrierV2Client: ObservableObject {
    public typealias EnvelopeHandler = (CarrierEnvelope, CarrierPeer) -> Void

    public static let serviceType = "_typecarrier-v2._tcp"
    public static let deviceIDTXTKey = "id"
    /// A cached address that does not answer this fast is probably stale; fall back to Bonjour.
    static let cachedEndpointTimeout: Duration = .milliseconds(1_200)
    static let retryDelays: [Duration] = [.milliseconds(300), .seconds(1), .seconds(2), .seconds(4)]
    public nonisolated static let defaultSearchTimeout: Duration = .seconds(15)
    public nonisolated static let searchTimedOutMessage = "未找到设备"
    private static let endpointCacheKey = "CarrierV2LastEndpoints"

    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var connectedPeers: [CarrierPeer] = []
    @Published public private(set) var connectingPeers: [CarrierPeer] = []
    @Published public private(set) var availableReceivers: [CarrierV2DiscoveredReceiver] = []
    @Published public private(set) var pairedReceivers: [CarrierV2PairedDevice] = []
    @Published public private(set) var pairing: CarrierV2PairingState?
    @Published public private(set) var diagnostics: CarrierDiagnostics
    /// True after a search ran out without connecting; browsing and dialing are stopped.
    @Published public private(set) var searchTimedOut = false

    public var diagnosticLogFileURL: URL? { diagnosticLogStore?.fileURL }

    private let displayName: String
    private let deviceID: String
    private let platform: CarrierHello.Platform
    private let trustStore: CarrierV2TrustStore
    private let defaults: UserDefaults
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private var envelopeHandler: EnvelopeHandler?
    private var isRunning = false
    private var browser: NWBrowser?
    /// Bonjour endpoints by receiver device ID.
    private var browsedEndpoints: [String: (endpoint: NWEndpoint, name: String)] = [:]
    /// Live or in-flight session per paired receiver device ID.
    private var links: [String: CarrierV2Link] = [:]
    private var attemptTasks: [String: Task<Void, Never>] = [:]
    private var failureCounts: [String: Int] = [:]
    private var pairingLink: CarrierV2Link?
    private var events: [CarrierDiagnosticEvent] = []
    private let searchTimeout: Duration
    private var nextSearchTimeout: Duration?
    private var searchTimeoutTask: Task<Void, Never>?
    private var searchHolds = 0

    public init(
        displayName: String,
        deviceID: String,
        platform: CarrierHello.Platform = .iOS,
        trustStore: CarrierV2TrustStore = CarrierV2TrustStore(),
        defaults: UserDefaults = .standard,
        diagnosticLogFileURL: URL? = nil,
        searchTimeout: Duration = CarrierV2Client.defaultSearchTimeout
    ) {
        self.searchTimeout = searchTimeout
        self.displayName = displayName
        self.deviceID = deviceID
        self.platform = platform
        self.trustStore = trustStore
        self.defaults = defaults
        diagnosticLogStore = diagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
        diagnostics = CarrierDiagnostics(role: "sender.v2", localPeerName: displayName, serviceType: Self.serviceType)
        pairedReceivers = (try? trustStore.pairedDevices()) ?? []
    }

    // MARK: - Lifecycle

    public func start(onEnvelope: EnvelopeHandler? = nil) {
        envelopeHandler = onEnvelope
        guard !isRunning else { return }
        isRunning = true
        recordDiagnosticMarker("service.start", message: "Starting v2 sender.")
        beginSearch()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelSearchTimeout()
        nextSearchTimeout = nil
        searchTimedOut = false
        browser?.cancel()
        browser = nil
        browsedEndpoints = [:]
        attemptTasks.values.forEach { $0.cancel() }
        attemptTasks = [:]
        let closing = Array(links.values)
        links = [:]
        closing.forEach { $0.close() }
        cancelPairing()
        availableReceivers = []
        refreshState()
        recordDiagnosticMarker("service.stop", message: "Stopped v2 sender.")
    }

    /// Gives the search that is running now (or the next one) a longer deadline, used when the app
    /// comes back from the background and the network may still be waking up.
    public func extendCurrentSearchTimeoutForResumeRecovery(to timeout: Duration) {
        guard connectedPeers.isEmpty, !searchTimedOut else { return }
        nextSearchTimeout = timeout
        if searchTimeoutTask != nil {
            scheduleSearchTimeout()
        }
    }

    // MARK: - Search lifetime

    /// Starts a fresh search after it timed out. Does nothing while a search is already running.
    public func retrySearch() {
        guard isRunning else {
            start(onEnvelope: envelopeHandler)
            return
        }
        guard searchTimedOut else { return }
        recordDiagnosticMarker("v2.search.retry", message: "Searching again.")
        beginSearch()
    }

    /// Keeps searching (no timeout) until the matching `endSearchHold()`, and restarts a search
    /// that already timed out. The Mac list holds it so nearby Macs stay listed while it is open.
    public func beginSearchHold() {
        searchHolds += 1
        cancelSearchTimeout()
        if isRunning, searchTimedOut {
            recordDiagnosticMarker("v2.search.retry", message: "Searching again for the Mac list.")
            beginSearch()
        }
    }

    public func endSearchHold() {
        searchHolds = max(0, searchHolds - 1)
        refreshState()
    }

    private func beginSearch() {
        searchTimedOut = false
        failureCounts = [:]
        if browser == nil {
            startBrowser()
        }
        for receiver in pairedReceivers {
            connect(to: receiver.deviceID)
        }
        refreshState()
    }

    private func scheduleSearchTimeout() {
        searchTimeoutTask?.cancel()
        let timeout = nextSearchTimeout ?? searchTimeout
        searchTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.handleSearchTimeout(after: timeout)
        }
    }

    private func cancelSearchTimeout() {
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
    }

    private func handleSearchTimeout(after timeout: Duration) {
        searchTimeoutTask = nil
        // Something is dialing, pairing, or holding the search open: refreshState() arms a new
        // deadline once the client is back to plain searching.
        guard isRunning, links.isEmpty, pairingLink == nil, searchHolds == 0 else { return }
        nextSearchTimeout = nil
        searchTimedOut = true
        browser?.cancel()
        browser = nil
        attemptTasks.values.forEach { $0.cancel() }
        attemptTasks = [:]
        // Bonjour service endpoints are resolved when dialed, so the last results stay usable for
        // the nearby-Mac hint and for pairing while a new search warms up.
        recordDiagnosticMarker("v2.search.timeout", message: "Nothing connected within \(timeout); stopped searching.")
        refreshState()
    }

    // MARK: - Sending

    public func send(_ envelope: CarrierEnvelope, to targetID: String) throws {
        guard let deviceID = Self.deviceID(fromPeerID: targetID),
              let link = links[deviceID], link.isEstablished else {
            throw CarrierServiceError.noConnectedPeer
        }
        try link.send(envelope)
        if let payload = envelope.payload {
            recordDiagnosticMarker("v2.send", message: "Sent payload \(payload.id).", peerName: link.peer?.info.deviceName)
        }
    }

    // MARK: - Pairing

    public func pair(with receiver: CarrierV2DiscoveredReceiver) {
        guard let endpoint = browsedEndpoints[receiver.id]?.endpoint else {
            pairing = .failed("找不到 \(receiver.name)，请确认两台设备在同一网络。")
            return
        }
        cancelPairing()
        pairing = .connecting(receiverName: receiver.name)
        let link = makeLink(endpoint: endpoint, role: .initiator(.pair, remoteStaticKey: nil)) { [weak self] link, event in
            self?.handlePairing(event, link: link, receiverName: receiver.name)
        }
        pairingLink = link
        recordDiagnosticMarker("v2.pairing.start", message: "Pairing with \(endpoint).", peerName: receiver.name)
        link?.start()
    }

    public func cancelPairing() {
        let link = pairingLink
        pairingLink = nil
        link?.close()
        if case .failed = pairing {} else { pairing = nil }
        refreshState()
    }

    public func dismissPairingResult() {
        pairing = nil
    }

    public func unpair(deviceID: String) {
        try? trustStore.unpair(deviceID: deviceID)
        pairedReceivers = (try? trustStore.pairedDevices()) ?? []
        attemptTasks.removeValue(forKey: deviceID)?.cancel()
        links.removeValue(forKey: deviceID)?.close()
        removeCachedEndpoint(for: deviceID)
        refreshAvailableReceivers()
        refreshState()
    }

    private func handlePairing(_ event: CarrierV2Link.Event, link: CarrierV2Link, receiverName: String) {
        guard link === pairingLink else { return }
        switch event {
        case .tcpReady:
            break
        case .pairingCodeReady(let code, _):
            pairing = .comparing(code: code, receiverName: receiverName)
        case .established(let peer):
            try? trustStore.pair(CarrierV2PairedDevice(
                deviceID: peer.info.deviceID,
                deviceName: peer.info.deviceName,
                platform: peer.platform,
                publicKey: peer.publicKey,
                lastConnectedAt: Date()
            ))
            pairedReceivers = (try? trustStore.pairedDevices()) ?? []
            cacheEndpoint(of: link, for: peer.info.deviceID)
            recordDiagnosticMarker("v2.pairing.confirmed", message: "Paired.", peerName: peer.info.deviceName)
            pairing = nil
            pairingLink = nil
            // The pairing session is already authenticated; keep it as the live session.
            adopt(link, for: peer.info.deviceID)
            refreshAvailableReceivers()
        case .received:
            break
        case .closed(let reason, let networkError):
            pairingLink = nil
            let message: String
            switch reason {
            case .pairingRejected: message = "设备拒绝了配对，可以重新发起。"
            case .pairingNotOpen: message = "设备正在处理另一个配对请求，请稍后重试。"
            case .unsupportedVersion: message = "设备上的 TypeCarrier 版本不兼容，请把两边都更新到最新版。"
            case .handshakeFailed: message = "设备未响应或配对失败，请重试。"
            default: message = networkError.map { "连接失败：\($0)" } ?? "配对已取消。"
            }
            pairing = .failed(message)
            recordDiagnosticMarker("v2.pairing.failed", message: message, peerName: receiverName)
            refreshState()
        }
    }

    // MARK: - Connecting to paired receivers

    private func connect(to receiverID: String) {
        guard isRunning, links[receiverID] == nil, attemptTasks[receiverID] == nil,
              let receiver = pairedReceivers.first(where: { $0.deviceID == receiverID }) else { return }
        let delayIndex = failureCounts[receiverID].map { min($0 - 1, Self.retryDelays.count - 1) }
        attemptTasks[receiverID] = Task { @MainActor [weak self] in
            if let delayIndex {
                try? await Task.sleep(for: Self.retryDelays[delayIndex])
            }
            guard !Task.isCancelled, let self else { return }
            self.attemptTasks[receiverID] = nil
            await self.dial(receiver)
        }
    }

    private func dial(_ receiver: CarrierV2PairedDevice) async {
        guard isRunning, links[receiver.deviceID] == nil else { return }
        // Fast path: the last address that worked. Only Bonjour can tell us about a new one.
        if let cached = cachedEndpoint(for: receiver.deviceID) {
            if await attempt(receiver, endpoint: cached, source: "cache", tcpTimeout: Self.cachedEndpointTimeout) {
                return
            }
        }
        guard isRunning, links[receiver.deviceID] == nil else { return }
        if let browsed = browsedEndpoints[receiver.deviceID]?.endpoint {
            _ = await attempt(receiver, endpoint: browsed, source: "bonjour", tcpTimeout: nil)
            return
        }
        // Not visible yet. The browser will call connect(to:) when it appears.
        refreshState()
    }

    /// Starts a link and waits until its TCP connection is ready or gives up. Returns true when the
    /// link reached TCP ready (the handshake then continues in the background).
    private func attempt(_ receiver: CarrierV2PairedDevice, endpoint: NWEndpoint, source: String, tcpTimeout: Duration?) async -> Bool {
        let started = ContinuousClock.now
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            func resume(_ value: Bool) { once.resume(value) }
            let link = makeLink(endpoint: endpoint, role: .initiator(.connect, remoteStaticKey: receiver.publicKey)) { [weak self] link, event in
                if case .tcpReady = event {
                    self?.recordDiagnosticMarker(
                        "v2.connect.tcpReady",
                        message: "TCP ready via \(source) in \(Self.milliseconds(since: started)) ms.",
                        peerName: receiver.deviceName
                    )
                    resume(true)
                }
                if case .closed = event { resume(false) }
                self?.handle(event, link: link, receiverID: receiver.deviceID, started: started)
            }
            guard let link else {
                resume(false)
                return
            }
            links[receiver.deviceID] = link
            refreshState()
            recordDiagnosticMarker("v2.connect.start", message: "Dialing \(endpoint) via \(source).", peerName: receiver.deviceName)
            link.start()
            if let tcpTimeout {
                Task { @MainActor [weak self, weak link] in
                    try? await Task.sleep(for: tcpTimeout)
                    guard !once.hasResumed, let self, let link else { return }
                    self.recordDiagnosticMarker("v2.connect.cacheStale", message: "No TCP answer from \(endpoint) within \(tcpTimeout).", peerName: receiver.deviceName)
                    if self.links[receiver.deviceID] === link {
                        self.links[receiver.deviceID] = nil
                    }
                    resume(false)
                    link.close()
                }
            }
        }
    }

    private func adopt(_ link: CarrierV2Link, for receiverID: String) {
        links[receiverID]?.close()
        links[receiverID] = link
        failureCounts[receiverID] = nil
        let started = ContinuousClock.now
        link.onEvent = { [weak self] link, event in
            self?.handle(event, link: link, receiverID: receiverID, started: started)
        }
        refreshState()
    }

    private func handle(_ event: CarrierV2Link.Event, link: CarrierV2Link, receiverID: String, started: ContinuousClock.Instant) {
        switch event {
        case .tcpReady, .pairingCodeReady:
            break
        case .established(let peer):
            guard links[receiverID] === link else { return }
            failureCounts[receiverID] = nil
            cacheEndpoint(of: link, for: receiverID)
            try? trustStore.recordConnection(publicKey: peer.publicKey, deviceName: peer.info.deviceName)
            pairedReceivers = (try? trustStore.pairedDevices()) ?? []
            recordDiagnosticMarker(
                "v2.session.ready",
                message: "Session established in \(Self.milliseconds(since: started)) ms.",
                peerName: peer.info.deviceName
            )
            refreshState()
        case .received(let envelope):
            guard let peer = link.peer else { return }
            envelopeHandler?(envelope, Self.carrierPeer(peer.info))
        case .closed(let reason, let networkError):
            guard links[receiverID] === link else { return }
            links[receiverID] = nil
            let wasEstablished = link.peer != nil && reason != .handshakeFailed
            recordDiagnosticMarker(
                "v2.session.closed",
                message: "Closed: \(reason.map { "reason=\($0.rawValue)" } ?? "network=\(networkError ?? "cancelled")").",
                peerName: link.peer?.info.deviceName
            )
            if !wasEstablished {
                // A stale address may now belong to another machine; rediscover it through Bonjour.
                removeCachedEndpoint(for: receiverID)
            }
            if reason == .notPaired {
                // The receiver forgot this phone; stop dialing until the person pairs again.
                unpair(deviceID: receiverID)
                return
            }
            failureCounts[receiverID] = wasEstablished ? 1 : (failureCounts[receiverID] ?? 0) + 1
            refreshState()
            connect(to: receiverID)
        }
    }

    private func makeLink(
        endpoint: NWEndpoint,
        role: CarrierV2Session.Role,
        onEvent: @escaping (CarrierV2Link, CarrierV2Link.Event) -> Void
    ) -> CarrierV2Link? {
        guard let staticKey = try? trustStore.identityKey() else {
            connectionState = .failed("无法读取钥匙串中的设备密钥")
            return nil
        }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.connectionTimeout = 5
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 10
        }
        let session = CarrierV2Session(
            role: role,
            identity: CarrierV2Identity(
                staticKey: staticKey,
                info: CarrierV2DeviceInfo(deviceID: deviceID, deviceName: displayName),
                platform: platform,
                capabilities: [CarrierHello.capabilitySendText]
            )
        )
        return CarrierV2Link(connection: NWConnection(to: endpoint, using: parameters), session: session, onEvent: onEvent)
    }

    // MARK: - Bonjour

    private func startBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updateBrowseResults(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed(let error), .waiting(let error):
                    self.recordDiagnosticMarker("v2.browser.problem", message: error.localizedDescription)
                default:
                    break
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func updateBrowseResults(_ results: Set<NWBrowser.Result>) {
        var endpoints: [String: (endpoint: NWEndpoint, name: String)] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata, let id = txt[Self.deviceIDTXTKey], !id.isEmpty else { continue }
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            endpoints[id] = (result.endpoint, name)
        }
        let appeared = Set(endpoints.keys).subtracting(browsedEndpoints.keys)
        browsedEndpoints = endpoints
        refreshAvailableReceivers()
        for id in appeared where pairedReceivers.contains(where: { $0.deviceID == id }) {
            // A paired receiver just became visible: dial now instead of waiting out a retry delay.
            if links[id] == nil {
                attemptTasks.removeValue(forKey: id)?.cancel()
                failureCounts[id] = nil
                connect(to: id)
            }
        }
    }

    private func refreshAvailableReceivers() {
        let pairedIDs = Set(pairedReceivers.map(\.deviceID))
        availableReceivers = browsedEndpoints
            .filter { !pairedIDs.contains($0.key) }
            .map { CarrierV2DiscoveredReceiver(id: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
        diagnostics.discoveredPeers = browsedEndpoints.values.map(\.name).sorted()
    }

    // MARK: - Endpoint cache

    private func cachedEndpoint(for receiverID: String) -> NWEndpoint? {
        guard let value = (defaults.dictionary(forKey: Self.endpointCacheKey) as? [String: String])?[receiverID],
              let separator = value.lastIndex(of: ":"),
              let portNumber = UInt16(value[value.index(after: separator)...]),
              let port = NWEndpoint.Port(rawValue: portNumber) else { return nil }
        let host = String(value[..<separator])
        return .hostPort(host: NWEndpoint.Host(host), port: port)
    }

    private func cacheEndpoint(of link: CarrierV2Link, for receiverID: String) {
        guard case .hostPort(let host, let port)? = link.connection.currentPath?.remoteEndpoint else { return }
        let hostText: String
        switch host {
        case .ipv4(let address): hostText = "\(address)"
        case .ipv6(let address): hostText = "[\(address)]".replacingOccurrences(of: "%", with: "%25")
        case .name(let name, _): hostText = name
        @unknown default: return
        }
        // IPv6 link-local scopes and brackets do not round-trip reliably; cache IPv4 only.
        guard case .ipv4 = host else { return }
        var cache = defaults.dictionary(forKey: Self.endpointCacheKey) as? [String: String] ?? [:]
        cache[receiverID] = "\(hostText):\(port.rawValue)"
        defaults.set(cache, forKey: Self.endpointCacheKey)
    }

    private func removeCachedEndpoint(for receiverID: String) {
        var cache = defaults.dictionary(forKey: Self.endpointCacheKey) as? [String: String] ?? [:]
        cache[receiverID] = nil
        defaults.set(cache, forKey: Self.endpointCacheKey)
    }

    // MARK: - State

    private func refreshState() {
        let established = links.values.compactMap { link -> CarrierPeer? in
            guard link.isEstablished, let peer = link.peer else { return nil }
            return Self.carrierPeer(peer.info)
        }.sorted { $0.displayName < $1.displayName }
        let connecting = links.compactMap { id, link -> CarrierPeer? in
            guard !link.isEstablished else { return nil }
            let name = pairedReceivers.first { $0.deviceID == id }?.deviceName ?? id
            return CarrierPeer(id: Self.peerID(forDeviceID: id), displayName: name, role: .receiver)
        }.sorted { $0.displayName < $1.displayName }

        if connectedPeers != established { connectedPeers = established }
        if connectingPeers != connecting { connectingPeers = connecting }

        let state: ConnectionState
        if let first = established.first {
            state = .connected(first.displayName)
        } else if let first = connecting.first {
            state = .connecting(first.displayName)
        } else if isRunning, searchTimedOut {
            state = .failed(Self.searchTimedOutMessage)
        } else if isRunning {
            state = .searching
        } else {
            state = .idle
        }

        if !established.isEmpty {
            cancelSearchTimeout()
            nextSearchTimeout = nil
            if searchTimedOut, isRunning {
                // Paired from the last results after a timeout: keep browsing so a later drop
                // can find the receiver again.
                searchTimedOut = false
                if browser == nil { startBrowser() }
            }
        } else if state == .searching, searchTimeoutTask == nil, searchHolds == 0, pairingLink == nil {
            scheduleSearchTimeout()
        }
        if connectionState != state { connectionState = state }
        diagnostics.connectionState = state
        diagnostics.connectedPeers = established.map(\.displayName)
        diagnostics.invitedPeers = connecting.map(\.displayName)
    }

    // MARK: - Identity mapping

    public static func peerID(forDeviceID deviceID: String) -> String {
        "v2:\(deviceID)"
    }

    static func deviceID(fromPeerID peerID: String) -> String? {
        peerID.hasPrefix("v2:") ? String(peerID.dropFirst(3)) : nil
    }

    static func carrierPeer(_ info: CarrierV2DeviceInfo) -> CarrierPeer {
        CarrierPeer(id: peerID(forDeviceID: info.deviceID), displayName: info.deviceName, role: .receiver)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - Diagnostics

    public func recordDiagnosticMarker(_ name: String, message: String, peerName: String? = nil) {
        let event = CarrierDiagnosticEvent(
            name: name,
            message: message,
            peerName: peerName,
            connectionState: connectionState,
            connectedPeers: connectedPeers.map(\.displayName)
        )
        events.append(event)
        if events.count > 100 { events.removeFirst(events.count - 100) }
        diagnostics.events = events
        try? diagnosticLogStore?.append(event: event, diagnostics: diagnostics)
    }
}

/// Resumes a continuation exactly once, whichever of several callbacks gets there first.
/// Every caller runs on the main actor; the lock only satisfies the compiler's Sendable checking.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    var hasResumed: Bool { lock.withLock { continuation == nil } }

    func resume(_ value: Bool) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
