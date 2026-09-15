import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Claude plan usage: runs `claudebar --json` on a timer and turns the document
// into what the panel and the taskbar face draw — one entry per usage window,
// the extra usage, freshness, and the gauge colors for any percentage.
QtObject {
  id: root

  readonly property string bin: "claudebar"
  readonly property string installCmd: "curl -fsSL https://raw.githubusercontent.com/mryll/claudebar/master/claudebar -o ~/.local/bin/claudebar && chmod +x ~/.local/bin/claudebar"

  property var doc: null
  readonly property bool hasData: doc !== null
  property string loadError: ""
  property bool loading: false
  property bool notInstalled: false
  property bool runFailed: false
  property double nowMs: Date.now()

  // ---------------------------------------------------------------- fetch
  //
  // stdout and the exit code arrive in either order, so a run only finishes
  // once both are in. A refresh asked for during a run is queued, not dropped.
  property bool collected: true
  property bool exited: true
  readonly property bool busy: !collected || !exited
  property string output: ""
  property int exitCode: 0
  property var pending: null

  function refresh(force) {
    var args = ["--json",
      "--color-low", String(Theme.gauge.low), "--color-mid", String(Theme.gauge.mid),
      "--color-high", String(Theme.gauge.high), "--color-critical", String(Theme.gauge.critical)]
    if (force === true) args.push("--refresh")
    start(args)
  }

  function start(args) {
    if (proc.running) { pending = args; return }
    collected = false
    exited = false
    output = ""
    exitCode = 0
    // Through sh: Quickshell aborts when asked to start a binary that does
    // not exist, while sh always starts and reports it as exit 127.
    proc.command = ["/bin/sh", "-c", 'exec "$0" "$@"', bin].concat(args)
    proc.running = true
  }

  function finishIfDone() {
    if (!collected || !exited) return
    exitFallback.stop()
    finish()
  }

  function fail(message) {
    loadError = String(message)
    loading = false
    runFailed = true
  }

  function finish() {
    notInstalled = false
    var text = output.trim()
    if (text === "") {
      if (exitCode === 126 || exitCode === 127) {
        notInstalled = true
        fail(bin + " not found on PATH.\n\nInstall it with:\n" + installCmd)
      } else {
        fail(bin + " produced no output (exit " + exitCode + ")")
      }
    } else {
      parse(text)
    }
    if (pending) {
      var next = pending
      pending = null
      Qt.callLater(function() { start(next) })
    }
  }

  // The last good document stays on screen through any failure; a malformed
  // or failed run is always reported, never swallowed.
  function parse(text) {
    nowMs = Date.now()
    var d = null
    try { d = JSON.parse(text) } catch (e) { d = null }
    if (d === null || typeof d !== "object") {
      fail(exitCode !== 0 ? bin + " failed (exit " + exitCode + ")" : bin + " returned malformed output")
      return
    }
    if (Number(d.schema_version) !== 2) {
      fail(bin + " returned an unexpected document (schema_version " + d.schema_version + ", expected 2)")
      return
    }
    if (d.loading === true) {
      loading = true
      loadError = ""
      return
    }
    if (d.error && !(Array.isArray(d.windows) && d.windows.length > 0)) {
      fail(String(d.error.message || bin + " failed"))
      return
    }
    doc = d
    loading = false
    loadError = ""
    runFailed = false
  }

  property Process proc: Process {
    onRunningChanged: {
      if (running) return
      root.exited = true
      exitFallback.restart()
      root.finishIfDone()
    }
    onExited: function(code) {
      root.exitCode = code
      root.exited = true
      exitFallback.restart()
      root.finishIfDone()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.output = text.length > 1024 * 1024 ? "" : text
        root.collected = true
        root.finishIfDone()
      }
    }
  }

  property Timer exitFallback: Timer {
    interval: 300
    onTriggered: { root.collected = true; root.finishIfDone() }
  }

  property Timer poll: Timer {
    interval: Theme.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // ---------------------------------------------------------------- model

  // Every window the document carries, already ordered and named by the CLI.
  readonly property var windows: {
    if (!doc || !Array.isArray(doc.windows)) return []
    var out = []
    for (var i = 0; i < doc.windows.length; i++) {
      var w = doc.windows[i]
      if (w) out.push({ title: w.group ? String(w.group) + " · " + String(w.label || "") : String(w.label || ""), w: w })
    }
    return out
  }

  function windowById(id) {
    for (var i = 0; i < windows.length; i++)
      if (String(windows[i].w.id) === id) return windows[i].w
    return null
  }

  readonly property string plan: doc ? String(doc.plan || "").replace(/[<>&]/g, " ").trim() : ""
  readonly property var extra: doc ? (doc.extra_usage || null) : null
  readonly property string extraSpent: extra
    ? "Spent: " + money(extra.used_credit_cents) + " / " + (extra.balance_known === true ? money(extra.funded_credit_cents) : "—")
    : ""
  readonly property string extraCredit: extra
    ? "Available: " + (extra.balance_known === true ? money(extra.available_credit_cents) : "—") + " · Monthly limit: " + money(extra.monthly_limit_cents)
    : ""
  readonly property bool stale: runFailed || !!(doc && doc.stale === true)
  readonly property var apiError: doc ? (doc.last_error || null) : null

  // ---------------------------------------------------------------- taskbar face

  readonly property var barWindowData: windowById(Theme.barWindow)
  readonly property real barPct: barWindowData ? Number(barWindowData.used_pct || 0) : 0
  readonly property string barLabel: Theme.showLabel && barWindowData ? Math.round(barPct) + "%" : ""

  // The face takes the gauge color of the value it shows, lifted to stay
  // readable on the taskbar. Stale data gets its own mark, never a color.
  readonly property color barColor: {
    if (!hasData) return Theme.dim
    return Theme.barColored ? contrastFloor(usageColor(barPct), Theme.background, Theme.foreground, 4.5) : Theme.foreground
  }
  readonly property bool barStale: hasData && stale

  // Windows other than the one on the taskbar that are critical: shown as a
  // dot so a spent weekly limit still gets noticed while the session is fine.
  readonly property var criticalOthers: {
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var entry = windows[i]
      if (entry.w !== barWindowData && String(entry.w.state || "") === "critical") out.push(entry)
    }
    return out
  }
  readonly property color alertColor: Theme.barColored ? contrastFloor(gaugeCritical, Theme.background, Theme.foreground, 4.5) : Theme.foreground

  readonly property string barTooltip: {
    var lines = []
    for (var i = 0; i < criticalOthers.length; i++)
      lines.push(criticalOthers[i].title + ": " + Math.round(Number(criticalOthers[i].w.used_pct || 0)) + "%")
    if (barStale) lines.push("Stale — showing the last data from " + (updatedAt() || "earlier"))
    return lines.join("\n")
  }

  // ---------------------------------------------------------------- gauge
  //
  // Green at 0%, through amber, to red at the top. The CLI publishes the
  // stops (colors from our config, percentages from its thresholds), and a
  // percentage is colored by interpolating between them.
  readonly property color gaugeCritical: paletteColor("critical", Theme.gauge.critical)

  function paletteColor(key, fallback) {
    var p = doc && doc.palette ? doc.palette : null
    return p && typeof p[key] === "string" && p[key].length > 0 ? p[key] : fallback
  }

  readonly property var stops: {
    var raw = doc && doc.palette ? doc.palette.stops : null
    var out = []
    if (raw && raw.length !== undefined) {
      for (var i = 0; i < raw.length; i++) {
        var pct = Number(raw[i] ? raw[i].pct : NaN)
        var col = String(raw[i] ? raw[i].color || "" : "")
        if (isFinite(pct) && col !== "") out.push({ pct: clamp(pct, 0, 100), color: Qt.darker(col, 1.0) })
      }
      out.sort(function(a, b) { return a.pct - b.pct })
    }
    if (out.length > 0) return out
    return [ { pct: 0, color: Qt.darker(Theme.gauge.low, 1.0) },
             { pct: 50, color: Qt.darker(Theme.gauge.mid, 1.0) },
             { pct: 75, color: Qt.darker(Theme.gauge.high, 1.0) },
             { pct: 90, color: Qt.darker(Theme.gauge.critical, 1.0) } ]
  }

  function usageColor(pct) {
    var p = clamp(Number(pct) || 0, 0, 100)
    if (p <= stops[0].pct) return stops[0].color
    for (var i = stops.length - 1; i >= 0; i--) {
      if (p < stops[i].pct) continue
      if (i === stops.length - 1) return stops[i].color
      var span = stops[i + 1].pct - stops[i].pct
      return span <= 0 ? stops[i].color : mix(stops[i].color, stops[i + 1].color, (p - stops[i].pct) / span)
    }
    return stops[0].color
  }

  function panelColor(pct) { return Theme.panelColored ? usageColor(pct) : Theme.foreground }

  // Only burning fast earns full urgent; slightly ahead gets a nudge.
  function paceColor(state) {
    if (!Theme.panelColored) return state === "hot" ? Theme.foreground : Theme.dim
    if (state === "hot") return Theme.urgent
    if (state === "ahead") return mix(Theme.dim, Theme.urgent, 0.5)
    return Theme.dim
  }

  // ---------------------------------------------------------------- helpers

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  function luminance(c) {
    function chan(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
  }

  // WCAG contrast floor: blend toward `safe` only as far as needed to reach
  // `ratio` against `backdrop`, so the hue survives wherever it can.
  function contrastFloor(c, backdrop, safe, ratio) {
    function contrast(a, b) {
      var la = luminance(a), lb = luminance(b)
      return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    if (contrast(c, backdrop) >= ratio) return c
    for (var t = 1; t <= 10; t++) {
      var blended = mix(c, safe, t / 10)
      if (contrast(blended, backdrop) >= ratio) return blended
    }
    return safe
  }

  function duration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function resetText(w) {
    if (!w || !w.reset_at) return ""
    var ms = new Date(w.reset_at).getTime() - nowMs
    if (!isFinite(ms)) return ""
    return ms > 0 ? "Resets in " + duration(ms) : "Resets now"
  }

  function paceText(pace) {
    if (!pace) return ""
    var d = Number(pace.delta_points)
    if (!isFinite(d) || d === 0) return "→ on pace"
    return (d > 0 ? "↑ " : "↓ ") + String(pace.points_label || "")
  }

  function money(cents) {
    var n = Number(cents)
    return "$" + ((isFinite(n) ? n : 0) / 100).toFixed(2)
  }

  function updatedAt() {
    if (!doc || !doc.updated_at) return ""
    var t = new Date(doc.updated_at)
    return isNaN(t.getTime()) ? "" : Qt.formatTime(t, "HH:mm")
  }

  function footerText() {
    if (!hasData) return loading ? "󰅐  Waiting for first usage data…" : ""
    var at = updatedAt()
    if (at === "" && !stale) return ""
    return "󰅐  Updated " + (at !== "" ? at : "—")
  }

  function footerSuffix() {
    if (!hasData || !stale) return ""
    if (runFailed) return " · stale (refresh failed)"
    return " · stale (" + (doc.stale_reason === "network" ? "waiting for network" : "API errors") + ")"
  }

  function copyInstallCommand() {
    Quickshell.execDetached(["/bin/sh", "-c", 'printf %s "$1" | xclip -selection clipboard', "sh", installCmd])
  }
}
