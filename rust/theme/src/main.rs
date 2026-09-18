use notify::{RecursiveMode, Watcher};
use serde_json::{json, Value};
use std::{
    collections::BTreeSet,
    env,
    fs::File,
    io::{self, Read, Write},
    path::PathBuf,
    sync::mpsc,
    time::Duration,
};

fn fallback() -> Value {
    json!({"background":"#171b24", "surface":"#222838", "foreground":"#e0e6f0",
        "accent":"#7aa2f7", "selection":"#343e55", "border":"#59657a",
        "error":"#f3a6a6", "onAccent":"#000000", "mode":"dark"})
}
fn color(value: &str) -> bool {
    value.len() == 7
        && value.starts_with('#')
        && value.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
}
fn parse(text: &str) -> Result<Value, String> {
    let table: toml::Table = text.parse().map_err(|_| "TOML inválido")?;
    let get = |key: &str| -> Result<Option<String>, String> {
        table
            .get(key)
            .map(|v| {
                v.as_str()
                    .filter(|s| color(s))
                    .map(str::to_owned)
                    .ok_or_else(|| format!("Color inválido: {key}"))
            })
            .transpose()
    };
    let required = |key| get(key)?.ok_or_else(|| format!("Falta {key}"));
    let bg = required("background")?;
    let fg = required("foreground")?;
    let accent = required("accent")?;
    let mode = match table.get("mode") {
        Some(v) if v.as_str() == Some("light") => "light",
        Some(v) if v.as_str() == Some("dark") => "dark",
        Some(_) => return Err("Modo inválido".into()),
        None => {
            if luminance(&bg) > 0.5 {
                "light"
            } else {
                "dark"
            }
        }
    };
    Ok(
        json!({"surface": get("lighter_background")?.unwrap_or(bg.clone()),
        "selection":get("selection")?.unwrap_or(accent.clone()),
        "border":get("muted")?.unwrap_or(fg.clone()),
        "error":get("red")?.unwrap_or(fg.clone()),
        "onAccent":if luminance(&accent) > 0.179 { "#000000" } else { "#ffffff" },
        "background":bg, "foreground":fg, "accent":accent, "mode":mode}),
    )
}
fn luminance(color: &str) -> f64 {
    [1, 3, 5]
        .iter()
        .zip([0.2126, 0.7152, 0.0722])
        .map(|(i, w)| {
            let c = u8::from_str_radix(&color[*i..*i + 2], 16).unwrap_or(0) as f64 / 255.0;
            w * if c <= 0.04045 {
                c / 12.92
            } else {
                ((c + 0.055) / 1.055).powf(2.4)
            }
        })
        .sum()
}
fn paths() -> Vec<PathBuf> {
    if let Some(p) = env::var_os("PDF_VIEW_THEME_FILE") {
        return vec![p.into()];
    }
    let home = PathBuf::from(env::var_os("HOME").unwrap_or_default());
    let state = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| home.join(".local/state"));
    let config = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| home.join(".config"));
    vec![
        state.join("omarchy/current/theme/colors.toml"),
        home.join(".local/state/omarchy/current/theme/colors.toml"),
        config.join("omarchy/current/theme/colors.toml"),
    ]
}
fn read_palette(path: &PathBuf) -> Result<Value, String> {
    let file = File::open(path).map_err(|_| "No se puede leer el tema")?;
    if !file
        .metadata()
        .map_err(|_| "No se puede leer el tema")?
        .is_file()
    {
        return Err("El tema no es un archivo regular".into());
    }
    let mut text = String::new();
    file.take(65537)
        .read_to_string(&mut text)
        .map_err(|_| "Tema ilegible")?;
    if text.len() > 65536 {
        return Err("Tema demasiado grande".into());
    }
    parse(&text)
}
fn main() -> io::Result<()> {
    let candidates = paths();
    let (tx, rx) = mpsc::sync_channel(8);
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if !matches!(event, Ok(ref e) if e.kind.is_access()) {
            let _ = tx.try_send(());
        }
    })
    .ok();
    let mut watched = BTreeSet::new();
    let mut palette = fallback();
    let mut last = String::new();
    loop {
        // Watch parents too: Omarchy removes current/theme and moves next-theme into place.
        // Rebuild watches after replacement; include canonical parents for legacy symlinks.
        let mut wanted = BTreeSet::new();
        for path in &candidates {
            for candidate in [Some(path.clone()), path.canonicalize().ok()]
                .into_iter()
                .flatten()
            {
                for parent in candidate.ancestors() {
                    if parent.is_dir() {
                        wanted.insert(parent.to_owned());
                    }
                }
            }
        }
        if let Some(watcher) = watcher.as_mut() {
            for path in watched.difference(&wanted) {
                let _ = watcher.unwatch(path);
            }
            // Re-register to recover watches invalidated when a directory is replaced.
            for path in &wanted {
                let _ = watcher.unwatch(path);
                let _ = watcher.watch(path, RecursiveMode::NonRecursive);
            }
            watched = wanted;
        }
        let source = candidates.iter().find(|p| p.exists());
        let status = match source {
            Some(path) => match read_palette(path) {
                Ok(next) => {
                    palette = next;
                    "omarchy"
                }
                Err(_) => "retained",
            },
            None => {
                if last.is_empty() {
                    "fallback"
                } else {
                    "retained"
                }
            }
        };
        let message = json!({"palette":palette,"status":status}).to_string();
        if message != last {
            let mut stdout = io::stdout().lock();
            writeln!(stdout, "{message}")?;
            stdout.flush()?;
            last = message;
        }
        // A bounded fallback also recovers from inotify overflow or unsupported filesystems.
        if rx.recv_timeout(Duration::from_secs(2)).is_ok() {
            std::thread::sleep(Duration::from_millis(120));
            while rx.try_recv().is_ok() {}
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn valid_light_and_comments() {
        let p = parse("background='#ffffff'\nforeground='#111111'\naccent=\"#0000ff\" # comment\nmode='light'").unwrap();
        assert_eq!(p["surface"], "#ffffff");
        assert_eq!(p["onAccent"], "#ffffff");
        assert_eq!(p["mode"], "light");
    }
    #[test]
    fn invalid_and_incomplete() {
        for s in [
            "",
            "background=42",
            "background='#fff'\nforeground='#000000'\naccent='#123456'",
            "background='bad",
        ] {
            assert!(parse(s).is_err());
        }
    }
    #[test]
    fn known_optional_values_are_validated() {
        let base = "background='#ffffff'\nforeground='#000000'\naccent='#123456'\n";
        assert!(parse(&(base.to_owned() + "muted='url(foo)'")).is_err());
        assert!(parse(&(base.to_owned() + "mode='unexpected'")).is_err());
    }
}
