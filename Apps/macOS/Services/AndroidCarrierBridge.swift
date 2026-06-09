import Foundation
import Network
import TypeCarrierCore

@MainActor
final class AndroidCarrierBridge: ObservableObject {
    typealias EnvelopeHandler = (CarrierEnvelope, String, @escaping (CarrierEnvelope) -> Void) -> Void

    enum BridgeState: Equatable {
        case stopped
        case listening(port: UInt16?)
        case failed(String)

        var isFailed: Bool {
            if case .failed = self {
                return true
            }
            return false
        }
    }

    static let serviceType = AndroidBonjourAdvertisement.serviceType
    static let defaultPort: NWEndpoint.Port = 17641
    private static let macIDDefaultsKey = "AndroidBridgeMacID"
    private static let pairingCodeDefaultsKey = "AndroidBridgePairingCode"

    @Published private(set) var state: BridgeState = .stopped
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var discoveredAndroidPairingDevices: [AndroidPairingDevice] = []
    @Published private(set) var connectedAndroidDeviceNames: [String] = []
    @Published private(set) var associationStatusMessage: String?

    var pairingCode: String {
        localPairingCode
    }

    var bonjourDiscoveryInfo: [String: String] {
        AndroidBonjourAdvertisement.discoveryInfo(
            macID: macID,
            macName: displayName,
            port: Self.defaultPort.rawValue
        )
    }

    var manualConnectionHints: String {
        let portText: String
        switch state {
        case .listening(let port):
            portText = String(port ?? Self.defaultPort.rawValue)
        default:
            portText = String(Self.defaultPort.rawValue)
        }

        let addresses = Self.localIPv4Addresses()
        guard !addresses.isEmpty else {
            return "端口 \(portText)"
        }
        return addresses.map { "\($0.address):\(portText)（\($0.interfaceName)）" }.joined(separator: "\n")
    }

    private let displayName: String
    private let macID: String
    private let localPairingCode: String
    private let trustTokenStore: AndroidTrustTokenStore
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private var listener: NWListener?
    private var pairingBrowser: AndroidPairingBrowser?
    private var connections: [ObjectIdentifier: BridgeConnectionState] = [:]
    private var activeSenderGate = AndroidBridgeActiveSenderGate()
    private var envelopeHandler: EnvelopeHandler?
    private var pendingStartHandler: EnvelopeHandler?
    private var isStoppingListener = false

    init(
        displayName: String,
        pairingCode: String = AndroidCarrierBridge.resolvePairingCode(),
        trustTokenStore: AndroidTrustTokenStore = AndroidTrustTokenStore(),
        macID: String = AndroidCarrierBridge.resolveMacID(),
        diagnosticLogFileURL: URL? = nil
    ) {
        self.displayName = displayName
        self.macID = macID
        self.localPairingCode = pairingCode
        self.trustTokenStore = trustTokenStore
        diagnosticLogStore = diagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
    }

    func start(onEnvelope: @escaping EnvelopeHandler) {
        if hasActiveResources {
            stop(thenStart: onEnvelope)
            return
        }
        startFresh(onEnvelope: onEnvelope)
    }

    func restart(onEnvelope: @escaping EnvelopeHandler) {
        stop(thenStart: onEnvelope)
    }

    private func startFresh(onEnvelope: @escaping EnvelopeHandler) {
        envelopeHandler = onEnvelope
        lastErrorMessage = nil

        do {
            let listener = try NWListener(using: .tcp, on: Self.defaultPort)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            recordDiagnosticEvent(
                "androidBridge.listener.start",
                message: "Starting Android TCP listener on port \(Self.defaultPort.rawValue)."
            )
            listener.start(queue: .main)
            self.listener = listener
            state = .listening(port: nil)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        stop(thenStart: nil)
    }

    private func stop(thenStart nextStartHandler: EnvelopeHandler?) {
        pendingStartHandler = nextStartHandler
        let existingListener = listener
        if existingListener != nil {
            isStoppingListener = true
        }
        listener?.cancel()
        pairingBrowser?.stop()
        pairingBrowser = nil
        discoveredAndroidPairingDevices = []
        connectedAndroidDeviceNames = []
        connections.values.forEach { $0.connection.cancel() }
        connections = [:]
        activeSenderGate = AndroidBridgeActiveSenderGate()
        envelopeHandler = nil
        lastErrorMessage = nil
        recordDiagnosticEvent("androidBridge.listener.stop", message: "Stopped Android bridge listener.")
        if existingListener == nil {
            finishListenerStop()
        }
    }

    func associateAndroidDevice(pairingCode: String) {
        guard AndroidPairingCode.isValid(pairingCode) else {
            associationStatusMessage = "请输入 6 位匹配码。"
            return
        }

        guard let device = discoveredAndroidPairingDevices.first else {
            associationStatusMessage = "未发现可关联的 Android 设备。请保持 Android 版 TypeCarrier 打开。"
            return
        }

        associationStatusMessage = "正在关联 \(device.name)..."
        let request = AndroidPairingAssociationRequest(
            macID: macID,
            macName: displayName,
            pairingCode: pairingCode
        )

        Task { @MainActor in
            do {
                let response = try await AndroidPairingAssociationClient.associate(device: device, request: request)
                if response.status == .accepted,
                   let deviceID = response.deviceID,
                   let trustToken = response.trustToken {
                    trustTokenStore.remember(AndroidTrustToken(rawValue: trustToken), for: deviceID)
                    associationStatusMessage = "已关联 \(response.deviceName ?? device.name)。"
                } else {
                    associationStatusMessage = response.message
                }
            } catch {
                associationStatusMessage = error.localizedDescription
            }
        }
    }

    private func handleListenerState(_ listenerState: NWListener.State) {
        if isStoppingListener {
            switch listenerState {
            case .cancelled, .failed:
                recordDiagnosticEvent("androidBridge.listener.cancelled", message: "Android bridge listener cancelled.")
                finishListenerStop()
            default:
                break
            }
            return
        }

        switch listenerState {
        case .ready:
            let port = listener?.port?.rawValue
            state = .listening(port: port)
            recordDiagnosticEvent(
                "androidBridge.listener.ready",
                message: "Android bridge listening on \(manualConnectionHints)."
            )
        case .failed(let error):
            fail(error.localizedDescription)
        case .cancelled:
            recordDiagnosticEvent("androidBridge.listener.cancelled", message: "Android bridge listener cancelled.")
            finishListenerStop()
        default:
            break
        }
    }

    private var hasActiveResources: Bool {
        listener != nil || pairingBrowser != nil || !connections.isEmpty
    }

    private func finishListenerStop() {
        listener = nil
        isStoppingListener = false
        state = .stopped

        guard let nextStartHandler = pendingStartHandler else {
            return
        }
        pendingStartHandler = nil
        startFresh(onEnvelope: nextStartHandler)
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = BridgeConnectionState(connection: connection)
        recordDiagnosticEvent(
            "androidBridge.connection.accepted",
            message: "Accepted Android bridge TCP connection from \(String(describing: connection.endpoint))."
        )
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else {
                return
            }
            Task { @MainActor in
                self?.handleConnectionState(state, connection: connection)
            }
        }
        connection.start(queue: .main)
        receive(from: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            recordDiagnosticEvent(
                "androidBridge.connection.ready",
                message: "Android bridge TCP connection is ready.",
                peerName: connections[ObjectIdentifier(connection)]?.deviceName
            )
        case .failed(let error):
            recordDiagnosticEvent(
                "androidBridge.connection.failed",
                message: error.localizedDescription,
                peerName: connections[ObjectIdentifier(connection)]?.deviceName
            )
            remove(connection)
        case .cancelled:
            recordDiagnosticEvent(
                "androidBridge.connection.cancelled",
                message: "Android bridge TCP connection cancelled.",
                peerName: connections[ObjectIdentifier(connection)]?.deviceName
            )
            remove(connection)
        default:
            break
        }
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, isComplete, error in
            guard let connection else {
                return
            }
            Task { @MainActor in
                guard let self else {
                    return
                }
                if let data, !data.isEmpty {
                    self.handle(data, from: connection)
                }
                if isComplete || error != nil {
                    self.remove(connection)
                } else {
                    self.receive(from: connection)
                }
            }
        }
    }

    private func handle(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var connectionState = connections[id] else {
            return
        }

        connectionState.buffer.append(data)

        do {
            while let payload = try CarrierWireFrame.nextPayload(from: &connectionState.buffer) {
                try handle(payload, from: connection, state: &connectionState)
            }
            connections[id] = connectionState
            updateConnectedAndroidDevices()
        } catch {
            recordDiagnosticEvent(
                "androidBridge.connection.payloadRejected",
                message: error.localizedDescription,
                peerName: connectionState.deviceName
            )
            sendAndRemove(AndroidBridgeResponse(status: .rejected, message: error.localizedDescription), to: connection)
        }
    }

    private func handle(_ payload: Data, from connection: NWConnection, state connectionState: inout BridgeConnectionState) throws {
        if connectionState.deviceID == nil {
            let handshake = try JSONDecoder().decode(AndroidBridgeHandshake.self, from: payload)
            handle(handshake, from: connection, state: &connectionState)
            return
        }

        let envelope = try CarrierCodec.decode(payload)
        let deviceName = connectionState.deviceName ?? "Android"
        envelopeHandler?(envelope, deviceName) { [weak self, weak connection] reply in
            guard let self, let connection else {
                return
            }
            self.send(reply, to: connection)
        }
    }

    private func handle(_ handshake: AndroidBridgeHandshake, from connection: NWConnection, state connectionState: inout BridgeConnectionState) {
        guard activeSenderGate.claim(deviceID: handshake.deviceID) else {
            recordDiagnosticEvent(
                "androidBridge.handshake.busy",
                message: "Rejected Android handshake because another sender is active.",
                peerName: handshake.deviceName
            )
            sendAndRemove(.busy("Mac is already serving another device."), to: connection)
            return
        }

        if handshake.isPairingAttempt, handshake.pairingCode == localPairingCode {
            let trustToken = (try? AndroidTrustToken.generate()) ?? AndroidTrustToken(rawValue: UUID().uuidString)
            trustTokenStore.remember(trustToken, for: handshake.deviceID)
            accept(handshake: handshake, from: connection, state: &connectionState)
            recordDiagnosticEvent(
                "androidBridge.handshake.paired",
                message: "Accepted Android pairing code handshake.",
                peerName: handshake.deviceName
            )
            send(AndroidBridgeResponse(status: .accepted, message: "Paired.", trustToken: trustToken.rawValue, macID: macID, macName: displayName), to: connection)
            return
        }

        if handshake.isTokenAttempt,
           let tokenProof = handshake.tokenProof,
           let challenge = handshake.challenge,
           let trustToken = trustTokenStore.token(for: handshake.deviceID),
            AndroidTrustToken.verify(token: trustToken, challenge: Data(challenge.utf8), proof: tokenProof) {
            accept(handshake: handshake, from: connection, state: &connectionState)
            recordDiagnosticEvent(
                "androidBridge.handshake.trusted",
                message: "Accepted Android trust token handshake.",
                peerName: handshake.deviceName
            )
            send(AndroidBridgeResponse(status: .accepted, message: "Trusted.", macID: macID, macName: displayName), to: connection)
            return
        }

        activeSenderGate.release(deviceID: handshake.deviceID)
        recordDiagnosticEvent(
            "androidBridge.handshake.rejected",
            message: "Invalid Android pairing code or trust token.",
            peerName: handshake.deviceName
        )
        sendAndRemove(AndroidBridgeResponse(status: .invalidPairing, message: "Invalid pairing code or trust token."), to: connection)
    }

    private func accept(
        handshake: AndroidBridgeHandshake,
        from connection: NWConnection,
        state connectionState: inout BridgeConnectionState
    ) {
        removeSupersededConnections(for: handshake.deviceID, keeping: connection)
        connectionState.deviceID = handshake.deviceID
        connectionState.deviceName = handshake.deviceName
    }

    private func send(_ response: AndroidBridgeResponse, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(response) else {
            return
        }
        send(data, to: connection)
    }

    private func send(_ envelope: CarrierEnvelope, to connection: NWConnection) {
        guard let data = try? CarrierCodec.encode(envelope) else {
            return
        }
        send(data, to: connection)
    }

    private func send(_ payload: Data, to connection: NWConnection) {
        send(payload, to: connection, completion: nil)
    }

    private func send(_ payload: Data, to connection: NWConnection, completion: (() -> Void)?) {
        guard let frame = try? CarrierWireFrame.encode(payload) else {
            completion?()
            return
        }
        connection.send(content: frame, completion: .contentProcessed { _ in
            Task { @MainActor in
                completion?()
            }
        })
    }

    private func sendAndRemove(_ response: AndroidBridgeResponse, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(response) else {
            remove(connection)
            return
        }
        send(data, to: connection) { [weak self, weak connection] in
            guard let self, let connection else {
                return
            }
            self.remove(connection)
        }
    }

    private func remove(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let deviceID = connections[id]?.deviceID
        connections[id] = nil
        if let deviceID,
           !connections.values.contains(where: { $0.deviceID == deviceID }) {
            activeSenderGate.release(deviceID: deviceID)
        }
        updateConnectedAndroidDevices()
        connection.cancel()
    }

    private func removeSupersededConnections(for deviceID: String, keeping connection: NWConnection) {
        let currentID = ObjectIdentifier(connection)
        let supersededConnections = connections
            .filter { id, state in
                id != currentID && state.deviceID == deviceID
            }

        for (id, state) in supersededConnections {
            connections[id] = nil
            state.connection.cancel()
        }
    }

    private func updateConnectedAndroidDevices() {
        var devicesByID: [String: String] = [:]
        for state in connections.values {
            guard let deviceID = state.deviceID else {
                continue
            }
            if let deviceName = state.deviceName, !deviceName.isEmpty {
                devicesByID[deviceID] = deviceName
            } else {
                devicesByID[deviceID] = "Android"
            }
        }
        connectedAndroidDeviceNames = devicesByID.values.sorted()
    }

    private func fail(_ message: String) {
        lastErrorMessage = message
        state = .failed(message)
        recordDiagnosticEvent("androidBridge.listener.failed", message: message)
    }

    private func startPairingBrowser() {
        let browser = AndroidPairingBrowser { [weak self] devices in
            Task { @MainActor in
                self?.discoveredAndroidPairingDevices = devices
            }
        } onError: { [weak self] message in
            Task { @MainActor in
                self?.recordDiagnosticEvent("androidBridge.pairingBrowser.failed", message: message)
            }
        }
        pairingBrowser = browser
        browser.start()
    }

    private var diagnosticConnectionState: ConnectionState {
        if let deviceName = connectedAndroidDeviceNames.first {
            return .connected(deviceName)
        }

        switch state {
        case .stopped:
            return .idle
        case .listening:
            return .advertising
        case .failed(let message):
            return .failed(message)
        }
    }

    private func recordDiagnosticEvent(_ name: String, message: String, peerName: String? = nil) {
        let connectionState = diagnosticConnectionState
        let diagnostics = CarrierDiagnostics(
            role: "receiver.android",
            localPeerName: displayName,
            serviceType: Self.serviceType,
            connectionState: connectionState,
            discoveredPeers: discoveredAndroidPairingDevices.map(\.name).sorted(),
            connectedPeers: connectedAndroidDeviceNames,
            lastErrorMessage: lastErrorMessage
        )
        let event = CarrierDiagnosticEvent(
            name: name,
            message: message,
            peerName: peerName,
            connectionState: connectionState,
            connectedPeers: connectedAndroidDeviceNames
        )
        try? diagnosticLogStore?.append(event: event, diagnostics: diagnostics)
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

    private static func resolveMacID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: macIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let next = UUID().uuidString
        defaults.set(next, forKey: macIDDefaultsKey)
        return next
    }

    private static func resolvePairingCode(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: pairingCodeDefaultsKey), AndroidPairingCode.isValid(existing) {
            return existing
        }
        let next = AndroidPairingCode.generate()
        defaults.set(next, forKey: pairingCodeDefaultsKey)
        return next
    }
}

struct AndroidPairingDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
}

private final class AndroidPairingBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private let onDevicesChanged: ([AndroidPairingDevice]) -> Void
    private let onError: (String) -> Void
    private var services: [String: NetService] = [:]
    private var devices: [String: AndroidPairingDevice] = [:]

    init(onDevicesChanged: @escaping ([AndroidPairingDevice]) -> Void, onError: @escaping (String) -> Void) {
        self.onDevicesChanged = onDevicesChanged
        self.onError = onError
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: "_tcpair._tcp", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.values.forEach {
            $0.stop()
            $0.delegate = nil
        }
        services = [:]
        devices = [:]
        publish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services[service.name] = nil
        devices[service.name] = nil
        publish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        onError("Android 匹配设备发现失败：\(errorDict)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName,
              sender.port > 0,
              sender.port <= UInt16.max else {
            return
        }

        devices[sender.name] = AndroidPairingDevice(
            id: "\(sender.name)@\(hostName):\(sender.port)",
            name: sender.name,
            host: hostName,
            port: UInt16(sender.port)
        )
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        onError("Android 匹配设备解析失败：\(errorDict)")
    }

    private func publish() {
        onDevicesChanged(devices.values.sorted { $0.name < $1.name })
    }
}

@MainActor
private final class AndroidPairingAssociationClient {
    private let connection: NWConnection
    private let frame: Data
    private var continuation: CheckedContinuation<AndroidPairingAssociationResponse, Error>?
    private var buffer = Data()
    private var didFinish = false

    private init(device: AndroidPairingDevice, frame: Data) throws {
        guard let port = NWEndpoint.Port(rawValue: device.port) else {
            throw AndroidAssociationError.invalidRequest
        }
        self.connection = NWConnection(host: NWEndpoint.Host(device.host), port: port, using: .tcp)
        self.frame = frame
    }

    static func associate(
        device: AndroidPairingDevice,
        request: AndroidPairingAssociationRequest
    ) async throws -> AndroidPairingAssociationResponse {
        guard let requestData = try? JSONEncoder().encode(request),
              let frame = try? CarrierWireFrame.encode(requestData) else {
            throw AndroidAssociationError.invalidRequest
        }

        let client = try AndroidPairingAssociationClient(device: device, frame: frame)
        return try await client.start()
    }

    private func start() async throws -> AndroidPairingAssociationResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            connection.stateUpdateHandler = { state in
                Task { @MainActor in
                    self.handleState(state)
                }
            }
            connection.start(queue: .main)
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connection.send(content: frame, completion: .contentProcessed { error in
                Task { @MainActor in
                    if let error {
                        self.finish(.failure(error))
                    } else {
                        self.receive()
                    }
                }
            })
        case .failed(let error):
            finish(.failure(error))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            Task { @MainActor in
                if let error {
                    self.finish(.failure(error))
                    return
                }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    do {
                        if let payload = try CarrierWireFrame.nextPayload(from: &self.buffer) {
                            let response = try JSONDecoder().decode(AndroidPairingAssociationResponse.self, from: payload)
                            self.finish(.success(response))
                            return
                        }
                    } catch {
                        self.finish(.failure(error))
                        return
                    }
                }
                if isComplete {
                    self.finish(.failure(AndroidAssociationError.connectionClosed))
                } else {
                    self.receive()
                }
            }
        }
    }

    private func finish(_ result: Result<AndroidPairingAssociationResponse, Error>) {
        guard !didFinish else {
            return
        }
        didFinish = true
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

private enum AndroidAssociationError: LocalizedError {
    case invalidRequest
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "关联请求无效。"
        case .connectionClosed:
            "关联连接已关闭。"
        }
    }
}

private struct BridgeConnectionState {
    let connection: NWConnection
    var buffer = Data()
    var deviceID: String?
    var deviceName: String?
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
