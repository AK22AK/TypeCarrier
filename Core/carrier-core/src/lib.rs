//! TypeCarrier's transport protocol core, shared by every platform. Native code owns the UI,
//! device discovery and sockets; this crate owns everything that must behave identically on
//! both ends of a connection: framing, version negotiation, the Noise handshake, pairing codes,
//! heartbeats and encrypted messages.

pub mod frame;
pub mod protocol;
pub mod session;

pub use protocol::{CoreCloseReason, CoreHelloMode, CorePlatform};
pub use session::{
    CoreSession, CoreIdentity, CorePeer, CoreResponderPolicy, CoreRole, CoreSessionError, CoreSessionEvent, generate_static_private_key,
    public_key_for,
};

uniffi::setup_scaffolding!();
