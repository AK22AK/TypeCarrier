import AppKit
import Combine
import Foundation
import TypeCarrierCore

enum MacReceiverPreferenceKeys {
    static let displayName = "MacReceiverDisplayName"
    static let restoresClipboardAfterAutomaticPaste = "MacReceiverRestoresClipboardAfterAutomaticPaste"
}

@MainActor
final class MacCarrierStore: ObservableObject {
    private static let clipboardRestoreDelay: TimeInterval = 1.25

    @Published private(set) var lastPayloadText = ""
    @Published private(set) var lastPasteResult = PasteInjectionResult.idle
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var records: [CarrierRecord] = [] {
        // Views read the incoming subset many times per render; filter once per change.
        didSet { receivedHistory = records.filter { $0.kind == .incoming } }
    }
    private(set) var receivedHistory: [CarrierRecord] = []
    @Published private(set) var lastDiagnosticExportURL: URL?
    @Published private(set) var lastDiagnosticExportErrorMessage: String?
    @Published private(set) var lastAccessibilityResetMessage: String?
    @Published private(set) var restoresClipboardAfterAutomaticPaste: Bool
    @Published private(set) var customReceiverDisplayName: String
    @Published private(set) var receiverDisplayName: String

    @Published private(set) var v2Receiver: CarrierV2Receiver
    let connectionDiagnosticLogFileURL: URL?
    private let userDefaults: UserDefaults
    private let displayNamePreference: DeviceNamePreference
    private let recordStore: CarrierRecordStore?
    private let pasteInjector = PasteInjector()
    private let pasteQueue = CarrierPasteQueue()
    private let permissionChecker = AccessibilityPermissionChecker()
    private let diagnosticLogStore: CarrierDiagnosticLogStore?
    private var v2ReceiverCancellable: AnyCancellable?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let namePreference = DeviceNamePreference(defaults: userDefaults, key: MacReceiverPreferenceKeys.displayName)
        displayNamePreference = namePreference
        customReceiverDisplayName = namePreference.customName
        let initialReceiverDisplayName = CarrierDeviceIdentity.preferredDisplayName(
            customName: namePreference.customName,
            systemName: Host.current().localizedName ?? "",
            fallbackName: "TypeCarrier Mac"
        )
        receiverDisplayName = initialReceiverDisplayName
        restoresClipboardAfterAutomaticPaste = userDefaults.bool(
            forKey: MacReceiverPreferenceKeys.restoresClipboardAfterAutomaticPaste
        )
        connectionDiagnosticLogFileURL = try? CarrierDiagnosticLogStore.defaultFileURL(fileName: "mac-connection-events.jsonl")
        v2Receiver = CarrierV2Receiver(
            displayName: initialReceiverDisplayName,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
        diagnosticLogStore = connectionDiagnosticLogFileURL.flatMap { try? CarrierDiagnosticLogStore(fileURL: $0) }
        do {
            recordStore = try CarrierRecordStore(
                fileURL: try CarrierRecordStore.defaultFileURL(fileName: "mac-records.json")
            )
            records = recordStore?.records ?? []
            // didSet does not run for assignments inside init.
            receivedHistory = records.filter { $0.kind == .incoming }
        } catch {
            recordStore = nil
            records = []
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用：\(error.localizedDescription)", succeeded: false)
        }

        v2ReceiverCancellable = v2Receiver.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        refreshAccessibilityStatus()
        start()
    }

    var connectionState: ConnectionState {
        receiverConnectionState
    }

    /// The paired-device (v2) receiver, in the shape the status summary expects.
    private var receiverConnectionState: ConnectionState {
        if let name = v2Receiver.connectedDeviceNames.first {
            return .connected(name)
        }
        switch v2Receiver.state {
        case .stopped: return .idle
        case .listening: return .advertising
        case .failed(let message): return .failed(message)
        }
    }

    var receiverStatusSummary: ReceiverStatusSummary {
        ReceiverStatusSummary(
            connectionState: receiverConnectionState,
            connectedDevices: v2Receiver.connectedDevices,
            sharedIssue: sharedReceiverIssue
        )
    }

    var receiverDisplayConnectionState: ConnectionState {
        let connectedDeviceCount = receiverStatusSummary.connectedDevices.count
        if connectedDeviceCount > 1 {
            return .connected("\(connectedDeviceCount) 台设备")
        }

        if receiverConnectionState.isConnected {
            return receiverConnectionState
        }

        return receiverConnectionState
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


    func start() {
        startV2Receiver()
    }

    private func startV2Receiver() {
        v2Receiver.start { [weak self] envelope, deviceName, deviceID, reply in
            self?.handle(envelope, from: deviceName, sourceDeviceID: deviceID, sendReceipt: reply)
        }
    }

    var systemReceiverDisplayName: String {
        CarrierDeviceIdentity.preferredDisplayName(customName: nil, systemName: Host.current().localizedName ?? "", fallbackName: "TypeCarrier Mac")
    }

    func setCustomReceiverDisplayName(_ name: String) {
        customReceiverDisplayName = displayNamePreference.save(name)
        let effectiveName = CarrierDeviceIdentity.preferredDisplayName(
            customName: customReceiverDisplayName,
            systemName: Host.current().localizedName ?? "",
            fallbackName: "TypeCarrier Mac"
        )
        guard effectiveName != receiverDisplayName else { return }
        receiverDisplayName = effectiveName
        v2Receiver.updateDisplayName(effectiveName)
        recordDiagnosticMarker("receiver.displayName.updated", message: "Updated the advertised receiver name.")
    }

    func restart() {
        v2Receiver.restart()
        recordDiagnosticMarker("receiver.restart.rebuilt", message: "Restarted the receiver.")
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
        recordDiagnosticMarker(name, message: message)
    }

    private func recordDiagnosticMarker(_ name: String, message: String, peerName: String? = nil) {
        let state = receiverDisplayConnectionState
        let diagnostics = CarrierDiagnostics(
            role: "receiver",
            localPeerName: receiverDisplayName,
            serviceType: CarrierV2Receiver.serviceType,
            connectionState: state,
            connectedPeers: receiverConnectedDeviceNames
        )
        let event = CarrierDiagnosticEvent(
            name: name,
            message: message,
            peerName: peerName,
            connectionState: state,
            connectedPeers: receiverConnectedDeviceNames
        )
        try? diagnosticLogStore?.append(event: event, diagnostics: diagnostics)
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

        recordDiagnosticMarker(
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

    func recentConnectionDiagnosticLogEntries(limit: Int) -> [CarrierDiagnosticLogEntry] {
        guard let connectionDiagnosticLogFileURL else {
            return []
        }

        return (try? CarrierDiagnosticLogStore.recentEntries(
            fileURL: connectionDiagnosticLogFileURL,
            limit: limit
        )) ?? []
    }

    /// Called when the menu opens, the app activates, and before each paste. Assigning a
    /// @Published value re-renders every view watching the store even when it did not change,
    /// so only assign when the answer actually changed.
    func refreshAccessibilityStatus() {
        let trusted = permissionChecker.isTrusted(prompt: false)
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
    }

    func runManualDiagnostics() {
        refreshAccessibilityStatus()
        recordDiagnosticMarker(
            "diagnostic.manualCheck",
            message: "Manual diagnostics completed. accessibilityTrusted=\(accessibilityTrusted)."
        )
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: true)
        permissionChecker.openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        permissionChecker.openAccessibilitySettings()
    }

    func resetAccessibilityAuthorization() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            lastAccessibilityResetMessage = "无法确认当前应用的 Bundle ID，不能重置辅助功能授权。"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lastAccessibilityResetMessage = "重置辅助功能授权失败：\(error.localizedDescription)"
            recordDiagnosticMarker(
                "accessibility.reset.failed",
                message: "Failed to reset Accessibility authorization for \(bundleIdentifier): \(error.localizedDescription)"
            )
            return
        }

        if process.terminationStatus == 0 {
            accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
            lastAccessibilityResetMessage = "已重置 \(bundleIdentifier) 的辅助功能授权。列表里找不到 TypeCarrier 时，用 + 手动添加当前 App。"
            recordDiagnosticMarker(
                "accessibility.reset.succeeded",
                message: "Reset Accessibility authorization for \(bundleIdentifier)."
            )
            permissionChecker.openAccessibilitySettings()
        } else {
            lastAccessibilityResetMessage = "重置辅助功能授权失败：tccutil 退出码 \(process.terminationStatus)。"
            recordDiagnosticMarker(
                "accessibility.reset.failed",
                message: "tccutil reset Accessibility \(bundleIdentifier) exited with \(process.terminationStatus)."
            )
        }
    }

    func revealCurrentApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func setRestoresClipboardAfterAutomaticPaste(_ restoresClipboard: Bool) {
        restoresClipboardAfterAutomaticPaste = restoresClipboard
        userDefaults.set(
            restoresClipboard,
            forKey: MacReceiverPreferenceKeys.restoresClipboardAfterAutomaticPaste
        )
    }

    private func restart(reason: String, message: String) {
        recordDiagnosticMarker(reason, message: message)
        restart()
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
        enqueuePaste(text: "来自 TypeCarrier 的测试文本")
    }

    func paste(record: CarrierRecord) {
        enqueuePaste(text: record.text, recordID: record.id, sourceDeviceName: record.sourceDeviceName)
    }

    func enqueuePaste(
        text: String,
        recordID: UUID? = nil,
        sourceDeviceName: String? = nil,
        postPasteAction: CarrierPostPasteAction? = nil,
        completion: ((PasteInjectionResult) -> Void)? = nil
    ) {
        let restoreDelay = clipboardRestoreDelayIfEnabled
        pasteQueue.enqueue { [weak self] in
            guard let self else { return }
            self.refreshAccessibilityStatus()
            let result = await self.pasteInjector.paste(text: text, restoreDelay: restoreDelay, postPasteAction: postPasteAction)
            self.lastPasteResult = result
            self.recordPasteDiagnostic(result, peerName: sourceDeviceName)
            // A user may edit/delete a queued record. Do not resurrect it or overwrite its edited text.
            if let recordID, var record = self.records.first(where: { $0.id == recordID && $0.text == text }), let recordStore = self.recordStore {
                record.status = Self.recordStatus(for: result.pasteStatus)
                record.updatedAt = result.date
                record.detail = result.status
                do {
                    try recordStore.upsert(record)
                    self.syncRecords()
                } catch {
                    self.recordDiagnosticMarker("record.pasteStatusUpdate.failed", message: error.localizedDescription)
                }
            }
            completion?(result)
        }
    }

    @discardableResult
    func updateText(for record: CarrierRecord, text: String) -> Bool {
        var updated = record
        updated.text = text
        updated.updatedAt = Date()
        updated.detail = "已编辑接收文本"

        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用", succeeded: false)
            return false
        }

        do {
            try recordStore.upsert(updated)
            syncRecords()
            return true
        } catch {
            lastPasteResult = PasteInjectionResult(status: "更新历史记录失败：\(error.localizedDescription)", succeeded: false)
            return false
        }
    }

    @discardableResult
    func delete(_ record: CarrierRecord) -> Bool {
        guard let recordStore else {
            lastPasteResult = PasteInjectionResult(status: "历史记录存储不可用", succeeded: false)
            return false
        }

        do {
            try recordStore.delete(id: record.id)
            syncRecords()
            return true
        } catch {
            lastPasteResult = PasteInjectionResult(status: "删除历史记录失败：\(error.localizedDescription)", succeeded: false)
            return false
        }
    }

    private func handle(
        _ envelope: CarrierEnvelope,
        from peerDisplayName: String,
        sourceDeviceID: String,
        sendReceipt: (CarrierEnvelope) -> Void
    ) {
        guard envelope.kind == .text, let payload = envelope.payload else {
            return
        }

        refreshAccessibilityStatus()
        lastPayloadText = payload.text
        let now = Date()
        let sourceDeviceName = peerDisplayName
        recordDiagnosticMarker(
            "receiver.payload.received",
            message: "Received text payload \(payload.id) from \(sourceDeviceName).",
            peerName: sourceDeviceName
        )
        let record = CarrierRecord(
            payloadID: payload.id,
            kind: .incoming,
            status: .received,
            text: payload.text,
            createdAt: now,
            updatedAt: now,
            detail: "来自 \(sourceDeviceName)",
            sourceDeviceName: sourceDeviceName,
            sourceDeviceID: sourceDeviceID
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

        // Confirm durable receipt to the originating connection before entering the paste queue.
        sendReceipt(.receipt(CarrierDeliveryReceipt(
            payloadID: payload.id,
            pasteStatus: .received,
            detail: "Mac 已接收并保存，等待粘贴"
        )))
        let receivedAt = ContinuousClock.now
        enqueuePaste(text: payload.text, recordID: record.id, sourceDeviceName: sourceDeviceName, postPasteAction: payload.postPasteAction) { [weak self] _ in
            let elapsed = ContinuousClock.now - receivedAt
            self?.recordDiagnosticMarker(
                "receiver.payload.pasteFinished",
                message: "Payload \(payload.id) pasted \(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000) ms after it was saved; sent at \(payload.createdAt.formatted(.iso8601)).",
                peerName: sourceDeviceName
            )
        }
    }

    private func recordPasteDiagnostic(_ result: PasteInjectionResult, peerName: String? = nil) {
        recordDiagnosticMarker(
            result.diagnosticEventName,
            message: result.fullDetail,
            peerName: peerName
        )
    }

    private var clipboardRestoreDelayIfEnabled: TimeInterval? {
        restoresClipboardAfterAutomaticPaste ? Self.clipboardRestoreDelay : nil
    }

    private func syncRecords() {
        records = recordStore?.records ?? []
    }

    private static func recordStatus(for pasteStatus: CarrierDeliveryReceipt.PasteStatus) -> CarrierRecord.Status {
        switch pasteStatus {
        case .received:
            return .received
        case .posted:
            return .pastePosted
        case .unverifiedPosted:
            return .pasteUnverified
        case .failed:
            return .pasteFailed
        }
    }
}

private extension PasteInjectionResult {
    var diagnosticEventName: String {
        succeeded ? "paste.command.posted" : "paste.command.failed"
    }
}
