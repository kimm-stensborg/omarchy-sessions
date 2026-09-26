import QtQuick
import qs.Commons
import qs.Ui

// → beside the list: the last few things said in the session in hand, from
// scan.py `peek`, newest at the bottom, so you know what it was before you
// go back into it.
Item {
  id: root

  property var messages: []
  // "loading", "ready" or "none".
  property string phase: "loading"
  property string agentLabel: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color accent: Color.accent


  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.normalBorderWidth
    color: Util.alpha(root.borderColor, 0.2)
  }

  Text {
    visible: root.phase !== "ready" || root.messages.length === 0
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.phase === "loading" ? "…" : "Nothing said yet"
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: Style.space(16)
    contentHeight: said.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: root.phase === "ready"
    // Newest at the bottom, in view.
    onContentHeightChanged: flick.contentY = Math.max(0, flick.contentHeight - flick.height)

    Column {
      id: said
      width: flick.width
      spacing: Style.space(12)

      Repeater {
        model: root.messages

        Column {
          required property var modelData
          width: said.width
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            text: modelData.role === "user" ? "You" : root.agentLabel
            color: modelData.role === "user" ? root.accent : root.foreground
            opacity: modelData.role === "user" ? 0.9 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: modelData.text
            color: root.foreground
            opacity: modelData.role === "user" ? 0.95 : 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.15
          }
        }
      }
    }
  }
}
