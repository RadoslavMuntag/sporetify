//! Wire types and frame builders for the socket protocol.
//! The contract is `.claude/architecture/03-protocol.md`.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Bumped on any incompatible change. Clients require equality until v1.
pub const PROTOCOL: u32 = 0;

/// Longest line the daemon will buffer from a client.
pub const MAX_LINE_BYTES: usize = 64 * 1024;

/// Upper bound applied to every client-supplied deadline.
pub const MAX_DEADLINE_MS: u64 = 30_000;

/// One line from a client. Every field is optional so that a malformed
/// request can still be answered with a precise `bad_request`.
#[derive(Debug, Deserialize)]
pub struct Incoming {
    pub id: Option<u64>,
    pub op: Option<String>,
    #[serde(default)]
    pub args: Value,
    pub deadline_ms: Option<u64>,
    /// Only used by `cancel`.
    pub target: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    Timeout,
    Offline,
    RateLimited,
    Unauthorized,
    NoPremium,
    NoAudio,
    NotFound,
    Cancelled,
    BadRequest,
    Internal,
}

#[derive(Debug, Clone, Serialize)]
pub struct OpError {
    pub code: ErrorCode,
    pub message: String,
    pub retry_after_ms: Option<u64>,
}

impl OpError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into(), retry_after_ms: None }
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::BadRequest, message)
    }
}

pub type OpResult = Result<Value, OpError>;

/// The single terminal frame of a request.
pub fn terminal(id: u64, result: &OpResult) -> String {
    match result {
        Ok(data) => json!({
            "id": id, "ok": true, "stale": false, "final": true, "data": data,
        }),
        Err(error) => json!({
            "id": id, "ok": false, "final": true, "error": error,
        }),
    }
    .to_string()
}

/// An error for a line that carries no usable id.
pub fn orphan_error(error: &OpError) -> String {
    json!({ "id": null, "ok": false, "final": true, "error": error }).to_string()
}

/// An unsolicited frame: `{"ev": name, ...fields}`.
pub fn event(name: &str, fields: Value) -> String {
    let mut frame = match fields {
        Value::Object(map) => map,
        _ => serde_json::Map::new(),
    };
    frame.insert("ev".into(), Value::String(name.into()));
    Value::Object(frame).to_string()
}
