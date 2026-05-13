import AppKit
import SwiftUI

@main
struct TypeCarrierMacApp: App {
    @StateObject private var coordinator = MacAppCoordinator()

    var body: some Scene {
        WindowGroup("TypeCarrier", id: "main") {
            MainWindowView(store: coordinator.store)
        }
        .defaultSize(width: 980, height: 620)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)

        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            MenuBarStatusIcon(store: coordinator.store)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        Image(nsImage: NSImage.typeCarrierMenuBarStatusIcon(state: state))
            .accessibilityLabel(accessibilityLabel)
    }

    private var state: MenuBarStatusIconState {
        if store.receiverHealthWarning != nil {
            return .warning
        }

        return store.connectionState.isConnected ? .connected : .idle
    }

    private var accessibilityLabel: String {
        if store.receiverHealthWarning != nil {
            return "TypeCarrier 接收器异常"
        }

        return store.connectionState.isConnected ? "TypeCarrier 已连接" : "TypeCarrier 空闲"
    }
}

private enum MenuBarStatusIconState {
    case idle
    case connected
    case warning
}

private extension NSImage {
    static func typeCarrierMenuBarStatusIcon(state: MenuBarStatusIconState) -> NSImage {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let keyboard = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 15.5, weight: .regular)) else {
                return false
            }

            let keyboardRect = keyboard
                .aspectFitRect(
                    in: NSRect(x: 0, y: 1, width: 21, height: 15)
                )
                .integral

            keyboard.draw(
                in: keyboardRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            if let badgeSymbolName = state.badgeSymbolName,
               let badge = NSImage(
                systemSymbolName: badgeSymbolName,
                accessibilityDescription: nil
               )?.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold)) {
                badge.draw(
                    in: NSRect(x: rect.maxX - 11, y: 0, width: 10, height: 10),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    private func aspectFitRect(in boundingRect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else {
            return boundingRect
        }

        let scale = min(boundingRect.width / size.width, boundingRect.height / size.height)
        let width = size.width * scale
        let height = size.height * scale

        return NSRect(
            x: boundingRect.midX - width / 2,
            y: boundingRect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private extension MenuBarStatusIconState {
    var badgeSymbolName: String? {
        switch self {
        case .idle:
            return nil
        case .connected:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
}
