import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: MacCarrierStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TypeCarrier")
                .font(.headline)

            Label(store.connectionState.displayText, systemImage: store.connectionState.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")

            Label(
                store.accessibilityTrusted ? "Accessibility enabled" : "Accessibility required",
                systemImage: store.accessibilityTrusted ? "lock.open.fill" : "lock.fill"
            )

            Divider()

            Button("Open Debug Window") {
                openWindow(id: "debug")
            }

            Button("Test Paste") {
                store.pasteTestText()
            }

            if !store.accessibilityTrusted {
                Button("Request Accessibility") {
                    store.requestAccessibilityAccess()
                }
            }

            Button("Restart Receiver") {
                store.restart()
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
