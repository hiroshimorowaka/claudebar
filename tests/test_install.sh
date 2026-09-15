#!/usr/bin/env bash
# install.sh against a fake HOME. GNOME, Quickshell, fontconfig and the network
# are stubs, so the test checks what the installer writes and removes without
# touching the real desktop.
source "$(dirname "$0")/lib.sh"

UUID="claudebar@hiroshi"

# A HOME with stubs for everything the installer talks to.
#   gsettings  keeps org.gnome.shell keys in files under ~/.gsettings
#   qs         logs its arguments to ~/qs.log
#   curl       serves a fake claudebar CLI, or a Font Awesome zip for .zip URLs
#   fc-list    reports the Nerd Font, and Font Awesome once its file exists
setup_home() {
  local home
  home="$(new_home)"
  mkdir -p "$home/.gsettings"
  printf "['other@example.com']" >"$home/.gsettings/enabled-extensions"
  printf "['disabled@example.com']" >"$home/.gsettings/disabled-extensions"

  stub "$home" gsettings <<'EOF'
#!/bin/sh
file="$HOME/.gsettings/$3"
case "$1" in
  get) if [ -f "$file" ]; then cat "$file"; else printf '@as []'; fi ;;
  set) printf '%s' "$4" >"$file" ;;
esac
EOF
  stub "$home" gnome-extensions <<'EOF'
#!/bin/sh
exit 1
EOF
  stub "$home" gnome-shell <<'EOF'
#!/bin/sh
exit 0
EOF
  stub "$home" claude <<'EOF'
#!/bin/sh
exit 0
EOF
  stub "$home" xclip <<'EOF'
#!/bin/sh
exit 0
EOF
  stub "$home" qs <<'EOF'
#!/bin/sh
echo "$*" >>"$HOME/qs.log"
EOF
  stub "$home" fc-cache <<'EOF'
#!/bin/sh
exit 0
EOF
  stub "$home" fc-list <<'EOF'
#!/bin/sh
echo "JetBrainsMono Nerd Font"
find "$HOME/.local/share/fonts" -name 'Font Awesome 7 Brands*' 2>/dev/null | grep -q . && echo "Font Awesome 7 Brands"
exit 0
EOF
  stub "$home" curl <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    http*) url="$1" ;;
  esac
  shift
done
echo "$url" >>"$HOME/curl.log"
case "$url" in
  *.zip) python3 - "$out" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("fontawesome-free-7.3.1-desktop/otfs/Font Awesome 7 Brands-Regular-400.otf", "font")
    z.writestr("fontawesome-free-7.3.1-desktop/otfs/Font Awesome 7 Free-Solid-900.otf", "other")
PY
  ;;
  *) printf '#!/bin/sh\necho fake claudebar\n' >"$out" ;;
esac
EOF
  printf '%s' "$home"
}

install() { OUT="$(pinned "$1" bash "$ROOT/install.sh" "${@:2}" 2>&1)"; RC=$?; }

setting() { cat "$1/.gsettings/$2"; }

# Everything in HOME except the test's own scaffolding.
snapshot() {
  (cd "$1" && find . -mindepth 1 \
    -not -path './bin' -not -path './bin/*' \
    -not -path './run' \
    -not -path './.gsettings' -not -path './.gsettings/*' \
    -not -name 'qs.log' -not -name 'curl.log' | sort)
}

section "fresh install"
H="$(setup_home)"
install "$H"
check "exits 0" "$RC" "0"
check "links the widget to the repository" "$(readlink "$H/.config/quickshell/claudebar")" "$ROOT/quickshell"
check "links the extension to the repository" "$(readlink "$H/.local/share/gnome-shell/extensions/$UUID")" "$ROOT/gnome-extension"
check_true "creates the config from the example" cmp -s "$H/.config/claudebar/config.json" "$ROOT/config.example.json"
check_contains "autostart runs the widget daemon" "$(cat "$H/.config/autostart/claudebar.desktop")" "Exec=$H/bin/qs -p $H/.config/quickshell/claudebar -d"
check_true "downloads the claudebar CLI" test -x "$H/.local/bin/claudebar"
check_true "installs only the Brands font" test -f "$H/.local/share/fonts/claudebar/Font Awesome 7 Brands-Regular-400.otf"
check "copies no other font" "$(find "$H/.local/share/fonts/claudebar" -type f | wc -l)" "1"
check_contains "starts the widget" "$(cat "$H/qs.log")" "-p $H/.config/quickshell/claudebar -d"
check "enables the extension and keeps the others" "$(setting "$H" enabled-extensions)" "['other@example.com', '$UUID']"
check "leaves other disabled extensions alone" "$(setting "$H" disabled-extensions)" "['disabled@example.com']"

section "install again"
echo '{"barWindow": "weekly"}' >"$H/.config/claudebar/config.json"
install "$H"
check "exits 0" "$RC" "0"
check "keeps the edited config" "$(cat "$H/.config/claudebar/config.json")" '{"barWindow": "weekly"}'
check "does not list the extension twice" "$(setting "$H" enabled-extensions)" "['other@example.com', '$UUID']"
check "does not download the CLI again" "$(grep -c claudebar "$H/curl.log")" "1"
check "does not download the font again" "$(grep -c '\.zip' "$H/curl.log")" "1"
rm -rf "$H"

section "an extension disabled by gnome-extensions gets enabled"
H="$(setup_home)"
printf "['disabled@example.com', '%s']" "$UUID" >"$H/.gsettings/disabled-extensions"
install "$H"
check "removes the uuid from disabled-extensions" "$(setting "$H" disabled-extensions)" "['disabled@example.com']"
check "adds the uuid to enabled-extensions" "$(setting "$H" enabled-extensions)" "['other@example.com', '$UUID']"
rm -rf "$H"

section "a file in the way stops the install"
H="$(setup_home)"
mkdir -p "$H/.config/quickshell/claudebar"
install "$H"
check_false "exits non-zero" test "$RC" -eq 0
check_contains "explains what to move" "$OUT" "is not a symlink"
rm -rf "$H"

section "uninstall removes everything the install added"
H="$(setup_home)"
before="$(snapshot "$H")"
install "$H"
mkdir -p "$H/.cache/claudebar" && echo '{}' >"$H/.cache/claudebar/usage.json"
echo '{}' >"$H/run/claudebar.json"
install "$H" --uninstall
check "exits 0" "$RC" "0"
check "HOME is back to what it was before the install" "$(snapshot "$H")" "$before"
check "removes the state file" "$(ls "$H/run")" ""
check "restores enabled-extensions" "$(setting "$H" enabled-extensions)" "['other@example.com']"
check "restores disabled-extensions" "$(setting "$H" disabled-extensions)" "['disabled@example.com']"
check_contains "stops the widget" "$(tail -n 1 "$H/qs.log")" "-p $H/.config/quickshell/claudebar kill"
rm -rf "$H"

section "uninstall keeps what the install did not add"
H="$(setup_home)"
stub "$H" claudebar <<'EOF'
#!/bin/sh
echo "the user's own claudebar"
EOF
mkdir -p "$H/.local/share/fonts/mine" "$H/.config/quickshell/other-shell"
touch "$H/.local/share/fonts/mine/Font Awesome 7 Brands-Regular-400.otf"
install "$H"
check "uses the claudebar already on PATH" "$(grep -c claudebar "$H/curl.log" 2>/dev/null || echo 0)" "0"
check "uses the font already installed" "$(test -e "$H/.local/share/fonts/claudebar" && echo installed || echo skipped)" "skipped"
install "$H" --uninstall
check_true "keeps the user's claudebar" test -x "$H/bin/claudebar"
check_true "keeps the user's font" test -f "$H/.local/share/fonts/mine/Font Awesome 7 Brands-Regular-400.otf"
check_true "keeps other Quickshell configs" test -d "$H/.config/quickshell/other-shell"
rm -rf "$H"

section "uninstall without an install"
H="$(setup_home)"
before="$(snapshot "$H")"
install "$H" --uninstall
check "exits 0" "$RC" "0"
check "changes nothing" "$(snapshot "$H")" "$before"
rm -rf "$H"

finish
