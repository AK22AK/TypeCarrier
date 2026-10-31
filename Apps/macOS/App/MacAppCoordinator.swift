import AppKit
import OSLog
import TypeCarrierCore

@MainActor
final class MacAppCoordinator: NSObject, ObservableObject {
    static let mainWindowID = "main"
    private(set) lazy var store = MacCarrierStore()
    @Published private(set) var selectedPage: MacManagementPage? = .received
    let recordEditor = ReceivedRecordEditor()
    private var isPresentingEditPrompt = false
    private var closeGuard: ManagementWindowCloseGuard?

    private let logger = Logger(subsystem: "org.typecarrier.mac", category: "Lifecycle")
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var mainWindowRequestHandler: (() -> Void)?
    private var hasPendingMainWindowRequest = false
    private var hasManagementWindow = false
    private var windowCloseObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleepStartedAt: Date?
    private var lastWakeRestartAt: Date?
    private let wakeRestartDebounceInterval: TimeInterval = 2
    private let compactWindowSizeAppliedKey = "MacManagementWindowSize740x609Applied"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setManagementWindowOpen(hasManagementWindow)
        observeManagementWindowClose()
        _ = store // Start receiving even when the management window has never opened.
        hotKeyMonitor.register { [weak self] in
            self?.showMainWindow()
        }
        observeWorkspaceWake()
    }

    func setMainWindowRequestHandler(_ handler: @escaping () -> Void) {
        mainWindowRequestHandler = handler
        if hasPendingMainWindowRequest {
            hasPendingMainWindowRequest = false
            handler()
        }
    }

    func showMainWindow(page: MacManagementPage? = nil) {
        if let page { selectPage(page) }
        setManagementWindowOpen(true)
        if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID && $0.canBecomeMain }) {
            NSApp.activate(ignoringOtherApps: true)
            if existingWindow.isMiniaturized { existingWindow.deminiaturize(nil) }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let mainWindowRequestHandler else {
            // A reopen event may arrive before the menu label installs openWindow.
            hasPendingMainWindowRequest = true
            return
        }
        mainWindowRequestHandler()
    }

    func managementWindowDidAppear() {
        setManagementWindowOpen(true)
        DispatchQueue.main.async { [weak self] in
            self?.applyCompactWindowSizeOnce()
            self?.updateEditingCloseGuard()
        }
    }

    func selectPage(_ page: MacManagementPage?, onCancel: @escaping () -> Void = {}) {
        guard selectedPage != page else { return }
        resolveRecordEdits(onCancel: onCancel) { self.selectedPage = page }
    }

    @discardableResult
    func saveRecordEdits() -> Bool {
        finishRecordTextComposition()
        var failure = "这条接收记录已不存在，未保存的文字仍保留在编辑框中。"
        let succeeded = recordEditor.save(persist: { id, text in
            guard let record = self.store.receivedHistory.first(where: { $0.id == id }) else { return false }
            let succeeded = self.store.updateText(for: record, text: text)
            if !succeeded { failure = self.store.lastPasteResult.status }
            return succeeded
        }, failureMessage: { failure })
        if succeeded { updateEditingCloseGuard() }
        return succeeded
    }

    /// Called before a selection, route, close, or quit is allowed to change.
    func resolveRecordEdits(onCancel: @escaping () -> Void = {}, then action: @escaping () -> Void) {
        finishRecordTextComposition()
        guard recordEditor.hasChanges else {
            recordEditor.discard()
            updateEditingCloseGuard()
            action()
            return
        }
        guard !isPresentingEditPrompt,
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }),
              window.attachedSheet == nil else {
            onCancel()
            return
        }
        isPresentingEditPrompt = true
        let alert = NSAlert()
        alert.messageText = "保存对接收记录的修改？"
        alert.informativeText = "不保存会丢弃本次编辑。取消将继续编辑当前记录。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPresentingEditPrompt = false
                switch response {
                case .alertFirstButtonReturn:
                    if self.saveRecordEdits() { action() } else { onCancel() }
                case .alertSecondButtonReturn:
                    self.recordEditor.discard()
                    self.updateEditingCloseGuard()
                    action()
                default:
                    onCancel()
                }
            }
        }
    }

    func deleteConfirmedRecords(_ records: [CarrierRecord]) {
        for record in records {
            if store.delete(record), recordEditor.recordID == record.id {
                recordEditor.discard()
            }
        }
    }

    /// A composing input method may not publish its text binding until commit.
    func finishRecordTextComposition() {
        guard recordEditor.recordID != nil,
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }),
              let input = window.firstResponder as? NSTextView, input.hasMarkedText() else { return }
        input.unmarkText()
        recordEditor.draft = input.string
    }

    func updateEditingCloseGuard() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }) else { return }
        guard recordEditor.recordID != nil else {
            closeGuard?.restoreDelegate(on: window)
            closeGuard = nil
            return
        }
        if let closeGuard, window.delegate === closeGuard { return }
        let guardDelegate = ManagementWindowCloseGuard(coordinator: self, forwardingTo: window.delegate)
        closeGuard = guardDelegate
        window.delegate = guardDelegate
    }

    private func applyCompactWindowSizeOnce() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }) else { return }
        let autosaveName = window.frameAutosaveName.isEmpty ? "TypeCarrierManagementWindow" : window.frameAutosaveName
        _ = window.setFrameAutosaveName(autosaveName)
        if UserDefaults.standard.bool(forKey: compactWindowSizeAppliedKey) {
            _ = window.setFrameUsingName(autosaveName)
            return
        }
        var frame = window.frame
        frame.size = NSSize(width: 740, height: 609)
        window.setFrame(frame, display: true)
        window.saveFrame(usingName: autosaveName)
        UserDefaults.standard.set(true, forKey: compactWindowSizeAppliedKey)
    }

    private func setManagementWindowOpen(_ isOpen: Bool) {
        hasManagementWindow = isOpen
        let policy: NSApplication.ActivationPolicy = isOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func observeManagementWindowClose() {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard window.identifier?.rawValue == Self.mainWindowID else { return }
                // Only a real close removes the Dock entry. Minimizing and closing
                // menus or auxiliary panels must not change management-window state.
                self?.setManagementWindowOpen(false)
            }
        }
    }

    private func observeWorkspaceWake() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let sleepNotifications: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
        ]
        let wakeNotifications: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]

        let sleepObservers = sleepNotifications.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let notificationName = notification.name.rawValue
                Task { @MainActor [weak self] in
                    self?.handleSleep(notificationName: notificationName)
                }
            }
        }

        let wakeObservers = wakeNotifications.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let notificationName = notification.name.rawValue
                Task { @MainActor [weak self] in
                    self?.handleWake(notificationName: notificationName)
                }
            }
        }

        workspaceObservers = sleepObservers + wakeObservers
    }

    private func handleSleep(notificationName: String) {
        sleepStartedAt = Date()
        logger.info("Workspace sleep notification: \(notificationName, privacy: .public)")
        store.recordLifecycleMarker(
            "mac.sleep",
            message: "Workspace sleep notification received: \(notificationName)."
        )
    }

    private func handleWake(notificationName: String) {
        let now = Date()
        let sleepDuration = sleepStartedAt.map { now.timeIntervalSince($0) }

        logger.info("Workspace wake notification: \(notificationName, privacy: .public)")
        store.recordLifecycleMarker(
            "mac.wake",
            message: "Workspace wake notification received: \(notificationName)."
        )

        if let lastWakeRestartAt,
           now.timeIntervalSince(lastWakeRestartAt) < wakeRestartDebounceInterval {
            store.recordLifecycleMarker(
                "receiver.restart.wakeSkipped",
                message: "Skipped duplicate wake restart for \(notificationName)."
            )
            return
        }

        lastWakeRestartAt = now
        store.restartAfterWake(notificationName: notificationName, sleepDuration: sleepDuration)
    }
}

extension MacAppCoordinator: NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        finishRecordTextComposition()
        guard recordEditor.hasChanges else { return .terminateNow }
        guard !isPresentingEditPrompt,
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }),
              window.attachedSheet == nil else { return .terminateCancel }
        resolveRecordEdits(onCancel: { sender.reply(toApplicationShouldTerminate: false) }) {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }
}

/// Forward every existing SwiftUI window-delegate callback except the close veto.
@MainActor
private final class ManagementWindowCloseGuard: NSObject, NSWindowDelegate {
    private weak var coordinator: MacAppCoordinator?
    private weak var originalDelegate: (any NSWindowDelegate)?

    init(coordinator: MacAppCoordinator, forwardingTo delegate: (any NSWindowDelegate)?) {
        self.coordinator = coordinator
        originalDelegate = delegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator else { return originalDelegate?.windowShouldClose?(sender) ?? true }
        coordinator.finishRecordTextComposition()
        if coordinator.recordEditor.hasChanges {
            coordinator.resolveRecordEdits { [weak sender] in
                // Let AppKit finish removing the confirmation sheet before retrying close.
                DispatchQueue.main.async { sender?.performClose(nil) }
            }
            return false
        }
        coordinator.recordEditor.discard()
        restoreDelegate(on: sender)
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    func restoreDelegate(on window: NSWindow) {
        if window.delegate === self { window.delegate = originalDelegate }
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || MainActor.assumeIsolated { originalDelegate?.responds(to: selector) ?? false }
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        let target = MainActor.assumeIsolated { () -> WindowDelegateTarget? in
            guard let originalDelegate, originalDelegate.responds(to: selector) else { return nil }
            return WindowDelegateTarget(delegate: originalDelegate)
        }
        return target?.delegate ?? super.forwardingTarget(for: selector)
    }
}

// AppKit delegate forwarding is synchronous on the main thread. This box carries
// the non-Sendable Objective-C reference out of the checked assumeIsolated call.
private struct WindowDelegateTarget: @unchecked Sendable {
    let delegate: any NSWindowDelegate
}
