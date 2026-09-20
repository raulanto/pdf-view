//! Atomic document writes belong to the broker, never to the sandboxed parser.
use crate::{process::WorkerProcess, protocol::execute};
use base64::{engine::general_purpose::STANDARD, Engine};
use pdf_view_backend::Result;
use serde_json::{json, Value};
use std::{
    fs::{self, File, Metadata, OpenOptions},
    io::Write,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};
fn identity(m: &Metadata) -> (u64, u64, u64, i64, i64, i64, i64) {
    (
        m.dev(),
        m.ino(),
        m.len(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec(),
    )
}
pub fn save(
    worker: &Arc<Mutex<Option<WorkerProcess>>>,
    source: &File,
    path: &Path,
    request: &Value,
    cancel: &AtomicBool,
    id: u64,
) -> Result<Value> {
    let started = std::time::Instant::now();
    let expected = source.metadata().map_err(|e| e.to_string())?;
    let check = || -> Result<()> {
        let now = fs::symlink_metadata(path).map_err(|_| "El archivo ya no existe.")?;
        if !now.is_file() || identity(&now) != identity(&expected) {
            return Err("El PDF cambió fuera del visor. Ábrelo de nuevo antes de guardar.".into());
        }
        if cancel.load(Ordering::Relaxed) {
            return Err("Guardado cancelado.".into());
        }
        Ok(())
    };
    check()?;
    let writable = OpenOptions::new()
        .write(true)
        .custom_flags((rustix::fs::OFlags::NOFOLLOW | rustix::fs::OFlags::NONBLOCK).bits() as i32)
        .open(path)
        .map_err(|_| "No tienes permiso para guardar este PDF.")?;
    if identity(&writable.metadata().map_err(|e| e.to_string())?) != identity(&expected) {
        return Err("El PDF cambió antes de guardar.".into());
    }
    drop(writable);
    let mut export = request.clone();
    export["op"] = json!("export");
    let meta = execute(worker, &export, cancel)?;
    if let Some(error) = meta["error"].as_str() {
        return Err(error.into());
    }
    let size = meta["bytes"].as_u64().ok_or("Exportación inválida.")? as usize;
    let parent = path.parent().ok_or("Ruta inválida.")?;
    let stage = parent.join(format!(".pdf-view-{}-{id}.tmp", std::process::id()));
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&stage)
        .map_err(|_| "No se pudo preparar el guardado en esta carpeta.")?;
    let result = (|| -> Result<Value> {
        let mut offset = 0;
        let mut tail = Vec::new();
        while offset < size {
            if cancel.load(Ordering::Relaxed) {
                return Err("Guardado cancelado.".into());
            }
            let remaining = std::time::Duration::from_secs(45)
                .checked_sub(started.elapsed())
                .ok_or("El guardado excedió 45 segundos; el original sigue intacto.")?;
            let part = execute(
                worker,
                &json!({"op":"export_chunk","offset":offset,"timeoutMs":remaining.as_millis() as u64}),
                cancel,
            )?;
            let bytes = STANDARD
                .decode(part["chunk"].as_str().ok_or("Exportación incompleta.")?)
                .map_err(|_| "Fragmento inválido.")?;
            if bytes.len() != (size - offset).min(1024 * 1024)
                || (offset == 0 && !bytes.starts_with(b"%PDF-"))
            {
                return Err("PDF exportado inválido.".into());
            }
            output
                .write_all(&bytes)
                .map_err(|_| "No se pudo escribir el PDF. El original sigue intacto.")?;
            tail = bytes[bytes.len().saturating_sub(64)..].to_vec();
            offset += bytes.len();
        }
        if !tail.windows(5).any(|w| w == b"%%EOF") {
            return Err("PDF exportado incompleto.".into());
        }
        output
            .set_permissions(fs::Permissions::from_mode(expected.mode() & 0o777))
            .map_err(|e| e.to_string())?;
        output
            .sync_all()
            .map_err(|_| "No se pudo sincronizar el PDF. El original sigue intacto.")?;
        check()?;
        fs::rename(&stage, path)
            .map_err(|_| "No se pudo sustituir el PDF. El original sigue intacto.")?;
        let durable = File::open(parent).and_then(|f| f.sync_all()).is_ok();
        Ok(
            json!({"saved":true,"warning":if durable {""} else {"Guardado, pero no se pudo sincronizar la carpeta."}}),
        )
    })();
    drop(output);
    let _ = fs::remove_file(&stage);
    result
}
