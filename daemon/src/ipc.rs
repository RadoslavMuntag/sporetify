//! Socket server: line framing, request supervision, cancellation and event
//! delivery. Guarantees exactly one terminal frame per accepted request.

use std::collections::{HashMap, HashSet};
use std::io;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::unix::OwnedReadHalf;
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc, oneshot, watch, Notify};

use crate::catalog::Catalog;
use crate::ops::{self, Context};
use crate::player::Playback;
use crate::proto::{self, ErrorCode, Incoming, OpError, OpResult};
use crate::state::{Shared, ALWAYS_TOPICS};

/// Lines queued for a client that is not reading. Past this it is dropped.
const OUTBOX_LINES: usize = 256;

#[derive(Clone)]
pub struct ServerConfig {
    pub debug_ops: bool,
}

/// Accept connections until the listener fails. `clients` always holds the
/// number of live connections, which drives the idle exit.
pub async fn serve(
    listener: UnixListener,
    shared: Arc<Shared>,
    playback: Arc<Playback>,
    config: ServerConfig,
    clients: watch::Sender<usize>,
) -> io::Result<()> {
    let clients = Arc::new(clients);
    // One library cache for every connection.
    let catalog = Arc::new(Catalog::default());
    loop {
        let (stream, _) = listener.accept().await?;
        if !same_user(&stream) {
            continue;
        }
        let shared = shared.clone();
        let playback = playback.clone();
        let catalog = catalog.clone();
        let config = config.clone();
        let clients = clients.clone();
        tokio::spawn(async move {
            clients.send_modify(|n| *n += 1);
            connection(stream, shared, playback, catalog, config).await;
            clients.send_modify(|n| *n -= 1);
        });
    }
}

fn same_user(stream: &UnixStream) -> bool {
    // SAFETY: getuid has no preconditions and cannot fail.
    let me = unsafe { libc::getuid() };
    matches!(stream.peer_cred(), Ok(cred) if cred.uid() == me)
}

/// Sends lines to one client. A full outbox means the client stopped
/// reading, so the connection is torn down instead of buffering without end.
#[derive(Clone)]
struct Outbox {
    lines: mpsc::Sender<Arc<str>>,
    overflow: Arc<Notify>,
}

impl Outbox {
    fn send(&self, line: impl Into<Arc<str>>) {
        if let Err(mpsc::error::TrySendError::Full(_)) = self.lines.try_send(line.into()) {
            self.overflow.notify_one();
        }
    }
}

type Pending = Arc<Mutex<HashMap<u64, oneshot::Sender<()>>>>;

async fn connection(
    stream: UnixStream,
    shared: Arc<Shared>,
    playback: Arc<Playback>,
    catalog: Arc<Catalog>,
    config: ServerConfig,
) {
    let (read_half, mut write_half) = stream.into_split();
    let (lines_tx, mut lines_rx) = mpsc::channel::<Arc<str>>(OUTBOX_LINES);
    let outbox = Outbox { lines: lines_tx, overflow: Arc::new(Notify::new()) };

    let writer = tokio::spawn(async move {
        while let Some(line) = lines_rx.recv().await {
            if write_half.write_all(line.as_bytes()).await.is_err()
                || write_half.write_all(b"\n").await.is_err()
            {
                break;
            }
        }
    });

    // Subscribe before the snapshot so no change can fall between the two.
    let mut events = shared.subscribe();
    let (status, player) = shared.snapshot();
    outbox.send(proto::event(
        "hello",
        json!({
            "protocol": proto::PROTOCOL,
            "daemon": env!("CARGO_PKG_VERSION"),
            "status": status,
            "player": player,
        }),
    ));

    let ctx = Context { shared, playback, catalog, debug_ops: config.debug_ops };
    let pending: Pending = Arc::default();
    let mut topics: HashSet<String> = HashSet::new();
    let mut reader = LineReader::new(read_half);

    loop {
        tokio::select! {
            line = reader.next() => match line {
                Ok(Some(line)) => handle_line(&line, &ctx, &outbox, &pending, &mut topics),
                // EOF, an I/O error or an oversized line all end the connection.
                Ok(None) | Err(_) => break,
            },
            event = events.recv() => match event {
                Ok(event) => {
                    if ALWAYS_TOPICS.contains(&event.topic) || topics.contains(event.topic) {
                        outbox.send(event.line);
                    }
                }
                // This client fell behind the event stream; it must resync.
                Err(broadcast::error::RecvError::Lagged(_)) => break,
                Err(broadcast::error::RecvError::Closed) => break,
            },
            _ = outbox.overflow.notified() => break,
        }
    }

    // Dropping the senders cancels every request still in flight.
    pending.lock().expect("pending lock").clear();
    drop(outbox);
    writer.abort();
}

fn handle_line(
    line: &str,
    ctx: &Context,
    outbox: &Outbox,
    pending: &Pending,
    topics: &mut HashSet<String>,
) {
    if line.trim().is_empty() {
        return;
    }
    let incoming: Incoming = match serde_json::from_str(line) {
        Ok(incoming) => incoming,
        Err(e) => {
            outbox.send(proto::orphan_error(&OpError::bad_request(format!("invalid JSON: {e}"))));
            return;
        }
    };
    let Some(op) = incoming.op else {
        outbox.send(reject(incoming.id, "missing 'op'"));
        return;
    };

    // `cancel` has no id and no reply of its own; its target ends `cancelled`.
    if op == "cancel" {
        if let Some(target) = incoming.target {
            if let Some(cancel) = pending.lock().expect("pending lock").remove(&target) {
                let _ = cancel.send(());
            }
        }
        return;
    }

    let Some(id) = incoming.id else {
        outbox.send(reject(None, "missing 'id'"));
        return;
    };
    let Some(deadline_ms) = incoming.deadline_ms.filter(|ms| *ms > 0) else {
        outbox.send(reject(Some(id), "missing 'deadline_ms'"));
        return;
    };

    // Subscriptions are connection state, so they are answered inline.
    if op == "subscribe" || op == "unsubscribe" {
        let result = update_topics(topics, &incoming.args, op == "subscribe");
        outbox.send(proto::terminal(id, &result));
        return;
    }

    let (cancel_tx, cancel_rx) = oneshot::channel();
    {
        let mut pending = pending.lock().expect("pending lock");
        if pending.contains_key(&id) {
            // Answering with this id would end the request already running.
            drop(pending);
            outbox.send(reject(None, &format!("id {id} is already in flight")));
            return;
        }
        pending.insert(id, cancel_tx);
    }

    let deadline = Duration::from_millis(deadline_ms.min(proto::MAX_DEADLINE_MS));
    tokio::spawn(supervise(id, op, incoming.args, deadline, cancel_rx, ctx.clone(), outbox.clone(), pending.clone()));
}

fn reject(id: Option<u64>, message: &str) -> String {
    let error = OpError::bad_request(message);
    match id {
        Some(id) => proto::terminal(id, &Err(error)),
        None => proto::orphan_error(&error),
    }
}

fn update_topics(topics: &mut HashSet<String>, args: &Value, add: bool) -> OpResult {
    let Some(list) = args.get("topics").and_then(Value::as_array) else {
        return Err(OpError::bad_request("'args.topics' must be an array"));
    };
    for topic in list.iter().filter_map(Value::as_str) {
        if add {
            topics.insert(topic.to_owned());
        } else {
            topics.remove(topic);
        }
    }
    let mut current: Vec<&String> = topics.iter().collect();
    current.sort();
    Ok(json!({ "topics": current }))
}

/// Runs one op and reports exactly one outcome, whichever comes first:
/// its result, its deadline, a cancel, or a panic.
#[allow(clippy::too_many_arguments)]
async fn supervise(
    id: u64,
    op: String,
    args: Value,
    deadline: Duration,
    cancel: oneshot::Receiver<()>,
    ctx: Context,
    outbox: Outbox,
    pending: Pending,
) {
    let work = tokio::spawn(ops::dispatch(op, args, ctx));
    let abort = work.abort_handle();

    let result: OpResult = tokio::select! {
        joined = work => match joined {
            Ok(result) => result,
            Err(_) => Err(OpError::new(ErrorCode::Internal, "the daemon hit an internal error")),
        },
        _ = tokio::time::sleep(deadline) => {
            abort.abort();
            Err(OpError::new(ErrorCode::Timeout, "the request did not finish in time"))
        }
        // Resolves on an explicit cancel and when the connection goes away.
        _ = cancel => {
            abort.abort();
            Err(OpError::new(ErrorCode::Cancelled, "cancelled"))
        }
    };

    pending.lock().expect("pending lock").remove(&id);
    outbox.send(proto::terminal(id, &result));
}

/// Newline framing with a hard cap on line length. The buffer lives in the
/// struct, so dropping a pending `next()` (as `select!` does) loses nothing.
struct LineReader {
    read_half: OwnedReadHalf,
    buffer: Vec<u8>,
    scanned: usize,
}

impl LineReader {
    fn new(read_half: OwnedReadHalf) -> Self {
        Self { read_half, buffer: Vec::with_capacity(1024), scanned: 0 }
    }

    /// The next line without its terminator, or `None` at end of stream.
    async fn next(&mut self) -> io::Result<Option<String>> {
        loop {
            if let Some(offset) = self.buffer[self.scanned..].iter().position(|b| *b == b'\n') {
                let end = self.scanned + offset;
                let rest = self.buffer.split_off(end + 1);
                let mut line = std::mem::replace(&mut self.buffer, rest);
                line.truncate(end);
                self.scanned = 0;
                return String::from_utf8(line)
                    .map(Some)
                    .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "line is not UTF-8"));
            }
            self.scanned = self.buffer.len();
            if self.buffer.len() > proto::MAX_LINE_BYTES {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "line too long"));
            }
            if self.read_half.read_buf(&mut self.buffer).await? == 0 {
                return Ok(None);
            }
        }
    }
}
