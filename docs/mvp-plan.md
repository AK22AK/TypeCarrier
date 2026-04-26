# MVP Plan

## MVP Definition

The MVP is successful when:

1. The iPhone app accepts text from any keyboard.
2. The iPhone app can send the current text to the Mac app.
3. The Mac app receives the text while running in the menu bar.
4. The Mac app inserts the text into the currently focused input field.
5. The flow works repeatedly with low friction.

## Phase 1: Local Prototype

Build the smallest working end-to-end loop.

- Create iOS SwiftUI app with a large text editor and send button.
- Create macOS menu bar app.
- Establish local device discovery and connection.
- Send plain text payloads from iOS to Mac.
- On Mac, write payload to clipboard and simulate paste.
- Show simple connection and send status.

## Phase 2: Usability Hardening

Make it reliable enough for daily self-use.

- Add first-run permission guidance for macOS Accessibility.
- Add reconnect behavior.
- Add send failure retry.
- Preserve and restore previous clipboard where practical.
- Add a "paste manually instead" fallback mode.
- Add configurable behavior after send: clear text, keep text, or select all.

## Phase 3: Productization Candidates

Only consider these after the core loop feels good.

- QR pairing.
- Paired device list.
- Lightweight send history.
- Local encryption review.
- Optional internet relay.
- Android/Windows exploration.
- iOS widgets or Shortcuts actions.

## Deliberately Deferred

- AI transcription.
- AI rewriting.
- File transfer.
- Clipboard manager UI.
- Team use.
- Cloud accounts.

## Open Questions

- Should send always auto-paste, or should the Mac app support a "receive to clipboard only" mode?
- Should the iOS text buffer clear automatically after successful paste?
- Should the app restore the previous Mac clipboard by default?
- How visible should the macOS menu bar UI be during normal use?
- Should there be a keyboard shortcut on iOS hardware keyboards to send?

