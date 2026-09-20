use crate::process::WorkerProcess;
use base64::{engine::general_purpose::STANDARD, Engine};
use pdf_view_backend::{integer, number, Rect, Result, Word};
use serde_json::{json, Value};
use std::{
    fs::{File, OpenOptions},
    io::{self, Write},
    os::unix::fs::OpenOptionsExt,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    time::{Duration, Instant},
};

/// Emite una respuesta JSON por stdout hacia el frontend QML.
pub fn emit(id: u64, kind: usize, meta: Value) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{}", json!({"id":id,"kind":kind,"data":meta}));
    let _ = out.flush();
}

/// Abre un archivo PDF local desde una URL `file://`.
/// Valida esquema, host, regularidad del archivo y tamaño máximo (256 MiB).
pub fn open_document(uri: &str) -> Result<File> {
    let url = url::Url::parse(uri).map_err(|_| "Selecciona un archivo PDF local.")?;
    if url.scheme() != "file"
        || url
            .host_str()
            .is_some_and(|h| !h.is_empty() && h != "localhost")
    {
        return Err("Selecciona un archivo PDF local.".into());
    }
    let path = url.to_file_path().map_err(|_| "Ruta inválida.")?;
    let file = OpenOptions::new()
        .read(true)
        .custom_flags((rustix::fs::OFlags::NONBLOCK | rustix::fs::OFlags::CLOEXEC).bits() as i32)
        .open(path)
        .map_err(|_| "No se puede abrir el documento.")?;
    let meta = file.metadata().map_err(|e| e.to_string())?;
    if !meta.is_file() || meta.len() > 256 * 1024 * 1024 {
        return Err("El archivo no es regular o supera 256 MiB.".into());
    }
    Ok(file)
}

/// Valida la respuesta del worker antes de usarla en el frontend.
/// Codifica los píxeles RGB crudos como PNG solo tras la validación.
pub fn validate(mut meta: Value, pixels: Vec<u8>, request: &Value) -> Result<Value> {
    if !meta.is_object() {
        return Err("Metadatos inválidos.".into());
    }
    if meta["locked"] == true || meta.get("error").is_some() {
        if !pixels.is_empty() {
            return Err("Respuesta inválida.".into());
        }
        if let Some(e) = meta.get("error") {
            if e.as_str().is_none_or(|s| s.len() > 1024) {
                return Err("Error del motor inválido.".into());
            }
        }
        return Ok(meta);
    }
    let op = request["op"].as_str().unwrap_or("");
    if op == "export" {
        if !pixels.is_empty() || !(8..=256 * 1024 * 1024).contains(&integer(&meta, "bytes", 0)) {
            return Err("Exportación inválida.".into());
        }
        return Ok(meta);
    }
    if op == "export_chunk" {
        if !pixels.is_empty()
            || meta["offset"] != request["offset"]
            || meta["chunk"]
                .as_str()
                .is_none_or(|s| s.is_empty() || s.len() > 1024 * 1024 * 4 / 3 + 4)
        {
            return Err("Fragmento inválido.".into());
        }
        return Ok(meta);
    }
    if op == "extract" {
        if !pixels.is_empty()
            || meta["text"]
                .as_str()
                .is_none_or(|s| s.chars().count() > 2 * 1024 * 1024)
        {
            return Err("Selección inválida.".into());
        }
        return Ok(meta);
    }
    if op == "search" {
        let matches = meta["matches"].as_array().ok_or("Búsqueda inválida.")?;
        if !pixels.is_empty() || matches.len() > 2000 {
            return Err("Búsqueda inválida.".into());
        }
        for m in matches {
            let r: Rect =
                serde_json::from_value(m["rect"].clone()).map_err(|_| "Coordenadas inválidas.")?;
            if !r.valid() || !(1..=1000000).contains(&integer(m, "page", 0)) {
                return Err("Coincidencia inválida.".into());
            }
        }
        return Ok(meta);
    }
    let w = integer(&meta, "width", 0);
    let h = integer(&meta, "height", 0);
    let max = if op == "thumbnail" {
        256
    } else if op == "region" {
        2048
    } else {
        4096
    };
    let pw = number(&meta, "pageWidth", 0.);
    let ph = number(&meta, "pageHeight", 0.);
    let text_only = op == "text";
    if (text_only && !pixels.is_empty())
        || (!text_only
            && (!(1..=max).contains(&w)
                || !(1..=max).contains(&h)
                || pixels.len() != (w * h * 3) as usize))
        || !(1..=1000000).contains(&integer(&meta, "pages", 0))
        || meta["page"] != request["page"]
        || meta["rotation"] != request["rotation"]
        || pw <= 0.
        || ph <= 0.
        || pw > 100000.
        || ph > 100000.
    {
        return Err("Imagen inválida.".into());
    }
    let words: Vec<Word> =
        serde_json::from_value(meta["words"].clone()).map_err(|_| "Texto inválido.")?;
    if words.len() > 50000
        || words
            .iter()
            .any(|w| !w.rect.valid() || w.text.chars().count() > 4096)
    {
        return Err("Texto inválido.".into());
    }
    if let Some(outline) = meta.get("outline") {
        let entries = outline.as_array().ok_or("Índice inválido.")?;
        if entries.len() > 2048 {
            return Err("Índice inválido.".into());
        }
        for e in entries {
            if e["title"].as_str().is_none_or(|s| s.chars().count() > 512)
                || !(0..=integer(&meta, "pages", 0)).contains(&integer(e, "page", -1))
                || !(0..=16).contains(&integer(e, "depth", -1))
            {
                return Err("Índice inválido.".into());
            }
        }
    }
    if text_only {
        let notes = meta["annotations"]
            .as_array()
            .ok_or("Anotaciones inválidas.")?;
        if notes.len() > 256 || !meta["canAnnotate"].is_boolean() {
            return Err("Anotaciones inválidas.".into());
        }
        for note in notes {
            pdf_view_backend::annotation_rgb(note["color"].as_str().unwrap_or(""))?;
            let r: Rect =
                serde_json::from_value(note["rect"].clone()).map_err(|_| "Anotación inválida.")?;
            if !r.valid()
                || note["text"]
                    .as_str()
                    .is_none_or(|s| s.chars().count() > 4000)
                || !["note", "underline", "highlight"]
                    .contains(&note["kind"].as_str().unwrap_or(""))
            {
                return Err("Anotación inválida.".into());
            }
        }
        return Ok(meta);
    }
    // Encode only validated raw pixels here: the UI never decodes an image supplied by the PDF parser.
    let mut png = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut png, w as u32, h as u32);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_compression(png::Compression::Fast);
        encoder
            .write_header()
            .map_err(|e| e.to_string())?
            .write_image_data(&pixels)
            .map_err(|e| e.to_string())?;
    }
    meta["image"] = json!(format!("data:image/png;base64,{}", STANDARD.encode(png)));
    Ok(meta)
}

/// Envía una petición al worker aislado y espera su respuesta.
/// Cancela y destruye el worker si supera el límite de tiempo o si
/// el flag de cancelación se activa.
pub fn execute(
    worker_slot: &Arc<Mutex<Option<WorkerProcess>>>,
    request: &Value,
    cancel_flag: &AtomicBool,
) -> Result<Value> {
    let mut input = serde_json::to_vec(request).map_err(|e| e.to_string())?;
    input.push(b'\n');
    let limit = if request["op"] == "render" && request["ocr"] != true {
        20
    } else {
        45
    };
    let limit = Duration::from_millis(
        request["timeoutMs"]
            .as_u64()
            .unwrap_or(limit * 1000)
            .clamp(1, limit * 1000),
    );
    let mut guard = worker_slot.lock().unwrap();
    let worker_proc = guard.as_mut().ok_or("Motor no disponible.")?;
    if worker_proc.stdin.write_all(&input).is_err() {
        if let Some(mut wp) = guard.take() {
            wp.kill();
        }
        return Err("No se pudo enviar la petición.".into());
    }
    let start = Instant::now();
    let frame = loop {
        if cancel_flag.load(Ordering::Relaxed) || start.elapsed() > limit {
            break Err("La operación excedió el tiempo permitido.".into());
        }
        match worker_proc.frames.recv_timeout(Duration::from_millis(20)) {
            Ok(frame) => break frame,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(_) => break Err("El motor terminó sin responder.".into()),
        }
    };
    if cancel_flag.load(Ordering::Relaxed) || start.elapsed() > limit {
        if let Some(mut wp) = guard.take() {
            wp.kill();
        }
        return Err(if cancel_flag.load(Ordering::Relaxed) {
            "cancelled"
        } else {
            "La operación excedió el tiempo permitido."
        }
        .into());
    }
    let (meta, pixels) = match frame {
        Ok(f) => f,
        Err(e) => {
            if let Some(mut wp) = guard.take() {
                wp.kill();
            }
            return Err(e);
        }
    };
    validate(meta, pixels, request)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn rejects_remote_and_invalid_worker_output() {
        assert!(open_document("https://example.com/doc.pdf").is_err());
        assert!(validate(json!({"bytes":0}), vec![], &json!({"op":"export"})).is_err());
        assert!(validate(
            json!({"bytes":268435457_u64}),
            vec![],
            &json!({"op":"export"})
        )
        .is_err());
        assert!(validate(
            json!({"offset":2,"chunk":"AAAA"}),
            vec![],
            &json!({"op":"export_chunk","offset":0})
        )
        .is_err());
        assert!(validate(json!({"width":999999}), vec![], &json!({"op":"render"})).is_err());
        assert!(validate(json!({"text":"a"}), vec![0], &json!({"op":"extract"})).is_err());
    }
}
