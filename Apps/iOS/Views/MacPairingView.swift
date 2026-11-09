import SwiftUI
import TypeCarrierCore

/// Lists paired Macs and Macs nearby that can be paired, and runs the pairing code comparison.
struct MacPairingView: View {
    @ObservedObject var client: CarrierV2Client

    var body: some View {
        List {
            if let pairing = client.pairing {
                Section {
                    pairingStatus(pairing)
                }
            }

            Section {
                if client.availableReceivers.isEmpty, !client.pairedReceivers.isEmpty {
                    // Paired Macs are listed below, so an empty list here is the expected state.
                    Text("附近没有其他可配对的设备").foregroundStyle(.secondary)
                } else if client.availableReceivers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在查找附近的设备…").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(client.availableReceivers) { receiver in
                        Button {
                            client.pair(with: receiver)
                        } label: {
                            HStack {
                                Label(receiver.name, systemImage: "desktopcomputer")
                                Spacer()
                                Text("配对").foregroundStyle(.tint)
                            }
                        }
                        .disabled(client.pairing.map(Self.isInProgress) ?? false)
                    }
                }
            } header: {
                Text("附近的设备")
            } footer: {
                Text("确保设备上的 TypeCarrier 已打开。点“配对”后，设备上会弹出请求，核对数字后点“允许”。")
            }

            if !client.pairedReceivers.isEmpty {
                Section("已配对") {
                    ForEach(client.pairedReceivers) { device in
                        HStack {
                            Label(device.deviceName, systemImage: "desktopcomputer")
                            Spacer()
                            Text(client.connectedPeers.contains { $0.id == CarrierV2Client.peerID(forDeviceID: device.deviceID) } ? "已连接" : "未连接")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("移除", role: .destructive) {
                                client.unpair(deviceID: device.deviceID)
                            }
                        }
                    }
                }
            }
        }
        .softTopScrollEdge()
        .navigationTitle("设备")
        .navigationBarTitleDisplayMode(.inline)
        // Keep searching while the list is open, and search again if the last search timed out.
        .onAppear { client.beginSearchHold() }
        .onDisappear {
            client.endSearchHold()
            if case .failed = client.pairing { client.dismissPairingResult() }
        }
    }

    @ViewBuilder
    private func pairingStatus(_ pairing: CarrierV2PairingState) -> some View {
        switch pairing {
        case .connecting(let name):
            HStack(spacing: 10) {
                ProgressView()
                Text("正在连接 \(name)…")
                Spacer()
                Button("取消") { client.cancelPairing() }.buttonStyle(.borderless)
            }
        case .comparing(let code, let name):
            VStack(alignment: .leading, spacing: 12) {
                Text("在 \(name) 上核对这个数字").font(.headline)
                Text(code)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                Text("设备上显示的数字一致时，在设备上点“允许”完成配对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("取消") { client.cancelPairing() }.buttonStyle(.borderless)
            }
            .padding(.vertical, 6)
        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(message)
                Spacer()
                Button("好") { client.dismissPairingResult() }.buttonStyle(.borderless)
            }
        }
    }

    private static func isInProgress(_ pairing: CarrierV2PairingState) -> Bool {
        if case .failed = pairing { return false }
        return true
    }
}
