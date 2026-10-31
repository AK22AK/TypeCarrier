import AppKit
import SwiftUI
import TypeCarrierCore

struct SettingsReceivingPage: View {
    @ObservedObject var store: MacCarrierStore

    @State private var nameEditor = DeviceNameEditState()
    @State private var showsNameGuidance = false
    private let nameGuidance = "建议中文 10 字、英文 18 字符；过长会省略显示。"

    var body: some View {
        MacManagementForm {
            Section("设备") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("本机名称")
                        Button {
                            showsNameGuidance.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .help(nameGuidance)
                        .accessibilityLabel("名称长度建议")
                        .accessibilityIdentifier("receiverNameHelp")
                        .popover(isPresented: $showsNameGuidance) {
                            Text(nameGuidance)
                                .frame(width: 300, alignment: .leading)
                                .padding(16)
                        }
                    }
                    if nameEditor.isEditing {
                        TextField("例如：书房 Mac", text: $nameEditor.draft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("本机显示名称")
                            .accessibilityIdentifier("receiverNameDraft")
                        HStack {
                            Button("取消") { nameEditor.cancel() }
                            Button("保存") {
                                if let name = nameEditor.savedName() { store.setCustomReceiverDisplayName(name) }
                            }
                            .disabled(!nameEditor.canSave)
                            Button("使用系统名称") {
                                nameEditor.selectSystemName(store.systemReceiverDisplayName)
                            }
                            .disabled(store.customReceiverDisplayName.isEmpty || nameEditor.pendingSource == .system)
                        }
                    } else {
                        HStack(alignment: .top) {
                            Text(store.receiverDisplayName)
                                .font(.system(size: 15, weight: .semibold))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                                .accessibilityIdentifier("receiverEffectiveName")
                            Spacer(minLength: 8)
                            Button("编辑") {
                                nameEditor.begin(effectiveName: store.receiverDisplayName, hasCustomName: !store.customReceiverDisplayName.isEmpty)
                            }
                            .fixedSize()
                        }
                        Text(store.customReceiverDisplayName.isEmpty ? "系统名称" : "自定义名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            Section {
                Toggle("恢复原剪贴板", isOn: Binding(
                    get: { store.restoresClipboardAfterAutomaticPaste },
                    set: { store.setRestoresClipboardAfterAutomaticPaste($0) }
                ))
            } header: { Text("自动粘贴") } footer: {
                Text("开启后，自动粘贴会尝试恢复原剪贴板内容。")
            }
        }
        .onDisappear { nameEditor.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window.identifier?.rawValue == MacAppCoordinator.mainWindowID {
                nameEditor.cancel()
            }
        }
    }
}

struct SettingsDiagnosticsPage: View {
    @ObservedObject var store: MacCarrierStore
    let showFunctionTest: () -> Void
    @State private var showsRecentEvents = false
    @State private var showsRecovery = false

    private var presentation: ReceiverManagementPresentation {
        .init(summary: store.receiverStatusSummary, accessibilityTrusted: store.accessibilityTrusted)
    }

    var body: some View {
        MacManagementPageContent {
            MacManagementHeader(title: diagnosticTitle,
                                detail: "出现连接或粘贴问题时，可以在这里检查。",
                                symbol: "stethoscope", tint: presentation.needsAttention ? .orange : .green)
                .padding(.bottom, 4)
            MacManagementGroup {
                ForEach(Array(selfCheckFindings.enumerated()), id: \.element.id) { index, finding in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    SettingsSelfCheckFindingRow(finding: finding).padding(16)
                }
                if !store.accessibilityTrusted {
                    Divider().padding(.horizontal, 16)
                    MacManagementActionRow(title: "授权辅助功能", symbol: "lock.open") { store.requestAccessibilityAccess() }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("检查与反馈").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                MacManagementGroup {
                    MacManagementActionRow(title: "功能测试", symbol: "checkmark.seal", action: showFunctionTest)
                    Divider().padding(.horizontal, 16)
                    MacManagementActionRow(title: "导出诊断", symbol: "square.and.arrow.up") { store.exportConnectionDiagnosticsToFinder() }
                }
                if let error = store.lastDiagnosticExportErrorMessage { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                else if let url = store.lastDiagnosticExportURL {
                    Text("最近导出：\(url.path)").font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            DisclosureGroup(isExpanded: $showsRecentEvents) {
                MacManagementGroup {
                    if recentEvents.isEmpty { Text("暂无事件").foregroundStyle(.secondary).padding(16) }
                    else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(recentEvents) { event in DiagnosticEventListRow(event: event) }
                        }.padding(16)
                    }
                }.padding(.top, 10)
            } label: { Text("最近事件").foregroundStyle(.secondary) }
            DisclosureGroup(isExpanded: $showsRecovery) {
                MacManagementGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("重启接收器") { store.restartFromUserAction() }
                        Text("会中断当前连接，手机可能需要重新连接。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        AccessibilityRecoveryActions(store: store)
                    }.padding(16)
                }.padding(.top, 10)
            } label: { Text("高级恢复操作").foregroundStyle(.secondary) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("运行自检", systemImage: "stethoscope") { store.runManualDiagnostics() }
            }
        }
    }

    private var diagnosticTitle: String {
        if !presentation.canReceive { return "接收服务需要处理" }
        if presentation.summary.overallHealth != .ok { return "部分入口异常" }
        return store.accessibilityTrusted ? "接收器运行正常" : "自动粘贴需要授权"
    }

    private var selfCheckFindings: [SelfCheckFinding] {
        ConnectionSelfCheck.findings(
            receiverSummary: store.receiverStatusSummary,
            accessibilityTrusted: store.accessibilityTrusted
        )
        // A stopped endpoint with no reported error is not a ready receiver.
        // The service summary above provides its next step; retain other findings.
        .filter { store.receiverStatusSummary.hasUsableEndpoint || $0.id != "receiver.waiting" }
    }

    private var recentEvents: [SettingsDiagnosticEvent] {
        store.recentConnectionDiagnosticLogEntries(limit: 50).enumerated().map { offset, entry in
            SettingsDiagnosticEvent(
                id: offset,
                timestamp: entry.timestamp,
                name: entry.name,
                message: entry.message,
                summary: entry.compactDiagnosticSummary
            )
        }
    }


}

private struct SettingsSelfCheckFindingRow: View {
    let finding: SelfCheckFinding
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.systemImageName).font(.system(size: 16)).foregroundStyle(finding.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title.localizedDiagnosticMessageText).font(.system(size: 13, weight: .medium))
                Text(finding.detail.localizedDiagnosticMessageText).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = finding.actionTitle {
                    Text(actionTitle.localizedDiagnosticMessageText).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AccessibilityRecoveryActions: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    store.openAccessibilitySettings()
                } label: {
                    Label("打开辅助功能设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                Button {
                    store.resetAccessibilityAuthorization()
                } label: {
                    Label("重置辅助功能授权", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    store.revealCurrentApplicationInFinder()
                } label: {
                    Label("显示当前 App", systemImage: "app.dashed")
                }
                .buttonStyle(.bordered)
            }

            Text("授权后返回 TypeCarrier 会自动刷新；也可以点顶部“运行自检”立即检查。重置会把 TypeCarrier 从辅助功能列表中移除；如果列表里找不到它，点击“显示当前 App”，再用系统设置左下角 + 添加该 app。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = store.lastAccessibilityResetMessage {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SettingsDiagnosticEvent: Identifiable {
    let id: Int
    let timestamp: Date
    let name: String
    let message: String
    let summary: String
}

private struct DiagnosticEventListRow: View {
    let event: SettingsDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.name)
                .font(.caption.weight(.semibold))

            Text(event.summary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Text("\(event.timestamp.formatted(date: .omitted, time: .standard)) \(event.message)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private extension SelfCheckFinding {
    var requiresAttention: Bool {
        severity == .warning || severity == .blocking
    }

    var systemImageName: String {
        switch severity {
        case .ok:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .blocking:
            "xmark.octagon.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch severity {
        case .ok:
            .green
        case .warning:
            .orange
        case .blocking:
            .red
        case .unknown:
            .secondary
        }
    }
}
