# Design Goals

## Primary Goal

Make the following workflow feel immediate:

> iPhone text input -> send -> Mac current cursor receives the text.

The product should reduce the current manual flow from several gestures to one tap.

## User Experience Goals

- The iPhone app should open directly into a large editable text area.
- The send action should be obvious and reachable.
- After a successful send, the iPhone text field can clear automatically.
- The Mac app should live quietly in the menu bar.
- The Mac app should not require the user to switch windows.
- The received text should be inserted into the currently focused Mac input field.
- Connection state should be understandable: connected, searching, failed, sent.
- The tool should support repeated short bursts of text without ceremony.

## Non-Goals for the First Version

- No built-in speech recognition.
- No AI rewriting or formatting.
- No clipboard history manager.
- No file, image, or link transfer.
- No account system.
- No internet relay.
- No Windows or Android support.
- No multi-user collaboration.
- No complex device fleet management.

## Product Principles

- Local first: prefer nearby device communication without a server.
- Fast path first: optimize the one-tap send and paste path before adding features.
- Minimal interface: avoid turning this into a general productivity dashboard.
- Predictable behavior: the user should know where the text went and whether it arrived.
- Respect the Mac clipboard: if the paste implementation temporarily replaces clipboard contents, preserve and restore the previous clipboard where practical.

