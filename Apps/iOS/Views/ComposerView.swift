import SwiftUI
import TypeCarrierCore

struct ComposerView: View {
    @StateObject private var store = ComposerStore()

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
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(minWidth: 104)
                }
                .buttonStyle(.glassProminent)
                .disabled(!store.canSend)
            }
        }
    }

    private var statusChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(store.sendState.displayText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .capsule)
    }

    private var statusColor: Color {
        switch store.sendState {
        case .idle:
            store.connectionState.isConnected ? .green : .secondary
        case .sending:
            .orange
        case .sent:
            .green
        case .failed:
            .red
        }
    }
}

#Preview {
    ComposerView()
}
