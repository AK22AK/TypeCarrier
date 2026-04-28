import SwiftUI
import TypeCarrierCore

struct ComposerView: View {
    @StateObject private var store = ComposerStore()
    @State private var showsDiagnostics = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                editor
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .task {
            store.start()
        }
        .sheet(isPresented: $showsDiagnostics) {
            ConnectionDiagnosticsSheet(store: store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text("TypeCarrier")
                    .font(.title2.weight(.semibold))
                Text(store.connectionState.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showsDiagnostics = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.medium))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Connection diagnostics")
        }
    }

    private var editor: some View {
        TextEditor(text: $store.text)
            .font(.system(.title3, design: .rounded))
            .scrollContentBackground(.hidden)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("Type or dictate here")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 26)
                        .allowsHitTesting(false)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                statusChip

                Button {
                    store.send()
                } label: {
                    Label(store.sendButtonText, systemImage: sendButtonSystemImage)
                        .font(.headline)
                        .frame(minWidth: 104, minHeight: footerControlHeight)
                }
                .buttonStyle(.glassProminent)
                .disabled(!store.canSend)
            }
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if store.canRestartConnection {
            Button {
                store.restartConnection()
            } label: {
                statusChipContent(showsRetryIcon: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry connection")
        } else {
            statusChipContent(showsRetryIcon: false)
        }
    }

    private func statusChipContent(showsRetryIcon: Bool) -> some View {
        HStack(spacing: 8) {
            if showsRetryIcon {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            } else {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
            }

            Text(store.connectionStatusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: footerControlHeight, alignment: .leading)
        .glassEffect(.regular, in: .capsule)
    }

    private var footerControlHeight: CGFloat {
        52
    }

    private var connectionStatusColor: Color {
        switch store.connectionStatus {
        case .connected:
            .green
        case .connecting:
            .orange
        case .searching, .disconnected:
            .secondary
        }
    }

    private var sendButtonSystemImage: String {
        switch store.sendState {
        case .sent:
            "checkmark"
        default:
            "paperplane.fill"
        }
    }
}

private struct ConnectionDiagnosticsSheet: View {
    @ObservedObject var store: ComposerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    diagnosticRow("Role", store.diagnostics.role)
                    diagnosticRow("Local Peer", store.diagnostics.localPeerName)
                    diagnosticRow("Service", store.diagnostics.serviceType)
                    diagnosticRow("State", store.diagnostics.connectionState.displayText)
                    diagnosticRow("Discovered", store.diagnostics.discoveredPeersText)
                    diagnosticRow("Invited", store.diagnostics.invitedPeersText)
                    diagnosticRow("Connected", store.diagnostics.connectedPeersText)

                    if let error = store.diagnostics.lastErrorMessage {
                        diagnosticRow("Last Error", error)
                    }
                }

                Section("Recent Events") {
                    ForEach(Array(store.diagnostics.events.suffix(20).reversed())) { event in
                        DiagnosticEventRow(event: event)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct DiagnosticEventRow: View {
    let event: CarrierDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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

            if let peerName = event.peerName {
                Text(peerName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }
}
#Preview {
    ComposerView()
}
