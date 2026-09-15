import QtQuick
import qs

// The card surface: background, border, padding, and a height that fits its
// content up to `maxHeight`. Clicks on it stop here.
Rectangle {
  id: root

  property real contentHeight: Theme.space(200)
  property real maxHeight: Theme.panelMaxHeight

  readonly property int inset: Theme.padding + Theme.borderWidth

  default property alias content: holder.children

  width: Theme.panelWidth
  height: Math.round(Math.min(contentHeight + inset * 2, maxHeight))
  color: Theme.alpha(Theme.background, Theme.backgroundOpacity)
  border.color: Theme.border
  border.width: Theme.borderWidth
  radius: Theme.radius

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
