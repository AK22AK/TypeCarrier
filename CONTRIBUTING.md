# Contributing

TypeCarrier is early-stage prototype software. Small, focused changes are easier
to review than broad rewrites.

## Workflow

Use pull requests for feature work, behavior changes, release configuration,
permissions, transport logic, and paste behavior. Keep `master` buildable.

Small documentation fixes may be committed directly by maintainers.

Before opening a pull request:

- Run `xcodegen generate`.
- Run the core tests.
- Build the iOS and macOS targets when your change touches app code.
- Do not commit personal signing files, Xcode user state, certificates, or
  provisioning profiles.

Public contributions are submitted under the Apache License 2.0.
