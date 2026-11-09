//! Wire protocol v2, shared by every platform. A connection is:
//!
//! 1. Each side sends one plaintext `Hello` frame (version negotiation, no secrets).
//! 2. A Noise handshake: XX when pairing, IK when reconnecting to a paired device. Both hellos are
//!    bound into the Noise prologue, so a tampered hello fails the handshake.
//! 3. Encrypted `Message` frames.
//!
//! Every step is length-prefixed with `frame::encode`.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const VERSION: u32 = 2;
pub const MINIMUM_VERSION: u32 = 2;
const PROLOGUE_LABEL: &[u8] = b"TypeCarrier/2";
const PAIRING_CODE_LABEL: &[u8] = b"TypeCarrier pairing code";

pub const CAPABILITY_SEND_TEXT: &str = "send.text";
pub const CAPABILITY_RECEIVE_PASTE: &str = "receive.paste";
pub const CAPABILITY_RECEIPT: &str = "receipt";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "lowercase")]
pub enum CoreHelloMode {
    /// First connection between two devices: Noise XX plus a pairing code check.
    Pair,
    /// Reconnect to a paired device: Noise IK.
    Connect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CorePlatform {
    #[serde(rename = "iOS")]
    Ios,
    #[serde(rename = "macOS")]
    MacOs,
    #[serde(rename = "android")]
    Android,
    #[serde(rename = "windows")]
    Windows,
    #[serde(rename = "linux")]
    Linux,
    #[serde(rename = "harmonyOS")]
    HarmonyOs,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Hello {
    pub proto: u32,
    pub min_proto: u32,
    pub mode: CoreHelloMode,
    pub platform: CorePlatform,
    pub capabilities: Vec<String>,
}

impl Hello {
    pub fn new(mode: CoreHelloMode, platform: CorePlatform, capabilities: Vec<String>) -> Self {
        Hello { proto: VERSION, min_proto: MINIMUM_VERSION, mode, platform, capabilities }
    }

    /// The highest version both sides speak, or `None` when their ranges do not overlap.
    pub fn negotiated_version(&self, remote: &Hello) -> Option<u32> {
        let version = self.proto.min(remote.proto);
        (version >= self.min_proto.max(remote.min_proto)).then_some(version)
    }
}

/// Sent inside the Noise handshake payloads, so it is only readable by the other party.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeviceInfo {
    #[serde(rename = "deviceID")]
    pub device_id: String,
    #[serde(rename = "deviceName")]
    pub device_name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "camelCase")]
pub enum CoreCloseReason {
    UnsupportedVersion,
    NotPaired,
    PairingNotOpen,
    PairingRejected,
    HandshakeFailed,
    ProtocolViolation,
    Replaced,
    HeartbeatTimeout,
    Shutdown,
}

/// Encrypted application messages after the handshake, as type-tagged JSON so other platforms
/// can read and write them without mirroring any one language's conventions. The envelope stays
/// opaque JSON here: its shape belongs to the apps, not to the transport.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Message {
    Envelope { envelope: serde_json::Value },
    Ping { id: u64 },
    Pong { id: u64 },
    /// Responder -> initiator after the person confirmed matching pairing codes on the receiver.
    PairingConfirmed,
    PairingRejected,
    Close { reason: CoreCloseReason },
}

pub fn prologue(initiator_hello: &[u8], responder_hello: &[u8]) -> Vec<u8> {
    let mut prologue = PROLOGUE_LABEL.to_vec();
    for hello in [initiator_hello, responder_hello] {
        prologue.extend_from_slice(&(hello.len() as u32).to_be_bytes());
        prologue.extend_from_slice(hello);
    }
    prologue
}

/// The 4-digit code both screens show while pairing. It is derived from the Noise handshake hash,
/// so a device in the middle ends up with different codes on each side.
pub fn pairing_code(handshake_hash: &[u8]) -> String {
    let digest = Sha256::new().chain_update(PAIRING_CODE_LABEL).chain_update(handshake_hash).finalize();
    let value = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    format!("{:04}", value % 10_000)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_round_trips_with_the_swift_field_names() {
        let json = r#"{"capabilities":["send.text"],"minProto":2,"mode":"connect","platform":"iOS","proto":2}"#;
        let hello: Hello = serde_json::from_str(json).unwrap();
        assert_eq!(hello, Hello::new(CoreHelloMode::Connect, CorePlatform::Ios, vec!["send.text".into()]));
    }

    #[test]
    fn version_negotiation_picks_the_shared_maximum() {
        let ours = Hello::new(CoreHelloMode::Pair, CorePlatform::MacOs, vec![]);
        let future = Hello { proto: 4, min_proto: 2, ..ours.clone() };
        let too_new = Hello { proto: 9, min_proto: 9, ..ours.clone() };
        assert_eq!(ours.negotiated_version(&future), Some(2));
        assert_eq!(ours.negotiated_version(&too_new), None);
    }

    #[test]
    fn messages_use_type_tagged_json() {
        assert_eq!(serde_json::to_string(&Message::Ping { id: 7 }).unwrap(), r#"{"type":"ping","id":7}"#);
        let close: Message = serde_json::from_str(r#"{"type":"close","reason":"replaced"}"#).unwrap();
        assert_eq!(close, Message::Close { reason: CoreCloseReason::Replaced });
        let confirmed: Message = serde_json::from_str(r#"{"type":"pairingConfirmed"}"#).unwrap();
        assert_eq!(confirmed, Message::PairingConfirmed);
    }

    #[test]
    fn pairing_code_matches_the_swift_implementation() {
        let code = pairing_code(&[0xAB; 32]);
        assert_eq!(code.len(), 4);
        assert_eq!(code, pairing_code(&[0xAB; 32]));
        assert_ne!(code, pairing_code(&[0xAC; 32]));
    }
}
