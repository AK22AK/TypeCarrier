import AppKit

struct PasteInjectionResult: Equatable {
    static let idle = PasteInjectionResult(status: "Not tested", succeeded: false)

    let status: String
    let succeeded: Bool
    let date: Date

    init(status: String, succeeded: Bool, date: Date = Date()) {
        self.status = status
        self.succeeded = succeeded
        self.date = date
    }
}

struct PasteInjector {
    private let accessibilityChecker = AccessibilityPermissionChecker()

    func paste(text: String, restoreDelay: TimeInterval = 0.45) -> PasteInjectionResult {
        guard accessibilityChecker.isTrusted(prompt: false) else {
            return PasteInjectionResult(status: "Accessibility permission required", succeeded: false)
        }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return PasteInjectionResult(status: "Failed to write clipboard", succeeded: false)
        }
        let pasteboardChangeCount = pasteboard.changeCount

        guard postCommandV() else {
            return PasteInjectionResult(status: "Failed to post Command-V", succeeded: false)
        }

        if let previousString {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                let restoreBoard = NSPasteboard.general
                guard restoreBoard.changeCount == pasteboardChangeCount else {
                    return
                }
                restoreBoard.clearContents()
                restoreBoard.setString(previousString, forType: .string)
            }
        }

        return PasteInjectionResult(status: "Pasted \(text.count) characters", succeeded: true)
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
