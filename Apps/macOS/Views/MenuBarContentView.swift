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

            Label(store.connectionState.displayText, systemImage: store.connectionState.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")

            if let warning = store.receiverHealthWarning {
                Label("Receiver needs attention", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Label(
                store.accessibilityTrusted ? "Accessibility enabled" : "Accessibility required",
                systemImage: store.accessibilityTrusted ? "lock.open.fill" : "lock.fill"
            )

            Divider()

            Button("Open TypeCarrier") {
                coordinator.showMainWindow()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button("Test Paste") {
                store.pasteTestText()
            }

            if !store.accessibilityTrusted {
                Button("Request Accessibility") {
                    store.requestAccessibilityAccess()
                }
            }

            Button("Restart Receiver") {
                store.restartFromUserAction()
            }

            Button("Export Diagnostics") {
                store.exportConnectionDiagnosticsToFinder()
            }

            if let exportError = store.lastDiagnosticExportErrorMessage {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Button("Quit TypeCarrier") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            store.refreshAccessibilityStatus()
        }
    }
}
