use serde::{Deserialize, Serialize};
use std::io::{Read, Write};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Payload {
    pub phrase_id: u32,
    pub salience: f32,
    pub count: u32,
    pub n: u8,
}

impl Payload {
    #[allow(dead_code)]
    pub fn new(phrase_id: u32, salience: f32, count: u32, n: u8) -> Self {
        Self {
            phrase_id,
            salience,
            count,
            n,
        }
    }

    pub fn salience_score(&self) -> f32 {
        self.salience * ((self.count + 1) as f32).ln()
    }

    pub fn read_from<R: Read>(reader: &mut R) -> std::io::Result<Self> {
        let mut buf = [0u8; 17];
        reader.read_exact(&mut buf)?;

        let phrase_id = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]);
        let salience = f32::from_le_bytes([buf[4], buf[5], buf[6], buf[7]]);
        let count = u32::from_le_bytes([buf[8], buf[9], buf[10], buf[11]]);
        let n = buf[16];

        Ok(Self {
            phrase_id,
            salience,
            count,
            n,
        })
    }

    #[allow(dead_code)]
    pub fn write_to<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        writer.write_all(&self.phrase_id.to_le_bytes())?;
        writer.write_all(&self.salience.to_le_bytes())?;
        writer.write_all(&self.count.to_le_bytes())?;
        writer.write_all(&[0u8; 4])?;
        writer.write_all(&[self.n])?;
        Ok(())
    }
}

pub fn load_payloads<R: Read>(mut reader: R) -> std::io::Result<Vec<Payload>> {
    let mut payloads = Vec::new();

    loop {
        match Payload::read_from(&mut reader) {
            Ok(payload) => payloads.push(payload),
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e),
        }
    }

    Ok(payloads)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_payload_roundtrip() {
        let payload = Payload::new(12345, 2.13, 314, 2);

        let mut buf = Vec::new();
        payload.write_to(&mut buf).unwrap();

        let mut cursor = std::io::Cursor::new(buf);
        let loaded = Payload::read_from(&mut cursor).unwrap();

        assert_eq!(loaded.phrase_id, 12345);
        assert_eq!(loaded.count, 314);
        assert_eq!(loaded.n, 2);
        assert!((loaded.salience - 2.13).abs() < 0.001);
    }

    #[test]
    fn test_salience_score() {
        let payload = Payload::new(1, 2.0, 99, 2);
        let score = payload.salience_score();
        assert!((score - (2.0 * 100.0_f32.ln())).abs() < 0.001);
    }
}