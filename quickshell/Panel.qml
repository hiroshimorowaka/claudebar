pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs

// Content of the card: the Claude header, one section per usage window with
// an animated meter, the extra usage, errors, and the freshness footer.
// Keys: r / Enter / Space refresh, Esc closes, Up / Down / j / k scroll.
Item {
  id: root

  required property Usage usage
  property bool opened: false

  signal closeRequested()

  readonly property Item keyTarget: keys
  readonly property real contentHeight: column.implicitHeight

  // Every open sweeps the meters from zero to their value. Refreshes while
  // open ease over 160ms instead, so the sweep gates those animations.
  property real openProgress: 1
  property bool sweeping: false

  NumberAnimation {
    id: sweep
    target: root
    property: "openProgress"
    from: 0
    to: 1
    duration: 200
    easing.type: Easing.OutCubic
    onFinished: root.sweeping = false
  }

  onOpenedChanged: if (opened) {
    usage.nowMs = Date.now()
    flick.contentY = 0
    sweeping = true
    sweep.restart()
    usage.refresh(false)
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.usage.nowMs = Date.now()
  }

  property bool copied: false
  Timer { id: copiedReset; interval: 1500; onTriggered: root.copied = false }

  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) root.closeRequested()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
               || event.text === "r" || event.text === "R") root.usage.refresh(true)
      else if (event.key === Qt.Key_Down || event.text === "j") scroll(1)
      else if (event.key === Qt.Key_Up || event.text === "k") scroll(-1)
      else return
      event.accepted = true
    }

    function scroll(direction) {
      flick.contentY = root.usage.clamp(flick.contentY + direction * Theme.space(56), 0,
                                        Math.max(0, flick.contentHeight - flick.height))
    }

    Flickable {
      id: flick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
        spacing: Theme.space(12)

        // ---------- header: Claude glyph, plan
        Item {
          width: parent.width
          implicitHeight: Math.max(glyph.implicitHeight, labels.implicitHeight)

          Text {
            id: glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            textFormat: Text.PlainText
            color: Theme.panelColored ? root.usage.contrastFloor(Theme.brand, Theme.background, Theme.foreground, 3.0) : Theme.foreground
            font.family: "Font Awesome 7 Brands"
            font.pixelSize: Theme.display
          }

          Column {
            id: labels
            anchors.left: glyph.right
            anchors.leftMargin: Theme.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space(2)

            Text {
              text: "Claude"
              textFormat: Text.PlainText
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: (root.usage.hasData ? root.usage.plan : (root.usage.loading ? "Loading" : "")).toUpperCase()
              visible: text !== ""
              textFormat: Text.PlainText
              color: Theme.subtle
              font.family: Theme.fontFamily
              font.pixelSize: Theme.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        // ---------- nothing yet, or a hard failure with nothing to show
        Text {
          visible: !root.usage.hasData && root.usage.loadError === ""
          width: parent.width
          topPadding: Theme.space(16)
          text: "No usage data yet.\nLog in with the claude CLI and refresh."
          textFormat: Text.PlainText
          color: Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Rectangle {
          visible: !root.usage.hasData && root.usage.loadError !== ""
          width: parent.width
          implicitHeight: errorText.implicitHeight + Theme.space(10) * 2
          readonly property color tone: Theme.panelColored ? Theme.urgent : Theme.foreground
          color: Theme.alpha(tone, 0.10)
          border.color: Theme.alpha(tone, 0.35)
          border.width: 1
          radius: Theme.radius

          Text {
            id: errorText
            anchors.left: parent.left
            anchors.right: copyButton.visible ? copyButton.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space(12)
            anchors.rightMargin: Theme.space(12)
            text: root.usage.loadError
            textFormat: Text.PlainText
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.caption
            wrapMode: Text.WrapAnywhere
          }

          IconButton {
            id: copyButton
            visible: root.usage.notInstalled
            anchors.right: parent.right
            anchors.rightMargin: Theme.space(8)
            anchors.verticalCenter: parent.verticalCenter
            icon: root.copied ? "󰄬" : "󰆏"
            tooltip: root.copied ? "Copied" : "Copy install command"
            onClicked: {
              root.usage.copyInstallCommand()
              root.copied = true
              copiedReset.restart()
            }
          }
        }

        // ---------- usage windows
        Separator { visible: root.usage.windows.length > 0 }

        Column {
          visible: root.usage.windows.length > 0
          width: parent.width
          spacing: Theme.space(10)

          Header { text: "USAGE" }

          Repeater {
            model: root.usage.windows

            WindowSection {
              required property var modelData
              width: parent.width
              entry: modelData
            }
          }
        }

        // ---------- extra usage
        Separator { visible: !!root.usage.extra }

        Column {
          id: extraSection
          visible: !!root.usage.extra
          width: parent.width
          spacing: Theme.space(6)

          readonly property bool balanceKnown: !!root.usage.extra && root.usage.extra.balance_known === true

          Header { text: "EXTRA USAGE" }

          Item {
            width: parent.width
            implicitHeight: Math.max(spentLabel.implicitHeight, extraPct.implicitHeight)

            Text {
              id: spentLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.usage.extraSpent
              textFormat: Text.PlainText
              color: Theme.dim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.caption
            }

            Text {
              id: extraPct
              visible: extraSection.balanceKnown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(extraMeter.shownPct) + "%"
              textFormat: Text.PlainText
              color: root.usage.panelColor(extraMeter.shownPct)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.body
              font.bold: true
            }
          }

          Meter {
            id: extraMeter
            visible: extraSection.balanceKnown
            width: parent.width
            pct: root.usage.extra ? Number(root.usage.extra.used_pct || 0) : 0
          }

          Text {
            width: parent.width
            text: root.usage.extraCredit
            textFormat: Text.PlainText
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.caption
            elide: Text.ElideRight
          }
        }

        // ---------- API error behind data that is still usable
        Separator { visible: apiErrorText.visible }

        Text {
          id: apiErrorText
          visible: !!root.usage.apiError || (root.usage.hasData && root.usage.loadError !== "")
          width: parent.width
          text: {
            var e = root.usage.apiError
            if (!e) return root.usage.hasData ? root.usage.loadError : ""
            var head = e.http_status !== undefined ? "HTTP " + e.http_status : ""
            var msg = String(e.message || "")
            return head === "" ? msg : (msg !== "" ? head + " — " + msg : head)
          }
          textFormat: Text.PlainText
          // 5xx is the server failing and gets full urgent; 4xx a softer tone.
          color: {
            var e = root.usage.apiError
            if (!Theme.panelColored) return e && Number(e.http_status) >= 500 ? Theme.foreground : Theme.dim
            return e && Number(e.http_status) >= 500 ? Theme.urgent : root.usage.mix(Theme.dim, Theme.urgent, 0.5)
          }
          font.family: Theme.fontFamily
          font.pixelSize: Theme.caption
          wrapMode: Text.WordWrap
        }

        // ---------- freshness footer and refresh
        Separator {}

        Item {
          width: parent.width
          implicitHeight: Math.max(footer.implicitHeight, refreshButton.implicitHeight)

          Row {
            id: footer
            anchors.left: parent.left
            anchors.right: refreshButton.left
            anchors.rightMargin: Theme.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: root.usage.footerText()
              textFormat: Text.PlainText
              color: Theme.dim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.caption
            }

            Text {
              visible: text !== ""
              text: root.usage.footerSuffix()
              textFormat: Text.PlainText
              color: Theme.panelColored ? root.usage.mix(Theme.dim, Theme.urgent, 0.4) : Theme.dim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.caption
            }
          }

          IconButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰑐"
            tooltip: "Refresh now"
            enabled: !root.usage.busy
            onClicked: root.usage.refresh(true)
          }
        }
      }
    }
  }

  component Separator: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: Theme.alpha(Theme.foreground, 0.12)
  }

  component Header: Text {
    textFormat: Text.PlainText
    color: Theme.subtle
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
    font.bold: true
    topPadding: Math.ceil(Theme.caption * 0.15)
  }

  // Name and percent, meter with the pace marker, reset countdown and pace.
  component WindowSection: Column {
    id: section
    property var entry: null

    readonly property var w: entry ? entry.w : null
    readonly property var pace: w ? (w.pace || null) : null

    spacing: Theme.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(nameLabel.implicitHeight, pctLabel.implicitHeight)

      Text {
        id: nameLabel
        anchors.left: parent.left
        anchors.right: pctLabel.left
        anchors.rightMargin: Theme.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: section.entry ? section.entry.title : ""
        textFormat: Text.PlainText
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        elide: Text.ElideRight
      }

      // Reads the meter's animated value, so the figure counts up with the
      // bar and carries the tone of the meter's tip.
      Text {
        id: pctLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(meter.shownPct) + "%"
        textFormat: Text.PlainText
        color: root.usage.panelColor(meter.shownPct)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
      }
    }

    Meter {
      id: meter
      width: parent.width
      pct: section.w ? Math.round(Number(section.w.used_pct || 0)) : 0
      markerAt: section.w && section.w.reset_at ? Math.round(Number(section.w.elapsed_pct || 0)) / 100 : -1
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(resetLabel.implicitHeight, paceLabel.implicitHeight)

      Text {
        id: resetLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.usage.resetText(section.w)
        textFormat: Text.PlainText
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
      }

      Text {
        id: paceLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.usage.paceText(section.pace)
        textFormat: Text.PlainText
        color: root.usage.paceColor(section.pace ? String(section.pace.state || "") : "")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
      }
    }
  }

  // Rounded track with a fill that paints the gauge as a scale: the gradient
  // anchors are rescaled to the painted width, so the tip is always the color
  // of the value it reaches. The pace marker rides above the track.
  component Meter: Item {
    id: meter
    property real pct: 0
    property real markerAt: -1

    readonly property real shownPct: track.width > 0 ? fill.width / track.width * 100 : 0

    function anchorAt(i) {
      var s = root.usage.stops
      return i < s.length ? s[i].pct : 100
    }
    function stopAt(i) { return shownPct > 0 ? Math.min(1, anchorAt(i) / shownPct) : 0 }
    function colorAt(i) { return root.usage.panelColor(Math.min(anchorAt(i), shownPct)) }

    implicitHeight: Theme.space(14)

    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Theme.space(4), Math.round(Theme.space(28) * 0.14))
      radius: height / 2
      color: Theme.alpha(Theme.foreground, 0.18)
    }

    Rectangle {
      id: fill
      anchors.left: track.left
      anchors.verticalCenter: track.verticalCenter
      height: track.height
      radius: track.radius
      width: track.width * root.usage.clamp(meter.pct, 0, 100) / 100 * root.openProgress

      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: meter.stopAt(0); color: meter.colorAt(0) }
        GradientStop { position: meter.stopAt(1); color: meter.colorAt(1) }
        GradientStop { position: meter.stopAt(2); color: meter.colorAt(2) }
        GradientStop { position: meter.stopAt(3); color: meter.colorAt(3) }
        GradientStop { position: meter.stopAt(4); color: meter.colorAt(4) }
        GradientStop { position: meter.stopAt(5); color: meter.colorAt(5) }
      }

      Behavior on width {
        enabled: !root.sweeping
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      visible: meter.markerAt >= 0
      width: Math.max(2, Theme.spaceReal(2))
      height: Math.max(3, Theme.spaceReal(4))
      anchors.bottom: track.top
      anchors.bottomMargin: Math.max(1, Theme.spaceReal(1))
      x: root.usage.clamp(track.width * root.usage.clamp(meter.markerAt, 0, 1) * root.openProgress - width / 2,
                          0, Math.max(0, track.width - width))
      color: Theme.alpha(Theme.foreground, 0.75)

      Behavior on x {
        enabled: !root.sweeping
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
