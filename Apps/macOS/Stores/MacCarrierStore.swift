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
    @Published private(set) var androidBridge: AndroidCarrierBridge
    let connectionDiagnosticLogFileURL: URL?
    private let receiverDisplayName: String
    private let recordStore: CarrierRecordStore?
    private let pasteInjector = PasteInjector()
    private let permissionChecker = AccessibilityPermissionChecker()
    private var carrierServiceCancellable: AnyCancellable?
    private var androidBridgeCancellable: AnyCancellable?

    init() {
        connectionDiagnosticLogFileURL = try? CarrierDiagnosticLogStore.defaultFileURL(fileName: "mac-connection-events.jsonl")
        receiverDisplayName = Host.current().localizedName ?? "TypeCarrier Mac"
        carrierService = Self.makeCarrierService(
            displayName: receiverDisplayName,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
        androidBridge = AndroidCarrierBridge(displayName: receiverDisplayName)
        do {
            recordStore = try CarrierRecordStore(
                fileURL: try CarrierRecordStore.defaultFileURL(fileName: "mac-records.json")
            )
            records = recordStore?.records ?? []
        } catch {
            recordStore = nil
            records = []
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用：\(error.localizedDescription)", succeeded: false)
        }

        bindCarrierService()
        bindAndroidBridge()
        refreshAccessibilityStatus()
        start()
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var receiverStatusSummary: ReceiverStatusSummary {
        ReceiverStatusSummary(
            appleConnectionState: carrierService.connectionState,
            appleConnectedDeviceNames: carrierService.diagnostics.connectedPeers,
            androidConnectionState: androidEndpointConnectionState,
            androidConnectedDeviceNames: androidBridge.connectedAndroidDeviceNames,
            sharedIssue: sharedReceiverIssue
        )
    }

    var receiverDisplayConnectionState: ConnectionState {
        let connectedDeviceCount = receiverStatusSummary.connectedDevices.count
        if connectedDeviceCount > 1 {
            return .connected("\(connectedDeviceCount) 台设备")
        }

        if carrierService.connectionState.isConnected {
            return carrierService.connectionState
        }

        if let androidDeviceName = androidBridge.connectedAndroidDeviceNames.first {
            return .connected(androidDeviceName)
        }

        if carrierService.connectionState.isFailed, androidEndpointConnectionState == .listening {
            return .advertising
        }

        return carrierService.connectionState
    }

    var receiverConnectedDeviceNames: [String] {
        receiverStatusSummary.connectedDevices.map(\.name)
    }

    var receiverHealthWarning: String? {
        if receiverStatusSummary.requiresGlobalAttention {
            return "连接异常，请尝试重启接收器。"
        }

        return nil
    }

    var lastPayloadPreview: String {
        guard !lastPayloadText.isEmpty else {
            return "尚未收到内容"
        }

        return String(lastPayloadText.prefix(160))
    }

    var receivedHistory: [CarrierRecord] {
        records.filter { $0.kind == .incoming }
    }

    func start() {
        carrierService.start { [weak self] envelope, peerID in
            self?.handle(envelope, from: peerID.displayName) { receipt in
                try? self?.carrierService.send(receipt)
            }
        }
        androidBridge.start { [weak self] envelope, deviceName, reply in
            self?.handle(envelope, from: deviceName, sendReceipt: reply)
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
        androidBridge.stop()
        androidBridgeCancellable = nil
        androidBridge = AndroidCarrierBridge(displayName: receiverDisplayName)
        bindCarrierService()
        bindAndroidBridge()
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

    private func bindAndroidBridge() {
        androidBridgeCancellable = androidBridge.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private var androidEndpointConnectionState: ReceiverEndpointConnectionState {
        if let androidDeviceName = androidBridge.connectedAndroidDeviceNames.first {
            return .connected(androidDeviceName)
        }

        switch androidBridge.state {
        case .stopped:
            return .idle
        case .listening:
            return .listening
        case .failed(let message):
            return .failed(message)
        }
    }

    private var sharedReceiverIssue: ReceiverStatusIssue? {
        guard recordStore == nil else {
            return nil
        }

        return ReceiverStatusIssue(
            severity: .actionRequired,
            impact: .allDevices,
            message: "历史记录存储不可用",
            suggestedAction: .restartReceiver
        )
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
        lastPasteResult = pasteInjector.paste(text: "来自 TypeCarrier 的测试文本")
        recordPasteDiagnostic(lastPasteResult)
    }

    func paste(record: CarrierRecord) {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: record.text)
        recordPasteDiagnostic(lastPasteResult)
    }

    func updateText(for record: CarrierRecord, text: String) {
        var updated = record
        updated.text = text
        updated.updatedAt = Date()
        updated.detail = "已编辑接收文本"

        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用", succeeded: false)
            return
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
        } catch {
            lastPasteResult = PasteInjectionResult(status: "更新历史记录失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    func delete(_ record: CarrierRecord) {
        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用", succeeded: false)
            return
        }

        do {
            try recordStore.delete(id: record.id)
            syncRecords()
        } catch {
            lastPasteResult = PasteInjectionResult(status: "删除历史记录失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private func handle(
        _ envelope: CarrierEnvelope,
        from peerDisplayName: String,
        sendReceipt: (CarrierEnvelope) -> Void
    ) {
        guard envelope.kind == .text, let payload = envelope.payload else {
            return
        }

        refreshAccessibilityStatus()
        lastPayloadText = payload.text
        let now = Date()
        let sourceDeviceName = envelope.sender?.displayName ?? peerDisplayName
        let record = CarrierRecord(
            payloadID: payload.id,
            kind: .incoming,
            status: .received,
            text: payload.text,
            createdAt: now,
            updatedAt: now,
            detail: "来自 \(sourceDeviceName)",
            sourceDeviceName: sourceDeviceName
        )

        guard let recordStore else {
            let detail = "历史记录存储不可用"
            lastPasteResult = PasteInjectionResult(status: detail, succeeded: false)
            return
        }

        do {
            try recordStore.upsert(record)
            syncRecords()
        } catch {
            let detail = "保存接收文本失败：\(error.localizedDescription)"
            lastPasteResult = PasteInjectionResult(status: detail, succeeded: false)
            return
        }

        sendReceipt(.receipt(CarrierDeliveryReceipt(
            payloadID: payload.id,
            pasteStatus: .received,
            detail: "Mac 已接收来自 \(sourceDeviceName) 的文本"
        )))
        lastPasteResult = pasteInjector.paste(text: payload.text)
        recordPasteDiagnostic(lastPasteResult)
    }

    private func recordPasteDiagnostic(_ result: PasteInjectionResult) {
        carrierService.recordDiagnosticMarker(
            result.diagnosticEventName,
            message: result.fullDetail
        )
    }

    private func syncRecords() {
        records = recordStore?.records ?? []
    }
}

private extension PasteInjectionResult {
    var diagnosticEventName: String {
        succeeded ? "paste.command.posted" : "paste.command.failed"
    }
}
