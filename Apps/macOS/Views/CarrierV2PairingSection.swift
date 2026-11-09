import SwiftUI
import TypeCarrierCore

/// Pairing and paired-device management for the v2 connection.
struct CarrierV2PairingSection: View {
    @ObservedObject var receiver: CarrierV2Receiver

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配对设备").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            MacManagementGroup {
                VStack(alignment: .leading, spacing: 0) {
                    pairingRow.padding(.horizontal, 16).padding(.vertical, 14)
                    ForEach(receiver.pairedDevices) { device in
                        Divider().padding(.horizontal, 16)
                        pairedRow(device).padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pairingRow: some View {
        if let pending = receiver.pendingPairing {
            PairingRequestView(receiver: receiver, pending: pending)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加设备").font(.system(size: 13, weight: .medium))
                    Text("在手机上的 TypeCarrier 里选择这台电脑并点“配对”，这里会弹出请求，核对数字后点“允许”。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
        }
    }

    private func pairedRow(_ device: CarrierV2PairedDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.platform == .android ? "apps.iphone" : "iphone").font(.system(size: 15)).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.deviceName)
                Text(Self.lastSeenText(device)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("移除") { receiver.unpair(deviceID: device.deviceID) }.controlSize(.small)
        }
    }

    private static func lastSeenText(_ device: CarrierV2PairedDevice) -> String {
        guard let date = device.lastConnectedAt else { return "尚未连接" }
        return "上次连接：" + date.formatted(.relative(presentation: .named))
    }
}
