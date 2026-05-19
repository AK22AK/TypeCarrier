import Testing
@testable import TypeCarrierCore

@Suite("PasteFailureGuidance")
struct PasteFailureGuidanceTests {
    @Test("Accessibility failures tell the user to grant permission and retry")
    func accessibilityFailureGuidance() {
        let guidance = PasteFailureGuidance.suggestion(
            status: "需要辅助功能权限",
            detail: "accessibilityTrusted=false"
        )

        #expect(guidance == "在系统设置中为 TypeCarrier 开启辅助功能权限，然后回到 Mac 端再测试粘贴。")
    }

    @Test("Focus failures explain that the target input may not accept Command-V")
    func focusFailureGuidance() {
        let guidance = PasteFailureGuidance.suggestion(
            status: "当前焦点 TextEdit AXTextArea 未接受 Command-V",
            detail: "commandVPosted=true"
        )

        #expect(guidance == "确认 Mac 光标停在可输入文本框内；如果目标 App 不接受模拟粘贴，先手动粘贴剪贴板内容。")
    }

    @Test("Clipboard failures tell the user to retry after checking clipboard access")
    func clipboardFailureGuidance() {
        let guidance = PasteFailureGuidance.suggestion(
            status: "写入剪贴板失败",
            detail: "pasteboardWrite=failed"
        )

        #expect(guidance == "TypeCarrier 没能写入系统剪贴板；请重试，或先确认剪贴板没有被其他工具拦截。")
    }

    @Test("Successful paste results do not show recovery guidance")
    func successfulPasteHasNoGuidance() {
        let guidance = PasteFailureGuidance.suggestion(
            status: "已插入 4 个字符到 TextEdit AXTextArea",
            detail: "pasteboardWrite=success"
        )

        #expect(guidance == nil)
    }
}
