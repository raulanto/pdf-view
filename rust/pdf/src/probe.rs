use std::{
    fs::{self, OpenOptions},
    net::{SocketAddr, TcpStream},
    time::Duration,
};
fn main() {
    let isolated = ["/home", "/run/user", "/etc/passwd"]
        .iter()
        .all(|p| !std::path::Path::new(p).exists())
        && fs::read("/document.pdf").is_ok()
        && OpenOptions::new()
            .write(true)
            .open("/document.pdf")
            .is_err()
        && fs::read_to_string("/proc/net/dev")
            .is_ok_and(|s| s.lines().skip(2).all(|l| l.trim_start().starts_with("lo:")))
        && TcpStream::connect_timeout(
            &"192.0.2.1:80".parse::<SocketAddr>().unwrap(),
            Duration::from_millis(100),
        )
        .is_err();
    let no_leaked_descriptors = fs::read_dir("/proc/self/fd").is_ok_and(|entries| {
        entries.flatten().all(|entry| {
            fs::read_link(entry.path())
                .is_ok_and(|path| !path.to_string_lossy().contains("private-descriptor"))
        })
    });
    let message = if isolated && no_leaked_descriptors {
        "sandbox verified"
    } else {
        "sandbox failed"
    };
    pdf_view_backend::write_frame(&serde_json::json!({"error":message}), &[]).unwrap();
}
