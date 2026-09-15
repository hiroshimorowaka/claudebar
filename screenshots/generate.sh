#!/usr/bin/env bash
# Regenerate the screenshots in this folder from fake data.
#
#   screenshots/generate.sh
#
# Each screenshot runs the real widget offscreen in Quickshell and the real
# claudebar CLI from your PATH, in a temporary HOME with fake credentials, a
# cached API response and a stubbed curl. Nothing reaches the network and no
# real account is shown. Countdowns and pace are computed from the current
# time, so they read like a live widget.
source "$(dirname "$0")/../tests/lib.sh"
set -e

SHOTS="$ROOT/screenshots"
# The temporary HOME hides your fonts from fontconfig; the card needs yours.
FONTS="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
command -v qs >/dev/null || { echo "Quickshell (qs) not found on PATH"; exit 1; }
command -v claudebar >/dev/null || { echo "claudebar CLI not found on PATH"; exit 1; }

iso_in() { date -u -d "+$1 seconds" +%Y-%m-%dT%H:%M:%S+00:00; }

# Remaining seconds for a window of <length> seconds of which <elapsed>% passed.
remaining() { echo $(($1 * (100 - $2) / 100)); }
FIVE_HOURS=18000
WEEK=604800

# The same demo day the claudebar README uses: every gauge band and pace state.
MAX_USAGE="$(cat <<EOF
{
  "five_hour": {"utilization": 34, "resets_at": "$(iso_in "$(remaining $FIVE_HOURS 15)")"},
  "seven_day": {"utilization": 68, "resets_at": "$(iso_in "$(remaining $WEEK 68)")"},
  "seven_day_sonnet": {"utilization": 82, "resets_at": "$(iso_in "$(remaining $WEEK 95)")"},
  "limits": [
    {"kind": "weekly_scoped", "percent": 94, "resets_at": "$(iso_in "$(remaining $WEEK 60)")", "scope": {"model": {"display_name": "Opus"}}},
    {"kind": "weekly_scoped", "percent": 12, "resets_at": "$(iso_in "$(remaining $WEEK 60)")", "scope": {"model": {"display_name": "Fable"}}}
  ],
  "extra_usage": {"is_enabled": true, "used_credits": 3750, "monthly_limit": 20000}
}
EOF
)"
PRO_USAGE="$(cat <<EOF
{
  "five_hour": {"utilization": 41, "resets_at": "$(iso_in "$(remaining $FIVE_HOURS 55)")"},
  "seven_day": {"utilization": 23, "resets_at": "$(iso_in "$(remaining $WEEK 30)")"}
}
EOF
)"

# <file> <plan: pro|max> <usage json or ""> <network: up|down|503> [config json] [--no-cli] [--no-login]
shot() {
  local file="$1" plan="$2" usage="$3" network="$4" config="${5:-}" flag home
  shift 5 || shift $#
  home="$(new_home)"
  mkdir -p "$home/shell" "$home/.claude" "$home/.cache/claudebar" "$home/.config/claudebar"
  ln -s "$ROOT"/quickshell/{Theme,Usage,Panel,Card,IconButton}.qml "$home/shell/"
  cp "$SHOTS/qml/shell.qml" "$home/shell/"
  use_tool "$home" qs
  use_tool "$home" claudebar
  ln -s "$FONTS" "$home/.local/share/fonts"

  local tier="default"
  [[ $plan == max ]] && tier="default_claude_5x"
  printf '{"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":4102444800000,"subscriptionType":"%s","rateLimitTier":"%s"}}' \
    "$plan" "$tier" >"$home/.claude/.credentials.json"
  printf '%s' '{"oauthAccount":{"organizationUuid":"org-demo"}}' >"$home/.claude.json"
  printf '%s' '{"amount":1250,"currency":"USD"}' >"$home/.cache/claudebar/credits.json"
  [[ -n $config ]] && printf '%s' "$config" >"$home/.config/claudebar/config.json"

  if [[ -n $usage ]]; then
    printf '%s' "$usage" >"$home/.cache/claudebar/usage.json"
    # A fresh cache is served as is; an old one makes the CLI ask the network.
    [[ $network == up ]] || touch -d '-12 minutes' "$home/.cache/claudebar/usage.json" "$home/.cache/claudebar/credits.json"
  fi

  case "$network" in
    503) printf '#!/bin/sh\nprintf %%s %s\n' "'{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}
503'" | stub "$home" curl ;;
    *) printf '#!/bin/sh\nexit 7\n' | stub "$home" curl ;;
  esac

  for flag in "$@"; do
    case "$flag" in
      --no-cli) rm "$home/bin/claudebar" ;;
      --no-login) rm "$home/.claude/.credentials.json" ;;
    esac
  done

  local log
  log="$(pinned "$home" env QT_QPA_PLATFORM=offscreen SHOT="$SHOTS/$file" \
    CLAUDEBAR_TEST_NET_RETRY_DELAY=0 CLAUDEBAR_TEST_NET_QUICK_BUDGET=1 CLAUDEBAR_TEST_NET_LONG_BUDGET=1 \
    timeout 30 qs -p "$home/shell" 2>&1 | grep -a -o 'SHOT .*' || true)"
  printf '  %-28s %s\n' "$file" "${log#SHOT }"
  rm -rf "$home"
}

echo "Generating screenshots in $SHOTS"
shot panel.png                max "$MAX_USAGE" up
shot panel-pro.png            pro "$PRO_USAGE" up
shot panel-monochrome.png     max "$MAX_USAGE" up '{"colors": "none"}'
shot panel-stale-network.png  pro "$PRO_USAGE" down
shot panel-api-error.png      pro "$PRO_USAGE" 503
shot panel-loading.png        pro ""           down
shot panel-not-logged-in.png  pro "$PRO_USAGE" up "" --no-login
shot panel-cli-missing.png    pro "$PRO_USAGE" up "" --no-cli
