# Distribution

TypeCarrier separates public source builds from official signed releases.

## Local Development

Generate the Xcode project:

```sh
xcodegen generate
```

Build and test from the command line:

```sh
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Local Signing

The public project uses placeholder bundle identifiers and no committed
developer team. For device builds or release archives, copy the example signing
file:

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

Then edit `Configs/Signing.local.xcconfig` with your own values:

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = your.bundle.prefix
DEVELOPMENT_TEAM = YOURTEAMID
```

`Configs/Signing.local.xcconfig` is ignored by Git and should stay local.

## Official Releases

Official App Store or Mac releases should be archived from a trusted local
machine or private release environment. Do not commit certificates, provisioning
profiles, App Store Connect API keys, or private release configuration to the
public repository.

## GitHub Actions

Public CI should verify builds and tests only. It should not publish official
store releases unless a private signing setup is intentionally added later.
