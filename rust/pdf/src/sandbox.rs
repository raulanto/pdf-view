use std::{
    fs::File,
    os::{
        fd::{AsRawFd, BorrowedFd},
        unix::process::CommandExt,
    },
    path::PathBuf,
    process::Command,
};

/// Construye el comando Bubblewrap que lanza el worker aislado.
/// Recibe el archivo ya abierto en solo lectura; lo entrega al worker
/// mediante `--ro-bind-fd` sin reabrir por ruta.
pub fn sandbox(worker: &PathBuf, file: &File) -> Command {
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
