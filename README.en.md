# TypeCarrier

[中文](README.md)

TypeCarrier is a lightweight iPhone-to-Mac text carrier.

It focuses on one workflow:

> Type on the iPhone, or use any iPhone speech-to-text input, tap send, and the text appears at the current cursor position on the Mac.

TypeCarrier is not a speech recognition product. It assumes you already have a preferred iPhone input method, such as the system keyboard, a third-party keyboard, or dictation. TypeCarrier handles local transport and insertion on the Mac.

## Current Status

TypeCarrier is currently a native Apple 0.1 Beta:

- `TypeCarrieriOS`: iPhone input and sender app.
- `TypeCarrierMac`: macOS menu bar receiver that inserts received text into the current input focus.
- `TypeCarrierCore`: shared payload, connection state, diagnostics, and Multipeer transport logic.

0.1 uses Apple Multipeer Connectivity on the local network. It does not require an account or a server. The project currently targets iOS 26.0 and macOS 26.0.

## 0.1 Beta Scope

- Focused iPhone text composer and send action.
- macOS menu bar receiver.
- Local network discovery and transport.
- Text insertion on macOS through clipboard handoff and simulated paste.
- Connection state, receiver state, and diagnostics entry points.
- No cloud sync, QR pairing, pairing code, AI, speech recognition, Android, Windows, or multi-device switching in 0.1.

## Downloads and Releases

Users can get TypeCarrier from these platform-specific entry points:

- iOS: download from the App Store. The App Store page is not live yet; the current placeholder is [TypeCarrier on the App Store](https://apps.apple.com/app/typecarrier), and it will be replaced with the real store URL after release.
- Android: download the sideloadable APK from the [latest GitHub Release](https://github.com/AK22AK/TypeCarrier/releases/latest).
- macOS: download the sideloadable Mac package from the [latest GitHub Release](https://github.com/AK22AK/TypeCarrier/releases/latest).

Current GitHub Releases are still beta / sideload distribution:

- Android and macOS packages are provided through GitHub Release, not through app stores.
- The macOS testing package may still be Apple Development / Personal Team signed and may not be a Developer ID notarized public distribution build. Gatekeeper may block it.
- iOS installable builds are not provided through GitHub Release. The official iOS acquisition path is the App Store.

## Build

Install XcodeGen:

```sh
brew install xcodegen
```

Generate the Xcode project:

```sh
xcodegen generate
```

Run the main checks:

```sh
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'generic/platform=iOS Simulator' build
```

For local device testing or release archives, copy the local signing config:

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

Then fill in your bundle prefix and Apple Developer Team ID in `Configs/Signing.local.xcconfig`. The file is gitignored and should not be committed.

## Open Source and Official Builds

TypeCarrier source code is licensed under Apache License 2.0. Users may build the app from source.

Official App Store, Mac, and future Android builds may be sold as one-time purchases. Payment covers official signed builds, store distribution, updates, and maintenance support. It does not change the open-source status of the code.

The `TypeCarrier` name, app icon, store assets, and official distribution identity follow the project brand policy. Forks may use the source code, but user-facing distribution should use a different app name, bundle id, icon, and store assets unless explicitly authorized.

## Contributing

Feature work, protocol changes, permissions, automatic paste behavior, and release configuration changes should go through pull requests and keep `master` buildable. Small documentation fixes may be committed directly by maintainers.

Current GitHub Actions perform baseline checks. Hosted runners may not always provide Xcode 26 yet, so Xcode builds are skipped with a notice when the runner is too old.

## Documentation

- [Idea](docs/idea.md)
- [Design Goals](docs/design-goals.md)
- [Competitive Analysis](docs/competitive-analysis.md)
- [Technical Notes](docs/technical-notes.md)
- [MVP Plan](docs/mvp-plan.md)
- [Roadmap](docs/roadmap.md)
- [0.1.2 Release Notes](docs/releases/0.1.2.en.md)
- [0.1.1 Release Notes](docs/releases/0.1.1.en.md)
- [0.1 Beta 1 Release Notes](docs/releases/0.1-beta.1.en.md)
- [Multi-Device Management Plan](docs/multi-device-management-plan.md)
- [Open Source and Official Build Policy](docs/open-source-policy.md)
- [Distribution](docs/distribution.en.md)
- [GitHub History Remediation](docs/github-history-remediation.md)
- [Brand Policy](BRANDING.md)
