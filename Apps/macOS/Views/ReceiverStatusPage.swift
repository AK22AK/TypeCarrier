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
        MacManagementPageContent {
            MacManagementHeader(
                title: presentation.title, detail: presentation.detail,
                symbol: presentation.canReceive ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle",
                tint: summary.overallHealth != .ok || !presentation.canReceive ? .orange : .green
            )
            .padding(.bottom, 4)

            if !store.accessibilityTrusted {
                MacManagementGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(presentation.canReceive ? "可以接收文本；自动粘贴需要辅助功能授权。" : "自动粘贴需要辅助功能授权。", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                        Button("处理自动粘贴权限", action: showDiagnostics)
                    }.padding(16)
                }
            }
            if !summary.issues.isEmpty || !presentation.canReceive {
                MacManagementGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(summary.issues.enumerated()), id: \.offset) { _, issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.message.localizedDiagnosticMessageText)
                                Text(issue.impact.localizedManagementText).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Button("前往诊断与测试", action: showDiagnostics)
                    }.padding(16)
                }
            }
            if !summary.connectedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("已连接设备 · \(summary.connectedDevices.count)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    MacManagementGroup {
                        ForEach(Array(summary.connectedDevices.enumerated()), id: \.offset) { index, device in
                            if index > 0 { Divider().padding(.horizontal, 16) }
                            HStack(spacing: 10) {
                                Image(systemName: device.platform == .apple ? "iphone" : "apps.iphone").font(.system(size: 15))
                                Text(device.name).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Text("已连接").font(.system(size: 12)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 16).padding(.vertical, 14)
                        }
                    }
                }
            }
            if presentation.canReceive {
                DisclosureGroup("连接新设备", isExpanded: $showsConnectionGuide) {
                    MacManagementGroup {
                        connectionGuidance("iPhone", symbol: "iphone", detail: "打开手机上的 TypeCarrier，自动发现这台 Mac。")
                        Divider().padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 12) {
                            connectionGuidanceLabel("Android", symbol: "apps.iphone", detail: "首次连接时，在手机输入配对码。")
                            LabeledContent("配对码") {
                                Text(store.androidBridge.pairingCode)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced)).textSelection(.enabled)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .padding(.top, 10)
                    Text("手机与 Mac 需在同一局域网；有多台 Mac 时，在手机上选择这台。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
            DisclosureGroup(isExpanded: $showsAdvancedInfo) {
                MacManagementGroup {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }.padding(16)
                }.padding(.top, 10)
            } label: { Text("高级信息").foregroundStyle(.secondary) }
        }
        .onAppear { showsConnectionGuide = summary.connectedDevices.isEmpty }
        .onChange(of: summary.connectedDevices.isEmpty) { _, isEmpty in showsConnectionGuide = isEmpty }
    }

    private func connectionGuidance(_ title: String, symbol: String, detail: String) -> some View {
        connectionGuidanceLabel(title, symbol: symbol, detail: detail)
            .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func connectionGuidanceLabel(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
