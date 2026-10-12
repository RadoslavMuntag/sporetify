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
    path().map(|path| load_from(&path)).unwrap_or_default()
}

/// Best effort: losing this file only costs the resume point.
pub fn save(saved: &Saved) {
    if let Some(path) = path() {
        save_to(&path, saved);
    }
}

fn load_from(path: &std::path::Path) -> Saved {
    std::fs::read(path).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default()
}

fn save_to(path: &std::path::Path, saved: &Saved) {
    let Some(dir) = path.parent() else { return };
    let Ok(bytes) = serde_json::to_vec_pretty(saved) else { return };
    let temporary = path.with_extension("json.tmp");
    // Write beside the target and rename, so a crash never leaves half a file.
    if std::fs::create_dir_all(dir).is_ok() && std::fs::write(&temporary, bytes).is_ok() {
        let _ = std::fs::rename(&temporary, path);
    }
}

#[cfg(test)]
mod tests {
    use super::{load_from, save_to, Saved};
    use crate::state::Track;

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("sporetify-persist-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir.join("nested/state.json")
    }

    #[test]
    fn what_is_saved_is_what_is_loaded() {
        let path = scratch("roundtrip");
        let saved = Saved {
            volume: Some(0.42),
            context_uri: Some("spotify:playlist:x".into()),
            track: Some(Track {
                id: "spotify:track:y".into(),
                title: "Title".into(),
                artists: vec!["A".into(), "B".into()],
                album: "Album".into(),
                duration_ms: 1234,
                art_url: Some("https://i.scdn.co/image/z".into()),
                art_path: None,
            }),
            position_ms: 5678,
        };
        save_to(&path, &saved);
        assert_eq!(load_from(&path), saved);
        // Nothing is left behind from the atomic write.
        assert!(!path.with_extension("json.tmp").exists());
    }

    #[test]
    fn a_missing_or_broken_file_gives_the_defaults() {
        let path = scratch("broken");
        assert_eq!(load_from(&path), Saved::default());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, b"{ not json").unwrap();
        assert_eq!(load_from(&path), Saved::default());
    }

    #[test]
    fn a_file_from_an_older_version_still_loads() {
        let path = scratch("older");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        // No context, and a track without the cover fields added later.
        std::fs::write(&path, br#"{"volume":0.5,"track":{"id":"t","title":"T","artists":[],"album":"","duration_ms":1,"art_url":null}}"#).unwrap();
        let loaded = load_from(&path);
        assert_eq!(loaded.volume, Some(0.5));
        assert_eq!(loaded.context_uri, None);
        assert_eq!(loaded.track.unwrap().art_path, None);
    }
}
