import QtQuick
import Quickshell
import qs

// Renders the real card and panel offscreen for screenshots/generate.sh. Waits
// for the first fetch, lets the layout settle, saves the card to $SHOT and quits.
ShellRoot {
  id: root

  Usage { id: usage }

  FloatingWindow {
    visible: true
    color: "transparent"
    implicitWidth: Theme.panelWidth
    implicitHeight: Theme.panelMaxHeight

    Card {
      id: card
      contentHeight: panel.contentHeight

      Panel {
        id: panel
        anchors.fill: parent
        usage: usage
      }
    }
  }

  property int ticks: 0
  property int settled: 0

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 400) { console.log("SHOT timed out"); Qt.quit() }
      var done = !usage.busy && (usage.hasData || usage.loading || usage.loadError !== "")
      root.settled = done ? root.settled + 1 : 0
      if (root.settled < 6) return
      stop()
      card.grabToImage(function(result) {
        console.log("SHOT " + (result.saveToFile(Quickshell.env("SHOT")) ? "saved" : "failed"))
        quitTimer.start()
      })
    }
  }

  // Qt.quit() is ignored until the event loop runs, so quit from a timer.
  Timer { id: quitTimer; interval: 10; onTriggered: Qt.quit() }
}
