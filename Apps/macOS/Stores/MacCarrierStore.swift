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
    @Published private(set) var records: [CarrierRecord] = []
    @Published private(set) var lastDiagnosticExportURL: URL?
    @Published private(set) var lastDiagnosticExportErrorMessage: String?
    @Published private(set) var lastAccessibilityResetMessage: String?
    @Published private(set) var restoresClipboardAfterAutomaticPaste: Bool
    @Published private(set) var customReceiverDisplayName: String
    @Published private(set) var receiverDisplayName: String

    @Published private(set) var carrierService: MultipeerCarrierService
    @Published private(set) var androidBridge: AndroidCarrierBridge
    let connectionDiagnosticLogFileURL: URL?
    private let userDefaults: UserDefaults
    private let displayNamePreference: DeviceNamePreference
    private let recordStore: CarrierRecordStore?
    private let pasteInjector = PasteInjector()
    private let pasteQueue = CarrierPasteQueue()
    private let permissionChecker = AccessibilityPermissionChecker()
    private var carrierServiceCancellable: AnyCancellable?
    private var androidBridgeCancellable: AnyCancellable?

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
        let bridge = AndroidCarrierBridge(
            displayName: initialReceiverDisplayName,
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
        androidBridge = bridge
        carrierService = Self.makeCarrierService(
            displayName: initialReceiverDisplayName,
            receiverDiscoveryInfoExtras: Self.receiverDiscoveryInfoExtras(androidDiscoveryInfo: bridge.bonjourDiscoveryInfo),
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

    private static var appVariant: String {
#if DEBUG
        "debug"
#else
        "release"
#endif
    }

    private static func receiverDiscoveryInfoExtras(androidDiscoveryInfo: [String: String]) -> [String: String] {
        var info = androidDiscoveryInfo
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            info[CarrierReceiverDiscoveryInfo.appBundleIDKey] = bundleIdentifier
        }
        info[CarrierReceiverDiscoveryInfo.appVariantKey] = appVariant
        return info
    }

    var receiverStatusSummary: ReceiverStatusSummary {
        ReceiverStatusSummary(
            appleConnectionState: carrierService.connectionState,
            appleConnectedDeviceNames: carrierService.connectedPeers.map { "\($0.displayName) · \($0.id.suffix(8))" },
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
        startCarrierService()
        startAndroidBridge()
    }

    private func startCarrierService() {
        carrierService.start { [weak self] envelope, peerID in
            guard let self else { return }
            let source = self.carrierService.peerIdentity(for: peerID)
            self.handle(envelope, from: source.displayName, sourceDeviceID: source.id) { receipt in
                try? self.carrierService.send(receipt, to: source.id)
            }
        }
    }

    private func startAndroidBridge() {
        androidBridge.start { [weak self] envelope, deviceID, deviceName, reply in
            self?.handle(envelope, from: deviceName, sourceDeviceID: "android:\(deviceID)", sendReceipt: reply)
        }
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
        androidBridge.updateDisplayName(effectiveName)
        // Apple peer names are immutable: rebuild only that transport. Android
        // retains its authenticated sockets and publishes the new discovery name.
        rebuildReceiverService(rebuiltReason: "receiver.displayName.updated", restartsAndroidBridge: false)
    }

    func restart() {
        rebuildReceiverService(
            rebuiltReason: "receiver.restart.rebuilt",
            restartsAndroidBridge: true
        )
    }

    private func rebuildReceiverService(rebuiltReason: String, restartsAndroidBridge: Bool) {
        carrierService.stop()
        carrierServiceCancellable = nil
        carrierService = Self.makeCarrierService(
            displayName: receiverDisplayName,
            receiverDiscoveryInfoExtras: Self.receiverDiscoveryInfoExtras(androidDiscoveryInfo: androidBridge.bonjourDiscoveryInfo),
            diagnosticLogFileURL: connectionDiagnosticLogFileURL
        )
        bindCarrierService()
        startCarrierService()

        if restartsAndroidBridge {
            androidBridge.restart { [weak self] envelope, deviceID, deviceName, reply in
                self?.handle(envelope, from: deviceName, sourceDeviceID: "android:\(deviceID)", sendReceipt: reply)
            }
        }

        carrierService.recordDiagnosticMarker(
            rebuiltReason,
            message: restartsAndroidBridge
                ? "Created fresh Apple and Android receiver services after restart."
                : "Created a fresh Apple receiver service after Multipeer session invalidation."
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

    func recentConnectionDiagnosticLogEntries(limit: Int) -> [CarrierDiagnosticLogEntry] {
        guard let connectionDiagnosticLogFileURL else {
            return []
        }

        return (try? CarrierDiagnosticLogStore.recentEntries(
            fileURL: connectionDiagnosticLogFileURL,
            limit: limit
        )) ?? []
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
    }

    func runManualDiagnostics() {
        refreshAccessibilityStatus()
        carrierService.recordDiagnosticMarker(
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
            carrierService.recordDiagnosticMarker(
                "accessibility.reset.failed",
                message: "Failed to reset Accessibility authorization for \(bundleIdentifier): \(error.localizedDescription)"
            )
            return
        }

        if process.terminationStatus == 0 {
            accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
            lastAccessibilityResetMessage = "已重置 \(bundleIdentifier) 的辅助功能授权。列表里找不到 TypeCarrier 时，用 + 手动添加当前 App。"
            carrierService.recordDiagnosticMarker(
                "accessibility.reset.succeeded",
                message: "Reset Accessibility authorization for \(bundleIdentifier)."
            )
            permissionChecker.openAccessibilitySettings()
        } else {
            lastAccessibilityResetMessage = "重置辅助功能授权失败：tccutil 退出码 \(process.terminationStatus)。"
            carrierService.recordDiagnosticMarker(
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
        carrierService.recordDiagnosticMarker(reason, message: message)
        restart()
    }

    private func restartAfterReceiverSessionInvalidated(peerName: String, previousState: ConnectionState) {
        carrierService.recordDiagnosticMarker(
            "receiver.restart.sessionInvalidated",
            message: "Automatically rebuilding receiver after \(peerName) changed from \(previousState.displayText) to not connected."
        )
        rebuildReceiverService(
            rebuiltReason: "receiver.restart.appleSessionRebuilt",
            restartsAndroidBridge: false
        )
    }

    private static func makeCarrierService(
        displayName: String,
        receiverDiscoveryInfoExtras: [String: String],
        diagnosticLogFileURL: URL?
    ) -> MultipeerCarrierService {
        MultipeerCarrierService(
            role: .receiver,
            displayName: displayName,
            receiverDiscoveryInfoExtras: receiverDiscoveryInfoExtras,
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
                    self.carrierService.recordDiagnosticMarker("record.pasteStatusUpdate.failed", message: error.localizedDescription)
                }
            }
            completion?(result)
        }
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
        carrierService.recordDiagnosticMarker(
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
        enqueuePaste(text: payload.text, recordID: record.id, sourceDeviceName: sourceDeviceName, postPasteAction: payload.postPasteAction)
    }

    private func recordPasteDiagnostic(_ result: PasteInjectionResult, peerName: String? = nil) {
        carrierService.recordDiagnosticMarker(
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
