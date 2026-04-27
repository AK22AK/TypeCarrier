# 技术说明

## MVP 推荐架构

TypeCarrier 从两个原生 app 开始：

- iOS app：SwiftUI 文本输入界面。
- macOS app：菜单栏接收端，使用 SwiftUI + 必要的 AppKit 集成。

第一版传输应优先使用 Apple 设备之间的本地通信。最合适的起点是 `MultipeerConnectivity`，因为它面向附近 Apple 设备，可以通过 Wi-Fi、peer-to-peer Wi-Fi 和蓝牙工作。

## 数据流

1. iOS app 持有一个可编辑文本缓冲区。
2. 用户用任意 iOS 键盘输入或听写。
3. 用户点击发送。
4. iOS app 把小文本 payload 发送给已连接的 Mac。
5. Mac app 接收 payload。
6. Mac app 临时把文本写入 `NSPasteboard`。
7. Mac app 模拟 `Command + V`，粘贴到当前聚焦 app。
8. Mac app 尽量恢复原剪贴板内容。
9. iOS app 显示成功并清空输入区。

## macOS 权限

自动粘贴到当前聚焦输入框通常需要 Accessibility 权限，因为 Mac app 需要合成键盘事件。

预期权限：

- Accessibility：用于发送键盘事件。

可能使用的 API：

- `NSPasteboard`：写入和恢复剪贴板。
- `CGEvent` / `CGEventPost`：模拟 `Command + V`。

## 配对

候选配对方式：

- Mac 显示二维码，iPhone 扫码。
- 附近设备浏览 + 手动选择。
- 手动输入配对码作为 fallback。

第一版原型可以只做附近发现。分享给更多用户前，二维码或配对码会更稳妥。

## 传输选项

### 本地网络 / Nearby First

优点：

- 不需要服务器。
- 不需要账号。
- 隐私更好。
- 成本更低。
- 符合主要使用场景。

缺点：

- 受限 Wi-Fi 网络可能失败。
- 需要本地网络权限。
- 企业或公共网络中的设备发现可能不稳定。

### 后续互联网中转

候选方案：

- CloudKit。
- WebSocket relay。
- Firebase / Supabase / Pusher 这类实时服务。

优点：

- 设备不在同一网络或不在附近时仍可工作。
- 更容易提供跨网络的持久配对。

缺点：

- 需要认证或更强配对安全。
- 运维复杂度更高。
- 引入隐私和数据处理问题。
- 对第一版自用原型不是必要条件。

## 风险

- 某些 Mac 输入框可能拒绝粘贴或键盘事件注入。
- 安全输入框和密码框不应作为目标。
- 富文本或 owner-provided pasteboard data 可能无法完整恢复。
- Multipeer 在某些网络下发现不稳定。
- iOS 无法程序化控制第三方输入法听写，用户需要在文本框里正常使用输入法。

## 安全与隐私

MVP 阶段：

- 保持本地传输。
- 只在已连接设备之间发送纯文本。
- 不做云存储。
- 默认不保留历史。

产品化前：

- 增加配对信任机制。
- 明确传输层加密预期。
- 历史记录只做 opt-in。
- 在 onboarding 中解释剪贴板处理方式。
