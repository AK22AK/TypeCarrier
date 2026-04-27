# 发行说明

TypeCarrier 将公开源码构建和官方签名发布分开处理。

## 本地开发

生成 Xcode 工程：

```sh
xcodegen generate
```

从命令行构建和测试：

```sh
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## 本地签名

公开工程使用占位 bundle id，不提交开发者团队信息。真机调试或发布归档时，复制示例签名文件：

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

然后编辑 `Configs/Signing.local.xcconfig`：

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = your.bundle.prefix
DEVELOPMENT_TEAM = YOURTEAMID
```

`Configs/Signing.local.xcconfig` 已被 Git 忽略，应只保留在本机。

## 官方发布

官方 App Store 或 Mac 版本应从可信本机或私有发布环境归档。不要把证书、provisioning profile、App Store Connect API key 或私有发布配置提交到公开仓库。

## GitHub Actions

公开 CI 只负责构建和测试验证，不负责正式商店发布。

如果后续要自动发布，建议优先考虑 Xcode Cloud 或 self-hosted Mac runner，并把签名材料和 App Store Connect key 放在受控的私有环境中。
