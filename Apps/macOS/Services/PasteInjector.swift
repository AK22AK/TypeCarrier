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

    func paste(text: String, restoreDelay: TimeInterval? = nil) -> PasteInjectionResult {
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

        let focusedTextTarget = FocusedTextTarget.current(trace: &trace)
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
        waitForPasteDelivery()
        trace.add("postWaitSeconds", "0.25")
        focusedTextTarget?.recordPostPasteState(expectedText: text, trace: &trace)
        if let restoreDelay {
            trace.add("clipboardRestoreDelaySeconds", String(format: "%.2f", restoreDelay))
            trace.add("clipboardRestore", "scheduledAfterCommandV")
            scheduleClipboardRestore(
                previousString: previousString,
                changeCount: pasteboardChangeCount,
                delay: restoreDelay
            )
        } else {
            trace.add("clipboardRestore", "disabledBySetting")
        }
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

    private func waitForPasteDelivery() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
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

private struct FocusedTextTarget {
    private let element: AXUIElement
    private let initialValue: String?
    private let initialSelectedRange: NSRange?

    static func current(trace: inout PasteInjectionTrace) -> FocusedTextTarget? {
        let app = NSWorkspace.shared.frontmostApplication
        trace.add("frontApp", app?.localizedName ?? "unknown")
        trace.add("frontBundle", app?.bundleIdentifier ?? "unknown")
        if let processIdentifier = app?.processIdentifier {
            trace.add("frontPID", "\(processIdentifier)")
        }

        let system = AXUIElementCreateSystemWide()
        let focusedElementResult = copyAttribute(system, kAXFocusedUIElementAttribute)
        trace.add("focusedElementResult", focusedElementResult.result.debugDescription)
        guard let focusedElement = focusedElementResult.value,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            trace.add("focusedElementType", "unavailable")
            return nil
        }

        let element = unsafeDowncast(focusedElement, to: AXUIElement.self)
        let role = stringAttribute(element, kAXRoleAttribute)
        let subrole = stringAttribute(element, kAXSubroleAttribute)
        trace.add("role", role.value ?? "unknown")
        trace.add("roleResult", role.result.debugDescription)
        trace.add("subrole", subrole.value ?? "unknown")
        trace.add("subroleResult", subrole.result.debugDescription)

        let initialValueResult = stringAttribute(element, kAXValueAttribute)
        trace.add("initialValueResult", initialValueResult.result.debugDescription)
        if let value = initialValueResult.value {
            trace.add("initialValueUTF16", "\(value.utf16.count)")
        }

        let selectedRangeResult = selectedTextRange(element)
        trace.add("initialSelectionResult", selectedRangeResult.result.debugDescription)
        if let range = selectedRangeResult.value {
            trace.add("initialSelection", "\(range.location):\(range.length)")
        }

        return FocusedTextTarget(
            element: element,
            initialValue: initialValueResult.value,
            initialSelectedRange: selectedRangeResult.value
        )
    }

    func recordPostPasteState(expectedText text: String, trace: inout PasteInjectionTrace) {
        guard let initialValue else {
            trace.add("verification", "initialValueUnavailable")
            return
        }

        let currentValueResult = Self.stringAttribute(element, kAXValueAttribute)
        trace.add("postValueResult", currentValueResult.result.debugDescription)
        guard let currentValue = currentValueResult.value else {
            trace.add("verification", "currentValueUnavailable")
            return
        }

        trace.add("postValueUTF16", "\(currentValue.utf16.count)")
        trace.add("postValueChanged", currentValue == initialValue ? "false" : "true")
        if let expectedValue = expectedValue(inserting: text) {
            trace.add("expectedValueAvailable", "true")
            trace.add("matchesExpectedValue", currentValue == expectedValue ? "true" : "false")
        } else {
            trace.add("expectedValueAvailable", "false")
            trace.add("containsInsertedText", currentValue != initialValue && currentValue.contains(text) ? "true" : "false")
        }
    }

    private func expectedValue(inserting text: String) -> String? {
        guard let initialValue, let initialSelectedRange else {
            return nil
        }

        return TextInsertionPolicy.replacingText(
            in: initialValue,
            selectedUTF16Range: initialSelectedRange,
            with: text
        )
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> (value: AnyObject?, result: AXError) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (result == .success ? value : nil, result)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> (value: String?, result: AXError) {
        let result = copyAttribute(element, attribute)
        return (result.value as? String, result.result)
    }

    private static func selectedTextRange(_ element: AXUIElement) -> (value: NSRange?, result: AXError) {
        let result = copyAttribute(element, kAXSelectedTextRangeAttribute)
        guard let value = result.value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return (nil, result.result)
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return (nil, result.result)
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return (nil, result.result)
        }
        return (NSRange(location: range.location, length: range.length), result.result)
    }
}

private extension AXError {
    var debugDescription: String {
        switch self {
        case .success:
            "success"
        case .failure:
            "failure"
        case .illegalArgument:
            "illegalArgument"
        case .invalidUIElement:
            "invalidUIElement"
        case .invalidUIElementObserver:
            "invalidUIElementObserver"
        case .cannotComplete:
            "cannotComplete"
        case .attributeUnsupported:
            "attributeUnsupported"
        case .actionUnsupported:
            "actionUnsupported"
        case .notificationUnsupported:
            "notificationUnsupported"
        case .notImplemented:
            "notImplemented"
        case .notificationAlreadyRegistered:
            "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            "notificationNotRegistered"
        case .apiDisabled:
            "apiDisabled"
        case .noValue:
            "noValue"
        case .parameterizedAttributeUnsupported:
            "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            "notEnoughPrecision"
        @unknown default:
            "unknown(\(rawValue))"
        }
    }
}
