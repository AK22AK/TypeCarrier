# Open Source and Official Builds

TypeCarrier uses an open-core-free model for source code: the code is public and
can be studied, modified, and self-built under the Apache License 2.0.

Official builds may still be paid on app stores. A small one-time purchase for
the iOS, macOS, or future Android app is a distribution and support choice, not
a restriction on reading or building the source code.

## Policy

- Source code is open under Apache License 2.0.
- Users may self-build the app from source.
- Official store builds may be paid.
- Official signing certificates, provisioning profiles, App Store Connect keys,
  and release metadata are not stored in this repository.
- Forks should use their own app name, bundle identifiers, icons, and store
  listings unless explicit permission is granted.
- Android should follow the same model if it is added later: source available,
  official store build may be paid.

## Why This Model

The value of the official build is convenience, trusted signing, store updates,
and support for continued development. The value of the open repository is
transparency, auditability, learning, and community contribution.

## What Not To Commit

- Apple Developer Team IDs for official releases.
- Provisioning profiles or certificates.
- App Store Connect API keys.
- Private release notes or unreleased store metadata.
- Personal Xcode user state files.
- Local signing override files such as `Configs/Signing.local.xcconfig`.
