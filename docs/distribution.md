# 发行说明

[English](distribution.en.md)

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
- macOS 端随 release 上传 Apple Development / Personal Team 签名的测试包。
- 这个 macOS 测试包不是 Developer ID notarized 正式包，Gatekeeper 可能拦截。
- 不要把 0.1 Beta 的 macOS zip 描述成对普通用户即开即用的正式安装包。

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

如果已经准备好 macOS development zip，可以一并上传：

```sh
gh release upload v0.1.0-beta.1 dist/TypeCarrierMac-0.1-1-development.zip
```

## macOS 本地打包

本地生成 macOS Release zip：

```sh
script/package_macos_release.sh
```

脚本会执行 Release build、校验签名、运行 Gatekeeper assessment，并输出 `dist/TypeCarrierMac-<version>-<build>-development.zip` 及 SHA-256。

0.1 默认生成 development 测试包：

- 文件名：`TypeCarrierMac-0.1-1-development.zip`。
- 签名：Apple Development / Personal Team。
- Gatekeeper assessment 可能失败；脚本会输出 warning，但不会把它当作 0.1 development 包的构建失败。

## 未来正式 macOS 包

当前公开仓库不提交真实签名材料。未来要发布 Developer ID notarized 包时，本机需要在 `Configs/Signing.local.xcconfig` 中配置发布签名，例如：

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = ak22ak.typecarrier
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY[sdk=macosx*] = Developer ID Application
```

正式包还需要 Apple Developer Program、Developer ID Application 证书、notarytool 凭据、notarization、staple，并最终通过 `spctl --assess`。

## GitHub Actions

公开 CI 负责构建和测试验证。Release workflow 可以创建 GitHub prerelease draft，但不在 GitHub hosted runner 上保存签名私钥，也不生成正式签名包。

如果后续要自动发布，建议优先考虑 Xcode Cloud 或 self-hosted Mac runner，并把签名材料和 App Store Connect key 放在受控的私有环境中。
