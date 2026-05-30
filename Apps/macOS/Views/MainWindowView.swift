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
                connectionStateText: store.connectionState.localizedDisplayText,
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
            minWidth: 980,
            idealWidth: 1_120,
            maxWidth: 1_260,
            minHeight: 600,
            idealHeight: 700
        )
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
    let connectionStateText: String
    let hasConnectionWarning: Bool

    var body: some View {
        List(selection: $selectedSection) {
            Label("接收列表", systemImage: "tray.and.arrow.down")
                .badge(receivedCount)
                .tag(MainWindowSection.received)

            Label("连接状态", systemImage: hasConnectionWarning ? "exclamationmark.triangle" : "antenna.radiowaves.left.and.right")
                .badge(Text(connectionStateText))
                .tag(MainWindowSection.connectionStatus)

            Label("设置", systemImage: "gearshape")
                .tag(MainWindowSection.settings)
        }
        .listStyle(.sidebar)
        .navigationTitle("TypeCarrier")
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
                ForEach(records) { record in
                    ReceivedRecordRow(record: record)
                        .tag(record.id)
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.delete(records[index])
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct ReceivedRecordRow: View {
    let record: CarrierRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.text)
                .lineLimit(1)

            Text(updatedTimestampText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private var updatedTimestampText: String {
        CarrierRecordTimestampFormatter.historyListText(for: record.updatedAt)
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
            editableText

            timestampMetadata

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
        .padding(.top, 28)
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
            pasteEditedText()
        } label: {
            Label("再次粘贴", systemImage: "text.insert")
        }
        .labelStyle(.iconOnly)
        .help("再次粘贴")

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
            Text("接收于 \(CarrierRecordTimestampFormatter.historyListText(for: record.createdAt))")

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

    private func pasteEditedText() {
        if hasUnsavedChanges {
            store.updateText(for: record, text: editedText)
        }

        var editedRecord = record
        editedRecord.text = editedText
        store.paste(record: editedRecord)
    }
}

private struct ReceiverStatusPage: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("连接状态")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    statusLine("状态", store.connectionState.localizedDisplayText)
                    statusLine("已连接设备", diagnostics.connectedPeers.localizedPeerListText)
                    statusLine("已发现设备", diagnostics.discoveredPeers.localizedPeerListText)
                    statusLine("已邀请设备", diagnostics.invitedPeers.localizedPeerListText)
                    statusLine("本机设备", diagnostics.localPeerName)
                    statusLine("服务", diagnostics.serviceType)
                    statusLine("辅助功能", accessibilityText)
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
