//! Files only the user may read.
//!
//! The resume point and the library cache name what the user listens to,
//! their playlists and their Spotify user id. They are written with mode
//! 0600 into folders of mode 0700, whatever the process's umask is, and
//! anything an earlier version left more open is closed at start.

use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

const FILE_MODE: u32 = 0o600;
const DIR_MODE: u32 = 0o700;

/// Create `dir` if needed and make it readable by the user alone. Parents
/// that had to be created get the same mode; ones that existed are left.
pub fn dir(dir: &Path) -> std::io::Result<()> {
    std::fs::DirBuilder::new().recursive(true).mode(DIR_MODE).create(dir)?;
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(DIR_MODE))
}

/// Write `bytes` to `path` so that a crash never leaves half a file and no
/// one else can read it: a private file beside the target, then a rename.
pub fn write(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let parent = path.parent().ok_or_else(|| std::io::Error::other("no parent folder"))?;
    dir(parent)?;
    let mut name = path.file_name().ok_or_else(|| std::io::Error::other("no file name"))?.to_owned();
    name.push(".tmp");
    let temporary = parent.join(name);
    {
        let mut file =
            std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(FILE_MODE).open(&temporary)?;
        // The mode above only applies to a file that did not exist yet.
        file.set_permissions(std::fs::Permissions::from_mode(FILE_MODE))?;
        file.write_all(bytes)?;
    }
    std::fs::rename(&temporary, path)
}

fn base(variable: &str, fallback: &str) -> Option<PathBuf> {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(fallback)))
}

/// Run once at start, before anything is written: make every file created
/// from here on private by default, and close what is already on disk.
pub fn secure_at_start() {
    // SAFETY: umask only swaps the process's file mode mask and cannot fail.
    unsafe {
        libc::umask(0o077);
    }
    let folders = [
        base("XDG_CACHE_HOME", ".cache").map(|base| base.join("sporetify")),
        base("XDG_STATE_HOME", ".local/state").map(|base| base.join("sporetify")),
    ];
    for folder in folders.into_iter().flatten() {
        close(&folder);
    }
}

/// Take away group and other access from `folder`, the files directly in
/// it, and its cover folder. Missing things are fine.
fn close(folder: &Path) {
    if !folder.is_dir() {
        return;
    }
    let _ = std::fs::set_permissions(folder, std::fs::Permissions::from_mode(DIR_MODE));
    let _ = std::fs::set_permissions(folder.join("art"), std::fs::Permissions::from_mode(DIR_MODE));
    let Ok(entries) = std::fs::read_dir(folder) else { return };
    for entry in entries.flatten() {
        if entry.file_type().is_ok_and(|kind| kind.is_file()) {
            let _ = std::fs::set_permissions(entry.path(), std::fs::Permissions::from_mode(FILE_MODE));
        }
    }
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("sporetify-private-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn mode(path: &Path) -> u32 {
        std::fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn a_new_file_and_its_folder_are_private() {
        let root = scratch("new");
        let path = root.join("sporetify/state.json");
        super::write(&path, b"{}").unwrap();
        assert_eq!(mode(&path), 0o600);
        assert_eq!(mode(path.parent().unwrap()), 0o700);
        assert_eq!(std::fs::read(&path).unwrap(), b"{}");
        assert!(!root.join("sporetify/state.json.tmp").exists());
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn rewriting_closes_a_file_and_folder_that_were_open() {
        let root = scratch("open");
        let dir = root.join("sporetify");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.join("library.json");
        std::fs::write(&path, b"old").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        // A stale temporary file left open by an older version.
        std::fs::write(dir.join("library.json.tmp"), b"junk").unwrap();
        std::fs::set_permissions(dir.join("library.json.tmp"), std::fs::Permissions::from_mode(0o644)).unwrap();

        super::write(&path, b"new").unwrap();
        assert_eq!(mode(&path), 0o600);
        assert_eq!(mode(&dir), 0o700);
        assert_eq!(std::fs::read(&path).unwrap(), b"new");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn closing_a_folder_covers_what_is_already_there() {
        let root = scratch("close");
        let dir = root.join("sporetify");
        std::fs::create_dir_all(dir.join("art")).unwrap();
        for name in ["library.json", "tracks.v3.json", "art/cover.jpg"] {
            std::fs::write(dir.join(name), b"x").unwrap();
            std::fs::set_permissions(dir.join(name), std::fs::Permissions::from_mode(0o644)).unwrap();
        }
        for folder in [dir.clone(), dir.join("art")] {
            std::fs::set_permissions(folder, std::fs::Permissions::from_mode(0o755)).unwrap();
        }

        super::close(&dir);
        assert_eq!(mode(&dir), 0o700);
        assert_eq!(mode(&dir.join("art")), 0o700);
        assert_eq!(mode(&dir.join("library.json")), 0o600);
        assert_eq!(mode(&dir.join("tracks.v3.json")), 0o600);
        // Covers are reached only through their folder, which is closed.
        super::close(&root.join("missing"));
        let _ = std::fs::remove_dir_all(root);
    }
}
