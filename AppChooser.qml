import QtQuick
import qs.Commons
import qs.Ui

// Where a session should open, asked with Shift+Enter: one button per
// installed app, the session's own (or the default) picked to start with.
// Built like the shell's ConfirmDialog, and driven the same way: the panel
// hands its keys to handleKey() while this is open.
//
//   ← / → / Tab   move      Enter   open there
//   d             make it the default      Esc   cancel
Item {
  id: root

  property bool opened: false
  property string title: ""
  property var choices: []
  property string defaultId: ""
  property int selectedIndex: 0
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  signal picked(string id)
  signal madeDefault(string id)
  signal canceled()

  function show(choices, current) {
    root.choices = choices
    root.selectedIndex = 0
    for (var i = 0; i < choices.length; i++) {
      if (choices[i].id === current) root.selectedIndex = i
    }
    root.opened = true
  }

  function handleKey(event) {
    if (!root.opened) return false
    var count = root.choices.length
    if (event.key === Qt.Key_Escape) {
      root.canceled()
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
               || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
      root.selectedIndex = (root.selectedIndex + 1) % count
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (count) root.picked(root.choices[root.selectedIndex].id)
    } else if (event.text === "d" && count) {
      root.madeDefault(root.choices[root.selectedIndex].id)
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
      width: Math.min(parent.width - Style.space(32), Style.space(420))
      height: card.contentTopInset + card.contentBottomInset + titleText.implicitHeight
        + Style.space(16) + Style.space(44) + Style.space(12) + hint.implicitHeight
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(14)

        Text {
          id: titleText
          width: parent.width
          textFormat: Text.PlainText
          text: "Open “" + root.title + "” in"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        Row {
          id: buttons
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.choices

            BorderSurface {
              required property int index
              required property var modelData
              readonly property bool selected: root.selectedIndex === index

              width: (buttons.width - buttons.spacing * (root.choices.length - 1)) / Math.max(1, root.choices.length)
              height: Style.space(44)
              color: selected ? root.selectedBackground : "transparent"
              borderSpec: Border.flat(selected ? root.selectedText : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
              radius: 0

              Column {
                anchors.centerIn: parent
                spacing: Style.space(1)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: selected ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: modelData.id === root.defaultId
                  textFormat: Text.PlainText
                  text: "default"
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: root.picked(modelData.id)
              }
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          textFormat: Text.PlainText
          text: "enter opens    d makes it the default    esc cancels"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
