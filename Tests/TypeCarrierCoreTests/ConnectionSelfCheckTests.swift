import Testing
@testable import TypeCarrierCore

@Suite("ConnectionSelfCheck")
struct ConnectionSelfCheckTests {
    @Test("Searching with no discovered peers explains discovery prerequisites")
    func searchingWithoutPeersShowsDiscoveryGuidance() {
        let findings = ConnectionSelfCheck.findings(
            diagnostics: CarrierDiagnostics(
                role: "sender",
                localPeerName: "iPhone",
                serviceType: "typecarrier",
                connectionState: .searching
            )
        )

        #expect(findings.first?.severity == .warning)
        #expect(findings.first?.title == "没有发现 Mac")
        #expect(findings.first?.actionTitle == "检查局域网和 Mac 接收器")
        #expect(findings.first?.relatedEventName == "search.timeout")
    }

    @Test("Local network permission failures explain the iOS system permission")
    func localNetworkPermissionFailureShowsSpecificGuidance() {
        let findings = ConnectionSelfCheck.findings(
            diagnostics: CarrierDiagnostics(
                role: "sender",
                localPeerName: "iPhone",
                serviceType: "typecarrier",
                connectionState: .searching,
                events: [
                    CarrierDiagnosticEvent(
                        name: "browser.failed",
                        message: "The app is not allowed to use the local network.",
                        peerName: nil,
                        connectionState: .searching,
                        connectedPeers: []
                    )
                ]
            )
        )

        #expect(findings.first?.severity == .blocking)
        #expect(findings.first?.title == "需要本地网络权限")
        #expect(findings.first?.actionTitle == "在系统设置中允许本地网络")
        #expect(findings.first?.relatedEventName == "browser.failed")
    }

    @Test("Busy receiver failure tells the user another sender is active")
    func busyReceiverShowsActiveSenderGuidance() {
        let findings = ConnectionSelfCheck.findings(
            diagnostics: CarrierDiagnostics(
                role: "sender",
                localPeerName: "iPhone",
                serviceType: "typecarrier",
                connectionState: .failed("MacBook Pro is already connected to another device."),
                events: [
                    CarrierDiagnosticEvent(
                        name: "browser.receiverBusy",
                        message: "Receiver is busy",
                        peerName: "MacBook Pro",
                        connectionState: .failed("MacBook Pro is already connected to another device."),
                        connectedPeers: []
                    )
                ]
            )
        )

        #expect(findings.first?.severity == .blocking)
        #expect(findings.first?.title == "Mac 正在服务另一台设备")
        #expect(findings.first?.actionTitle == "断开另一台发送端后重试")
        #expect(findings.first?.relatedEventName == "browser.receiverBusy")
    }

    @Test("Mac diagnostics report Accessibility as blocking when automatic paste is unavailable")
    func accessibilityFindingBlocksAutomaticPaste() {
        let findings = ConnectionSelfCheck.findings(
            diagnostics: CarrierDiagnostics(
                role: "receiver",
                localPeerName: "MacBook Pro",
                serviceType: "typecarrier",
                connectionState: .advertising
            ),
            accessibilityTrusted: false
        )

        #expect(findings.first?.severity == .blocking)
        #expect(findings.first?.title == "需要辅助功能权限")
        #expect(findings.first?.actionTitle == "主动诊断；必要时用 + 重新添加当前 App")
    }

    @Test("Mac diagnostics confirm Accessibility when automatic paste is available")
    func accessibilityFindingConfirmsAutomaticPasteAvailable() {
        let findings = ConnectionSelfCheck.findings(
            receiverSummary: ReceiverStatusSummary(
                appleConnectionState: .advertising,
                appleConnectedDeviceNames: [],
                androidConnectionState: .listening,
                androidConnectedDeviceNames: []
            ),
            accessibilityTrusted: true
        )

        let accessibilityFinding = findings.first { $0.id == "mac.accessibility.ready" }
        #expect(accessibilityFinding?.severity == .ok)
        #expect(accessibilityFinding?.title == "辅助功能权限正常")
        #expect(accessibilityFinding?.detail == "自动粘贴可以使用；需要排查时仍可打开系统设置或重置授权。")
    }

    @Test("Connected sender reports ready state")
    func connectedSenderReportsReady() {
        let findings = ConnectionSelfCheck.findings(
            diagnostics: CarrierDiagnostics(
                role: "sender",
                localPeerName: "iPhone",
                serviceType: "typecarrier",
                connectionState: .connected("MacBook Pro"),
                connectedPeers: ["MacBook Pro"]
            )
        )

        #expect(findings.first?.severity == .ok)
        #expect(findings.first?.title == "连接可用")
        #expect(findings.first?.actionTitle == nil)
    }

    @Test("Receiver self-check reports Android endpoint issues without hiding Apple availability")
    func receiverSelfCheckReportsEndpointIssueScope() {
        let findings = ConnectionSelfCheck.findings(
            receiverSummary: ReceiverStatusSummary(
                appleConnectionState: .advertising,
                appleConnectedDeviceNames: [],
                androidConnectionState: .failed("Address already in use"),
                androidConnectedDeviceNames: []
            ),
            accessibilityTrusted: true
        )

        #expect(findings.first?.severity == .warning)
        #expect(findings.first?.title == "部分连接入口异常")
        #expect(findings.first?.detail == "Apple 设备仍可发现这台 Mac；Android 入口异常：Address already in use")
        #expect(findings.first?.actionTitle == "重启接收器")
    }

    @Test("Receiver self-check names simultaneous Apple and Android connections")
    func receiverSelfCheckNamesSimultaneousConnections() {
        let findings = ConnectionSelfCheck.findings(
            receiverSummary: ReceiverStatusSummary(
                appleConnectionState: .connected("iPhone"),
                appleConnectedDeviceNames: ["iPhone"],
                androidConnectionState: .connected("Pixel"),
                androidConnectedDeviceNames: ["Pixel"]
            ),
            accessibilityTrusted: true
        )

        #expect(findings.first?.severity == .ok)
        #expect(findings.first?.title == "可以接收")
        #expect(findings.first?.detail == "已连接 iPhone、Pixel，可以接收并粘贴发送内容。")
    }
}
