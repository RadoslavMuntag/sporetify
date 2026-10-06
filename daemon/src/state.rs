//! The single authoritative state and its change stream. Every mutation goes
//! through `Shared`, so socket subscribers (and later MPRIS) cannot disagree.

use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::sync::broadcast;

use crate::proto;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Starting,
    Ready,
    Offline,
    SignedOut,
    NoPremium,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Track {
    /// Spotify URI, e.g. `spotify:track:...`.
    pub id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub album: String,
    pub duration_ms: u64,
    pub art_url: Option<String>,
    /// The cover as a local file, once it has been fetched.
    #[serde(default)]
    pub art_path: Option<String>,
}

/// Playback position as a point in time, so clients can interpolate locally.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Position {
    pub position_ms: u64,
    /// Unix time in milliseconds when `position_ms` was true.
    pub at_ms: u64,
    /// 1.0 while playing, 0.0 while paused.
    pub rate: f32,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PlayerState {
    /// Incremented on every change; clients resync when they see a gap.
    pub seq: u64,
    pub track: Option<Track>,
    pub playing: bool,
    pub position: Position,
    pub volume: f32,
    pub shuffle: bool,
    pub repeat: bool,
    pub device: Option<String>,
}

/// A pre-serialised event line and the topic that gates its delivery.
#[derive(Debug, Clone)]
pub struct Event {
    pub topic: &'static str,
    pub line: Arc<str>,
}

/// Topics every client receives without subscribing.
pub const ALWAYS_TOPICS: [&str; 2] = ["player", "status"];

struct Inner {
    status: Status,
    player: PlayerState,
}

pub struct Shared {
    inner: Mutex<Inner>,
    events: broadcast::Sender<Event>,
}

impl Shared {
    pub fn new(status: Status) -> Arc<Self> {
        let (events, _) = broadcast::channel(64);
        Arc::new(Self {
            inner: Mutex::new(Inner { status, player: PlayerState::default() }),
            events,
        })
    }

    pub fn snapshot(&self) -> (Status, PlayerState) {
        let inner = self.inner.lock().expect("state lock");
        (inner.status, inner.player.clone())
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.events.subscribe()
    }

    pub fn set_status(&self, status: Status) {
        {
            let mut inner = self.inner.lock().expect("state lock");
            if inner.status == status {
                return;
            }
            inner.status = status;
        }
        self.emit("status", proto::event("status", json!({ "status": status })));
    }

    /// Apply a change to the player state. Subscribers are told only when
    /// something actually changed, and always get the whole new state.
    pub fn update_player(&self, change: impl FnOnce(&mut PlayerState)) {
        let line = {
            let mut inner = self.inner.lock().expect("state lock");
            let mut next = inner.player.clone();
            change(&mut next);
            if next == inner.player {
                return;
            }
            next.seq = inner.player.seq + 1;
            inner.player = next;
            proto::event("player", json!({ "player": inner.player }))
        };
        self.emit("player", line);
    }

    /// Tell clients a browser sign-in ended without signing anyone in.
    pub fn emit_auth_failure(&self, message: &str) {
        self.emit("status", proto::event("auth", json!({ "ok": false, "message": message })));
    }

    fn emit(&self, topic: &'static str, line: String) {
        // No receivers is normal: nobody is connected.
        let _ = self.events.send(Event { topic, line: line.into() });
    }
}
