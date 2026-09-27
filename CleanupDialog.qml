import QtQuick
import qs.Commons
import qs.Ui

// Ctrl+D: clean up by a rule. Each rule says how many of the sessions the
// list shows it matches; picking one marks them, so they can be looked over
// in the list before Del deletes them. Running and pinned sessions are never
// matched. Driven like the other dialogs: the panel hands its keys to
// handleKey() while this is open.
//
//   ↑ / ↓   move      Enter   mark them      Esc   cancel
Item {
  id: root

  property bool opened: false
  property var rules: []
  property int selectedIndex: 0
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  readonly property int rowHeight: Math.max(Style.space(32), Style.font.body + Style.space(16))

  signal picked(var ids)
  signal canceled()

  function show(rules) {
    root.rules = rules || []
    root.selectedIndex = 0
    root.opened = true
  }

  function handleKey(event) {
    if (!root.opened) return false
    var count = root.rules.length
    if (event.key === Qt.Key_Escape) {
      root.canceled()
    } else if (event.key === Qt.Key_Up) {
      root.selectedIndex = Math.max(0, root.selectedIndex - 1)
    } else if (event.key === Qt.Key_Down) {
      root.selectedIndex = Math.min(count - 1, root.selectedIndex + 1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var rule = root.rules[root.selectedIndex]
      if (rule && rule.ids.length) root.picked(rule.ids)
    }
    return true
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(440))
      height: card.contentTopInset + card.contentBottomInset + content.implicitHeight
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          text: "Clean up: mark the sessions"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Column {
          width: parent.width

          Repeater {
            model: root.rules

            Rectangle {
              id: line
              required property int index
              required property var modelData
              readonly property bool selected: root.selectedIndex === index
              readonly property bool empty: modelData.ids.length === 0

              width: parent.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: line.selected ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: line.modelData.label
                color: line.selected && !line.empty ? root.selectedText : root.foreground
                opacity: line.empty ? 0.4 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(line.modelData.ids.length)
                color: root.foreground
                opacity: line.empty ? 0.3 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: line.empty ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: root.selectedIndex = line.index
                onClicked: if (!line.empty) root.picked(line.modelData.ids)
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Of what the list shows; running and pinned sessions are left alone. Enter marks them, then Del deletes the marked after asking."
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
