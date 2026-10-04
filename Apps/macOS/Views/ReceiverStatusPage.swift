import SwiftUI
import TypeCarrierCore

struct ReceiverStatusPage: View {
    @ObservedObject var store: MacCarrierStore
    let showDiagnostics: () -> Void
    @State private var showsConnectionGuide = false
    @State private var showsAdvancedInfo = false

    private var summary: ReceiverStatusSummary { store.receiverStatusSummary }
    private var presentation: ReceiverManagementPresentation {
        .init(summary: summary, accessibilityTrusted: store.accessibilityTrusted)
    }

    var body: some View {
        MacManagementForm {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.title).font(.system(size: 17, weight: .semibold))
                        Text(presentation.detail).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: presentation.canReceive ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle")
                        .font(.system(size: 22))
                        .foregroundStyle(summary.overallHealth != .ok || !presentation.canReceive ? .orange : .green)
                }
            }
            if !store.accessibilityTrusted {
                Section {
                    Label(presentation.canReceive ? "可以接收文本；自动粘贴需要辅助功能授权。" : "自动粘贴需要辅助功能授权。", systemImage: "lock.open")
                        .foregroundStyle(.secondary)
                    Button("处理自动粘贴权限", action: showDiagnostics)
                }
            }
            if !summary.issues.isEmpty {
                Section(presentation.canReceive ? "局部异常" : "需要处理") {
                    ForEach(Array(summary.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.message.localizedDiagnosticMessageText)
                            Text(issue.impact.localizedManagementText).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Button("前往诊断与测试", action: showDiagnostics)
                }
            } else if !presentation.canReceive {
                Section { Button("前往诊断与测试", action: showDiagnostics) }
            }
            if !summary.connectedDevices.isEmpty {
                Section("已连接设备 · \(summary.connectedDevices.count)") {
                    ForEach(Array(summary.connectedDevices.enumerated()), id: \.offset) { _, device in
                        LabeledContent {
                            Text("已连接").font(.system(size: 12)).foregroundStyle(.secondary)
                        } label: {
                            Label(device.name, systemImage: device.platform == .apple ? "iphone" : "apps.iphone")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if presentation.canReceive {
                Section {
                    DisclosureGroup("连接新设备", isExpanded: $showsConnectionGuide) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("iPhone", systemImage: "iphone").fontWeight(.medium)
                            Text("与 Mac 连接同一局域网，打开 TypeCarrier，手机会自动发现并连接。多台 Mac 时，在手机上选择这台 Mac。")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Android", systemImage: "apps.iphone").fontWeight(.medium)
                            Text("在手机上选择这台 Mac，首次连接输入配对码。已信任设备可以重连。")
                                .foregroundStyle(.secondary)
                            LabeledContent("配对码") {
                                Text(store.androidBridge.pairingCode).monospaced().textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("高级信息", isExpanded: $showsAdvancedInfo) {
                    LabeledContent("本机名称", value: store.receiverDisplayName)
                    LabeledContent("服务标识", value: store.carrierService.diagnostics.serviceType)
                    LabeledContent("Apple 接收入口", value: store.carrierService.connectionState.localizedDisplayText)
                    LabeledContent("Android 接收入口", value: androidAvailability)
                    LabeledContent("已发现设备", value: store.carrierService.diagnostics.discoveredPeers.joined(separator: "、"))
                    LabeledContent("连接中设备", value: store.carrierService.diagnostics.invitedPeers.joined(separator: "、"))
                    Text(store.androidBridge.manualConnectionHints).textSelection(.enabled).foregroundStyle(.secondary)
                    if let error = store.carrierService.diagnostics.lastErrorMessage { Text(error).textSelection(.enabled) }
                    if let error = store.androidBridge.lastErrorMessage { Text(error).textSelection(.enabled) }
                    Button("重启接收器") { store.restartFromUserAction() }
                    Text("会中断当前连接，手机可能需要重新连接。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { showsConnectionGuide = summary.connectedDevices.isEmpty }
        .onChange(of: summary.connectedDevices.isEmpty) { _, isEmpty in showsConnectionGuide = isEmpty }
    }

    private var androidAvailability: String {
        switch store.androidBridge.state {
        case .stopped: "未启动"
        case .listening(let port): port.map { "监听中：\($0)" } ?? "监听中"
        case .failed(let message): "失败：\(message)"
        }
    }
}

private extension ReceiverIssueImpact {
    var localizedManagementText: String {
        switch self {
        case .allDevices: "影响所有设备"
        case .endpoint(.appleMultipeer): "影响 iPhone 接收入口"
        case .endpoint(.androidBridge): "影响 Android 接收入口"
        }
    }
}
