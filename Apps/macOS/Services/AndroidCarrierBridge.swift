import Foundation
import Network
import TypeCarrierCore

@MainActor
final class AndroidCarrierBridge: ObservableObject {
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

    static let serviceType = "_typecarrier-json._tcp"
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
        return addresses.map { "\($0):\(portText)" }.joined(separator: "\n")
    }

    private let displayName: String
    private let macID: String
    private let localPairingCode: String
    private let trustTokenStore: AndroidTrustTokenStore
    private var listener: NWListener?
    private var bonjourPublisher: AndroidBonjourPublisher?
    private var pairingBrowser: AndroidPairingBrowser?
    private var connections: [ObjectIdentifier: BridgeConnectionState] = [:]
    private var activeSenderGate = AndroidBridgeActiveSenderGate()
    private var envelopeHandler: ((CarrierEnvelope, String, @escaping (CarrierEnvelope) -> Void) -> Void)?

    init(
        displayName: String,
        pairingCode: String = AndroidCarrierBridge.resolvePairingCode(),
        trustTokenStore: AndroidTrustTokenStore = AndroidTrustTokenStore(),
        macID: String = AndroidCarrierBridge.resolveMacID()
    ) {
        self.displayName = displayName
        self.macID = macID
        self.localPairingCode = pairingCode
        self.trustTokenStore = trustTokenStore
    }

    func start(onEnvelope: @escaping (CarrierEnvelope, String, @escaping (CarrierEnvelope) -> Void) -> Void) {
        stop()
        envelopeHandler = onEnvelope

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
            listener.start(queue: .main)
            self.listener = listener
            startPairingBrowser()
            state = .listening(port: nil)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        bonjourPublisher?.stop()
        bonjourPublisher = nil
        pairingBrowser?.stop()
        pairingBrowser = nil
        discoveredAndroidPairingDevices = []
        connectedAndroidDeviceNames = []
        connections.values.forEach { $0.connection.cancel() }
        connections = [:]
        activeSenderGate = AndroidBridgeActiveSenderGate()
        envelopeHandler = nil
        lastErrorMessage = nil
        state = .stopped
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
        switch listenerState {
        case .ready:
            let port = listener?.port?.rawValue
            state = .listening(port: port)
            publishBonjour(port: port)
        case .failed(let error):
            fail(error.localizedDescription)
        case .cancelled:
            state = .stopped
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = BridgeConnectionState(connection: connection)
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
        case .failed, .cancelled:
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
            sendAndRemove(.busy("Mac is already serving another device."), to: connection)
            return
        }

        if handshake.isPairingAttempt, handshake.pairingCode == localPairingCode {
            let trustToken = (try? AndroidTrustToken.generate()) ?? AndroidTrustToken(rawValue: UUID().uuidString)
            trustTokenStore.remember(trustToken, for: handshake.deviceID)
            accept(handshake: handshake, from: connection, state: &connectionState)
            send(AndroidBridgeResponse(status: .accepted, message: "Paired.", trustToken: trustToken.rawValue, macID: macID, macName: displayName), to: connection)
            return
        }

        if handshake.isTokenAttempt,
           let tokenProof = handshake.tokenProof,
           let challenge = handshake.challenge,
           let trustToken = trustTokenStore.token(for: handshake.deviceID),
           AndroidTrustToken.verify(token: trustToken, challenge: Data(challenge.utf8), proof: tokenProof) {
            accept(handshake: handshake, from: connection, state: &connectionState)
            send(AndroidBridgeResponse(status: .accepted, message: "Trusted.", macID: macID, macName: displayName), to: connection)
            return
        }

        activeSenderGate.release(deviceID: handshake.deviceID)
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
        guard let frame = try? CarrierWireFrame.encode(payload) else {
            return
        }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendAndRemove(_ response: AndroidBridgeResponse, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(response) else {
            remove(connection)
            return
        }
        guard let frame = try? CarrierWireFrame.encode(data) else {
            remove(connection)
            return
        }
        connection.send(content: frame, completion: .contentProcessed { [weak self, weak connection] _ in
            Task { @MainActor in
                guard let self, let connection else {
                    return
                }
                self.remove(connection)
            }
        })
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
    }

    private func publishBonjour(port: UInt16?) {
        let resolvedPort = port ?? Self.defaultPort.rawValue
        bonjourPublisher?.stop()
        let publisher = AndroidBonjourPublisher(
            name: displayName,
            type: Self.serviceType + ".",
            port: resolvedPort,
            macID: macID
        ) { [weak self] message in
            Task { @MainActor in
                self?.lastErrorMessage = message
            }
        }
        bonjourPublisher = publisher
        publisher.start()
    }

    private func startPairingBrowser() {
        let browser = AndroidPairingBrowser { [weak self] devices in
            Task { @MainActor in
                self?.discoveredAndroidPairingDevices = devices
            }
        } onError: { [weak self] message in
            Task { @MainActor in
                self?.lastErrorMessage = message
            }
        }
        pairingBrowser = browser
        browser.start()
    }

    private static func localIPv4Addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var addresses: [String] = []
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
                addresses.append(String(cString: hostname))
            }
        }

        return Array(Set(addresses)).sorted()
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
        browser.searchForServices(ofType: "_typecarrier-android-pair._tcp.", inDomain: "local.")
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

private final class AndroidBonjourPublisher: NSObject, NetServiceDelegate {
    private let name: String
    private let type: String
    private let port: UInt16
    private let macID: String
    private let onError: (String) -> Void
    private var service: NetService?

    init(name: String, type: String, port: UInt16, macID: String, onError: @escaping (String) -> Void) {
        self.name = name
        self.type = type
        self.port = port
        self.macID = macID
        self.onError = onError
    }

    func start() {
        let nextService = NetService(
            domain: "local.",
            type: type,
            name: name,
            port: Int32(port)
        )
        nextService.setTXTRecord(
            NetService.data(fromTXTRecord: [
                "macID": Data(macID.utf8),
                "macName": Data(name.utf8),
            ])
        )
        nextService.delegate = self
        nextService.publish()
        service = nextService
    }

    func stop() {
        service?.stop()
        service?.delegate = nil
        service = nil
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        onError("Android 自动发现发布失败：\(errorDict)")
    }
}

private struct BridgeConnectionState {
    let connection: NWConnection
    var buffer = Data()
    var deviceID: String?
    var deviceName: String?
}
