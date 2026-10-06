//! Protocol conformance, driven over a real Unix socket.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use sporetifyd::ipc::{self, ServerConfig};
use sporetifyd::player::Playback;
use sporetifyd::proto;
use sporetifyd::state::{Shared, Status};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::watch;

struct Server {
    path: PathBuf,
    shared: Arc<Shared>,
    clients: watch::Receiver<usize>,
}

impl Server {
    fn start() -> Self {
        static NEXT: AtomicU32 = AtomicU32::new(0);
        let path = std::env::temp_dir().join(format!(
            "sporetify-test-{}-{}.sock",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path).expect("bind test socket");
        let shared = Shared::new(Status::SignedOut);
        let (clients_tx, clients) = watch::channel(0usize);
        // The session loop is not run, so playback stays unavailable: these
        // tests cover the protocol, not Spotify.
        let playback = Playback::new(shared.clone());
        tokio::spawn(ipc::serve(listener, shared.clone(), playback, ServerConfig { debug_ops: true }, clients_tx));
        Self { path, shared, clients }
    }

    async fn connect(&self) -> Client {
        let stream = UnixStream::connect(&self.path).await.expect("connect");
        let (read_half, write_half) = stream.into_split();
        Client { lines: BufReader::new(read_half), write_half }
    }

    /// A client that has already consumed the `hello` frame.
    async fn client(&self) -> Client {
        let mut client = self.connect().await;
        assert_eq!(client.recv().await["ev"], "hello");
        client
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

struct Client {
    lines: BufReader<OwnedReadHalf>,
    write_half: OwnedWriteHalf,
}

impl Client {
    async fn send_raw(&mut self, line: &str) {
        self.write_half.write_all(line.as_bytes()).await.expect("write");
        self.write_half.write_all(b"\n").await.expect("write");
    }

    async fn send(&mut self, frame: Value) {
        self.send_raw(&frame.to_string()).await;
    }

    /// The next frame, or a panic if the daemon stays silent.
    async fn recv(&mut self) -> Value {
        self.try_recv().await.expect("connection closed")
    }

    async fn try_recv(&mut self) -> Option<Value> {
        let mut line = String::new();
        let read = tokio::time::timeout(Duration::from_secs(2), self.lines.read_line(&mut line))
            .await
            .expect("daemon sent nothing for 2s")
            .expect("read");
        (read > 0).then(|| serde_json::from_str(&line).expect("daemon sent invalid JSON"))
    }
}

fn error_code(frame: &Value) -> &str {
    assert_eq!(frame["ok"], false, "expected an error frame, got {frame}");
    assert_eq!(frame["final"], true, "errors are always final: {frame}");
    frame["error"]["code"].as_str().expect("error.code")
}

#[tokio::test]
async fn hello_is_the_first_frame_and_carries_a_snapshot() {
    let server = Server::start();
    let mut client = server.connect().await;
    let hello = client.recv().await;
    assert_eq!(hello["ev"], "hello");
    assert_eq!(hello["protocol"], proto::PROTOCOL);
    assert_eq!(hello["status"], "signed_out");
    assert_eq!(hello["player"]["playing"], false);
    assert!(hello["daemon"].is_string());
}

#[tokio::test]
async fn player_get_answers_with_one_final_frame() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 1, "op": "player.get", "args": {}, "deadline_ms": 1000})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 1);
    assert_eq!(frame["ok"], true);
    assert_eq!(frame["final"], true);
    assert_eq!(frame["data"]["status"], "signed_out");
    assert_eq!(frame["data"]["player"]["seq"], 0);
}

#[tokio::test]
async fn a_request_without_a_deadline_is_rejected() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 2, "op": "player.get", "args": {}})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 2);
    assert_eq!(error_code(&frame), "bad_request");
}

#[tokio::test]
async fn transport_ops_fail_fast_when_signed_out() {
    let server = Server::start();
    let mut client = server.client().await;
    for (id, op) in [(20, "player.toggle"), (21, "player.next"), (22, "player.pause")] {
        client.send(json!({"id": id, "op": op, "args": {}, "deadline_ms": 1000})).await;
        let frame = client.recv().await;
        assert_eq!(frame["id"], id);
        assert_eq!(error_code(&frame), "unauthorized");
    }
}

#[tokio::test]
async fn transport_ops_validate_their_arguments() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 23, "op": "player.volume", "args": {"value": "loud"}, "deadline_ms": 1000})).await;
    assert_eq!(error_code(&client.recv().await), "bad_request");
    client.send(json!({"id": 24, "op": "player.seek", "args": {}, "deadline_ms": 1000})).await;
    assert_eq!(error_code(&client.recv().await), "bad_request");
}

#[tokio::test]
async fn an_unknown_op_is_a_bad_request() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 3, "op": "nope", "deadline_ms": 1000})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 3);
    assert_eq!(error_code(&frame), "bad_request");
}

#[tokio::test]
async fn a_slow_op_ends_in_timeout_at_its_deadline() {
    let server = Server::start();
    let mut client = server.client().await;
    let started = Instant::now();
    client.send(json!({"id": 4, "op": "debug.sleep", "args": {"ms": 10_000}, "deadline_ms": 100})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 4);
    assert_eq!(error_code(&frame), "timeout");
    let elapsed = started.elapsed();
    assert!(elapsed >= Duration::from_millis(100), "answered before the deadline: {elapsed:?}");
    assert!(elapsed < Duration::from_millis(600), "answered long after the deadline: {elapsed:?}");
}

#[tokio::test]
async fn cancel_ends_the_target_as_cancelled() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 5, "op": "debug.sleep", "args": {"ms": 10_000}, "deadline_ms": 5000})).await;
    client.send(json!({"op": "cancel", "target": 5})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 5);
    assert_eq!(error_code(&frame), "cancelled");

    // The id is dead afterwards: cancelling again is silent, and the
    // connection still answers.
    client.send(json!({"op": "cancel", "target": 5})).await;
    client.send(json!({"id": 6, "op": "player.get", "deadline_ms": 1000})).await;
    assert_eq!(client.recv().await["id"], 6);
}

#[tokio::test]
async fn a_panicking_op_still_produces_a_terminal_frame() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 7, "op": "debug.panic", "deadline_ms": 1000})).await;
    let frame = client.recv().await;
    assert_eq!(frame["id"], 7);
    assert_eq!(error_code(&frame), "internal");
}

#[tokio::test]
async fn malformed_json_is_answered_and_the_connection_survives() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send_raw("{not json").await;
    let frame = client.recv().await;
    assert!(frame["id"].is_null());
    assert_eq!(error_code(&frame), "bad_request");

    client.send(json!({"id": 8, "op": "player.get", "deadline_ms": 1000})).await;
    assert_eq!(client.recv().await["ok"], true);
}

#[tokio::test]
async fn a_duplicate_in_flight_id_does_not_end_the_first_request() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 9, "op": "debug.sleep", "args": {"ms": 150}, "deadline_ms": 2000})).await;
    client.send(json!({"id": 9, "op": "player.get", "deadline_ms": 2000})).await;

    let rejected = client.recv().await;
    assert!(rejected["id"].is_null());
    assert_eq!(error_code(&rejected), "bad_request");

    let first = client.recv().await;
    assert_eq!(first["id"], 9);
    assert_eq!(first["data"]["slept_ms"], 150);
}

#[tokio::test]
async fn requests_run_concurrently() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 10, "op": "debug.sleep", "args": {"ms": 300}, "deadline_ms": 2000})).await;
    client.send(json!({"id": 11, "op": "player.get", "deadline_ms": 2000})).await;
    assert_eq!(client.recv().await["id"], 11, "a fast op must not queue behind a slow one");
    assert_eq!(client.recv().await["id"], 10);
}

#[tokio::test]
async fn status_changes_reach_every_client_without_subscribing() {
    let server = Server::start();
    let mut client = server.client().await;
    server.shared.set_status(Status::Offline);
    let frame = client.recv().await;
    assert_eq!(frame["ev"], "status");
    assert_eq!(frame["status"], "offline");
}

#[tokio::test]
async fn subscribe_and_unsubscribe_report_the_current_topics() {
    let server = Server::start();
    let mut client = server.client().await;
    client.send(json!({"id": 12, "op": "subscribe", "args": {"topics": ["viz", "queue"]}, "deadline_ms": 1000})).await;
    assert_eq!(client.recv().await["data"]["topics"], json!(["queue", "viz"]));
    client.send(json!({"id": 13, "op": "unsubscribe", "args": {"topics": ["viz"]}, "deadline_ms": 1000})).await;
    assert_eq!(client.recv().await["data"]["topics"], json!(["queue"]));
}

#[tokio::test]
async fn an_oversized_line_closes_the_connection() {
    let server = Server::start();
    let mut client = server.client().await;
    let huge = "x".repeat(proto::MAX_LINE_BYTES + 4096);
    // The daemon may hang up mid-write; either way the stream must end.
    let _ = client.write_half.write_all(huge.as_bytes()).await;
    assert!(client.try_recv().await.is_none());
}

#[tokio::test]
async fn disconnecting_cancels_in_flight_work_and_updates_the_client_count() {
    let server = Server::start();
    let mut clients = server.clients.clone();
    let mut client = server.client().await;
    client.send(json!({"id": 14, "op": "debug.sleep", "args": {"ms": 10_000}, "deadline_ms": 20_000})).await;
    tokio::time::timeout(Duration::from_secs(2), clients.wait_for(|n| *n == 1))
        .await
        .expect("client was never counted")
        .expect("server gone");

    drop(client);
    tokio::time::timeout(Duration::from_secs(2), clients.wait_for(|n| *n == 0))
        .await
        .expect("client count did not return to zero")
        .expect("server gone");
}
