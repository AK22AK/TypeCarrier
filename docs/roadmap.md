# TypeCarrier 路线图

TypeCarrier 的长期方向是“用手机作为更自由的电脑输入入口”。当前源码为 0.1.3 Beta；已实现能力与后续候选分开列出，具体版本获取方式见 [发行说明](distribution.md)。

## 当前已实现

- iPhone 和 Android 向 Mac 当前光标发送文本，支持普通发送和发送后回车。
- macOS 菜单栏接收端、主窗口、辅助功能授权提示和本地粘贴测试。
- iPhone 使用 Multipeer Connectivity；Android 使用局域网 TCP，支持 NSD / mDNS 发现、配对码、手动连接和已配对目标重连。
- iOS 草稿、发送历史、重新发送、撤销/重做；Mac 接收历史。
- iOS 单条删除和清空列表、Mac 接收历史单条删除及各端记录数量上限；Mac 剪贴板恢复开关。
- 连接状态、自检、诊断导出，以及前后台恢复和重连逻辑。
- iOS TestFlight 测试渠道，以及 Android APK / macOS 签名公证 DMG 发布流程；GitHub 流程先产出草稿，需核对后公开。

以上描述代码能力，不代表所有设备、网络和目标应用均已验收。Multipeer 与 Android bridge 分别限制同一入口的 active sender；两入口可以并行，尚无跨入口统一的多设备调度。

## 待验证与候选改进

以下内容供后续任务讨论，不代表已确定的版本承诺或优先级。

- 连续输入：验证发送后继续编辑、切后台恢复、Mac 重启后重连和粘贴失败后的重试。
- 发送行为：手机以 Mac 接收留存为清空依据，粘贴失败或不可验证时可从 Mac 历史手动处理；传输失败或未获接收确认时保留文本。清空/保留/全选配置仍是 [发送行为设计](superpowers/specs/2026-05-31-sending-behavior-configuration-design.md) 的候选方案。
- 历史维护：搜索、多选删除、保留期限及分类型上限尚未完成；当前 iOS 草稿和发送历史共享默认 200 条上限，新增草稿最多 99 条。见 [历史保留设计](superpowers/specs/2026-05-31-history-retention-policy-design.md)。
- 自检：已有排查入口，权限可判断范围、失败解释与跨端状态还需持续核对。见 [连接与权限自检设计](superpowers/specs/2026-05-31-connection-permission-self-check-design.md)。
- 快捷键：评估 Mac 全局唤起快捷键自定义和 iOS 外接键盘操作。
- 接收方式：评估仅复制到剪贴板或确认后粘贴；当前自动粘贴仍是主路径。

## 后续方向

- [多设备管理](multi-device-management-plan.md)：目标选择、多 sender 并发及跨入口优先级与队列。
- [手机触控板](superpowers/specs/2026-05-31-touchpad-mode-design.md)：先评估 iOS 到 Mac 的移动、点击和滚动。
- Windows receiver 与 TV / 盒子输入可行性探索。
- 正式 App Store / Mac App Store 分发及其他官方下载渠道。

云账号、互联网中转、AI 转写和复杂剪贴板管理不属于当前核心范围。
