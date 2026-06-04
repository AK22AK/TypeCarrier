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

## 基础体验能力

目标：补齐日常反复使用时最容易影响效率和信心的基础能力，同时避免把 TypeCarrier 做成剪贴板管理器或远程控制套件。

- 搜索与过滤：搜索草稿、发送历史和 Mac 接收历史；第一版只做本地文本搜索和少量状态过滤。
- 快捷键自定义：允许用户配置 Mac 全局唤起快捷键，并规划 iOS 外接键盘的发送、清空、保存草稿快捷键。
- 发送行为配置：整理发送后清空/保留、失败后保留、Mac 自动粘贴/仅复制到剪贴板、确认后粘贴等核心手感。专项设计见 [发送行为配置设计](superpowers/specs/2026-05-31-sending-behavior-configuration-design.md)。
- 历史清理与保留策略：只做批量删除、保留期限、条目上限等轻量维护能力，不做收藏、置顶、重命名等剪贴板管理器式功能。专项设计见 [历史清理与保留策略设计](superpowers/specs/2026-05-31-history-retention-policy-design.md)。
- 连接与权限自检：提供“为什么不能用”的排查入口，串起 Mac 是否在线、系统权限、局域网发现、active sender、最近失败原因和诊断导出。专项设计见 [连接与权限自检设计](superpowers/specs/2026-05-31-connection-permission-self-check-design.md)。
- 导入、导出与备份暂不作为近期独立产品方向；当前只保留诊断日志导出，未来只有在迁移设备、长期归档或排查支持需要明确后再重新评估。

## 多设备管理

目标：从当前 1:1 receiver 约束升级为局域网多设备模型。

- iOS 端展示可用 Mac receiver 列表，并允许选择发送目标。
- macOS 端允许多个 iOS sender 同时连接。
- 诊断日志和历史记录保留来源设备信息。
- 多设备专项设计见 [多设备管理后续计划](multi-device-management-plan.md)。

## 平台扩展

目标：从 Apple 双端验证扩展到更通用的手机输入中继。

- 手机触控板模式：在手机端模拟触控板，向 Mac 发送鼠标移动、点击、滚动等控制指令，用于远程把 Mac 光标定位到输入框；第一版优先 iOS + Mac，后续再评估 Android + Mac。专项设计见 [手机触控板模式设计](superpowers/specs/2026-05-31-touchpad-mode-design.md)。
- Android sender MVP：支持 Android 手机在同一局域网或热点下向 Mac 当前光标发送文本；第一版采用原生 Android UI、固定 TCP 端口 + 手动地址连接作为可靠路径，NSD / mDNS 发现作为后续增强，协议使用 JSON framing，并保持 1:1 active sender 约束。专项设计见 [Android Sender MVP 设计](superpowers/specs/2026-06-01-android-sender-mvp-design.md)。
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
- 搜索是否只覆盖 TypeCarrier 自己保存的草稿/历史，还是要支持系统剪贴板内容；当前倾向只覆盖 TypeCarrier 记录。
- 快捷键自定义是否需要跨 iOS 和 macOS 同步；当前倾向两端独立保存。
- 多设备场景下，第二台设备发起连接时应自动排队、提示占用，还是由 Mac 端主动切换当前 sender？
- 手机触控板模式是否只做相对位移和点击，还是也要支持拖拽、惯性滚动、多显示器边界提示和输入框辅助定位？
- TV / 盒子输入场景中，哪些设备和 App 能通过系统输入法或蓝牙键盘接收文本，哪些会因为自绘输入框、厂商限制或平台封闭性不可支持？
