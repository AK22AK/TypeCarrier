import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var coordinator: MacAppCoordinator
    @ObservedObject private var store: MacCarrierStore

    init(coordinator: MacAppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    private var presentation: ReceiverManagementPresentation {
        .init(summary: store.receiverStatusSummary, accessibilityTrusted: store.accessibilityTrusted)
    }

    var body: some View {
        Button(presentation.menuTitle) {}.disabled(true)
        Divider()
        Button("打开接收列表") { coordinator.showMainWindow(page: .received) }
            .keyboardShortcut("t", modifiers: [.command, .option])
        Button("连接管理…") { coordinator.showMainWindow(page: .connections) }
        Button("接收设置…") { coordinator.showMainWindow(page: .receiving) }
        if presentation.needsAttention {
            Button("处理问题…") { coordinator.showMainWindow(page: .diagnostics) }
        }
        Divider()
        Button("退出 TypeCarrier") { NSApplication.shared.terminate(nil) }
        .onAppear { store.refreshAccessibilityStatus() }
    }
}
