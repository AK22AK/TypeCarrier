# 开源与官方版本策略

TypeCarrier 的源码采用开放策略：代码公开，任何人都可以在 Apache License 2.0 下学习、修改和自行构建。

官方构建仍然可以在应用商店中收费。iOS、macOS 或未来 Android 版本的一次性购买，是发行和维护策略，不限制用户阅读源码或自行构建。

## 策略

- 源码使用 Apache License 2.0 开源。
- 用户可以自行从源码构建 app。
- 官方商店版本可以收费。
- 官方签名证书、provisioning profile、App Store Connect key 和发布元数据不存放在公开仓库。
- Fork 面向用户分发时，应使用自己的 app 名称、bundle id、图标和商店素材，除非获得明确授权。
- 如果未来增加 Android，也采用同一模型：源码开放，官方商店构建可以收费。

## 为什么采用这个模型

官方构建的价值是方便下载、可信签名、商店更新和持续维护支持。

公开仓库的价值是透明、可审计、便于学习，以及接受社区贡献。

这两个目标不冲突。

## 不应提交的内容

- 官方发布使用的 Apple Developer Team ID。
- Provisioning profile 或证书。
- App Store Connect API key。
- 私有发布说明或未公开商店元数据。
- 个人 Xcode 用户状态文件。
- 本地签名覆盖文件，例如 `Configs/Signing.local.xcconfig`。
