import Foundation

public enum SelfCheckSeverity: String, Equatable, Sendable {
    case ok
    case warning
    case blocking
    case unknown
}

public struct SelfCheckFinding: Identifiable, Equatable, Sendable {
    public let id: String
    public let severity: SelfCheckSeverity
    public let title: String
    public let detail: String
    public let actionTitle: String?
    public let relatedEventName: String?

    public init(
        id: String,
        severity: SelfCheckSeverity,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        relatedEventName: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.relatedEventName = relatedEventName
    }
}

public enum ConnectionSelfCheck {
    public static func findings(
        receiverSummary: ReceiverStatusSummary,
        accessibilityTrusted: Bool? = nil
    ) -> [SelfCheckFinding] {
        var findings = receiverAccessibilityFindings(accessibilityTrusted: accessibilityTrusted)

        switch receiverSummary.overallHealth {
        case .ok:
            findings.append(SelfCheckFinding(
                id: receiverSummary.connectedDevices.isEmpty ? "receiver.waiting" : "receiver.connected",
                severity: .ok,
                title: receiverSummary.connectedDevices.isEmpty ? "接收器正在等待连接" : "可以接收",
                detail: receiverReadyDetail(receiverSummary)
            ))
        case .degraded:
            if let issue = receiverSummary.issues.first {
                findings.append(SelfCheckFinding(
                    id: "receiver.endpoint.degraded",
                    severity: .warning,
                    title: "部分连接入口异常",
                    detail: receiverDegradedDetail(receiverSummary, issue: issue),
                    actionTitle: actionTitle(for: issue.suggestedAction)
                ))
            }
        case .actionRequired:
            if let issue = receiverSummary.issues.first {
                findings.append(SelfCheckFinding(
                    id: "receiver.actionRequired",
                    severity: .blocking,
                    title: "接收器需要处理",
                    detail: issue.message,
                    actionTitle: actionTitle(for: issue.suggestedAction)
                ))
            }
        }

        if findings.isEmpty {
            findings.append(SelfCheckFinding(
                id: "receiver.pending",
                severity: .unknown,
                title: "正在确认接收器状态",
                detail: "继续等待自动发现或查看最近调试事件。"
            ))
        }

        appendAccessibilityReadyFinding(to: &findings, accessibilityTrusted: accessibilityTrusted)

        return findings
    }

    public static func findings(
        diagnostics: CarrierDiagnostics,
        accessibilityTrusted: Bool? = nil
    ) -> [SelfCheckFinding] {
        var findings = receiverAccessibilityFindings(accessibilityTrusted: accessibilityTrusted)

        if let localNetworkFailureEvent = diagnostics.events.last(where: isLocalNetworkPermissionFailure) {
            findings.append(SelfCheckFinding(
                id: "ios.localNetworkPermission",
                severity: .blocking,
                title: "需要本地网络权限",
                detail: "iOS 需要允许 TypeCarrier 访问本地网络，才能发现同一局域网或附近的 Mac。",
                actionTitle: "在系统设置中允许本地网络",
                relatedEventName: localNetworkFailureEvent.name
            ))
        }

        if let busyEvent = diagnostics.events.last(where: { $0.name == "browser.receiverBusy" }) {
            findings.append(SelfCheckFinding(
                id: "connection.receiverBusy",
                severity: .blocking,
                title: "Mac 正在服务另一台设备",
                detail: "这台 Mac 当前已有发送端占用；断开另一台发送端后再从这里重试。",
                actionTitle: "断开另一台发送端后重试",
                relatedEventName: busyEvent.name
            ))
        }

        switch diagnostics.connectionState {
        case .connected(let peerName):
            findings.append(SelfCheckFinding(
                id: "connection.connected",
                severity: .ok,
                title: "连接可用",
                detail: "已连接到 \(peerName)，可以发送文本。"
            ))
        case .searching where diagnostics.discoveredPeers.isEmpty:
            findings.append(SelfCheckFinding(
                id: "discovery.noMac",
                severity: .warning,
                title: "没有发现 Mac",
                detail: "请确认 Mac 端 TypeCarrier 正在运行，两端在同一局域网；iOS 还需要允许本地网络访问。",
                actionTitle: "检查局域网和 Mac 接收器",
                relatedEventName: "search.timeout"
            ))
        case .failed(let message) where findings.isEmpty:
            findings.append(SelfCheckFinding(
                id: "connection.failed",
                severity: .warning,
                title: "连接失败",
                detail: message,
                actionTitle: "重试连接",
                relatedEventName: diagnostics.events.last { $0.connectionState.isFailed }?.name
            ))
        case .advertising where diagnostics.role.hasPrefix("receiver"):
            findings.append(SelfCheckFinding(
                id: "receiver.waiting",
                severity: .ok,
                title: "接收器正在等待连接",
                detail: "手机端可以在同一局域网或附近发现这台 Mac。"
            ))
        default:
            break
        }

        if findings.isEmpty {
            findings.append(SelfCheckFinding(
                id: "connection.pending",
                severity: .unknown,
                title: "正在确认连接状态",
                detail: "继续等待自动发现或查看最近调试事件。"
            ))
        }

        appendAccessibilityReadyFinding(to: &findings, accessibilityTrusted: accessibilityTrusted)

        return findings
    }

    private static func receiverAccessibilityFindings(accessibilityTrusted: Bool?) -> [SelfCheckFinding] {
        guard let accessibilityTrusted, !accessibilityTrusted else {
            return []
        }

        return [
            SelfCheckFinding(
                id: "mac.accessibility",
                severity: .blocking,
                title: "需要辅助功能权限",
                detail: "Mac 已经可以接收文本，但自动粘贴需要在系统设置中为 TypeCarrier 授权辅助功能。",
                actionTitle: "主动诊断；必要时用 + 重新添加当前 App",
                relatedEventName: "paste.command.failed"
            )
        ]
    }

    private static func appendAccessibilityReadyFinding(
        to findings: inout [SelfCheckFinding],
        accessibilityTrusted: Bool?
    ) {
        guard accessibilityTrusted == true else {
            return
        }

        findings.append(SelfCheckFinding(
            id: "mac.accessibility.ready",
            severity: .ok,
            title: "辅助功能权限正常",
            detail: "自动粘贴可以使用；需要排查时仍可打开系统设置或重置授权。"
        ))
    }

    private static func isLocalNetworkPermissionFailure(_ event: CarrierDiagnosticEvent) -> Bool {
        let haystack = "\(event.name) \(event.message)".lowercased()
        return haystack.contains("local network") ||
            haystack.contains("本地网络") ||
            (haystack.contains("permission") && haystack.contains("network")) ||
            (haystack.contains("not allowed") && haystack.contains("network"))
    }

    private static func receiverReadyDetail(_ summary: ReceiverStatusSummary) -> String {
        guard !summary.connectedDevices.isEmpty else {
            return "手机端可以在同一局域网或附近发现这台 Mac。"
        }

        let deviceNames = summary.connectedDevices.map(\.name).joined(separator: "、")
        return "已连接 \(deviceNames)，可以接收并粘贴发送内容。"
    }

    private static func receiverDegradedDetail(
        _ summary: ReceiverStatusSummary,
        issue: ReceiverStatusIssue
    ) -> String {
        let availableText: String
        switch issue.impact {
        case .endpoint(.androidBridge):
            availableText = "Apple 设备仍可发现这台 Mac"
        case .endpoint(.appleMultipeer):
            availableText = summary.connectedDevices.contains { $0.endpoint == .androidBridge }
                ? "Android 设备仍可发送到这台 Mac"
                : "Android 入口仍可用"
        case .allDevices:
            availableText = "接收器存在共享问题"
        }

        return "\(availableText)；\(issueTitle(for: issue.impact))：\(issue.message)"
    }

    private static func issueTitle(for impact: ReceiverIssueImpact) -> String {
        switch impact {
        case .allDevices:
            return "接收器异常"
        case .endpoint(.appleMultipeer):
            return "Apple 入口异常"
        case .endpoint(.androidBridge):
            return "Android 入口异常"
        }
    }

    private static func actionTitle(for action: ReceiverIssueAction?) -> String? {
        switch action {
        case .restartReceiver:
            return "重启接收器"
        case nil:
            return nil
        }
    }
}
