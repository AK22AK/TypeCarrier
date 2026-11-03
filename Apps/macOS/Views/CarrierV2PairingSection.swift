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
            VStack(alignment: .leading, spacing: 12) {
                Text("核对 \(pending.deviceName) 上显示的数字").font(.system(size: 13, weight: .medium))
                Text(Self.spaced(pending.code))
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text("两边数字一致才点“一致”。不一致说明连接可能被他人拦截，请点“不一致”。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("一致") { receiver.confirmPendingPairing() }
                        .keyboardShortcut(.defaultAction)
                    Button("不一致") { receiver.rejectPendingPairing() }
                }
            }
        } else if receiver.isPairingOpen {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("等待手机配对").font(.system(size: 13, weight: .medium))
                    Text("在手机上的 TypeCarrier 里选择这台 Mac。2 分钟内有效。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("取消") { receiver.closePairing() }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加设备").font(.system(size: 13, weight: .medium))
                    Text("首次连接时需要在两边核对一个 6 位数字，之后自动连接。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("开始配对") { receiver.openPairing() }
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

    private static func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }

    private static func lastSeenText(_ device: CarrierV2PairedDevice) -> String {
        guard let date = device.lastConnectedAt else { return "尚未连接" }
        return "上次连接：" + date.formatted(.relative(presentation: .named))
    }
}
