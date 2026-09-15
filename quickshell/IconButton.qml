import QtQuick
import QtQuick.Controls
import qs

// Small square glyph button with a hover tint and a tooltip.
Rectangle {
  id: root

  property string icon: ""
  property string tooltip: ""
  property color foreground: Theme.dim
  property color hoverColor: Theme.foreground
  property int size: Theme.space(20)

  signal clicked()

  readonly property bool hot: mouse.containsMouse && enabled

  implicitWidth: size
  implicitHeight: size
  radius: Theme.radius
  color: hot ? Theme.alpha(hoverColor, 0.08) : "transparent"

  Behavior on color { ColorAnimation { duration: 60 } }

  Text {
    anchors.centerIn: parent
    text: root.icon
    textFormat: Text.PlainText
    color: root.enabled ? (root.hot ? root.hoverColor : root.foreground) : Qt.darker(root.foreground, 2.0)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  ToolTip {
    id: tip
    visible: root.tooltip !== "" && mouse.containsMouse
    delay: 400
    padding: 0

    background: Rectangle {
      color: Theme.background
      border.color: Theme.foreground
      border.width: 1
      radius: Theme.radius
    }

    contentItem: Text {
      text: root.tooltip
      textFormat: Text.PlainText
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.small
      leftPadding: 1 + Theme.space(10)
      rightPadding: 1 + Theme.space(10)
      topPadding: 1 + Theme.space(6)
      bottomPadding: 1 + Theme.space(6)
    }
  }
}
