# TypeCarrier 路线图

TypeCarrier 的长期方向是“用手机作为更自由的电脑输入入口”。0.1 Beta 先验证 iPhone 到 Mac 的本地输入闭环，后续再扩展设备、平台和分发形态。

## 0.1 Beta：当前版本

目标：提供一个可自用、可小范围测试的端到端闭环。

- iPhone 输入文本，发送到 Mac 当前光标所在位置。
- macOS 菜单栏接收端常驻运行。
- 基于 Multipeer Connectivity 在局域网内发现和传输。
- Mac 端通过剪贴板和模拟粘贴插入文本。
- 提供连接状态、接收状态和诊断入口。
- 当前按 1:1 receiver 约束发布：一个 Mac receiver 同一时间只应服务一个 iOS sender。

## 近期加固

目标：让 0.1 的核心场景更稳定、可解释、可排查。

- macOS Accessibility 授权引导和失败解释。
- 连接失败、接收失败、粘贴失败的诊断日志继续补齐。
- 发送后输入框清空、保留焦点、继续输入的体验保持稳定。
- Mac 端状态展示继续收敛，避免用户误判 receiver 是否可用。
- 发布文档和 GitHub Release 流程稳定下来。

## 多设备管理

目标：从当前 1:1 receiver 约束升级为局域网多设备模型。

- iOS 端展示可用 Mac receiver 列表，并允许选择发送目标。
- macOS 端允许多个 iOS sender 同时连接。
- 诊断日志和历史记录保留来源设备信息。
- 多设备专项设计见 [多设备管理后续计划](multi-device-management-plan.md)。

## 平台扩展

目标：从 Apple 双端验证扩展到更通用的手机输入中继。

- Android sender 探索。
- Windows receiver 探索。
- Android 到 Windows / Mac 的输入链路。
- TV / 盒子输入探索：研究手机向国产安卓盒子、Apple TV 等客厅设备输入文本的可行性；优先验证国产安卓盒子的第三方输入法路径，Apple TV + Android 手机先作为蓝牙键盘 / HID 兼容性穿刺，不承诺纯软件接收端。

## 分发路线

目标：先让源码和测试包可用，再逐步补正式分发。

- 0.1 Beta：GitHub prerelease，源码完整公开，macOS 提供 Apple Development / Personal Team 测试包。
- 后续 Beta：如果开通 Apple Developer Program，再提供 Developer ID notarized macOS 包。
- iOS 外部测试：需要 TestFlight 时再开通 Apple Developer Program。
- 正式版本：再评估 App Store / Mac App Store / 官网或 GitHub 下载的组合。

## 开放问题

- 发送后是否总是自动粘贴，还是 Mac app 也要支持“只接收到剪贴板”模式？
- Mac 剪贴板是否默认恢复？
- iOS 外接键盘是否需要快捷键发送？
- 多设备场景下，第二台设备发起连接时应自动排队、提示占用，还是由 Mac 端主动切换当前 sender？
- TV / 盒子输入场景中，哪些设备和 App 能通过系统输入法或蓝牙键盘接收文本，哪些会因为自绘输入框、厂商限制或平台封闭性不可支持？
