import AppKit
import SwiftUI

@MainActor
final class MacAppCoordinator: NSObject, ObservableObject {
    let store = MacCarrierStore()

    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var mainWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []

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
        let wakeNotifications: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]

        workspaceObservers = wakeNotifications.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.store.restart()
                }
            }
        }
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
