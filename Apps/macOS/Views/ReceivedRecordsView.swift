import AppKit
import SwiftUI
import TypeCarrierCore

struct ReceivedRecordsListPane: View {
    let records: [CarrierRecord]
    @Binding var selectedRecordID: UUID?
    @ObservedObject var store: MacCarrierStore
    @ObservedObject var editor: ReceivedRecordEditor
    let selectionRevision: Int
    let onDelete: ([CarrierRecord]) -> Void

    @State private var pendingDeletion: [CarrierRecord] = []

    var body: some View {
        List(selection: Binding<ManagementSelection<UUID>?>(
            get: { selectedRecordID.map { ManagementSelection(value: $0, revision: selectionRevision) } },
            set: { selectedRecordID = $0?.value }
        )) {
            if records.isEmpty {
                Text("暂无接收文本")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(groupedRecords) { group in
                    Section {
                        ForEach(group.records) { record in
                            ReceivedRecordRow(record: record, showsSourceIdentity: Set(records.filter { $0.sourceDeviceName == record.sourceDeviceName }.compactMap(\.sourceDeviceID)).count > 1)
                                .tag(ManagementSelection(value: record.id, revision: selectionRevision))
                        }
                        .onDelete { offsets in
                            pendingDeletion = offsets.map { group.records[$0] }
                        }
                    } header: {
                        Text(group.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.bottom, 2)
                    } footer: {
                        if !group.isLast {
                            Spacer(minLength: 0)
                                .frame(height: 8)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("已接收文本").fontWeight(.medium)
                Spacer()
                Text("\(records.count) 条").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .alert("删除接收记录？", isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })) {
            Button("取消", role: .cancel) { pendingDeletion = [] }
            Button("删除", role: .destructive) {
                onDelete(pendingDeletion)
                pendingDeletion = []
            }
        } message: {
            Text(pendingDeletion.contains(where: { $0.id == editor.recordID }) && editor.hasChanges
                 ? "记录和未保存的修改都会删除，无法恢复。" : "删除后无法恢复。")
        }
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
    let showsSourceIdentity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.text)
                .font(.system(size: 13))
                .lineLimit(2)

            Text(recordMetadataText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var recordMetadataText: String {
        let timestamp = CarrierRecordTimestampFormatter.historyListText(for: record.updatedAt)
        guard let sourceDeviceName = record.sourceDeviceName, !sourceDeviceName.isEmpty else {
            return timestamp
        }

        return "\(timestamp) · 来自 \(sourceDeviceName)\(showsSourceIdentity ? record.sourceDeviceID.map { " · \($0.suffix(8))" } ?? "" : "")"
    }
}

struct ReceivedRecordDetail: View {
    let record: CarrierRecord
    @ObservedObject var store: MacCarrierStore
    let coordinator: MacAppCoordinator
    @ObservedObject private var editor: ReceivedRecordEditor
    let showsSourceIdentity: Bool
    @FocusState private var editorFocused: Bool
    @State private var showsDeleteConfirmation = false

    init(record: CarrierRecord, store: MacCarrierStore, coordinator: MacAppCoordinator, showsSourceIdentity: Bool) {
        self.record = record
        self.store = store
        self.coordinator = coordinator
        self.editor = coordinator.recordEditor
        self.showsSourceIdentity = showsSourceIdentity
    }

    private var isEditing: Bool { editor.recordID == record.id }

    var body: some View {
        Group {
            if isEditing {
                editingContent
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        timestampMetadata
                        Text(verbatim: record.text)
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("receivedRecordBody")
                        if let detail = PasteFailureGuidance.userFacingRecordDetail(status: record.status, detail: record.detail) {
                            Label(detail, systemImage: "lightbulb")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, isEditing ? 14 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Button("取消") { editor.discard() }
                        .help("放弃本次编辑")
                        .accessibilityIdentifier("cancelRecordEdit")
                    Button("保存") { coordinator.saveRecordEdits() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!editor.hasChanges)
                        .accessibilityIdentifier("saveRecordEdit")
                } else {
                    recordActionButtons
                }
            }
            .sharedBackgroundVisibility(.visible)
        }
        .alert("删除接收记录？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { coordinator.deleteConfirmedRecords([record]) }
        } message: { Text("删除后无法恢复。") }
    }

    private var editingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(receivedMetadataText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(receivedMetadataText)
                .accessibilityLabel(receivedMetadataText)
            TextEditor(text: $editor.draft)
                .font(.system(size: 13, weight: .regular))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(editorFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: editorFocused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("编辑接收文本")
                .accessibilityIdentifier("receivedRecordEditor")
                .onAppear { editorFocused = true }
                .onDisappear { editorFocused = false }
            if let error = editor.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recordEditSaveError")
            }
        }
    }

    @ViewBuilder private var recordActionButtons: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.text, forType: .string)
        } label: { Label("复制", systemImage: "doc.on.doc") }
            .labelStyle(.iconOnly)
            .help("复制全文")
        Button { editor.begin(record) } label: { Label("编辑", systemImage: "square.and.pencil") }
            .labelStyle(.iconOnly)
            .help("编辑")
            .accessibilityIdentifier("editReceivedRecord")
        Button(role: .destructive) { showsDeleteConfirmation = true } label: { Label("删除", systemImage: "trash") }
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
        .font(.system(size: 12))
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

        return "接收于 \(timestamp) · 来自 \(sourceDeviceName)\(showsSourceIdentity ? record.sourceDeviceID.map { " · \($0.suffix(8))" } ?? "" : "")"
    }

}
