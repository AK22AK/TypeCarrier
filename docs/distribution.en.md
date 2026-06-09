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

- iOS installable builds are not uploaded to GitHub Release. The official iOS acquisition path is the App Store / TestFlight.
- Android uploads a sideloadable APK.
- macOS builds a Developer ID signed + notarized DMG in the release workflow and uploads the `.dmg` plus `.sha256`.
- Do not describe beta sideload packages as regular user-ready installers.

Recommended tag for 0.1.1:

```sh
git tag -a v0.1.1 -m "TypeCarrier 0.1.1"
git push origin v0.1.1
```

Create the GitHub prerelease:

```sh
gh release create v0.1.1 \
  --title "TypeCarrier 0.1.1" \
  --notes-file docs/releases/0.1.1.md \
  --prerelease
```

### Post-Release Checks

After publishing, verify in this order:

1. The GitHub Release is marked as a prerelease, not a stable release.
2. The Release page shows the Android APK, macOS notarized DMG, and matching checksum files.
3. The checksum files match local `shasum -a 256` output.
4. The Release body keeps the beta positioning, iOS App Store / TestFlight acquisition path, Android / macOS sideload notes, and macOS permission guidance.
5. The tag points at the intended release commit, not a temporary local commit.
6. If GitHub Actions skipped builds because of the runner Xcode version, rerun the release note verification commands locally before publishing.
7. Download the GitHub asset once after publishing, mount the DMG, and confirm the app bundle version matches the release tag.
8. Run `spctl --assess --type install --verbose=4 <dmg>` on the downloaded DMG and confirm Gatekeeper accepts it.

## macOS Local Packaging

Generate a local macOS Release zip:

```sh
script/package_macos_release.sh
```

The script runs a Release build, verifies code signing, runs Gatekeeper assessment, and prints the SHA-256 checksum.

0.1.1 generates a development testing package by default:

- File name: `TypeCarrierMac-0.1.1-2-development.zip`.
- Signing: Apple Development / Personal Team.
- Gatekeeper assessment may fail. The script prints a warning, but this is not treated as a packaging failure for the 0.1 development package.

## Future Official macOS Package

The public repository must not store real signing material. A local Developer ID notarized build requires signing configuration such as:

```xcconfig
TYPECARRIER_BUNDLE_PREFIX = ak22ak.typecarrier
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_STYLE[sdk=macosx*] = Manual
CODE_SIGN_IDENTITY[sdk=macosx*] = Developer ID Application
```

Then run:

```sh
APPLE_TEAM_ID=YOURTEAMID \
NOTARYTOOL_KEYCHAIN_PROFILE=typecarrier-notary \
script/package_macos_developer_id_dmg.sh
```

The script archives the app, creates a DMG, signs the DMG, submits notarization, staples the ticket, and verifies the final package with `spctl --assess`.

## GitHub Actions Signing

The release workflow automatically builds the Android APK and macOS Developer ID notarized DMG. The official macOS DMG uses a protected GitHub Environment: `release-signing`. Do not store signing Secrets as regular repository secrets. Store them as `release-signing` environment secrets, and configure Required reviewers for the environment.

The `release-signing` environment requires these Secrets:

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 content of the Developer ID Application `.p12` certificate |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_TEAM_ID` | Apple Developer Team ID, for example `4H8462MSN6` |
| `APPSTORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Issuer ID for a Team API Key; leave empty for an Individual API Key |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | Full text of the App Store Connect API `.p8` private key |

Create the API Key in App Store Connect under `Users and Access` -> `Integrations`. Use it for CI notarization. Do not store an Apple ID password or app-specific password in the repository.

To export the Developer ID `.p12`, use Keychain Access, select the `Developer ID Application` certificate and its private key, export them as `.p12`, and set a strong password. Convert it for GitHub Secrets locally:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

The release workflow creates a temporary keychain on the macOS runner, imports the certificate, runs `script/package_macos_developer_id_dmg.sh`, and uploads the DMG plus `.sha256` to the draft prerelease. Because the job is bound to the `release-signing` environment, signing material is exposed to the runner only after the environment is approved.

The release workflow pins the runner to `macos-26` to avoid receiving an incompatible Xcode version during `macos-latest` migrations.

## GitHub Actions

Public CI verifies source, tests, and builds. The release workflow creates a GitHub prerelease draft, uploads the Android APK, and uploads the macOS notarized DMG.

Signing private keys and App Store Connect keys in `release-signing` Environment Secrets must only be used by the controlled release workflow. Do not print them in pull request workflows, logs, release notes, or repository files.
