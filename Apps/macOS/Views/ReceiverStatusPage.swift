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
        MacConnectionPageContent {
            MacManagementGroup {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("接收器").font(.system(size: 13, weight: .medium))
                        HStack(spacing: 5) {
                            Circle().fill(presentation.canReceive ? (summary.overallHealth == .degraded ? Color.orange : Color.green) : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(presentation.title).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    if presentation.needsAttention {
                        Button("处理问题", action: showDiagnostics).controlSize(.small)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(minHeight: 60, alignment: .leading)
            }

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
            CarrierV2PairingSection(receiver: store.v2Receiver)
            if presentation.canReceive {
                VStack(alignment: .leading, spacing: 8) {
                    MacManagementGroup {
                        DisclosureGroup("连接新设备", isExpanded: $showsConnectionGuide) {
                            VStack(alignment: .leading, spacing: 0) {
                                guidanceRow("iPhone", symbol: "iphone", detail: "首次连接时，点上方“开始配对”，在手机上选择这台 Mac 并核对数字。")
                                Divider()
                                guidanceRow("Android", symbol: "apps.iphone", detail: "首次连接时，点上方“开始配对”，在手机上选择这台 Mac 并核对数字。")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                        .font(.system(size: 13)).padding(12)
                    }
                    if showsConnectionGuide {
                        Text("手机与 Mac 使用同一局域网。多台 Mac 时，在手机上选择目标。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                    }
                }
            }
            MacManagementGroup {
                DisclosureGroup(isExpanded: $showsAdvancedInfo) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("本机名称", value: store.receiverDisplayName)
                        LabeledContent("服务标识", value: CarrierV2Receiver.serviceType)
                        LabeledContent("接收入口", value: v2Availability)
                        LabeledContent("已配对设备", value: store.v2Receiver.pairedDevices.map(\.deviceName).joined(separator: "、"))
                        Text(store.v2Receiver.manualConnectionHints).textSelection(.enabled).foregroundStyle(.secondary)
                        if let error = store.v2Receiver.lastErrorMessage { Text(error).textSelection(.enabled) }
                        Button("重启接收器") { store.restartFromUserAction() }
                        Text("会中断当前连接，手机可能需要重新连接。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.top, 12)
            } label: { Text("高级信息").foregroundStyle(.secondary) }
                .padding(12)
            }
        }
        .onAppear { showsConnectionGuide = summary.connectedDevices.isEmpty }
        .onChange(of: summary.connectedDevices.isEmpty) { _, isEmpty in showsConnectionGuide = isEmpty }
    }

    private func guidanceRow(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private var v2Availability: String {
        switch store.v2Receiver.state {
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
        case .receiver: "影响所有手机的连接"
        }
    }
}


/// Network-style page: adaptive width, anchored to the detail leading edge.
private struct MacConnectionPageContent<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
