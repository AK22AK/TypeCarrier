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
    @Published private(set) var records: [CarrierRecord] = []

    let carrierService: MultipeerCarrierService
    private let recordStore: CarrierRecordStore?
    private var pendingPayloadID: UUID?
    private var pendingRecordID: UUID?
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        carrierService = MultipeerCarrierService(role: .sender, displayName: UIDevice.current.name)
        do {
            recordStore = try CarrierRecordStore(
                fileURL: try CarrierRecordStore.defaultFileURL(fileName: "ios-records.json")
            )
            records = recordStore?.records ?? []
        } catch {
            recordStore = nil
            records = []
            sendState = .failed("History storage unavailable: \(error.localizedDescription)")
        }

        carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var diagnostics: CarrierDiagnostics {
        carrierService.diagnostics
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

    var headerStatusText: String {
        connectionState.peerName ?? connectionState.displayText
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

    var drafts: [CarrierRecord] {
        records.filter { $0.kind == .draft }
    }

    var outgoingHistory: [CarrierRecord] {
        records.filter { $0.kind == .outgoing }
    }

    var canSaveDraft: Bool {
        CarrierPayload.canSend(text)
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

        let textToSend = text
        let payload = CarrierPayload(text: textToSend)
        let now = Date()
        let record = CarrierRecord(
            payloadID: payload.id,
            kind: .outgoing,
            status: .queued,
            text: textToSend,
            createdAt: now,
            updatedAt: now,
            detail: "Queued for sending"
        )

        guard let recordStore else {
            sendState = .failed("History storage unavailable")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            sendState = .failed("Failed to save history: \(error.localizedDescription)")
            return
        }

        pendingPayloadID = payload.id
        pendingRecordID = record.id
        sendState = .sending

        do {
            try carrierService.send(.text(payload))
            updateRecord(
                id: record.id,
                status: .sent,
                detail: "Sent to Mac"
            )
            text = ""
        } catch {
            pendingPayloadID = nil
            pendingRecordID = nil
            updateRecord(
                id: record.id,
                status: .failed,
                detail: error.localizedDescription
            )
            sendState = .failed(error.localizedDescription)
        }
    }

    func send(record: CarrierRecord) {
        text = record.text
        send()
    }

    func saveDraft() {
        guard CarrierPayload.canSend(text) else {
            sendState = .failed("Text is empty")
            return
        }

        let now = Date()
        let record = CarrierRecord(
            kind: .draft,
            status: .draft,
            text: text,
            createdAt: now,
            updatedAt: now,
            detail: "Saved draft"
        )

        guard let recordStore else {
            sendState = .failed("History storage unavailable")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
            sendState = .sent
        } catch {
            sendState = .failed("Failed to save draft: \(error.localizedDescription)")
        }
    }

    func loadIntoEditor(_ record: CarrierRecord) {
        text = record.text
        sendState = .idle
    }

    func updateText(for record: CarrierRecord, text: String) {
        var updated = record
        updated.text = text
        updated.updatedAt = Date()
        updated.detail = record.kind == .draft ? "Updated draft" : "Edited history text"

        guard let recordStore else {
            sendState = .failed("History storage unavailable")
            return
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
        } catch {
            sendState = .failed("Failed to update history: \(error.localizedDescription)")
        }
    }

    func delete(_ record: CarrierRecord) {
        guard let recordStore else {
            sendState = .failed("History storage unavailable")
            return
        }

        do {
            try recordStore.delete(id: record.id)
            syncRecords()
        } catch {
            sendState = .failed("Failed to delete history: \(error.localizedDescription)")
        }
    }

    private func handle(_ envelope: CarrierEnvelope) {
        if envelope.kind == .ack, envelope.ackID == pendingPayloadID {
            finishPendingSend(status: .sent, detail: "Mac acknowledged receipt")
        } else if envelope.kind == .receipt, let receipt = envelope.receipt, receipt.payloadID == pendingPayloadID {
            switch receipt.pasteStatus {
            case .received:
                finishPendingSend(status: .received, detail: receipt.detail ?? "Mac received and saved text")
            case .posted:
                finishPendingSend(status: .pastePosted, detail: receipt.detail ?? "Mac posted paste command")
            case .failed:
                finishPendingSend(status: .pasteFailed, detail: receipt.detail ?? "Mac paste failed")
            }
        }
    }

    private func finishPendingSend(status: CarrierRecord.Status, detail: String) {
        if let pendingRecordID {
            updateRecord(id: pendingRecordID, status: status, detail: detail)
        }
        pendingPayloadID = nil
        pendingRecordID = nil
        sendState = .sent
    }

    private func updateRecord(id: UUID, status: CarrierRecord.Status, detail: String?) {
        guard var record = records.first(where: { $0.id == id }) else {
            return
        }

        record.status = status
        record.detail = detail
        record.updatedAt = Date()

        guard let recordStore else {
            sendState = .failed("History storage unavailable")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            sendState = .failed("Failed to update history: \(error.localizedDescription)")
        }
    }

    private func syncRecords() {
        records = recordStore?.records ?? []
    }
}
