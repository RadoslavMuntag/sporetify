.pragma library

// The single source of truth for keyboard shortcuts. Key handling, keycap
// hints and the hint bar are all derived from this table, so a hint can
// never disagree with what a key does.
//
// `keys` are names as produced by keyName(): a printable character, or a
// named key such as "Space", "Left", "Esc". The first key is the one shown
// in hints.

// `primary` actions are the ones a hint bar shows when space is short; the
// rest are still listed in the help overlay. `group` says which section of
// the help overlay an action belongs to.
var actions = [
  { id: "playPause",   keys: ["Space"],          label: "Play / pause",     scope: "player", group: "playback", primary: true },
  { id: "next",        keys: ["n"],              label: "Next track",       scope: "player", group: "playback", primary: true },
  { id: "previous",    keys: ["p"],              label: "Previous track",   scope: "player", group: "playback", primary: true },
  { id: "seekForward", keys: ["Right", "l"],     label: "Forward 10 s",     scope: "player", group: "playback" },
  { id: "seekBack",    keys: ["Left", "h"],      label: "Back 10 s",        scope: "player", group: "playback" },
  { id: "volumeUp",    keys: ["+", "="],         label: "Volume up",        scope: "player", group: "playback" },
  { id: "volumeDown",  keys: ["-"],              label: "Volume down",      scope: "player", group: "playback" },
  { id: "mute",        keys: ["m"],              label: "Mute",             scope: "player", group: "playback" },
  { id: "shuffle",     keys: ["s"],              label: "Shuffle",          scope: "player", group: "playback" },
  { id: "repeat",      keys: ["r"],              label: "Repeat",           scope: "player", group: "playback" },

  { id: "openApp",     keys: ["o"],              label: "Open app",         scope: "mini", group: "places", primary: true },
  { id: "likePlaying", keys: ["f"],              label: "Like",             scope: "mini", group: "track", primary: true },

  { id: "down",        keys: ["j", "Down"],      label: "Down",             scope: "browse", group: "moving" },
  { id: "up",          keys: ["k", "Up"],        label: "Up",               scope: "browse", group: "moving" },
  { id: "pageDown",    keys: ["PgDn"],           label: "Page down",        scope: "browse", group: "moving" },
  { id: "pageUp",      keys: ["PgUp"],           label: "Page up",          scope: "browse", group: "moving" },
  { id: "top",         keys: ["g", "Home"],      label: "Top",              scope: "browse", group: "moving" },
  { id: "bottom",      keys: ["G", "End"],       label: "Bottom",           scope: "browse", group: "moving" },
  { id: "paneNext",    keys: ["Tab"],            label: "Switch pane",      scope: "browse", group: "moving", primary: true },
  { id: "activate",    keys: ["Return"],         label: "Play / open",      scope: "browse", group: "moving", primary: true },

  { id: "back",        keys: ["Backspace", "["], label: "Back",             scope: "browse", group: "places", primary: true },
  { id: "forward",     keys: ["]"],              label: "Forward",          scope: "browse", group: "places" },
  { id: "artist",      keys: ["a"],              label: "Go to artist",     scope: "browse", group: "places", primary: true },
  { id: "album",       keys: ["d"],              label: "Go to album",      scope: "browse", group: "places", primary: true },
  { id: "queue",       keys: ["u"],              label: "Up next",          scope: "browse", group: "places", primary: true },

  { id: "search",      keys: ["/"],              label: "Search Spotify",   scope: "browse", group: "search", primary: true },
  { id: "searchLibrary", keys: ["Ctrl+f"],       label: "Search library",   scope: "browse", group: "search", primary: true },
  { id: "searchType",  keys: ["t"],              label: "Songs / artists / albums / playlists", scope: "browse", group: "search" },

  { id: "like",        keys: ["f"],              label: "Like / unlike",    scope: "browse", group: "track", primary: true },
  { id: "enqueue",     keys: ["e"],              label: "Add to queue",     scope: "browse", group: "track", primary: true },
  { id: "addToPlaylist", keys: ["A"],            label: "Add to playlist",  scope: "browse", group: "track", primary: true },
  { id: "mark",        keys: ["V"],              label: "Select several",   scope: "browse", group: "track" },

  { id: "newPlaylist", keys: ["N"],              label: "New playlist",     scope: "browse", group: "playlists" },
  { id: "rename",      keys: ["F2"],             label: "Rename playlist",  scope: "browse", group: "playlists" },
  { id: "moveDown",    keys: ["J"],              label: "Move track down",  scope: "browse", group: "playlists" },
  { id: "moveUp",      keys: ["K"],              label: "Move track up",    scope: "browse", group: "playlists" },
  { id: "removeFromPlaylist", keys: ["x", "Del"], label: "Remove track, or delete playlist in sidebar (twice)", scope: "browse", group: "playlists" },

  { id: "reload",      keys: ["R"],              label: "Reload",           scope: "browse", group: "app" },
  { id: "covers",      keys: ["c"],              label: "Covers in lists",  scope: "browse", group: "app" },
  { id: "creatures",   keys: ["v"],              label: "Creatures",        scope: "browse", group: "app" },
  { id: "help",        keys: ["?"],              label: "All keys",         scope: "browse", group: "app", primary: true },

  { id: "signIn",      keys: ["Return"],         label: "Sign in",          scope: "signedOut", group: "app", primary: true },
  { id: "retry",       keys: ["Return"],         label: "Retry",            scope: "fault", group: "app", primary: true },
  // A popup closes on Esc; the app window does not (Esc there backs out of
  // a search), so the two have their own scopes.
  { id: "close",       keys: ["Esc", "q"],       label: "Close",            scope: "popup", group: "app", primary: true },
  { id: "cancel",      keys: ["Esc"],            label: "Clear selection, or leave search", scope: "app", group: "search" },
  { id: "quit",        keys: ["Ctrl+c"],         label: "Quit",             scope: "app", group: "app", primary: true }
]

// The sections of the help overlay, in reading order.
var groups = [
  { id: "playback",  title: "Playback" },
  { id: "moving",    title: "Moving around" },
  { id: "places",    title: "Going places" },
  { id: "search",    title: "Search" },
  { id: "track",     title: "The track under the cursor" },
  { id: "playlists", title: "Your playlists" },
  { id: "app",       title: "App" }
]

// Qt::Key values for the keys that have no printable character.
var named = {
  0x20: "Space",
  0x01000000: "Esc",
  0x01000001: "Tab",
  0x01000003: "Backspace",
  0x01000007: "Del",
  0x01000031: "F2",
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

// Qt::ControlModifier
var CTRL = 0x04000000

// Name of the key in a QML key event. With Ctrl held the name is "Ctrl+x",
// so a chord never triggers the plain key's action.
function keyName(key, text, modifiers) {
  if (modifiers & CTRL) {
    // Letters: Qt::Key_A..Key_Z are their ASCII codes.
    return key >= 0x41 && key <= 0x5a ? "Ctrl+" + String.fromCharCode(key).toLowerCase() : ""
  }
  if (named[key] !== undefined) return named[key]
  return text && text.length === 1 ? text : ""
}

function inScopes(action, scopes) {
  return action.scope === "any" || scopes.indexOf(action.scope) !== -1
}

// The action a key triggers, or null. `scopes` is one scope name or a list
// of them, most specific first; actions scoped "any" apply everywhere.
// `modifiers` is the event's modifier mask (optional).
function actionFor(key, text, scopes, modifiers) {
  var name = keyName(key, text, modifiers)
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
      return show(actions[i].keys[0])
    }
  }
  return ""
}

// How a key name is shown.
function show(key) {
  if (key.indexOf("Ctrl+") === 0) return "Ctrl " + key.slice(5).toUpperCase()
  return glyphs[key] !== undefined ? glyphs[key] : key
}

// Hint entries for one scope or a list of scopes: [{ key, label }], in table
// order. With `primaryOnly`, just the actions marked primary.
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

// Everything the scopes offer, by section, for the help overlay:
// [{ title, items: [{ keys: [shown key, ...], label }] }]. Every key of an
// action is listed, and sections with nothing in them are left out.
function sections(scopes) {
  var list = typeof scopes === "string" ? [scopes] : scopes
  var out = []
  for (var g = 0; g < groups.length; g++) {
    var items = []
    for (var i = 0; i < actions.length; i++) {
      var action = actions[i]
      if (action.group !== groups[g].id || !inScopes(action, list)) continue
      items.push({ keys: action.keys.map(show), label: action.label })
    }
    if (items.length > 0) out.push({ title: groups[g].title, items: items })
  }
  return out
}

// The sections dealt into `count` columns of similar height, each section
// kept whole and the reading order kept down the columns.
function columns(scopes, count) {
  var all = sections(scopes)
  var total = 0
  for (var i = 0; i < all.length; i++) total += all[i].items.length + 2
  var out = []
  var column = []
  var height = 0
  var target = total / count
  for (var s = 0; s < all.length; s++) {
    var size = all[s].items.length + 2
    // Start a new column when this one is full enough, unless it is the last.
    if (column.length > 0 && out.length < count - 1 && height + size / 2 > target) {
      out.push(column)
      column = []
      height = 0
    }
    column.push(all[s])
    height += size
  }
  if (column.length > 0) out.push(column)
  return out
}
