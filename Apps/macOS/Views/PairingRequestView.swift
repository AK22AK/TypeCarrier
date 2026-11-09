import SwiftUI

/// A phone's pairing request: the code both screens show, and allow or reject.
struct PairingRequestView: View {
    @ObservedObject var receiver: CarrierV2Receiver
    let pending: CarrierV2Receiver.PendingPairing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(pending.deviceName) 请求配对").font(.system(size: 15, weight: .semibold))
            Text(pending.code)
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .tracking(6)
                .textSelection(.enabled)
                .accessibilityLabel(pending.code.map(String.init).joined(separator: " "))
            Text("确认手机上显示的也是这 4 位数字再点“允许”。数字不同说明请求可能来自别的设备，请点“拒绝”。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("拒绝") { receiver.rejectPendingPairing() }
                    .keyboardShortcut(.cancelAction)
                Button("允许") { receiver.confirmPendingPairing() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
