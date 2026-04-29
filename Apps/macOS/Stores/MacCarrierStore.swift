import AppKit
import Combine
import Foundation
import TypeCarrierCore

@MainActor
final class MacCarrierStore: ObservableObject {
    @Published private(set) var lastPayloadText = ""
    @Published private(set) var lastPasteResult = PasteInjectionResult.idle
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var records: [CarrierRecord] = []

    let carrierService: MultipeerCarrierService
    private let recordStore: CarrierRecordStore?
    private let pasteInjector = PasteInjector()
    private let permissionChecker = AccessibilityPermissionChecker()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        carrierService = MultipeerCarrierService(role: .receiver, displayName: Host.current().localizedName ?? "TypeCarrier Mac")
        do {
            recordStore = try CarrierRecordStore(
                fileURL: try CarrierRecordStore.defaultFileURL(fileName: "mac-records.json")
            )
            records = recordStore?.records ?? []
        } catch {
            recordStore = nil
            records = []
            lastPasteResult = PasteInjectionResult(status: "History storage unavailable: \(error.localizedDescription)", succeeded: false)
        }

        carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refreshAccessibilityStatus()
        start()
    }

    var menuBarSystemImage: String {
        carrierService.connectionState.isConnected ? "keyboard.badge.ellipsis" : "keyboard"
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var lastPayloadPreview: String {
        guard !lastPayloadText.isEmpty else {
            return "No payload received"
        }

        return String(lastPayloadText.prefix(160))
    }

    var receivedHistory: [CarrierRecord] {
        records.filter { $0.kind == .incoming }
    }

    func start() {
        carrierService.start { [weak self] envelope, _ in
            self?.handle(envelope)
        }
    }

    func restart() {
        carrierService.stop()
        start()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: true)
        permissionChecker.openAccessibilitySettings()
    }

    func pasteTestText() {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: "Hello from TypeCarrier")
    }

    func paste(record: CarrierRecord) {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: record.text)
        updateRecordAfterPaste(record, result: lastPasteResult)
    }

    func updateText(for record: CarrierRecord, text: String) {
        var updated = record
        updated.text = text
        updated.updatedAt = Date()
        updated.detail = "Edited received text"

        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "History storage unavailable", succeeded: false)
            return
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
        } catch {
            lastPasteResult = PasteInjectionResult(status: "Failed to update history: \(error.localizedDescription)", succeeded: false)
        }
    }

    func delete(_ record: CarrierRecord) {
        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "History storage unavailable", succeeded: false)
            return
        }

        do {
            try recordStore.delete(id: record.id)
            syncRecords()
        } catch {
            lastPasteResult = PasteInjectionResult(status: "Failed to delete history: \(error.localizedDescription)", succeeded: false)
        }
    }

    private func handle(_ envelope: CarrierEnvelope) {
        guard envelope.kind == .text, let payload = envelope.payload else {
            return
        }

        refreshAccessibilityStatus()
        lastPayloadText = payload.text
        let now = Date()
        let record = CarrierRecord(
            payloadID: payload.id,
            kind: .incoming,
            status: .received,
            text: payload.text,
            createdAt: now,
            updatedAt: now,
            detail: "Received from iPhone"
        )

        guard let recordStore else {
            let detail = "History storage unavailable"
            lastPasteResult = PasteInjectionResult(status: detail, succeeded: false)
            sendReceipt(payloadID: payload.id, pasteStatus: .failed, detail: detail)
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            let detail = "Failed to save received text: \(error.localizedDescription)"
            lastPasteResult = PasteInjectionResult(status: detail, succeeded: false)
            sendReceipt(payloadID: payload.id, pasteStatus: .failed, detail: detail)
            return
        }

        lastPasteResult = pasteInjector.paste(text: payload.text)
        updateRecordAfterPaste(record, result: lastPasteResult)
        sendReceipt(
            payloadID: payload.id,
            pasteStatus: lastPasteResult.succeeded ? .posted : .failed,
            detail: lastPasteResult.status
        )
    }

    private func updateRecordAfterPaste(_ record: CarrierRecord, result: PasteInjectionResult) {
        var updated = record
        updated.status = result.succeeded ? .pastePosted : .pasteFailed
        updated.updatedAt = result.date
        updated.detail = result.status

        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "History storage unavailable", succeeded: false)
            return
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
        } catch {
            lastPasteResult = PasteInjectionResult(status: "Failed to update paste result: \(error.localizedDescription)", succeeded: false)
        }
    }

    private func sendReceipt(payloadID: UUID, pasteStatus: CarrierDeliveryReceipt.PasteStatus, detail: String) {
        let receipt = CarrierDeliveryReceipt(
            payloadID: payloadID,
            pasteStatus: pasteStatus,
            detail: detail
        )
        try? carrierService.send(.receipt(receipt))
    }

    private func syncRecords() {
        records = recordStore?.records ?? []
    }
}
