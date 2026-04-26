# TypeCarrier

TypeCarrier is a lightweight iPhone-to-Mac text carrier.

The first version focuses on one workflow:

> Type or dictate text on iPhone, tap send, and have the text inserted at the current Mac cursor.

This project is intentionally not a speech recognition product. It assumes the user already prefers an input method on the phone, such as Doubao keyboard dictation, and only solves the cross-device text delivery and paste step.

## Initial Scope

- iOS app: a focused text input surface with a send action.
- macOS app: a menu bar receiver that inserts received text into the current focused input.
- Transport: local Apple-device communication first, preferably no account and no server.
- Primary platform: iPhone and Mac.
- Primary user: a developer or heavy computer user who prefers phone dictation but wants text to land directly on the Mac.

## Documents

- [Idea](docs/idea.md)
- [Design Goals](docs/design-goals.md)
- [Competitive Analysis](docs/competitive-analysis.md)
- [Technical Notes](docs/technical-notes.md)
- [MVP Plan](docs/mvp-plan.md)

