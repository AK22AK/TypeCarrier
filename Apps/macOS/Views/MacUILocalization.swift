import Foundation
import TypeCarrierCore

extension ConnectionState {
    var localizedDisplayText: String {
        switch self {
        case .idle:
            "空闲"
        case .searching:
            "正在搜索设备"
        case .advertising:
            "正在等待连接"
        case .connecting(let peerName):
            "正在连接 \(peerName)"
        case .reconnecting(let peerName):
            "正在重新连接 \(peerName)"
        case .connected(let peerName):
            "已连接到 \(peerName)"
        case .failed(let message):
            message.localizedDiagnosticMessageText
        }
    }
}

extension Array where Element == String {
    var localizedPeerListText: String {
        isEmpty ? "无" : joined(separator: ", ")
    }
}

extension String {
    var localizedPasteDetailText: String {
        localizedDiagnosticMessageText
            .replacingOccurrences(of: "Inserted ", with: "已插入 ")
            .replacingOccurrences(of: " characters via Accessibility fallback in ", with: " 个字符（通过辅助功能兜底）到 ")
            .replacingOccurrences(of: " characters in ", with: " 个字符到 ")
            .replacingOccurrences(of: "Posted paste command for ", with: "已发送粘贴指令，共 ")
            .replacingOccurrences(of: " characters", with: " 个字符")
            .replacingOccurrences(of: "Focused ", with: "当前焦点 ")
            .replacingOccurrences(of: " did not accept Command-V", with: " 未接受 Command-V")
    }

    var localizedDiagnosticMessageText: String {
        self
            .replacingOccurrences(of: "Connection issue. Try Restart Receiver.", with: "连接异常，请尝试重启接收器。")
            .replacingOccurrences(of: "No payload received", with: "尚未收到内容")
            .replacingOccurrences(of: "History storage unavailable", with: "历史记录存储不可用")
            .replacingOccurrences(of: "Failed to update history", with: "更新历史记录失败")
            .replacingOccurrences(of: "Failed to delete history", with: "删除历史记录失败")
            .replacingOccurrences(of: "Failed to save received text", with: "保存接收文本失败")
            .replacingOccurrences(of: "Failed to update paste result", with: "更新粘贴结果失败")
            .replacingOccurrences(of: "Accessibility permission required", with: "需要辅助功能权限")
            .replacingOccurrences(of: "Failed to write clipboard", with: "写入剪贴板失败")
            .replacingOccurrences(of: "Failed to post Command-V", with: "发送 Command-V 失败")
    }
}
