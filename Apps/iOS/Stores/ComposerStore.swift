import Combine
import Foundation
import TypeCarrierCore
import UIKit

@MainActor
final class ComposerStore: ObservableObject {
    private static let maximumDraftCount = ComposerRecordStore.maximumDraftCount

    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)

        var diagnosticName: String {
            switch self {
            case .idle:
                "idle"
            case .sending:
                "sending"
            case .sent:
                "sent"
            case .failed:
                "failed"
            }
        }
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
    @Published private(set) var historyRetention: SendHistoryRetention = .default
    @Published private(set) var historyRetentionErrorMessage: String?
    @Published private(set) var customSenderDisplayName: String

    @Published private(set) var carrierService: MultipeerCarrierService
    let debugDiagnosticLogFileURL: URL?
    private let recordStore: ComposerRecordStore?
    private let systemDeviceName: String
    private let senderDeviceID: String
    @Published private(set) var targetSelection: ReceiverTargetSelection
    private let userDefaults: UserDefaults
    private let deliveryConfirmationWait: DeliveryConfirmationWait
    private var pendingRecordID: UUID?
    private var pendingSendPreservesActiveInputSession = false
    private var hasStarted = false
    private let backgroundDisconnectGraceSeconds: TimeInterval
    private let resumeRecoverySearchTimeout: Duration = .seconds(25)
    private var backgroundStopTask: Task<Void, Never>?
    private var foregroundRecovery: ForegroundConnectionRecovery
    private var textHistory = TextEditHistory()
    private var shouldRecordTextChange = true
    private var carrierServiceCancellables: Set<AnyCancellable> = []
    private var cancellables: Set<AnyCancellable> = []

    init(
        backgroundDisconnectGraceSeconds: TimeInterval = 12,
        deliveryConfirmationTimeout: Duration = .seconds(5),
        userDefaults: UserDefaults = .standard,
        systemDeviceName: String = UIDevice.current.name
    ) {
        let storedCustomSenderDisplayName = userDefaults.string(forKey: ComposerPreferenceKeys.senderDisplayName) ?? ""
        self.backgroundDisconnectGraceSeconds = backgroundDisconnectGraceSeconds
        deliveryConfirmationWait = DeliveryConfirmationWait(timeout: deliveryConfirmationTimeout)
        self.userDefaults = userDefaults
        self.systemDeviceName = systemDeviceName
        let deviceID = userDefaults.string(forKey: "senderStableDeviceID") ?? UUID().uuidString
        senderDeviceID = deviceID
        userDefaults.set(deviceID, forKey: "senderStableDeviceID")
        targetSelection = ReceiverTargetSelection()
        customSenderDisplayName = storedCustomSenderDisplayName
        foregroundRecovery = ForegroundConnectionRecovery(
            backgroundDisconnectGraceSeconds: backgroundDisconnectGraceSeconds
        )
        debugDiagnosticLogFileURL = try? CarrierDiagnosticLogStore.defaultFileURL(fileName: "ios-debug-events.jsonl")
        carrierService = Self.makeCarrierService(
            displayName: CarrierDeviceIdentity.preferredDisplayName(
                customName: storedCustomSenderDisplayName,
                systemName: systemDeviceName
            ),
            deviceID: senderDeviceID,
            diagnosticLogFileURL: debugDiagnosticLogFileURL
        )
        do {
            let directory = try CarrierRecordStore.defaultFileURL(fileName: "ios-drafts.json").deletingLastPathComponent()
            recordStore = try ComposerRecordStore(directory: directory)
            records = recordStore?.records ?? []
            historyRetention = recordStore?.retention ?? .default
        } catch {
            recordStore = nil
            records = []
            sendState = .failed("历史记录存储不可用：\(error.localizedDescription)")
        }

        bindCarrierService()

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

    var senderDisplayName: String {
        CarrierDeviceIdentity.preferredDisplayName(
            customName: customSenderDisplayName,
            systemName: systemDeviceName
        )
    }

    var canSend: Bool {
        CarrierPayload.canSend(text) && selectedTarget != nil && sendState != .sending
    }

    var canRestartConnection: Bool {
        guard sendState != .sending else {
            return false
        }

        return connectionState.isManualRestartEligible
    }

    var connectionStatus: ConnectionStatus {
        if !connectedReceivers.isEmpty { return .connected }
        if !connectingReceivers.isEmpty { return .connecting }
        return switch connectionState {
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

    var connectedReceivers: [CarrierPeer] {
        carrierService.connectedPeers.filter { $0.role == .receiver }
    }

    var selectedTarget: CarrierPeer? { targetSelection.target(in: connectedReceivers) }

    var connectingReceivers: [CarrierPeer] {
        carrierService.connectingPeers.filter { $0.role == .receiver }
    }

    var showsTargetPicker: Bool { connectedReceivers.count >= 2 }

    var headerStatusText: String {
        if let target = selectedTarget { return target.displayName }
        if connectingReceivers.count > 1 { return "连接 \(connectingReceivers.count) 台" }
        if let peer = connectingReceivers.first { return peer.displayName }
        if let name = connectionState.peerName { return name }
        return connectionStatus.displayText
    }

    var headerAccessibilityText: String {
        if let target = selectedTarget { return "已连接 \(target.displayName)" }
        if connectingReceivers.count > 1 { return "正在连接 \(connectingReceivers.count) 台设备" }
        if let peer = connectingReceivers.first { return "正在连接 \(peer.displayName)" }
        if let name = connectionState.peerName { return "正在连接 \(name)" }
        return connectionStatus.displayText
    }

    func selectReceiver(_ peer: CarrierPeer) {
        guard connectedReceivers.contains(where: { $0.id == peer.id }) else { return }
        targetSelection.select(peer)
    }

    private func reconcileTargets() {
        targetSelection.reconcile(connected: connectedReceivers)
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

        return "\(draftCount)"
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
        carrierService.start { [weak self] envelope, peer in
            self?.handle(envelope, sourceID: self?.carrierService.peerIdentity(for: peer).id)
        }
    }

    func restartConnection() {
        cancelBackgroundStop()
        carrierService.stop()
        hasStarted = false
        sendState = .idle
        start()
    }

    func setCustomSenderDisplayName(_ name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDisplayName = senderDisplayName
        customSenderDisplayName = normalizedName

        if normalizedName.isEmpty {
            userDefaults.removeObject(forKey: ComposerPreferenceKeys.senderDisplayName)
        } else {
            userDefaults.set(normalizedName, forKey: ComposerPreferenceKeys.senderDisplayName)
        }

        guard senderDisplayName != oldDisplayName else {
            return
        }

        rebuildSenderService(rebuiltReason: "sender.displayName.updated")
    }

    func makeDebugDiagnosticExportURL(now: Date = Date()) throws -> URL {
        guard let debugDiagnosticLogFileURL else {
            throw CarrierDiagnosticExportError.missingLogFile
        }

        carrierService.recordDiagnosticMarker(
            "diagnostic.exportPrepared",
            message: "Prepared timestamped debug diagnostic export."
        )
        return try CarrierDiagnosticExport.createTimestampedCopy(
            sourceURL: debugDiagnosticLogFileURL,
            directory: CarrierDiagnosticExport.defaultExportDirectory(),
            prefix: "ios-debug-events",
            now: now
        )
    }

    private static func makeCarrierService(
        displayName: String,
        deviceID: String,
        diagnosticLogFileURL: URL?
    ) -> MultipeerCarrierService {
        MultipeerCarrierService(
            role: .sender,
            displayName: displayName,
            deviceID: deviceID,
            diagnosticLogFileURL: diagnosticLogFileURL
        )
    }

    private func rebuildSenderService(rebuiltReason: String) {
        let shouldRestart = hasStarted
        carrierService.stop()
        carrierServiceCancellables.removeAll()
        carrierService = Self.makeCarrierService(
            displayName: senderDisplayName,
            deviceID: senderDeviceID,
            diagnosticLogFileURL: debugDiagnosticLogFileURL
        )
        bindCarrierService()
        hasStarted = false

        guard shouldRestart else {
            return
        }

        sendState = .idle
        start()
        carrierService.recordDiagnosticMarker(
            rebuiltReason,
            message: "Created a fresh sender service with displayName=\(senderDisplayName)."
        )
    }

    private func bindCarrierService() {
        carrierServiceCancellables.removeAll()

        carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &carrierServiceCancellables)

        carrierService.$connectionState
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleConnectionStateChanged(state)
                }
            }
            .store(in: &carrierServiceCancellables)
        carrierService.$connectedPeers
            .sink { [weak self] peers in
                // Consume each published snapshot directly so rapid disconnect/reconnect
                // events cannot be collapsed into a later service state.
                self?.targetSelection.reconcile(connected: peers)
            }
            .store(in: &carrierServiceCancellables)
    }

    func recordEditorDiagnosticMarker(
        _ name: String,
        modelTextLength: Int,
        visibleTextLength: Int,
        visibleTextLengthAfterSync: Int? = nil,
        isFocused: Bool,
        isFirstResponder: Bool,
        source: String
    ) {
        var parts = [
            "source=\(source)",
            "modelLength=\(modelTextLength)",
            "visibleLength=\(visibleTextLength)",
            "focused=\(isFocused)",
            "firstResponder=\(isFirstResponder)",
            "hasEditorText=\(hasEditorText)",
            "canSend=\(canSend)",
            "canSaveDraft=\(canSaveDraft)",
            "sendState=\(sendState.diagnosticName)",
            "editorResetGeneration=\(editorResetGeneration)"
        ]

        if let visibleTextLengthAfterSync {
            parts.append("visibleLengthAfterSync=\(visibleTextLengthAfterSync)")
        }

        carrierService.recordDiagnosticMarker(
            name,
            message: parts.joined(separator: " ")
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
        cleanOutgoingHistory()
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

    func send(
        preservesActiveInputSession: Bool = false,
        postPasteAction: CarrierPostPasteAction? = nil
    ) {
        guard CarrierPayload.canSend(text) else {
            sendState = .failed("文本为空")
            return
        }

        guard sendState != .sending else { return }
        reconcileTargets()
        guard let target = selectedTarget else {
            sendState = .failed("目标 Mac 未连接")
            return
        }
        let textToSend = text
        let payload = CarrierPayload(text: textToSend, postPasteAction: postPasteAction)
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

        pendingRecordID = record.id
        pendingSendPreservesActiveInputSession = preservesActiveInputSession
        sendState = .sending
        deliveryConfirmationWait.begin(payloadID: payload.id, targetID: target.id) { [weak self] in
            self?.handleDeliveryConfirmationTimeout()
        }

        do {
            try carrierService.send(.text(
                payload,
                sender: CarrierDeviceIdentity(displayName: senderDisplayName, deviceID: senderDeviceID)
            ), to: target.id)
            updateRecord(
                id: record.id,
                status: .sent,
                detail: "已发送到 Mac"
            )
        } catch {
            deliveryConfirmationWait.cancel()
            pendingRecordID = nil
            pendingSendPreservesActiveInputSession = false
            updateRecord(
                id: record.id,
                status: .failed,
                detail: error.localizedDescription
            )
            sendState = .failed(error.localizedDescription)
            reconcileTargets()
        }
    }

    func send(record: CarrierRecord) {
        replaceEditorText(record.text, resetsHistory: true)
        send()
    }

    func saveDraft(preservesActiveInputSession: Bool = false) {
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
                replaceEditorText(
                    "",
                    resetsHistory: true,
                    rebuildsEditorWhenEmptying: !preservesActiveInputSession
                )
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

    func clearText(preservesActiveInputSession: Bool = false) {
        guard hasEditorText else {
            return
        }

        textHistory.recordChange(from: text, to: "")
        replaceEditorText("", rebuildsEditorWhenEmptying: !preservesActiveInputSession)
        sendState = .idle
    }

    func undoTextChange(preservesActiveInputSession: Bool = false) {
        guard let previous = textHistory.undo(current: text) else {
            return
        }

        replaceEditorTextAfterUndoRedo(
            previous,
            rebuildsEditorWhenEmptying: !preservesActiveInputSession
        )
        sendState = .idle
    }

    func redoTextChange(preservesActiveInputSession: Bool = false) {
        guard let next = textHistory.redo(current: text) else {
            return
        }

        replaceEditorTextAfterUndoRedo(
            next,
            rebuildsEditorWhenEmptying: !preservesActiveInputSession
        )
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

        do {
            try recordStore.clearDrafts()
            syncRecords()
        } catch {
            sendState = .failed("清空草稿失败：\(error.localizedDescription)")
        }
    }

    func deleteAllOutgoingHistory() {
        guard let recordStore else {
            sendState = .failed("历史记录存储不可用")
            return
        }
        do {
            try recordStore.clearHistory()
            syncRecords()
        } catch {
            sendState = .failed("清空历史记录失败：\(error.localizedDescription)")
        }
    }

    func setHistoryRetention(_ retention: SendHistoryRetention) {
        guard let recordStore else {
            historyRetentionErrorMessage = "历史记录存储不可用"
            return
        }
        do {
            try recordStore.setRetention(retention)
            historyRetention = recordStore.retention
            historyRetentionErrorMessage = nil
            syncRecords()
        } catch {
            historyRetentionErrorMessage = "更新历史保留设置失败：\(error.localizedDescription)"
        }
    }

    private func cleanOutgoingHistory() {
        guard let recordStore else { return }
        do {
            try recordStore.cleanHistory()
            syncRecords()
            historyRetentionErrorMessage = nil
        } catch {
            historyRetentionErrorMessage = "清理历史记录失败：\(error.localizedDescription)"
        }
    }

    private func handle(_ envelope: CarrierEnvelope, sourceID: String?) {
        if envelope.kind == .ack, let ackID = envelope.ackID,
           deliveryConfirmationWait.confirm(payloadID: ackID, sourceID: sourceID) {
            finishPendingSend(
                status: .received,
                detail: "Mac 已确认收到",
                pasteStatus: .received
            )
        } else if envelope.kind == .receipt, let receipt = envelope.receipt,
                  deliveryConfirmationWait.confirm(payloadID: receipt.payloadID, sourceID: sourceID) {
            finishPendingSend(
                status: .received,
                detail: receipt.detail ?? "Mac 已接收文本",
                pasteStatus: receipt.pasteStatus
            )
        }
    }

    private func handleDeliveryConfirmationTimeout() {
        let detail = "发送超时，请检查 Mac 端接收结果"
        if let pendingRecordID {
            updateRecord(id: pendingRecordID, status: .failed, detail: detail)
        }
        pendingRecordID = nil
        pendingSendPreservesActiveInputSession = false
        sendState = .failed(detail)
        reconcileTargets()
    }

    private func finishPendingSend(
        status: CarrierRecord.Status,
        detail: String,
        pasteStatus: CarrierDeliveryReceipt.PasteStatus? = nil
    ) {
        if let pendingRecordID {
            updateRecord(id: pendingRecordID, status: status, detail: detail)
        }

        pendingRecordID = nil
        sendState = .sent

        if let pasteStatus, EditorTextReplacementPolicy.shouldClearEditorAfterDeliveryReceipt(pasteStatus) {
            let rebuildsEditorWhenEmptying = !pendingSendPreservesActiveInputSession
            pendingSendPreservesActiveInputSession = false
            replaceEditorText(
                "",
                resetsHistory: true,
                rebuildsEditorWhenEmptying: rebuildsEditorWhenEmptying
            )
        } else {
            pendingSendPreservesActiveInputSession = false
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
        let previousGeneration = editorResetGeneration
        shouldRecordTextChange = false
        text = newText
        shouldRecordTextChange = true
        editorResetGeneration = EditorTextReplacementPolicy.nextEditorGeneration(
            currentText: previousText,
            newText: newText,
            currentGeneration: editorResetGeneration,
            rebuildsWhenEmptying: rebuildsEditorWhenEmptying
        )
        recordEditorTextReplacementDiagnostic(
            source: "replaceEditorText",
            previousTextLength: previousText.count,
            newTextLength: newText.count,
            previousGeneration: previousGeneration,
            newGeneration: editorResetGeneration,
            rebuildsEditorWhenEmptying: rebuildsEditorWhenEmptying
        )

        if resetsHistory {
            textHistory.reset()
        }
    }

    private func replaceEditorTextAfterUndoRedo(
        _ newText: String,
        rebuildsEditorWhenEmptying: Bool = true
    ) {
        let previousText = text
        let previousGeneration = editorResetGeneration
        shouldRecordTextChange = false
        text = newText
        shouldRecordTextChange = true
        editorResetGeneration = EditorTextReplacementPolicy.nextEditorGenerationAfterUndoRedo(
            currentText: previousText,
            newText: newText,
            currentGeneration: editorResetGeneration,
            rebuildsWhenEmptying: rebuildsEditorWhenEmptying
        )
        recordEditorTextReplacementDiagnostic(
            source: "replaceEditorTextAfterUndoRedo",
            previousTextLength: previousText.count,
            newTextLength: newText.count,
            previousGeneration: previousGeneration,
            newGeneration: editorResetGeneration,
            rebuildsEditorWhenEmptying: rebuildsEditorWhenEmptying
        )
    }

    private func recordEditorTextReplacementDiagnostic(
        source: String,
        previousTextLength: Int,
        newTextLength: Int,
        previousGeneration: Int,
        newGeneration: Int,
        rebuildsEditorWhenEmptying: Bool
    ) {
        carrierService.recordDiagnosticMarker(
            "editor.modelTextReplaced",
            message: [
                "source=\(source)",
                "previousLength=\(previousTextLength)",
                "newLength=\(newTextLength)",
                "previousGeneration=\(previousGeneration)",
                "newGeneration=\(newGeneration)",
                "rebuildsEditorWhenEmptying=\(rebuildsEditorWhenEmptying)",
                "hasEditorText=\(hasEditorText)",
                "canSend=\(canSend)",
                "canSaveDraft=\(canSaveDraft)",
                "sendState=\(sendState.diagnosticName)"
            ].joined(separator: " ")
        )
    }
}
