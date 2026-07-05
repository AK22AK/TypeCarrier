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

### Android 侧载签名

Android APK 即使走侧载路线也需要签名。TypeCarrier 的 Android release 构建会从 `Apps/Android/local.properties` 或环境变量读取签名配置；`local.properties` 已被 Git 忽略。

首次在本机创建 release keystore：

```sh
script/setup_android_release_signing.sh
```

脚本会生成 `~/.typecarrier/android-release.jks`，并把下面这些本机配置写入 `Apps/Android/local.properties`：

```properties
typecarrier.android.release.storeFile=/absolute/path/to/android-release.jks
typecarrier.android.release.storePassword=...
typecarrier.android.release.keyAlias=typecarrier-release
typecarrier.android.release.keyPassword=...
```

构建本机 release APK：

```sh
cd Apps/Android
./gradlew testDebugUnitTest assembleRelease
```

输出文件为 `Apps/Android/app/build/outputs/apk/release/app-release.apk`。后续发布给用户侧载的 APK 应保持使用同一份 keystore，否则同一个 `applicationId` 不能覆盖升级已有安装。

## 官方发布

官方 App Store 或 Mac 版本应从可信本机或私有发布环境归档。不要把证书、provisioning profile、App Store Connect API key 或私有发布配置提交到公开仓库。

## 用户下载入口

- iOS：前往 App Store 下载。App Store 页面尚未上架，当前占位链接为 [TypeCarrier on the App Store](https://apps.apple.com/app/typecarrier)，正式上架后替换为真实商店地址。
- Android：在 [GitHub 最新 Release](https://github.com/AK22AK/TypeCarrier/releases/latest) 下载 APK 侧载包。
- macOS：在 [GitHub 最新 Release](https://github.com/AK22AK/TypeCarrier/releases/latest) 下载 Mac 侧载包。

## GitHub Beta 发布

GitHub Release 提供 Android / macOS 侧载包，并保留到最新 Release 的自引用入口：

- iOS 端不在 GitHub Release 上传可直接安装的 iOS 构建产物；正式获取方式是 App Store / TestFlight。
- Android 端随 release 上传 APK 侧载包。
- macOS 端在 release workflow 中生成 Developer ID signed + notarized DMG，并随 release 上传 `.dmg` 和 `.sha256`。
- 不要把 beta 侧载包描述成对普通用户即开即用的正式安装包。

0.1.2 建议 tag 命名：

```sh
git tag -a v0.1.2 -m "TypeCarrier 0.1.2"
git push origin v0.1.2
```

创建 GitHub prerelease：

```sh
gh release create v0.1.2 \
  --title "TypeCarrier 0.1.2" \
  --notes-file docs/releases/0.1.2.md \
  --prerelease
```

### 发布后核对

发布后按下面顺序确认：

1. GitHub Release 标记为 prerelease，不是正式 stable release。
2. Release 页面显示 Android APK、macOS notarized DMG 以及对应校验文件。
3. 校验文件内容与本地 `shasum -a 256` 输出一致。
4. Release body 保留 beta 定位、iOS App Store / TestFlight 获取方式、Android / macOS 侧载说明和 macOS 权限提示。
5. 当前 tag 指向预期的发布 commit，而不是临时本地 commit。
6. 如果 GitHub Actions 因 runner Xcode 版本跳过 build，发布前必须使用本机 Xcode 重新跑完 release note 里的验证命令。
7. 发布后下载一次 GitHub asset，确认 DMG 可以挂载，app bundle 版本号与 release tag 对应。
8. 对下载的 DMG 运行 `spctl --assess --type install --verbose=4 <dmg>`，确认 Gatekeeper 评估通过。

## macOS 本地打包

本地生成 macOS Release zip：

```sh
script/package_macos_release.sh
```

脚本会执行 Release build、校验签名、运行 Gatekeeper assessment，并输出 `dist/TypeCarrierMac-<version>-<build>-development.zip` 及 SHA-256。

0.1.2 默认生成 development 测试包：

- 文件名：`TypeCarrierMac-0.1.2-3-development.zip`。
- 签名：Apple Development / Personal Team。
- Gatekeeper assessment 可能失败；脚本会输出 warning，但不会把它当作 0.1 development 包的构建失败。

## 未来正式 macOS 包

当前公开仓库不提交真实签名材料。本机要发布 Developer ID notarized 包时，需要在 `Configs/Signing.local.xcconfig` 中配置发布签名，例如：

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = ak22ak.typecarrier
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_STYLE[sdk=macosx*] = Manual
CODE_SIGN_IDENTITY[sdk=macosx*] = Developer ID Application
```

然后运行：

```sh
APPLE_TEAM_ID=YOURTEAMID \
NOTARYTOOL_KEYCHAIN_PROFILE=typecarrier-notary \
script/package_macos_developer_id_dmg.sh
```

脚本会 archive、生成 DMG、签名 DMG、提交 notarization、staple，并最终通过 `spctl --assess`。

## GitHub Actions 签名配置

Release workflow 会自动生成 Android APK 和 macOS Developer ID notarized DMG。macOS 正式 DMG 使用受保护的 GitHub Environment：`release-signing`。不要把签名 Secrets 放在普通 repository secrets 里，应该放在 `release-signing` environment secrets 里，并给该 environment 配置 Required reviewers。

`release-signing` 里需要设置下面这些 Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Android release keystore 文件的 base64 内容 |
| `ANDROID_RELEASE_STORE_PASSWORD` | Android release keystore 密码 |
| `ANDROID_RELEASE_KEY_ALIAS` | Android release key alias，例如 `typecarrier-release` |
| `ANDROID_RELEASE_KEY_PASSWORD` | Android release key 密码 |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Developer ID Application `.p12` 证书的 base64 内容 |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `APPLE_TEAM_ID` | Apple Developer Team ID，例如 `4H8462MSN6` |
| `APPSTORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Team API Key 的 Issuer ID；Individual API Key 可留空 |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | App Store Connect API `.p8` 私钥全文 |

推荐在 App Store Connect 的 `Users and Access` -> `Integrations` 里创建 API Key，用于 CI notarization。不要把 Apple ID 密码或 app-specific password 写进仓库。

导出 Android keystore secret：

```sh
base64 -i ~/.typecarrier/android-release.jks | pbcopy
```

导出 Developer ID `.p12` 时，用 Keychain Access 选中 `Developer ID Application` 证书及其私钥，导出为 `.p12`，设置一个强密码。然后在本机转换为 GitHub Secret 可用的 base64：

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Release workflow 会在 macOS runner 上创建临时 keychain、导入证书、执行 `script/package_macos_developer_id_dmg.sh`，并把生成的 DMG 与 `.sha256` 上传到 draft prerelease。由于 job 绑定了 `release-signing` environment，签名材料只有在该 environment 被批准后才会暴露给 runner。

Release workflow 固定使用 `macos-26` runner，避免 `macos-latest` 迁移期间拿到不兼容的 Xcode 版本。

Android 侧也提供独立的 `Android Release APK` workflow，用于只验证和产出签名 APK。该 workflow 读取同一组 Android secrets，执行 `./gradlew testDebugUnitTest assembleRelease`，并上传 `TypeCarrier-Android-<version>.apk` 与 `.sha256` 作为 Actions artifact。

## GitHub Actions

公开 CI 负责构建和测试验证。Release workflow 负责创建 GitHub prerelease draft、上传 Android APK、上传 macOS notarized DMG。

`release-signing` Environment Secrets 中的签名私钥和 App Store Connect key 只能用于受控 release workflow。不要在 pull request workflow、日志、release notes 或仓库文件中输出这些内容。
