.pragma library

// The single source of truth for keyboard shortcuts. Key handling, keycap
// hints and the hint bar are all derived from this table, so a hint can
// never disagree with what a key does.
//
// `keys` are names as produced by keyName(): a printable character, or a
// named key such as "Space", "Left", "Esc". The first key is the one shown
// in hints.

// `primary` actions are the ones a hint bar shows when space is short; the
// rest are still listed in the help overlay.
var actions = [
  { id: "playPause",   keys: ["Space"],          label: "Play/Pause",  scope: "player", primary: true },
  { id: "next",        keys: ["n"],              label: "Next",        scope: "player", primary: true },
  { id: "previous",    keys: ["p"],              label: "Previous",    scope: "player", primary: true },
  { id: "volumeUp",    keys: ["+", "="],         label: "Vol +",       scope: "player", primary: true },
  { id: "volumeDown",  keys: ["-"],              label: "Vol −",       scope: "player", primary: true },
  { id: "mute",        keys: ["m"],              label: "Mute",        scope: "player" },
  { id: "seekForward", keys: ["Right", "l"],     label: "+10s",        scope: "player" },
  { id: "seekBack",    keys: ["Left", "h"],      label: "−10s",        scope: "player" },
  { id: "shuffle",     keys: ["s"],              label: "Shuffle",     scope: "player" },
  { id: "repeat",      keys: ["r"],              label: "Repeat",      scope: "player" },
  { id: "openApp",     keys: ["o"],              label: "Open app",    scope: "mini", primary: true },
  { id: "activate",    keys: ["Return"],         label: "Play / open", scope: "browse", primary: true },
  { id: "paneNext",    keys: ["Tab"],            label: "Switch pane", scope: "browse", primary: true },
  { id: "search",      keys: ["/"],              label: "Search",      scope: "browse", primary: true },
  { id: "artist",      keys: ["a"],              label: "Artist",      scope: "browse", primary: true },
  { id: "album",       keys: ["d"],              label: "Album",       scope: "browse", primary: true },
  { id: "queue",       keys: ["u"],              label: "Up next",     scope: "browse", primary: true },
  { id: "back",        keys: ["Backspace", "["], label: "Back",        scope: "browse", primary: true },
  { id: "forward",     keys: ["]"],              label: "Forward",     scope: "browse" },
  { id: "down",        keys: ["j", "Down"],      label: "Down",        scope: "browse" },
  { id: "up",          keys: ["k", "Up"],        label: "Up",          scope: "browse" },
  { id: "top",         keys: ["g", "Home"],      label: "Top",         scope: "browse" },
  { id: "bottom",      keys: ["G", "End"],       label: "Bottom",      scope: "browse" },
  { id: "pageDown",    keys: ["PgDn"],           label: "Page down",   scope: "browse" },
  { id: "pageUp",      keys: ["PgUp"],           label: "Page up",     scope: "browse" },
  { id: "reload",      keys: ["R"],              label: "Reload",      scope: "browse" },
  { id: "creatures",   keys: ["v"],              label: "Creatures",   scope: "browse" },
  { id: "help",        keys: ["?"],              label: "All keys",    scope: "browse", primary: true },
  { id: "signIn",      keys: ["Return"],         label: "Sign in",     scope: "signedOut", primary: true },
  { id: "retry",       keys: ["Return"],         label: "Retry",       scope: "fault", primary: true },
  { id: "close",       keys: ["Esc", "q"],       label: "Close",       scope: "any", primary: true }
]

// Qt::Key values for the keys that have no printable character.
var named = {
  0x20: "Space",
  0x01000000: "Esc",
  0x01000001: "Tab",
  0x01000003: "Backspace",
  0x01000004: "Return",
  0x01000005: "Return",
  0x01000010: "Home",
  0x01000011: "End",
  0x01000016: "PgUp",
  0x01000017: "PgDn",
  0x01000012: "Left",
  0x01000013: "Up",
  0x01000014: "Right",
  0x01000015: "Down"
}

// Symbols used when a key is shown to the user.
var glyphs = { Space: "␣", Left: "←", Right: "→", Up: "↑", Down: "↓", Return: "⏎", Tab: "⇥", Backspace: "⌫" }

// Name of the key in a QML key event ({ key, text }).
function keyName(key, text) {
  if (named[key] !== undefined) return named[key]
  return text && text.length === 1 ? text : ""
}

function inScopes(action, scopes) {
  return action.scope === "any" || scopes.indexOf(action.scope) !== -1
}

// The action a key triggers, or null. `scopes` is one scope name or a list
// of them, most specific first; actions scoped "any" apply everywhere.
function actionFor(key, text, scopes) {
  var name = keyName(key, text)
  if (name === "") return null
  var list = typeof scopes === "string" ? [scopes] : scopes
  for (var s = 0; s <= list.length; s++) {
    var scope = s < list.length ? list[s] : "any"
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].scope === scope && actions[i].keys.indexOf(name) !== -1) return actions[i].id
    }
  }
  return null
}

// How the primary key of an action is shown, e.g. "␣" or "n".
function keyLabel(id) {
  for (var i = 0; i < actions.length; i++) {
    if (actions[i].id === id) {
      var key = actions[i].keys[0]
      return glyphs[key] !== undefined ? glyphs[key] : key
    }
  }
  return ""
}

// Hint entries for one scope or a list of scopes: [{ key, label }], in table
// order, with the "any" actions last. With `primaryOnly`, just the actions
// marked primary.
function hints(scopes, primaryOnly) {
  var list = typeof scopes === "string" ? [scopes] : scopes
  var out = []
  for (var i = 0; i < actions.length; i++) {
    if (!inScopes(actions[i], list)) continue
    if (primaryOnly && !actions[i].primary) continue
    out.push({ key: keyLabel(actions[i].id), label: actions[i].label })
  }
  return out
}
