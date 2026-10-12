.pragma library

// What to tell the user when Sporetify cannot work, and the command that
// fixes it. One wording for the bar, the mini-player and the app.

// Where `omarchy plugin add` puts the plugin, and so its setup script.
var setupCommand = "~/.config/omarchy/plugins/namelessnovice.sporetify/scripts/setup.sh"

// One line saying what is wrong, or "" when the phase is not a fault.
function title(phase) {
  switch (phase) {
  case "signed_out": return "Sign in to Spotify to start listening"
  case "offline": return "Offline. Playback resumes when Spotify is reachable"
  case "no_premium": return "Spotify Premium is required to play"
  case "unavailable": return "Sporetify's daemon is not installed or not running"
  case "incompatible": return "Sporetify's daemon is a different version from this plugin"
  }
  return ""
}

// The command to run in a terminal to fix it, or "" when there is none.
// Both cases have the same cure: setup installs the daemon that matches.
function command(phase) {
  return phase === "unavailable" || phase === "incompatible" ? setupCommand : ""
}

// What that command does, as a sentence to put before it.
function advice(phase) {
  switch (phase) {
  case "unavailable": return "Install it by running, in a terminal:"
  case "incompatible": return "Bring it up to date by running, in a terminal:"
  }
  return ""
}
