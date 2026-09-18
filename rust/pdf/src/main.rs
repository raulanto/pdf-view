use base64::{engine::general_purpose::STANDARD, Engine};
use pdf_view_backend::*;
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs::{File, OpenOptions},
    io::{self, BufRead, Read, Write},
    os::{
        fd::{AsRawFd, BorrowedFd},
        unix::{
            fs::{MetadataExt, OpenOptionsExt},
            process::CommandExt,
        },
    },
    path::PathBuf,
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

struct Job {
    cancel: Arc<AtomicBool>,
    thread: thread::JoinHandle<()>,
}
struct WorkerProcess {
    child: std::process::Child,
    stdin: std::process::ChildStdin,
    frames: Receiver<Result<(Value, Vec<u8>)>>,
    reader: Option<thread::JoinHandle<()>>,
}
impl WorkerProcess {
    fn spawn(worker: &PathBuf, file: &File) -> Result<Self> {
        let mut child = sandbox(worker, file)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("No se pudo iniciar el motor aislado: {e}"))?;
        let stdin = child.stdin.take().unwrap();
        let mut stdout = std::io::BufReader::new(child.stdout.take().unwrap());
        let (sender, frames) = mpsc::sync_channel(1);
        let reader = thread::spawn(move || loop {
            let frame = read_frame(&mut stdout);
            let failed = frame.is_err();
            if sender.send(frame).is_err() || failed {
                break;
            }
        });
        Ok(Self {
            child,
            stdin,
            frames,
            reader: Some(reader),
        })
    }
    fn kill(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
impl Drop for WorkerProcess {
    fn drop(&mut self) {
        self.kill();
        // Release a reader blocked on sending an unsolicited/extra frame.
        let (_, empty) = mpsc::channel();
        drop(std::mem::replace(&mut self.frames, empty));
        if let Some(reader) = self.reader.take() {
            let _ = reader.join();
        }
    }
}
fn cancel(job: &mut Option<Job>, _worker_slot: &Arc<Mutex<Option<WorkerProcess>>>) {
    if let Some(job) = job.take() {
        job.cancel.store(true, Ordering::Relaxed);
        let _ = job.thread.join();
    }
}
struct Cache {
    entries: VecDeque<(String, Value, usize)>,
    bytes: usize,
}
impl Cache {
    fn get(&mut self, key: &str) -> Option<Value> {
        let i = self.entries.iter().position(|e| e.0 == key)?;
        let e = self.entries.remove(i)?;
        let value = e.1.clone();
        self.entries.push_back(e);
        Some(value)
    }
    fn put(&mut self, key: String, value: Value) {
        let size = value.to_string().len() + key.len();
        if size > 96 * 1024 * 1024 {
            return;
        }
        while self.bytes + size > 96 * 1024 * 1024 {
            if let Some(e) = self.entries.pop_front() {
                self.bytes -= e.2;
            } else {
                break;
            }
        }
        self.bytes += size;
        self.entries.push_back((key, value, size));
    }
    fn clear(&mut self) {
        self.entries.clear();
        self.bytes = 0;
    }
}
fn emit(id: u64, kind: usize, meta: Value) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{}", json!({"id":id,"kind":kind,"data":meta}));
    let _ = out.flush();
}
fn open_document(uri: &str) -> Result<File> {
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
fn sandbox(worker: &PathBuf, file: &File) -> Command {
    let fd = file.as_raw_fd();
    let descriptor = fd.to_string();
    let mut command = Command::new("/usr/bin/bwrap");
    command
        .args([
            "--unshare-all",
            "--unshare-user",
            "--unshare-net",
            "--disable-userns",
            "--die-with-parent",
            "--new-session",
            "--clearenv",
            "--ro-bind",
            "/usr",
            "/usr",
            "--symlink",
            "usr/lib",
            "/lib",
            "--symlink",
            "usr/lib",
            "/lib64",
            "--proc",
            "/proc",
            "--dev",
            "/dev",
            "--tmpfs",
            "/tmp",
            "--dir",
            "/app",
            "--ro-bind",
        ])
        .arg(worker)
        .args([
            "/app/worker",
            "--ro-bind-fd",
            &descriptor,
            "/document.pdf",
            "--setenv",
            "HOME",
            "/nonexistent",
            "--setenv",
            "XDG_CACHE_HOME",
            "/tmp/cache",
            "--setenv",
            "OMP_THREAD_LIMIT",
            "1",
            "--setenv",
            "LANG",
            "C.UTF-8",
            "--chdir",
            "/tmp",
        ]);
    if std::path::Path::new("/etc/fonts").exists() {
        command.args(["--ro-bind", "/etc/fonts", "/etc/fonts"]);
    }
    let library = std::env::var_os("PDF_VIEW_PDFIUM")
        .map(PathBuf::from)
        .unwrap_or_else(|| worker.with_file_name("libpdfium.so"));
    let engine = std::env::var("PDF_VIEW_ENGINE").unwrap_or_else(|_| {
        if library.is_file() {
            "pdfium"
        } else {
            "poppler"
        }
        .into()
    });
    command.args(["--setenv", "PDF_VIEW_ENGINE", &engine]);
    if engine == "pdfium" {
        command
            .arg("--ro-bind")
            .arg(library)
            .arg("/app/libpdfium.so");
    }
    command.args(["--", "/app/worker"]);
    // After fork use only allocation-free Rustix syscalls. Mark every inherited
    // descriptor CLOEXEC except the opened PDF; retain the spawn error pipe until exec.
    unsafe {
        command.pre_exec(move || {
            let directory = rustix::fs::open(
                c"/proc/self/fd",
                rustix::fs::OFlags::RDONLY
                    | rustix::fs::OFlags::DIRECTORY
                    | rustix::fs::OFlags::CLOEXEC,
                rustix::fs::Mode::empty(),
            )?;
            let mut buffer = [std::mem::MaybeUninit::uninit(); 2048];
            let mut entries = rustix::fs::RawDir::new(directory, &mut buffer);
            while let Some(entry) = entries.next() {
                let entry = entry?;
                if let Ok(name) = std::str::from_utf8(entry.file_name().to_bytes()) {
                    if let Ok(number) = name.parse::<i32>() {
                        if number >= 3 && number != fd {
                            rustix::io::fcntl_setfd(
                                BorrowedFd::borrow_raw(number),
                                rustix::io::FdFlags::CLOEXEC,
                            )?;
                        }
                    }
                }
            }
            rustix::io::fcntl_setfd(BorrowedFd::borrow_raw(fd), rustix::io::FdFlags::empty())?;
            Ok(())
        });
    }
    command
}
fn validate(mut meta: Value, pixels: Vec<u8>, request: &Value) -> Result<Value> {
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
fn execute(
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
        if cancel_flag.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(limit) {
            break Err("La operación excedió el tiempo permitido.".into());
        }
        match worker_proc.frames.recv_timeout(Duration::from_millis(20)) {
            Ok(frame) => break frame,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(_) => break Err("El motor terminó sin responder.".into()),
        }
    };
    if cancel_flag.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(limit) {
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
fn main() -> io::Result<()> {
    let worker = std::env::var_os("PDF_VIEW_WORKER")
        .map(PathBuf::from)
        .unwrap_or(std::env::current_exe()?.with_file_name("pdf-worker"));
    let cache = Arc::new(Mutex::new(Cache {
        entries: VecDeque::new(),
        bytes: 0,
    }));
    let workers: [Arc<Mutex<Option<WorkerProcess>>>; 3] = [
        Arc::new(Mutex::new(None)),
        Arc::new(Mutex::new(None)),
        Arc::new(Mutex::new(None)),
    ];
    let mut jobs: [Option<Job>; 3] = [None, None, None];
    let mut file: Option<Arc<File>> = None;
    let mut password = String::new();
    let mut stamp = (0, 0, 0);
    let mut input = io::stdin().lock();
    loop {
        let mut line = Vec::new();
        let n = input.by_ref().take(16385).read_until(b'\n', &mut line)?;
        if n == 0 {
            break;
        }
        if n > 16384 {
            break;
        }
        let mut req: Value = match serde_json::from_slice::<Value>(&line) {
            Ok(v) if v.is_object() => v,
            _ => continue,
        };
        let id = req["id"].as_u64().unwrap_or(0);
        let kind = req["kind"].as_u64().unwrap_or(0).min(2) as usize;
        let op = req["op"].as_str().unwrap_or("").to_owned();
        cancel(&mut jobs[kind], &workers[kind]);
        if op == "cancel" {
            continue;
        }
        if op == "open" {
            for (job, w) in jobs.iter_mut().zip(&workers) {
                cancel(job, w);
                w.lock().unwrap().take();
            }
            file = None;
            password.clear();
            cache.lock().unwrap().clear();
            match open_document(req["url"].as_str().unwrap_or("")) {
                Ok(f) => file = Some(Arc::new(f)),
                Err(e) => {
                    emit(id, kind, json!({"error":e}));
                    continue;
                }
            }
            req["op"] = json!("render");
            if req.get("outline").is_none() {
                req["outline"] = json!(true);
            }
        } else if op == "unlock" {
            for (job, w) in jobs.iter_mut().zip(&workers) {
                cancel(job, w);
                w.lock().unwrap().take();
            }
            cache.lock().unwrap().clear();
            password = req["password"].as_str().unwrap_or("").to_owned();
            req["op"] = json!("render");
            if req.get("outline").is_none() {
                req["outline"] = json!(true);
            }
        }
        let Some(file) = file.clone() else {
            emit(id, kind, json!({"error":"Abre un documento."}));
            continue;
        };
        if let Ok(meta) = file.metadata() {
            let next = (meta.mtime(), meta.mtime_nsec(), meta.len());
            if next != stamp {
                cache.lock().unwrap().clear();
                for (job, w) in jobs.iter_mut().zip(&workers) {
                    cancel(job, w);
                    w.lock().unwrap().take();
                }
                stamp = next;
            }
        }
        req.as_object_mut().unwrap().remove("id");
        req.as_object_mut().unwrap().remove("kind");
        req.as_object_mut().unwrap().remove("url");
        let mut key = req.clone();
        key.as_object_mut().unwrap().remove("password");
        let key = key.to_string();
        let cached =
            if ["render", "region", "thumbnail"].contains(&req["op"].as_str().unwrap_or("")) {
                cache.lock().unwrap().get(&key)
            } else {
                None
            };
        if let Some(value) = cached {
            emit(id, kind, value);
            continue;
        }
        req["password"] = json!(password);
        // Bubblewrap's parent-death signal belongs to the spawning thread. Spawn
        // on this long-lived thread so a completed render does not kill the worker.
        {
            let mut slot = workers[kind].lock().unwrap();
            if slot.is_none() {
                match WorkerProcess::spawn(&worker, &file) {
                    Ok(process) => *slot = Some(process),
                    Err(error) => {
                        emit(id, kind, json!({"error":error}));
                        continue;
                    }
                }
            }
        }
        let cancelled = Arc::new(AtomicBool::new(false));
        let flag = cancelled.clone();
        let worker_slot = workers[kind].clone();
        let cache = cache.clone();
        let thread = thread::spawn(move || {
            let value = match execute(&worker_slot, &req, &flag) {
                Ok(v) => v,
                Err(e) => json!({"error":e}),
            };
            if flag.load(Ordering::Relaxed) {
                return;
            }
            if value.get("image").is_some() {
                cache.lock().unwrap().put(key, value.clone());
            }
            emit(id, kind, value);
        });
        jobs[kind] = Some(Job {
            cancel: cancelled,
            thread,
        });
    }
    for (job, w) in jobs.iter_mut().zip(&workers) {
        cancel(job, w);
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_remote_and_invalid_worker_output() {
        assert!(open_document("https://example.com/doc.pdf").is_err());
        assert!(validate(json!({"width":999999}), vec![], &json!({"op":"render"})).is_err());
        assert!(validate(json!({"text":"a"}), vec![0], &json!({"op":"extract"})).is_err());
    }
}
