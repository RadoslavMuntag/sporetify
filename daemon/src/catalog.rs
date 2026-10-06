//! The user's library, read through the librespot session's internal API.
//! Nothing here touches the public Web API (it refuses the built-in client
//! id), so no client id of our own is needed.
//!
//! Track metadata never changes, so it is cached on disk for good
//! (`$XDG_CACHE_HOME/sporetify/tracks.v2.json`) and fetched at most once per
//! track, one at a time with bounded concurrency. Lists are cached in memory.
//!
//! Search runs over what is cached. Spotify's own search is not reachable
//! without a client id, so this searches the user's library instead; Liked
//! Songs are indexed in the background the first time the library is used.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use futures_util::stream::{self, StreamExt};
use librespot_core::{Session, SpotifyUri};
use librespot_metadata::{Album, Artist, Metadata, Playlist, Track};
use librespot_protocol::playlist4_external::SelectedListContent;
use protobuf::Message;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::proto::{ErrorCode, OpError, OpResult};

/// How many track lookups may be in flight at once.
const LOOKUPS_IN_FLIGHT: usize = 8;
const MAX_PAGE: usize = 200;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackRow {
    pub uri: String,
    pub title: String,
    pub artists: Vec<String>,
    pub album: String,
    pub duration_ms: u64,
    /// False for entries that cannot be shown or played (removed, regional, not a track).
    pub available: bool,
    /// Parallel to `artists`, for navigating to an artist.
    #[serde(default)]
    pub artist_uris: Vec<String>,
    #[serde(default)]
    pub album_uri: String,
}

/// What an album row needs: enough to list it without its tracks.
#[derive(Debug, Clone, Serialize)]
pub struct AlbumHeader {
    pub uri: String,
    pub name: String,
    pub artists: Vec<String>,
    pub year: i32,
    /// "album", "single", "ep" or "compilation".
    pub kind: String,
    pub tracks: usize,
    /// Address of the cover; `art.get` turns it into a local file.
    pub art_url: Option<String>,
}

#[derive(Clone, Serialize, Deserialize)]
struct List {
    name: String,
    uris: Vec<String>,
}

/// What is kept on disk so the library can be shown without a connection:
/// the sidebar as last seen, and every list that has been loaded.
#[derive(Default, Serialize, Deserialize)]
#[serde(default)]
struct LibraryFile {
    sidebar: Vec<Value>,
    lists: HashMap<String, List>,
}

pub struct Catalog {
    lists: Mutex<HashMap<String, Arc<List>>>,
    /// The playlists response as last fetched, for showing it offline.
    sidebar: Mutex<Vec<Value>>,
    library_unsaved: AtomicBool,
    tracks: Mutex<HashMap<String, TrackRow>>,
    albums: Mutex<HashMap<String, AlbumHeader>>,
    /// Tracks fetched since the cache file was last written.
    unsaved: AtomicBool,
    indexing: AtomicBool,
    indexed: AtomicBool,
    lookup_failure_logged: AtomicBool,
}

impl Default for Catalog {
    fn default() -> Self {
        let library = load_library();
        Self {
            lists: Mutex::new(library.lists.into_iter().map(|(uri, list)| (uri, Arc::new(list))).collect()),
            sidebar: Mutex::new(library.sidebar),
            library_unsaved: AtomicBool::new(false),
            tracks: Mutex::new(load_tracks()),
            albums: Mutex::default(),
            unsaved: AtomicBool::new(false),
            indexing: AtomicBool::new(false),
            indexed: AtomicBool::new(false),
            lookup_failure_logged: AtomicBool::new(false),
        }
    }
}

fn tracks_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))?;
    // v2: rows carry artist and album uris.
    Some(base.join("sporetify/tracks.v2.json"))
}

fn library_path() -> Option<PathBuf> {
    tracks_path().map(|path| path.with_file_name("library.json"))
}

fn load_library() -> LibraryFile {
    library_path()
        .and_then(|path| std::fs::read(path).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

/// Write `bytes` beside `path` and rename, so a crash never leaves half a file.
fn write_atomically(path: &std::path::Path, bytes: &[u8]) {
    let Some(dir) = path.parent() else { return };
    let temporary = path.with_extension("json.tmp");
    if std::fs::create_dir_all(dir).is_ok() && std::fs::write(&temporary, bytes).is_ok() {
        let _ = std::fs::rename(&temporary, path);
    }
}

/// The sidebar from the rootlist's entries, in order. Playlists carry the
/// depth of the folders they sit in; a folder is an entry of its own.
/// `entries` are (uri, name, length).
fn sidebar_entries(liked_uri: &str, entries: &[(String, String, Option<i32>)]) -> Vec<Value> {
    let mut items = vec![json!({ "uri": liked_uri, "name": "Liked Songs", "length": null, "depth": 0 })];
    let mut depth = 0usize;
    for (uri, name, length) in entries {
        if let Some(rest) = uri.strip_prefix("spotify:start-group:") {
            // spotify:start-group:<id>:<name, url-encoded with + for spaces>
            let (id, raw) = rest.split_once(':').unwrap_or((rest, ""));
            items.push(json!({ "kind": "folder", "id": id, "name": percent_decode(raw), "depth": depth }));
            depth += 1;
        } else if uri.starts_with("spotify:end-group:") {
            depth = depth.saturating_sub(1);
        } else if uri.starts_with("spotify:playlist:") {
            items.push(json!({
                "uri": uri,
                "name": if name.is_empty() { "Untitled playlist" } else { name },
                "length": length,
                "depth": depth,
            }));
        }
    }
    items
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let escaped = (bytes[i] == b'%' && i + 2 < bytes.len() + 1)
            .then(|| bytes.get(i + 1..i + 3))
            .flatten()
            .and_then(|hex| std::str::from_utf8(hex).ok())
            .and_then(|hex| u8::from_str_radix(hex, 16).ok());
        match (bytes[i], escaped) {
            (_, Some(byte)) => {
                out.push(byte);
                i += 2;
            }
            (b'+', _) => out.push(b' '),
            (other, _) => out.push(other),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn load_tracks() -> HashMap<String, TrackRow> {
    tracks_path()
        .and_then(|path| std::fs::read(path).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn upstream(what: &str, error: impl std::fmt::Display) -> OpError {
    OpError::new(ErrorCode::Offline, format!("could not load {what} from Spotify: {error}"))
}

pub fn liked_songs_uri(session: &Session) -> String {
    format!("spotify:user:{}:collection", session.username())
}

impl Catalog {
    /// Liked Songs followed by the user's playlists, in their own order.
    pub async fn playlists(&self, session: Option<&Session>) -> OpResult {
        let fetched = match session {
            Some(session) => self.fetch_sidebar(session).await,
            None => Err(OpError::new(ErrorCode::Offline, "not connected to Spotify")),
        };
        match fetched {
            Ok(items) => {
                *self.sidebar.lock().expect("sidebar lock") = items.clone();
                self.library_unsaved.store(true, Ordering::Relaxed);
                self.flush();
                Ok(json!({ "items": items, "stale": false }))
            }
            // Without Spotify, show the sidebar as it was last seen.
            Err(error) => {
                let saved = self.sidebar.lock().expect("sidebar lock").clone();
                if saved.is_empty() {
                    Err(error)
                } else {
                    Ok(json!({ "items": saved, "stale": true }))
                }
            }
        }
    }

    async fn fetch_sidebar(&self, session: &Session) -> Result<Vec<Value>, OpError> {
        let bytes = session
            .spclient()
            .get_rootlist(0, Some(1000))
            .await
            .map_err(|e| upstream("your playlists", e))?;
        let root = SelectedListContent::parse_from_bytes(&bytes).map_err(|e| upstream("your playlists", e))?;
        let contents = root.contents.as_ref();
        let uris = contents.map(|c| c.items.as_slice()).unwrap_or_default();
        let metas = contents.map(|c| c.meta_items.as_slice()).unwrap_or_default();
        let entries: Vec<(String, String, Option<i32>)> = uris
            .iter()
            .enumerate()
            .map(|(index, item)| {
                let meta = metas.get(index);
                (
                    item.uri().to_owned(),
                    meta.map(|m| m.attributes.name().to_owned()).unwrap_or_default(),
                    meta.and_then(|m| m.length),
                )
            })
            .collect();
        Ok(sidebar_entries(&liked_songs_uri(session), &entries))
    }

    /// One page of a playlist's (or Liked Songs') tracks, with metadata.
    pub async fn tracks(
        &self,
        session: Option<&Session>,
        uri: &str,
        offset: usize,
        limit: usize,
        refresh: bool,
    ) -> OpResult {
        let limit = limit.clamp(1, MAX_PAGE);
        let (list, rows) = match session {
            Some(session) => {
                let list = self.list(session, uri, refresh).await?;
                let page = list.uris.iter().skip(offset).take(limit).cloned().collect();
                let rows = self.rows(session, page, LOOKUPS_IN_FLIGHT).await;
                (list, rows)
            }
            // Offline: whatever was saved, with placeholders for the rest.
            None => {
                let list = self.lists.lock().expect("lists lock").get(uri).cloned().ok_or_else(|| {
                    OpError::new(ErrorCode::Offline, "this list was not saved before going offline")
                })?;
                let tracks = self.tracks.lock().expect("tracks lock");
                let rows = list
                    .uris
                    .iter()
                    .skip(offset)
                    .take(limit)
                    .map(|uri| tracks.get(uri).cloned().unwrap_or_else(|| unavailable_row(uri.clone())))
                    .collect();
                (list, rows)
            }
        };

        Ok(json!({
            "uri": uri,
            "name": list.name,
            "total": list.uris.len(),
            "offset": offset,
            "items": self.decorate(rows),
        }))
    }

    /// The uris in Liked Songs, if that list has been loaded.
    fn liked_set(&self) -> HashSet<String> {
        let lists = self.lists.lock().expect("lists lock");
        lists
            .iter()
            .find(|(uri, _)| uri.ends_with(":collection"))
            .map(|(_, list)| list.uris.iter().cloned().collect())
            .unwrap_or_default()
    }

    /// Rows as sent to clients: each carries whether the track is liked.
    fn decorate(&self, rows: Vec<TrackRow>) -> Vec<Value> {
        let liked = self.liked_set();
        rows.into_iter()
            .map(|row| {
                let is_liked = liked.contains(&row.uri);
                let mut value = serde_json::to_value(row).unwrap_or(Value::Null);
                value["liked"] = json!(is_liked);
                value
            })
            .collect()
    }

    /// Track rows for `uris`, decorated, for places that are not a stored list.
    pub async fn decorated_rows(&self, session: &Session, uris: Vec<String>) -> Vec<Value> {
        let rows = self.rows(session, uris, LOOKUPS_IN_FLIGHT).await;
        self.decorate(rows)
    }

    async fn rows(&self, session: &Session, uris: Vec<String>, in_flight: usize) -> Vec<TrackRow> {
        let rows = stream::iter(uris)
            .map(|track_uri| self.track(session, track_uri))
            .buffered(in_flight)
            .collect()
            .await;
        self.flush();
        rows
    }

    /// Write the track cache if it has grown. Losing it only costs refetching.
    fn flush(&self) {
        if self.unsaved.swap(false, Ordering::Relaxed) {
            let bytes = serde_json::to_vec(&*self.tracks.lock().expect("tracks lock"));
            if let (Some(path), Ok(bytes)) = (tracks_path(), bytes) {
                write_atomically(&path, &bytes);
            }
        }
        if self.library_unsaved.swap(false, Ordering::Relaxed) {
            let file = LibraryFile {
                sidebar: self.sidebar.lock().expect("sidebar lock").clone(),
                lists: self
                    .lists
                    .lock()
                    .expect("lists lock")
                    .iter()
                    .map(|(uri, list)| (uri.clone(), (**list).clone()))
                    .collect(),
            };
            if let (Some(path), Ok(bytes)) = (library_path(), serde_json::to_vec(&file)) {
                write_atomically(&path, &bytes);
            }
        }
    }

    /// Fetch every list in the library and its tracks' metadata, once, in
    /// the background: Liked Songs first, then each playlist. Afterwards
    /// search covers the whole library, and all of it can be shown offline.
    pub fn index_in_background(self: &Arc<Self>, session: &Session) {
        if self.indexed.load(Ordering::Relaxed) || self.indexing.swap(true, Ordering::Relaxed) {
            return;
        }
        let (this, session) = (self.clone(), session.clone());
        tokio::spawn(async move {
            // Liked Songs must be complete; a playlist may hold entries that
            // can never be looked up (episodes, local files, removed tracks),
            // so those get fewer retries and do not hold the index open.
            let liked = liked_songs_uri(&session);
            let missing = this.index_list(&session, &liked, 4).await;
            if missing.unwrap_or(1) > 0 {
                eprintln!("sporetifyd: liked songs are not fully indexed yet; will retry later");
            }

            let playlists: Vec<String> = this
                .sidebar
                .lock()
                .expect("sidebar lock")
                .iter()
                .filter_map(|item| item["uri"].as_str())
                .filter(|uri| uri.starts_with("spotify:playlist:"))
                .map(str::to_owned)
                .collect();
            for uri in playlists {
                let _ = this.index_list(&session, &uri, 2).await;
            }

            this.flush();
            // An incomplete index is retried the next time the library is opened.
            this.indexed.store(missing == Some(0), Ordering::Relaxed);
            this.indexing.store(false, Ordering::Relaxed);
        });
    }

    /// Load one list and all of its rows, gently. Returns how many rows
    /// could not be fetched, or `None` if the list itself could not be.
    async fn index_list(&self, session: &Session, uri: &str, attempts: u64) -> Option<usize> {
        let list = self.list(session, uri, false).await.ok()?;
        let mut missing = 0;
        // Small chunks with pauses: nobody is waiting on this, and Spotify
        // throttles bursts of lookups.
        for chunk in list.uris.chunks(20) {
            let mut failed = usize::MAX;
            for attempt in 0..attempts {
                let rows = self.rows(session, chunk.to_vec(), 3).await;
                failed = rows.iter().filter(|row| !row.available).count();
                if failed == 0 {
                    break;
                }
                // Cached rows come back at once, so a retry only repeats the
                // lookups that failed.
                if attempt + 1 < attempts {
                    tokio::time::sleep(std::time::Duration::from_secs(2 + attempt * 4)).await;
                }
            }
            missing += failed;
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        }
        Some(missing)
    }

    /// Tracks in the user's library whose title, artists or album contain
    /// every word of `query`. Only cached metadata is searched.
    pub fn search(&self, query: &str, limit: usize) -> OpResult {
        let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
        let lists = self.lists.lock().expect("lists lock");
        let tracks = self.tracks.lock().expect("tracks lock");

        // Liked Songs first, then playlists by name, so results are stable.
        let mut ordered: Vec<(&String, &Arc<List>)> = lists.iter().collect();
        ordered.sort_by_key(|(uri, list)| (!uri.ends_with(":collection"), list.name.to_lowercase()));

        let liked: HashSet<&String> = lists
            .iter()
            .find(|(uri, _)| uri.ends_with(":collection"))
            .map(|(_, list)| list.uris.iter().collect())
            .unwrap_or_default();
        let mut seen = HashSet::new();
        let mut items = Vec::new();
        let mut total = 0usize;
        if !words.is_empty() {
            for (context_uri, list) in ordered {
                for uri in &list.uris {
                    let Some(row) = tracks.get(uri) else { continue };
                    if !row.available || !seen.insert(uri) {
                        continue;
                    }
                    let haystack =
                        format!("{} {} {}", row.title, row.artists.join(" "), row.album).to_lowercase();
                    if words.iter().all(|word| haystack.contains(word.as_str())) {
                        total += 1;
                        if items.len() < limit {
                            let mut item = serde_json::to_value(row).unwrap_or(Value::Null);
                            item["liked"] = json!(liked.contains(uri));
                            item["context_uri"] = json!(context_uri);
                            item["context_name"] = json!(list.name);
                            items.push(item);
                        }
                    }
                }
            }
        }
        Ok(json!({
            "query": query,
            "items": items,
            "total": total,
            "indexing": self.indexing.load(Ordering::Relaxed),
        }))
    }

    async fn list(&self, session: &Session, uri: &str, refresh: bool) -> Result<Arc<List>, OpError> {
        if !refresh {
            if let Some(list) = self.lists.lock().expect("lists lock").get(uri) {
                return Ok(list.clone());
            }
        }
        let list = if uri.ends_with(":collection") {
            self.liked_songs(session, uri).await?
        } else if uri.starts_with("spotify:album:") {
            let (album, uris) = self.fetch_album(session, uri).await?;
            List { name: album.name, uris }
        } else if uri.starts_with("spotify:artist:") {
            let artist = fetch_artist(session, uri).await?;
            List { name: artist.name.clone(), uris: top_tracks(session, &artist) }
        } else {
            let id = SpotifyUri::from_uri(uri).map_err(|_| OpError::bad_request(format!("not a playlist: '{uri}'")))?;
            let playlist = Playlist::get(session, &id).await.map_err(|e| upstream("the playlist", e))?;
            List { name: playlist.name().to_owned(), uris: playlist.tracks().filter_map(|t| t.to_uri().ok()).collect() }
        };
        let list = Arc::new(list);
        self.lists.lock().expect("lists lock").insert(uri.to_owned(), list.clone());
        self.library_unsaved.store(true, Ordering::Relaxed);
        Ok(list)
    }

    async fn fetch_album(&self, session: &Session, uri: &str) -> Result<(AlbumHeader, Vec<String>), OpError> {
        let id = SpotifyUri::from_uri(uri).map_err(|_| OpError::bad_request(format!("not an album: '{uri}'")))?;
        let album = Album::get(session, &id).await.map_err(|e| upstream("the album", e))?;
        let uris: Vec<String> = album.tracks().filter_map(|t| t.to_uri().ok()).collect();
        let header = AlbumHeader {
            uri: uri.to_owned(),
            name: album.name.clone(),
            artists: album.artists.iter().map(|a| a.name.clone()).collect(),
            year: album.date.as_utc().year(),
            kind: format!("{:?}", album.album_type).to_lowercase(),
            tracks: uris.len(),
            art_url: image_url(&album.covers),
        };
        self.albums.lock().expect("albums lock").insert(uri.to_owned(), header.clone());
        Ok((header, uris))
    }

    /// An album with all of its tracks.
    pub async fn album(&self, session: &Session, uri: &str) -> OpResult {
        let (header, uris) = self.fetch_album(session, uri).await?;
        self.lists
            .lock()
            .expect("lists lock")
            .insert(uri.to_owned(), Arc::new(List { name: header.name.clone(), uris: uris.clone() }));
        let rows = self.rows(session, uris, LOOKUPS_IN_FLIGHT).await;
        Ok(json!({ "album": header, "items": self.decorate(rows) }))
    }

    async fn album_header(&self, session: &Session, uri: String) -> Option<AlbumHeader> {
        if let Some(header) = self.albums.lock().expect("albums lock").get(&uri) {
            return Some(header.clone());
        }
        self.fetch_album(session, &uri).await.ok().map(|(header, _)| header)
    }

    /// An artist: their most played tracks and their releases.
    pub async fn artist(&self, session: &Session, uri: &str) -> OpResult {
        let artist = fetch_artist(session, uri).await?;
        let top = top_tracks(session, &artist);
        self.lists
            .lock()
            .expect("lists lock")
            .insert(uri.to_owned(), Arc::new(List { name: artist.name.clone(), uris: top.clone() }));

        let releases = |uris: Vec<String>| async move {
            let mut headers: Vec<AlbumHeader> = stream::iter(uris)
                .map(|album_uri| self.album_header(session, album_uri))
                .buffered(LOOKUPS_IN_FLIGHT)
                .filter_map(|header| async move { header })
                .collect()
                .await;
            headers.sort_by(|a, b| b.year.cmp(&a.year).then_with(|| a.name.cmp(&b.name)));
            headers
        };
        let take = |uris: Vec<&SpotifyUri>| -> Vec<String> {
            uris.into_iter().filter_map(|u| u.to_uri().ok()).take(MAX_RELEASES).collect()
        };
        let albums = releases(take(artist.albums_current().collect())).await;
        let singles = releases(take(artist.singles_current().collect())).await;
        let rows = self.rows(session, top, LOOKUPS_IN_FLIGHT).await;

        Ok(json!({
            "artist": { "uri": uri, "name": artist.name, "art_url": image_url(&artist.portrait_group).or_else(|| image_url(&artist.portraits)) },
            "top_tracks": self.decorate(rows),
            "albums": albums,
            "singles": singles,
        }))
    }

    /// Search all of Spotify, through the search service its own apps use
    /// (a persisted GraphQL query), with the session's credentials. Needs no
    /// client id. Tracks found are cached like any other.
    pub async fn search_spotify(&self, session: &Session, query: &str, limit: usize) -> OpResult {
        use http_body_util::BodyExt;

        let unreachable = |e: String| upstream("search results", e);
        let token = session.login5().auth_token().await.map_err(|e| unreachable(e.to_string()))?;
        let client_token = session.spclient().client_token().await.map_err(|e| unreachable(e.to_string()))?;

        let variables = json!({
            "searchTerm": query, "offset": 0, "limit": limit, "numberOfTopResults": 5,
            "includeAudiobooks": false,
        });
        let hash = std::env::var("SPORETIFY_SEARCH_HASH").unwrap_or_else(|_| SEARCH_QUERY_HASH.to_owned());
        let extensions = json!({ "persistedQuery": { "version": 1, "sha256Hash": hash } });
        let url = format!(
            "https://api-partner.spotify.com/pathfinder/v1/query?operationName=searchDesktop&variables={}&extensions={}",
            percent_encode(&variables.to_string()),
            percent_encode(&extensions.to_string()),
        );
        let request = http::Request::builder()
            .method(http::Method::GET)
            .uri(url)
            .header(http::header::AUTHORIZATION, format!("Bearer {}", token.access_token))
            .header("client-token", client_token)
            .header(http::header::ACCEPT, "application/json")
            .header("app-platform", "WebPlayer")
            .body(bytes::Bytes::new())
            .map_err(|e| unreachable(e.to_string()))?;
        let response = session.http_client().request(request).await.map_err(|e| unreachable(e.to_string()))?;
        let status = response.status();
        let body = response.into_body().collect().await.map_err(|e| unreachable(e.to_string()))?.to_bytes();

        if status == http::StatusCode::TOO_MANY_REQUESTS {
            return Err(OpError::new(ErrorCode::RateLimited, "Spotify asked us to slow down"));
        }
        let parsed: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
        let found = &parsed["data"]["search"];
        if !status.is_success() || !found.is_object() {
            // Most likely Spotify retired this version of its search query.
            return Err(OpError::new(
                ErrorCode::Internal,
                format!("Spotify's search did not answer as expected (HTTP {})", status.as_u16()),
            ));
        }

        let text = |value: &Value| value.as_str().unwrap_or_default().to_owned();
        let names = |artists: &Value, field: &str| -> Vec<String> {
            artists["items"]
                .as_array()
                .map(|items| {
                    items
                        .iter()
                        .map(|artist| if field == "uri" { text(&artist["uri"]) } else { text(&artist["profile"]["name"]) })
                        .collect()
                })
                .unwrap_or_default()
        };
        let each = |section: &str| found[section]["items"].as_array().cloned().unwrap_or_default();

        let mut rows = Vec::new();
        for item in each("tracks") {
            let track = &item["track"];
            let uri = text(&track["uri"]);
            if uri.is_empty() {
                continue;
            }
            let row = TrackRow {
                uri: uri.clone(),
                title: text(&track["name"]),
                artists: names(&track["artists"], "name"),
                artist_uris: names(&track["artists"], "uri"),
                album: text(&track["album"]["name"]),
                album_uri: text(&track["album"]["uri"]),
                duration_ms: track["duration"]["totalMilliseconds"].as_u64().unwrap_or(0),
                available: track["playability"]["playable"].as_bool().unwrap_or(true),
            };
            if row.available {
                self.tracks.lock().expect("tracks lock").entry(uri).or_insert_with(|| row.clone());
                self.unsaved.store(true, Ordering::Relaxed);
            }
            rows.push(row);
        }
        self.flush();

        let artists: Vec<Value> = each("artists")
            .iter()
            .filter(|artist| artist["uri"].is_string())
            .map(|artist| json!({ "uri": artist["uri"], "name": artist["profile"]["name"] }))
            .collect();
        let albums: Vec<Value> = each("albums")
            .iter()
            .filter(|album| album["uri"].is_string())
            .map(|album| json!({
                "uri": album["uri"],
                "name": album["name"],
                "artists": names(&album["artists"], "name"),
                "year": album["date"]["year"],
                "kind": text(&album["type"]).to_lowercase(),
            }))
            .collect();
        let playlists: Vec<Value> = each("playlists")
            .iter()
            .filter(|playlist| playlist["uri"].is_string())
            .map(|playlist| json!({
                "uri": playlist["uri"], "name": playlist["name"], "owner": playlist["owner"]["name"],
            }))
            .collect();

        Ok(json!({
            "query": query,
            "tracks": self.decorate(rows),
            "artists": artists,
            "albums": albums,
            "playlists": playlists,
        }))
    }

    /// Add a track to Liked Songs or remove it, through the collection
    /// service the official clients use. Needs no client id.
    pub async fn set_liked(&self, session: &Session, uri: &str, liked: bool) -> OpResult {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let body = collection_write(&session.username(), uri, now, !liked);

        let mut headers = http::HeaderMap::new();
        let kind = http::HeaderValue::from_static("application/vnd.collection-v2.spotify.proto");
        headers.insert(http::header::CONTENT_TYPE, kind.clone());
        headers.insert(http::header::ACCEPT, kind);
        session
            .spclient()
            .request(&http::Method::POST, "/collection/v2/write", Some(headers), Some(&body))
            .await
            .map_err(|e| upstream("the change to your liked songs", e))?;

        // Keep the cached Liked Songs list in step, newest first like Spotify.
        let key = liked_songs_uri(session);
        let mut lists = self.lists.lock().expect("lists lock");
        if let Some(list) = lists.get(&key).cloned() {
            let mut uris: Vec<String> = list.uris.iter().filter(|u| u.as_str() != uri).cloned().collect();
            if liked {
                uris.insert(0, uri.to_owned());
            }
            lists.insert(key, Arc::new(List { name: list.name.clone(), uris }));
        }
        Ok(json!({ "uri": uri, "liked": liked }))
    }

    /// Whether a track is in Liked Songs, as far as the cached list knows.
    pub async fn is_liked(&self, session: &Session, uri: &str) -> OpResult {
        let list = self.list(session, &liked_songs_uri(session), false).await?;
        Ok(json!({ "uri": uri, "liked": list.uris.iter().any(|u| u == uri) }))
    }

    /// One track's row, for navigating from a track the view has no row for.
    pub async fn track_row(&self, session: &Session, uri: &str) -> OpResult {
        let row = self.track(session, uri.to_owned()).await;
        self.flush();
        Ok(json!({ "track": self.decorate(vec![row]).pop() }))
    }

    /// What plays after `current` in `context_uri`, in the list's own order.
    pub async fn up_next(&self, session: &Session, context_uri: &str, current: &str, limit: usize) -> OpResult {
        let list = self.list(session, context_uri, false).await?;
        let position = list.uris.iter().position(|uri| uri == current);
        let start = position.map(|index| index + 1).unwrap_or(0);
        let upcoming: Vec<String> = list.uris.iter().skip(start).take(limit).cloned().collect();
        let rows = self.rows(session, upcoming, LOOKUPS_IN_FLIGHT).await;
        Ok(json!({
            "context_uri": context_uri,
            "context_name": list.name,
            "position": position,
            "total": list.uris.len(),
            "items": self.decorate(rows),
        }))
    }

    async fn liked_songs(&self, session: &Session, uri: &str) -> Result<List, OpError> {
        let context = session.spclient().get_context(uri).await.map_err(|e| upstream("your liked songs", e))?;
        let uris = context
            .pages
            .iter()
            .flat_map(|page| page.tracks.iter())
            .map(|track| track.uri().to_owned())
            .filter(|uri| !uri.is_empty())
            .collect();
        Ok(List { name: "Liked Songs".to_owned(), uris })
    }

    async fn track(&self, session: &Session, uri: String) -> TrackRow {
        if let Some(row) = self.tracks.lock().expect("tracks lock").get(&uri) {
            return row.clone();
        }
        let fetched = match SpotifyUri::from_uri(&uri) {
            Ok(id) => match Track::get(session, &id).await {
                Ok(track) => Some(track),
                Err(e) => {
                    // One line per daemon run is enough to explain a pattern.
                    if !self.lookup_failure_logged.swap(true, Ordering::Relaxed) {
                        eprintln!("sporetifyd: track lookup failed (further failures not logged): {e}");
                    }
                    None
                }
            },
            Err(_) => None,
        };
        match fetched {
            Some(track) => {
                let row = TrackRow {
                    uri: uri.clone(),
                    title: track.name,
                    artists: track.artists.iter().map(|a| a.name.clone()).collect(),
                    artist_uris: track.artists.iter().filter_map(|a| a.id.to_uri().ok()).collect(),
                    album_uri: track.album.id.to_uri().unwrap_or_default(),
                    album: track.album.name,
                    duration_ms: u64::try_from(track.duration).unwrap_or(0),
                    available: true,
                };
                // Track metadata does not change, so it is kept for good.
                self.tracks.lock().expect("tracks lock").insert(uri, row.clone());
                self.unsaved.store(true, Ordering::Relaxed);
                row
            }
            // Not cached: a failed lookup may succeed next time.
            None => unavailable_row(uri),
        }
    }
}

/// Identifies the `searchDesktop` query on Spotify's side. Spotify replaces
/// these from time to time; when search starts failing with an HTTP error,
/// this is the first thing to check. `SPORETIFY_SEARCH_HASH` overrides it.
const SEARCH_QUERY_HASH: &str = "75bbf6bfcfdf85b8fc828417bfad92b7cd66bf7f556d85670f4da8292373ebec";

/// Percent-encoding for a URL query value.
fn percent_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len() * 3);
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

/// A `spotify.collection.proto.v2.WriteRequest` for one item. librespot does
/// not compile this message, and it is small enough to encode by hand:
///
/// ```text
/// WriteRequest   { 1: username, 2: set, 3: repeated CollectionItem, 4: client_update_id }
/// CollectionItem { 1: uri, 2: added_at (int32 seconds), 3: is_removed }
/// ```
fn collection_write(username: &str, uri: &str, now_secs: u64, remove: bool) -> Vec<u8> {
    fn varint(out: &mut Vec<u8>, mut value: u64) {
        while value >= 0x80 {
            out.push((value as u8 & 0x7f) | 0x80);
            value >>= 7;
        }
        out.push(value as u8);
    }
    fn bytes(out: &mut Vec<u8>, field: u8, value: &[u8]) {
        out.push(field << 3 | 2);
        varint(out, value.len() as u64);
        out.extend_from_slice(value);
    }

    let mut item = Vec::new();
    bytes(&mut item, 1, uri.as_bytes());
    item.push(2 << 3);
    varint(&mut item, now_secs);
    if remove {
        item.extend_from_slice(&[3 << 3, 1]);
    }

    let mut request = Vec::new();
    bytes(&mut request, 1, username.as_bytes());
    bytes(&mut request, 2, b"collection");
    bytes(&mut request, 3, &item);
    bytes(&mut request, 4, format!("{now_secs:016x}{:08x}", uri.len()).as_bytes());
    request
}

/// The address of the largest of `images`.
fn image_url(images: &librespot_metadata::image::Images) -> Option<String> {
    let image = images.iter().max_by_key(|image| image.width)?;
    Some(format!("https://i.scdn.co/image/{}", image.id.to_base16().ok()?))
}

fn unavailable_row(uri: String) -> TrackRow {
    TrackRow {
        uri,
        title: "Unavailable".to_owned(),
        artists: Vec::new(),
        album: String::new(),
        duration_ms: 0,
        available: false,
        artist_uris: Vec::new(),
        album_uri: String::new(),
    }
}

/// Albums and singles listed per artist.
const MAX_RELEASES: usize = 30;
const TOP_TRACKS: usize = 10;

async fn fetch_artist(session: &Session, uri: &str) -> Result<Artist, OpError> {
    let id = SpotifyUri::from_uri(uri).map_err(|_| OpError::bad_request(format!("not an artist: '{uri}'")))?;
    Artist::get(session, &id).await.map_err(|e| upstream("the artist", e))
}

fn top_tracks(session: &Session, artist: &Artist) -> Vec<String> {
    artist
        .top_tracks
        .for_country(&session.country())
        .iter()
        .filter_map(|track| track.to_uri().ok())
        .take(TOP_TRACKS)
        .collect()
}

pub fn page_args(args: &Value) -> (usize, usize) {
    let read = |key: &str, default: u64| args.get(key).and_then(Value::as_u64).unwrap_or(default) as usize;
    (read("offset", 0), read("limit", 50))
}

#[cfg(test)]
mod tests {
    use super::collection_write;

    #[test]
    fn collection_write_encodes_the_documented_fields() {
        let body = collection_write("u", "spotify:track:x", 300, true);
        let expected: Vec<u8> = [
            &[0x0a, 1, b'u'][..],                      // 1: username
            &[0x12, 10][..], b"collection",            // 2: set
            &[0x1a, 22, 0x0a, 15][..], b"spotify:track:x", // 3: item { 1: uri
            &[0x10, 0xac, 0x02, 0x18, 1][..],          //   2: added_at = 300, 3: is_removed }
            &[0x22, 24][..], b"000000000000012c0000000f", // 4: client_update_id
        ]
        .concat();
        assert_eq!(body, expected);
    }

    #[test]
    fn percent_encode_keeps_unreserved_and_escapes_the_rest() {
        assert_eq!(super::percent_encode("a-Z_0.~"), "a-Z_0.~");
        assert_eq!(super::percent_encode("{\"q\":\"a b&c\"}"), "%7B%22q%22%3A%22a%20b%26c%22%7D");
        assert_eq!(super::percent_encode("é"), "%C3%A9");
    }

    #[test]
    fn sidebar_keeps_folders_and_depth() {
        let entry = |uri: &str, name: &str| (uri.to_owned(), name.to_owned(), Some(3));
        let items = super::sidebar_entries(
            "spotify:user:u:collection",
            &[
                entry("spotify:playlist:a", "Top"),
                entry("spotify:start-group:f1:Road+trips%21", ""),
                entry("spotify:playlist:b", ""),
                entry("spotify:start-group:f2:Inner", ""),
                entry("spotify:playlist:c", "Deep"),
                entry("spotify:end-group:f2", ""),
                entry("spotify:end-group:f1", ""),
                entry("spotify:playlist:d", "After"),
                entry("spotify:end-group:stray", ""),
            ],
        );
        let brief: Vec<(String, u64)> = items
            .iter()
            .map(|item| (item["name"].as_str().unwrap_or("").to_owned(), item["depth"].as_u64().unwrap_or(99)))
            .collect();
        assert_eq!(
            brief,
            [
                ("Liked Songs", 0), ("Top", 0), ("Road trips!", 0), ("Untitled playlist", 1),
                ("Inner", 1), ("Deep", 2), ("After", 0),
            ]
            .map(|(name, depth)| (name.to_owned(), depth))
        );
        assert_eq!(items[2]["kind"], "folder");
        assert_eq!(items[2]["id"], "f1");
        assert!(items[1]["kind"].is_null());
    }

    #[test]
    fn percent_decode_handles_plus_escapes_and_stray_percent() {
        assert_eq!(super::percent_decode("a+b%20c"), "a b c");
        assert_eq!(super::percent_decode("caf%C3%A9"), "café");
        assert_eq!(super::percent_decode("100%"), "100%");
        assert_eq!(super::percent_decode("%zz"), "%zz");
    }

    #[test]
    fn collection_write_omits_is_removed_when_adding() {
        let body = collection_write("u", "spotify:track:x", 300, false);
        assert!(!body.windows(2).any(|pair| pair == [0x18, 1]));
    }
}
