use std::{env, fs::File, io::Read, path::PathBuf};

/// Ruta al archivo `monitors.conf` de Hyprland, siguiendo XDG_CONFIG_HOME.
pub fn scale_path() -> Option<PathBuf> {
    let config = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".config"));
    Some(config.join("hypr/monitors.conf"))
}

/// Extrae el factor de escala de la primera línea `monitor=` activa.
/// Formato esperado: `monitor=<nombre>,<res>,<pos>,<scale>[,...]`
/// Devuelve 1.0 si no se puede parsear ningún valor válido.
pub fn parse_scale(text: &str) -> f64 {
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') || !trimmed.to_ascii_lowercase().starts_with("monitor=") {
            continue;
        }
        let after_eq = &trimmed["monitor=".len()..];
        let parts: Vec<&str> = after_eq.splitn(5, ',').map(str::trim).collect();
        if parts.len() >= 4 {
            if let Ok(s) = parts[3].parse::<f64>() {
                if s > 0.0 && s <= 8.0 {
                    return s;
                }
            }
        }
    }
    1.0
}

/// Lee `monitors.conf` y devuelve el factor de escala activo (defecto 1.0).
pub fn read_scale(path: &PathBuf) -> f64 {
    let Ok(f) = File::open(path) else { return 1.0 };
    if f.metadata().map(|m| !m.is_file()).unwrap_or(true) {
        return 1.0;
    }
    let mut text = String::new();
    if f.take(65537).read_to_string(&mut text).is_err() || text.len() > 65536 {
        return 1.0;
    }
    parse_scale(&text)
}
