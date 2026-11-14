# TypeCarrier

English | [简体中文](README.zh-CN.md)

TypeCarrier is a lightweight phone-to-Mac text carrier.

> Type or dictate on an iPhone or Android phone, tap send, and the text appears at the current cursor position on the Mac.

It uses your phone's existing keyboard and dictation tools, and handles local transport and automatic paste on the Mac. It does not include speech recognition or AI.

## Current Status

The current source version is **0.2.0 Beta**, with iPhone and Android senders and a macOS menu bar receiver:

- All three platforms speak the same v2 transport: local TCP with Bonjour / mDNS discovery, end-to-end encrypted with a Noise handshake. The protocol core is written in Rust (`Core/carrier-core`) and shared by iOS, macOS and Android. Android can also connect by typing an address when discovery fails.
- The phone starts pairing on first connection: both screens show the same 4-digit code, and pairing completes once it is confirmed on the Mac; later connections reconnect automatically. Phones can connect to multiple Macs and select one send target. Mac accepts multiple phones and pastes their text through one arrival-order queue.
- 0.2.0 is not protocol-compatible with 0.1.x: update all three apps together and pair once again.
- Plain send and send-with-Return are supported. Automatic paste needs macOS Accessibility permission; results depend on the current focus and target app.
- iOS provides drafts, send history, resend, and undo/redo. Drafts are stored independently; send history can be retained by count or age. Mac provides receive history (read first, edit on demand with explicit save) and a clipboard restoration toggle.
- Connection state, self-checks, and diagnostic export are available. Foreground recovery and reconnect are implemented; reliability still needs device and network validation.

No account or server is required. Requirements: iOS 26.0, macOS 26.0, or Android 8.0 or later. Cloud sync, internet relay, Windows and touchpad mode are not supported yet.

## Downloads and Releases

- iOS: invited testing through TestFlight, or build from source. No public App Store download is available yet.
- Android / macOS: visit [GitHub Releases](https://github.com/AK22AK/TypeCarrier/releases) for published APK / DMG packages and checksums.

The latest source may include unreleased changes, and its version may differ from published builds on each channel. The GitHub release workflow creates a draft prerelease, which is published after verification; a draft is not a public release. iOS installable packages are not provided on GitHub Release.

The macOS release workflow supports Developer ID signed and notarized DMGs. Local development testing packages may be blocked by Gatekeeper. Check the corresponding release notes.

## Build

Install XcodeGen and Rust (via [rustup](https://rustup.rs)):

```sh
brew install xcodegen
```

Add the Rust targets the Apple apps need:

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

Before the first build, compile the Rust protocol core (it produces `Core/build/CarrierCoreFFI.xcframework`). After that, Xcode builds recompile it whenever `Core/carrier-core` changes:

```sh
script/build_carrier_core_apple.sh
```

Generate the Xcode project:

```sh
xcodegen generate
```

Run the main checks:

```sh
(cd Core/carrier-core && cargo test)
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'generic/platform=iOS Simulator' build
```

For local device testing or release archives, copy the local signing config:

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

Then fill in your bundle prefix and Apple Developer Team ID in `Configs/Signing.local.xcconfig`. The file is gitignored and should not be committed.

Android also needs the Android NDK, `cargo-ndk` and the matching Rust targets; the Gradle build runs `script/build_carrier_core_android.sh` to compile the Rust core:

```sh
cargo install cargo-ndk --locked
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd Apps/Android && ./gradlew testDebugUnitTest assembleDebug
```

## Open Source and Official Builds

TypeCarrier source code is licensed under Apache License 2.0. Users may build the app from source.

Official App Store, Mac, and Android builds may be sold as one-time purchases. Payment covers official signed builds, store distribution, updates, and maintenance support. It does not change the open-source status of the code.

The `TypeCarrier` name, app icon, store assets, and official distribution identity follow the project brand policy. Forks may use the source code, but user-facing distribution should use a different app name, bundle id, icon, and store assets unless explicitly authorized.

## Contributing

Feature work, protocol changes, permissions, automatic paste behavior, and release configuration changes should go through pull requests and keep `master` buildable. Small documentation fixes may be committed directly by maintainers.

GitHub Actions perform baseline checks. Apple tests and builds run only when the runner has Xcode 26 or later; otherwise they are skipped. A successful CI run does not necessarily include Apple build verification. Android CI runs unit tests and a Debug build.

## Documentation

- [Technical Notes](docs/technical-notes.md) (Chinese): architecture and the v2 transport protocol
- [Roadmap](docs/roadmap.md) (Chinese)
- [Design Goals](docs/design-goals.md) (Chinese)
- [Distribution](docs/distribution.en.md): building, signing and releasing
- [Release Notes](https://github.com/AK22AK/TypeCarrier/releases) (sources in [docs/releases](docs/releases))
- [Open Source and Official Build Policy](docs/open-source-policy.md) (Chinese) · [Brand Policy](BRANDING.md)
