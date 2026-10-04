import TypeCarrierCore

/// Shared presentation for the window and menu; paste permission never blocks receiving.
struct ReceiverManagementPresentation {
    let summary: ReceiverStatusSummary
    let accessibilityTrusted: Bool
    var canReceive: Bool { summary.hasUsableEndpoint && !summary.requiresGlobalAttention }
    var needsAttention: Bool { !canReceive || summary.overallHealth != .ok || !accessibilityTrusted }
    var title: String {
        if !canReceive { return "暂时无法接收" }
        if summary.overallHealth == .degraded { return "部分入口异常" }
        return summary.connectedDevices.isEmpty ? "正在等待设备" : "可以接收"
    }
    var detail: String {
        if !canReceive { return "请在诊断与测试中检查接收服务。" }
        if summary.overallHealth == .degraded { return "仍有接收入口可用；受影响范围见下方。" }
        if summary.connectedDevices.isEmpty { return "接收器已就绪，在手机上连接这台 Mac。" }
        return "已连接 \(summary.connectedDevices.count) 台设备，文本会按收到的顺序处理。"
    }
    var menuTitle: String {
        if !canReceive { return "接收器需要处理" }
        if summary.overallHealth == .degraded { return "可以接收 · 部分入口异常" }
        if !accessibilityTrusted { return "可以接收 · 粘贴需授权" }
        return summary.connectedDevices.isEmpty ? "正在等待设备" : "可以接收 · \(summary.connectedDevices.count) 台设备"
    }
}
