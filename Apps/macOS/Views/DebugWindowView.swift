import SwiftUI
import TypeCarrierCore

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
                debugRow("Local Peer", store.carrierService.diagnostics.localPeerName)
                debugRow("Service", store.carrierService.diagnostics.serviceType)
                debugRow("Discovered", store.carrierService.diagnostics.discoveredPeersText)
                debugRow("Invited", store.carrierService.diagnostics.invitedPeersText)
                debugRow("Connected", store.carrierService.diagnostics.connectedPeersText)

                if let error = store.carrierService.diagnostics.lastErrorMessage {
                    debugRow("Last Error", error)
                }
            }

            Text("Recent Events")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.carrierService.diagnostics.events.suffix(16).reversed())) { event in
                        DiagnosticEventRow(event: event)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 100, maxHeight: 180)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

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

private struct DiagnosticEventRow: View {
    let event: CarrierDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(event.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let peerName = event.peerName {
                    Text(peerName)
                }

                Text(event.connectionState.displayText)

                if !event.connectedPeers.isEmpty {
                    Text("connected: \(event.connectedPeers.joined(separator: ", "))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
