import Foundation

public enum PasteFailureGuidance {
    public static func suggestion(status: String, detail: String? = nil) -> String? {
        let text = [status, detail].compactMap { $0 }.joined(separator: " ")

        if text.contains("需要辅助功能权限")
            || text.contains("Accessibility permission required")
            || text.contains("accessibilityTrusted=false") {
            return "在系统设置中为 TypeCarrier 开启辅助功能权限，然后回到 Mac 端再测试粘贴。"
        }

        if text.contains("未接受 Command-V")
            || text.contains("did not accept Command-V")
            || text.contains("发送 Command-V 失败")
            || text.contains("Failed to post Command-V") {
            return "确认 Mac 光标停在可输入文本框内；如果目标 App 不接受模拟粘贴，先手动粘贴剪贴板内容。"
        }

        if text.contains("写入剪贴板失败")
            || text.contains("Failed to write clipboard")
            || text.contains("pasteboardWrite=failed") {
            return "TypeCarrier 没能写入系统剪贴板；请重试，或先确认剪贴板没有被其他工具拦截。"
        }

        if text.contains("粘贴失败") || text.contains("paste.injection.failed") {
            return "文本已经到达 Mac，但自动插入失败；请先复制或手动粘贴该条记录，再导出诊断定位原因。"
        }

        return nil
    }
}
