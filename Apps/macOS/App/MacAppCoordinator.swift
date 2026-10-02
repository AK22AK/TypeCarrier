import AppKit
import OSLog

@MainActor
final class MacAppCoordinator: NSObject, ObservableObject {
    static let mainWindowID = "main"
    private(set) lazy var store = MacCarrierStore()

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

    func showMainWindow() {
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }
}
