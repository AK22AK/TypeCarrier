import SwiftUI
import TypeCarrierCore
import UIKit

struct ComposerView: View {
    @StateObject private var store = ComposerStore()
    @FocusState private var isEditorFocused: Bool
    @State private var showsDiagnostics = false
    @State private var showsHistory = false
    @State private var isHeaderCollapsed = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                editor
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, pageTopPadding)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task {
            store.start()
        }
        .sheet(isPresented: $showsDiagnostics) {
            ConnectionDiagnosticsSheet(store: store)
        }
        .sheet(isPresented: $showsHistory) {
            CarrierHistorySheet(store: store)
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            if isFocused {
                collapseHeaderForEditing()
            } else {
                restoreHeaderAfterEditing()
            }
        }
    }

    private var header: some View {
        let progress = headerCollapseProgress
        let headerHeight = interpolated(expanded: expandedHeaderHeight, compact: compactHeaderHeight, progress: progress)

        return GeometryReader { proxy in
            let titleX = interpolated(expanded: headerLogoSize + 12, compact: 0, progress: progress)
            let titleY = interpolated(expanded: expandedHeaderContentY, compact: compactHeaderTitleY, progress: progress)
            let titleWidth = max(
                120,
                proxy.size.width - titleX - (headerActionsGroupWidth + 12) * progress
            )
            let logoY = expandedHeaderContentY
            let actionsY = interpolated(expanded: expandedHeaderActionsY, compact: compactHeaderActionsY, progress: progress)

            ZStack(alignment: .topLeading) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: headerLogoSize, height: headerLogoSize)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .opacity(1 - progress)
                    .scaleEffect(interpolated(expanded: 1, compact: 0.88, progress: progress))
                    .offset(x: 0, y: logoY)

                animatedHeaderTitle(progress: progress)
                    .frame(width: titleWidth, alignment: .topLeading)
                    .offset(x: titleX, y: titleY)

                headerActions
                    .frame(width: headerActionsGroupWidth, height: headerActionsGroupHeight)
                    .offset(x: proxy.size.width - headerActionsGroupWidth, y: actionsY)
            }
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .topLeading)
    }

    private func animatedHeaderTitle(progress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: interpolated(expanded: 2, compact: 1, progress: progress)) {
            Text("TypeCarrier")
                .font(.system(size: interpolated(expanded: 34, compact: 24, progress: progress), weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(height: interpolated(expanded: 40, compact: 29, progress: progress), alignment: .topLeading)

            Text(store.headerStatusText)
                .font(.system(size: interpolated(expanded: 17, compact: 14, progress: progress), weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: interpolated(expanded: 22, compact: 18, progress: progress), alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            Button {
                showsHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: headerActionWidth, height: headerActionHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History and drafts")

            Menu {
                Button {
                    showsDiagnostics = true
                } label: {
                    Label("Connection Diagnostics", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: headerActionWidth, height: headerActionHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var editor: some View {
        ZStack(alignment: .bottom) {
            TextField("Type or dictate here", text: $store.text, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .lineLimit(1...10)
                .submitLabel(.send)
                .focused($isEditorFocused)
                .onSubmit {
                    if store.canSend {
                        store.send()
                    }
                }
                .padding(.bottom, showsEditorAccessoryBar ? editorAccessoryReservedHeight : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showsEditorAccessoryBar {
                editorAccessoryBar
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture {
            focusEditor()
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var editorAccessoryBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if store.canUndo || store.canRedo {
                    editorToolGroup {
                        editorToolButton(
                            systemName: "arrow.uturn.backward",
                            accessibilityLabel: "Undo text edit",
                            isEnabled: store.canUndo
                        ) {
                            store.undoTextChange()
                        }

                        editorToolButton(
                            systemName: "arrow.uturn.forward",
                            accessibilityLabel: "Redo text edit",
                            isEnabled: store.canRedo
                        ) {
                            store.redoTextChange()
                        }
                    }
                }

                editorStandaloneToolButton(
                    systemName: "doc.on.doc",
                    accessibilityLabel: "Copy text",
                    isVisible: store.hasEditorText
                ) {
                    store.copyText()
                }

                Spacer(minLength: 0)

                editorStandaloneToolButton(
                    systemName: "trash",
                    accessibilityLabel: "Clear text",
                    isVisible: store.hasEditorText
                ) {
                    store.clearText()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: editorAccessoryHeight)
    }

    private func editorToolButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            focusEditor()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.42))
                .frame(width: editorToolButtonSize, height: editorToolButtonSize)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func editorStandaloneToolButton(
        systemName: String,
        accessibilityLabel: String,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            focusEditor()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: editorAccessoryHeight, height: editorAccessoryHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isVisible)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel(accessibilityLabel)
    }

    private func editorToolGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: editorAccessoryHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                statusChip

                Button {
                    store.saveDraft()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.canSaveDraft ? Color.primary : Color.secondary.opacity(0.45))
                        .frame(width: footerControlHeight, height: footerControlHeight)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!store.canSaveDraft)
                .accessibilityLabel("Save draft")

                Button {
                    store.send()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 16, height: 16)
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(store.canSend ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(minWidth: 96, minHeight: footerControlHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!store.canSend)
            }
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if store.canRestartConnection {
            Button {
                store.restartConnection()
            } label: {
                statusChipContent(showsRetryIcon: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry connection")
        } else {
            statusChipContent(showsRetryIcon: false)
        }
    }

    private func statusChipContent(showsRetryIcon: Bool) -> some View {
        HStack(spacing: 8) {
            if showsRetryIcon {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            } else {
                ConnectionStatusIndicator(status: store.connectionStatus)
                    .id(store.connectionStatus)
            }

            Text(store.connectionStatusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: footerControlHeight, maxHeight: footerControlHeight, alignment: .leading)
        .glassEffect(.regular, in: .capsule)
    }

    private var footerControlHeight: CGFloat {
        46
    }

    private var showsEditorAccessoryBar: Bool {
        store.canUndo || store.canRedo || store.hasEditorText
    }

    private var pageTopPadding: CGFloat {
        4
    }

    private var expandedHeaderHeight: CGFloat {
        114
    }

    private var compactHeaderHeight: CGFloat {
        46
    }

    private var expandedHeaderContentY: CGFloat {
        56
    }

    private var compactHeaderTitleY: CGFloat {
        2
    }

    private var expandedHeaderActionsY: CGFloat {
        -5
    }

    private var compactHeaderActionsY: CGFloat {
        -3
    }

    private var headerCollapseProgress: CGFloat {
        isHeaderCollapsed ? 1 : 0
    }

    private var headerActionsGroupWidth: CGFloat {
        headerActionWidth * 2 + 2 + 16
    }

    private var headerActionsGroupHeight: CGFloat {
        headerActionHeight + 8
    }

    private func interpolated(expanded: CGFloat, compact: CGFloat, progress: CGFloat) -> CGFloat {
        expanded + (compact - expanded) * progress
    }

    private func focusEditor() {
        guard !isEditorFocused else {
            return
        }

        collapseHeaderForEditing()
        isEditorFocused = true
    }

    private func collapseHeaderForEditing() {
        guard !isHeaderCollapsed else {
            return
        }

        isHeaderCollapsed = true
    }

    private func restoreHeaderAfterEditing() {
        guard isHeaderCollapsed else {
            return
        }

        isHeaderCollapsed = false
    }

    private var headerLogoSize: CGFloat {
        48
    }

    private var headerActionWidth: CGFloat {
        46
    }

    private var headerActionHeight: CGFloat {
        40
    }

    private var editorAccessoryHeight: CGFloat {
        40
    }

    private var editorToolButtonSize: CGFloat {
        34
    }

    private var editorAccessoryReservedHeight: CGFloat {
        48
    }

}

private struct ConnectionStatusIndicator: View {
    let status: ComposerStore.ConnectionStatus
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            switch status {
            case .searching:
                Circle()
                    .stroke(Color.blue.opacity(isBreathing ? 0.18 : 0.45), lineWidth: 1.6)
                    .frame(width: isBreathing ? 16 : 9, height: isBreathing ? 16 : 9)
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 5, height: 5)
            case .connecting:
                Circle()
                    .fill(Color.orange.opacity(isBreathing ? 0.18 : 0.4))
                    .frame(width: isBreathing ? 16 : 10, height: isBreathing ? 16 : 10)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            case .disconnected:
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .animation(statusAnimation, value: isBreathing)
        .onAppear {
            isBreathing = status.isBreathing
        }
    }

    private var statusAnimation: Animation? {
        guard status.isBreathing else {
            return nil
        }

        return .easeInOut(duration: status == .searching ? 1.35 : 0.95)
            .repeatForever(autoreverses: true)
    }
}

private extension ComposerStore.ConnectionStatus {
    var isBreathing: Bool {
        self == .searching || self == .connecting
    }
}

private struct ConnectionDiagnosticsSheet: View {
    @ObservedObject var store: ComposerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    diagnosticRow("Role", store.diagnostics.role)
                    diagnosticRow("Local Peer", store.diagnostics.localPeerName)
                    diagnosticRow("Service", store.diagnostics.serviceType)
                    diagnosticRow("State", store.diagnostics.connectionState.displayText)
                    diagnosticRow("Discovered", store.diagnostics.discoveredPeersText)
                    diagnosticRow("Invited", store.diagnostics.invitedPeersText)
                    diagnosticRow("Connected", store.diagnostics.connectedPeersText)

                    if let error = store.diagnostics.lastErrorMessage {
                        diagnosticRow("Last Error", error)
                    }
                }

                Section("Recent Events") {
                    ForEach(Array(store.diagnostics.events.suffix(20).reversed())) { event in
                        DiagnosticEventRow(event: event)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct DiagnosticEventRow: View {
    let event: CarrierDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(event.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let peerName = event.peerName {
                Text(peerName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct CarrierHistorySheet: View {
    @ObservedObject var store: ComposerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !store.drafts.isEmpty {
                    Section("Drafts") {
                        ForEach(store.drafts) { record in
                            NavigationLink {
                                CarrierRecordDetailView(record: record, store: store)
                            } label: {
                                CarrierRecordRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets, from: store.drafts)
                        }
                    }
                }

                Section("Sent History") {
                    if store.outgoingHistory.isEmpty {
                        ContentUnavailableView("No sent text", systemImage: "paperplane")
                    } else {
                        ForEach(store.outgoingHistory) { record in
                            NavigationLink {
                                CarrierRecordDetailView(record: record, store: store)
                            } label: {
                                CarrierRecordRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets, from: store.outgoingHistory)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet, from records: [CarrierRecord]) {
        for index in offsets {
            store.delete(records[index])
        }
    }
}

private struct CarrierRecordRow: View {
    let record: CarrierRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(record.status.displayText, systemImage: record.status.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.status.tint)

                Spacer()

                Text(record.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(record.text)
                .font(.body)
                .lineLimit(2)

            if let detail = record.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CarrierRecordDetailView: View {
    let record: CarrierRecord
    @ObservedObject var store: ComposerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String

    init(record: CarrierRecord, store: ComposerStore) {
        self.record = record
        self.store = store
        _editedText = State(initialValue: record.text)
    }

    var body: some View {
        Form {
            Section("Text") {
                TextEditor(text: $editedText)
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 220)
            }

            Section("Status") {
                LabeledContent("Type", value: record.kind.displayText)
                LabeledContent("State", value: record.status.displayText)
                LabeledContent("Updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let detail = record.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    store.updateText(for: record, text: editedText)
                    store.loadIntoEditor(recordWithEditedText)
                    dismiss()
                } label: {
                    Label("Edit in Composer", systemImage: "square.and.pencil")
                }

                Button {
                    store.updateText(for: record, text: editedText)
                    store.send(record: recordWithEditedText)
                    dismiss()
                } label: {
                    Label("Send Again", systemImage: "paperplane.fill")
                }
                .disabled(!CarrierPayload.canSend(editedText))

                Button {
                    UIPasteboard.general.string = editedText
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    store.delete(record)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .navigationTitle(record.kind == .draft ? "Draft" : "Sent Text")
    }

    private var recordWithEditedText: CarrierRecord {
        var copy = record
        copy.text = editedText
        copy.updatedAt = Date()
        return copy
    }
}

private extension CarrierRecord.Kind {
    var displayText: String {
        switch self {
        case .draft:
            "Draft"
        case .outgoing:
            "Sent"
        case .incoming:
            "Received"
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

#Preview {
    ComposerView()
}
