import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Claude usage widget for the GNOME taskbar.
//
// This process owns the data and the card. The taskbar icon is a GNOME Shell
// extension (claude-usage@hiroshi) that draws the state written to
// $XDG_RUNTIME_DIR/claude-usage.json and calls the IPC below on click.
ShellRoot {
  id: shell

  Usage { id: usage }

  Popup {
    id: popup
    focusTarget: panel.keyTarget
    contentHeight: panel.contentHeight
    onCloseRequested: popup.open = false

    Panel {
      id: panel
      anchors.fill: parent
      usage: usage
      opened: popup.open
      onCloseRequested: popup.open = false
    }
  }

  function screenAt(x, y) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s
    }
    return screens[0]
  }

  IpcHandler {
    target: "claude-usage"

    // x: icon center; edge: taskbar edge facing the screen; both global.
    // size: taskbar height; position: "top" or "bottom".
    function toggleAt(x: int, edge: int, size: int, position: string): void {
      popup.barPosition = position === "top" ? "top" : "bottom"
      popup.barSize = size
      popup.anchorScreen = shell.screenAt(x, popup.barPosition === "top" ? edge - 1 : edge)
      popup.anchorX = x
      popup.edgeY = edge
      popup.open = !popup.open
    }
    function close(): void { popup.open = false }
    function refresh(): void { usage.refresh(true) }
  }

  // ---- state for the taskbar icon

  function hex(c) {
    function part(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + part(c.r) + part(c.g) + part(c.b)
  }

  readonly property string barState: JSON.stringify({
    label: usage.barLabel,
    color: hex(usage.barColor),
    stale: usage.barStale,
    staleColor: hex(Qt.darker(usage.barColor, 1.55)),
    alert: usage.criticalOthers.length > 0,
    alertColor: hex(usage.alertColor),
    tooltip: usage.barTooltip,
    open: popup.open,
    style: {
      fontFamily: Theme.fontFamily,
      background: hex(Theme.background),
      foreground: hex(Theme.foreground),
      radius: Theme.radius
    }
  })

  onBarStateChanged: Qt.callLater(function() { stateFile.setText(shell.barState) })

  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/claude-usage.json"
    printErrors: false
  }
}
