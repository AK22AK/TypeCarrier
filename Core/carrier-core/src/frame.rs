//! Length-prefixed framing: a 4-byte big-endian length, then the payload (at most 1 MiB).

pub const MAX_PAYLOAD_SIZE: usize = 1_048_576;
const HEADER_SIZE: usize = 4;

#[derive(Debug, PartialEq, Eq)]
pub struct PayloadTooLarge(pub usize);

pub fn encode(payload: &[u8]) -> Result<Vec<u8>, PayloadTooLarge> {
    if payload.len() > MAX_PAYLOAD_SIZE {
        return Err(PayloadTooLarge(payload.len()));
    }
    let mut frame = Vec::with_capacity(HEADER_SIZE + payload.len());
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    frame.extend_from_slice(payload);
    Ok(frame)
}

/// Removes and returns the next complete payload from `buffer`, or `None` until one has arrived.
pub fn next_payload(buffer: &mut Vec<u8>) -> Result<Option<Vec<u8>>, PayloadTooLarge> {
    if buffer.len() < HEADER_SIZE {
        return Ok(None);
    }
    let length = u32::from_be_bytes([buffer[0], buffer[1], buffer[2], buffer[3]]) as usize;
    if length > MAX_PAYLOAD_SIZE {
        return Err(PayloadTooLarge(length));
    }
    if buffer.len() < HEADER_SIZE + length {
        return Ok(None);
    }
    let payload = buffer[HEADER_SIZE..HEADER_SIZE + length].to_vec();
    buffer.drain(..HEADER_SIZE + length);
    Ok(Some(payload))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reassembles_frames_split_across_reads() {
        let mut stream = encode(b"hello").unwrap();
        stream.extend(encode(b"world").unwrap());
        let mut buffer = Vec::new();
        let mut payloads = Vec::new();
        for byte in stream {
            buffer.push(byte);
            while let Some(payload) = next_payload(&mut buffer).unwrap() {
                payloads.push(payload);
            }
        }
        assert_eq!(payloads, vec![b"hello".to_vec(), b"world".to_vec()]);
    }

    #[test]
    fn rejects_oversized_frames() {
        let mut buffer = ((MAX_PAYLOAD_SIZE + 1) as u32).to_be_bytes().to_vec();
        assert_eq!(next_payload(&mut buffer), Err(PayloadTooLarge(MAX_PAYLOAD_SIZE + 1)));
    }
}
