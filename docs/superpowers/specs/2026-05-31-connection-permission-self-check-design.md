# TypeCarrier 连接与权限自检设计

状态：后续设计。当前版本已经有连接状态、诊断日志和部分权限提示；本文用于规范排查入口和排查顺序。

## 目标

- 给用户一个“为什么不能用”的明确入口。
- 把连接、权限、当前焦点、active sender、最近失败原因串成可执行的排查顺序。
- 让诊断导出服务于排查，而不是变成普通数据备份功能。

## 非目标

- 不做自动修复所有系统权限问题；系统权限仍需要用户在系统设置中确认。
- 不做跨公网连接诊断。
- 不做复杂网络抓包或专业日志分析 UI。
- 不把用户历史文本默认打包进诊断导出。

## 自检项目

### 手机端

- 本机角色和设备名。
- 是否正在搜索 Mac receiver。
- 是否发现 Mac receiver。
- 是否已连接 Mac receiver。
- 最近一次发送状态和 Mac 回执。
- iOS Local Network 权限状态，如果系统 API 可用。
- 最近一次连接失败原因和建议动作。

### Mac 端

- Mac receiver 是否正在运行并 advertising。
- 是否已授予 Accessibility 权限。
- 是否有已连接 sender。
- 当前是否存在 active sender；多设备规划落地前，一个 receiver 同一时间只服务一个 sender。
- 最近一次接收、剪贴板写入、Command-V、粘贴验证或失败原因。
- 最近一次诊断日志导出位置。

### 跨端提示

- 手机搜不到 Mac：优先检查两端是否在同一局域网、Mac receiver 是否运行、Local Network 权限。
- 能连接但不能输入：优先检查 Mac Accessibility、当前焦点、目标 App 是否接受模拟粘贴。
- 显示已接收但用户没看到文本：区分“已收到 payload”“已复制到剪贴板”“已尝试粘贴”“已验证插入”。
- 第二台设备无法连接：在多设备实现前，提示当前 1:1 receiver 约束。

## UI 建议

- iOS 保留当前诊断页，但顶部增加自检摘要：可用、需要处理、不可判断。
- Mac 主窗口诊断区域增加同样的自检摘要。
- 每个失败项只给一个下一步动作，避免用户被日志淹没。
- 诊断导出仍放在自检页底部，作为“需要反馈给开发者”时的操作。

## 数据模型建议

- 保留底层 `CarrierDiagnostics` 作为事件和状态来源。
- 新增一个轻量 `SelfCheckFinding` 派生模型，用于 UI 展示：
  - `severity`: ok / warning / blocking / unknown
  - `title`
  - `detail`
  - `actionTitle`
  - `relatedEventName`
- 自检结果应由当前状态实时派生，不作为长期持久化数据。

## 诊断导出边界

- 默认导出连接事件、状态快照和错误原因。
- 默认不导出草稿、发送历史、接收历史全文。
- 如果未来需要“带文本内容的支持包”，必须是独立开关，并在导出前明确说明。

## 测试计划

### Core Tests

- 搜索超时能生成“检查 Mac receiver / 局域网”的 finding。
- busy receiver 能生成“当前已有 active sender”的 finding。
- Accessibility 缺失能生成阻断级 finding。
- 粘贴不可验证能生成“确认焦点或手动粘贴”的 finding。

### iOS Validation

- Mac 未启动时，自检页给出明确下一步。
- Mac busy 时，自检页说明当前 1:1 约束。
- 发送失败后，自检页显示最近失败原因。
- 诊断导出不包含历史文本全文。

### macOS Validation

- Accessibility 未授权时，自检摘要明确阻断自动粘贴。
- 已连接 sender 时，自检摘要显示可用。
- 目标输入框不可验证时，自检摘要把问题归到当前焦点或目标 App。
- 导出诊断后，Finder 能定位到导出文件。

## 建议拆分

1. 先定义 `SelfCheckFinding` 派生模型和 Core 测试。
2. 再把现有 iOS / macOS 诊断页顶部改成自检摘要。
3. 再补齐 Accessibility、busy receiver、搜索超时、粘贴失败的统一 finding。
4. 最后收紧诊断导出边界，确保默认不包含历史文本全文。
