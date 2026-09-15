#!/usr/bin/env bash
# The `claudebar --json` contract the widget depends on.
#
# Runs the claudebar CLI installed on this machine against a fake HOME: crafted
# credentials, a cached API response and a curl stub, so nothing reaches the
# network. Every field quickshell/Usage.qml reads is checked here, so updating
# the CLI shows at once whether the widget still understands it.
source "$(dirname "$0")/lib.sh"

command -v claudebar >/dev/null || { echo "claudebar CLI not found on PATH"; exit 1; }

CREDS='{"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":4102444800000,"subscriptionType":"max","rateLimitTier":"default_claude_5x"}}'
COLORS=(--color-low "#112233" --color-mid "#445566" --color-high "#778899" --color-critical "#aabbcc")

in_hours() { date -u -d "+$1 hours" +%Y-%m-%dT%H:%M:%S+00:00; }

# A HOME logged in to Claude. $2 is the curl stub body (the CLI reads
# "body, newline, HTTP status"); an empty body makes curl fail like a network
# that is down.
setup_home() { # <usage-json or ""> <curl-response or "">
  local home
  home="$(new_home)"
  use_tool "$home" claudebar
  use_tool "$home" jq
  mkdir -p "$home/.claude" "$home/.cache/claudebar"
  printf '%s' "$CREDS" >"$home/.claude/.credentials.json"
  printf '%s' '{"oauthAccount":{"organizationUuid":"org-test"}}' >"$home/.claude.json"
  printf '%s' '{"amount":1000,"currency":"USD"}' >"$home/.cache/claudebar/credits.json"
  [[ -n $1 ]] && printf '%s' "$1" >"$home/.cache/claudebar/usage.json"
  if [[ -n $2 ]]; then
    printf '#!/usr/bin/env bash\nprintf %%s %q\n' "$2" | stub "$home" curl
  else
    printf '#!/bin/sh\nexit 7\n' | stub "$home" curl
  fi
  printf '%s' "$home"
}

# The CLI's own test hooks shrink its network retry budget from 20s to 1s.
run() { # <home> [args...]
  OUT="$(pinned "$1" env CLAUDEBAR_TEST_NET_RETRY_DELAY=0 CLAUDEBAR_TEST_NET_QUICK_BUDGET=1 \
    CLAUDEBAR_TEST_NET_LONG_BUDGET=1 claudebar --json "${COLORS[@]}" "${@:2}")"
  RC=$?
}

field() { jq -r "$1" <<<"$OUT" 2>/dev/null; }

USAGE="$(printf '{"five_hour":{"utilization":40,"resets_at":"%s"},"seven_day":{"utilization":20,"resets_at":"%s"},"limits":[{"kind":"weekly_scoped","percent":95,"resets_at":"%s","scope":{"model":{"display_name":"Opus"}}}],"extra_usage":{"is_enabled":true,"used_credits":250,"monthly_limit":5000}}' \
  "$(in_hours 2)" "$(in_hours 72)" "$(in_hours 72)")"

section "fresh data"
H="$(setup_home "$USAGE" "")"
run "$H"
check "exits 0" "$RC" "0"
check "schema_version is 2" "$(field .schema_version)" "2"
check "plan is a string" "$(field '.plan | type')" "string"
check "loading is false" "$(field .loading)" "false"
check "stale is false" "$(field .stale)" "false"
check "no error" "$(field .error)" "null"
check "no last_error" "$(field .last_error)" "null"
check "updated_at is ISO-8601" "$(field '.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")')" "true"

check "windows are session, weekly, then the model limit" "$(field '[.windows[].id] | join(",")')" "session,weekly,model_0"
check "session label" "$(field '.windows[0].label')" "Session"
check "session has no group" "$(field '.windows[0].group')" "null"
check "model window group names the model" "$(field '.windows[2].group')" "Opus"
check "model window label" "$(field '.windows[2].label')" "Weekly"
check "used_pct is a number" "$(field '[.windows[].used_pct | type] | unique | join(",")')" "number"
check "used_pct values" "$(field '[.windows[].used_pct] | join(",")')" "40,20,95"
check "elapsed_pct is a number" "$(field '[.windows[].elapsed_pct | type] | unique | join(",")')" "number"
check "reset_at is ISO-8601" "$(field '[.windows[].reset_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")] | all')" "true"
check "state is a severity" "$(field '[.windows[].state] | join(",")')" "low,low,critical"
check "pace.delta_points is a number" "$(field '[.windows[].pace.delta_points | type] | unique | join(",")')" "number"
check "pace.points_label is a string" "$(field '[.windows[].pace.points_label | type] | unique | join(",")')" "string"
check "pace.state is known" "$(field '[.windows[].pace.state | IN("hot","ahead","on","under")] | all')" "true"

check "extra_usage spent cents" "$(field .extra_usage.used_credit_cents)" "250"
check "extra_usage funded cents" "$(field .extra_usage.funded_credit_cents)" "1250"
check "extra_usage available cents" "$(field .extra_usage.available_credit_cents)" "1000"
check "extra_usage monthly limit cents" "$(field .extra_usage.monthly_limit_cents)" "5000"
check "extra_usage balance_known" "$(field .extra_usage.balance_known)" "true"
check "extra_usage used_pct" "$(field .extra_usage.used_pct)" "20"

check "palette follows --color-critical" "$(field .palette.critical)" "#aabbcc"
check "palette stops thresholds" "$(field '[.palette.stops[].pct] | join(",")')" "0,50,75,90,100"
check "palette stops follow --color-*" "$(field '[.palette.stops[].color] | join(",")')" "#112233,#445566,#778899,#aabbcc,#aabbcc"
rm -rf "$H"

section "no extra usage configured"
H="$(setup_home "$(printf '{"five_hour":{"utilization":5,"resets_at":"%s"},"seven_day":{"utilization":5,"resets_at":"%s"}}' "$(in_hours 1)" "$(in_hours 9)")" "")"
run "$H"
check "extra_usage is null" "$(field .extra_usage)" "null"
check "only session and weekly" "$(field '.windows | length')" "2"
rm -rf "$H"

section "refresh with the network down"
H="$(setup_home "$USAGE" "")"
run "$H" --refresh
check "exits 0" "$RC" "0"
check "keeps the cached windows" "$(field '.windows | length')" "3"
check "marks the data stale" "$(field .stale)" "true"
check "stale_reason is network" "$(field .stale_reason)" "network"
rm -rf "$H"

section "refresh while the API answers an error"
H="$(setup_home "$USAGE" $'{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n503')"
run "$H" --refresh
check "keeps the cached windows" "$(field '.windows | length')" "3"
check "marks the data stale" "$(field .stale)" "true"
check "last_error.http_status" "$(field .last_error.http_status)" "503"
check "last_error.message" "$(field .last_error.message)" "Overloaded"
rm -rf "$H"

section "no data yet and the network down"
H="$(setup_home "" "")"
run "$H"
check "exits 0" "$RC" "0"
check "loading is true" "$(field .loading)" "true"
check "no windows" "$(field '.windows | length')" "0"
rm -rf "$H"

section "not logged in"
H="$(setup_home "$USAGE" "")"
rm "$H/.claude/.credentials.json"
run "$H"
check "exits 0" "$RC" "0"
check "schema_version is 2" "$(field .schema_version)" "2"
check "error.message is a string" "$(field '.error.message | type')" "string"
check "no windows" "$(field '.windows | length')" "0"
rm -rf "$H"

finish
