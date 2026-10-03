# TypeCarrier 路线图

TypeCarrier 的长期方向是“用手机作为更自由的电脑输入入口”。当前源码为 0.1.3 Beta；已实现能力与后续候选分开列出，当前源码可包含尚未发布的改动，具体版本获取方式见 [发行说明](distribution.md)。

## 当前已实现

- iPhone 和 Android 向 Mac 当前光标发送文本，支持普通发送和发送后回车。
- macOS 菜单栏接收端、主窗口、辅助功能授权提示和本地粘贴测试。
- iPhone 使用 Multipeer Connectivity；Android 使用局域网 TCP，支持 NSD / mDNS 发现、配对码、手动连接和已配对目标重连。
- iOS 草稿、发送历史、重新发送、撤销/重做；Mac 接收历史。
- iOS 草稿与发送历史独立存储和清空；草稿最多新增到 99 条，不自动淘汰；发送历史按条数或时间保留。Mac 接收历史单条删除及默认数量上限；Mac 剪贴板恢复开关。
- 连接状态、自检、诊断导出，以及前后台恢复和重连逻辑。
- 手机多 Mac 连接与单目标发送；Mac 多手机接收、稳定来源身份和统一 FIFO 粘贴。见 [多设备模型](multi-device-management-plan.md)。
- iOS TestFlight 测试渠道，以及 Android APK / macOS 签名公证 DMG 发布流程；GitHub 流程先产出草稿，需核对后公开。

以上描述代码能力，不代表所有设备、网络和目标应用均已验收。多设备能力已在源码落地，仍需多台真机混合发送、断线和目标应用兼容性验证。

## 待验证与候选改进

以下内容供后续任务讨论，不代表已确定的版本承诺或优先级。

- 连续输入：验证发送后继续编辑、切后台恢复、Mac 重启后重连和粘贴失败后的重试。
- 发送行为：手机以 Mac 接收留存为清空依据，粘贴失败或不可验证时可从 Mac 历史手动处理；传输失败或未获接收确认时保留文本。清空/保留/全选配置仍是 [发送行为设计](superpowers/specs/2026-05-31-sending-behavior-configuration-design.md) 的候选方案。
- 历史维护：iOS 已支持条数与时间互斥的保留策略；搜索、多选删除及 Mac 保留策略配置仍未实现。见 [历史保留设计](superpowers/specs/2026-05-31-history-retention-policy-design.md)。
- 自检：已有排查入口，权限可判断范围、失败解释与跨端状态还需持续核对。见 [连接与权限自检设计](superpowers/specs/2026-05-31-connection-permission-self-check-design.md)。
- 快捷键：评估 Mac 全局唤起快捷键自定义和 iOS 外接键盘操作。
- 接收方式：评估仅复制到剪贴板或确认后粘贴；当前自动粘贴仍是主路径。

## 后续方向

- 多设备连接与高频混合发送的真机验收；当前队列按到达顺序处理，不增加优先级。
- [手机触控板](superpowers/specs/2026-05-31-touchpad-mode-design.md)：先评估 iOS 到 Mac 的移动、点击和滚动。
- Windows receiver 与 TV / 盒子输入可行性探索。
- 正式 App Store / Mac App Store 分发及其他官方下载渠道。

云账号、互联网中转、AI 转写和复杂剪贴板管理不属于当前核心范围。
