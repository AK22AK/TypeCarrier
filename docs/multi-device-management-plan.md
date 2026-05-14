# TypeCarrier 多设备管理后续计划

状态：后续路线图。0.1 Beta 仍按 1:1 receiver 约束发布，本计划不代表当前版本已经支持多设备连接。

## 目标

- 将 TypeCarrier 从当前 1:1 receiver 约束升级为局域网多设备模型。
- iOS 端展示可用 Mac receiver 列表，并要求发送前选择目标 Mac。
- macOS 端允许多个 iOS sender 同时连接，收到任意 sender 文本后继续走现有接收、粘贴、历史和回执流程。
- 第一版不做配对、可信设备列表、二维码或跨网络中转。

## 范围

### Core

- 扩展 `CarrierPeer`，加入稳定 device id、display name、role、connection status、last seen time。
- 在 Multipeer `discoveryInfo` 中广播本地持久化 device id 和 role，避免同名设备混淆。
- 将 `MultipeerCarrierService` 从单 peer 状态改为维护多个 peers。
- receiver 删除 `advertiser.invitation.rejectedBusy` 单活保护，改为接受多个 sender 进入同一个 `MCSession`。
- sender 增加指定目标发送接口，例如 `send(_:to peerID:)`，不再默认广播给全部 connected peers。

### iOS

- Composer header 或连接区域展示 Mac receiver 列表和当前选中目标。
- 未选择目标、目标未连接、目标断开时禁用 Send，并给出明确提示。
- 默认恢复最近一次成功发送的 Mac；没有历史目标时要求用户手动选择。

### macOS

- 菜单栏显示已连接 sender 数量和最近发送来源。
- 主窗口 diagnostics 显示 connected sender 列表。
- 接收历史记录保留来源设备名/device id，便于区分真机和模拟器。

### Docs

- 更新 `docs/v0-prototype-notes.md`，移除“一个 Mac receiver 同一时间只服务一个 iOS sender”的当前限制描述。
- 更新 `docs/mvp-plan.md`，将“多设备连接与切换管理”从候选项移动到正在实现/已规划能力。

## 测试计划

### Core Tests

- receiver 已连接 `iPhone 17 Pro` 后，再收到 `iPhone` invitation，应接受第二个 peer。
- sender 发现两台 Mac 后，两台都出现在 peer 列表中。
- sender 指定 `Mac A` 发送时，只向 `Mac A` 发送，不发给 `Mac B`。
- 两台同名设备通过 device id 区分，不被合并。

### iOS Validation

- 无目标 Mac 时 Send 禁用。
- 多台 Mac 在线时可切换目标。
- 目标断开后 UI 明确显示该目标不可发送。

### macOS Validation

- 真机 iPhone 和 simulator 同时运行时，Mac 不再拒绝第二个 sender。
- 两台 iOS 依次发送，Mac 都能接收并在历史里显示来源。
- 导出的诊断日志能看到多个 connected peers 和每条 receive 的 peer。

## 假设

- 第一版不做安全配对；局域网内发现即显示。
- Mac 收到多台 iOS 的文本时按到达顺序处理，不增加确认收件箱。
- iOS 可以同时连接多个 Mac，但一次 Send 只发给一个明确选中的 Mac。
- 多设备 UI 优先轻量，不新增复杂设置页。

## 建议拆分

1. 先改 Core 的 peer identity、discovery metadata 和多 peer 状态模型，并补齐单元测试。
2. 再改 macOS receiver 的多 sender 接受、来源记录和 diagnostics。
3. 最后改 iOS 的 receiver 选择 UI、发送禁用条件和最近目标恢复。
4. 完成后再更新 v0/MVP 文档，避免计划未落地时文档提前宣称能力已支持。
