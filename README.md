# TypeCarrier

TypeCarrier 是一个轻量的 iPhone 到 Mac 文本传送工具。

它解决一个很具体的工作流：

> 在 iPhone 上输入或语音转文字，点发送，文本自动出现在 Mac 当前光标所在的位置。

TypeCarrier 不是语音识别产品。它默认你已经有顺手的手机输入方式，比如系统键盘、第三方输入法或语音输入；TypeCarrier 只负责跨设备传输和在 Mac 端自动粘贴。

## 当前状态

项目目前是一个原生 Apple 双端 v0 原型：

- `TypeCarrieriOS`：iPhone 输入和发送端。
- `TypeCarrierMac`：macOS 菜单栏接收端，收到文本后自动粘贴到当前输入焦点。
- `TypeCarrierCore`：共享 payload、连接状态和 Multipeer 传输逻辑。

v0 使用 Apple 的 Multipeer Connectivity 在局域网内通信，不需要账号，也不经过服务器。当前工程目标系统版本为 iOS 26.0 和 macOS 26.0。

## v0 范围

- iOS 端提供聚焦的文本输入界面和发送按钮。
- macOS 端常驻菜单栏，接收文本并插入到当前聚焦输入框。
- 默认场景是 iPhone 开热点，Mac 连接该热点，两端在局域网内自动发现。
- v0 不做云同步、历史记录、二维码配对、配对码、AI、语音识别或 Android 版本。

## 构建

安装 XcodeGen：

```sh
brew install xcodegen
```

生成 Xcode 工程：

```sh
xcodegen generate
```

运行主要检查：

```sh
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'generic/platform=iOS Simulator' build
```

如果要真机调试或正式归档，复制本地签名配置：

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

然后在 `Configs/Signing.local.xcconfig` 中填写自己的 bundle 前缀和 Apple Developer Team ID。该文件已被 Git 忽略，不应提交到仓库。

## 开源与官方版本

TypeCarrier 源码使用 Apache License 2.0 开源，用户可以自行从源码构建。

官方 App Store、Mac 版本以及未来可能的 Android 版本，可能采用一次性付费购买。付费对应的是官方签名构建、商店分发、更新和持续维护支持；这不改变源码开源属性。

`TypeCarrier` 名称、图标、商店素材和官方发布身份遵循项目品牌策略。Fork 可以使用源码，但面向用户分发时应使用自己的应用名称、bundle id、图标和商店素材，除非获得明确授权。

## 协作方式

功能开发、传输协议、权限、自动粘贴、发布配置等改动建议走 Pull Request，并保持 `master` 可构建。小的文档修正可以由维护者直接提交。

当前 GitHub Actions 只做基础检查。由于 GitHub hosted runner 暂时还没有 iOS 26 / macOS 26 构建环境，CI 会在 Xcode 版本不足时跳过真实 Xcode build。后续可以接入 self-hosted Mac 或 Xcode Cloud 作为正式发布流水线。

## 文档

- [Idea](docs/idea.md)
- [Design Goals](docs/design-goals.md)
- [Competitive Analysis](docs/competitive-analysis.md)
- [Technical Notes](docs/technical-notes.md)
- [MVP Plan](docs/mvp-plan.md)
- [Open Source Policy](docs/open-source-policy.md)
- [Distribution](docs/distribution.md)
- [GitHub History Remediation](docs/github-history-remediation.md)
- [Branding](BRANDING.md)
