#!/bin/bash
# Install claudebar for the current user on a GNOME X11 desktop.
#
# Usage: ./install.sh              install or update (safe to run again)
#        ./install.sh --uninstall  remove everything the install added
#
# The install copies the widget and the extension out of the repository and
# leaves a copy of this script as ~/.local/share/claudebar/uninstall.sh, so the
# repository can be kept or deleted after the install.
#
# It also records in a manifest what it adds that was not there before: the
# claudebar CLI, the font and every directory it creates. The uninstall reads
# it back, so it removes all of that and nothing that was yours.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
NAME="claudebar"
UUID="claudebar@hiroshi"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$NAME"
RUNTIME_STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$NAME.json"

QS_DIR="$DATA_HOME/$NAME/quickshell"
# Where versions before 2026-09-15 put the widget.
OLD_QS_DIR="$CONFIG_HOME/quickshell/$NAME"
EXTENSION_DIR="$DATA_HOME/gnome-shell/extensions/$UUID"
CONFIG_DIR="$CONFIG_HOME/$NAME"
AUTOSTART="$CONFIG_HOME/autostart/$NAME.desktop"
UNINSTALLER="$DATA_HOME/$NAME/uninstall.sh"
BIN_DIR="$HOME/.local/bin"
FONT_DIR="$DATA_HOME/fonts/$NAME"
MANIFEST="$STATE_DIR/installed"

CLAUDEBAR_CLI_URL="https://raw.githubusercontent.com/mryll/claudebar/master/claudebar"
FONT_AWESOME_VERSION="7.3.1"
FONT_AWESOME_URL="https://github.com/FortAwesome/Font-Awesome/releases/download/$FONT_AWESOME_VERSION/fontawesome-free-$FONT_AWESOME_VERSION-desktop.zip"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- manifest

record() {
  mkdir -p "$STATE_DIR"
  grep -qxF "$1" "$MANIFEST" 2>/dev/null || printf '%s\n' "$1" >>"$MANIFEST"
}

# Create a directory, recording the outermost one that did not exist.
make_dir() {
  local dir="$1" missing=""
  while [[ ! -d $dir ]]; do
    missing="$dir"
    dir="$(dirname "$dir")"
  done
  [[ -n $missing ]] || return 0
  mkdir -p "$1"
  # The manifest lives in STATE_DIR: record its own parent only.
  if [[ $missing == "$STATE_DIR" ]]; then return 0; fi
  if [[ $STATE_DIR == "$missing"/* && ! -d $STATE_DIR ]]; then
    mkdir -p "$STATE_DIR"
  fi
  record "dir $missing"
}

# ---- helpers

installed_files() { grep -qxF files "$MANIFEST" 2>/dev/null; }

# A path this project may replace or remove: a link from an older install
# that pointed into the repository, or a copy this installer made.
ours() { [[ -L $1 ]] || installed_files; }

# Replace <dest> with a copy of <source>.
place() { # <source> <dest>
  rm -rf "$2"
  make_dir "$(dirname "$2")"
  cp -r "$1" "$2"
}

stop_widget() {
  if command -v qs >/dev/null; then
    qs -p "$QS_DIR" kill >/dev/null 2>&1 || true
    qs -p "$OLD_QS_DIR" kill >/dev/null 2>&1 || true
  fi
}

# An older install put the widget in ~/.config/quickshell/claudebar, as a link
# into the repository or as a copy. Remove it only when it is that widget, so a
# Quickshell config of the user's own with the same name stays.
remove_old_widget() {
  [[ -f $OLD_QS_DIR/shell.qml ]] && grep -qF 'target: "claudebar"' "$OLD_QS_DIR/shell.qml" || return 0
  if [[ -L $OLD_QS_DIR ]] || installed_files; then
    info "Removing the widget from its old place, $OLD_QS_DIR"
    rm -rf "$OLD_QS_DIR"
  fi
}

# GNOME reads two lists, and disabled-extensions wins over enabled-extensions.
# `gnome-extensions disable` adds the uuid to the disabled list, so enabling
# has to take it out of there too.
set_extension_enabled() {
  local enable="$1"
  python3 - "$UUID" "$enable" <<'EOF'
import ast, subprocess, sys
uuid, enable = sys.argv[1], sys.argv[2] == "1"

def update(key, keep):
    current = subprocess.check_output(["gsettings", "get", "org.gnome.shell", key], text=True).strip()
    extensions = ast.literal_eval(current.replace("@as ", "")) or []
    updated = [e for e in extensions if e != uuid] + ([uuid] if keep else [])
    if updated != extensions:
        subprocess.check_call(["gsettings", "set", "org.gnome.shell", key, str(updated)])

update("enabled-extensions", enable)
update("disabled-extensions", False)
EOF
}

# ---- uninstall

uninstall() {
  local entries=()
  [[ -f $MANIFEST ]] && mapfile -t entries <"$MANIFEST"

  info "Stopping the widget"
  stop_widget

  if command -v gsettings >/dev/null && command -v python3 >/dev/null; then
    info "Disabling the GNOME extension"
    set_extension_enabled 0
  fi

  info "Removing the widget, the extension, the config and the cache"
  remove_old_widget
  local path
  for path in "$QS_DIR" "$EXTENSION_DIR" "$(dirname "$UNINSTALLER")"; do
    if [[ -L $path ]] || { [[ -e $path ]] && [[ ${#entries[@]} -gt 0 ]] && printf '%s\n' "${entries[@]}" | grep -qxF files; }; then
      rm -rf "$path"
    fi
  done
  rm -f "$AUTOSTART" "$RUNTIME_STATE"
  rm -rf "$CONFIG_DIR" "$CACHE_DIR" "$STATE_DIR"

  local entry
  for entry in "${entries[@]}"; do
    case "$entry" in
      cli)
        info "Removing the claudebar CLI"
        rm -f "$BIN_DIR/claudebar"
        ;;
      font)
        info "Removing the Font Awesome Brands font"
        rm -rf "$FONT_DIR"
        command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
        ;;
    esac
  done

  # Directories the install created, if nothing else lives in them now.
  for entry in "${entries[@]}"; do
    if [[ $entry == "dir "* && -d ${entry#dir } ]]; then
      find "${entry#dir }" -depth -type d -empty -delete
    fi
  done

  info "claudebar is uninstalled."
}

# ---- install

check_requirements() {
  command -v gnome-shell >/dev/null || die "GNOME Shell is required"
  [[ ${XDG_SESSION_TYPE:-} == x11 ]] || warn "claudebar needs a GNOME X11 session; the popup cannot open on GNOME Wayland"
  command -v qs >/dev/null || die "Quickshell (qs) is required: https://quickshell.org/docs/guide/install-setup/"
  local tool
  for tool in curl jq python3 gsettings; do
    command -v "$tool" >/dev/null || die "$tool is required"
  done
  command -v claude >/dev/null || warn "the claude CLI was not found; log in with 'claude' before using the widget"
  command -v xclip >/dev/null || warn "xclip was not found; the 'copy install command' button will not work"
  fc-list : family | grep -ci "JetBrainsMono Nerd Font" >/dev/null ||
    warn "JetBrainsMono Nerd Font was not found; set style.fontFamily in $CONFIG_DIR/config.json to a Nerd Font you have"
}

install_cli() {
  if [[ -x $BIN_DIR/claudebar ]] && grep -qxF cli "$MANIFEST" 2>/dev/null; then
    info "claudebar CLI already installed at $BIN_DIR/claudebar"
  elif command -v claudebar >/dev/null; then
    info "claudebar CLI found at $(command -v claudebar)"
  else
    info "Installing the claudebar CLI to $BIN_DIR"
    make_dir "$BIN_DIR"
    curl -fsSL "$CLAUDEBAR_CLI_URL" -o "$BIN_DIR/claudebar"
    chmod +x "$BIN_DIR/claudebar"
    record cli
  fi
  [[ ":$PATH:" == *":$BIN_DIR:"* ]] || command -v claudebar >/dev/null ||
    warn "$BIN_DIR is not on your PATH; add it so the widget can run claudebar"
}

install_font() {
  if fc-list : family | grep -c "Font Awesome 7 Brands" >/dev/null; then
    info "Font Awesome 7 Brands found"
    return
  fi
  command -v unzip >/dev/null || die "unzip is required to install Font Awesome"
  info "Installing Font Awesome $FONT_AWESOME_VERSION Brands (Claude glyph) to $FONT_DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "$FONT_AWESOME_URL" -o "$tmp/fontawesome.zip"
  unzip -q -j "$tmp/fontawesome.zip" "*/otfs/Font Awesome 7 Brands-Regular-400.otf" -d "$tmp"
  make_dir "$FONT_DIR"
  cp "$tmp/Font Awesome 7 Brands-Regular-400.otf" "$FONT_DIR/"
  record font
  fc-cache -f "$FONT_DIR" >/dev/null
}

install_widget() {
  local path
  for path in "$QS_DIR" "$EXTENSION_DIR"; do
    if [[ -e $path ]] && ! ours "$path"; then
      die "$path was not installed by claudebar; move it away and run again"
    fi
  done

  stop_widget
  remove_old_widget
  info "Copying the widget, the GNOME extension and the uninstaller"
  place "$REPO/quickshell" "$QS_DIR"
  place "$REPO/gnome-extension" "$EXTENSION_DIR"
  make_dir "$(dirname "$UNINSTALLER")"
  cp "$REPO/install.sh" "$UNINSTALLER"
  chmod +x "$UNINSTALLER"
  record files

  if [[ -f $CONFIG_DIR/config.json ]]; then
    info "Keeping your config at $CONFIG_DIR/config.json"
  else
    info "Creating $CONFIG_DIR/config.json"
    make_dir "$CONFIG_DIR"
    cp "$REPO/config.example.json" "$CONFIG_DIR/config.json"
  fi

  info "Starting the widget with the session"
  make_dir "$(dirname "$AUTOSTART")"
  cat >"$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Claudebar
Exec=$(command -v qs) -p $QS_DIR -d
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

  qs -p "$QS_DIR" -d >/dev/null 2>&1

  info "Enabling the GNOME extension"
  set_extension_enabled 1
}

if [[ ${1:-} == "--uninstall" || $(basename "$0") == uninstall.sh ]]; then
  uninstall
  exit 0
fi

check_requirements
install_cli
install_font
install_widget

info "Done. To uninstall later, run $UNINSTALLER"
if ! gnome-extensions info "$UUID" 2>/dev/null | grep -q "State: ACTIVE"; then
  echo "    GNOME Shell loads a new extension after a restart: press Alt+F2, type r and press Enter."
fi
