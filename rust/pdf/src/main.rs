mod cache;
mod process;
mod protocol;
mod sandbox;

use cache::Cache;
use process::{cancel, Job, WorkerProcess};
use protocol::{emit, execute, open_document};
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs::File,
    io::{self, BufRead, Read},
    os::unix::fs::MetadataExt,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
};

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
