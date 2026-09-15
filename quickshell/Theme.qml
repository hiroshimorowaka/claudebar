pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every setting of the widget, read from $XDG_CONFIG_HOME/claude-usage/config.json
// and reloaded live when the file changes. Missing keys fall back to the
// defaults below, so a missing, empty or broken config still draws the widget.
QtObject {
  id: root

  property var config: ({})

  function pick(path, fallback) {
    var node = config
    var keys = path.split(".")
    for (var i = 0; i < keys.length; i++) {
      if (node === null || typeof node !== "object" || !(keys[i] in node)) return fallback
      node = node[keys[i]]
    }
    return node === null || node === undefined ? fallback : node
  }

  // ---- behavior
  readonly property int refreshSec: Math.max(60, Number(pick("refreshIntervalSec", 300)) || 300)
  readonly property string barWindow: pick("barWindow", "session") === "weekly" ? "weekly" : "session"
  readonly property bool showLabel: pick("showLabel", true) === true
  readonly property string colorMode: {
    var mode = String(pick("colors", "full"))
    return ["full", "none", "bar-only", "panel-only"].indexOf(mode) >= 0 ? mode : "full"
  }
  readonly property bool barColored: colorMode === "full" || colorMode === "bar-only"
  readonly property bool panelColored: colorMode === "full" || colorMode === "panel-only"

  // ---- colors
  readonly property color background: pick("style.background", "#101315")
  readonly property real backgroundOpacity: Math.max(0, Math.min(1, Number(pick("style.backgroundOpacity", 1))))
  readonly property color foreground: pick("style.foreground", "#cacccc")
  readonly property color border: pick("style.border", "#cacccc")
  readonly property color urgent: pick("style.urgent", "#a55555")
  readonly property color brand: pick("style.brand", "#d97757")
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color subtle: Qt.darker(foreground, 1.4)

  readonly property var gauge: ({
    low: pick("gauge.low", "#98c379"),
    mid: pick("gauge.mid", "#e5c07b"),
    high: pick("gauge.high", "#d19a66"),
    critical: pick("gauge.critical", "#e06c75")
  })

  // ---- geometry: sizes are written for a 12px font and scale with fontSize
  readonly property string fontFamily: pick("style.fontFamily", "JetBrainsMono Nerd Font")
  readonly property int fontSize: Math.max(6, Number(pick("style.fontSize", 12)) || 12)
  readonly property real scale: fontSize / 12
  readonly property int radius: Math.max(0, Number(pick("style.radius", 0)) || 0)
  readonly property int borderWidth: Math.max(0, Math.round(Number(pick("style.borderWidth", 2))))
  readonly property int padding: space(Number(pick("style.padding", 14)) || 14)
  readonly property int gap: space(Number(pick("style.gap", 5)) || 5)
  readonly property int panelWidth: space(Number(pick("style.width", 340)) || 340)
  readonly property int panelMaxHeight: space(620)

  function space(px) { return px <= 0 ? 0 : Math.max(1, Math.round(px * scale)) }
  function spaceReal(px) { return px * scale }

  readonly property int caption: Math.round(fontSize * 0.833)
  readonly property int small: Math.round(fontSize * 0.917)
  readonly property int body: fontSize
  readonly property int title: Math.round(fontSize * 1.167)
  readonly property int display: fontSize * 2

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  property FileView file: FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/claude-usage/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text()) } catch (e) { root.config = {} }
    }
    onLoadFailed: root.config = {}
  }
}
