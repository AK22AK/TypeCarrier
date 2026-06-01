# TypeCarrier 手机触控板模式设计

状态：后续设计。本文记录未来实现方向，不代表当前版本已经支持手机触控板控制 Mac。

## 目标

- 在手机端提供一个触控板界面，让用户不碰 Mac 鼠标或触控板，也能把 Mac 光标移动到目标输入框并点击聚焦。
- 聚焦完成后，继续复用 TypeCarrier 现有文本发送和 Mac 自动粘贴能力。
- 第一版优先支持 iOS + Mac；协议和 Mac receiver 边界预留 Android + Mac sender。

## 非目标

- 第一版不做 Mac 屏幕画面回传，不把产品扩展成完整远程桌面。
- 第一版不承诺自动识别所有 App 的输入框；输入框辅助定位只作为后续增强。
- 第一版不绕过 macOS 锁屏、登录窗口、系统安全弹窗或受保护输入场景。
- 第一版不支持跨公网控制，只做本地网络或附近设备连接。

## 用户流程

1. 用户在 Mac 上运行 TypeCarrier Mac，并授予 Accessibility 权限。
2. 手机连接到 Mac receiver。
3. 用户进入手机端的触控板模式。
4. 用户在手机屏幕上滑动来移动 Mac 光标，轻点来点击输入框，双指滑动来滚动。
5. 输入框获得焦点后，用户回到文本输入模式并发送文本。
6. Mac 端收到文本后继续走现有剪贴板写入和模拟粘贴流程。

## 架构

### 手机端

- 新增 touchpad UI，识别滑动、轻点、长按、双指滚动等手势。
- 将手势转换成相对控制指令，而不是发送绝对屏幕坐标。
- iOS 第一版继续使用 Multipeer Connectivity。
- Android 后续版本使用局域网 TCP 或 WebSocket，发现层可用 mDNS / DNS-SD。

### Mac 端

- 新增 remote pointer controller，接收触控板指令并转换成 macOS 输入事件。
- 继续复用现有 Accessibility 权限检查。
- 使用 Core Graphics 事件注入鼠标移动、点击和滚动。
- 保持文本接收和 PasteInjector 独立，避免把鼠标控制逻辑混进粘贴流程。

### Core / 协议

触控板指令应作为独立 envelope kind 或 payload 类型，不复用文本 payload。

建议的最小命令集：

- `pointerMove(dx, dy, sequence, timestamp)`
- `pointerClick(button, phase)`
- `pointerScroll(dx, dy)`

后续可扩展：

- `pointerDrag(button, phase, dx, dy)`
- `pointerSensitivity(value)`
- `pointerCancel(reason)`

协议应保持平台中立，让 iOS 和 Android sender 都能产生同一类指令，Mac receiver 共用同一个执行层。

## 权限和安全

- Mac 端必须明确提示 Accessibility 权限用途：用于根据已配对手机的指令移动光标、点击和滚动。
- 未授权时，手机端应显示“Mac 未授权远程指针控制”，并禁用触控板模式。
- 控制指令只接受来自当前已连接、已信任或当前 active sender 的设备。
- Android + Mac 路径必须先完成配对和信任机制；不能允许同一局域网内任意设备直接发送控制事件。

## 可用性细节

- 触控板使用相对位移，避免手机端必须知道 Mac 屏幕分辨率和多显示器布局。
- Mac 端做灵敏度曲线和位移限幅，减少网络抖动导致的跳动。
- 点击和移动要有序处理；乱序或过期指令应丢弃。
- 第一版支持单击、右键和滚动即可；拖拽、多指手势和输入框辅助定位放到后续。
- 手机端应保留一个明显入口回到文本输入，避免触控板模式成为额外主流程。

## Android + Mac 可行性

Android + Mac 可行，但不是 Apple Multipeer 的直接复用。

- Android sender 负责触控板 UI 和协议编码。
- Mac receiver 继续负责权限、配对、接收和事件注入。
- 连接层建议走局域网 TCP 或 WebSocket。
- 发现层建议使用 mDNS / DNS-SD；Android 可用系统 NSD 能力。
- 第一版 Android 应在真机上验证，模拟器无法可靠覆盖局域网发现、热点和真实触控手感。

## 测试计划

### Core Tests

- pointer command 可以编码和解码。
- 乱序 sequence 不会覆盖较新的移动指令。
- 未知 command type 不影响文本 payload 的兼容性。

### macOS Validation

- 未授予 Accessibility 时，Mac 端拒绝执行指针指令并返回明确状态。
- 授权后，手机滑动能移动 Mac 光标。
- 手机轻点能让 TextEdit 或浏览器输入框获得焦点。
- 手机双指滚动能滚动前台窗口。
- 触控板模式不影响现有文本发送和粘贴回执。

### iOS Validation

- 触控板模式下滑动、轻点、双指滚动不会误触发送文本。
- 网络断开时触控板 UI 明确禁用。
- 回到文本输入模式后可以继续发送文本到刚刚聚焦的输入框。

### Android Validation

- Android 真机能发现 Mac receiver 或通过手动地址连接。
- Android 触控板指令和 iOS 指令走同一 Mac receiver 执行层。
- 配对前发送控制指令会被 Mac 拒绝。

## 建议拆分

1. 先扩展 Core 协议，增加 pointer command 的编码、解码和兼容性测试。
2. 再实现 macOS remote pointer controller，并用本地调试入口验证移动、点击和滚动。
3. 再做 iOS 触控板 UI，接入现有连接状态和权限状态。
4. 最后再启动 Android sender 版本，复用协议并新增 TCP / mDNS 连接层。
