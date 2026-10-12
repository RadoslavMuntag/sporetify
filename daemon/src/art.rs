//! Cover art, fetched once and kept as files. Frontends are not allowed to
//! load from the network, so they are handed a local path instead.
//!
//! Files live in `$XDG_CACHE_HOME/sporetify/art/`, named by a hash of the
//! address they came from. The folder is kept under a size limit by removing
//! the covers that have gone unused the longest.

use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, SystemTime};

use librespot_core::Session;

/// Covers are only ever fetched from Spotify's image hosts.
const HOSTS: [&str; 3] = ["https://i.scdn.co/", "https://image-cdn-ak.spotifycdn.com/", "https://image-cdn-fa.spotifycdn.com/"];

/// Refuse anything that is not plausibly a picture.
const MAX_BYTES: usize = 4 * 1024 * 1024;

/// How big the cover folder may get. Thumbnails are a few kilobytes and full
/// covers around a hundred, so this is tens of thousands of pictures.
const CACHE_LIMIT_BYTES: u64 = 200 * 1024 * 1024;
/// Pruning brings the folder this far below the limit, so it is not needed
/// again straight away.
const CACHE_TARGET_BYTES: u64 = CACHE_LIMIT_BYTES / 10 * 8;
/// The folder is checked after this many downloads.
const PRUNE_EVERY: usize = 200;
/// A cover's timestamp is refreshed on use at most this often.
const TOUCH_AFTER: Duration = Duration::from_secs(24 * 60 * 60);

static DOWNLOADS: AtomicUsize = AtomicUsize::new(0);

fn directory() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))?;
    Some(base.join("sporetify/art"))
}

/// Where the image at `url` is, or would be, stored. `None` for an address
/// that is not one of Spotify's image hosts.
pub fn path_for(url: &str) -> Option<PathBuf> {
    if !HOSTS.iter().any(|host| url.starts_with(host)) {
        return None;
    }
    // FNV-1a, 64 bit: stable across runs, which a std hasher is not.
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in url.bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    Some(directory()?.join(format!("{hash:016x}.jpg")))
}

/// The local file for `url`, downloading it first if it is not there yet.
pub async fn fetch(session: &Session, url: &str) -> Option<PathBuf> {
    let path = path_for(url)?;
    if path.exists() {
        touch(&path);
        return Some(path);
    }
    let bytes = session.spclient().request_url(url).await.ok()?;
    if bytes.is_empty() || bytes.len() > MAX_BYTES {
        return None;
    }
    std::fs::create_dir_all(path.parent()?).ok()?;
    // Write beside the target and rename, so a reader never sees half a picture.
    let temporary = path.with_extension("part");
    std::fs::write(&temporary, &bytes).ok()?;
    std::fs::rename(&temporary, &path).ok()?;
    if DOWNLOADS.fetch_add(1, Ordering::Relaxed) % PRUNE_EVERY == PRUNE_EVERY - 1 {
        prune();
    }
    Some(path)
}

/// Mark a cover as used, so pruning keeps it. The modification time stands
/// in for "last used"; it is only rewritten once it is a day old, so showing
/// a list of covers does not turn into a burst of writes.
fn touch(path: &std::path::Path) {
    let stale = std::fs::metadata(path)
        .and_then(|meta| meta.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|age| age > TOUCH_AFTER);
    if stale {
        if let Ok(file) = std::fs::File::options().write(true).open(path) {
            let _ = file.set_modified(SystemTime::now());
        }
    }
}

/// Bring the cover folder back under its limit. Called at start and every
/// so many downloads; cheap when there is nothing to do.
pub fn prune() {
    let Some(directory) = directory() else { return };
    let Ok(entries) = std::fs::read_dir(&directory) else { return };
    let files: Vec<(PathBuf, u64, SystemTime)> = entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let meta = entry.metadata().ok()?;
            meta.is_file().then(|| (entry.path(), meta.len(), meta.modified().unwrap_or(SystemTime::UNIX_EPOCH)))
        })
        .collect();
    for path in evictions(files, CACHE_LIMIT_BYTES, CACHE_TARGET_BYTES) {
        let _ = std::fs::remove_file(path);
    }
}

/// Which files to remove: none while the total is within `limit`; otherwise
/// the least recently used, until the total is down to `target`.
fn evictions<T>(mut files: Vec<(T, u64, SystemTime)>, limit: u64, target: u64) -> Vec<T> {
    let mut total: u64 = files.iter().map(|(_, size, _)| size).sum();
    if total <= limit {
        return Vec::new();
    }
    files.sort_by_key(|(_, _, used)| *used);
    let mut out = Vec::new();
    for (file, size, _) in files {
        if total <= target {
            break;
        }
        total -= size;
        out.push(file);
    }
    out
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

    use super::{evictions, path_for};

    fn at(seconds: u64) -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(seconds)
    }

    #[test]
    fn nothing_is_removed_while_within_the_limit() {
        let files = vec![("a", 40, at(1)), ("b", 60, at(2))];
        assert!(evictions(files, 100, 80).is_empty());
    }

    #[test]
    fn the_least_recently_used_go_first_until_the_target_is_met() {
        let files = vec![("new", 40, at(30)), ("oldest", 30, at(1)), ("old", 30, at(2)), ("mid", 30, at(10))];
        // 130 over a limit of 100: remove down to 80.
        assert_eq!(evictions(files, 100, 80), vec!["oldest", "old"]);
    }

    #[test]
    fn one_huge_file_does_not_empty_the_cache_needlessly() {
        let files = vec![("big-and-old", 500, at(1)), ("small", 10, at(2))];
        assert_eq!(evictions(files, 100, 80), vec!["big-and-old"]);
    }

    #[test]
    fn only_spotify_image_hosts_are_accepted() {
        assert!(path_for("https://i.scdn.co/image/ab67616d0000b273").is_some());
        assert!(path_for("https://image-cdn-ak.spotifycdn.com/image/x").is_some());
        assert!(path_for("https://example.com/image/x").is_none());
        assert!(path_for("file:///etc/passwd").is_none());
        assert!(path_for("https://i.scdn.co.evil.example/image/x").is_none());
    }

    #[test]
    fn the_same_address_always_maps_to_the_same_file() {
        let a = path_for("https://i.scdn.co/image/one").unwrap();
        assert_eq!(a, path_for("https://i.scdn.co/image/one").unwrap());
        assert_ne!(a, path_for("https://i.scdn.co/image/two").unwrap());
        assert!(a.to_string_lossy().ends_with(".jpg"));
    }
}
