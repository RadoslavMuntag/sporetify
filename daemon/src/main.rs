use std::io;
use std::os::fd::FromRawFd;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use sporetifyd::ipc::{self, ServerConfig};
use sporetifyd::player::Playback;
use sporetifyd::state::{Shared, Status};
use tokio::net::UnixListener;
use tokio::signal::unix::{signal, SignalKind};
use tokio::sync::watch;

const USAGE: &str = "\
Usage: sporetifyd [--socket PATH] [--idle-secs N] [--debug-ops] [--verbose] [--no-connect]

  --socket PATH   Listen here when not started by systemd socket activation
                  (default: $XDG_RUNTIME_DIR/sporetify.sock)
  --idle-secs N   Exit after N seconds without a client; 0 never exits
                  (default: 900)
  --debug-ops     Enable debug.* ops used by the protocol tests
  --verbose       Print librespot's debug log to stderr
  --no-connect    Never connect to Spotify and report offline; for testing
                  what works from the saved library
";

/// Prints librespot's own log lines to stderr. Off unless `--verbose`.
struct StderrLog;

impl log::Log for StderrLog {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.target().starts_with("librespot")
    }
    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{} {}] {}", record.level(), record.target(), record.args());
        }
    }
    fn flush(&self) {}
}

struct Options {
    verbose: bool,
    no_connect: bool,
    socket: Option<PathBuf>,
    idle: Duration,
    debug_ops: bool,
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options { verbose: false, no_connect: false, socket: None, idle: Duration::from_secs(900), debug_ops: false };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket" => {
                options.socket = Some(args.next().ok_or("--socket needs a path")?.into());
            }
            "--idle-secs" => {
                let value = args.next().ok_or("--idle-secs needs a number")?;
                let secs: u64 = value.parse().map_err(|_| format!("bad --idle-secs '{value}'"))?;
                options.idle = Duration::from_secs(secs);
            }
            "--debug-ops" => options.debug_ops = true,
            "--verbose" => options.verbose = true,
            "--no-connect" => options.no_connect = true,
            "--version" => {
                println!("sporetifyd {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument '{other}'")),
        }
    }
    Ok(options)
}

/// The listening socket systemd passed us, if this process was socket-activated.
fn activated_listener() -> io::Result<Option<UnixListener>> {
    let pid_matches = std::env::var("LISTEN_PID").ok().and_then(|v| v.parse::<u32>().ok())
        == Some(std::process::id());
    let fds = std::env::var("LISTEN_FDS").ok().and_then(|v| v.parse::<u32>().ok()).unwrap_or(0);
    if !pid_matches || fds < 1 {
        return Ok(None);
    }
    // SAFETY: systemd guarantees fd 3 is the first passed socket and that it
    // is ours alone when LISTEN_PID names this process.
    let listener = unsafe { std::os::unix::net::UnixListener::from_raw_fd(3) };
    listener.set_nonblocking(true)?;
    UnixListener::from_std(listener).map(Some)
}

/// Bind our own socket for runs outside systemd. Returns the path to remove on exit.
fn bound_listener(path: Option<PathBuf>) -> io::Result<(UnixListener, PathBuf)> {
    let path = match path {
        Some(path) => path,
        None => {
            let runtime = std::env::var_os("XDG_RUNTIME_DIR")
                .ok_or_else(|| io::Error::other("XDG_RUNTIME_DIR is not set; pass --socket"))?;
            PathBuf::from(runtime).join("sporetify.sock")
        }
    };
    if path.exists() {
        if std::os::unix::net::UnixStream::connect(&path).is_ok() {
            return Err(io::Error::new(
                io::ErrorKind::AddrInUse,
                format!("another sporetifyd is already listening on {}", path.display()),
            ));
        }
        std::fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    Ok((listener, path))
}

/// Resolves once there have been no clients for `idle` and nothing is
/// playing. Never resolves for zero.
async fn idle_exit(mut clients: watch::Receiver<usize>, idle: Duration, shared: std::sync::Arc<Shared>) {
    if idle.is_zero() {
        return std::future::pending().await;
    }
    loop {
        if clients.wait_for(|n| *n == 0).await.is_err() {
            return std::future::pending().await;
        }
        tokio::select! {
            // Music with no frontend open is still in use.
            _ = tokio::time::sleep(idle) => if !shared.snapshot().1.playing { return },
            _ = clients.changed() => {}
        }
    }
}

async fn run(options: Options) -> io::Result<()> {
    if options.verbose {
        static LOGGER: StderrLog = StderrLog;
        if log::set_logger(&LOGGER).is_ok() {
            log::set_max_level(log::LevelFilter::Debug);
        }
    }
    let (listener, owned_path) = match activated_listener()? {
        Some(listener) => (listener, None),
        None => {
            let (listener, path) = bound_listener(options.socket)?;
            eprintln!("sporetifyd: listening on {}", path.display());
            (listener, Some(path))
        }
    };

    let shared = Shared::new(Status::Starting);
    let playback = Playback::new(shared.clone());
    let (clients_tx, clients_rx) = watch::channel(0usize);
    let config = ServerConfig { debug_ops: options.debug_ops };

    let mut terminate = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;

    let at_exit = playback.clone();
    let result = tokio::select! {
        served = ipc::serve(listener, shared.clone(), playback.clone(), config, clients_tx) => served,
        _ = async {
            if options.no_connect {
                shared.set_status(Status::Offline);
                std::future::pending::<()>().await
            } else {
                playback.run().await
            }
        } => Ok(()),
        _ = sporetifyd::mpris::run(shared.clone(), at_exit.clone()) => Ok(()),
        _ = idle_exit(clients_rx, options.idle, shared.clone()) => {
            eprintln!("sporetifyd: idle, exiting");
            Ok(())
        }
        _ = terminate.recv() => Ok(()),
        _ = interrupt.recv() => Ok(()),
    };

    at_exit.remember_position();
    if let Some(path) = owned_path {
        let _ = std::fs::remove_file(path);
    }
    result
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    // How the stream is named in the system mixer; librespot reads these.
    if std::env::var_os("PULSE_PROP_application.name").is_none() {
        std::env::set_var("PULSE_PROP_application.name", "Sporetify");
        std::env::set_var("PULSE_PROP_application.icon_name", "audio-x-generic");
        std::env::set_var("PULSE_PROP_media.role", "music");
    }
    let options = match parse_args() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("sporetifyd: {message}\n\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    // MPRIS callbacks are not `Send`, so everything runs on a LocalSet.
    match tokio::task::LocalSet::new().run_until(run(options)).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("sporetifyd: {e}");
            ExitCode::FAILURE
        }
    }
}
