#!/usr/bin/env bash
# Run the whole suite and the lint checks. Exits non-zero if anything fails.
#
#   tests/run_all.sh
#
# Needs qs (Quickshell) and the claudebar CLI on PATH, plus jq and python3.
# node, shellcheck and qmlformat add lint checks when they are available.

cd "$(dirname "$0")/.." || exit 1
rc=0

for test in tests/test_*.sh; do
  echo "== $test"
  bash "$test" | grep -E '^(  FAIL|       |[0-9]+ passed)' || true
  [[ ${PIPESTATUS[0]} -eq 0 ]] || rc=1
done

echo "== lint"
lint() { # <name> <command...>
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then echo "  ok   $name"; else echo "  FAIL $name"; rc=1; fi
}
skip() { echo "  skip $1 ($2 not installed)"; }

for script in install.sh tests/*.sh screenshots/generate.sh; do
  lint "bash syntax: $script" bash -n "$script"
done

if command -v shellcheck >/dev/null; then
  lint "shellcheck: install.sh" shellcheck -S warning install.sh
else
  skip "shellcheck" shellcheck
fi

if command -v node >/dev/null; then
  lint "extension.js syntax" node --input-type=module --check <gnome-extension/extension.js
else
  skip "extension.js syntax" node
fi

qmlformat="$(command -v qmlformat || ls /opt/Qt/*/gcc_64/bin/qmlformat 2>/dev/null | tail -n 1)"
if [[ -x $qmlformat ]]; then
  for file in quickshell/*.qml tests/qml/*.qml screenshots/qml/*.qml; do
    lint "QML syntax: $file" "$qmlformat" "$file"
  done
else
  skip "QML syntax" qmlformat
fi

for file in config.example.json gnome-extension/metadata.json tests/fixtures/*.json; do
  [[ $file == */malformed.json ]] && continue
  lint "valid JSON: $file" jq -e . "$file"
done

# The widget, the extension and the installer find each other by name.
uuid="$(jq -r .uuid gnome-extension/metadata.json)"
lint "installer uses the extension uuid ($uuid)" grep -qF "UUID=\"$uuid\"" install.sh
lint "extension and widget share the IPC target" \
  bash -c "grep -qF 'target: \"claudebar\"' quickshell/shell.qml && grep -qF \"'call', 'claudebar'\" gnome-extension/extension.js"
lint "extension and widget share the state file" \
  bash -c "grep -qF '\"/claudebar.json\"' quickshell/shell.qml && grep -qF \"'claudebar.json'\" gnome-extension/extension.js"

echo
if [[ $rc -eq 0 ]]; then echo "all green"; else echo "FAILED"; fi
exit $rc
