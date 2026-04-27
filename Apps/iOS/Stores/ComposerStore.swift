import Combine
import Foundation
import TypeCarrierCore
import UIKit

@MainActor
final class ComposerStore: ObservableObject {
    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    enum ConnectionStatus: Equatable {
        case disconnected
        case searching
        case connecting
        case connected

        var displayText: String {
            switch self {
            case .disconnected:
                "Disconnected"
            case .searching:
                "Searching"
            case .connecting:
                "Connecting"
            case .connected:
                "Connected"
            }
        }
    }

    @Published var text = ""
    @Published private(set) var sendState: SendState = .idle

    let carrierService: MultipeerCarrierService
    private var pendingPayloadID: UUID?
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        carrierService = MultipeerCarrierService(role: .sender, displayName: UIDevice.current.name)
        carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var canSend: Bool {
        CarrierPayload.canSend(text) && connectionState.isConnected && sendState != .sending
    }

    var canRestartConnection: Bool {
        connectionStatus == .disconnected && sendState != .sending
    }

    var connectionStatus: ConnectionStatus {
        switch connectionState {
        case .connected:
            .connected
        case .connecting:
            .connecting
        case .searching:
            .searching
        default:
            .disconnected
        }
    }

    var connectionStatusText: String {
        connectionStatus.displayText
    }

    var sendButtonText: String {
        switch sendState {
        case .sending:
            "Sending"
        case .sent:
            "Sent"
        default:
            "Send"
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        carrierService.start { [weak self] envelope, _ in
            self?.handle(envelope)
        }
    }

    func restartConnection() {
        carrierService.stop()
        hasStarted = false
        sendState = .idle
        start()
    }

    func send() {
        guard CarrierPayload.canSend(text) else {
            sendState = .failed("Text is empty")
            return
        }

        let payload = CarrierPayload(text: text)
        pendingPayloadID = payload.id
        sendState = .sending

        do {
            try carrierService.send(.text(payload))
        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }

    private func handle(_ envelope: CarrierEnvelope) {
        guard envelope.kind == .ack, envelope.ackID == pendingPayloadID else {
            return
        }

        pendingPayloadID = nil
        text = ""
        sendState = .sent
    }
}
