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

    @Published var text = "" {
        didSet {
            guard shouldRecordTextChange else {
                return
            }

            textHistory.recordChange(from: oldValue, to: text)
        }
    }
    @Published private(set) var sendState: SendState = .idle
    @Published private(set) var records: [CarrierRecord] = []

    let carrierService: MultipeerCarrierService
    let connectionDiagnosticLogFileURL: URL?
    private let recordStore: CarrierRecordStore?
    private var pendingPayloadID: UUID?
    private var pendingRecordID: UUID?
    private var hasStarted = false
    private let backgroundDisconnectGraceSeconds: TimeInterval
    private let resumeRecoverySearchTimeout: Duration = .seconds(25)
    private var backgroundStopTask: Task<Void, Never>?
    private var foregroundRecovery: ForegroundConnectionRecovery
    private var textHistory = TextEditHistory()
    private var shouldRecordTextChange = true
    private var cancellables: Set<AnyCancellable> = []

    init(backgroundDisconnectGraceSeconds: TimeInterval = 12) {
        self.backgroundDisconnectGraceSeconds = backgroundDisconnectGraceSeconds
        foregroundRecovery = ForegroundConnectionRecovery(
            backgroundDisconnectGraceSeconds: backgroundDisconnectGraceSeconds
        )
        connectionDiagnosticLogFileURL = try? CarrierDiagnosticLogStore.defaultFileURL(fileName: "ios-connection-events.jsonl")
        carrierService = MultipeerCarrierService(
            role: .sender,
            displayName: UIDevice.current.name,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
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

        carrierService.$connectionState
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleConnectionStateChanged(state)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppDidBecomeActive()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppDidEnterBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppWillTerminate()
                }
            }
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
        case .connecting, .reconnecting:
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
        switch connectionState {
        case .connecting(let peerName), .reconnecting(let peerName), .connected(let peerName):
            peerName
        case .searching:
            connectionState.displayText
        default:
            connectionStatus.displayText
        }
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

    var canUndo: Bool {
        textHistory.canUndo
    }

    var canRedo: Bool {
        textHistory.canRedo
    }

    var hasEditorText: Bool {
        !text.isEmpty
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
        cancelBackgroundStop()
        carrierService.stop()
        hasStarted = false
        sendState = .idle
        start()
    }

    func refreshConnectionAfterAppBecameActive() {
        guard hasStarted, sendState != .sending, !connectionState.isConnected else {
            return
        }

        carrierService.stop()
        hasStarted = false
        start()
    }

    private func handleAppDidEnterBackground() {
        cancelBackgroundStop()
        foregroundRecovery.didEnterBackground(at: Date())

        guard hasStarted, sendState != .sending else {
            return
        }

        carrierService.recordDiagnosticMarker(
            "app.backgroundGraceStarted",
            message: "Will disconnect after \(backgroundDisconnectGraceSeconds) seconds in background."
        )

        let graceSeconds = backgroundDisconnectGraceSeconds
        backgroundStopTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, graceSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.disconnectAfterBackgroundGrace()
        }
    }

    private func handleAppDidBecomeActive() {
        cancelBackgroundStop()

        let action = foregroundRecovery.didBecomeActive(
            at: Date(),
            hasStarted: hasStarted,
            isSending: sendState == .sending,
            isConnected: connectionState.isConnected
        )
        switch action {
        case .none:
            return
        case .resumeFastPath(let message):
            carrierService.recordDiagnosticMarker(
                "app.resumeFastPath",
                message: message
            )
            return
        case .resumeFreshConnect(let restartsExistingService, let message):
            carrierService.recordDiagnosticMarker(
                "app.resumeFreshConnect",
                message: message
            )
            startResumeRecovery(restartsExistingService: restartsExistingService)
            return
        }
    }

    private func handleConnectionStateChanged(_ state: ConnectionState) {
        guard sendState != .sending else {
            return
        }

        let action = foregroundRecovery.didChangeConnectionState(
            isConnected: state.isConnected,
            isIdleOrFailed: state == .idle || state.isFailed,
            displayText: state.displayText
        )
        switch action {
        case .none:
            return
        case .resumeFreshRetry(let message):
            carrierService.recordDiagnosticMarker(
                "app.resumeFreshRetry",
                message: message
            )
            startResumeRecovery(restartsExistingService: true, keepsRetryBudget: true)
        }
    }

    private func startResumeRecovery(restartsExistingService: Bool, keepsRetryBudget: Bool = false) {
        foregroundRecovery.beginResumeRecovery(
            restartsExistingService: restartsExistingService,
            keepsRetryBudget: keepsRetryBudget
        )
        if restartsExistingService, hasStarted {
            carrierService.stop()
            hasStarted = false
        }

        sendState = .idle
        start()
        carrierService.extendCurrentSearchTimeoutForResumeRecovery(to: resumeRecoverySearchTimeout)
    }

    private func handleAppWillTerminate() {
        cancelBackgroundStop()
        foregroundRecovery.didTerminate()

        guard hasStarted else {
            return
        }

        carrierService.recordDiagnosticMarker(
            "app.willTerminateDisconnect",
            message: "Disconnecting before app termination."
        )
        carrierService.stop()
        hasStarted = false
    }

    private func disconnectAfterBackgroundGrace() {
        guard hasStarted, foregroundRecovery.isInBackground, sendState != .sending else {
            return
        }

        carrierService.stop()
        hasStarted = false
        foregroundRecovery.didDisconnectAfterBackgroundGrace()
        carrierService.recordDiagnosticMarker(
            "app.backgroundDisconnected",
            message: "Disconnected after \(backgroundDisconnectGraceSeconds) seconds in background."
        )
    }

    private func cancelBackgroundStop() {
        backgroundStopTask?.cancel()
        backgroundStopTask = nil
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
            replaceEditorText("", resetsHistory: true)
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
        replaceEditorText(record.text, resetsHistory: true)
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
        replaceEditorText(record.text, resetsHistory: true)
        sendState = .idle
    }

    func copyText() {
        guard hasEditorText else {
            return
        }

        UIPasteboard.general.string = text
    }

    func clearText() {
        guard hasEditorText else {
            return
        }

        textHistory.recordChange(from: text, to: "")
        replaceEditorText("")
        sendState = .idle
    }

    func undoTextChange() {
        guard let previous = textHistory.undo(current: text) else {
            return
        }

        replaceEditorText(previous)
        sendState = .idle
    }

    func redoTextChange() {
        guard let next = textHistory.redo(current: text) else {
            return
        }

        replaceEditorText(next)
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

    private func replaceEditorText(_ newText: String, resetsHistory: Bool = false) {
        shouldRecordTextChange = false
        text = newText
        shouldRecordTextChange = true

        if resetsHistory {
            textHistory.reset()
        }
    }
}
