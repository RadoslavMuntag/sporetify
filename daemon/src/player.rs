//! Playback: the librespot session, the Spotify Connect device and the
//! translation of player events into `PlayerState`.
//!
//! Commands never wait for Spotify. They are handed to librespot's own queue
//! and return at once; the outcome arrives later as a `player` event.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use librespot_connect::{ConnectConfig, LoadRequest, LoadRequestOptions, PlayingTrack, Spirc};
use librespot_core::authentication::Credentials;
use librespot_core::config::SessionConfig;
use librespot_core::session::Session;
use librespot_metadata::audio::UniqueFields;
use librespot_oauth::OAuthToken;
use librespot_playback::audio_backend;
use librespot_playback::config::{AudioFormat, PlayerConfig};
use librespot_playback::mixer::{self, MixerConfig};
use librespot_playback::player::{Player, PlayerEvent};
use tokio::sync::Notify;

use crate::auth::{self, AuthError};
use crate::persist::{self, Saved};
use crate::proto::{ErrorCode, OpError};
use crate::state::{PlayerState, Position, Shared, Status, Track};

const DEVICE_NAME: &str = "Sporetify";
const RETRY_MIN: Duration = Duration::from_secs(2);
const RETRY_MAX: Duration = Duration::from_secs(60);
/// How often a connected session is checked for having been given up. When
/// the network goes away under an open connection (a cable pulled, a switch
/// of network), librespot notices only through its keep-alive, about 80 s
/// later, and marks the session invalid without ending the Connect task.
const SESSION_CHECK: Duration = Duration::from_secs(2);
/// Music that stopped because the connection was lost starts again by itself
/// if the connection is back within this long.
const RESUME_WINDOW: Duration = Duration::from_secs(5 * 60);
/// How often librespot reports the position it is really playing. Kept in
/// the daemon, never sent to frontends.
const HEARD_INTERVAL: Duration = Duration::from_secs(1);

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Command {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Seek(u32),
    /// 0.0 to 1.0.
    Volume(f32),
    /// Relative change, e.g. 0.05 or -0.05.
    VolumeStep(f32),
    Shuffle(bool),
    Repeat(bool),
}

/// What to start playing: a playlist or Liked Songs, optionally from one track.
#[derive(Debug, Clone)]
pub struct PlayRequest {
    pub context_uri: String,
    pub track_uri: Option<String>,
}

struct Active {
    spirc: Spirc,
    session: Session,
    username: String,
}

pub struct Playback {
    shared: Arc<Shared>,
    active: Mutex<Option<Active>>,
    /// A token handed over by a browser sign-in, used before the keyring.
    fresh_token: Mutex<Option<OAuthToken>>,
    signing_in: Mutex<bool>,
    /// Wakes the session loop: signed in, signed out, or asked to retry.
    wake: Notify,
    sign_out: Notify,
    /// True while a session is connected and commands can be accepted.
    ready: tokio::sync::watch::Sender<bool>,
    /// Whether this device has a track loaded. Until it does, the track in
    /// `PlayerState` is only the remembered one and "play" has to load it.
    loaded: AtomicBool,
    /// Volume and resume point, mirrored to disk.
    saved: Mutex<Saved>,
    /// Tracks queued from here that have not started yet. Spotify's queue
    /// cannot be read back, so this is the only record of it.
    queued: Mutex<Vec<String>>,
    /// The last position librespot reported while sound was really coming
    /// out: (track uri, position). Unlike the state's position it does not
    /// move on when playback stalls.
    heard: Mutex<Option<(String, u64)>>,
    /// Set when a session was lost while music played, to start it again
    /// once the next session is up.
    resume: Mutex<Option<Instant>>,
}

impl Playback {
    pub fn new(shared: Arc<Shared>) -> Arc<Self> {
        Arc::new(Self {
            shared,
            active: Mutex::new(None),
            fresh_token: Mutex::new(None),
            signing_in: Mutex::new(false),
            wake: Notify::new(),
            sign_out: Notify::new(),
            ready: tokio::sync::watch::Sender::new(false),
            loaded: AtomicBool::new(false),
            saved: Mutex::new(persist::load()),
            queued: Mutex::new(Vec::new()),
            heard: Mutex::new(None),
            resume: Mutex::new(None),
        })
    }

    /// Wait out a connection attempt that is under way, so a command sent
    /// to a daemon that was just started lands instead of failing. Returns
    /// at once in every other state; the caller's deadline bounds the wait.
    pub async fn settle(&self) {
        if self.shared.snapshot().0 != Status::Starting {
            return;
        }
        let mut ready = self.ready.subscribe();
        let mut status = self.shared.subscribe();
        loop {
            if *ready.borrow_and_update() || self.shared.snapshot().0 != Status::Starting {
                return;
            }
            tokio::select! {
                changed = ready.changed() => if changed.is_err() { return },
                _ = status.recv() => {}
            }
        }
    }

    /// Hand a command to the player. Returns immediately.
    pub fn command(&self, command: Command) -> Result<(), OpError> {
        let active = self.active.lock().expect("active lock");
        let Some(active) = active.as_ref() else {
            return Err(self.unavailable());
        };
        let (_, player) = self.shared.snapshot();
        let spirc = &active.spirc;

        let sent = match command {
            Command::Play | Command::Toggle if !self.loaded.load(Ordering::Relaxed) => {
                // Nothing is loaded on this device yet, so "play" resumes
                // where the user left off, or starts their liked songs.
                let saved = self.saved.lock().expect("saved lock").clone();
                let context = saved
                    .context_uri
                    .unwrap_or_else(|| format!("spotify:user:{}:collection", active.username));
                // Remembered so "up next" knows what is playing from where.
                self.remember(|saved| saved.context_uri = Some(context.clone()));
                let options = LoadRequestOptions {
                    start_playing: true,
                    seek_to: saved.track.as_ref().map(|_| saved.position_ms as u32).unwrap_or(0),
                    playing_track: saved.track.map(|track| PlayingTrack::Uri(track.id)),
                    ..Default::default()
                };
                // Only an active device accepts a load. Activation resets the
                // device to its initial volume, so the current one is re-applied.
                spirc
                    .activate()
                    .and_then(|_| spirc.set_volume(to_device_volume(player.volume)))
                    .and_then(|_| spirc.load(LoadRequest::from_context_uri(context, options)))
            }
            Command::Play => spirc.play(),
            Command::Pause => spirc.pause(),
            Command::Toggle => spirc.play_pause(),
            Command::Next => spirc.next(),
            Command::Previous => spirc.prev(),
            Command::Seek(position_ms) => spirc.set_position_ms(position_ms),
            Command::Volume(volume) => spirc.set_volume(to_device_volume(volume)),
            Command::VolumeStep(delta) => spirc.set_volume(to_device_volume(player.volume + delta)),
            Command::Shuffle(on) => spirc.shuffle(on),
            Command::Repeat(on) => spirc.repeat(on),
        };
        sent.map_err(|e| OpError::new(ErrorCode::Internal, format!("the player did not accept the command: {e}")))?;

        if let Command::Volume(_) | Command::VolumeStep(_) = command {
            // Kept even if the device is not active and ignores the command.
            let volume = match command {
                Command::Volume(volume) => volume,
                _ => player.volume + match command { Command::VolumeStep(delta) => delta, _ => 0.0 },
            };
            self.remember(|saved| saved.volume = Some(volume.clamp(0.0, 1.0)));
        }

        // Reflect the intent now; librespot's events confirm or correct it.
        self.shared.update_player(|state| match command {
            Command::Play => set_playing(state, true),
            Command::Pause => set_playing(state, false),
            Command::Toggle if state.track.is_some() => set_playing(state, !state.playing),
            Command::Volume(volume) => state.volume = volume.clamp(0.0, 1.0),
            Command::VolumeStep(delta) => state.volume = (state.volume + delta).clamp(0.0, 1.0),
            Command::Shuffle(on) => state.shuffle = on,
            Command::Repeat(on) => state.repeat = on,
            _ => {}
        });
        Ok(())
    }

    /// The connected session, for library lookups.
    pub fn connected_session(&self) -> Result<Session, OpError> {
        match self.active.lock().expect("active lock").as_ref() {
            Some(active) => Ok(active.session.clone()),
            None => Err(self.unavailable()),
        }
    }

    /// Start a playlist or Liked Songs. Returns immediately.
    pub fn play_context(&self, request: PlayRequest) -> Result<(), OpError> {
        let active = self.active.lock().expect("active lock");
        let Some(active) = active.as_ref() else {
            return Err(self.unavailable());
        };
        let (_, player) = self.shared.snapshot();
        let context_uri = request.context_uri.clone();
        self.remember(|saved| saved.context_uri = Some(context_uri));
        let options = LoadRequestOptions {
            start_playing: true,
            playing_track: request.track_uri.map(PlayingTrack::Uri),
            ..Default::default()
        };
        let spirc = &active.spirc;
        // Activating is ignored when already active; when it is not, it
        // resets the volume, so the current one is re-applied.
        let _ = spirc.activate();
        spirc
            .set_volume(to_device_volume(player.volume))
            .and_then(|_| spirc.load(LoadRequest::from_context_uri(request.context_uri, options)))
            .map_err(|e| OpError::new(ErrorCode::Internal, format!("the player did not accept the command: {e}")))
    }

    /// The playlist, album or artist the current track is playing from, as
    /// far as this daemon knows: it is only known when playback was started
    /// from here.
    pub fn context_uri(&self) -> Option<String> {
        self.saved.lock().expect("saved lock").context_uri.clone()
    }

    /// Change the remembered state and write it out.
    fn remember(&self, change: impl FnOnce(&mut Saved)) {
        let mut saved = self.saved.lock().expect("saved lock");
        let before = saved.clone();
        change(&mut saved);
        if *saved != before {
            persist::save(&saved);
        }
    }

    /// Record where playback is right now. Called before the daemon exits.
    /// Like `remember_position`, but from the position last heard playing,
    /// when it belongs to the current track.
    fn remember_heard_position(&self) {
        let (_, state) = self.shared.snapshot();
        let Some(track) = state.track.clone() else { return };
        let heard = self.heard.lock().expect("heard lock").clone();
        let position_ms = resume_position(heard.as_ref(), &track.id, state.position.position_ms);
        self.remember(|saved| {
            saved.position_ms = position_ms;
            saved.track = Some(track);
        });
    }

    pub fn remember_position(&self) {
        let (_, state) = self.shared.snapshot();
        if state.track.is_none() {
            return;
        }
        let elapsed = if state.playing { now_ms().saturating_sub(state.position.at_ms) } else { 0 };
        self.remember(|saved| {
            saved.position_ms = state.position.position_ms + elapsed;
            saved.track = state.track;
        });
    }

    /// Ask Spotify to put a track at the front of this device's queue. The
    /// request goes out the way another device's "add to queue" would, and
    /// comes back to librespot as a remote command, because librespot has no
    /// local call for it.
    pub async fn queue_add(&self, uri: &str) -> Result<(), OpError> {
        let session = self.connected_session()?;
        let device = session.device_id().to_owned();
        let body = serde_json::json!({
            "command": {
                "endpoint": "add_to_queue",
                "track": { "uri": uri, "metadata": { "is_queued": "true" }, "provider": "queue" },
                "logging_params": { "command_id": format!("{:032x}", now_ms() as u128 * 2_654_435_761) },
            }
        })
        .to_string();
        let mut headers = http::HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, http::HeaderValue::from_static("application/json"));
        let endpoint = format!("/connect-state/v1/player/command/from/{device}/to/{device}");
        session
            .spclient()
            .request(&http::Method::POST, &endpoint, Some(headers), Some(body.as_bytes()))
            .await
            .map_err(|e| OpError::new(ErrorCode::Internal, format!("Spotify did not accept the queue request: {e}")))?;
        self.queued.lock().expect("queued lock").push(uri.to_owned());
        Ok(())
    }

    /// Tracks queued from here that are still waiting, oldest first.
    pub fn queued(&self) -> Vec<String> {
        self.queued.lock().expect("queued lock").clone()
    }

    fn unavailable(&self) -> OpError {
        match self.shared.snapshot().0 {
            Status::SignedOut => OpError::new(ErrorCode::Unauthorized, "not signed in to Spotify"),
            Status::NoPremium => OpError::new(ErrorCode::NoPremium, "Spotify Premium is required to play"),
            Status::Offline => OpError::new(ErrorCode::Offline, "not connected to Spotify"),
            _ => OpError::new(ErrorCode::Offline, "still connecting to Spotify"),
        }
    }

    /// Start the browser sign-in in the background. Its outcome arrives as a
    /// `status` event (or an `auth` event carrying the failure).
    pub fn begin_sign_in(self: &Arc<Self>) -> Result<(), OpError> {
        {
            let mut signing_in = self.signing_in.lock().expect("signing_in lock");
            if *signing_in {
                return Ok(());
            }
            *signing_in = true;
        }
        let this = self.clone();
        tokio::spawn(async move {
            match auth::sign_in().await {
                Ok(token) => {
                    *this.fresh_token.lock().expect("token lock") = Some(token);
                    this.wake.notify_one();
                }
                Err(e) => {
                    eprintln!("sporetifyd: sign-in failed: {e}");
                    this.shared.emit_auth_failure(&e.to_string());
                }
            }
            *this.signing_in.lock().expect("signing_in lock") = false;
        });
        Ok(())
    }

    pub async fn sign_out(&self) -> Result<(), OpError> {
        auth::forget().await.map_err(|e| OpError::new(ErrorCode::Internal, e.to_string()))?;
        self.sign_out.notify_one();
        Ok(())
    }

    /// Ask a waiting session loop to try again now (e.g. the user hit retry).
    pub fn retry(&self) {
        self.wake.notify_one();
    }

    /// The session loop: sign in from the keyring, run the Connect device,
    /// and come back after any disconnect. Never returns.
    pub async fn run(self: Arc<Self>) {
        let mut retry_in = RETRY_MIN;
        loop {
            let token = match self.next_token().await {
                Ok(Some(token)) => token,
                Ok(None) => {
                    self.shared.set_status(Status::SignedOut);
                    self.wake.notified().await;
                    continue;
                }
                Err(AuthError::Rejected) => {
                    eprintln!("sporetifyd: stored sign-in was rejected; signing out");
                    let _ = auth::forget().await;
                    continue;
                }
                Err(AuthError::Other(message)) => {
                    eprintln!("sporetifyd: could not refresh sign-in: {message}");
                    self.wait_offline(&mut retry_in).await;
                    continue;
                }
            };

            self.shared.set_status(Status::Starting);
            match self.session(token).await {
                Ok(SessionEnd::SignedOut) => retry_in = RETRY_MIN,
                Ok(SessionEnd::Disconnected) => {
                    retry_in = RETRY_MIN;
                    self.wait_offline(&mut retry_in).await;
                }
                Err(message) => {
                    eprintln!("sporetifyd: could not start playback: {message}");
                    if message.to_lowercase().contains("premium") {
                        self.shared.set_status(Status::NoPremium);
                        self.wake.notified().await;
                    } else {
                        self.wait_offline(&mut retry_in).await;
                    }
                }
            }
        }
    }

    async fn next_token(&self) -> Result<Option<OAuthToken>, AuthError> {
        if let Some(token) = self.fresh_token.lock().expect("token lock").take() {
            return Ok(Some(token));
        }
        auth::restore().await
    }

    async fn wait_offline(&self, retry_in: &mut Duration) {
        self.shared.set_status(Status::Offline);
        tokio::select! {
            _ = tokio::time::sleep(*retry_in) => {}
            _ = self.wake.notified() => {}
        }
        *retry_in = (*retry_in * 2).min(RETRY_MAX);
    }

    /// One connected session, from connect until it ends.
    async fn session(&self, token: OAuthToken) -> Result<SessionEnd, String> {
        let session = Session::new(SessionConfig::default(), None);
        let credentials = Credentials::with_access_token(&token.access_token);

        let mixer = mixer::find(None).ok_or("no volume mixer available")?(MixerConfig::default())
            .map_err(|e| e.to_string())?;
        let backend = audio_backend::find(None).ok_or("no audio backend available")?;
        let player = Player::new(
            PlayerConfig { position_update_interval: Some(HEARD_INTERVAL), ..PlayerConfig::default() },
            session.clone(),
            mixer.get_soft_volume(),
            move || backend(None, AudioFormat::default()),
        );
        let mut events = player.get_player_event_channel();

        let saved = self.saved.lock().expect("saved lock").clone();
        let mut config = ConnectConfig { name: DEVICE_NAME.to_owned(), ..Default::default() };
        if let Some(volume) = saved.volume {
            config.initial_volume = to_device_volume(volume);
        }
        let initial_volume = config.initial_volume;
        let (spirc, spirc_task) = Spirc::new(config, session.clone(), credentials, player.clone(), mixer)
            .await
            .map_err(|e| e.to_string())?;
        // Boxed so it can be handed to another thread at the end.
        let mut spirc_task = Box::pin(spirc_task);

        *self.active.lock().expect("active lock") =
            Some(Active { spirc, session: session.clone(), username: session.username() });
        self.shared.update_player(|state| {
            *state = PlayerState {
                volume: from_device_volume(initial_volume),
                device: Some(DEVICE_NAME.to_owned()),
                // Shown paused until "play" loads it for real.
                position: Position { position_ms: saved.position_ms, at_ms: now_ms(), rate: 0.0 },
                track: saved.track,
                ..PlayerState::default()
            };
        });
        self.shared.set_status(Status::Ready);
        self.ready.send_replace(true);
        // The remembered track's cover, so it shows before anything plays.
        self.fetch_art();

        // Music that stopped with the last lost connection plays on.
        let resume = self.resume.lock().expect("resume lock").take();
        if resume.is_some_and(|lost| lost.elapsed() < RESUME_WINDOW) {
            eprintln!("sporetifyd: connected again; resuming where the music stopped");
            if let Err(e) = self.command(Command::Play) {
                eprintln!("sporetifyd: could not resume: {}", e.message);
            }
        }

        let mut check = tokio::time::interval(SESSION_CHECK);
        check.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let end = loop {
            tokio::select! {
                _ = check.tick() => if session.is_invalid() {
                    eprintln!("sporetifyd: lost the connection to Spotify; reconnecting");
                    break SessionEnd::Disconnected;
                },
                _ = &mut spirc_task => break SessionEnd::Disconnected,
                event = events.recv() => match event {
                    Some(event) => self.apply(event),
                    None => break SessionEnd::Disconnected,
                },
                _ = self.sign_out.notified() => break SessionEnd::SignedOut,
            }
        };

        if end == SessionEnd::Disconnected && self.shared.snapshot().1.playing {
            // The sound may have stopped well before the session was given
            // up: keep the position last heard, not the one the state has
            // moved on to since, and start again from there.
            self.remember_heard_position();
            *self.resume.lock().expect("resume lock") = Some(Instant::now());
        } else {
            self.remember_position();
        }
        self.queued.lock().expect("queued lock").clear();
        self.loaded.store(false, Ordering::Relaxed);
        self.ready.send_replace(false);
        if let Some(active) = self.active.lock().expect("active lock").take() {
            let _ = active.spirc.shutdown();
        }
        player.stop();
        // librespot's Player joins its threads when the last handle goes,
        // and a track load caught on a dead connection never finishes. Let
        // that wait happen on a thread of its own: on this one it would stop
        // the whole daemon, requests and reconnecting included.
        let teardown = std::thread::Builder::new().name("session-teardown".into()).spawn(move || {
            drop(spirc_task);
            drop(player);
        });
        if let Err(e) = teardown {
            eprintln!("sporetifyd: could not start the session teardown: {e}");
        }
        self.shared.update_player(|state| *state = PlayerState::default());
        Ok(end)
    }

    fn apply(&self, event: PlayerEvent) {
        if let PlayerEvent::PositionChanged { track_id, position_ms, .. } = &event {
            // Only for `heard`: the frontends interpolate the position
            // themselves, and a state change every second would wake them.
            if let Ok(uri) = track_id.to_uri() {
                *self.heard.lock().expect("heard lock") = Some((uri, u64::from(*position_ms)));
            }
            return;
        }
        match &event {
            PlayerEvent::TrackChanged { audio_item } => {
                self.loaded.store(true, Ordering::Relaxed);
                // A queued track that starts playing has left the queue.
                let mut queued = self.queued.lock().expect("queued lock");
                if let Some(index) = queued.iter().position(|uri| *uri == audio_item.uri) {
                    queued.remove(index);
                }
            }
            PlayerEvent::Loading { .. } => self.loaded.store(true, Ordering::Relaxed),
            // Another device took over, or the context ran out.
            PlayerEvent::Stopped { .. } => self.loaded.store(false, Ordering::Relaxed),
            _ => {}
        }
        let track_changed = matches!(event, PlayerEvent::TrackChanged { .. });
        let worth_saving = matches!(
            event,
            PlayerEvent::TrackChanged { .. }
                | PlayerEvent::Paused { .. }
                | PlayerEvent::VolumeChanged { .. }
                | PlayerEvent::Seeked { .. }
        );
        self.apply_to_state(event);
        if track_changed {
            self.fetch_art();
        }
        if worth_saving {
            let (_, state) = self.shared.snapshot();
            self.remember(|saved| {
                saved.volume = Some(state.volume);
                if state.track.is_some() {
                    saved.position_ms = state.position.position_ms;
                    saved.track = state.track;
                }
            });
        }
    }

    /// Fetch the current track's cover in the background and add its path to
    /// the state when it arrives, unless the track has changed by then.
    fn fetch_art(&self) {
        let (_, state) = self.shared.snapshot();
        let Some(track) = state.track else { return };
        let Some(url) = track.art_url.clone() else { return };
        let Ok(session) = self.connected_session() else { return };
        let shared = self.shared.clone();
        tokio::spawn(async move {
            let Some(path) = crate::art::fetch(&session, &url).await else { return };
            let path = path.to_string_lossy().into_owned();
            shared.update_player(|state| {
                if let Some(current) = state.track.as_mut() {
                    if current.id == track.id {
                        current.art_path = Some(path);
                    }
                }
            });
        });
    }

    fn apply_to_state(&self, event: PlayerEvent) {
        self.shared.update_player(|state| match event {
            PlayerEvent::TrackChanged { audio_item } => {
                let (artists, album) = match &audio_item.unique_fields {
                    UniqueFields::Track { artists, album, .. } => {
                        (artists.0.iter().map(|a| a.name.clone()).collect(), album.clone())
                    }
                    UniqueFields::Episode { show_name, .. } => (vec![show_name.clone()], String::new()),
                    UniqueFields::Local { artists, album, .. } => (
                        artists.clone().into_iter().collect(),
                        album.clone().unwrap_or_default(),
                    ),
                };
                state.track = Some(Track {
                    id: audio_item.uri.clone(),
                    title: audio_item.name.clone(),
                    artists,
                    album,
                    duration_ms: u64::from(audio_item.duration_ms),
                    art_url: audio_item.covers.iter().max_by_key(|c| c.width).map(|c| c.url.clone()),
                    // Filled in by `fetch_art` once the file is there.
                    art_path: None,
                });
            }
            PlayerEvent::Playing { position_ms, .. } => {
                state.playing = true;
                state.position = position(position_ms, true);
            }
            PlayerEvent::Paused { position_ms, .. } => {
                state.playing = false;
                state.position = position(position_ms, false);
            }
            PlayerEvent::Seeked { position_ms, .. } | PlayerEvent::PositionCorrection { position_ms, .. } => {
                state.position = position(position_ms, state.playing);
            }
            PlayerEvent::Loading { position_ms, .. } => {
                state.position = position(position_ms, false);
            }
            PlayerEvent::Stopped { .. } => {
                // Keep showing the track and where it stopped.
                set_playing(state, false);
            }
            PlayerEvent::VolumeChanged { volume } => state.volume = from_device_volume(volume),
            PlayerEvent::ShuffleChanged { shuffle } => state.shuffle = shuffle,
            PlayerEvent::RepeatChanged { context, .. } => state.repeat = context,
            _ => {}
        });
    }
}

#[derive(PartialEq)]
enum SessionEnd {
    /// The connection to Spotify ended; reconnect.
    Disconnected,
    /// The user signed out; do not reconnect.
    SignedOut,
}

fn set_playing(state: &mut PlayerState, playing: bool) {
    if state.track.is_none() || state.playing == playing {
        return;
    }
    // Freeze or restart the clock at where playback is right now.
    let now = now_ms();
    let elapsed = if state.playing { now.saturating_sub(state.position.at_ms) } else { 0 };
    state.position = Position {
        position_ms: state.position.position_ms + elapsed,
        at_ms: now,
        rate: if playing { 1.0 } else { 0.0 },
    };
    state.playing = playing;
}

/// Where to start a track again after its sound stopped: the position last
/// heard playing if that was this track, else the track's last known
/// position, not moved on, since nothing says it played past it.
fn resume_position(heard: Option<&(String, u64)>, track: &str, last_known_ms: u64) -> u64 {
    match heard {
        Some((uri, position_ms)) if uri == track => *position_ms,
        _ => last_known_ms,
    }
}

fn position(position_ms: u32, playing: bool) -> Position {
    Position { position_ms: u64::from(position_ms), at_ms: now_ms(), rate: if playing { 1.0 } else { 0.0 } }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

fn to_device_volume(volume: f32) -> u16 {
    (volume.clamp(0.0, 1.0) * f32::from(u16::MAX)).round() as u16
}

fn from_device_volume(volume: u16) -> f32 {
    f32::from(volume) / f32::from(u16::MAX)
}

#[cfg(test)]
mod tests {
    use super::{from_device_volume, now_ms, resume_position, set_playing, to_device_volume};
    use crate::state::{PlayerState, Position, Track};

    fn loaded(playing: bool, position_ms: u64, seconds_ago: u64) -> PlayerState {
        PlayerState {
            track: Some(Track { id: "t".into(), title: "T".into(), ..Track::default() }),
            playing,
            position: Position {
                position_ms,
                at_ms: now_ms() - seconds_ago * 1000,
                rate: if playing { 1.0 } else { 0.0 },
            },
            ..PlayerState::default()
        }
    }

    #[test]
    fn music_lost_with_the_connection_starts_again_where_it_was_last_heard() {
        let heard = ("spotify:track:a".to_owned(), 61_000);
        // Heard playing at 1:01; the state had moved on to 2:30 by the time
        // the session was given up, but the sound had stopped long before.
        assert_eq!(resume_position(Some(&heard), "spotify:track:a", 150_000), 61_000);
        // The next track was loaded but never heard: from its own start.
        assert_eq!(resume_position(Some(&heard), "spotify:track:b", 0), 0);
        // Nothing heard yet: the last known position, not moved on.
        assert_eq!(resume_position(None, "spotify:track:a", 42_000), 42_000);
    }

        #[test]
    fn pausing_freezes_the_clock_where_playback_has_got_to() {
        let mut state = loaded(true, 10_000, 5);
        set_playing(&mut state, false);
        assert!(!state.playing);
        assert_eq!(state.position.rate, 0.0);
        // Ten seconds in, five more played since: about fifteen.
        assert!((15_000..15_300).contains(&state.position.position_ms), "{}", state.position.position_ms);
    }

    #[test]
    fn resuming_restarts_the_clock_from_where_it_was_paused() {
        let mut state = loaded(false, 10_000, 60);
        set_playing(&mut state, true);
        assert!(state.playing);
        assert_eq!(state.position.rate, 1.0);
        // The minute spent paused does not count.
        assert_eq!(state.position.position_ms, 10_000);
        assert!(now_ms() - state.position.at_ms < 300);
    }

    #[test]
    fn nothing_changes_without_a_track_or_without_a_change() {
        let mut empty = PlayerState::default();
        set_playing(&mut empty, true);
        assert!(!empty.playing);

        let before = loaded(true, 10_000, 5);
        let mut state = before.clone();
        set_playing(&mut state, true);
        assert_eq!(state, before);
    }

    #[test]
    fn volume_survives_the_trip_to_the_device_and_back() {
        for percent in [0, 1, 12, 50, 67, 99, 100] {
            let volume = percent as f32 / 100.0;
            assert!((from_device_volume(to_device_volume(volume)) - volume).abs() < 0.001);
        }
        assert_eq!(to_device_volume(-1.0), 0);
        assert_eq!(to_device_volume(2.0), u16::MAX);
    }
}
