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
    @Published private(set) var lastDiagnosticExportURL: URL?
    @Published private(set) var lastDiagnosticExportErrorMessage: String?

    @Published private(set) var carrierService: MultipeerCarrierService
    let connectionDiagnosticLogFileURL: URL?
    private let receiverDisplayName: String
    private let recordStore: CarrierRecordStore?
    private let pasteInjector = PasteInjector()
    private let permissionChecker = AccessibilityPermissionChecker()
    private var carrierServiceCancellable: AnyCancellable?

    init() {
        connectionDiagnosticLogFileURL = try? CarrierDiagnosticLogStore.defaultFileURL(fileName: "mac-connection-events.jsonl")
        receiverDisplayName = Host.current().localizedName ?? "TypeCarrier Mac"
        carrierService = Self.makeCarrierService(
            displayName: receiverDisplayName,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
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

        bindCarrierService()
        refreshAccessibilityStatus()
        start()
    }

    var menuBarSystemImage: String {
        if receiverHealthWarning != nil {
            return "exclamationmark.triangle"
        }

        return carrierService.connectionState.isConnected ? "keyboard.badge.ellipsis" : "keyboard"
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var receiverHealthWarning: String? {
        if connectionState.isFailed || carrierService.diagnostics.lastErrorMessage != nil {
            return "Connection issue. Try Restart Receiver."
        }

        return nil
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
        rebuildReceiverService(rebuiltReason: "receiver.restart.rebuilt")
    }

    private func rebuildReceiverService(rebuiltReason: String) {
        carrierService.stop()
        carrierServiceCancellable = nil
        carrierService = Self.makeCarrierService(
            displayName: receiverDisplayName,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
        bindCarrierService()
        start()
        carrierService.recordDiagnosticMarker(
            rebuiltReason,
            message: "Created a fresh receiver service after restart."
        )
    }

    func restartFromUserAction() {
        restart(
            reason: "receiver.restart.user",
            message: "User requested receiver restart."
        )
    }

    func restartAfterWake(notificationName: String, sleepDuration: TimeInterval?) {
        let durationText = sleepDuration.map(Self.formattedDuration) ?? "unknown"
        restart(
            reason: "receiver.restart.wake",
            message: "Restarting receiver after \(notificationName); sleep duration: \(durationText)."
        )
    }

    func recordLifecycleMarker(_ name: String, message: String) {
        carrierService.recordDiagnosticMarker(name, message: message)
    }

    func exportConnectionDiagnosticsToFinder(now: Date = Date()) {
        do {
            let exportURL = try makeConnectionDiagnosticExportURL(now: now)
            lastDiagnosticExportURL = exportURL
            lastDiagnosticExportErrorMessage = nil
            NSWorkspace.shared.activateFileViewerSelecting([exportURL])
        } catch {
            lastDiagnosticExportErrorMessage = error.localizedDescription
        }
    }

    func makeConnectionDiagnosticExportURL(now: Date = Date()) throws -> URL {
        guard let connectionDiagnosticLogFileURL else {
            throw CarrierDiagnosticExportError.missingLogFile
        }

        carrierService.recordDiagnosticMarker(
            "diagnostic.exportPrepared",
            message: "Prepared timestamped diagnostic export."
        )
        return try CarrierDiagnosticExport.createTimestampedCopy(
            sourceURL: connectionDiagnosticLogFileURL,
            directory: CarrierDiagnosticExport.defaultExportDirectory(),
            prefix: "mac-connection-events",
            now: now
        )
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: true)
        permissionChecker.openAccessibilitySettings()
    }

    private func restart(reason: String, message: String) {
        carrierService.recordDiagnosticMarker(reason, message: message)
        restart()
    }

    private static func makeCarrierService(
        displayName: String,
        diagnosticLogFileURL: URL?
    ) -> MultipeerCarrierService {
        MultipeerCarrierService(
            role: .receiver,
            displayName: displayName,
            diagnosticLogFileURL: diagnosticLogFileURL
        )
    }

    private func bindCarrierService() {
        carrierServiceCancellable = carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration >= 0 else {
            return "unknown"
        }

        if duration < 60 {
            return String(format: "%.1fs", duration)
        }

        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }

        return "\(minutes)m \(seconds)s"
    }

    func pasteTestText() {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: "Hello from TypeCarrier")
        recordPasteDiagnostic(lastPasteResult)
    }

    func paste(record: CarrierRecord) {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: record.text)
        recordPasteDiagnostic(lastPasteResult)
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
        recordPasteDiagnostic(lastPasteResult)
        updateRecordAfterPaste(record, result: lastPasteResult)
        sendReceipt(
            payloadID: payload.id,
            pasteStatus: lastPasteResult.succeeded ? .posted : .failed,
            detail: lastPasteResult.fullDetail
        )
    }

    private func updateRecordAfterPaste(_ record: CarrierRecord, result: PasteInjectionResult) {
        var updated = record
        updated.status = result.succeeded ? .pastePosted : .pasteFailed
        updated.updatedAt = result.date
        updated.detail = result.fullDetail

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

    private func recordPasteDiagnostic(_ result: PasteInjectionResult) {
        carrierService.recordDiagnosticMarker(
            result.succeeded ? "paste.injection.succeeded" : "paste.injection.failed",
            message: result.fullDetail
        )
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
