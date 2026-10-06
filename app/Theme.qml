pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy theme tokens for the full app. The app runs outside omarchy-shell
// and cannot import its theme module, so this reads the same files and
// exposes the same names. Switching theme applies live.
Singleton {
  id: root

  // key -> colour string, straight from the active theme's colors.toml.
  property var palette: ({})
  property string mode: "dark"
  // [font] base-size from the user's shell.toml; the rem root of every size.
  property int baseSize: 12

  function pick(name, fallback) {
    return palette[name] !== undefined ? palette[name] : fallback
  }
  function alpha(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // Neutral fallbacks only show if the theme file cannot be read.
  readonly property color background: pick("background", mode === "light" ? "white" : "black")
  readonly property color foreground: pick("foreground", mode === "light" ? "black" : "white")
  readonly property color accent: pick("accent", foreground)
  readonly property color muted: pick("muted", alpha(foreground, 0.5))
  readonly property color urgent: pick("red", foreground)
  readonly property color raised: pick("lighter_background", alpha(foreground, 0.06))
  readonly property color sunken: pick("dark_background", background)

  // Colours a creature's body may take: the theme's named palette.
  readonly property var creatureColors: {
    var names = ["green", "cyan", "blue", "magenta", "yellow", "orange", "red"]
    var out = []
    for (var i = 0; i < names.length; i++) if (palette[names[i]] !== undefined) out.push(Qt.color(palette[names[i]]))
    return out.length > 0 ? out : [accent]
  }

  // Control states, same strengths as the shell's defaults.
  readonly property color hoverFill: alpha(foreground, 0.08)
  readonly property color selectedFill: alpha(foreground, 0.18)
  readonly property color line: alpha(foreground, 0.12)
  readonly property color border: alpha(foreground, 0.25)

  readonly property real scale: Math.max(1 / 12, baseSize / 12)
  function space(px) {
    return Math.max(1, Math.round(px * scale))
  }

  readonly property QtObject spacing: QtObject {
    readonly property int xs: root.space(3)
    readonly property int sm: root.space(4)
    readonly property int md: root.space(6)
    readonly property int lg: root.space(8)
    readonly property int xl: root.space(10)
    readonly property int xxl: root.space(12)
    readonly property int huge: root.space(18)
    readonly property int rowHeight: root.space(30)
    // Rows of the track list: two lines of text beside a cover.
    readonly property int trackRow: root.space(52)
    readonly property int thumb: root.space(38)
    readonly property int controlHeight: root.space(28)
  }

  readonly property QtObject font: QtObject {
    // Fontconfig resolves this to the font Omarchy is set to.
    readonly property string family: "monospace"
    readonly property int caption: Math.round(root.baseSize * 0.833)
    readonly property int bodySmall: Math.round(root.baseSize * 0.917)
    readonly property int body: root.baseSize
    readonly property int subtitle: Math.round(root.baseSize * 1.083)
    readonly property int title: Math.round(root.baseSize * 1.167)
    readonly property int heading: Math.round(root.baseSize * 1.333)
    readonly property int icon: Math.round(root.baseSize * 1.167)
    readonly property int iconLarge: Math.round(root.baseSize * 1.5)
  }

  // Top-level `key = "value"` pairs of a TOML file.
  function parsePairs(text) {
    var out = {}
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*"?([^"#\s][^"]*?)"?\s*$/)
      if (!m) m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*"(#[0-9a-fA-F]+)"/)
      if (m) out[m[1]] = m[2]
    }
    return out
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
    onLoaded: {
      var pairs = root.parsePairs(text())
      root.mode = pairs.mode === "light" ? "light" : "dark"
      root.palette = pairs
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = text().match(/^\s*base-size\s*=\s*(\d+)/m)
      root.baseSize = m ? Math.max(6, parseInt(m[1])) : 12
    }
  }
}
