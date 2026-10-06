//! Cover art, fetched once and kept as files. Frontends are not allowed to
//! load from the network, so they are handed a local path instead.
//!
//! Files live in `$XDG_CACHE_HOME/sporetify/art/`, named by a hash of the
//! address they came from. Nothing is evicted yet.

use std::path::PathBuf;

use librespot_core::Session;

/// Covers are only ever fetched from Spotify's image hosts.
const HOSTS: [&str; 3] = ["https://i.scdn.co/", "https://image-cdn-ak.spotifycdn.com/", "https://image-cdn-fa.spotifycdn.com/"];

/// Refuse anything that is not plausibly a picture.
const MAX_BYTES: usize = 4 * 1024 * 1024;

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
    Some(path)
}

#[cfg(test)]
mod tests {
    use super::path_for;

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
