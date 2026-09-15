import QtQuick
import Quickshell
import qs

// The card that opens from the taskbar icon. A full-screen transparent dock
// window on the icon's screen holds the card and closes it on any click
// outside; the other screens get a transparent twin that does the same.
PanelWindow {
  id: root

  property bool open: false
  property Item focusTarget: null
  property int contentHeight: Theme.space(200)

  // Where the icon is, in global coordinates: its center along the taskbar,
  // the taskbar edge facing the screen, and which side the taskbar is on.
  property var anchorScreen: Quickshell.screens[0]
  property real anchorX: 0
  property real edgeY: 0
  property string barPosition: "bottom"
  property int barSize: 40

  signal closeRequested()

  default property alias content: holder.children

  screen: anchorScreen
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  focusable: true

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property int inset: Theme.padding + Theme.borderWidth
  readonly property int cardHeight: {
    var available = screen ? screen.height - barSize - Theme.gap * 2 : contentHeight
    return Math.round(Math.min(contentHeight + inset * 2, Theme.panelMaxHeight, available))
  }

  readonly property point cardOrigin: {
    if (!screen) return Qt.point(Theme.gap, Theme.gap)
    var x = anchorX - screen.x - Theme.panelWidth / 2
    var y = barPosition === "top" ? edgeY - screen.y + Theme.gap : edgeY - screen.y - cardHeight - Theme.gap
    x = Math.max(Theme.gap, Math.min(x, screen.width - Theme.panelWidth - Theme.gap))
    y = Math.max(Theme.gap, Math.min(y, screen.height - cardHeight - Theme.gap))
    return Qt.point(Math.round(x), Math.round(y))
  }

  // GNOME does not give keyboard focus to a dock window by itself.
  onOpenChanged: if (open) Qt.callLater(function() {
    if (!root.open) return
    if (card.Window.window) card.Window.window.requestActivate()
    if (root.focusTarget) root.focusTarget.forceActiveFocus()
  })

  MouseArea {
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    onPressed: root.closeRequested()
  }

  Variants {
    model: root.open ? Quickshell.screens : []

    PanelWindow {
      required property var modelData

      screen: modelData
      visible: root.open && !!root.screen && modelData.name !== root.screen.name
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      aboveWindows: true

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.closeRequested()
      }
    }
  }

  Rectangle {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: Theme.panelWidth
    height: root.cardHeight
    color: Theme.alpha(Theme.background, Theme.backgroundOpacity)
    border.color: Theme.border
    border.width: Theme.borderWidth
    radius: Theme.radius
    opacity: root.open ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Swallow clicks on the card so they do not reach the dismiss area.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: holder
      anchors.fill: parent
      anchors.margins: root.inset
    }
  }
}
