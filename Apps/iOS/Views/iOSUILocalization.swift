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
    var localizedRoleText: String {
        switch self {
        case "sender":
            "发送端"
        case "receiver":
            "接收端"
        default:
            self
        }
    }

    var localizedDiagnosticMessageText: String {
        self
            .replacingOccurrences(of: "Try Restart Receiver on the Mac, then retry here.", with: "请先在 Mac 上重启接收器，然后在这里重试。")
            .replacingOccurrences(of: "Connection issue", with: "连接异常")
            .replacingOccurrences(of: "History storage unavailable", with: "历史记录存储不可用")
            .replacingOccurrences(of: "Failed to save history", with: "保存历史记录失败")
            .replacingOccurrences(of: "Failed to save draft", with: "保存草稿失败")
            .replacingOccurrences(of: "Failed to update history", with: "更新历史记录失败")
            .replacingOccurrences(of: "Failed to delete history", with: "删除历史记录失败")
            .replacingOccurrences(of: "Failed to clear drafts", with: "清空草稿失败")
            .replacingOccurrences(of: "Failed to clear history", with: "清空历史记录失败")
            .replacingOccurrences(of: "Text is empty", with: "文本为空")
            .replacingOccurrences(of: "Mac acknowledged receipt", with: "Mac 已确认收到")
            .replacingOccurrences(of: "Mac received and saved text", with: "Mac 已接收并保存文本")
            .replacingOccurrences(of: "Mac inserted text", with: "Mac 已插入文本")
            .replacingOccurrences(of: "Mac paste failed", with: "Mac 粘贴失败")
            .replacingOccurrences(of: "Posted paste command for ", with: "已发送粘贴指令，共 ")
            .replacingOccurrences(of: "Inserted ", with: "已插入 ")
            .replacingOccurrences(of: " characters via Accessibility fallback in ", with: " 个字符（通过辅助功能兜底）到 ")
            .replacingOccurrences(of: " characters in ", with: " 个字符到 ")
            .replacingOccurrences(of: " characters", with: " 个字符")
    }
}
