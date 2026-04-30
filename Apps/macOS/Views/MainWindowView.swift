import AppKit
import SwiftUI
import TypeCarrierCore

struct MainWindowView: View {
    @ObservedObject var store: MacCarrierStore
    @State private var selectedRecordID: UUID?

    var body: some View {
        NavigationSplitView {
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
            .navigationTitle("TypeCarrier")
            .toolbar {
                Button {
                    store.restart()
                } label: {
                    Label("Restart Receiver", systemImage: "arrow.clockwise")
                }
            }
        } detail: {
            if let selectedRecord {
                ReceivedRecordDetail(record: selectedRecord, store: store)
                    .id(selectedRecord.id)
            } else {
                ContentUnavailableView("Select received text", systemImage: "text.page")
            }
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
                detailRow("Paste", store.lastPasteResult.status)
                detailRow("Connection", store.connectionState.displayText)
                detailRow("Accessibility", store.accessibilityTrusted ? "Enabled" : "Required")
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

            DiagnosticsSummary(store: store)
        }
        .padding(24)
        .navigationTitle("Received Text")
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

private struct DiagnosticsSummary: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        DisclosureGroup("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                diagnosticLine("Local Peer", store.carrierService.diagnostics.localPeerName)
                diagnosticLine("Service", store.carrierService.diagnostics.serviceType)
                diagnosticLine("Connected", store.carrierService.diagnostics.connectedPeersText)
                diagnosticLine("Discovered", store.carrierService.diagnostics.discoveredPeersText)
                if let logURL = store.connectionDiagnosticLogFileURL {
                    diagnosticLine("Log", logURL.path)
                }

                ForEach(Array(store.carrierService.diagnostics.events.suffix(5).reversed())) { event in
                    Text("\(event.timestamp.formatted(date: .omitted, time: .standard)) \(event.name): \(event.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
    }

    private func diagnosticLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
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
