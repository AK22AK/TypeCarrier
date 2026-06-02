import AppKit
import SwiftUI
import TypeCarrierCore

struct MainWindowView: View {
    @ObservedObject var store: MacCarrierStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSection: MainWindowSection? = .received
    @State private var selectedRecordID: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebar(
                selectedSection: $selectedSection,
                receivedCount: store.receivedHistory.count,
                connectionState: store.receiverDisplayConnectionState,
                hasConnectionWarning: store.receiverHealthWarning != nil
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .onAppear {
            store.refreshAccessibilityStatus()
            ensureSelectedRecord()
        }
        .onChange(of: store.records) { _, _ in
            ensureSelectedRecord()
        }
        .onChange(of: selectedSection) { _, newValue in
            if newValue == .received {
                ensureSelectedRecord()
            }
        }
        .frame(
            minWidth: 860,
            idealWidth: 980,
            maxWidth: 1_160,
            minHeight: 600,
            idealHeight: 700
        )
        .toolbar(removing: .sidebarToggle)
    }

    private var selectedRecord: CarrierRecord? {
        store.receivedHistory.first { $0.id == selectedRecordID }
    }

    private var activeSection: MainWindowSection {
        selectedSection ?? .received
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch activeSection {
        case .received:
            ReceivedRecordsListPane(
                records: store.receivedHistory,
                selectedRecordID: $selectedRecordID,
                store: store
            )
            .navigationTitle("已接收文本")
            .navigationSubtitle("\(store.receivedHistory.count) 个文本")
            .navigationSplitViewColumnWidth(min: 270, ideal: 320, max: 380)
        case .connectionStatus:
            ContentUnavailableView("连接状态", systemImage: "antenna.radiowaves.left.and.right")
                .navigationTitle("连接状态")
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 340)
        case .settings:
            ContentUnavailableView("设置", systemImage: "gearshape")
                .navigationTitle("设置")
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 340)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch activeSection {
        case .received:
            if let selectedRecord {
                ReceivedRecordDetail(record: selectedRecord, store: store)
                    .id(selectedRecord.id)
            } else {
                ContentUnavailableView("选择一条接收记录", systemImage: "text.page")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .connectionStatus:
            ReceiverStatusPage(store: store)
        case .settings:
            SettingsPlaceholderPage()
        }
    }

    private func ensureSelectedRecord() {
        guard !store.receivedHistory.isEmpty else {
            selectedRecordID = nil
            return
        }

        if selectedRecordID == nil || selectedRecord == nil {
            selectedRecordID = store.receivedHistory.first?.id
        }
    }
}

private enum MainWindowSection: String, Hashable, Identifiable {
    case received
    case connectionStatus
    case settings

    var id: Self {
        self
    }
}

private struct AppSidebar: View {
    @Binding var selectedSection: MainWindowSection?
    let receivedCount: Int
    let connectionState: ConnectionState
    let hasConnectionWarning: Bool

    var body: some View {
        List(selection: $selectedSection) {
            Label("接收列表", systemImage: "tray.and.arrow.down")
                .badge(receivedCount)
                .tag(MainWindowSection.received)

            HStack(spacing: 8) {
                Label("连接状态", systemImage: "antenna.radiowaves.left.and.right")

                Spacer(minLength: 8)

                Image(systemName: connectionStatusImage)
                    .imageScale(.small)
                    .foregroundStyle(connectionStatusTint)
                    .accessibilityLabel(connectionState.localizedDisplayText)
            }
            .help(connectionState.localizedDisplayText)
                .tag(MainWindowSection.connectionStatus)

            Label("设置", systemImage: "gearshape")
                .tag(MainWindowSection.settings)
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        .safeAreaInset(edge: .top, spacing: 10) {
            Text("TypeCarrier")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
        }
    }

    private var connectionStatusImage: String {
        if hasConnectionWarning {
            return "exclamationmark.triangle.fill"
        }

        switch connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting, .reconnecting, .searching, .advertising:
            return "dot.radiowaves.left.and.right"
        case .idle:
            return "circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var connectionStatusTint: Color {
        if hasConnectionWarning {
            return .orange
        }

        switch connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting, .searching, .advertising:
            return .orange
        case .failed:
            return .orange
        case .idle:
            return .secondary
        }
    }
}

private struct ReceivedRecordsListPane: View {
    let records: [CarrierRecord]
    @Binding var selectedRecordID: UUID?
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        List(selection: $selectedRecordID) {
            if records.isEmpty {
                Text("暂无接收文本")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(groupedRecords) { group in
                    Section {
                        ForEach(group.records) { record in
                            ReceivedRecordRow(record: record)
                                .tag(record.id)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.delete(group.records[index])
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .padding(.bottom, 6)
                    } footer: {
                        if !group.isLast {
                            Spacer(minLength: 0)
                                .frame(height: 18)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var groupedRecords: [ReceivedRecordTimeGroup] {
        ReceivedRecordTimeGroup.group(records)
    }
}

private struct ReceivedRecordTimeGroup: Identifiable {
    let id: String
    let title: String
    let records: [CarrierRecord]
    let isFirst: Bool
    let isLast: Bool

    static func group(_ records: [CarrierRecord], calendar: Calendar = .current, now: Date = Date()) -> [Self] {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let monthStart = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart

        var today: [CarrierRecord] = []
        var pastWeek: [CarrierRecord] = []
        var pastMonth: [CarrierRecord] = []
        var older: [CarrierRecord] = []

        for record in records {
            let timestamp = record.updatedAt
            if calendar.isDate(timestamp, inSameDayAs: now) {
                today.append(record)
            } else if timestamp >= weekStart {
                pastWeek.append(record)
            } else if timestamp >= monthStart {
                pastMonth.append(record)
            } else {
                older.append(record)
            }
        }

        let buckets = [
            ("today", "今天", today),
            ("pastWeek", "过去一周", pastWeek),
            ("pastMonth", "过去一个月", pastMonth),
            ("older", "更早", older)
        ]
        .filter { !$0.2.isEmpty }

        return buckets.enumerated()
        .map { index, bucket in
            Self(
                id: bucket.0,
                title: bucket.1,
                records: bucket.2,
                isFirst: index == 0,
                isLast: index == buckets.count - 1
            )
        }
    }
}

private struct ReceivedRecordRow: View {
    let record: CarrierRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.text)
                .lineLimit(1)

            Text(recordMetadataText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private var recordMetadataText: String {
        let timestamp = CarrierRecordTimestampFormatter.historyListText(for: record.updatedAt)
        guard let sourceDeviceName = record.sourceDeviceName, !sourceDeviceName.isEmpty else {
            return timestamp
        }

        return "\(timestamp) · 来自 \(sourceDeviceName)"
    }
}

private struct ReceivedRecordDetail: View {
    let record: CarrierRecord
    @ObservedObject var store: MacCarrierStore
    @State private var editedText: String
    @State private var isDeleting = false

    init(record: CarrierRecord, store: MacCarrierStore) {
        self.record = record
        self.store = store
        _editedText = State(initialValue: record.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            timestampMetadata

            editableText

            if let detail = PasteFailureGuidance.userFacingRecordDetail(
                status: record.status,
                detail: record.detail
            ) {
                Label(detail, systemImage: "lightbulb")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                recordActionButtons
            }
            .sharedBackgroundVisibility(.visible)
        }
        .toolbar(removing: .title)
        .onDisappear {
            saveEditedText()
        }
    }

    @ViewBuilder
    private var recordActionButtons: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(editedText, forType: .string)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        .labelStyle(.iconOnly)
        .help("复制")

        if !store.accessibilityTrusted {
            Button {
                store.requestAccessibilityAccess()
            } label: {
                Label("请求辅助功能权限", systemImage: "lock.open")
            }
            .labelStyle(.iconOnly)
            .help("请求辅助功能权限")
        }

        Button(role: .destructive) {
            isDeleting = true
            store.delete(record)
        } label: {
            Label("删除", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .help("删除")
    }

    private var timestampMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(receivedMetadataText)

            if hasVisibleModificationTimestamp {
                Text("修改于 \(CarrierRecordTimestampFormatter.historyListText(for: record.updatedAt))")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var hasVisibleModificationTimestamp: Bool {
        abs(record.updatedAt.timeIntervalSince(record.createdAt)) >= 1
    }

    private var receivedMetadataText: String {
        let timestamp = CarrierRecordTimestampFormatter.historyListText(for: record.createdAt)
        guard let sourceDeviceName = record.sourceDeviceName, !sourceDeviceName.isEmpty else {
            return "接收于 \(timestamp)"
        }

        return "接收于 \(timestamp) · 来自 \(sourceDeviceName)"
    }

    private var editableText: some View {
        TextField("", text: $editedText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15.5, weight: .regular))
            .lineSpacing(3)
            .lineLimit(1...24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var hasUnsavedChanges: Bool {
        editedText != record.text
    }

    private func saveEditedText() {
        guard !isDeleting else {
            return
        }

        guard hasUnsavedChanges else {
            return
        }

        store.updateText(for: record, text: editedText)
    }
}

private struct ReceiverStatusPage: View {
    @ObservedObject var store: MacCarrierStore
    @State private var androidPairingCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("连接状态")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    statusLine("状态", store.receiverDisplayConnectionState.localizedDisplayText)
                    statusLine("已连接设备", store.receiverConnectedDeviceNames.localizedPeerListText)
                    statusLine("已发现设备", diagnostics.discoveredPeers.localizedPeerListText)
                    statusLine("已邀请设备", diagnostics.invitedPeers.localizedPeerListText)
                    statusLine("本机设备", diagnostics.localPeerName)
                    statusLine("服务", diagnostics.serviceType)
                    statusLine("Android Bridge", androidBridgeStatusText)
                    statusLine("Android 手动连接", store.androidBridge.manualConnectionHints)
                    statusLine("本机匹配码", store.androidBridge.pairingCode)
                    statusLine("可关联 Android", androidPairingDevicesText)
                    statusLine("辅助功能", accessibilityText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("关联 Android")
                        .font(.headline)
                    HStack(spacing: 10) {
                        TextField("输入 Android 匹配码", text: $androidPairingCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                            .onChange(of: androidPairingCode) { _, newValue in
                                androidPairingCode = String(newValue.filter(\.isNumber).prefix(6))
                            }
                        Button {
                            store.androidBridge.associateAndroidDevice(pairingCode: androidPairingCode)
                        } label: {
                            Label("关联设备", systemImage: "display.and.arrow.down")
                        }
                        .disabled(androidPairingCode.count != 6)
                    }
                    Text("也可以在 Android 上输入本机匹配码来关联这台 Mac。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let message = store.androidBridge.associationStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let warning = store.receiverHealthWarning {
                    Divider()
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let lastError = diagnostics.lastErrorMessage {
                    statusLine("最近错误", lastError)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        store.restartFromUserAction()
                    } label: {
                        Label("重启接收器", systemImage: "arrow.clockwise")
                    }

                    Button {
                        store.exportConnectionDiagnosticsToFinder()
                    } label: {
                        Label("导出诊断", systemImage: "square.and.arrow.up")
                    }

                    if !store.accessibilityTrusted {
                        Button {
                            store.requestAccessibilityAccess()
                        } label: {
                            Label("请求辅助功能权限", systemImage: "lock.open")
                        }
                    }
                }

                if let exportError = store.lastDiagnosticExportErrorMessage {
                    statusLine("导出错误", exportError)
                } else if let exportURL = store.lastDiagnosticExportURL {
                    statusLine("最近导出", exportURL.path)
                }

                if !diagnostics.events.isEmpty {
                    Divider()
                    Text("最近事件")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(diagnostics.events.suffix(5).reversed())) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name)
                                    .font(.caption.weight(.semibold))
                                Text("\(event.timestamp.formatted(date: .omitted, time: .standard)) \(event.message)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .padding(.bottom, 28)
    }

    private var diagnostics: CarrierDiagnostics {
        store.carrierService.diagnostics
    }

    private var accessibilityText: String {
        store.accessibilityTrusted ? "已启用" : "需要授权"
    }

    private var androidBridgeStatusText: String {
        switch store.androidBridge.state {
        case .stopped:
            return "未启动"
        case .listening(let port):
            let prefix = port.map { "监听中：\($0)" } ?? "监听中"
            let devices = store.androidBridge.connectedAndroidDeviceNames
            guard !devices.isEmpty else {
                return prefix
            }
            return "\(prefix)，已连接 \(devices.joined(separator: "、"))"
        case .failed(let message):
            return "失败：\(message)"
        }
    }

    private var androidPairingDevicesText: String {
        let devices = store.androidBridge.discoveredAndroidPairingDevices
        guard !devices.isEmpty else {
            return "无"
        }
        return devices.map(\.name).joined(separator: "、")
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPlaceholderPage: View {
    var body: some View {
        ContentUnavailableView("设置", systemImage: "gearshape", description: Text("设置项稍后添加"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension CarrierRecord.Status {
    var localizedDisplayText: String {
        switch self {
        case .draft:
            "草稿"
        case .queued:
            "排队中"
        case .sent:
            "已发送"
        case .received:
            "已接收"
        case .pastePosted, .pasteUnverified, .pasteFailed:
            "已接收"
        case .failed:
            "失败"
        }
    }

    var systemImage: String {
        switch self {
        case .draft:
            "tray"
        case .queued:
            "clock"
        case .sent:
            "paperplane"
        case .received, .pastePosted, .pasteUnverified, .pasteFailed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .failed:
            .red
        case .received, .pastePosted, .pasteUnverified, .pasteFailed:
            .green
        case .queued:
            .orange
        default:
            .secondary
        }
    }
}
