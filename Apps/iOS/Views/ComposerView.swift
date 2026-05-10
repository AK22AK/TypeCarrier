import SwiftUI
import TypeCarrierCore
import UIKit

struct ComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = ComposerStore()
    @FocusState private var isEditorFocused: Bool
    @State private var showsDiagnostics = false
    @State private var showsHistory = false
    @State private var isHeaderCollapsed = false
    @State private var pendingEditorRefocus = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    header
                    connectionFailureNotice
                    editor
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, pageTopPadding)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationDestination(isPresented: $showsHistory) {
                CarrierHistoryView(store: store)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            store.start()
        }
        .sheet(isPresented: $showsDiagnostics) {
            ConnectionDiagnosticsSheet(store: store)
        }
        .alert(
            "草稿箱已满",
            isPresented: Binding(
                get: { store.draftLimitErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.dismissDraftLimitError()
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                store.dismissDraftLimitError()
            }
        } message: {
            Text(store.draftLimitErrorMessage ?? "")
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            if isFocused {
                collapseHeaderForEditing()
            } else if !pendingEditorRefocus {
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
            let actionsWidth = headerActionsGroupWidth
            let titleWidth = max(
                120,
                proxy.size.width - titleX - (actionsWidth + 12) * progress
            )
            let logoY = expandedHeaderContentY
            let actionsY = expandedHeaderActionsY

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
                    .frame(width: actionsWidth, height: headerActionsGroupHeight)
                    .offset(x: proxy.size.width - actionsWidth, y: actionsY)
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

            HStack(spacing: interpolated(expanded: 7, compact: 5, progress: progress)) {
                ConnectionStatusIndicator(status: store.connectionStatus)
                    .id(store.connectionStatus)

                Text(store.headerStatusText)
                    .font(.system(size: interpolated(expanded: 17, compact: 14, progress: progress), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(height: interpolated(expanded: 22, compact: 18, progress: progress), alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            if store.canRestartConnection {
                Button {
                    store.restartConnection()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: headerActionWidth, height: headerActionHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重试连接")
            }

            Button {
                showsHistory = true
            } label: {
                HeaderHistoryButtonLabel(
                    badgeText: store.draftBadgeText,
                    width: headerActionWidth,
                    height: headerActionHeight
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(historyAccessibilityLabel)

            Menu {
                Button {
                    showsDiagnostics = true
                } label: {
                    Label("连接诊断", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: headerActionWidth, height: headerActionHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private var connectionFailureNotice: some View {
        if let message = store.connectionFailureMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(message.localizedDiagnosticMessageText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if let suggestion = store.connectionRecoverySuggestion {
                        Text(suggestion.localizedDiagnosticMessageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if store.canRestartConnection {
                    Button {
                        store.restartConnection()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重试连接")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(connectionFailureAccessibilityLabel(message: message))
        }
    }

    private func connectionFailureAccessibilityLabel(message: String) -> String {
        if let suggestion = store.connectionRecoverySuggestion {
            return "连接异常：\(message.localizedDiagnosticMessageText) \(suggestion.localizedDiagnosticMessageText)"
        }

        return "连接异常：\(message.localizedDiagnosticMessageText)"
    }

    private var editor: some View {
        ZStack(alignment: .bottom) {
            TextField("输入或语音输入", text: $store.text, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .lineLimit(1...10)
                .submitLabel(.send)
                .focused($isEditorFocused)
                .onSubmit {
                    if store.canSend {
                        performEditorActionPreservingFocus {
                            store.send()
                        }
                    }
                }
                .padding(.bottom, editorAccessoryReservedHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(store.editorResetGeneration)

            editorAccessoryBar
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture {
            focusEditor()
        }
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(editorPanelFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(editorPanelStroke, lineWidth: 1)
        }
        .shadow(color: editorPanelShadow, radius: editorPanelShadowRadius, x: 0, y: editorPanelShadowYOffset)
    }

    private var editorPanelFill: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemGroupedBackground : .systemBackground)
    }

    private var editorPanelStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.clear
    }

    private var editorPanelShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.08)
    }

    private var editorPanelShadowRadius: CGFloat {
        colorScheme == .dark ? 18 : 24
    }

    private var editorPanelShadowYOffset: CGFloat {
        colorScheme == .dark ? 10 : 14
    }

    private var editorAccessoryBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if store.canUndo || store.canRedo {
                    editorToolGroup {
                        editorToolButton(
                            systemName: "arrow.uturn.backward",
                            accessibilityLabel: "撤销文本编辑",
                            isEnabled: store.canUndo
                        ) {
                            store.undoTextChange()
                        }

                        editorToolButton(
                            systemName: "arrow.uturn.forward",
                            accessibilityLabel: "重做文本编辑",
                            isEnabled: store.canRedo
                        ) {
                            store.redoTextChange()
                        }
                    }
                }

                editorStandaloneToolButton(
                    systemName: "doc.on.doc",
                    accessibilityLabel: "复制文本",
                    isEnabled: store.hasEditorText
                ) {
                    store.copyText()
                }

                Spacer(minLength: 0)

                editorStandaloneToolButton(
                    systemName: "trash",
                    accessibilityLabel: "清空文本",
                    isEnabled: store.hasEditorText
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
            performEditorActionPreservingFocus(action)
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
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            performEditorActionPreservingFocus(action)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.42))
                .frame(width: editorAccessoryHeight, height: editorAccessoryHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
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
                Spacer(minLength: 0)

                Button {
                    performEditorActionPreservingFocus {
                        store.saveDraft()
                    }
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.canSaveDraft ? Color.primary : Color.secondary.opacity(0.45))
                        .frame(width: footerControlHeight, height: footerControlHeight)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!store.canSaveDraft)
                .accessibilityLabel("保存草稿")

                Button {
                    performEditorActionPreservingFocus {
                        store.send()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 16, height: 16)
                        Text(store.sendButtonText)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(store.canSend ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(minWidth: 96, minHeight: footerControlHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!store.canSend)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var footerControlHeight: CGFloat {
        46
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

    private var headerCollapseProgress: CGFloat {
        isHeaderCollapsed ? 1 : 0
    }

    private var headerActionsGroupWidth: CGFloat {
        let actionCount: CGFloat = store.canRestartConnection ? 3 : 2
        return headerActionWidth * actionCount + 2 * (actionCount - 1) + 16
    }

    private var headerActionsGroupHeight: CGFloat {
        headerActionHeight + 8
    }

    private var historyAccessibilityLabel: String {
        if store.draftCount > 0 {
            return "历史和草稿，\(store.draftCount) 条草稿"
        }

        return "历史和草稿"
    }

    private func interpolated(expanded: CGFloat, compact: CGFloat, progress: CGFloat) -> CGFloat {
        expanded + (compact - expanded) * progress
    }

    private func focusEditor() {
        collapseHeaderForEditing()
        isEditorFocused = true
    }

    private func performEditorActionPreservingFocus(_ action: () -> Void) {
        let previousGeneration = store.editorResetGeneration
        action()

        if store.editorResetGeneration != previousGeneration {
            restoreEditorFocusAfterRebuild()
        } else {
            focusEditor()
        }
    }

    private func restoreEditorFocusAfterRebuild() {
        pendingEditorRefocus = true
        collapseHeaderForEditing()

        Task { @MainActor in
            await Task.yield()
            isEditorFocused = false
            await Task.yield()
            pendingEditorRefocus = false
            focusEditor()
        }
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

private struct HeaderHistoryButtonLabel: View {
    let badgeText: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 22, weight: .medium))
            .frame(width: width, height: height)
            .overlay(alignment: .topTrailing) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.red, in: .capsule)
                        .accessibilityHidden(true)
                        .padding(.top, 1)
                        .padding(.trailing, 1)
                }
            }
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
            case .idle:
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
    @State private var diagnosticExportShareItem: DiagnosticExportShareItem?
    @State private var diagnosticExportErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("会话") {
                    diagnosticRow("角色", store.diagnostics.role.localizedRoleText)
                    diagnosticRow("本机设备", store.diagnostics.localPeerName)
                    diagnosticRow("服务", store.diagnostics.serviceType)
                    diagnosticRow("状态", store.diagnostics.connectionState.localizedDisplayText)
                    diagnosticRow("已发现设备", store.diagnostics.discoveredPeers.localizedPeerListText)
                    diagnosticRow("已邀请设备", store.diagnostics.invitedPeers.localizedPeerListText)
                    diagnosticRow("已连接设备", store.diagnostics.connectedPeers.localizedPeerListText)

                    if let error = store.diagnostics.lastErrorMessage {
                        diagnosticRow("最近错误", error.localizedDiagnosticMessageText)
                    }

                    if let logURL = store.connectionDiagnosticLogFileURL {
                        diagnosticRow("日志文件", logURL.lastPathComponent)
                    }
                }

                Section("最近事件") {
                    ForEach(Array(store.diagnostics.events.suffix(20).reversed())) { event in
                        DiagnosticEventRow(event: event)
                    }
                }
            }
            .navigationTitle("诊断")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.connectionDiagnosticLogFileURL != nil {
                        Button {
                            exportLog()
                        } label: {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $diagnosticExportShareItem) { shareItem in
            ActivityView(activityItems: [shareItem.url])
        }
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { diagnosticExportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        diagnosticExportErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(diagnosticExportErrorMessage ?? "")
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

    private func exportLog() {
        do {
            let exportURL = try store.makeConnectionDiagnosticExportURL()
            diagnosticExportShareItem = DiagnosticExportShareItem(url: exportURL)
        } catch {
            diagnosticExportErrorMessage = error.localizedDescription
        }
    }
}

private struct DiagnosticExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

            Text(event.message.localizedDiagnosticMessageText)
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

private struct CarrierHistoryView: View {
    private enum HistoryTab {
        case drafts
        case history

        var title: String {
            switch self {
            case .drafts:
                "草稿"
            case .history:
                "历史"
            }
        }
    }

    @ObservedObject var store: ComposerStore
    @State private var selectedTab: HistoryTab
    @State private var showsClearConfirmation = false

    init(store: ComposerStore) {
        self.store = store
        _selectedTab = State(initialValue: store.drafts.isEmpty ? .history : .drafts)
    }

    var body: some View {
        List {
            switch selectedTab {
            case .drafts:
                draftsContent
            case .history:
                historyContent
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(selectedTab.title)
        .navigationSubtitle(currentSubtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                historyActionMenu
            }
        }
        .alert(clearConfirmationTitle, isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearCurrentTab()
            }
        } message: {
            Text(clearConfirmationMessage)
        }
    }

    private var historyScrollableHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            historyTabControl
        }
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .animation(.snappy(duration: 0.18), value: selectedTab)
    }

    private var historyActionMenu: some View {
        Menu {
            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label(clearActionTitle, systemImage: "trash")
            }
            .disabled(!canClearCurrentTab)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("历史操作")
    }

    private var historyTabControl: some View {
        Picker("历史视图", selection: $selectedTab) {
            Text("")
                .tag(HistoryTab.drafts)
            Text("")
                .tag(HistoryTab.history)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .center) {
            HistoryTabLabelOverlay(
                isDraftsSelected: selectedTab == .drafts,
                isHistorySelected: selectedTab == .history
            )
            .allowsHitTesting(false)
        }
        .padding(.horizontal, historyHorizontalPadding)
    }

    @ViewBuilder
    private var draftsContent: some View {
        if store.drafts.isEmpty {
            Section {
                ContentUnavailableView("暂无草稿", systemImage: "tray")
            } header: {
                historyScrollableHeader
            }
            .textCase(nil)
        } else {
            Section {
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
            } header: {
                historyScrollableHeader
            }
            .textCase(nil)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if store.outgoingHistory.isEmpty {
            Section {
                ContentUnavailableView("暂无发送记录", systemImage: "paperplane")
            } header: {
                historyScrollableHeader
            }
            .textCase(nil)
        } else {
            Section {
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
            } header: {
                historyScrollableHeader
            }
            .textCase(nil)
        }
    }

    private var canClearCurrentTab: Bool {
        switch selectedTab {
        case .drafts:
            !store.drafts.isEmpty
        case .history:
            !store.outgoingHistory.isEmpty
        }
    }

    private var currentSubtitle: String {
        switch selectedTab {
        case .drafts:
            return "\(store.draftCount) 条草稿"
        case .history:
            return "\(store.outgoingHistory.count) 条发送记录"
        }
    }

    private var clearActionAccessibilityLabel: String {
        switch selectedTab {
        case .drafts:
            "清空所有草稿"
        case .history:
            "清空发送历史"
        }
    }

    private var clearActionTitle: String {
        switch selectedTab {
        case .drafts:
            "清空草稿"
        case .history:
            "清空历史"
        }
    }

    private var clearConfirmationTitle: String {
        switch selectedTab {
        case .drafts:
            "清空草稿箱？"
        case .history:
            "清空历史记录？"
        }
    }

    private var clearConfirmationMessage: String {
        switch selectedTab {
        case .drafts:
            "这会删除 \(store.draftCount) 条草稿，无法撤销。"
        case .history:
            "这会删除 \(store.outgoingHistory.count) 条历史记录，无法撤销。"
        }
    }

    private func clearCurrentTab() {
        switch selectedTab {
        case .drafts:
            store.deleteAllDrafts()
        case .history:
            store.deleteAllOutgoingHistory()
        }
    }

    private func delete(_ offsets: IndexSet, from records: [CarrierRecord]) {
        for index in offsets {
            store.delete(records[index])
        }
    }

    private var historyHorizontalPadding: CGFloat {
        20
    }
}

private struct HistoryTabLabelOverlay: View {
    let isDraftsSelected: Bool
    let isHistorySelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            SegmentTabLabel(title: "草稿", isSelected: isDraftsSelected)
                .frame(maxWidth: .infinity)

            SegmentTabLabel(title: "历史", isSelected: isHistorySelected)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
    }
}

private struct SegmentTabLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.footnote)
        .foregroundStyle(Color.primary)
    }
}

private struct CarrierRecordRow: View {
    let record: CarrierRecord

    var body: some View {
        rowContent
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private var rowContent: some View {
        switch record.kind {
        case .draft:
            draftContent
        default:
            historyContent
        }
    }

    private var draftContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.text)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(updatedTimestampText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.text)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            historyMetadataRow
        }
    }

    private var historyMetadataRow: some View {
        HStack(spacing: 7) {
            if !record.status.isCompactSuccess {
                Text(record.status.localizedDisplayText)
                    .foregroundStyle(record.status.tint)
            }

            Text(updatedTimestampText)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var updatedTimestampText: String {
        CarrierRecordTimestampFormatter.historyListText(for: record.updatedAt)
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
            Section("文本") {
                TextEditor(text: $editedText)
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 220)
            }

            Section("状态") {
                LabeledContent("类型", value: record.kind.localizedDisplayText)
                LabeledContent("状态", value: record.status.localizedDisplayText)
                LabeledContent("更新时间", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let detail = record.detail {
                    Text(detail.localizedDiagnosticMessageText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    store.updateText(for: record, text: editedText)
                    store.loadIntoEditor(recordWithEditedText)
                    dismiss()
                } label: {
                    Label("载入编辑器", systemImage: "square.and.pencil")
                }

                Button {
                    store.updateText(for: record, text: editedText)
                    store.send(record: recordWithEditedText)
                    dismiss()
                } label: {
                    Label("再次发送", systemImage: "paperplane.fill")
                }
                .disabled(!CarrierPayload.canSend(editedText))

                Button {
                    UIPasteboard.general.string = editedText
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    store.delete(record)
                    dismiss()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .navigationTitle(record.kind == .draft ? "草稿" : "已发送文本")
    }

    private var recordWithEditedText: CarrierRecord {
        var copy = record
        copy.text = editedText
        copy.updatedAt = Date()
        return copy
    }
}

private extension CarrierRecord.Kind {
    var localizedDisplayText: String {
        switch self {
        case .draft:
            "草稿"
        case .outgoing:
            "已发送"
        case .incoming:
            "已接收"
        }
    }
}

private extension CarrierRecord.Status {
    var isCompactSuccess: Bool {
        switch self {
        case .received:
            true
        default:
            false
        }
    }

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
            "paperplane.circle"
        case .pasteFailed, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pasteFailed, .failed:
            .red
        case .received:
            .green
        case .pastePosted:
            .orange
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
