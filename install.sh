#!/bin/bash
# Install claudebar for the current user on a GNOME X11 desktop.
#
# Usage: ./install.sh              install or update (safe to run again)
#        ./install.sh --uninstall  remove everything except your config

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
NAME="claudebar"
UUID="claudebar@hiroshi"

QS_DIR="$HOME/.config/quickshell/$NAME"
EXTENSION_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$NAME"
AUTOSTART="$HOME/.config/autostart/$NAME.desktop"
BIN_DIR="$HOME/.local/bin"
FONT_DIR="$HOME/.local/share/fonts/$NAME"

CLAUDEBAR_CLI_URL="https://raw.githubusercontent.com/mryll/claudebar/master/claudebar"
FONT_AWESOME_VERSION="7.3.1"
FONT_AWESOME_URL="https://github.com/FortAwesome/Font-Awesome/releases/download/$FONT_AWESOME_VERSION/fontawesome-free-$FONT_AWESOME_VERSION-desktop.zip"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

link() {
  local target="$1" path="$2"
  if [[ -e $path && ! -L $path ]]; then
    die "$path exists and is not a symlink; move it away and run again"
  fi
  mkdir -p "$(dirname "$path")"
  ln -sfn "$target" "$path"
}

stop_widget() {
  command -v qs >/dev/null && qs -p "$QS_DIR" kill >/dev/null 2>&1 || true
}

set_extension_enabled() {
  local enable="$1"
  python3 - "$UUID" "$enable" <<'EOF'
import ast, subprocess, sys
uuid, enable = sys.argv[1], sys.argv[2] == "1"
current = subprocess.check_output(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True).strip()
extensions = ast.literal_eval(current.replace("@as ", "")) or []
extensions = [e for e in extensions if e != uuid] + ([uuid] if enable else [])
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(extensions)])
EOF
}

uninstall() {
  info "Stopping the widget"
  stop_widget
  info "Disabling the GNOME extension"
  set_extension_enabled 0
  rm -f "$QS_DIR" "$EXTENSION_DIR" "$AUTOSTART" "${XDG_RUNTIME_DIR:-/run/user/$UID}/$NAME.json"
  info "Removed. Your config is kept in $CONFIG_DIR"
}

check_requirements() {
  command -v gnome-shell >/dev/null || die "GNOME Shell is required"
  [[ ${XDG_SESSION_TYPE:-} == x11 ]] || warn "claudebar needs a GNOME X11 session; the popup cannot open on GNOME Wayland"
  command -v qs >/dev/null || die "Quickshell (qs) is required: https://quickshell.org/docs/guide/install-setup/"
  for tool in curl jq python3 gsettings; do
    command -v "$tool" >/dev/null || die "$tool is required"
  done
  command -v claude >/dev/null || warn "the claude CLI was not found; log in with 'claude' before using the widget"
  command -v xclip >/dev/null || warn "xclip was not found; the 'copy install command' button will not work"
  fc-list : family | grep -ci "JetBrainsMono Nerd Font" >/dev/null ||
    warn "JetBrainsMono Nerd Font was not found; set style.fontFamily in $CONFIG_DIR/config.json to a Nerd Font you have"
}

install_cli() {
  if command -v claudebar >/dev/null; then
    info "claudebar CLI found at $(command -v claudebar)"
    return
  fi
  info "Installing the claudebar CLI to $BIN_DIR"
  mkdir -p "$BIN_DIR"
  curl -fsSL "$CLAUDEBAR_CLI_URL" -o "$BIN_DIR/claudebar"
  chmod +x "$BIN_DIR/claudebar"
  [[ ":$PATH:" == *":$BIN_DIR:"* ]] || warn "$BIN_DIR is not on your PATH; add it so the widget can run claudebar"
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
  mkdir -p "$FONT_DIR"
  cp "$tmp/Font Awesome 7 Brands-Regular-400.otf" "$FONT_DIR/"
  fc-cache -f "$FONT_DIR" >/dev/null
}

install_widget() {
  info "Linking the widget and the GNOME extension"
  link "$REPO/quickshell" "$QS_DIR"
  link "$REPO/gnome-extension" "$EXTENSION_DIR"

  if [[ -f $CONFIG_DIR/config.json ]]; then
    info "Keeping your config at $CONFIG_DIR/config.json"
  else
    info "Creating $CONFIG_DIR/config.json"
    mkdir -p "$CONFIG_DIR"
    cp "$REPO/config.example.json" "$CONFIG_DIR/config.json"
  fi

  info "Starting the widget with the session"
  mkdir -p "$(dirname "$AUTOSTART")"
  cat >"$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Claudebar
Exec=$(command -v qs) -p $QS_DIR -d
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

  stop_widget
  qs -p "$QS_DIR" -d >/dev/null 2>&1

  info "Enabling the GNOME extension"
  gnome-extensions enable "$UUID" 2>/dev/null || set_extension_enabled 1
}

if [[ ${1:-} == "--uninstall" ]]; then
  uninstall
  exit 0
fi

check_requirements
install_cli
install_font
install_widget

info "Done."
if ! gnome-extensions info "$UUID" 2>/dev/null | grep -q "State: ACTIVE"; then
  echo "    GNOME Shell loads a new extension after a restart: press Alt+F2, type r and press Enter."
fi
