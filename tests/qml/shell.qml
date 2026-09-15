import QtQuick
import Quickshell
import qs

// Test harness for the widget logic, run headless by tests/test_widget.sh next
// to the real Theme.qml, Usage.qml, Panel.qml and IconButton.qml.
//
// It waits for the first fetch, forces a second one (which may read a second
// fixture), then prints one line, RESULT <json>, with everything the tests
// check, and quits.
ShellRoot {
  id: root

  Usage { id: usage }

  // Columns only lay out inside a window, so the panel gets an offscreen one.
  FloatingWindow {
    visible: true
    implicitWidth: Theme.panelWidth
    implicitHeight: Theme.panelMaxHeight

    Panel {
      id: panel
      anchors.fill: parent
      usage: usage
    }
  }

  property int phase: 0
  property int ticks: 0

  function done() { return !usage.busy && (usage.hasData || usage.loading || usage.loadError !== "") }

  function hex(c) {
    function part(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + part(c.r) + part(c.g) + part(c.b)
  }

  function contrast(a, b) {
    var la = usage.luminance(a), lb = usage.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function report(timedOut) {
    var gauge = {}
    var points = [0, 10, 50, 75, 90, 100]
    for (var i = 0; i < points.length; i++) gauge[points[i]] = hex(usage.usageColor(points[i]))

    console.log("RESULT " + JSON.stringify({
      timedOut: timedOut,
      hasData: usage.hasData,
      loading: usage.loading,
      loadError: usage.loadError,
      notInstalled: usage.notInstalled,
      plan: usage.plan,
      titles: usage.windows.map(function(e) { return e.title }),
      barLabel: usage.barLabel,
      barColor: hex(usage.barColor),
      barContrast: contrast(usage.barColor, Theme.background),
      barStale: usage.barStale,
      criticalOthers: usage.criticalOthers.length,
      alertColor: hex(usage.alertColor),
      barTooltip: usage.barTooltip,
      extraSpent: usage.extraSpent,
      extraCredit: usage.extraCredit,
      apiStatus: usage.apiError ? usage.apiError.http_status : null,
      footerText: usage.footerText(),
      footerSuffix: usage.footerSuffix(),
      gauge: gauge,
      panelColor50: hex(usage.panelColor(50)),
      paceHot: hex(usage.paceColor("hot")),
      paceAhead: usage.paceText({ delta_points: 19, points_label: "19pts ahead" }),
      paceUnder: usage.paceText({ delta_points: -5, points_label: "5pts under" }),
      paceOn: usage.paceText({ delta_points: 0, points_label: "" }),
      durations: [usage.duration(0), usage.duration(90 * 1000), usage.duration(185 * 60 * 1000), usage.duration(51 * 3600 * 1000)],
      resetPast: usage.resetText({ reset_at: "2000-01-01T00:00:00Z" }),
      money: usage.money(3750),
      theme: {
        refreshSec: Theme.refreshSec, barWindow: Theme.barWindow, showLabel: Theme.showLabel,
        colorMode: Theme.colorMode, panelWidth: Theme.panelWidth, caption: Theme.caption,
        radius: Theme.radius, borderWidth: Theme.borderWidth, background: hex(Theme.background)
      },
      panelHeight: panel.contentHeight
    }))
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160) { stop(); root.report(true); quitTimer.start(); return }
      if (!root.done()) return
      if (root.phase === 0) {
        root.phase = 1
        usage.refresh(true)
      } else if (root.phase === 1 && !usage.busy) {
        stop()
        root.report(false)
        quitTimer.start()
      }
    }
  }

  // Qt.quit() is ignored until the event loop runs, so quit from a timer.
  Timer { id: quitTimer; interval: 10; onTriggered: Qt.quit() }
}
