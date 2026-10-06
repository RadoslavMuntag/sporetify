//! MPRIS: the desktop's standard media-player interface. This is what makes
//! media keys, `playerctl` and other desktop tools control Sporetify.
//!
//! It mirrors `PlayerState` and turns method calls into the same commands
//! the socket uses, so the two can never disagree.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use mpris_server::{Metadata, PlaybackStatus, Player, Time, TrackId};
use tokio::sync::broadcast::error::RecvError;

use crate::player::{Command, Playback};
use crate::state::{PlayerState, Shared};

/// Runs for the daemon's lifetime. Must be polled inside a `LocalSet`.
pub async fn run(shared: Arc<Shared>, playback: Arc<Playback>) {
    let player = match Player::builder("sporetify")
        .identity("Sporetify")
        .desktop_entry("sporetify")
        .can_control(true)
        .can_play(true)
        .can_pause(true)
        .can_go_next(true)
        .can_go_previous(true)
        .can_seek(true)
        .build()
        .await
    {
        Ok(player) => player,
        Err(e) => {
            // Without a session bus the daemon is still fully usable over its socket.
            eprintln!("sporetifyd: MPRIS is unavailable: {e}");
            return std::future::pending().await;
        }
    };

    let send = |command: Command| {
        let playback = playback.clone();
        move || {
            let _ = playback.command(command);
        }
    };
    let (play, pause, toggle, next, previous) = (
        send(Command::Play),
        send(Command::Pause),
        send(Command::Toggle),
        send(Command::Next),
        send(Command::Previous),
    );
    player.connect_play(move |_| play());
    player.connect_pause(move |_| pause());
    player.connect_stop(send_fn(&playback, Command::Pause));
    player.connect_play_pause(move |_| toggle());
    player.connect_next(move |_| next());
    player.connect_previous(move |_| previous());
    {
        let (playback, shared) = (playback.clone(), shared.clone());
        player.connect_seek(move |_, offset| {
            let target = current_ms(&shared.snapshot().1) as i64 + offset.as_millis();
            let _ = playback.command(Command::Seek(target.max(0) as u32));
        });
    }
    {
        let playback = playback.clone();
        player.connect_set_position(move |_, _, position| {
            let _ = playback.command(Command::Seek(position.as_millis().max(0) as u32));
        });
    }
    {
        let playback = playback.clone();
        player.connect_set_volume(move |_, volume| {
            let _ = playback.command(Command::Volume(volume as f32));
        });
    }
    {
        let playback = playback.clone();
        player.connect_set_shuffle(move |_, on| {
            let _ = playback.command(Command::Shuffle(on));
        });
    }

    tokio::task::spawn_local(player.run());

    let mut events = shared.subscribe();
    let mut shown = PlayerState::default();
    push(&player, &shown, &shared.snapshot().1, true).await;
    shown = shared.snapshot().1;

    // While playing, keep the Position property close to the truth; reading
    // it does not reach us, so it has to be refreshed.
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            event = events.recv() => match event {
                Ok(event) if event.topic != "player" => continue,
                Ok(_) | Err(RecvError::Lagged(_)) => {
                    let next = shared.snapshot().1;
                    push(&player, &shown, &next, false).await;
                    shown = next;
                }
                Err(RecvError::Closed) => return,
            },
            _ = tick.tick(), if shown.playing => {
                player.set_position(Time::from_millis(current_ms(&shown) as i64));
            }
        }
    }
}

fn send_fn(playback: &Arc<Playback>, command: Command) -> impl Fn(&Player) + 'static {
    let playback = playback.clone();
    move |_| {
        let _ = playback.command(command);
    }
}

/// Publish what changed between two states.
async fn push(player: &Player, old: &PlayerState, new: &PlayerState, everything: bool) {
    if everything || old.track != new.track {
        let metadata = match &new.track {
            Some(track) => {
                let mut builder = Metadata::builder()
                    .title(track.title.clone())
                    .artist(track.artists.clone())
                    .album(track.album.clone())
                    .length(Time::from_millis(track.duration_ms as i64));
                if let Ok(id) = TrackId::try_from(track_path(&track.id)) {
                    builder = builder.trackid(id);
                }
                if let Some(art) = &track.art_url {
                    builder = builder.art_url(art.clone());
                }
                builder.build()
            }
            None => Metadata::new(),
        };
        let _ = player.set_metadata(metadata).await;
    }

    let status = |state: &PlayerState| match (&state.track, state.playing) {
        (None, _) => PlaybackStatus::Stopped,
        (Some(_), true) => PlaybackStatus::Playing,
        (Some(_), false) => PlaybackStatus::Paused,
    };
    if everything || status(old) != status(new) {
        let _ = player.set_playback_status(status(new)).await;
    }
    if everything || old.volume != new.volume {
        let _ = player.set_volume(f64::from(new.volume)).await;
    }
    if everything || old.shuffle != new.shuffle {
        let _ = player.set_shuffle(new.shuffle).await;
    }

    let position = Time::from_millis(current_ms(new) as i64);
    player.set_position(position);
    // A position that moved without a track or play-state change is a seek.
    if !everything && old.track == new.track && old.playing == new.playing && old.position != new.position {
        let _ = player.seeked(position).await;
    }
}

/// MPRIS track ids are D-Bus object paths.
fn track_path(uri: &str) -> String {
    let safe: String = uri.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    format!("/org/sporetify/track/{safe}")
}

fn current_ms(state: &PlayerState) -> u64 {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
    let elapsed = now.saturating_sub(state.position.at_ms) as f64 * f64::from(state.position.rate);
    let position = state.position.position_ms + elapsed as u64;
    match &state.track {
        Some(track) if track.duration_ms > 0 => position.min(track.duration_ms),
        _ => position,
    }
}
