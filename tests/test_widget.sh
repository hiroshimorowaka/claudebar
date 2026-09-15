#!/usr/bin/env bash
# Widget logic, run headless in Quickshell against fixtures.
#
# Each case builds a config dir with the real QML files and tests/qml/shell.qml,
# puts a fake claudebar CLI on PATH that prints a fixture, runs qs with the
# offscreen platform and reads the RESULT line the harness prints.
source "$(dirname "$0")/lib.sh"

command -v qs >/dev/null || { echo "Quickshell (qs) not found on PATH"; exit 1; }
FIXTURES="$TESTS/fixtures"

# <fixture or ""> [config-json] [second-fixture] [exit-code]
run_widget() {
  local home
  home="$(new_home)"
  mkdir -p "$home/shell" "$home/.config/claudebar"
  ln -s "$ROOT"/quickshell/{Theme,Usage,Panel,IconButton}.qml "$home/shell/"
  cp "$TESTS/qml/shell.qml" "$home/shell/"
  [[ -n $1 ]] && ln -s "$FIXTURES/fake-claudebar" "$home/bin/claudebar"
  [[ -n $1 && -f $FIXTURES/$1.json ]] && cp "$FIXTURES/$1.json" "$home/fixture.json"
  [[ -n ${2:-} ]] && printf '%s' "$2" >"$home/.config/claudebar/config.json"
  [[ -n ${3:-} ]] && cp "$FIXTURES/$3.json" "$home/fixture-2.json"
  [[ -n ${4:-} ]] && printf '%s' "$4" >"$home/fixture.exit"
  use_tool "$home" qs

  RESULT="$(pinned "$home" env QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$home/shell" 2>&1 |
    grep -a -o 'RESULT {.*' | sed 's/^RESULT //')"
  ARGS="$(cat "$home/claudebar-args.log" 2>/dev/null)"
  HOME_DIR="$home"
}

get() { jq -r "$1" <<<"$RESULT" 2>/dev/null; }
cleanup() { rm -rf "$HOME_DIR"; }

section "Pro plan"
run_widget pro
check "harness finished" "$(get .timedOut)" "false"
check "has data" "$(get .hasData)" "true"
check "plan" "$(get .plan)" "Pro"
check "windows" "$(get '.titles | join(",")')" "Session,Weekly"
check "taskbar label shows the session" "$(get .barLabel)" "30%"
check "taskbar label is readable on the card background" "$(get '.barContrast >= 4.5')" "true"
check "no alert dot" "$(get .criticalOthers)" "0"
check "no tooltip" "$(get .barTooltip)" ""
check "not stale" "$(get .barStale)" "false"
check "no extra usage" "$(get .extraSpent)" ""
check "footer shows the update time" "$(get .footerText)" "󰅐  Updated $(date -d 2026-09-15T12:34:00Z +%H:%M)"
check "passes the default gauge colors to the CLI" "$(head -n 1 <<<"$ARGS")" \
  "--json --color-low #98c379 --color-mid #e5c07b --color-high #d19a66 --color-critical #e06c75"
check "a forced refresh adds --refresh" "$(sed -n 2p <<<"$ARGS")" \
  "--json --color-low #98c379 --color-mid #e5c07b --color-high #d19a66 --color-critical #e06c75 --refresh"
check "the panel lays out its content" "$(get '.panelHeight > 200')" "true"
PRO_HEIGHT="$(get .panelHeight)"
cleanup

section "gauge and helpers"
run_widget pro
check "gauge at 0% is low" "$(get '.gauge["0"]')" "#98c379"
check "gauge at 10% blends low toward mid" "$(get '.gauge["10"]')" "#a7c279"
check "gauge at 50% is mid" "$(get '.gauge["50"]')" "#e5c07b"
check "gauge at 75% is high" "$(get '.gauge["75"]')" "#d19a66"
check "gauge at 90% is critical" "$(get '.gauge["90"]')" "#e06c75"
check "gauge at 100% stays critical" "$(get '.gauge["100"]')" "#e06c75"
check "pace ahead" "$(get .paceAhead)" "↑ 19pts ahead"
check "pace under" "$(get .paceUnder)" "↓ 5pts under"
check "pace on" "$(get .paceOn)" "→ on pace"
check "hot pace is urgent" "$(get .paceHot)" "#a55555"
check "durations" "$(get '.durations | join(",")')" "now,1m,3h 5m,2d 3h"
check "a past reset" "$(get .resetPast)" "Resets now"
check "money" "$(get .money)" "\$37.50"
cleanup

section "Max plan with per-model limits and extra usage"
run_widget max
check "plan" "$(get .plan)" "Max 5x"
check "windows" "$(get '.titles | join(",")')" "Session,Weekly,Sonnet · Weekly,Opus · Weekly,Fable · Weekly"
check "taskbar label shows the session" "$(get .barLabel)" "34%"
check "alert dot for the critical Opus limit" "$(get .criticalOthers)" "1"
check "tooltip names the critical limit" "$(get .barTooltip)" "Opus · Weekly: 94%"
check "extra usage spent" "$(get .extraSpent)" "Spent: \$37.50 / \$50.00"
check "extra usage credit" "$(get .extraCredit)" "Available: \$12.50 · Monthly limit: \$200.00"
check "the panel grows with the extra sections" "$(get ".panelHeight > $PRO_HEIGHT")" "true"
cleanup

section "a critical window on the taskbar is not an alert"
run_widget session-critical
check "no alert dot for the window the label already shows" "$(get .criticalOthers)" "0"
check "no tooltip" "$(get .barTooltip)" ""
cleanup
run_widget session-critical '{"barWindow": "weekly"}'
check "alert dot once the critical window is not on the taskbar" "$(get .criticalOthers)" "1"
check "tooltip names it" "$(get .barTooltip)" "Session: 96%"
cleanup

section "config: weekly on the taskbar, no label"
run_widget max '{"barWindow": "weekly"}'
check "taskbar label shows the weekly limit" "$(get .barLabel)" "68%"
cleanup
run_widget max '{"showLabel": false}'
check "no taskbar label" "$(get .barLabel)" ""
check "the alert dot stays" "$(get .criticalOthers)" "1"
cleanup

section "config: colors, gauge and style"
run_widget pro '{"colors": "none"}'
check "monochrome taskbar uses the foreground" "$(get .barColor)" "#cacccc"
check "monochrome panel uses the foreground" "$(get .panelColor50)" "#cacccc"
cleanup
run_widget pro '{"gauge": {"low": "#010203", "critical": "#fafafa"}}'
check "passes the configured gauge to the CLI" "$(sed -n 2p <<<"$ARGS")" \
  "--json --color-low #010203 --color-mid #e5c07b --color-high #d19a66 --color-critical #fafafa --refresh"
cleanup
run_widget pro '{"style": {"fontSize": 24, "radius": 8, "borderWidth": 0, "background": "#000000"}}'
check "sizes scale with the font" "$(get .theme.panelWidth),$(get .theme.caption)" "680,20"
check "radius" "$(get .theme.radius)" "8"
check "border can be removed" "$(get .theme.borderWidth)" "0"
check "background" "$(get .theme.background)" "#000000"
cleanup

section "config: missing or broken"
run_widget pro ""
check "defaults without a config" "$(get '.theme | "\(.refreshSec),\(.barWindow),\(.showLabel),\(.colorMode),\(.panelWidth)"')" "300,session,true,full,340"
cleanup
run_widget pro '{ not json'
check "defaults with a broken config" "$(get '.theme | "\(.refreshSec),\(.barWindow),\(.panelWidth)"')" "300,session,340"
check "still shows the data" "$(get .barLabel)" "30%"
cleanup
run_widget pro '{"refreshIntervalSec": 5, "barWindow": "monthly", "colors": "pink"}'
check "refresh interval has a 60s floor" "$(get .theme.refreshSec)" "60"
check "unknown bar window falls back to session" "$(get .theme.barWindow)" "session"
check "unknown color mode falls back to full" "$(get .theme.colorMode)" "full"
cleanup

section "stale data"
run_widget stale-network
check "stale mark" "$(get .barStale)" "true"
check "footer explains the network" "$(get .footerSuffix)" " · stale (waiting for network)"
check "tooltip explains the stale data" "$(get .barTooltip)" "Stale — showing the last data from $(date -d 2026-09-15T12:34:00Z +%H:%M)"
cleanup
run_widget api-error
check "API error status" "$(get .apiStatus)" "503"
check "footer explains the API errors" "$(get .footerSuffix)" " · stale (API errors)"
cleanup
run_widget pro "" malformed
check "keeps the last good data after a failed refresh" "$(get .barLabel)" "30%"
check "reports the failed refresh" "$(get .footerSuffix)" " · stale (refresh failed)"
check "and the reason" "$(get .loadError)" "claudebar returned malformed output"
cleanup

section "no data"
run_widget loading
check "loading" "$(get .loading)" "true"
check "footer waits for data" "$(get .footerText)" "󰅐  Waiting for first usage data…"
check "dim taskbar" "$(get .barColor)" "#828484"
cleanup
run_widget no-login
check "shows the CLI error" "$(get .loadError)" "No credentials. Run claude to log in."
check "no data" "$(get .hasData)" "false"
cleanup
run_widget old-schema
check_contains "rejects another schema version" "$(get .loadError)" "unexpected document"
cleanup
run_widget malformed
check "rejects malformed output" "$(get .loadError)" "claudebar returned malformed output"
cleanup
run_widget empty "" "" 2
check "empty output reports the exit code" "$(get .loadError)" "claudebar produced no output (exit 2)"
cleanup

section "claudebar CLI not installed"
run_widget ""
check "harness finished" "$(get .timedOut)" "false"
check "flags the missing CLI" "$(get .notInstalled)" "true"
check_contains "tells how to install it" "$(get .loadError)" "claudebar not found on PATH"
cleanup

finish
