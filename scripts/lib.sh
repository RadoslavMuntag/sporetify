# Sourced by setup.sh, install-dev.sh and uninstall.sh, after env.sh.
# Everything here touches only Sporetify's own files.

say() { echo "sporetify: $*"; }
die() { echo "sporetify: $*" >&2; exit 1; }

# What the daemon and the frontends call at run time.
check_requirements() {
  local missing=()
  local tool
  for tool in jq systemctl secret-tool qs hyprctl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  # The daemon plays through PulseAudio's client library (PipeWire provides it).
  # (Not `grep -q`: it stops reading early, which fails the pipe under pipefail.)
  [[ -n $(ldconfig -p 2>/dev/null | grep 'libpulse\.so') ]] || missing+=("libpulse")
  if ((${#missing[@]})); then
    die "missing: ${missing[*]}. On Omarchy all of these are installed by default; install them and run this again."
  fi
}

# Put a daemon binary in place and (re)start listening for it.
install_daemon() {
  local binary="$1"
  [[ -x $binary ]] || die "no daemon binary at $binary"
  mkdir -p "$BIN_DIR" "$UNIT_DIR"
  systemctl --user stop sporetifyd.service 2>/dev/null || true
  install -m 755 "$binary" "$BIN_DIR/sporetifyd"
  install -m 644 "$ROOT/systemd/sporetifyd.socket" "$ROOT/systemd/sporetifyd.service" "$UNIT_DIR/"
  systemctl --user daemon-reload
  systemctl --user enable --now sporetifyd.socket
}

# The `sporetify` command, its icon and its entry in the application menu.
# The entry says Sporetify can open spotify: links; whether it is the one
# that does is the user's choice (see the README), never made here.
install_launcher() {
  mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  ln -sfn "$ROOT/bin/sporetify" "$BIN_DIR/sporetify"
  install -m 644 "$ROOT/assets/sporetify.svg" "$ICON_DIR/sporetify.svg"
  cat >"$APP_DIR/sporetify.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Sporetify
Comment=Keyboard-first Spotify client
Exec=$BIN_DIR/sporetify %u
Icon=sporetify
Categories=AudioVideo;Audio;Player;
MimeType=x-scheme-handler/spotify;
StartupWMClass=sporetify
DESKTOP
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APP_DIR" 2>/dev/null
  return 0
}

# Build the daemon from this checkout. Prints the binary's path.
build_daemon() {
  command -v cargo >/dev/null 2>&1 || die "building needs Rust (cargo); install it or use a released version"
  cargo build --release --locked --manifest-path "$ROOT/daemon/Cargo.toml" >&2
  echo "$CARGO_TARGET_DIR/release/sporetifyd"
}

# The SHA-256 this checkout expects for a released archive, from
# scripts/daemon.sha256. Prints nothing when the archive is not listed.
pinned_digest() {
  awk -v name="$1" '!/^#/ && $2 == name && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }' "$ROOT/scripts/daemon.sha256" 2>/dev/null
}

# Download the released daemon for this version. It is used only if its
# SHA-256 equals the one committed in scripts/daemon.sha256: the release can
# be changed after the fact, the digest in this checkout cannot. Prints the
# binary's path. Fails when no digest is committed for this version, there is
# nothing to download, or the download is not the pinned file.
download_daemon() {
  local name="sporetifyd-$VERSION-x86_64-linux.tar.gz"
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/sporetify/download"
  local expected actual
  [[ $(uname -m) == x86_64 ]] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  expected="$(pinned_digest "$name")"
  if [[ -z $expected ]]; then
    echo "sporetify: this version has no pinned daemon build" >&2
    return 1
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  curl -fsSL -o "$dir/$name" "$REPOSITORY/releases/download/v$VERSION/$name" 2>/dev/null || return 1
  actual="$(sha256sum "$dir/$name" | cut -d' ' -f1)"
  if [[ $actual != "$expected" ]]; then
    echo "sporetify: the downloaded daemon is not the build this version was reviewed with; not using it" >&2
    echo "sporetify:   expected $expected" >&2
    echo "sporetify:   got      $actual" >&2
    rm -rf "$dir"
    return 1
  fi
  tar -xzf "$dir/$name" -C "$dir" sporetifyd || return 1
  echo "$dir/sporetifyd"
}

remove_installed() {
  systemctl --user disable --now sporetifyd.socket sporetifyd.service 2>/dev/null || true
  rm -f "$UNIT_DIR/sporetifyd.socket" "$UNIT_DIR/sporetifyd.service" \
    "$BIN_DIR/sporetifyd" "$BIN_DIR/sporetify" "$APP_DIR/sporetify.desktop" "$ICON_DIR/sporetify.svg"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APP_DIR" 2>/dev/null
  systemctl --user daemon-reload
}
