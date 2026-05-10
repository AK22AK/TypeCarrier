import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var coordinator: MacAppCoordinator

    private var store: MacCarrierStore {
        coordinator.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TypeCarrier")
                .font(.headline)

            Label(store.connectionState.localizedDisplayText, systemImage: store.connectionState.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")

            if let warning = store.receiverHealthWarning {
                Label("接收器需要处理", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Label(
                store.accessibilityTrusted ? "辅助功能已启用" : "需要辅助功能权限",
                systemImage: store.accessibilityTrusted ? "lock.open.fill" : "lock.fill"
            )

            Divider()

            Button("打开 TypeCarrier") {
                coordinator.showMainWindow()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button("测试粘贴") {
                store.pasteTestText()
            }

            if !store.accessibilityTrusted {
                Button("请求辅助功能权限") {
                    store.requestAccessibilityAccess()
                }
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
}
