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

## GitHub Beta 发布

首个 0.1 Beta 可以按 GitHub prerelease 处理：

- iOS 端只发布源码和说明，不在 GitHub Release 上传可直接安装的 iOS 构建产物。
- macOS 端可以上传 `.zip` 包，但面向公开下载时应使用 Developer ID Application 签名、开启 Hardened Runtime，并完成 notarization。
- 如果只是给自己或非常小范围测试，可以先只发布源码 tag，或上传带明确说明的开发签名包；不要把它描述成对普通用户即开即用的正式安装包。

建议 tag 命名：

```sh
git tag -a v0.1.0-beta.1 -m "TypeCarrier 0.1 Beta 1"
git push origin v0.1.0-beta.1
```

创建 GitHub prerelease：

```sh
gh release create v0.1.0-beta.1 \
  --title "TypeCarrier 0.1 Beta 1" \
  --notes-file docs/releases/0.1-beta.1.md \
  --prerelease
```

如果已经准备好 macOS zip，可以一并上传：

```sh
gh release upload v0.1.0-beta.1 dist/TypeCarrierMac-0.1-1.zip
```

## macOS 本地打包

本地生成 macOS Release zip：

```sh
script/package_macos_release.sh
```

脚本会执行 Release build、校验签名、运行 Gatekeeper assessment，并输出 `dist/TypeCarrierMac-<version>-<build>.zip` 及 SHA-256。

当前公开仓库不提交真实签名材料。公开分发前，本机需要在 `Configs/Signing.local.xcconfig` 中配置发布签名，例如：

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = ak22ak.typecarrier
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY[sdk=macosx*] = Developer ID Application
```

如果 `spctl --assess` 仍然拒绝产物，通常说明还没有使用 Developer ID 签名，或 zip 内 app 尚未 notarize/staple。

## GitHub Actions

公开 CI 只负责构建和测试验证，不负责正式商店发布。

如果后续要自动发布，建议优先考虑 Xcode Cloud 或 self-hosted Mac runner，并把签名材料和 App Store Connect key 放在受控的私有环境中。
