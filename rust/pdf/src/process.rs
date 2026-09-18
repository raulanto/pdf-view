use crate::sandbox::sandbox;
use pdf_view_backend::{read_frame, Result};
use serde_json::Value;
use std::{
    fs::File,
    path::PathBuf,
    process::Stdio,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver},
        Arc, Mutex,
    },
    thread,
};

pub struct Job {
    pub cancel: Arc<AtomicBool>,
    pub thread: thread::JoinHandle<()>,
}

pub struct WorkerProcess {
    pub child: std::process::Child,
    pub stdin: std::process::ChildStdin,
    pub frames: Receiver<Result<(Value, Vec<u8>)>>,
    pub reader: Option<thread::JoinHandle<()>>,
}

impl WorkerProcess {
    pub fn spawn(worker: &PathBuf, file: &File) -> Result<Self> {
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
    pub fn kill(&mut self) {
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

/// Cancela el job activo en `kind` y espera a que el hilo termine.
pub fn cancel(job: &mut Option<Job>, _worker_slot: &Arc<Mutex<Option<WorkerProcess>>>) {
    if let Some(job) = job.take() {
        job.cancel.store(true, Ordering::Relaxed);
        let _ = job.thread.join();
    }
}
