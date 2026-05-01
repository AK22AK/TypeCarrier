import AppKit
import OSLog
import SwiftUI

@MainActor
final class MacAppCoordinator: NSObject, ObservableObject {
    let store = MacCarrierStore()

    private let logger = Logger(subsystem: "org.typecarrier.mac", category: "Lifecycle")
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var mainWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleepStartedAt: Date?
    private var lastWakeRestartAt: Date?
    private let wakeRestartDebounceInterval: TimeInterval = 2

    override init() {
        super.init()

        hotKeyMonitor.register { [weak self] in
            self?.showMainWindow()
        }
        observeWorkspaceWake()
    }

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TypeCarrier"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: MainWindowView(store: store))
            window.center()
            mainWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
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

extension MacAppCoordinator: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else {
            return
        }

        mainWindow?.delegate = nil
        mainWindow = nil
    }
}
