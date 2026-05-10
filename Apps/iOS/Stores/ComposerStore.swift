import Combine
import Foundation
import TypeCarrierCore
import UIKit

@MainActor
final class ComposerStore: ObservableObject {
    private static let maximumDraftCount = 99

    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    enum ConnectionStatus: Equatable {
        case idle
        case searching
        case connecting
        case connected

        var displayText: String {
            switch self {
            case .idle:
                "空闲"
            case .searching:
                "正在搜索"
            case .connecting:
                "正在连接"
            case .connected:
                "已连接"
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
    @Published private(set) var editorResetGeneration = 0
    @Published private(set) var draftLimitErrorMessage: String?

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
            sendState = .failed("历史记录存储不可用：\(error.localizedDescription)")
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
        guard sendState != .sending else {
            return false
        }

        switch connectionState {
        case .idle, .failed:
            return true
        default:
            return false
        }
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
            .idle
        }
    }

    var headerStatusText: String {
        switch connectionState {
        case .connecting(let peerName), .reconnecting(let peerName), .connected(let peerName):
            peerName
        case .searching:
            connectionState.localizedDisplayText
        default:
            connectionStatus.displayText
        }
    }

    var connectionFailureMessage: String? {
        if case .failed(let message) = connectionState {
            return message
        }
        return nil
    }

    var connectionRecoverySuggestion: String? {
        diagnostics.connectionRecoverySuggestion
    }

    var sendButtonText: String {
        switch sendState {
        case .sending:
            "发送中"
        case .sent:
            hasEditorText ? "发送" : "已发送"
        default:
            "发送"
        }
    }

    var drafts: [CarrierRecord] {
        records.filter { $0.kind == .draft }
    }

    var draftCount: Int {
        drafts.count
    }

    var draftBadgeText: String? {
        guard draftCount > 0 else {
            return nil
        }

        return "\(min(draftCount, Self.maximumDraftCount))"
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
            prefix: "ios-connection-events",
            now: now
        )
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
            sendState = .failed("文本为空")
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
            detail: "等待发送"
        )

        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            sendState = .failed("保存历史记录失败：\(error.localizedDescription)")
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
                detail: "已发送到 Mac"
            )
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
            sendState = .failed("文本为空")
            return
        }

        guard draftCount < Self.maximumDraftCount else {
            draftLimitErrorMessage = "请先处理或删除一些草稿，再保存新的草稿。"
            return
        }

        let now = Date()
        let record = CarrierRecord(
            kind: .draft,
            status: .draft,
            text: text,
            createdAt: now,
            updatedAt: now,
            detail: "已保存草稿"
        )

        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
            sendState = .sent
            if EditorTextReplacementPolicy.shouldClearEditorAfterDraftSave(succeeded: true) {
                replaceEditorText("", resetsHistory: true, rebuildsEditorWhenEmptying: false)
            }
        } catch {
            sendState = .failed("保存草稿失败：\(error.localizedDescription)")
        }
    }

    func dismissDraftLimitError() {
        draftLimitErrorMessage = nil
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
        replaceEditorText("", rebuildsEditorWhenEmptying: false)
        sendState = .idle
    }

    func undoTextChange() {
        guard let previous = textHistory.undo(current: text) else {
            return
        }

        replaceEditorTextAfterUndoRedo(previous)
        sendState = .idle
    }

    func redoTextChange() {
        guard let next = textHistory.redo(current: text) else {
            return
        }

        replaceEditorTextAfterUndoRedo(next)
        sendState = .idle
    }

    func updateText(for record: CarrierRecord, text: String) {
        var updated = record
        updated.text = text
        updated.updatedAt = Date()
        updated.detail = record.kind == .draft ? "已更新草稿" : "已编辑历史文本"

        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
        } catch {
            sendState = .failed("更新历史记录失败：\(error.localizedDescription)")
        }
    }

    func delete(_ record: CarrierRecord) {
        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        do {
            try recordStore.delete(id: record.id)
            syncRecords()
        } catch {
            sendState = .failed("删除历史记录失败：\(error.localizedDescription)")
        }
    }

    func deleteAllDrafts() {
        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        let draftIDs = drafts.map(\.id)
        guard !draftIDs.isEmpty else {
            return
        }

        do {
            for id in draftIDs {
                try recordStore.delete(id: id)
            }
            syncRecords()
        } catch {
            sendState = .failed("清空草稿失败：\(error.localizedDescription)")
            syncRecords()
        }
    }

    func deleteAllOutgoingHistory() {
        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        let outgoingIDs = outgoingHistory.map(\.id)
        guard !outgoingIDs.isEmpty else {
            return
        }

        do {
            for id in outgoingIDs {
                try recordStore.delete(id: id)
            }
            syncRecords()
        } catch {
            sendState = .failed("清空历史记录失败：\(error.localizedDescription)")
            syncRecords()
        }
    }

    private func handle(_ envelope: CarrierEnvelope) {
        if envelope.kind == .ack, envelope.ackID == pendingPayloadID {
            finishPendingSend(status: .sent, detail: "Mac 已确认收到")
        } else if envelope.kind == .receipt, let receipt = envelope.receipt, receipt.payloadID == pendingPayloadID {
            switch receipt.pasteStatus {
            case .received:
                finishPendingSend(
                    status: .received,
                    detail: receipt.detail ?? "Mac 已接收并保存文本",
                    pasteStatus: receipt.pasteStatus
                )
            case .posted:
                finishPendingSend(
                    status: .pastePosted,
                    detail: receipt.detail ?? "Mac 已插入文本",
                    pasteStatus: receipt.pasteStatus
                )
            case .failed:
                finishPendingSend(
                    status: .pasteFailed,
                    detail: receipt.detail ?? "Mac 粘贴失败",
                    pasteStatus: receipt.pasteStatus
                )
            }
        }
    }

    private func finishPendingSend(
        status: CarrierRecord.Status,
        detail: String,
        pasteStatus: CarrierDeliveryReceipt.PasteStatus? = nil
    ) {
        if let pendingRecordID {
            updateRecord(id: pendingRecordID, status: status, detail: detail)
        }
        pendingPayloadID = nil
        pendingRecordID = nil
        sendState = .sent

        if let pasteStatus, EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(pasteStatus) {
            replaceEditorText("", resetsHistory: true, rebuildsEditorWhenEmptying: false)
        }
    }

    private func updateRecord(id: UUID, status: CarrierRecord.Status, detail: String?) {
        guard var record = records.first(where: { $0.id == id }) else {
            return
        }

        record.status = status
        record.detail = detail
        record.updatedAt = Date()

        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            sendState = .failed("更新历史记录失败：\(error.localizedDescription)")
        }
    }

    private func syncRecords() {
        records = recordStore?.records ?? []
    }

    private func replaceEditorText(
        _ newText: String,
        resetsHistory: Bool = false,
        rebuildsEditorWhenEmptying: Bool = true
    ) {
        let previousText = text
        shouldRecordTextChange = false
        text = newText
        shouldRecordTextChange = true
        editorResetGeneration = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: previousText,
            newText: newText,
            currentGeneration: editorResetGeneration,
            rebuildsWhenEmptying: rebuildsEditorWhenEmptying
        )

        if resetsHistory {
            textHistory.reset()
        }
    }

    private func replaceEditorTextAfterUndoRedo(_ newText: String) {
        let previousText = text
        shouldRecordTextChange = false
        text = newText
        shouldRecordTextChange = true
        editorResetGeneration = EditorTextReplacementPolicy.nextEditorGenerationAfterUndoRedo(
            currentText: previousText,
            newText: newText,
            currentGeneration: editorResetGeneration
        )
    }
}
