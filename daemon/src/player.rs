//! Playback: the librespot session, the Spotify Connect device and the
//! translation of player events into `PlayerState`.
//!
//! Commands never wait for Spotify. They are handed to librespot's own queue
//! and return at once; the outcome arrives later as a `player` event.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

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
            PlayerConfig::default(),
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
        tokio::pin!(spirc_task);

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

        let end = loop {
            tokio::select! {
                _ = &mut spirc_task => break SessionEnd::Disconnected,
                event = events.recv() => match event {
                    Some(event) => self.apply(event),
                    None => break SessionEnd::Disconnected,
                },
                _ = self.sign_out.notified() => break SessionEnd::SignedOut,
            }
        };

        self.remember_position();
        self.loaded.store(false, Ordering::Relaxed);
        self.ready.send_replace(false);
        if let Some(active) = self.active.lock().expect("active lock").take() {
            let _ = active.spirc.shutdown();
        }
        player.stop();
        self.shared.update_player(|state| *state = PlayerState::default());
        Ok(end)
    }

    fn apply(&self, event: PlayerEvent) {
        match &event {
            PlayerEvent::TrackChanged { .. } | PlayerEvent::Loading { .. } => {
                self.loaded.store(true, Ordering::Relaxed);
            }
            // Another device took over, or the context ran out.
            PlayerEvent::Stopped { .. } => self.loaded.store(false, Ordering::Relaxed),
            _ => {}
        }
        let worth_saving = matches!(
            event,
            PlayerEvent::TrackChanged { .. }
                | PlayerEvent::Paused { .. }
                | PlayerEvent::VolumeChanged { .. }
                | PlayerEvent::Seeked { .. }
        );
        self.apply_to_state(event);
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
            PlayerEvent::Seeked { position_ms, .. }
            | PlayerEvent::PositionCorrection { position_ms, .. }
            | PlayerEvent::PositionChanged { position_ms, .. } => {
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
