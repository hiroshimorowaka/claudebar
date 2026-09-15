#!/usr/bin/env bash
# Shared helpers for the test suite.
#
# Every test runs against a throwaway HOME with every XDG directory pinned
# inside it and a minimal PATH. A run never reads or writes the developer's
# real config, cache, fonts, extensions or GNOME settings: an unpinned test
# would pass on this machine because of its own setup and fail on another.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/tests"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }
section() { printf '== %s\n' "$1"; }

check() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "got: $2 | want: $3"; fi
}

check_contains() { # <name> <text> <fragment>
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "'$2' does not contain '$3'"; fi
}

check_true() { # <name> <command...>
  local name="$1"
  shift
  if "$@"; then ok "$name"; else no "$name" "failed: $*"; fi
}

check_false() { # <name> <command...>
  local name="$1"
  shift
  if "$@"; then no "$name" "unexpectedly succeeded: $*"; else ok "$name"; fi
}

# A fresh HOME with the base XDG directories every desktop session has, and an
# empty bin/ that goes first on PATH. The runtime dir is kept short because
# Unix sockets (Quickshell IPC) cap paths at 108 bytes.
new_home() {
  local home
  home="$(mktemp -d "${TMPDIR:-/tmp}/claudebar-test.XXXXXX")"
  mkdir -p "$home/bin" "$home/run" "$home/.cache" "$home/.config" "$home/.local/share" "$home/.local/state"
  chmod 700 "$home/run"
  printf '%s' "$home"
}

# Make a real tool from the developer's PATH available inside a test HOME.
use_tool() { # <home> <name>
  local path
  path="$(command -v "$2")" || return 1
  ln -sf "$path" "$1/bin/$2"
}

# Write an executable stub into the test HOME's bin/.
stub() { # <home> <name> <<'EOF' ... EOF
  cat >"$1/bin/$2"
  chmod +x "$1/bin/$2"
}

# Run a command with a clean environment pinned to the test HOME.
pinned() { # <home> <command...>
  local home="$1"
  shift
  env -i \
    HOME="$home" USER="${USER:-test}" LANG=C.UTF-8 TERM=dumb \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    XDG_DATA_HOME="$home/.local/share" \
    XDG_RUNTIME_DIR="$home/run" \
    XDG_SESSION_TYPE=x11 \
    PATH="$home/bin:/usr/bin:/bin" \
    "$@"
}

finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
