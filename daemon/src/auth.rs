//! Sign-in and credential storage.
//!
//! Sporetify has no client id of its own: it signs in through librespot's
//! OAuth flow with the id librespot ships. Only the refresh token is kept,
//! and only in the desktop keyring (via `secret-tool`); it never touches the
//! cache directory, the socket or the logs.

use std::process::Stdio;
use std::time::Duration;

use librespot_oauth::{OAuthClient, OAuthClientBuilder, OAuthError, OAuthToken};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

/// The client id librespot uses by default (Spotify's own desktop client).
const CLIENT_ID: &str = "65b708073fc0480ea92a077233ca87bd";
const REDIRECT_URI: &str = "http://127.0.0.1:8898/login";
const SCOPES: &[&str] = &[
    "streaming",
    "user-read-private",
    "user-read-email",
    "user-library-read",
    "user-library-modify",
    "playlist-read-private",
    "playlist-read-collaborative",
    "playlist-modify-private",
    "playlist-modify-public",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-follow-read",
    "user-follow-modify",
    "user-top-read",
    "user-read-recently-played",
];

/// How long the browser sign-in may take before it is abandoned.
pub const SIGN_IN_TIMEOUT: Duration = Duration::from_secs(300);

const KEYRING_ATTRS: [&str; 4] = ["service", "sporetify", "account", "spotify"];

#[derive(Debug)]
pub enum AuthError {
    /// Spotify refused the stored credentials; the user must sign in again.
    Rejected,
    /// Anything else: no network, no browser, keyring locked, timed out.
    Other(String),
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Rejected => write!(f, "Spotify rejected the stored sign-in"),
            Self::Other(message) => write!(f, "{message}"),
        }
    }
}

fn client(open_browser: bool) -> Result<OAuthClient, AuthError> {
    let mut builder = OAuthClientBuilder::new(CLIENT_ID, REDIRECT_URI, SCOPES.to_vec())
        .with_custom_message("Signed in to Sporetify. You can close this tab.");
    if open_browser {
        builder = builder.open_in_browser();
    }
    builder.build().map_err(|e| AuthError::Other(e.to_string()))
}

/// Run the browser sign-in to completion and remember the result.
pub async fn sign_in() -> Result<OAuthToken, AuthError> {
    let client = client(true)?;
    let token = tokio::time::timeout(SIGN_IN_TIMEOUT, client.get_access_token_async())
        .await
        .map_err(|_| AuthError::Other("sign-in was not completed in the browser in time".into()))?
        .map_err(|e| AuthError::Other(e.to_string()))?;
    store_refresh_token(&token.refresh_token).await?;
    Ok(token)
}

/// Turn the stored refresh token into a fresh access token.
/// `Ok(None)` means nobody is signed in.
pub async fn restore() -> Result<Option<OAuthToken>, AuthError> {
    let Some(refresh) = load_refresh_token().await? else {
        return Ok(None);
    };
    match client(false)?.refresh_token_async(&refresh).await {
        Ok(token) => {
            // Spotify may rotate the refresh token on use.
            if token.refresh_token != refresh && !token.refresh_token.is_empty() {
                store_refresh_token(&token.refresh_token).await?;
            }
            Ok(Some(token))
        }
        Err(e) if refresh_was_rejected(&e) => Err(AuthError::Rejected),
        Err(e) => Err(AuthError::Other(e.to_string())),
    }
}

/// A refusal from Spotify, as opposed to a request that never got an answer.
fn refresh_was_rejected(error: &OAuthError) -> bool {
    let text = format!("{error} {error:?}").to_lowercase();
    text.contains("invalid_grant") || text.contains("invalid_client") || text.contains("revoked")
}

pub async fn forget() -> Result<(), AuthError> {
    let status = Command::new("secret-tool")
        .arg("clear")
        .args(KEYRING_ATTRS)
        .stdin(Stdio::null())
        .status()
        .await
        .map_err(keyring_error)?;
    if status.success() {
        Ok(())
    } else {
        Err(AuthError::Other("the keyring refused to remove the sign-in".into()))
    }
}

async fn load_refresh_token() -> Result<Option<String>, AuthError> {
    let output = Command::new("secret-tool")
        .arg("lookup")
        .args(KEYRING_ATTRS)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .await
        .map_err(keyring_error)?;
    // secret-tool exits non-zero when the item simply does not exist.
    let token = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    Ok((output.status.success() && !token.is_empty()).then_some(token))
}

async fn store_refresh_token(token: &str) -> Result<(), AuthError> {
    let mut child = Command::new("secret-tool")
        .args(["store", "--label=Sporetify (Spotify sign-in)"])
        .args(KEYRING_ATTRS)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(keyring_error)?;
    // The secret goes over stdin so it never appears in a process listing.
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(token.as_bytes()).await.map_err(keyring_error)?;
    }
    let status = child.wait().await.map_err(keyring_error)?;
    if status.success() {
        Ok(())
    } else {
        Err(AuthError::Other("the keyring refused to store the sign-in".into()))
    }
}

fn keyring_error(error: std::io::Error) -> AuthError {
    AuthError::Other(format!("could not use the desktop keyring (secret-tool): {error}"))
}
