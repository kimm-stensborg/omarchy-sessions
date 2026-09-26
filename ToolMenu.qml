import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The tool pill's list, dropped under the pill: all tools, then each tool
// that has sessions. Driven like the dialogs: the panel hands its keys to
// handleKey() while this is open.
//
//   ↑ / ↓   move      Enter   show that tool      Esc   cancel
Item {
  id: root

  property bool opened: false
  property var items: []
  property int selectedIndex: 0
  property real menuX: 0
  property real menuY: 0
  property var themeColors: ({})
  property color background: Color.background
  property color foreground: Color.foreground
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.space(10))

  signal picked(string id)
  signal canceled()

  function show(items, current, x, y) {
    root.items = items || []
    root.selectedIndex = 0
    for (var i = 0; i < root.items.length; i++) {
      if (root.items[i].id === current) root.selectedIndex = i
    }
    root.menuX = x
    root.menuY = y
    root.opened = true
  }

  function handleKey(event) {
    if (!root.opened) return false
    var count = root.items.length
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.canceled()
    } else if (event.key === Qt.Key_Up) {
      root.selectedIndex = Math.max(0, root.selectedIndex - 1)
    } else if (event.key === Qt.Key_Down) {
      root.selectedIndex = Math.min(count - 1, root.selectedIndex + 1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (count) root.picked(root.items[root.selectedIndex].id)
    }
    return true
  }

  visible: opened

  MouseArea { anchors.fill: parent; onClicked: root.canceled() }

  BorderSurface {
    id: menu
    x: root.menuX
    y: root.menuY
    width: Style.space(170)
    height: menu.contentTopInset + menu.contentBottomInset + list.implicitHeight
    color: root.background
    borderSpec: Border.flat(Util.alpha(root.accent, 0.55), Style.normalBorderWidth)
    padding: Style.space(4)
    radius: root.cornerRadius

    Column {
      id: list
      anchors.fill: parent
      anchors.topMargin: menu.contentTopInset
      anchors.rightMargin: menu.contentRightInset
      anchors.bottomMargin: menu.contentBottomInset
      anchors.leftMargin: menu.contentLeftInset

      Repeater {
        model: root.items

        Rectangle {
          id: item
          required property int index
          required property var modelData
          readonly property bool selected: root.selectedIndex === index

          width: list.width
          height: root.rowHeight
          radius: root.cornerRadius
          color: item.selected ? root.selectedBackground : "transparent"

          Rectangle {
            id: mark
            visible: item.modelData.id !== ""
            width: Style.space(6)
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
            color: Model.toolColor(item.modelData.id, root.themeColors, root.accent)
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(9) + (mark.visible ? mark.width + Style.space(7) : 0)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: item.modelData.label
            color: item.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = item.index
            onClicked: root.picked(item.modelData.id)
          }
        }
      }
    }
  }
}
