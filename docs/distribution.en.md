# Distribution

[中文](distribution.md)

TypeCarrier separates open-source source distribution from official signed builds.

## Local Development

Generate the Xcode project:

```sh
xcodegen generate
```

Build and test from the command line:

```sh
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierCore -destination 'platform=macOS' test
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrierMac -destination 'platform=macOS' build
xcodebuild -project TypeCarrier.xcodeproj -scheme TypeCarrieriOS -destination 'generic/platform=iOS Simulator' build
```

## Local Signing

The public project uses placeholder signing settings and does not commit a concrete developer team. For local device testing or archives, copy the example signing file:

```sh
cp Configs/Signing.example.xcconfig Configs/Signing.local.xcconfig
```

Then edit `Configs/Signing.local.xcconfig`:

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = your.bundle.prefix
DEVELOPMENT_TEAM = YOURTEAMID
```

`Configs/Signing.local.xcconfig` is gitignored and should stay local.

## GitHub Beta Release

The first 0.1 Beta should be published as a GitHub prerelease:

- The iOS side is source-only. No installable iOS build is uploaded to GitHub Release.
- The macOS side may upload an Apple Development / Personal Team signed testing zip.
- This macOS testing zip is not a Developer ID notarized public distribution build. Gatekeeper may block it.
- Do not describe the 0.1 Beta macOS zip as a regular user-ready installer.

Recommended tag:

```sh
git tag -a v0.1.0-beta.1 -m "TypeCarrier 0.1 Beta 1"
git push origin v0.1.0-beta.1
```

Create the GitHub prerelease:

```sh
gh release create v0.1.0-beta.1 \
  --title "TypeCarrier 0.1 Beta 1" \
  --notes-file docs/releases/0.1-beta.1.md \
  --prerelease
```

Upload the local macOS development zip when ready:

```sh
gh release upload v0.1.0-beta.1 dist/TypeCarrierMac-0.1-1-development.zip
```

## macOS Local Packaging

Generate a local macOS Release zip:

```sh
script/package_macos_release.sh
```

The script runs a Release build, verifies code signing, runs Gatekeeper assessment, and prints the SHA-256 checksum.

0.1 generates a development testing package by default:

- File name: `TypeCarrierMac-0.1-1-development.zip`.
- Signing: Apple Development / Personal Team.
- Gatekeeper assessment may fail. The script prints a warning, but this is not treated as a packaging failure for the 0.1 development package.

## Future Official macOS Package

The public repository must not store real signing material. A future Developer ID notarized build requires local signing configuration such as:

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = ak22ak.typecarrier
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY[sdk=macosx*] = Developer ID Application
```

An official public macOS package also requires the paid Apple Developer Program, a Developer ID Application certificate, notarytool credentials, notarization, stapling, and a passing `spctl --assess` check.

## GitHub Actions

Public CI verifies source, tests, and builds. The release workflow may create a GitHub prerelease draft, but it does not store signing private keys on GitHub hosted runners and does not produce an official signed macOS package.

Future fully automated signing should use Xcode Cloud or a controlled self-hosted Mac runner with private signing materials and App Store Connect credentials.
