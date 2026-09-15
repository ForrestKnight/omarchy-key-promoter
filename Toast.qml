import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Promoter.js" as Promoter

// The card itself. Colors, font, radius and border all come from the shell's
// theme singletons, so it follows `omarchy theme set` like every other surface.
Item {
  id: root

  property var shell: null
  property int duration: 3500
  // top-left | top-center | top-right | bottom-left | bottom-center | bottom-right
  property string position: "bottom-right"
  property bool showCount: true

  property bool opened: false
  property var chips: []
  property string description: ""
  property int count: 0

  readonly property string vertical: position.indexOf("top") === 0 ? "top" : "bottom"
  readonly property string horizontal: position.indexOf("-left") > 0 ? "left" : (position.indexOf("-right") > 0 ? "right" : "center")

  readonly property string barPosition: shell && shell.barConfig ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVisible: shell && shell.bar ? !shell.bar.barHidden : true
  readonly property int barSize: shell && shell.bar && barVisible ? Math.max(0, shell.bar.barSize) : Style.bar.sizeHorizontal
  // Clear the bar only on the edge the toast shares with it.
  function margin(edge) { return Style.space(12) + (barPosition === edge && barVisible ? barSize + Style.gapsOut : 0) }
  readonly property int edgeMargin: margin(vertical)
  readonly property int sideMargin: margin(horizontal)

  readonly property int pad: Style.space(12)
  readonly property int slide: Style.space(8)

  function show(combo, text, times) {
    chips = Promoter.chips(combo)
    description = String(text || "")
    count = times || 0
    opened = true
    hideTimer.restart()
  }

  function hide() { opened = false; hideTimer.stop() }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  PanelWindow {
    id: panel
    // Stay mounted while the fade-out finishes.
    visible: root.opened || card.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "key-promoter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual only: never take clicks away from the desktop.
    mask: Region {}

    BorderSurface {
      id: card
      x: root.horizontal === "left" ? root.sideMargin
        : root.horizontal === "right" ? panel.width - card.width - root.sideMargin
        : Math.round((panel.width - card.width) / 2)
      y: root.vertical === "bottom"
        ? panel.height - card.height - root.edgeMargin + (root.opened ? 0 : root.slide)
        : root.edgeMargin - (root.opened ? 0 : root.slide)
      width: card.borderLeft + root.pad + row.implicitWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + row.implicitHeight + root.pad + card.borderBottom
      color: Util.alpha(Color.popups.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      Row {
        id: row
        x: card.borderLeft + root.pad
        y: card.borderTop + root.pad
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰌌"
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge * 0.75
          color: Color.accent
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          Repeater {
            model: root.chips
            delegate: Row {
              required property string modelData
              required property int index
              spacing: Style.space(4)
              Text {
                visible: index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Util.alpha(Color.popups.text, 0.5)
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: label.implicitWidth + Style.space(12)
                height: label.implicitHeight + Style.space(6)
                radius: Math.min(Style.cornerRadius, Style.space(4))
                color: Util.alpha(Color.accent, 0.12)
                border.width: 1
                border.color: Util.alpha(Color.accent, 0.6)
                Text {
                  id: label
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: modelData
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.popups.text
                }
              }
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.description
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
          width: Math.min(implicitWidth, Style.space(260))
        }

        Text {
          visible: root.showCount && root.count > 1
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "×" + root.count
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: Util.alpha(Color.popups.text, 0.5)
        }
      }
    }
  }
}
