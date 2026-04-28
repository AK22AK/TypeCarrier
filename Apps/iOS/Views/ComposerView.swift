import SwiftUI
import TypeCarrierCore

struct ComposerView: View {
    @StateObject private var store = ComposerStore()
    @FocusState private var isEditorFocused: Bool

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                Text(store.headerStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextField("Type or dictate here", text: $store.text, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .lineLimit(1...10)
                .submitLabel(.send)
                .focused($isEditorFocused)
                .onSubmit {
                    if store.canSend {
                        store.send()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture {
            isEditorFocused = true
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
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 16, height: 16)
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(store.canSend ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(minWidth: 96, minHeight: footerControlHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
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
                    .frame(width: 16, height: 16)
            } else {
                ConnectionStatusIndicator(status: store.connectionStatus)
                    .id(store.connectionStatus)
            }

            Text(store.connectionStatusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: footerControlHeight, maxHeight: footerControlHeight, alignment: .leading)
        .glassEffect(.regular, in: .capsule)
    }

    private var footerControlHeight: CGFloat {
        46
    }

}

private struct ConnectionStatusIndicator: View {
    let status: ComposerStore.ConnectionStatus
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            switch status {
            case .searching:
                Circle()
                    .stroke(Color.blue.opacity(isBreathing ? 0.18 : 0.45), lineWidth: 1.6)
                    .frame(width: isBreathing ? 16 : 9, height: isBreathing ? 16 : 9)
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 5, height: 5)
            case .connecting:
                Circle()
                    .fill(Color.orange.opacity(isBreathing ? 0.18 : 0.4))
                    .frame(width: isBreathing ? 16 : 10, height: isBreathing ? 16 : 10)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            case .disconnected:
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .animation(statusAnimation, value: isBreathing)
        .onAppear {
            isBreathing = status.isBreathing
        }
    }

    private var statusAnimation: Animation? {
        guard status.isBreathing else {
            return nil
        }

        return .easeInOut(duration: status == .searching ? 1.35 : 0.95)
            .repeatForever(autoreverses: true)
    }
}

private extension ComposerStore.ConnectionStatus {
    var isBreathing: Bool {
        self == .searching || self == .connecting
    }
}

#Preview {
    ComposerView()
}
