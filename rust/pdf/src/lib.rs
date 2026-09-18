use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io::{self, BufRead, Read, Write};

pub const MAX_META: usize = 8 * 1024 * 1024;
pub const MAX_PIXELS: usize = 4096 * 4096 * 4;
pub const MAX_FRAME: usize = MAX_META + MAX_PIXELS.div_ceil(3) * 4 + 128;
pub type Result<T> = std::result::Result<T, String>;

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
pub struct Rect(pub f64, pub f64, pub f64, pub f64);
impl Rect {
    pub fn valid(self) -> bool {
        [self.0, self.1, self.2, self.3]
            .iter()
            .all(|v| v.is_finite() && v.abs() <= 100000.)
            && self.2 >= 0.
            && self.3 >= 0.
    }
    pub fn union(self, other: Self) -> Self {
        let x = self.0.min(other.0);
        let y = self.1.min(other.1);
        Self(
            x,
            y,
            (self.0 + self.2).max(other.0 + other.2) - x,
            (self.1 + self.3).max(other.1 + other.3) - y,
        )
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Word {
    pub text: String,
    pub rect: Rect,
    pub space: bool,
}
pub fn joined(words: &[Word]) -> String {
    let mut text = String::new();
    for (i, w) in words.iter().enumerate() {
        text.push_str(&w.text);
        if let Some(next) = words.get(i + 1) {
            if (next.rect.1 + next.rect.3 / 2. - w.rect.1 - w.rect.3 / 2.).abs() > w.rect.3 / 2. {
                text.push('\n');
            } else if w.space {
                text.push(' ');
            }
        }
    }
    text
}
pub fn integer(v: &Value, key: &str, default: i64) -> i64 {
    v[key].as_i64().unwrap_or(default)
}
pub fn number(v: &Value, key: &str, default: f64) -> f64 {
    v[key].as_f64().unwrap_or(default)
}
pub fn language_valid(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 32
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b == b'_' || b == b'+')
}
// Both IPC boundaries use newline-delimited JSON. Pixels are raw RGBA in base64,
// never a compressed image that could bypass the broker's dimension checks.
pub fn read_frame(mut input: impl BufRead) -> Result<(Value, Vec<u8>)> {
    let mut data = Vec::new();
    let n = input
        .by_ref()
        .take((MAX_FRAME + 1) as u64)
        .read_until(b'\n', &mut data)
        .map_err(|e| e.to_string())?;
    if n == 0 || data.len() > MAX_FRAME || data.last() != Some(&b'\n') {
        return Err("Respuesta inválida del motor.".into());
    }
    let frame: Value = serde_json::from_slice(&data[..data.len() - 1])
        .map_err(|_| "Respuesta inválida del motor.")?;
    let meta = frame
        .get("meta")
        .filter(|v| v.is_object())
        .ok_or("Metadatos inválidos.")?;
    if meta.to_string().len() > MAX_META {
        return Err("Metadatos demasiado grandes.".into());
    }
    let encoded = frame["pixels"].as_str().ok_or("Píxeles inválidos.")?;
    if encoded.len() > MAX_PIXELS.div_ceil(3) * 4 {
        return Err("Imagen demasiado grande.".into());
    }
    let pixels = STANDARD.decode(encoded).map_err(|_| "Píxeles inválidos.")?;
    if pixels.len() > MAX_PIXELS {
        return Err("Imagen demasiado grande.".into());
    }
    Ok((meta.clone(), pixels))
}
pub fn write_frame(meta: &Value, pixels: &[u8]) -> io::Result<()> {
    if meta.to_string().len() > MAX_META || pixels.len() > MAX_PIXELS {
        return Err(io::Error::other("Respuesta demasiado grande"));
    }
    let frame = serde_json::json!({"meta":meta,"pixels":STANDARD.encode(pixels)});
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, &frame)?;
    out.write_all(b"\n")?;
    out.flush()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_untrusted_frames_and_coordinates() {
        assert!(read_frame(&b"{\"meta\":{},\"pixels\":\"bad!\"}\n"[..]).is_err());
        assert!(read_frame(&b"{}\n{}\n"[..]).is_err());
        let (meta, pixels) =
            read_frame(&b"{\"meta\":{\"page\":1},\"pixels\":\"AQID\"}\n"[..]).unwrap();
        assert_eq!(meta["page"], 1);
        assert_eq!(pixels, vec![1, 2, 3]);
        assert!(!Rect(0., 0., -1., 1.).valid());
        assert!(!Rect(f64::NAN, 0., 1., 1.).valid());
        assert!(!language_valid("../../eng"));
        assert!(language_valid("spa+eng"));
    }
}
