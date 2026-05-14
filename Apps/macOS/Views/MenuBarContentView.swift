import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var coordinator: MacAppCoordinator
    @ObservedObject private var store: MacCarrierStore

    init(coordinator: MacAppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                coordinator.showMainWindow()
            } label: {
                Label(statusMenuTitle, systemImage: statusSystemImage)
            }

            if let warning = store.receiverHealthWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Button("打开 TypeCarrier") {
                coordinator.showMainWindow()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button("测试粘贴") {
                store.pasteTestText()
            }

            Button("重启接收器") {
                store.restartFromUserAction()
            }

            Button("导出诊断") {
                store.exportConnectionDiagnosticsToFinder()
            }

            if let exportError = store.lastDiagnosticExportErrorMessage {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Button("退出 TypeCarrier") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            store.refreshAccessibilityStatus()
        }
    }

    private var statusMenuTitle: String {
        if store.receiverHealthWarning != nil {
            return "接收器需要处理"
        }

        return store.connectionState.localizedDisplayText
    }

    private var statusSystemImage: String {
        if store.receiverHealthWarning != nil {
            return "exclamationmark.triangle.fill"
        }

        return store.connectionState.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
    }
}
