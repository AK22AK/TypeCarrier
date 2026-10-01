# TypeCarrier

[中文](README.md)

TypeCarrier is a lightweight phone-to-Mac text carrier.

> Type or dictate on an iPhone or Android phone, tap send, and the text appears at the current cursor position on the Mac.

It uses your phone's existing keyboard and dictation tools, and handles local transport and automatic paste on the Mac. It does not include speech recognition or AI.

## Current Status

The current source version is **0.1.3 Beta**, with iPhone and Android senders and a macOS menu bar receiver:

- iPhone uses Multipeer Connectivity; Android uses local TCP with NSD / mDNS discovery and manual address connection.
- iPhone discovers and connects to the Mac automatically; Android uses a code shown on the Mac for first-time pairing. Multipeer and the Android bridge each allow one active sender; both transports can run concurrently, without unified multi-device scheduling.
- Plain send and send-with-Return are supported. Automatic paste needs macOS Accessibility permission; results depend on the current focus and target app.
- iOS provides drafts, send history, resend, and undo/redo. Drafts are stored independently; send history can be retained by count or age. Mac provides receive history and a clipboard restoration toggle.
- Connection state, self-checks, and diagnostic export are available. Foreground recovery and reconnect are implemented; reliability still needs device and network validation.

No account or server is required. Requirements: iOS 26.0, macOS 26.0, or Android 8.0 or later. Cloud sync, internet relay, Windows, unified multi-device scheduling, and touchpad mode are not supported yet.

## Downloads and Releases

- iOS: invited testing through TestFlight, or build from source. No public App Store download is available yet.
- Android / macOS: visit [GitHub Releases](https://github.com/AK22AK/TypeCarrier/releases) for published APK / DMG packages and checksums.

The latest source may include unreleased changes, and its version may differ from published builds on each channel. The GitHub release workflow creates a draft prerelease, which is published after verification; a draft is not a public release. iOS installable packages are not provided on GitHub Release.

The macOS release workflow supports Developer ID signed and notarized DMGs. Local development testing packages may be blocked by Gatekeeper. Check the corresponding release notes.

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

Official App Store, Mac, and Android builds may be sold as one-time purchases. Payment covers official signed builds, store distribution, updates, and maintenance support. It does not change the open-source status of the code.

The `TypeCarrier` name, app icon, store assets, and official distribution identity follow the project brand policy. Forks may use the source code, but user-facing distribution should use a different app name, bundle id, icon, and store assets unless explicitly authorized.

## Contributing

Feature work, protocol changes, permissions, automatic paste behavior, and release configuration changes should go through pull requests and keep `master` buildable. Small documentation fixes may be committed directly by maintainers.

GitHub Actions perform baseline checks. Apple tests and builds run only when the runner has Xcode 26 or later; otherwise they are skipped. A successful CI run does not necessarily include Apple build verification. Android CI runs unit tests and a Debug build.

## Documentation

- [Idea](docs/idea.md)
- [Design Goals](docs/design-goals.md)
- [Competitive Analysis](docs/competitive-analysis.md)
- [Technical Notes](docs/technical-notes.md)
- [MVP Plan](docs/mvp-plan.md)
- [Roadmap](docs/roadmap.md)
- [0.1.3 Release Notes](docs/releases/0.1.3.en.md)
- [0.1.2 Release Notes](docs/releases/0.1.2.en.md)
- [0.1.1 Release Notes](docs/releases/0.1.1.en.md)
- [0.1 Beta 1 Release Notes](docs/releases/0.1-beta.1.en.md)
- [Multi-Device Management Plan](docs/multi-device-management-plan.md)
- [Open Source and Official Build Policy](docs/open-source-policy.md)
- [Distribution](docs/distribution.en.md)
- [GitHub History Remediation](docs/github-history-remediation.md)
- [Brand Policy](BRANDING.md)
