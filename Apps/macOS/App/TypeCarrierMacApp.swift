import AppKit
import SwiftUI

@main
struct TypeCarrierMacApp: App {
    @StateObject private var coordinator = MacAppCoordinator()

    var body: some Scene {
        WindowGroup("TypeCarrier", id: "main") {
            MainWindowView(store: coordinator.store)
        }
        .defaultSize(width: 900, height: 620)
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
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.setFill()
            drawTypeCarrierMenuBarMark(in: NSRect(x: 0, y: 2, width: 23, height: 14))

            if let badgeSymbolName = state.badgeSymbolName,
               let badge = NSImage(
                systemSymbolName: badgeSymbolName,
                accessibilityDescription: nil
               )?.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold)) {
                badge.draw(
                    in: NSRect(x: rect.maxX - 10, y: 0, width: 10, height: 10),
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

    private static func drawTypeCarrierMenuBarMark(in rect: NSRect) {
        let unit = rect.width / 52
        let heightUnit = rect.height / 34
        let midY = rect.midY

        func x(_ value: CGFloat) -> CGFloat {
            rect.minX + value * unit
        }

        func capsule(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) {
            let path = NSBezierPath(
                roundedRect: NSRect(
                    x: centerX - width / 2,
                    y: centerY - height / 2,
                    width: width,
                    height: height
                ),
                xRadius: width / 2,
                yRadius: width / 2
            )
            path.fill()
        }

        let bars: [(x: CGFloat, height: CGFloat, width: CGFloat)] = [
            (4.8, 2.6, 2.3),
            (7.4, 5.0, 2.3),
            (10.2, 10.8, 2.4),
            (12.9, 20.6, 2.5),
            (15.2, 34.0, 2.7),
            (18.4, 31.2, 2.6),
            (21.7, 25.4, 2.5),
            (24.8, 19.2, 2.4),
            (27.7, 13.8, 2.2),
            (30.2, 9.2, 2.0),
            (32.4, 5.8, 1.9)
        ]

        for (index, bar) in bars.enumerated() {
            let width = max(bar.width * unit, 0.9)
            let height = max(bar.height * heightUnit, index == 0 ? width : 1.2)
            if index == 0 {
                NSBezierPath(
                    ovalIn: NSRect(
                        x: x(bar.x) - height / 2,
                        y: midY - height / 2,
                        width: height,
                        height: height
                    )
                ).fill()
            } else {
                capsule(centerX: x(bar.x), centerY: midY, width: width, height: height)
            }
        }

        let dots: [(x: CGFloat, size: CGFloat)] = [
            (34.8, 3.0),
            (36.8, 2.3),
            (38.7, 1.7),
            (40.4, 1.2),
            (42.0, 0.8)
        ]

        for dot in dots {
            let size = max(dot.size * unit * 0.52, 0.8)
            NSBezierPath(
                ovalIn: NSRect(
                    x: x(dot.x) - size / 2,
                    y: midY - size / 2,
                    width: size,
                    height: size
                )
            ).fill()
        }

        capsule(centerX: x(47), centerY: midY, width: 3.2 * unit, height: 10.6)
        capsule(centerX: x(47), centerY: midY + 5.3, width: 7.2 * unit, height: 2.2)
        capsule(centerX: x(47), centerY: midY - 5.3, width: 7.2 * unit, height: 2.2)
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
