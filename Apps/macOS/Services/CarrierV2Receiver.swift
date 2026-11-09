import Foundation
import Network
import TypeCarrierCore

/// Receives from paired devices over protocol v2 (Network.framework + Noise). It listens on one TCP
/// port, advertises `_typecarrier-v2._tcp` over Bonjour, and runs a `CarrierV2Link` per connection.
@MainActor
final class CarrierV2Receiver: ObservableObject {
    typealias EnvelopeHandler = (
        _ envelope: CarrierEnvelope,
        _ deviceName: String,
        _ deviceID: String,
        _ reply: @escaping (CarrierEnvelope) -> Void
    ) -> Void

    enum ListenerState: Equatable {
        case stopped
        case listening(port: UInt16?)
        case failed(String)
    }

    struct PendingPairing: Equatable, Identifiable {
        let id: ObjectIdentifier
        let code: String
        let deviceName: String
        let platform: CarrierHello.Platform
    }

    static let serviceType = "_typecarrier-v2._tcp"
    static let defaultPort: NWEndpoint.Port = 17642
    static let deviceIDTXTKey = "id"
    private static let deviceIDDefaultsKey = "CarrierV2DeviceID"

    @Published private(set) var state: ListenerState = .stopped
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published private(set) var connectedDevices: [ReceiverConnectedDevice] = []
    @Published private(set) var pendingPairing: PendingPairing?
    @Published private(set) var pairedDevices: [CarrierV2PairedDevice] = []
    @Published private(set) var lastErrorMessage: String?

    let deviceID: String
    private var displayName: String
    private let trustStore: CarrierV2TrustStore
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private var identity: CarrierV2Identity?
    private var listener: NWListener?
    private var links: [ObjectIdentifier: CarrierV2Link] = [:]
    private var envelopeHandler: EnvelopeHandler?
    private var restartTask: Task<Void, Never>?
    private var usesFallbackPort = false
    /// Held while listening so App Nap does not delay accepting a phone's connection.
    private var appNapActivity: NSObjectProtocol?

    init(
        displayName: String,
        trustStore: CarrierV2TrustStore = CarrierV2TrustStore(),
        deviceID: String = CarrierV2Receiver.resolveDeviceID(),
        diagnosticLogFileURL: URL? = nil
    ) {
        self.displayName = displayName
        self.trustStore = trustStore
        self.deviceID = deviceID
        diagnosticLogStore = diagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
        pairedDevices = (try? trustStore.pairedDevices()) ?? []
    }

    func start(onEnvelope: @escaping EnvelopeHandler) {
        envelopeHandler = onEnvelope
        guard listener == nil else { return }
        do {
            identity = CarrierV2Identity(
                staticKey: try trustStore.identityKey(),
                info: CarrierV2DeviceInfo(deviceID: deviceID, deviceName: displayName),
                platform: .macOS,
                capabilities: [CarrierHello.capabilityReceivePaste, CarrierHello.capabilityReceipt]
            )
        } catch {
            fail("无法读取钥匙串中的设备密钥：\(error.localizedDescription)")
            return
        }
        if appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Receiving text from paired devices"
            )
        }
        startListener()
    }

#if DEBUG
    /// Debug builds launched with TYPECARRIER_V2_AUTOPAIR=1 accept the first pairing code without
    /// a click, so simulator runs and soak scripts can pair unattended.
    private static var autoPairsForTesting: Bool {
        ProcessInfo.processInfo.environment["TYPECARRIER_V2_AUTOPAIR"] == "1"
    }
#endif

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        listener?.cancel()
        listener = nil
        links.values.forEach { $0.close() }
        links = [:]
        pendingPairing = nil
        updateConnectedDevices()
        state = .stopped
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }
        record("v2.listener.stop", message: "Stopped v2 receiver.")
    }

    func restart() {
        let handler = envelopeHandler
        stop()
        if let handler {
            start(onEnvelope: handler)
        }
    }

    func updateDisplayName(_ name: String) {
        guard name != displayName else { return }
        displayName = name
        if let identity {
            self.identity = CarrierV2Identity(
                staticKey: identity.staticKey,
                info: CarrierV2DeviceInfo(deviceID: deviceID, deviceName: name),
                platform: identity.platform,
                capabilities: identity.capabilities
            )
        }
        listener?.service = makeService()
    }

    /// This Mac's LAN addresses with the listening port, for typing into a phone when discovery fails.
    var manualConnectionHints: String {
        let port: String
        if case .listening(let listeningPort?) = state {
            port = String(listeningPort)
        } else {
            port = String(Self.defaultPort.rawValue)
        }
        let addresses = Self.localIPv4Addresses()
        guard !addresses.isEmpty else { return "端口 \(port)" }
        return addresses.map { "\($0.address):\(port)（\($0.interfaceName)）" }.joined(separator: "\n")
    }

    private static func localIPv4Addresses() -> [LocalIPv4Address] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var addresses: [LocalIPv4Address] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            defer { current = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0,
                  interface.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.pointee.ifa_addr,
                socklen_t(interface.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                addresses.append(LocalIPv4Address(
                    interfaceName: String(cString: interface.pointee.ifa_name),
                    address: String(cString: hostname)
                ))
            }
        }

        return Dictionary(grouping: addresses, by: { "\($0.interfaceName)|\($0.address)" })
            .compactMap { $0.value.first }
            .sorted()
    }

    // MARK: - Pairing

    func confirmPendingPairing() {
        guard let pendingPairing, let link = links[pendingPairing.id] else { return }
        link.confirmPairing()
    }

    func rejectPendingPairing() {
        guard let pendingPairing, let link = links[pendingPairing.id] else { return }
        self.pendingPairing = nil
        link.rejectPairing()
    }

    func unpair(deviceID: String) {
        guard let device = pairedDevices.first(where: { $0.deviceID == deviceID }) else { return }
        try? trustStore.unpair(deviceID: deviceID)
        pairedDevices = (try? trustStore.pairedDevices()) ?? []
        for link in links.values where link.peer?.publicKey == device.publicKey {
            link.close()
        }
        record("v2.pairing.removed", message: "Removed pairing.", peerName: device.deviceName)
    }

    // MARK: - Listener

    private func startListener() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        let port = usesFallbackPort ? NWEndpoint.Port.any : Self.defaultPort
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            fail(error.localizedDescription)
            return
        }
        listener.service = makeService()
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, listener === self.listener else { return }
                self.handle(state, of: listener)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
        record("v2.listener.start", message: "Starting v2 listener on port \(port).")
    }

    private func handle(_ listenerState: NWListener.State, of listener: NWListener) {
        switch listenerState {
        case .ready:
            lastErrorMessage = nil
            state = .listening(port: listener.port?.rawValue)
            record("v2.listener.ready", message: "Listening on port \(listener.port.map { String($0.rawValue) } ?? "?").")
        case .failed(let error):
            self.listener = nil
            listener.cancel()
            if case .posix(let code) = error, code == .EADDRINUSE, !usesFallbackPort {
                // Another process holds the usual port; any port works because Bonjour advertises it.
                usesFallbackPort = true
                record("v2.listener.portInUse", message: "Port \(Self.defaultPort) in use; falling back to a system-assigned port.")
                startListener()
                return
            }
            fail(error.localizedDescription)
            scheduleRestart()
        default:
            break
        }
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.listener == nil, self.envelopeHandler != nil else { return }
            self.startListener()
        }
    }

    private func makeService() -> NWListener.Service {
        var txt = NWTXTRecord()
        txt[Self.deviceIDTXTKey] = deviceID
        txt["proto"] = String(CarrierProtocolV2.version)
        return NWListener.Service(name: CarrierDeviceIdentity.serviceInstanceName(displayName), type: Self.serviceType, txtRecord: txt)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard let identity else {
            connection.cancel()
            return
        }
        let session = CarrierV2Session(
            role: .responder,
            identity: identity,
            isTrusted: { [weak self] key in self?.trustStore.isTrusted(publicKey: key) ?? false },
            // A phone asks to pair and the person allows or rejects it here; one request at a time.
            // An unanswered request expires with CarrierV2Link.pairingDecisionTimeout.
            isPairingOpen: { [weak self] in
                guard let self else { return false }
                return self.pendingPairing == nil
            }
        )
        let link = CarrierV2Link(connection: connection, session: session) { [weak self] link, event in
            self?.handle(event, from: link)
        }
        links[ObjectIdentifier(link)] = link
        record("v2.connection.accepted", message: "Accepted TCP connection from \(connection.endpoint).")
        link.start()
    }

    private func handle(_ event: CarrierV2Link.Event, from link: CarrierV2Link) {
        let id = ObjectIdentifier(link)
        switch event {
        case .tcpReady:
            break
        case .pairingCodeReady(let code, let peer):
            pendingPairing = PendingPairing(id: id, code: code, deviceName: peer.info.deviceName, platform: peer.platform)
            record("v2.pairing.codeShown", message: "Waiting for the person to compare codes.", peerName: peer.info.deviceName)
#if DEBUG
            if Self.autoPairsForTesting { confirmPendingPairing() }
#endif
        case .established(let peer):
            if pendingPairing?.id == id {
                try? trustStore.pair(CarrierV2PairedDevice(
                    deviceID: peer.info.deviceID,
                    deviceName: peer.info.deviceName,
                    platform: peer.platform,
                    publicKey: peer.publicKey,
                    lastConnectedAt: Date()
                ))
                pendingPairing = nil
                record("v2.pairing.confirmed", message: "Paired.", peerName: peer.info.deviceName)
            } else {
                try? trustStore.recordConnection(publicKey: peer.publicKey, deviceName: peer.info.deviceName)
            }
            pairedDevices = (try? trustStore.pairedDevices()) ?? []
            // One live session per device: a reconnect replaces the stale one.
            for (otherID, other) in links where otherID != id && other.peer?.publicKey == peer.publicKey {
                links[otherID] = nil
                other.close()
            }
            updateConnectedDevices()
            record("v2.session.ready", message: "Session established (\(peer.platform.rawValue)).", peerName: peer.info.deviceName)
        case .received(let envelope):
            guard let peer = link.peer else { return }
            envelopeHandler?(envelope, peer.info.deviceName, "v2:\(peer.info.deviceID)") { [weak link] reply in
                try? link?.send(reply)
            }
        case .closed(let reason, let networkError):
            links[id] = nil
            if pendingPairing?.id == id {
                pendingPairing = nil
            }
            updateConnectedDevices()
            let detail = reason.map { "reason=\($0.rawValue)" } ?? "network=\(networkError ?? "cancelled")"
            record(
                link.peer == nil ? "v2.connection.closed" : "v2.session.closed",
                message: "Closed: \(detail).",
                peerName: link.peer?.info.deviceName
            )
        }
    }

    private func updateConnectedDevices() {
        let devices = links.values
            .filter(\.isEstablished)
            .compactMap { link in
                link.peer.map { ReceiverConnectedDevice(name: $0.info.deviceName, platform: $0.platform == .android ? .android : .apple) }
            }
            .sorted { $0.name < $1.name }
        // Unchanged lists must not re-render every view watching the store.
        if devices != connectedDevices {
            connectedDevices = devices
            connectedDeviceNames = devices.map(\.name)
        }
    }

    private func fail(_ message: String) {
        lastErrorMessage = message
        state = .failed(message)
        record("v2.listener.failed", message: message)
    }

    // MARK: - Diagnostics

    private func record(_ name: String, message: String, peerName: String? = nil) {
        let connectionState: ConnectionState
        if let first = connectedDeviceNames.first {
            connectionState = .connected(first)
        } else if case .failed(let message) = state {
            connectionState = .failed(message)
        } else {
            connectionState = listener == nil ? .idle : .advertising
        }
        let diagnostics = CarrierDiagnostics(
            role: "receiver.v2",
            localPeerName: displayName,
            serviceType: Self.serviceType,
            connectionState: connectionState,
            discoveredPeers: [],
            connectedPeers: connectedDeviceNames,
            lastErrorMessage: lastErrorMessage
        )
        let event = CarrierDiagnosticEvent(
            name: name,
            message: message,
            peerName: peerName,
            connectionState: connectionState,
            connectedPeers: connectedDeviceNames
        )
        try? diagnosticLogStore?.append(event: event, diagnostics: diagnostics)
    }

    private static func resolveDeviceID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let next = UUID().uuidString
        defaults.set(next, forKey: deviceIDDefaultsKey)
        return next
    }
}

private struct LocalIPv4Address: Comparable {
    let interfaceName: String
    let address: String

    static func < (lhs: LocalIPv4Address, rhs: LocalIPv4Address) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.interfaceName != rhs.interfaceName {
            return lhs.interfaceName < rhs.interfaceName
        }
        return lhs.address < rhs.address
    }

    private var priority: Int {
        if interfaceName == "en0" {
            return 0
        }
        if interfaceName.hasPrefix("en") {
            return 1
        }
        if interfaceName.hasPrefix("bridge") {
            return 2
        }
        if interfaceName.hasPrefix("utun") || interfaceName.hasPrefix("awdl") || interfaceName.hasPrefix("llw") {
            return 9
        }
        return 5
    }
}
