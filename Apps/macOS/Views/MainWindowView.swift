import AppKit
import SwiftUI
import TypeCarrierCore

struct MainWindowView: View {
    @ObservedObject var store: MacCarrierStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isStatusInspectorPresented = false
    @State private var selectedRecordID: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            DetailContainer(
                selectedRecord: selectedRecord,
                store: store,
                isStatusInspectorPresented: $isStatusInspectorPresented
            )
        }
        .inspector(isPresented: $isStatusInspectorPresented) {
            ReceiverStatusInspector(store: store)
                .inspectorColumnWidth(min: 220, ideal: 240, max: 260)
        }
        .onAppear {
            store.refreshAccessibilityStatus()
            selectedRecordID = selectedRecordID ?? store.receivedHistory.first?.id
        }
        .onChange(of: store.records) { _, _ in
            if selectedRecordID == nil || selectedRecord == nil {
                selectedRecordID = store.receivedHistory.first?.id
            }
        }
        .frame(
            minWidth: 900,
            idealWidth: 980,
            maxWidth: 1_040,
            minHeight: 560,
            idealHeight: 620
        )
    }

    private var selectedRecord: CarrierRecord? {
        store.receivedHistory.first { $0.id == selectedRecordID }
    }

    private var sidebar: some View {
        List(selection: $selectedRecordID) {
            Section("已接收") {
                if store.receivedHistory.isEmpty {
                    Text("暂无接收文本")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.receivedHistory) { record in
                        ReceivedRecordRow(record: record)
                            .tag(record.id)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.delete(store.receivedHistory[index])
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DetailContainer: View {
    let selectedRecord: CarrierRecord?
    @ObservedObject var store: MacCarrierStore
    @Binding var isStatusInspectorPresented: Bool

    var body: some View {
        Group {
            if let selectedRecord {
                ReceivedRecordDetail(record: selectedRecord, store: store)
                    .id(selectedRecord.id)
            } else {
                ContentUnavailableView("选择一条接收记录", systemImage: "text.page")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ReceiverStatusToolbarButton(
                    store: store,
                    isPresented: $isStatusInspectorPresented
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

private struct ReceivedRecordRow: View {
    let record: CarrierRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.status.systemImage)
                .foregroundStyle(record.status.tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(record.status.localizedDisplayText)
                    Text(record.updatedAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ReceivedRecordDetail: View {
    let record: CarrierRecord
    @ObservedObject var store: MacCarrierStore
    @State private var editedText: String

    init(record: CarrierRecord, store: MacCarrierStore) {
        self.record = record
        self.store = store
        _editedText = State(initialValue: record.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            TextEditor(text: $editedText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .textEditorStyle(.plain)
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow("状态", record.status.localizedDisplayText)
                detailRow("更新时间", record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("粘贴", record.pasteSummaryText)
                if let detail = record.detail {
                    detailRow("详情", detail.localizedPasteDetailText)
                }
            }

            HStack {
                Button {
                    store.updateText(for: record, text: editedText)
                } label: {
                    Label("保存修改", systemImage: "checkmark")
                }

                Button {
                    var editedRecord = record
                    editedRecord.text = editedText
                    store.updateText(for: record, text: editedText)
                    store.paste(record: editedRecord)
                } label: {
                    Label("再次粘贴", systemImage: "text.insert")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editedText, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                if !store.accessibilityTrusted {
                    Button {
                        store.requestAccessibilityAccess()
                    } label: {
                        Label("请求辅助功能权限", systemImage: "lock.open")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    store.delete(record)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .buttonStyle(.glass)
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已接收文本")
                    .font(.title2.weight(.semibold))
                Text(record.updatedAt, style: .date)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(record.status.localizedDisplayText, systemImage: record.status.systemImage)
                .foregroundStyle(record.status.tint)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private struct ReceiverStatusToolbarButton: View {
    @ObservedObject var store: MacCarrierStore
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label {
                Text(statusLabelText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusTextTint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusTint)
                    .imageScale(.medium)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 180)
            .contentShape(.capsule)
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.regular)
        .help(statusTitle)
        .accessibilityLabel(statusTitle)
    }

    private var statusTitle: String {
        if store.receiverHealthWarning != nil {
            return "接收器异常"
        }

        switch store.connectionState {
        case .connected(let peerName):
            return "已连接到 \(peerName)"
        default:
            return "接收器空闲"
        }
    }

    private var statusLabelText: String {
        if store.receiverHealthWarning != nil {
            return "连接异常"
        }

        switch store.connectionState {
        case .connected(let peerName):
            return peerName
        default:
            return "空闲"
        }
    }

    private var statusSystemImage: String {
        if store.receiverHealthWarning != nil {
            return "exclamationmark.triangle.fill"
        }

        return store.connectionState.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
    }

    private var statusTint: Color {
        if store.receiverHealthWarning != nil {
            return .orange
        }

        return store.connectionState.isConnected ? .green : .secondary
    }

    private var statusTextTint: Color {
        if store.receiverHealthWarning != nil {
            return .orange
        }

        return store.connectionState.isConnected ? .primary : .secondary
    }
}

private struct ReceiverStatusInspector: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("连接状态")
                    .font(.title3.weight(.semibold))

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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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

private extension CarrierRecord {
    var pasteSummaryText: String {
        switch status {
        case .pastePosted:
            "粘贴已提交"
        case .pasteFailed:
            "粘贴失败"
        case .received:
            "已接收"
        default:
            status.localizedDisplayText
        }
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
        case .pastePosted:
            "粘贴已提交"
        case .pasteFailed:
            "粘贴失败"
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
        case .received:
            "checkmark.circle"
        case .pastePosted:
            "checkmark.circle.fill"
        case .pasteFailed, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pasteFailed, .failed:
            .red
        case .pastePosted, .received:
            .green
        case .queued:
            .orange
        default:
            .secondary
        }
    }
}
