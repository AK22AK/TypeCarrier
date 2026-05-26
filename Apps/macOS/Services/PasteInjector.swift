import AppKit
import ApplicationServices
import TypeCarrierCore

struct PasteInjectionResult: Equatable {
    static let idle = PasteInjectionResult(status: "尚未测试", succeeded: false)

    let status: String
    let diagnosticDetail: String
    let succeeded: Bool
    let pasteStatus: CarrierDeliveryReceipt.PasteStatus
    let date: Date

    init(
        status: String,
        diagnosticDetail: String? = nil,
        succeeded: Bool,
        pasteStatus: CarrierDeliveryReceipt.PasteStatus? = nil,
        date: Date = Date()
    ) {
        self.status = status
        self.diagnosticDetail = diagnosticDetail ?? status
        self.succeeded = succeeded
        self.pasteStatus = pasteStatus ?? (succeeded ? .posted : .failed)
        self.date = date
    }

    var fullDetail: String {
        guard diagnosticDetail != status else {
            return status
        }

        return "\(status) | \(diagnosticDetail)"
    }

}

struct PasteInjector {
    private let accessibilityChecker = AccessibilityPermissionChecker()

    func paste(text: String, restoreDelay: TimeInterval = 0.45) -> PasteInjectionResult {
        var trace = PasteInjectionTrace(text: text)
        guard accessibilityChecker.isTrusted(prompt: false) else {
            trace.add("accessibilityTrusted", "false")
            return PasteInjectionResult(
                status: "已接收文本，但需要辅助功能权限才能自动粘贴",
                diagnosticDetail: trace.summary,
                succeeded: false
            )
        }
        trace.add("accessibilityTrusted", "true")

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            trace.add("pasteboardWrite", "failed")
            return PasteInjectionResult(
                status: "写入剪贴板失败",
                diagnosticDetail: trace.summary,
                succeeded: false
            )
        }
        let pasteboardChangeCount = pasteboard.changeCount
        trace.add("pasteboardWrite", "success")
        trace.add("pasteboardChangeCount", "\(pasteboardChangeCount)")

        guard postCommandV() else {
            trace.add("commandVPosted", "false")
            return PasteInjectionResult(
                status: "发送 Command-V 失败",
                diagnosticDetail: trace.summary,
                succeeded: false
            )
        }
        trace.add("commandVPosted", "true")
        trace.add("clipboardRestore", "scheduledAfterCommandV")
        scheduleClipboardRestore(
            previousString: previousString,
            changeCount: pasteboardChangeCount,
            delay: restoreDelay
        )
        return PasteInjectionResult(
            status: "已接收文本，已发送粘贴指令",
            diagnosticDetail: trace.summary,
            succeeded: true,
            pasteStatus: .posted
        )
    }

    private func scheduleClipboardRestore(previousString: String?, changeCount: Int, delay: TimeInterval) {
        if let previousString {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let restoreBoard = NSPasteboard.general
                guard restoreBoard.changeCount == changeCount else {
                    return
                }
                restoreBoard.clearContents()
                restoreBoard.setString(previousString, forType: .string)
            }
        }
    }

    private func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeForV: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

}

private struct PasteInjectionTrace {
    private var fields: [(String, String)] = []

    init(text: String) {
        add("textChars", "\(text.count)")
        add("textUTF16", "\(text.utf16.count)")
    }

    mutating func add(_ key: String, _ value: String) {
        fields.append((key, value))
    }

    var summary: String {
        fields
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
    }
}
