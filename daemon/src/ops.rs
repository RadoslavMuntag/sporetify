//! Request handlers. Each returns one result; the deadline, cancellation and
//! the terminal frame are the caller's job (`ipc`), so no op can hang a client.

use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};

use crate::catalog::{self, Catalog};
use crate::player::{Command, PlayRequest, Playback};
use crate::proto::{OpError, OpResult};
use crate::state::Shared;

#[derive(Clone)]
pub struct Context {
    pub shared: Arc<Shared>,
    pub playback: Arc<Playback>,
    pub catalog: Arc<Catalog>,
    /// Enables `debug.*` ops, used by the protocol tests.
    pub debug_ops: bool,
}

fn number(args: &Value, key: &str) -> Result<f64, OpError> {
    args.get(key)
        .and_then(Value::as_f64)
        .ok_or_else(|| OpError::bad_request(format!("'args.{key}' must be a number")))
}

fn text(args: &Value, key: &str) -> Result<String, OpError> {
    args.get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| OpError::bad_request(format!("'args.{key}' must be a non-empty string")))
}

fn flag(args: &Value, key: &str) -> Result<bool, OpError> {
    args.get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| OpError::bad_request(format!("'args.{key}' must be true or false")))
}

pub async fn dispatch(op: String, args: Value, ctx: Context) -> OpResult {
    let command = match op.as_str() {
        "player.get" => {
            let (status, player) = ctx.shared.snapshot();
            return Ok(json!({ "status": status, "player": player }));
        }
        "player.play" => Command::Play,
        "player.pause" => Command::Pause,
        "player.toggle" => Command::Toggle,
        "player.next" => Command::Next,
        "player.previous" => Command::Previous,
        "player.seek" => Command::Seek(number(&args, "position_ms")?.max(0.0) as u32),
        "player.volume" => Command::Volume(number(&args, "value")? as f32),
        "player.volume_step" => Command::VolumeStep(number(&args, "delta")? as f32),
        "player.shuffle" => Command::Shuffle(flag(&args, "on")?),
        "player.repeat" => Command::Repeat(flag(&args, "on")?),

        "player.play_context" => {
            let context_uri = text(&args, "uri")?;
            let track_uri = args.get("track_uri").and_then(Value::as_str).map(str::to_owned);
            ctx.playback.settle().await;
            ctx.playback.play_context(PlayRequest { context_uri, track_uri })?;
            return Ok(json!({}));
        }

        "library.playlists" => {
            ctx.playback.settle().await;
            let session = ctx.playback.connected_session()?;
            ctx.catalog.index_in_background(&session);
            return ctx.catalog.playlists(&session).await;
        }
        "search" => {
            let query = text(&args, "query")?;
            let limit = args.get("limit").and_then(Value::as_u64).unwrap_or(20).clamp(1, 50) as usize;
            ctx.playback.settle().await;
            return ctx.catalog.search_spotify(&ctx.playback.connected_session()?, &query, limit).await;
        }
        "library.search" => {
            let limit = args.get("limit").and_then(Value::as_u64).unwrap_or(200) as usize;
            let query = args.get("query").and_then(Value::as_str).unwrap_or("");
            return ctx.catalog.search(query, limit.clamp(1, 500));
        }
        "library.save" | "library.unsave" => {
            ctx.playback.settle().await;
            let session = ctx.playback.connected_session()?;
            return ctx.catalog.set_liked(&session, &text(&args, "uri")?, op == "library.save").await;
        }
        "library.is_saved" => {
            ctx.playback.settle().await;
            return ctx.catalog.is_liked(&ctx.playback.connected_session()?, &text(&args, "uri")?).await;
        }
        "player.queue_add" => {
            ctx.playback.settle().await;
            ctx.playback.queue_add(&text(&args, "uri")?).await?;
            return Ok(json!({}));
        }
        "library.track" => {
            ctx.playback.settle().await;
            return ctx.catalog.track_row(&ctx.playback.connected_session()?, &text(&args, "uri")?).await;
        }
        "browse.album" => {
            ctx.playback.settle().await;
            return ctx.catalog.album(&ctx.playback.connected_session()?, &text(&args, "uri")?).await;
        }
        "browse.artist" => {
            ctx.playback.settle().await;
            return ctx.catalog.artist(&ctx.playback.connected_session()?, &text(&args, "uri")?).await;
        }
        "player.up_next" => {
            ctx.playback.settle().await;
            let session = ctx.playback.connected_session()?;
            let (_, player) = ctx.shared.snapshot();
            let limit = args.get("limit").and_then(Value::as_u64).unwrap_or(50).clamp(1, 200) as usize;
            // What was queued from here plays before the rest of the list.
            let queued: Vec<Value> = ctx
                .catalog
                .decorated_rows(&session, ctx.playback.queued())
                .await
                .into_iter()
                .map(|mut row| {
                    row["queued"] = json!(true);
                    row
                })
                .collect();
            let (Some(context), Some(track)) = (ctx.playback.context_uri(), player.track) else {
                return Ok(json!({
                    "context_uri": null, "items": queued, "total": 0, "shuffle": player.shuffle,
                }));
            };
            let mut next = ctx.catalog.up_next(&session, &context, &track.id, limit).await?;
            if let Some(items) = next["items"].as_array_mut() {
                items.splice(0..0, queued);
            }
            next["shuffle"] = json!(player.shuffle);
            return Ok(next);
        }
        "library.tracks" => {
            let uri = text(&args, "uri")?;
            let (offset, limit) = catalog::page_args(&args);
            let refresh = args.get("refresh").and_then(Value::as_bool).unwrap_or(false);
            ctx.playback.settle().await;
            return ctx.catalog.tracks(&ctx.playback.connected_session()?, &uri, offset, limit, refresh).await;
        }

        "auth.begin" => {
            ctx.playback.begin_sign_in()?;
            return Ok(json!({ "started": true }));
        }
        "auth.sign_out" => {
            ctx.playback.sign_out().await?;
            return Ok(json!({}));
        }
        "auth.retry" => {
            ctx.playback.retry();
            return Ok(json!({}));
        }

        "debug.sleep" if ctx.debug_ops => {
            let ms = args.get("ms").and_then(Value::as_u64).unwrap_or(0);
            tokio::time::sleep(Duration::from_millis(ms)).await;
            return Ok(json!({ "slept_ms": ms }));
        }
        "debug.panic" if ctx.debug_ops => panic!("debug.panic requested"),
        // Raw calls for exploring Spotify's internal API during development.
        "debug.mercury" if ctx.debug_ops => {
            let session = ctx.playback.connected_session()?;
            let request = session
                .mercury()
                .get(text(&args, "uri")?)
                .map_err(|e| OpError::bad_request(e.to_string()))?;
            let response = request.await.map_err(|e| OpError::new(crate::proto::ErrorCode::Internal, e.to_string()))?;
            let body = response.payload.first().map(|part| String::from_utf8_lossy(part).into_owned());
            return Ok(json!({ "status": response.status_code, "body": body }));
        }
        // An arbitrary request carrying the session's own credentials, with
        // the status and the start of the body returned whatever the outcome.
        "debug.http" if ctx.debug_ops => {
            use http_body_util::BodyExt;
            let session = ctx.playback.connected_session()?;
            let internal = |e: String| OpError::new(crate::proto::ErrorCode::Internal, e);
            let token = session.login5().auth_token().await.map_err(|e| internal(e.to_string()))?;
            let client_token = session.spclient().client_token().await.map_err(|e| internal(e.to_string()))?;
            let method = args.get("method").and_then(Value::as_str).unwrap_or("GET");
            let body = args.get("body").map(|b| if b.is_string() { b.as_str().unwrap_or("").to_owned() } else { b.to_string() });
            let mut request = http::Request::builder()
                .method(method)
                .uri(text(&args, "url")?)
                .header("Authorization", format!("Bearer {}", token.access_token))
                .header("client-token", client_token)
                .header("Accept", "application/json")
                .header("app-platform", "WebPlayer");
            if body.is_some() {
                request = request.header("Content-Type", "application/json;charset=UTF-8");
            }
            let request = request
                .body(bytes::Bytes::from(body.unwrap_or_default()))
                .map_err(|e| internal(e.to_string()))?;
            let response = session.http_client().request(request).await.map_err(|e| internal(e.to_string()))?;
            let status = response.status().as_u16();
            let bytes = response.into_body().collect().await.map_err(|e| internal(e.to_string()))?.to_bytes();
            let limit = args.get("limit").and_then(Value::as_u64).unwrap_or(600) as usize;
            let shown: String = String::from_utf8_lossy(&bytes).chars().take(limit).collect();
            return Ok(json!({ "status": status, "length": bytes.len(), "body": shown }));
        }
        "debug.spclient" if ctx.debug_ops => {
            let session = ctx.playback.connected_session()?;
            let endpoint = text(&args, "endpoint")?;
            let bytes = session
                .spclient()
                .request_as_json(&"GET".parse().expect("method"), &endpoint, None, None)
                .await
                .map_err(|e| OpError::new(crate::proto::ErrorCode::Internal, e.to_string()))?;
            return Ok(json!({ "body": String::from_utf8_lossy(&bytes) }));
        }
        _ => return Err(OpError::bad_request(format!("unknown op '{op}'"))),
    };
    ctx.playback.settle().await;
    ctx.playback.command(command)?;
    Ok(json!({}))
}
