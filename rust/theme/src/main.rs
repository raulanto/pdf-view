mod palette;
mod scale;

use notify::{RecursiveMode, Watcher};
use palette::{fallback, paths, read_palette};
use scale::{read_scale, scale_path};
use serde_json::json;
use std::{
    collections::BTreeSet,
    io::{self, Write},
    path::PathBuf,
    sync::mpsc,
    time::Duration,
};

/// Recorre `paths` y añade todos los directorios ancestros al conjunto,
/// incluyendo la ruta canónica para recuperarse de symlinks reemplazados.
fn ancestor_dirs(paths: &[PathBuf]) -> BTreeSet<PathBuf> {
    let mut dirs = BTreeSet::new();
    for path in paths {
        for candidate in [Some(path.clone()), path.canonicalize().ok()]
            .into_iter()
            .flatten()
        {
            for parent in candidate.ancestors() {
                if parent.is_dir() {
                    dirs.insert(parent.to_owned());
                }
            }
        }
    }
    dirs
}

fn main() -> io::Result<()> {
    let candidates = paths();
    let scale_file = scale_path();
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
        let mut wanted = ancestor_dirs(&candidates);
        if let Some(ref sp) = scale_file {
            wanted.extend(ancestor_dirs(std::slice::from_ref(sp)));
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
        let scale = scale_file.as_ref().map(read_scale).unwrap_or(1.0);
        let message = json!({"palette":palette,"scale":scale,"status":status}).to_string();
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
