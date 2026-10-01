# TypeCarrier

[English](README.en.md)

TypeCarrier 是一个轻量的手机到 Mac 文本传送工具。

> 在 iPhone 或 Android 手机上输入或语音转文字，点发送，文本出现在 Mac 当前光标所在的位置。

它使用手机现有键盘和听写能力，负责本地传输和 Mac 自动粘贴，不内置语音识别或 AI。

## 当前状态

当前源码版本为 **0.1.3 Beta**，包含 iPhone、Android 发送端和 macOS 菜单栏接收端：

- iPhone 使用 Multipeer Connectivity；Android 使用局域网 TCP，支持 NSD / mDNS 发现和手动地址连接。
- iPhone 自动发现并连接 Mac；Android 首次连接使用 Mac 显示的配对码。Multipeer 和 Android bridge 各自限制一个 active sender，两入口可并行，尚无统一多设备调度。
- 支持普通发送和发送后回车；Mac 自动粘贴需要辅助功能权限，实际结果取决于当前焦点和目标应用。
- iOS 提供草稿、发送历史、重新发送及撤销/重做；Mac 提供接收历史和剪贴板恢复开关。
- 提供连接状态、自检和诊断导出。前后台恢复与重连已有实现，稳定性仍需按设备和网络场景验证。

无需账号或服务器。系统要求为 iOS 26.0、macOS 26.0、Android 8.0 或更新版本。云同步、互联网中转、Windows、统一多设备调度和触控板模式尚未支持。

## 下载与发布

- iOS：通过 TestFlight 邀请测试，也可自行从源码构建；尚无公开 App Store 下载入口。
- Android / macOS：查看 [GitHub Releases](https://github.com/AK22AK/TypeCarrier/releases)，下载已公开版本的 APK / DMG 及校验文件。

源码版本与各渠道已公开的构建可能不同。GitHub 发布流程先生成 draft prerelease，完成核对后才公开；生成草稿不代表已经发布。iOS 安装包不在 GitHub Release 提供。

macOS 发布流程支持 Developer ID 签名及公证 DMG；本地 development 测试包可能被 Gatekeeper 拦截。请以对应发行说明为准。

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

官方 App Store、Mac 版本以及 Android 版本，可能采用一次性付费购买。付费对应的是官方签名构建、商店分发、更新和持续维护支持；这不改变源码开源属性。

`TypeCarrier` 名称、图标、商店素材和官方发布身份遵循项目品牌策略。Fork 可以使用源码，但面向用户分发时应使用自己的应用名称、bundle id、图标和商店素材，除非获得明确授权。

## 协作方式

功能开发、传输协议、权限、自动粘贴、发布配置等改动建议走 Pull Request，并保持 `master` 可构建。小的文档修正可以由维护者直接提交。

GitHub Actions 提供基础检查。Apple 端测试与构建仅在 runner 的 Xcode 版本至少为 26 时运行；否则会跳过。CI 成功不一定代表 Apple 端已完成构建验证。Android CI 运行单元测试和 Debug 构建。

## 文档

- [项目想法](docs/idea.md)
- [设计目标](docs/design-goals.md)
- [竞品分析](docs/competitive-analysis.md)
- [技术说明](docs/technical-notes.md)
- [MVP 计划](docs/mvp-plan.md)
- [路线图](docs/roadmap.md)
- [0.1.3 发行说明](docs/releases/0.1.3.md)
- [0.1.2 发行说明](docs/releases/0.1.2.md)
- [0.1.1 发行说明](docs/releases/0.1.1.md)
- [0.1 Beta 1 发行说明](docs/releases/0.1-beta.1.md)
- [多设备管理后续计划](docs/multi-device-management-plan.md)
- [开源与官方版本策略](docs/open-source-policy.md)
- [发行说明](docs/distribution.md)
- [GitHub 历史补救](docs/github-history-remediation.md)
- [品牌策略](BRANDING.md)
