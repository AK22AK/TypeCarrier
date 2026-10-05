import AppKit
import SwiftUI
import TypeCarrierCore

struct ReceivedRecordsListPane: View {
    let records: [CarrierRecord]
    @Binding var selectedRecordID: UUID?
    @ObservedObject var store: MacCarrierStore

    @State private var pendingDeletion: [CarrierRecord] = []

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
                            ReceivedRecordRow(record: record, showsSourceIdentity: Set(records.filter { $0.sourceDeviceName == record.sourceDeviceName }.compactMap(\.sourceDeviceID)).count > 1)
                                .tag(record.id)
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
                pendingDeletion.forEach { store.delete($0) }
                pendingDeletion = []
            }
        } message: { Text("删除后无法恢复。") }
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
    @State private var editedText: String
    @State private var savedText: String
    let showsSourceIdentity: Bool
    @State private var isDeleting = false
    @State private var showsDeleteConfirmation = false

    init(record: CarrierRecord, store: MacCarrierStore, showsSourceIdentity: Bool) {
        self.record = record
        self.store = store
        self.showsSourceIdentity = showsSourceIdentity
        _editedText = State(initialValue: record.text)
        _savedText = State(initialValue: record.text)
    }

    var body: some View {
        ScrollView {
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
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                recordActionButtons
            }
            .sharedBackgroundVisibility(.visible)
        }
        .alert("删除接收记录？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                isDeleting = true
                store.delete(record)
            }
        } message: { Text("删除后无法恢复。") }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window.identifier?.rawValue == MacAppCoordinator.mainWindowID { saveEditedText() }
        }
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

        Button(role: .destructive) {
            showsDeleteConfirmation = true
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

    private var editableText: some View {
        TextField("", text: $editedText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var hasUnsavedChanges: Bool {
        editedText != savedText
    }

    private func saveEditedText() {
        guard !isDeleting else {
            return
        }

        guard hasUnsavedChanges else {
            return
        }

        store.updateText(for: record, text: editedText)
        savedText = editedText
    }
}
