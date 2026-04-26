# Technical Notes

## Recommended MVP Architecture

TypeCarrier should start as two native apps:

- iOS app: SwiftUI text input surface.
- macOS app: menu bar receiver using SwiftUI/AppKit integration.

The first transport should be local Apple-device communication. The most likely option is `MultipeerConnectivity`, because it is designed for nearby Apple devices and can work over Wi-Fi, peer-to-peer Wi-Fi, and Bluetooth.

## Data Flow

1. iOS app has an editable text buffer.
2. User dictates or types using any iOS keyboard.
3. User taps send.
4. iOS app sends a small text payload to the paired Mac.
5. Mac app receives the payload.
6. Mac app temporarily writes the text to `NSPasteboard`.
7. Mac app simulates `Command + V` into the currently focused app.
8. Mac app optionally restores the previous clipboard contents.
9. iOS app shows success and clears the input buffer.

## macOS Permissions

Automatic paste into the current focused input likely requires Accessibility permission, because the Mac app needs to synthesize keyboard events.

Expected permission:

- Accessibility permission for posting keyboard events.

Possible APIs:

- `NSPasteboard` for clipboard write and restore.
- `CGEvent` / `CGEventPost` for simulating `Command + V`.

## Pairing

Candidate pairing methods:

- QR code shown on Mac and scanned by iPhone.
- Nearby browser with manual device selection.
- Manual code entry as fallback.

For the first prototype, nearby discovery may be enough. QR pairing is better before sharing with others.

## Transport Options

### Local Network / Nearby First

Pros:

- No server.
- No account.
- Better privacy.
- Lower cost.
- Fits the likely usage context.

Cons:

- Can fail on restricted Wi-Fi networks.
- Requires local network permissions.
- Device discovery can be less predictable in corporate or public networks.

### Internet Relay Later

Options:

- CloudKit.
- WebSocket relay.
- Firebase/Supabase/Pusher-style realtime service.

Pros:

- Works when devices are not nearby or on the same network.
- Easier to provide persistent pairing across networks.

Cons:

- Requires authentication or pairing security.
- Requires more operational complexity.
- Introduces privacy and data handling questions.
- Not necessary for the first self-use prototype.

## Risks

- Some Mac fields may reject paste or keyboard event injection.
- Secure input fields and password fields should not be targeted.
- Clipboard restore may fail for rich clipboard contents or owner-provided pasteboard data.
- Multipeer discovery may be unreliable on some networks.
- iOS cannot programmatically control Doubao keyboard dictation; the user must use it normally inside the text field.

## Security and Privacy

For MVP:

- Keep transfer local.
- Send plain text only between paired devices.
- Avoid cloud storage.
- Avoid retaining history by default.

Before productization:

- Add pairing trust.
- Add basic encryption expectations around the transport.
- Consider opt-in history only.
- Make clipboard handling explicit in onboarding.

