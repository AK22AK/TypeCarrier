//! Protocol logic for one v2 connection, independent of sockets and clocks so every platform can
//! run it over its own networking. Feed it received bytes and timer ticks; it returns the bytes to
//! write and what happened.

use std::sync::{Arc, Mutex};

use snow::{Builder, HandshakeState, TransportState};

use crate::frame;
use crate::protocol::{self, CoreCloseReason, DeviceInfo, Hello, CoreHelloMode, Message, CorePlatform};

pub const PING_INTERVAL_MS: u64 = 10_000;
pub const PEER_SILENCE_TIMEOUT_MS: u64 = 25_000;
const NOISE_MAX_MESSAGE: usize = 65_535;

/// A device's long-term identity: its Noise static key plus what it tells paired peers about itself.
#[derive(Debug, Clone, uniffi::Record)]
pub struct CoreIdentity {
    pub static_private_key: Vec<u8>,
    pub device_id: String,
    pub device_name: String,
    pub platform: CorePlatform,
    pub capabilities: Vec<String>,
}

/// The other end of a session.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CorePeer {
    pub device_id: String,
    pub device_name: String,
    pub public_key: Vec<u8>,
    pub platform: CorePlatform,
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum CoreSessionEvent {
    /// Bytes to write to the connection, already framed.
    Write { bytes: Vec<u8> },
    /// Pairing only: show this code. The receiver then calls `confirm_pairing` or `reject_pairing`;
    /// the sender waits for that answer.
    PairingCodeReady { code: String, peer: CorePeer },
    /// The session is ready for messages. For a pairing, the app stores `peer.public_key` now.
    Established { peer: CorePeer },
    /// An application envelope, as the JSON the sender wrote.
    Received { envelope_json: String },
    /// The session is over; close the connection after writing any preceding `Write` events.
    Closed { reason: CoreCloseReason },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum CoreRole {
    /// Opens the connection (the sender). `Connect` needs the paired receiver's public key.
    Initiator { mode: CoreHelloMode, remote_static_key: Option<Vec<u8>> },
    /// Accepts connections (the receiver).
    Responder,
}

/// Answers the receiver's two questions about an incoming connection.
#[uniffi::export(with_foreign)]
pub trait CoreResponderPolicy: Send + Sync {
    /// Whether a reconnecting device's public key is paired.
    fn is_trusted(&self, public_key: Vec<u8>) -> bool;
    /// Whether the person opened pairing on this device (and no other pairing is in progress).
    fn is_pairing_open(&self) -> bool;
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreSessionError {
    #[error("not connected")]
    NotConnected,
    #[error("message too large")]
    MessageTooLarge,
    #[error("invalid envelope JSON")]
    InvalidEnvelope,
    #[error("invalid key")]
    InvalidKey,
}

#[derive(uniffi::Object)]
pub struct CoreSession {
    core: Mutex<Core>,
}

#[uniffi::export]
impl CoreSession {
    #[uniffi::constructor]
    pub fn new(role: CoreRole, identity: CoreIdentity, now_ms: u64, policy: Option<Arc<dyn CoreResponderPolicy>>) -> Arc<Self> {
        Arc::new(CoreSession { core: Mutex::new(Core::new(role, identity, now_ms, policy, None)) })
    }

    /// The initiator speaks first; the responder waits for its hello.
    pub fn start(&self) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().start()
    }

    pub fn receive(&self, bytes: Vec<u8>, now_ms: u64) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().receive(&bytes, now_ms)
    }

    pub fn send_envelope(&self, envelope_json: String) -> Result<Vec<CoreSessionEvent>, CoreSessionError> {
        let envelope = serde_json::from_str(&envelope_json).map_err(|_| CoreSessionError::InvalidEnvelope)?;
        self.core.lock().unwrap().send(Message::Envelope { envelope })
    }

    /// Receiver: the person saw the same code on both screens.
    pub fn confirm_pairing(&self) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().confirm_pairing()
    }

    pub fn reject_pairing(&self) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().reject_pairing()
    }

    /// Call every few seconds. Sends heartbeats and detects a silent peer.
    pub fn tick(&self, now_ms: u64) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().tick(now_ms)
    }

    pub fn shutdown(&self) -> Vec<CoreSessionEvent> {
        self.core.lock().unwrap().shutdown()
    }

    pub fn is_established(&self) -> bool {
        matches!(self.core.lock().unwrap().state, State::Established { .. })
    }

    pub fn is_closed(&self) -> bool {
        matches!(self.core.lock().unwrap().state, State::Closed)
    }

    pub fn peer(&self) -> Option<CorePeer> {
        self.core.lock().unwrap().peer()
    }
}

/// A new long-term Noise private key.
#[uniffi::export]
pub fn generate_static_private_key() -> Vec<u8> {
    Builder::new(noise_params(CoreHelloMode::Pair)).generate_keypair().expect("default resolver generates keys").private
}

#[uniffi::export]
pub fn public_key_for(static_private_key: Vec<u8>) -> Result<Vec<u8>, CoreSessionError> {
    let secret: [u8; 32] = static_private_key.try_into().map_err(|_| CoreSessionError::InvalidKey)?;
    Ok(x25519_public_key(secret).to_vec())
}

fn x25519_public_key(secret: [u8; 32]) -> [u8; 32] {
    // X25519(secret, 9), via a throwaway Noise handshake would be roundabout; snow's resolver does
    // not expose the scalar multiplication, so use the same curve implementation it depends on.
    x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from(secret)).to_bytes()
}

fn noise_params(mode: CoreHelloMode) -> snow::params::NoiseParams {
    match mode {
        CoreHelloMode::Pair => "Noise_XX_25519_ChaChaPoly_SHA256",
        CoreHelloMode::Connect => "Noise_IK_25519_ChaChaPoly_SHA256",
    }
    .parse()
    .expect("valid Noise pattern")
}

enum State {
    AwaitingHello,
    Handshaking(Box<HandshakeState>),
    AwaitingPairingDecision { transport: Box<TransportState>, peer: CorePeer },
    Established { transport: Box<TransportState>, peer: CorePeer },
    Closed,
}

enum Failure {
    Close(CoreCloseReason),
    /// Bad ciphertext or keys; never reported to the peer once established.
    Crypto,
}

impl From<CoreCloseReason> for Failure {
    fn from(reason: CoreCloseReason) -> Self {
        Failure::Close(reason)
    }
}

pub(crate) struct Core {
    role: CoreRole,
    identity: CoreIdentity,
    policy: Option<Arc<dyn CoreResponderPolicy>>,
    state: State,
    buffer: Vec<u8>,
    local_hello: Option<Vec<u8>>,
    remote_hello: Option<Hello>,
    /// The peer's info from whichever handshake message carried it. In XX the initiator finishes on
    /// its own write, so message 2's payload has to be kept until then.
    remote_info: Option<DeviceInfo>,
    mode: Option<CoreHelloMode>,
    last_received_ms: u64,
    last_ping_ms: Option<u64>,
    next_ping_id: u64,
    /// Deterministic ephemeral key for tests only.
    fixed_ephemeral: Option<Vec<u8>>,
}

impl Core {
    pub(crate) fn new(
        role: CoreRole,
        identity: CoreIdentity,
        now_ms: u64,
        policy: Option<Arc<dyn CoreResponderPolicy>>,
        fixed_ephemeral: Option<Vec<u8>>,
    ) -> Self {
        Core {
            role,
            identity,
            policy,
            state: State::AwaitingHello,
            buffer: Vec::new(),
            local_hello: None,
            remote_hello: None,
            remote_info: None,
            mode: None,
            last_received_ms: now_ms,
            last_ping_ms: None,
            next_ping_id: 1,
            fixed_ephemeral,
        }
    }

    fn peer(&self) -> Option<CorePeer> {
        match &self.state {
            State::Established { peer, .. } | State::AwaitingPairingDecision { peer, .. } => Some(peer.clone()),
            _ => None,
        }
    }

    pub(crate) fn start(&mut self) -> Vec<CoreSessionEvent> {
        match self.role.clone() {
            CoreRole::Initiator { mode, .. } => self.send_hello(mode),
            CoreRole::Responder => Vec::new(),
        }
    }

    pub(crate) fn receive(&mut self, bytes: &[u8], now_ms: u64) -> Vec<CoreSessionEvent> {
        if matches!(self.state, State::Closed) {
            return Vec::new();
        }
        self.last_received_ms = now_ms;
        self.buffer.extend_from_slice(bytes);
        let mut events = Vec::new();
        loop {
            if matches!(self.state, State::Closed) {
                break;
            }
            let frame = match frame::next_payload(&mut self.buffer) {
                Ok(Some(frame)) => frame,
                Ok(None) => break,
                Err(_) => {
                    events.extend(self.close(CoreCloseReason::ProtocolViolation, true));
                    break;
                }
            };
            match self.handle(&frame) {
                Ok(produced) => events.extend(produced),
                Err(Failure::Close(reason)) => {
                    events.extend(self.close(reason, true));
                    break;
                }
                Err(Failure::Crypto) => {
                    let notify = !matches!(self.state, State::Established { .. });
                    events.extend(self.close(CoreCloseReason::HandshakeFailed, notify));
                    break;
                }
            }
        }
        events
    }

    pub(crate) fn send(&mut self, message: Message) -> Result<Vec<CoreSessionEvent>, CoreSessionError> {
        if !matches!(self.state, State::Established { .. }) {
            return Err(CoreSessionError::NotConnected);
        }
        self.encrypted(&message)
    }

    pub(crate) fn confirm_pairing(&mut self) -> Vec<CoreSessionEvent> {
        let State::AwaitingPairingDecision { transport, peer } = std::mem::replace(&mut self.state, State::Closed) else {
            return Vec::new();
        };
        self.state = State::Established { transport, peer: peer.clone() };
        match self.encrypted(&Message::PairingConfirmed) {
            Ok(mut events) => {
                events.push(CoreSessionEvent::Established { peer });
                events
            }
            Err(_) => self.close(CoreCloseReason::ProtocolViolation, false),
        }
    }

    pub(crate) fn reject_pairing(&mut self) -> Vec<CoreSessionEvent> {
        if !matches!(self.state, State::AwaitingPairingDecision { .. }) {
            return Vec::new();
        }
        let mut events = self.encrypted(&Message::PairingRejected).unwrap_or_default();
        self.state = State::Closed;
        events.push(CoreSessionEvent::Closed { reason: CoreCloseReason::PairingRejected });
        events
    }

    pub(crate) fn tick(&mut self, now_ms: u64) -> Vec<CoreSessionEvent> {
        if !matches!(self.state, State::Established { .. }) {
            return Vec::new();
        }
        if now_ms.saturating_sub(self.last_received_ms) >= PEER_SILENCE_TIMEOUT_MS {
            return self.close(CoreCloseReason::HeartbeatTimeout, false);
        }
        let last_activity = self.last_received_ms.max(self.last_ping_ms.unwrap_or(0));
        if now_ms.saturating_sub(last_activity) < PING_INTERVAL_MS {
            return Vec::new();
        }
        self.last_ping_ms = Some(now_ms);
        let id = self.next_ping_id;
        self.next_ping_id += 1;
        self.encrypted(&Message::Ping { id }).unwrap_or_default()
    }

    pub(crate) fn shutdown(&mut self) -> Vec<CoreSessionEvent> {
        if matches!(self.state, State::Closed) {
            return Vec::new();
        }
        self.close(CoreCloseReason::Shutdown, true)
    }

    // MARK: Frames

    fn handle(&mut self, frame: &[u8]) -> Result<Vec<CoreSessionEvent>, Failure> {
        match &self.state {
            State::AwaitingHello => self.handle_hello(frame),
            State::Handshaking(_) => {
                if let Some(reason) = plaintext_close(frame) {
                    self.state = State::Closed;
                    return Ok(vec![CoreSessionEvent::Closed { reason }]);
                }
                self.handle_handshake(frame)
            }
            State::AwaitingPairingDecision { .. } => {
                let message = self.decrypt(frame)?;
                self.handle_pairing_decision(message)
            }
            State::Established { .. } => {
                let message = self.decrypt(frame)?;
                self.handle_established(message)
            }
            State::Closed => Ok(Vec::new()),
        }
    }

    fn handle_hello(&mut self, frame: &[u8]) -> Result<Vec<CoreSessionEvent>, Failure> {
        if let Some(reason) = plaintext_close(frame) {
            self.state = State::Closed;
            return Ok(vec![CoreSessionEvent::Closed { reason }]);
        }
        let hello: Hello = serde_json::from_slice(frame).map_err(|_| CoreCloseReason::ProtocolViolation)?;
        self.remote_hello = Some(hello.clone());

        match self.role.clone() {
            CoreRole::Initiator { mode, remote_static_key } => {
                let local_bytes = self.local_hello.clone().ok_or(CoreCloseReason::ProtocolViolation)?;
                let local: Hello = serde_json::from_slice(&local_bytes).map_err(|_| CoreCloseReason::ProtocolViolation)?;
                local.negotiated_version(&hello).ok_or(CoreCloseReason::UnsupportedVersion)?;
                let prologue = protocol::prologue(&local_bytes, frame);
                let mut handshake = self.build_handshake(mode, true, &prologue, remote_static_key.as_deref())?;
                let payload = match mode {
                    CoreHelloMode::Pair => Vec::new(),
                    CoreHelloMode::Connect => self.device_info_json(),
                };
                let message = write_handshake(&mut handshake, &payload)?;
                self.mode = Some(mode);
                self.state = State::Handshaking(Box::new(handshake));
                Ok(vec![write_event(&message)?])
            }
            CoreRole::Responder => {
                let events = self.send_hello(hello.mode);
                if matches!(self.state, State::Closed) {
                    return Ok(events);
                }
                let local_bytes = self.local_hello.clone().ok_or(CoreCloseReason::ProtocolViolation)?;
                let local: Hello = serde_json::from_slice(&local_bytes).map_err(|_| CoreCloseReason::ProtocolViolation)?;
                local.negotiated_version(&hello).ok_or(CoreCloseReason::UnsupportedVersion)?;
                if hello.mode == CoreHelloMode::Pair && !self.policy.as_ref().is_some_and(|p| p.is_pairing_open()) {
                    return Err(CoreCloseReason::PairingNotOpen.into());
                }
                let prologue = protocol::prologue(frame, &local_bytes);
                let handshake = self.build_handshake(hello.mode, false, &prologue, None)?;
                self.mode = Some(hello.mode);
                self.state = State::Handshaking(Box::new(handshake));
                Ok(events)
            }
        }
    }

    fn handle_handshake(&mut self, frame: &[u8]) -> Result<Vec<CoreSessionEvent>, Failure> {
        let State::Handshaking(mut handshake) = std::mem::replace(&mut self.state, State::Closed) else {
            return Err(CoreCloseReason::ProtocolViolation.into());
        };
        let mut events = match self.advance_handshake(&mut handshake, frame) {
            Ok(events) => events,
            Err(failure) => {
                // Keep the handshake state so the close notice goes out in plaintext.
                self.state = State::Handshaking(handshake);
                return Err(failure);
            }
        };
        if !handshake.is_handshake_finished() {
            self.state = State::Handshaking(handshake);
            return Ok(events);
        }

        let hash = handshake.get_handshake_hash().to_vec();
        let remote_key = handshake.get_remote_static().map(<[u8]>::to_vec);
        let (Some(remote_key), Some(info), Some(hello)) = (remote_key, self.remote_info.clone(), self.remote_hello.clone()) else {
            self.state = State::Handshaking(handshake);
            return Err(CoreCloseReason::ProtocolViolation.into());
        };
        let transport = Box::new(handshake.into_transport_mode().map_err(|_| Failure::Crypto)?);
        let peer = CorePeer {
            device_id: info.device_id,
            device_name: info.device_name,
            public_key: remote_key,
            platform: hello.platform,
            capabilities: hello.capabilities,
        };
        if self.mode == Some(CoreHelloMode::Pair) {
            events.push(CoreSessionEvent::PairingCodeReady { code: protocol::pairing_code(&hash), peer: peer.clone() });
            self.state = State::AwaitingPairingDecision { transport, peer };
        } else {
            events.push(CoreSessionEvent::Established { peer: peer.clone() });
            self.state = State::Established { transport, peer };
        }
        Ok(events)
    }

    /// Reads one handshake message and writes the reply when it is our turn.
    fn advance_handshake(&mut self, handshake: &mut HandshakeState, frame: &[u8]) -> Result<Vec<CoreSessionEvent>, Failure> {
        let mut payload = vec![0u8; NOISE_MAX_MESSAGE];
        let length = handshake.read_message(frame, &mut payload).map_err(|_| Failure::Crypto)?;
        if length > 0 {
            let info: DeviceInfo = serde_json::from_slice(&payload[..length]).map_err(|_| CoreCloseReason::ProtocolViolation)?;
            self.remote_info = Some(info);
        }

        // IK responder: the first message revealed who is connecting.
        if self.role == CoreRole::Responder && self.mode == Some(CoreHelloMode::Connect) {
            let key = handshake.get_remote_static().ok_or(Failure::Crypto)?.to_vec();
            if !self.policy.as_ref().is_some_and(|p| p.is_trusted(key)) {
                return Err(CoreCloseReason::NotPaired.into());
            }
        }

        let mut events = Vec::new();
        if !handshake.is_handshake_finished() && handshake.is_my_turn() {
            let message = write_handshake(handshake, &self.device_info_json())?;
            events.push(write_event(&message)?);
        }
        Ok(events)
    }

    fn handle_pairing_decision(&mut self, message: Message) -> Result<Vec<CoreSessionEvent>, Failure> {
        if self.role == CoreRole::Responder {
            return Err(CoreCloseReason::ProtocolViolation.into());
        }
        match message {
            Message::PairingConfirmed => {
                let State::AwaitingPairingDecision { transport, peer } = std::mem::replace(&mut self.state, State::Closed) else {
                    return Err(CoreCloseReason::ProtocolViolation.into());
                };
                self.state = State::Established { transport, peer: peer.clone() };
                Ok(vec![CoreSessionEvent::Established { peer }])
            }
            Message::PairingRejected => {
                self.state = State::Closed;
                Ok(vec![CoreSessionEvent::Closed { reason: CoreCloseReason::PairingRejected }])
            }
            Message::Close { reason } => {
                self.state = State::Closed;
                Ok(vec![CoreSessionEvent::Closed { reason }])
            }
            _ => Err(CoreCloseReason::ProtocolViolation.into()),
        }
    }

    fn handle_established(&mut self, message: Message) -> Result<Vec<CoreSessionEvent>, Failure> {
        match message {
            Message::Envelope { envelope } => Ok(vec![CoreSessionEvent::Received { envelope_json: envelope.to_string() }]),
            Message::Ping { id } => self.encrypted(&Message::Pong { id }).map_err(|_| CoreCloseReason::ProtocolViolation.into()),
            Message::Pong { .. } => Ok(Vec::new()),
            Message::Close { reason } => {
                self.state = State::Closed;
                Ok(vec![CoreSessionEvent::Closed { reason }])
            }
            Message::PairingConfirmed | Message::PairingRejected => Err(CoreCloseReason::ProtocolViolation.into()),
        }
    }

    // MARK: Helpers

    fn build_handshake(
        &self,
        mode: CoreHelloMode,
        initiator: bool,
        prologue: &[u8],
        remote_static_key: Option<&[u8]>,
    ) -> Result<HandshakeState, Failure> {
        let mut builder = Builder::new(noise_params(mode))
            .local_private_key(&self.identity.static_private_key)
            .map_err(|_| Failure::Crypto)?
            .prologue(prologue)
            .map_err(|_| Failure::Crypto)?;
        if let Some(key) = remote_static_key {
            builder = builder.remote_public_key(key).map_err(|_| Failure::Crypto)?;
        } else if initiator && mode == CoreHelloMode::Connect {
            return Err(Failure::Crypto);
        }
        if let Some(ephemeral) = &self.fixed_ephemeral {
            builder = builder.fixed_ephemeral_key_for_testing_only(ephemeral);
        }
        let handshake = if initiator { builder.build_initiator() } else { builder.build_responder() };
        handshake.map_err(|_| Failure::Crypto)
    }

    fn device_info_json(&self) -> Vec<u8> {
        serde_json::to_vec(&DeviceInfo {
            device_id: self.identity.device_id.clone(),
            device_name: self.identity.device_name.clone(),
        })
        .expect("device info serializes")
    }

    fn send_hello(&mut self, mode: CoreHelloMode) -> Vec<CoreSessionEvent> {
        let hello = Hello::new(mode, self.identity.platform, self.identity.capabilities.clone());
        let bytes = serde_json::to_vec(&hello).expect("hello serializes");
        let Ok(frame) = frame::encode(&bytes) else {
            return self.close(CoreCloseReason::ProtocolViolation, false);
        };
        self.local_hello = Some(bytes);
        vec![CoreSessionEvent::Write { bytes: frame }]
    }

    fn decrypt(&mut self, frame: &[u8]) -> Result<Message, Failure> {
        let transport = match &mut self.state {
            State::Established { transport, .. } | State::AwaitingPairingDecision { transport, .. } => transport,
            _ => return Err(CoreCloseReason::ProtocolViolation.into()),
        };
        let mut plaintext = vec![0u8; frame.len()];
        let length = transport.read_message(frame, &mut plaintext).map_err(|_| Failure::Crypto)?;
        serde_json::from_slice(&plaintext[..length]).map_err(|_| CoreCloseReason::ProtocolViolation.into())
    }

    fn encrypted(&mut self, message: &Message) -> Result<Vec<CoreSessionEvent>, CoreSessionError> {
        let transport = match &mut self.state {
            State::Established { transport, .. } | State::AwaitingPairingDecision { transport, .. } => transport,
            _ => return Err(CoreSessionError::NotConnected),
        };
        let plaintext = serde_json::to_vec(message).expect("message serializes");
        let mut ciphertext = vec![0u8; plaintext.len() + 16];
        let length = transport.write_message(&plaintext, &mut ciphertext).map_err(|_| CoreSessionError::MessageTooLarge)?;
        let frame = frame::encode(&ciphertext[..length]).map_err(|_| CoreSessionError::MessageTooLarge)?;
        Ok(vec![CoreSessionEvent::Write { bytes: frame }])
    }

    /// Before the handshake finishes a close goes out in plaintext; afterwards it is encrypted.
    fn close(&mut self, reason: CoreCloseReason, notify_peer: bool) -> Vec<CoreSessionEvent> {
        let mut events = Vec::new();
        if notify_peer {
            match self.state {
                State::Established { .. } | State::AwaitingPairingDecision { .. } => {
                    events.extend(self.encrypted(&Message::Close { reason }).unwrap_or_default());
                }
                State::AwaitingHello | State::Handshaking(_) => {
                    let bytes = serde_json::to_vec(&Message::Close { reason }).expect("message serializes");
                    if let Ok(frame) = frame::encode(&bytes) {
                        events.push(CoreSessionEvent::Write { bytes: frame });
                    }
                }
                State::Closed => {}
            }
        }
        self.state = State::Closed;
        events.push(CoreSessionEvent::Closed { reason });
        events
    }
}

fn plaintext_close(frame: &[u8]) -> Option<CoreCloseReason> {
    match serde_json::from_slice::<Message>(frame) {
        Ok(Message::Close { reason }) => Some(reason),
        _ => None,
    }
}

fn write_handshake(handshake: &mut HandshakeState, payload: &[u8]) -> Result<Vec<u8>, Failure> {
    let mut message = vec![0u8; NOISE_MAX_MESSAGE];
    let length = handshake.write_message(payload, &mut message).map_err(|_| Failure::Crypto)?;
    message.truncate(length);
    Ok(message)
}

fn write_event(message: &[u8]) -> Result<CoreSessionEvent, Failure> {
    let bytes = frame::encode(message).map_err(|_| CoreCloseReason::ProtocolViolation)?;
    Ok(CoreSessionEvent::Write { bytes })
}
