import SwiftUI

struct DebugWindowView: View {
    @ObservedObject var store: MacCarrierStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                debugRow("Connection", store.connectionState.displayText)
                debugRow("Accessibility", store.accessibilityTrusted ? "Trusted" : "Missing")
                debugRow("Paste", store.lastPasteResult.status)
                debugRow("Received", store.lastPayloadPreview)
            }

            Text("Last Payload")
                .font(.headline)

            TextEditor(text: .constant(store.lastPayloadText))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

            HStack {
                Button("Test Paste") {
                    store.pasteTestText()
                }

                Button("Request Accessibility") {
                    store.requestAccessibilityAccess()
                }

                Button("Restart Receiver") {
                    store.restart()
                }
            }
            .buttonStyle(.glass)

            Spacer()
        }
        .padding(24)
        .onAppear {
            store.refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TypeCarrier Debug")
                    .font(.title2.weight(.semibold))
                Text("Receiver status and paste diagnostics")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func debugRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
