import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Ctrl+?: every key the panel knows, in groups, so the foot of the panel
// only needs the few for what is in hand. Any key closes it again.
Item {
  id: root

  property bool opened: false
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  signal closed()

  function handleKey(event) {
    if (!root.opened) return false
    // Shift and Ctrl alone are how Ctrl+? is reached; they don't close it.
    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control) return true
    root.closed()
    return true
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.closed() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(820))
      height: card.contentTopInset + card.contentBottomInset + content.implicitHeight
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(20)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: root.closed() }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(16)

        Text {
          textFormat: Text.PlainText
          text: "Shortcuts"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Grid {
          id: groups
          width: parent.width
          columns: 2
          columnSpacing: Style.space(28)
          rowSpacing: Style.space(18)

          Repeater {
            model: Model.SHORTCUTS

            Column {
              required property var modelData
              width: (groups.width - groups.columnSpacing) / 2
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: modelData.group.toUpperCase()
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Repeater {
                model: modelData.keys

                Row {
                  id: line
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(12)

                  Text {
                    width: Style.space(96)
                    textFormat: Text.PlainText
                    text: modelData[0]
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    width: line.width - Style.space(96) - line.spacing
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: modelData[1]
                    color: root.foreground
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: "any key closes"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
