import Foundation
import Network
import TypeCarrierCore

@MainActor
final class AndroidCarrierBridge: ObservableObject {
    enum BridgeState: Equatable {
        case stopped
        case listening(port: UInt16?)
        case failed(String)
    }

    static let serviceType = "_typecarrier-json._tcp"
    static let defaultPairingCode = "123456"
    static let defaultPort: NWEndpoint.Port = 17641

    @Published private(set) var state: BridgeState = .stopped
    @Published private(set) var lastErrorMessage: String?

    var pairingCode: String {
        pairingCodeProvider()
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
    private let pairingCodeProvider: () -> String
    private let trustTokenStore: AndroidTrustTokenStore
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: BridgeConnectionState] = [:]
    private var activeSenderGate = AndroidBridgeActiveSenderGate()
    private var envelopeHandler: ((CarrierEnvelope, String, @escaping (CarrierEnvelope) -> Void) -> Void)?

    init(
        displayName: String,
        pairingCodeProvider: @escaping () -> String = { defaultPairingCode },
        trustTokenStore: AndroidTrustTokenStore = AndroidTrustTokenStore()
    ) {
        self.displayName = displayName
        self.pairingCodeProvider = pairingCodeProvider
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
            state = .listening(port: nil)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.connection.cancel() }
        connections = [:]
        activeSenderGate = AndroidBridgeActiveSenderGate()
        envelopeHandler = nil
        lastErrorMessage = nil
        state = .stopped
    }

    private func handleListenerState(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            state = .listening(port: listener?.port?.rawValue)
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
        } catch {
            send(AndroidBridgeResponse(status: .rejected, message: error.localizedDescription), to: connection)
            remove(connection)
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
            send(.busy("Mac is already serving another device."), to: connection)
            remove(connection)
            return
        }

        if handshake.isPairingAttempt, handshake.pairingCode == pairingCodeProvider() {
            let trustToken = (try? AndroidTrustToken.generate()) ?? AndroidTrustToken(rawValue: UUID().uuidString)
            trustTokenStore.remember(trustToken, for: handshake.deviceID)
            connectionState.deviceID = handshake.deviceID
            connectionState.deviceName = handshake.deviceName
            send(AndroidBridgeResponse(status: .accepted, message: "Paired.", trustToken: trustToken.rawValue), to: connection)
            return
        }

        if handshake.isTokenAttempt,
           let tokenProof = handshake.tokenProof,
           let challenge = handshake.challenge,
           let trustToken = trustTokenStore.token(for: handshake.deviceID),
           AndroidTrustToken.verify(token: trustToken, challenge: Data(challenge.utf8), proof: tokenProof) {
            connectionState.deviceID = handshake.deviceID
            connectionState.deviceName = handshake.deviceName
            send(AndroidBridgeResponse(status: .accepted, message: "Trusted."), to: connection)
            return
        }

        activeSenderGate.release(deviceID: handshake.deviceID)
        send(AndroidBridgeResponse(status: .invalidPairing, message: "Invalid pairing code or trust token."), to: connection)
        remove(connection)
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

    private func remove(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        if let deviceID = connections[id]?.deviceID {
            activeSenderGate.release(deviceID: deviceID)
        }
        connections[id] = nil
        connection.cancel()
    }

    private func fail(_ message: String) {
        lastErrorMessage = message
        state = .failed(message)
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
}

private struct BridgeConnectionState {
    let connection: NWConnection
    var buffer = Data()
    var deviceID: String?
    var deviceName: String?
}
