import QtQuick
import qs.Commons
import qs.Ui

// F2: name a session. Built like the shell's ConfirmDialog, with a text
// field in place of the message. Enter saves, Esc cancels; saving an empty
// name takes the name away, and the session shows its own title again.
Item {
  id: root

  property bool opened: false
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  signal saved(string title)
  signal canceled()

  function show(title) {
    field.text = title
    root.opened = true
    Qt.callLater(function() {
      field.forceActiveFocus()
      field.selectAll()
    })
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(460))
      height: card.contentTopInset + card.contentBottomInset + heading.implicitHeight
        + Style.space(12) + field.implicitHeight + Style.space(12) + hint.implicitHeight
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
        spacing: Style.space(12)

        Text {
          id: heading
          textFormat: Text.PlainText
          text: "Name this session"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        TextField {
          id: field
          width: parent.width
          foreground: root.foreground
          accent: root.selectedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          onAccepted: root.saved(field.text)
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            root.canceled()
          }
        }

        Text {
          id: hint
          textFormat: Text.PlainText
          text: "enter saves    esc cancels    empty gives it back its own title"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
