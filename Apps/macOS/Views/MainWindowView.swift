import AppKit
import SwiftUI
import TypeCarrierCore

struct MainWindowView: View {
    @ObservedObject var store: MacCarrierStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedRecordID: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            DetailContainer(selectedRecord: selectedRecord, store: store)
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
    }

    private var selectedRecord: CarrierRecord? {
        store.receivedHistory.first { $0.id == selectedRecordID }
    }

    private var sidebar: some View {
        List(selection: $selectedRecordID) {
            Section("Received") {
                if store.receivedHistory.isEmpty {
                    Text("No received text")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                ReceiverStatusMenu(store: store)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if let selectedRecord {
                ReceivedRecordDetail(record: selectedRecord, store: store)
                    .id(selectedRecord.id)
            } else {
                ContentUnavailableView("Select received text", systemImage: "text.page")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                    Text(record.status.displayText)
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
                detailRow("Status", record.status.displayText)
                detailRow("Updated", record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Paste", record.pasteSummaryText)
                if let detail = record.detail {
                    detailRow("Detail", detail)
                }
            }

            HStack {
                Button {
                    store.updateText(for: record, text: editedText)
                } label: {
                    Label("Save Edit", systemImage: "checkmark")
                }

                Button {
                    var editedRecord = record
                    editedRecord.text = editedText
                    store.updateText(for: record, text: editedText)
                    store.paste(record: editedRecord)
                } label: {
                    Label("Paste Again", systemImage: "text.insert")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if !store.accessibilityTrusted {
                    Button {
                        store.requestAccessibilityAccess()
                    } label: {
                        Label("Request Accessibility", systemImage: "lock.open")
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    store.delete(record)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .buttonStyle(.glass)
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Received Text")
                    .font(.title2.weight(.semibold))
                Text(record.updatedAt, style: .date)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(record.status.displayText, systemImage: record.status.systemImage)
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

private struct ReceiverStatusMenu: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        Menu {
            Section("Receiver") {
                Text(store.connectionState.displayText)
                Text(accessibilityText)
            }

            if let warning = store.receiverHealthWarning {
                Section("Warning") {
                    Text(warning)
                }
            }

            Divider()

            Button {
                store.restartFromUserAction()
            } label: {
                Label("Restart Receiver", systemImage: "arrow.clockwise")
            }

            Button {
                store.exportConnectionDiagnosticsToFinder()
            } label: {
                Label("Export Diagnostics", systemImage: "square.and.arrow.up")
            }

            if !store.accessibilityTrusted {
                Button {
                    store.requestAccessibilityAccess()
                } label: {
                    Label("Request Accessibility", systemImage: "lock.open")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusTint)
                Text(statusTitle)
                    .fontWeight(.medium)
                Text(statusDetail)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Current receiver status")
    }

    private var statusTitle: String {
        if store.receiverHealthWarning != nil {
            return "Receiver Issue"
        }

        switch store.connectionState {
        case .connected:
            return "Connected"
        case .advertising:
            return "Receiver Ready"
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return "Reconnecting"
        case .searching:
            return "Searching"
        case .failed:
            return "Receiver Issue"
        case .idle:
            return "Receiver Idle"
        }
    }

    private var statusDetail: String {
        "\(store.connectionState.displayText) · \(accessibilityShortText)"
    }

    private var accessibilityText: String {
        store.accessibilityTrusted ? "Accessibility Enabled" : "Accessibility Required"
    }

    private var accessibilityShortText: String {
        store.accessibilityTrusted ? "AX On" : "AX Required"
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
}

private extension CarrierRecord {
    var pasteSummaryText: String {
        switch status {
        case .pastePosted:
            "Posted"
        case .pasteFailed:
            "Failed"
        case .received:
            "Received"
        default:
            status.displayText
        }
    }
}

private extension CarrierRecord.Status {
    var displayText: String {
        switch self {
        case .draft:
            "Draft"
        case .queued:
            "Queued"
        case .sent:
            "Sent"
        case .received:
            "Received"
        case .pastePosted:
            "Paste Posted"
        case .pasteFailed:
            "Paste Failed"
        case .failed:
            "Failed"
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
