import AppKit
import ApplicationServices
import TypeCarrierCore

struct PasteInjectionResult: Equatable {
    static let idle = PasteInjectionResult(status: "Not tested", succeeded: false)

    let status: String
    let diagnosticDetail: String
    let succeeded: Bool
    let date: Date

    init(status: String, diagnosticDetail: String? = nil, succeeded: Bool, date: Date = Date()) {
        self.status = status
        self.diagnosticDetail = diagnosticDetail ?? status
        self.succeeded = succeeded
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
                status: "Accessibility permission required",
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
                status: "Failed to write clipboard",
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
                status: "Failed to post Command-V",
                diagnosticDetail: trace.summary,
                succeeded: false
            )
        }
        trace.add("commandVPosted", "true")

        waitForPasteDelivery()
        trace.add("postWaitSeconds", "0.16")

        if let focusedTextTarget {
            if focusedTextTarget.didInsert(text, trace: &trace) {
                scheduleClipboardRestore(
                    previousString: previousString,
                    changeCount: pasteboardChangeCount,
                    delay: restoreDelay
                )
                return PasteInjectionResult(
                    status: "Inserted \(text.count) characters in \(focusedTextTarget.targetDescription)",
                    diagnosticDetail: trace.summary,
                    succeeded: true
                )
            }

            if focusedTextTarget.isUnchangedAfterPaste(trace: &trace),
               let result = focusedTextTarget.insertDirectly(text, trace: &trace) {
                scheduleClipboardRestore(
                    previousString: previousString,
                    changeCount: pasteboardChangeCount,
                    delay: restoreDelay
                )
                return PasteInjectionResult(
                    status: result.status,
                    diagnosticDetail: trace.summary,
                    succeeded: result.succeeded,
                    date: result.date
                )
            }

            if focusedTextTarget.canVerifyInsertion {
                scheduleClipboardRestore(
                    previousString: previousString,
                    changeCount: pasteboardChangeCount,
                    delay: restoreDelay
                )
                return PasteInjectionResult(
                    status: "Focused \(focusedTextTarget.targetDescription) did not accept Command-V",
                    diagnosticDetail: trace.summary,
                    succeeded: false
                )
            }
        }

        scheduleClipboardRestore(
            previousString: previousString,
            changeCount: pasteboardChangeCount,
            delay: restoreDelay
        )

        trace.add("verification", "unavailable")
        return PasteInjectionResult(
            status: "Posted paste command for \(text.count) characters",
            diagnosticDetail: trace.summary,
            succeeded: true
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.16))
    }
}

private struct FocusedTextTarget {
    private let element: AXUIElement
    private let initialValue: String?
    private let initialSelectedRange: NSRange?
    private let appName: String?
    private let role: String?

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
        guard let focusedElement = focusedElementResult.value else {
            return nil
        }

        let element = focusedElement as! AXUIElement
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

        let role = stringAttribute(element, kAXRoleAttribute).value
        let subrole = stringAttribute(element, kAXSubroleAttribute).value
        trace.add("role", role ?? "unknown")
        trace.add("subrole", subrole ?? "unknown")

        return FocusedTextTarget(
            element: element,
            initialValue: initialValueResult.value,
            initialSelectedRange: selectedRangeResult.value,
            appName: app?.localizedName,
            role: role
        )
    }

    var canVerifyInsertion: Bool {
        initialValue != nil
    }

    func isUnchangedAfterPaste(trace: inout PasteInjectionTrace) -> Bool {
        guard let initialValue else {
            trace.add("postValueComparison", "initialValueUnavailable")
            return false
        }

        let currentValueResult = Self.stringAttribute(element, kAXValueAttribute)
        trace.add("postValueResult", currentValueResult.result.debugDescription)
        guard let currentValue = currentValueResult.value else {
            trace.add("postValueComparison", "currentValueUnavailable")
            return false
        }

        trace.add("postValueUTF16", "\(currentValue.utf16.count)")
        let unchanged = currentValue == initialValue
        trace.add("postValueChanged", unchanged ? "false" : "true")
        return unchanged
    }

    var targetDescription: String {
        [appName, role].compactMap { $0 }.joined(separator: " ")
    }

    func didInsert(_ text: String, trace: inout PasteInjectionTrace) -> Bool {
        guard let initialValue else {
            trace.add("verification", "initialValueUnavailable")
            return false
        }

        let currentValueResult = Self.stringAttribute(element, kAXValueAttribute)
        trace.add("postValueResult", currentValueResult.result.debugDescription)
        guard let currentValue = currentValueResult.value else {
            trace.add("verification", "currentValueUnavailable")
            return false
        }

        trace.add("postValueUTF16", "\(currentValue.utf16.count)")
        trace.add("postValueChanged", currentValue == initialValue ? "false" : "true")

        if let expectedValue = expectedValue(inserting: text) {
            let matchesExpectedValue = currentValue == expectedValue
            trace.add("expectedValueAvailable", "true")
            trace.add("matchesExpectedValue", matchesExpectedValue ? "true" : "false")
            return matchesExpectedValue
        }

        let containsInsertedText = currentValue != initialValue && currentValue.contains(text)
        trace.add("expectedValueAvailable", "false")
        trace.add("containsInsertedText", containsInsertedText ? "true" : "false")
        return containsInsertedText
    }

    func insertDirectly(_ text: String, trace: inout PasteInjectionTrace) -> PasteInjectionResult? {
        guard
            let updatedValue = expectedValue(inserting: text)
        else {
            trace.add("accessibilityFallback", "notAttempted")
            return nil
        }

        guard isAttributeSettable(kAXValueAttribute, trace: &trace) else {
            trace.add("accessibilityFallback", "valueNotSettable")
            return nil
        }

        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updatedValue as CFString)
        trace.add("accessibilitySetValueResult", result.debugDescription)
        guard result == .success else {
            trace.add("accessibilityFallback", "setValueFailed")
            return nil
        }

        updateSelectionAfterInsertedText(text, trace: &trace)
        trace.add("accessibilityFallback", "succeeded")
        return PasteInjectionResult(
            status: "Inserted \(text.count) characters via Accessibility fallback in \(targetDescription)",
            succeeded: true
        )
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

    private func updateSelectionAfterInsertedText(_ text: String, trace: inout PasteInjectionTrace) {
        guard let initialSelectedRange else {
            trace.add("accessibilitySelectionUpdate", "initialSelectionUnavailable")
            return
        }

        var updatedRange = CFRange(
            location: initialSelectedRange.location + text.utf16.count,
            length: 0
        )
        guard let value = AXValueCreate(.cfRange, &updatedRange) else {
            trace.add("accessibilitySelectionUpdate", "createRangeFailed")
            return
        }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        trace.add("accessibilitySelectionUpdate", result.debugDescription)
    }

    private func isAttributeSettable(_ attribute: String, trace: inout PasteInjectionTrace) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        trace.add("valueSettableResult", result.debugDescription)
        trace.add("valueSettable", settable.boolValue ? "true" : "false")
        return result == .success && settable.boolValue
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
        guard
            let value = result.value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return (nil, result.result)
        }

        let axValue = value as! AXValue
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
