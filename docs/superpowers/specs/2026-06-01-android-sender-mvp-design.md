# TypeCarrier Android Sender MVP 设计

状态：MVP 验证中。本文记录 Android 最小可用版本的实现方向和真机验证过程中形成的约束。

## 目标

- 在用户忘带 iPhone 时，Android 手机也能把文本发送到 Mac 当前光标所在位置。
- 保持 TypeCarrier 的核心体验：手机端输入，Mac 端安静接收并自动粘贴。
- Android 第一版用于自用和侧载验证，不考虑 Play Store 上架、正式分发或付费策略。
- 在不破坏现有 iPhone -> Mac Multipeer 路径的前提下，给 Mac 增加 Android sender 入口。

## 非目标

- 不做 Android receiver。
- 不做 Windows receiver。
- 不做云同步、账号系统或互联网中转。
- 不做蓝牙 / BLE 作为第一版主传输。
- 不做 Android 与 iOS 的核心源码复用改造；第一版只做协议契约复用。
- 不做多台 sender 同时向同一台 Mac 发送；第一版保持 1:1 active sender 约束。
- 不做实时上屏、内置语音识别、触控板模式或复杂设备管理。

## 用户流程

1. 用户在 Mac 上运行 TypeCarrier Mac。
2. 用户在 Mac 端开启 Android bridge。
3. Mac 在局域网内广播 Android 可连接服务，并显示首次配对码。
4. Android app 打开后搜索同一局域网内的 TypeCarrier Mac。
5. 用户选择 Mac，并在首次连接时输入 Mac 显示的配对码。
6. 配对成功后，Android 进入文本输入界面。
7. 用户输入文本并点击发送。
8. Mac 接收文本，写入本地历史，执行现有粘贴流程，并把 receipt 返回给 Android。
9. 后续同一 Android 设备连接同一台 Mac 时使用已保存的信任凭据，不再要求反复输入配对码。

## 技术路线

### 传输选择

Android MVP 采用局域网优先路径：

- 发现层：Android 使用系统 NSD / mDNS 发现 Mac 广播的服务；真机热点验证阶段不把发现作为阻塞项。
- 连接层：Android 使用 TCP socket 连接 Mac；MVP 当前以固定端口 `17641` + 手动 Mac 地址作为可靠主路径。
- 协议层：复用现有 `CarrierEnvelope` / `CarrierPayload` / `CarrierDeliveryReceipt` JSON schema。
- framing：TCP 上使用 4-byte big-endian length prefix + UTF-8 JSON，避免粘包和半包问题。

不选 BLE 作为 MVP 主路径。BLE 会提前引入 GATT 角色、权限、配对、吞吐和后台能力差异，更适合作为后续 fallback transport 穿刺。

### Mac 端

- 保留现有 `MultipeerCarrierService`，继续服务 iPhone -> Mac 路径。
- 新增 Android bridge receiver，使用 `NWListener` 监听本地 TCP 端口。
- 新增 Bonjour service type，例如 `_typecarrier-json._tcp`，用于 Android NSD 发现；但 MVP 不依赖 Bonjour 发布来完成手动连接。
- 当 macOS 返回 `Network.NWError error -65555 - NoAuth` 时，Android bridge 不应因为 Bonjour 发布失败而停止手动 TCP 监听。
- 抽出 Mac 收到文本后的共用处理函数，供 Multipeer 和 Android bridge 共用：
  - 保存接收历史。
  - 刷新 Accessibility 状态。
  - 调用现有 `PasteInjector` 粘贴文本。
  - 记录诊断事件。
  - 返回 `CarrierDeliveryReceipt`。
- Android bridge 只接收来自当前 active sender 的文本。已有 active sender 时，新连接返回 busy 状态。

### Android 端

- 新增 `Apps/Android` 独立 Android 工程。
- 技术栈：Kotlin、Jetpack Compose、`androidx.compose.material3`、Coroutines、kotlinx.serialization。
- Android 工程不接入 XcodeGen；Apple 侧继续以 `project.yml` 管理。
- Android 包含以下边界清晰的模块：
  - protocol：Kotlin 版本的 envelope / payload / receipt models 和 JSON codec。
  - discovery：NSD 发现 TypeCarrier Mac。
  - transport：TCP 连接、framing、发送和 receipt 接收。
  - pairing：首次配对码校验和本地 trust token 保存。
  - store / viewmodel：连接状态、当前目标、文本发送状态和错误提示。
  - ui：Compose 界面，使用 Material 3 组件和 Android 交互规范。

## 配对和信任

配对码只用于首次授权，不作为每次连接凭据。

建议模型：

- Mac 端开启 Android bridge 后生成短期 6 位配对码。
- Android 首次连接时提交设备信息和配对码。
- 验证成功后，双方生成并保存高强度随机 trust token。
- Mac 保存可信 Android 设备的 `deviceId`、`deviceName`、`platform` 和 token 摘要。
- Android 保存可信 Mac 的 `macId`、`macName` 和 token。
- 后续连接使用 token proof 建立信任，不再输入配对码。
- Android 清数据、重装 app、Mac 删除可信设备或 token 校验失败时，需要重新配对。

MVP 安全边界是可信局域网 / 手机热点内自用，不承诺抵抗恶意局域网攻击。产品化前再评估 TLS、二维码配对、设备信任列表 UI 和 token 轮换。

## 1:1 Active Sender 策略

Android MVP 延续当前 TypeCarrier receiver 边界：一台 Mac 同一时间只服务一个 active sender。

规则：

- Mac 可以记住多台已配对 Android 设备。
- Mac 可以继续支持 iPhone Multipeer 路径。
- 同一时间只有一台 sender 可以处于 active 状态并发送文本。
- 如果已有 active sender，新 sender 连接时收到 busy 响应。
- Mac 端提供断开当前 sender、重新配对或清理可信设备的入口。

多 sender 同时发送、FIFO 粘贴队列、来源设备标记、跨 iPhone / Android 优先级和并发冲突策略，放入后续多设备 receiver 能力，不进入 Android MVP。

## UI 技术栈和规范

Android UI 采用 Android 官方 Kotlin + Jetpack Compose 路线，并使用 `androidx.compose.material3` 组件和 Material 3 设计规范。

这里的“官方 Android 路线”指非 WebView、非 Flutter、非 React Native；不表示使用传统 View/XML 或系统 widget。MVP 不采用 XML layout / View system 作为主 UI，除非后续实测发现 Compose 文本输入或输入法兼容性无法满足核心场景。

Android 视觉不复刻 iOS 细节，但保持同一产品心智。

第一屏直接是工具界面：

- 顶部：连接状态、当前 Mac 名称、刷新 / 重连入口。
- 主体：大文本输入框，打开后优先聚焦。
- 底部：发送、清空、保存草稿或复制等少量高频操作。
- 次级入口：设备列表、首次配对码输入、诊断信息、可信设备管理。

交互原则：

- 未连接或文本为空时禁用发送。
- 发送成功后清空输入并保持继续输入的节奏。
- busy、配对失败、Mac 不可达、receipt 失败要有明确状态。
- 不把 NSD、TCP、token 等底层细节暴露给主流程；这些信息只进入诊断。

## 验证计划

### 协议测试

- Swift 和 Kotlin 使用同一批 JSON fixtures 验证 `CarrierEnvelope` 编解码一致。
- frame codec 覆盖完整帧、半包、粘包、非法长度和非法 JSON。
- receipt 的 `received`、`posted`、`unverifiedPosted`、`failed` 都能跨端解析。

### Mac 验证

- 使用 localhost 测试 client 先验证 Android bridge，不依赖 Android 真机。
- Android bridge 收到文本后复用现有历史、粘贴、receipt 和诊断链路。
- 已有 iPhone Multipeer 路径不回退。
- 已有 active sender 时，新连接返回 busy。

### Android 验证

- `./gradlew testDebugUnitTest` 通过。
- 真机能通过 NSD 发现 Mac 或通过手动地址 fallback 连接。
- 首次配对成功后可发送中文、英文、emoji 和多行文本。
- 重启 Android app 后免配对连接同一台 Mac。
- Mac 删除可信设备后，Android 需要重新配对。

### 端到端验收

- Android 和 Mac 在同一 Wi-Fi 下可完成发现、配对、发送和 receipt。
- Android 开热点、Mac 连接热点后，至少可通过手动 IP + `17641` 完成配对、发送、Mac 历史入库和现有粘贴流程。
- Mac 无 Accessibility 权限时，Android 能看到明确失败状态。
- Android active 时，iPhone 或另一台 Android 的连接处理符合 1:1 active sender 规则。

## 2026-06-01 真机验证记录

- Android 真机热点场景下，NSD / Bonjour 发现不稳定，第一版不把自动发现作为可用性门槛。
- Mac 端 Android bridge 曾因 Bonjour 发布触发 `NoAuth` 而失败；当前 MVP 决策是手动连接路径不依赖 Bonjour 发布。
- 固定 TCP 端口 `17641` + 手动填写 Mac 地址后，Android -> Mac 已完成端到端穿通：Mac 能接收 Android 文本、写入历史，并复用与 iOS 相同的粘贴处理链路。
- 后续仍需补强：发现权限自检、NoAuth 文案、自动发现恢复、重启后免配对、busy 规则和 iPhone 路径回归。

## 本地开发环境

Android 开发环境以 Android Studio + SDK 为准：

- Android Studio。
- Android SDK Platform 36。
- Android SDK Build-Tools。
- Android SDK Platform-Tools，用于 `adb`。
- Android SDK Command-line Tools，用于 `sdkmanager`。
- JDK 17 或 Android Studio 管理的 Gradle JDK；本机已有 Java 21，但 Android 工程应优先使用 Android Studio / Gradle 推荐的 JDK 配置。
- Android 真机。NSD / mDNS、热点和局域网发现不应只靠模拟器验收。

Android 工程落地后，debug APK 构建入口：

```bash
cd Apps/Android
./gradlew assembleDebug
```

预期产物：

```text
Apps/Android/app/build/outputs/apk/debug/app-debug.apk
```

真机安装：

```bash
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Release APK 和签名配置等 Android MVP 链路稳定后再补；keystore 和签名密码不得提交到仓库。

## 建议拆分

1. 先补 Mac 端 Android bridge 的 wire protocol、pairing/trust model 和 localhost 测试。
2. 再建 Android 工程，完成 Kotlin protocol / framing / discovery / transport 单元测试。
3. 再做 Compose 文本发送界面和真机端到端验证。
4. 最后补诊断、busy 状态、可信设备清理和 iPhone 路径回归验证。
