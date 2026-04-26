# v0 Prototype Notes

## Current Status

The first native TypeCarrier prototype is wired end to end:

- `TypeCarrieriOS` provides the iPhone text input and send surface.
- `TypeCarrierMac` runs as a menu bar receiver with a debug window.
- `TypeCarrierCore` shares payload, envelope, connection state, and Multipeer transport code.

Manual testing confirmed the core workflow:

> iPhone input -> local Multipeer send -> Mac receive -> paste into current cursor.

## Local Development

Generate the Xcode project from the root:

```sh
xcodegen generate
```

Open `TypeCarrier.xcodeproj` in Xcode. The main schemes are:

- `TypeCarrieriOS`
- `TypeCarrierMac`
- `TypeCarrierCore`

Run the Mac menu bar app from the command line:

```sh
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm the app process exists.

## First Manual Test Path

1. Start `TypeCarrierMac` on the Mac.
2. Open its menu bar item and choose `Request Accessibility`.
3. Enable Accessibility permission for the Mac app.
4. Connect the Mac to the iPhone hotspot.
5. Run `TypeCarrieriOS` on the iPhone.
6. Put the Mac cursor in a text field.
7. Type or dictate text on iPhone, then tap Send.

## Known v0 Limits

- Auto-connects to the first discovered Mac peer.
- No pairing code or trusted device list yet.
- No retry queue.
- Clipboard restoration only handles plain string contents.
- No receive-to-clipboard-only mode.
