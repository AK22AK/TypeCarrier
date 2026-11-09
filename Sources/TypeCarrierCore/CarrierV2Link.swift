import Foundation
import Network

/// Runs one `CarrierV2Session` over an `NWConnection`: drives the socket, the heartbeat timer and
/// the handshake deadline, and reports what happened. Both the receiver's listener and the
/// sender's client use it, so the two sides behave identically on the wire.
@MainActor
public final class CarrierV2Link {
    public enum Event: Equatable {
        case tcpReady
        case pairingCodeReady(code: String, peer: CarrierV2Peer)
        case established(CarrierV2Peer)
        case received(CarrierEnvelope)
        /// Final event. `reason` is nil when the network failed rather than the protocol closing.
        case closed(reason: CarrierV2CloseReason?, networkError: String?)
    }

    public static let handshakeTimeout: Duration = .seconds(5)
    /// How long the person has to compare codes and confirm on the receiver.
    public static let pairingDecisionTimeout: Duration = .seconds(60)
    private static let tickInterval: Duration = .seconds(2)

    public let connection: NWConnection
    public private(set) var session: CarrierV2Session
    public private(set) var peer: CarrierV2Peer?
    public var endpoint: NWEndpoint { connection.endpoint }

    /// Replaceable so a session that finished pairing can be handed to the code that owns live sessions.
    public var onEvent: (CarrierV2Link, Event) -> Void
    private var deadlineTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var isFinished = false

    public init(connection: NWConnection, session: CarrierV2Session, onEvent: @escaping (CarrierV2Link, Event) -> Void) {
        self.connection = connection
        self.session = session
        self.onEvent = onEvent
    }

    public var isEstablished: Bool { session.isEstablished }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        connection.start(queue: .main)
        armDeadline(Self.handshakeTimeout + .seconds(3))
    }

    public func send(_ envelope: CarrierEnvelope) throws {
        apply(try session.send(envelope))
    }

    public func confirmPairing() {
        apply(session.confirmPairing())
    }

    public func rejectPairing() {
        apply(session.rejectPairing())
    }

    /// Closes politely (the peer learns why) and then tears the socket down.
    public func close() {
        let events = session.shutdown()
        if events.isEmpty {
            finish(reason: .shutdown, networkError: nil)
        } else {
            apply(events)
        }
    }

    // MARK: - Socket

    private func handle(_ state: NWConnection.State) {
        guard !isFinished else { return }
        switch state {
        case .ready:
            onEvent(self, .tcpReady)
            armDeadline(Self.handshakeTimeout)
            receive()
            apply(session.start())
        case .failed(let error):
            finish(reason: nil, networkError: error.localizedDescription)
        case .waiting(let error):
            // An unreachable endpoint parks in .waiting; nothing will change before the deadline does.
            finish(reason: nil, networkError: error.localizedDescription)
        case .cancelled:
            finish(reason: nil, networkError: nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isFinished else { return }
                if let data, !data.isEmpty {
                    self.apply(self.session.receive(data))
                }
                guard !self.isFinished else { return }
                if let error {
                    self.finish(reason: nil, networkError: error.localizedDescription)
                } else if isComplete {
                    self.finish(reason: nil, networkError: "Connection closed by peer.")
                } else {
                    self.receive()
                }
            }
        }
    }

    // MARK: - Session events

    private func apply(_ events: [CarrierV2SessionEvent]) {
        for event in events {
            guard !isFinished else { return }
            switch event {
            case .write(let data):
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.finish(reason: nil, networkError: error.localizedDescription) }
                })
            case .pairingCodeReady(let code, let peer):
                self.peer = peer
                armDeadline(Self.pairingDecisionTimeout)
                onEvent(self, .pairingCodeReady(code: code, peer: peer))
            case .established(let peer):
                self.peer = peer
                deadlineTask?.cancel()
                startTicking()
                onEvent(self, .established(peer))
            case .received(let envelope):
                onEvent(self, .received(envelope))
            case .closed(let reason):
                // Let queued writes (such as the close notice) flush before cancelling.
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
                finish(reason: reason, networkError: nil)
            }
        }
    }

    private func armDeadline(_ duration: Duration) {
        deadlineTask?.cancel()
        deadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, !self.isFinished, !self.session.isEstablished else { return }
            self.apply(self.session.shutdown())
            self.finish(reason: .handshakeFailed, networkError: "Timed out after \(duration).")
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, !self.isFinished else { return }
                self.apply(self.session.tick())
            }
        }
    }

    private func finish(reason: CarrierV2CloseReason?, networkError: String?) {
        guard !isFinished else { return }
        isFinished = true
        deadlineTask?.cancel()
        tickTask?.cancel()
        let connection = connection
        // Give a just-queued close notice a moment to leave before the socket goes away.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            connection.cancel()
        }
        onEvent(self, .closed(reason: reason, networkError: networkError))
    }
}
