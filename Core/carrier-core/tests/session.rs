use std::sync::{Arc, Mutex};

use carrier_core::*;

const PHONE_ID: &str = "phone-1";
const MAC_ID: &str = "mac-1";

struct Policy {
    trusted: Mutex<Vec<Vec<u8>>>,
    pairing_open: bool,
}

impl CoreResponderPolicy for Policy {
    fn is_trusted(&self, public_key: Vec<u8>) -> bool {
        self.trusted.lock().unwrap().contains(&public_key)
    }

    fn is_pairing_open(&self) -> bool {
        self.pairing_open
    }
}

struct Pair {
    phone: Arc<CoreSession>,
    mac: Arc<CoreSession>,
    phone_key: Vec<u8>,
    mac_key: Vec<u8>,
}

fn identity(key: &[u8], id: &str, name: &str, platform: CorePlatform, capabilities: &[&str]) -> CoreIdentity {
    CoreIdentity {
        static_private_key: key.to_vec(),
        device_id: id.into(),
        device_name: name.into(),
        platform,
        capabilities: capabilities.iter().map(|c| c.to_string()).collect(),
    }
}

fn make(mode: CoreHelloMode, remote: Option<Vec<u8>>, trusted: Vec<Vec<u8>>, pairing_open: bool) -> Pair {
    make_with_keys(generate_static_private_key(), generate_static_private_key(), mode, remote, trusted, pairing_open)
}

fn make_with_keys(
    phone_key: Vec<u8>,
    mac_key: Vec<u8>,
    mode: CoreHelloMode,
    remote: Option<Vec<u8>>,
    trusted: Vec<Vec<u8>>,
    pairing_open: bool,
) -> Pair {
    let phone = CoreSession::new(
        CoreRole::Initiator { mode, remote_static_key: remote },
        identity(&phone_key, PHONE_ID, "iPhone", CorePlatform::Ios, &["send.text"]),
        0,
        None,
    );
    let mac = CoreSession::new(
        CoreRole::Responder,
        identity(&mac_key, MAC_ID, "Mac", CorePlatform::MacOs, &["receive.paste", "receipt"]),
        0,
        Some(Arc::new(Policy { trusted: Mutex::new(trusted), pairing_open })),
    );
    Pair { phone, mac, phone_key, mac_key }
}

fn written(events: &[CoreSessionEvent]) -> Vec<u8> {
    events
        .iter()
        .flat_map(|event| match event {
            CoreSessionEvent::Write { bytes } => bytes.clone(),
            _ => Vec::new(),
        })
        .collect()
}

fn not_writes(events: Vec<CoreSessionEvent>) -> Vec<CoreSessionEvent> {
    events.into_iter().filter(|event| !matches!(event, CoreSessionEvent::Write { .. })).collect()
}

/// Delivers writes back and forth until both sides go quiet; returns each side's non-write events.
fn pump(pair: &Pair, phone_first: Vec<CoreSessionEvent>, mac_first: Vec<CoreSessionEvent>) -> (Vec<CoreSessionEvent>, Vec<CoreSessionEvent>) {
    let mut to_mac = written(&phone_first);
    let mut to_phone = written(&mac_first);
    let mut phone_events = not_writes(phone_first);
    let mut mac_events = not_writes(mac_first);
    while !to_mac.is_empty() || !to_phone.is_empty() {
        let from_mac = if to_mac.is_empty() { vec![] } else { pair.mac.receive(std::mem::take(&mut to_mac), 0) };
        let from_phone = if to_phone.is_empty() { vec![] } else { pair.phone.receive(std::mem::take(&mut to_phone), 0) };
        to_phone = written(&from_mac);
        to_mac = written(&from_phone);
        mac_events.extend(not_writes(from_mac));
        phone_events.extend(not_writes(from_phone));
    }
    (phone_events, mac_events)
}

fn public(key: &[u8]) -> Vec<u8> {
    public_key_for(key.to_vec()).unwrap()
}

fn pairing_code(events: &[CoreSessionEvent]) -> Option<String> {
    events.iter().find_map(|event| match event {
        CoreSessionEvent::PairingCodeReady { code, .. } => Some(code.clone()),
        _ => None,
    })
}

fn established(events: &[CoreSessionEvent]) -> Option<CorePeer> {
    events.iter().find_map(|event| match event {
        CoreSessionEvent::Established { peer } => Some(peer.clone()),
        _ => None,
    })
}

#[test]
fn pairing_shows_the_same_code_on_both_sides_and_establishes_after_confirmation() {
    let pair = make(CoreHelloMode::Pair, None, vec![], true);
    let (phone, mac) = pump(&pair, pair.phone.start(), vec![]);

    let code = pairing_code(&phone).expect("phone code");
    assert_eq!(Some(code.clone()), pairing_code(&mac));
    assert_eq!(code.len(), 4);
    assert!(!pair.phone.is_established() && !pair.mac.is_established());
    let mac_peer = pair.mac.peer().unwrap();
    assert_eq!(mac_peer.device_name, "iPhone");
    assert_eq!(mac_peer.public_key, public(&pair.phone_key));
    assert_eq!(mac_peer.platform, CorePlatform::Ios);

    let (phone, mac) = pump(&pair, vec![], pair.mac.confirm_pairing());
    assert!(pair.phone.is_established() && pair.mac.is_established());
    let phone_peer = established(&phone).unwrap();
    assert_eq!(phone_peer.public_key, public(&pair.mac_key));
    assert_eq!(phone_peer.device_id, MAC_ID);
    assert!(established(&mac).is_some());
}

#[test]
fn rejected_pairing_closes_both_sides() {
    let pair = make(CoreHelloMode::Pair, None, vec![], true);
    pump(&pair, pair.phone.start(), vec![]);
    let (phone, _) = pump(&pair, vec![], pair.mac.reject_pairing());
    assert!(phone.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::PairingRejected }));
    assert!(pair.phone.is_closed() && pair.mac.is_closed());
}

#[test]
fn pairing_is_refused_when_the_receiver_has_not_opened_it() {
    let pair = make(CoreHelloMode::Pair, None, vec![], false);
    let (phone, mac) = pump(&pair, pair.phone.start(), vec![]);
    assert!(phone.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::PairingNotOpen }));
    assert!(mac.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::PairingNotOpen }));
}

#[test]
fn paired_reconnect_carries_envelopes_both_ways() {
    let phone_key = generate_static_private_key();
    let mac_key = generate_static_private_key();
    let pair = make_with_keys(phone_key.clone(), mac_key.clone(), CoreHelloMode::Connect, Some(public(&mac_key)), vec![public(&phone_key)], false);
    let (phone, mac) = pump(&pair, pair.phone.start(), vec![]);
    assert_eq!(established(&mac).unwrap().device_id, PHONE_ID);
    assert_eq!(established(&phone).unwrap().device_id, MAC_ID);

    let envelope = r#"{"kind":"text","payload":{"text":"你好，Mac"},"version":1}"#;
    let (_, received) = pump(&pair, pair.phone.send_envelope(envelope.into()).unwrap(), vec![]);
    let CoreSessionEvent::Received { envelope_json } = &received[0] else { panic!("{received:?}") };
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(envelope_json).unwrap(),
        serde_json::from_str::<serde_json::Value>(envelope).unwrap()
    );

    let (receipt, _) = pump(&pair, vec![], pair.mac.send_envelope(r#"{"kind":"ack"}"#.into()).unwrap());
    assert_eq!(receipt, vec![CoreSessionEvent::Received { envelope_json: r#"{"kind":"ack"}"#.into() }]);
}

#[test]
fn reconnect_from_an_unpaired_device_is_refused() {
    let mac_key = generate_static_private_key();
    let pair = make_with_keys(generate_static_private_key(), mac_key.clone(), CoreHelloMode::Connect, Some(public(&mac_key)), vec![], false);
    let (phone, mac) = pump(&pair, pair.phone.start(), vec![]);
    assert!(mac.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::NotPaired }));
    assert!(phone.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::NotPaired }));
}

#[test]
fn reconnect_to_a_receiver_whose_key_changed_fails_the_handshake() {
    let phone_key = generate_static_private_key();
    let pair = make_with_keys(
        phone_key.clone(),
        generate_static_private_key(),
        CoreHelloMode::Connect,
        Some(public(&generate_static_private_key())),
        vec![public(&phone_key)],
        false,
    );
    let (phone, mac) = pump(&pair, pair.phone.start(), vec![]);
    assert!(mac.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::HandshakeFailed }));
    assert!(phone.contains(&CoreSessionEvent::Closed { reason: CoreCloseReason::HandshakeFailed }));
    assert!(!pair.phone.is_established());
}

#[test]
fn incompatible_versions_close_with_unsupported_version() {
    let pair = make(CoreHelloMode::Connect, None, vec![], false);
    let future = br#"{"proto":9,"minProto":9,"mode":"connect","platform":"windows","capabilities":[]}"#;
    let events = pair.mac.receive(carrier_core::frame::encode(future).unwrap(), 0);
    assert_eq!(events.last(), Some(&CoreSessionEvent::Closed { reason: CoreCloseReason::UnsupportedVersion }));
}

#[test]
fn frames_split_into_single_bytes_still_establish() {
    let phone_key = generate_static_private_key();
    let mac_key = generate_static_private_key();
    let pair = make_with_keys(phone_key.clone(), mac_key.clone(), CoreHelloMode::Connect, Some(public(&mac_key)), vec![public(&phone_key)], false);
    let mut to_mac = written(&pair.phone.start());
    for _ in 0..4 {
        let mut from_mac = Vec::new();
        for byte in std::mem::take(&mut to_mac) {
            from_mac.extend(pair.mac.receive(vec![byte], 0));
        }
        let mut from_phone = Vec::new();
        for byte in written(&from_mac) {
            from_phone.extend(pair.phone.receive(vec![byte], 0));
        }
        to_mac = written(&from_phone);
    }
    assert!(pair.phone.is_established() && pair.mac.is_established());
}

#[test]
fn heartbeat_pings_when_idle_and_closes_after_silence() {
    let phone_key = generate_static_private_key();
    let mac_key = generate_static_private_key();
    let pair = make_with_keys(phone_key.clone(), mac_key.clone(), CoreHelloMode::Connect, Some(public(&mac_key)), vec![public(&phone_key)], false);
    pump(&pair, pair.phone.start(), vec![]);

    assert!(pair.phone.tick(5_000).is_empty());
    let ping = pair.phone.tick(10_000);
    assert_eq!(ping.len(), 1);
    let pong = pair.mac.receive(written(&ping), 10_000);
    assert_eq!(pong.len(), 1);
    assert!(pair.phone.receive(written(&pong), 11_000).is_empty());

    let silent = pair.phone.tick(11_000 + 25_000);
    assert_eq!(silent.last(), Some(&CoreSessionEvent::Closed { reason: CoreCloseReason::HeartbeatTimeout }));
}

#[test]
fn a_tampered_established_frame_closes_the_session() {
    let phone_key = generate_static_private_key();
    let mac_key = generate_static_private_key();
    let pair = make_with_keys(phone_key.clone(), mac_key.clone(), CoreHelloMode::Connect, Some(public(&mac_key)), vec![public(&phone_key)], false);
    pump(&pair, pair.phone.start(), vec![]);
    let mut frame = written(&pair.phone.send_envelope("{}".into()).unwrap());
    let last = frame.len() - 1;
    frame[last] ^= 0xFF;
    assert_eq!(pair.mac.receive(frame, 0).last(), Some(&CoreSessionEvent::Closed { reason: CoreCloseReason::HandshakeFailed }));
}

#[test]
fn sending_before_the_session_is_established_fails() {
    let pair = make(CoreHelloMode::Pair, None, vec![], true);
    assert!(matches!(pair.phone.send_envelope("{}".into()), Err(CoreSessionError::NotConnected)));
}
