//! What survives a daemon restart: volume, and where playback left off.
//! Written atomically to `$XDG_STATE_HOME/sporetify/state.json`.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::state::Track;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Saved {
    /// 0.0 to 1.0.
    pub volume: Option<f32>,
    /// The playlist or collection the last track was played from.
    pub context_uri: Option<String>,
    pub track: Option<Track>,
    pub position_ms: u64,
}

fn path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))?;
    Some(base.join("sporetify/state.json"))
}

/// The saved state, or the defaults if there is none or it cannot be read.
pub fn load() -> Saved {
    path()
        .and_then(|path| std::fs::read(path).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

/// Best effort: losing this file only costs the resume point.
pub fn save(saved: &Saved) {
    let Some(path) = path() else { return };
    let Some(dir) = path.parent() else { return };
    let Ok(bytes) = serde_json::to_vec_pretty(saved) else { return };
    let temporary = path.with_extension("json.tmp");
    // Write beside the target and rename, so a crash never leaves half a file.
    if std::fs::create_dir_all(dir).is_ok() && std::fs::write(&temporary, bytes).is_ok() {
        let _ = std::fs::rename(&temporary, &path);
    }
}
