# TypeCarrier

TypeCarrier is a lightweight iPhone-to-Mac text carrier.

The first version focuses on one workflow:

> Type or dictate text on iPhone, tap send, and have the text inserted at the current Mac cursor.

This project is intentionally not a speech recognition product. It assumes the user already prefers an input method on the phone, such as Doubao keyboard dictation, and only solves the cross-device text delivery and paste step.

## Project Status

TypeCarrier is currently a native Apple-platform prototype:

- `TypeCarrieriOS`: iPhone sender app.
- `TypeCarrierMac`: macOS menu bar receiver app.
- `TypeCarrierCore`: shared payload, state, and Multipeer transport code.

The v0 prototype uses local-network Multipeer Connectivity and targets iOS 26.0
and macOS 26.0.

## Initial Scope

- iOS app: a focused text input surface with a send action.
- macOS app: a menu bar receiver that inserts received text into the current focused input.
- Transport: local Apple-device communication first, preferably no account and no server.
- Primary platform: iPhone and Mac.
- Primary user: a developer or heavy computer user who prefers phone dictation but wants text to land directly on the Mac.

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

For device builds or official archives, copy
`Configs/Signing.example.xcconfig` to `Configs/Signing.local.xcconfig` and fill
in your own bundle prefix and Apple Developer Team ID. The local signing file is
ignored by Git.

## Open Source and Official Builds

The source code is available under the Apache License 2.0. Users may self-build
the app from source.

Official App Store, Mac, and future Android builds may be paid one-time
purchases. The paid build is for signed distribution, updates, and continued
development support; it does not make the source code private.

The TypeCarrier name, icon, store listing assets, and official release identity
are covered by the project branding policy.

## Documents

- [Idea](docs/idea.md)
- [Design Goals](docs/design-goals.md)
- [Competitive Analysis](docs/competitive-analysis.md)
- [Technical Notes](docs/technical-notes.md)
- [MVP Plan](docs/mvp-plan.md)
- [Open Source Policy](docs/open-source-policy.md)
- [Distribution](docs/distribution.md)
- [GitHub History Remediation](docs/github-history-remediation.md)
- [Branding](BRANDING.md)
