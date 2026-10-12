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

# Download the released daemon for this version and check it against the
# published checksum. Prints the binary's path. Fails when there is no
# release for this version and machine, or when the checksum does not match.
download_daemon() {
  local name="sporetifyd-$VERSION-x86_64-linux"
  local base="$REPOSITORY/releases/download/v$VERSION"
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/sporetify/download"
  [[ $(uname -m) == x86_64 ]] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  rm -rf "$dir"
  mkdir -p "$dir"
  curl -fsSL -o "$dir/$name.tar.gz" "$base/$name.tar.gz" 2>/dev/null || return 1
  curl -fsSL -o "$dir/$name.tar.gz.sha256" "$base/$name.tar.gz.sha256" 2>/dev/null || return 1
  if ! (cd "$dir" && sha256sum --check --quiet "$name.tar.gz.sha256") >&2; then
    echo "sporetify: the downloaded daemon does not match its checksum; not using it" >&2
    return 1
  fi
  tar -xzf "$dir/$name.tar.gz" -C "$dir" sporetifyd || return 1
  echo "$dir/sporetifyd"
}

remove_installed() {
  systemctl --user disable --now sporetifyd.socket sporetifyd.service 2>/dev/null || true
  rm -f "$UNIT_DIR/sporetifyd.socket" "$UNIT_DIR/sporetifyd.service" \
    "$BIN_DIR/sporetifyd" "$BIN_DIR/sporetify" "$APP_DIR/sporetify.desktop" "$ICON_DIR/sporetify.svg"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APP_DIR" 2>/dev/null
  systemctl --user daemon-reload
}
