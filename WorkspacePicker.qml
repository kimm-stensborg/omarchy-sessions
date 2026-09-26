import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A workspace to work in, picked from every folder a session was held in,
// newest first. Typing narrows the list, as the search line does sessions.
// Two uses, driven like AppChooser: the panel hands its keys to handleKey()
// while this is open.
//
//   "new"     Ctrl+Enter: a tool and a workspace for a new session
//             ← / → / Tab   tool     ↑ / ↓   workspace     Enter   start
//             A name or path that isn't listed is offered last, as a new
//             workspace: the folder is made when the session starts.
//   "filter"  Ctrl+W: the one workspace the list shows, or all of them
//             ↑ / ↓   workspace     Enter   show it
//
//   Esc clears what was typed, then cancels.
Item {
  id: root

  property bool opened: false
  property string mode: "new"
  property var places: []
  property var tools: []
  property int toolIndex: 0
  property string query: ""
  property int selectedIndex: 0
  property var themeColors: ({})
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  readonly property int visibleRows: 7
  readonly property int rowHeight: Math.max(Style.space(30), Style.font.body + Style.space(14))
  property string home: ""
  // "All workspaces" heads the list when filtering and nothing is typed;
  // a new workspace named by what was typed ends it when starting one.
  readonly property var shown: {
    var list = Model.filterWorkspaces(root.places, root.query)
    if (root.mode === "filter" && !root.query.trim())
      list = [{ cwd: "", label: "All workspaces", path: "", tools: [] }].concat(list)
    if (root.mode === "new") {
      var fresh = Model.newWorkspace(root.query, root.places, root.home)
      if (fresh) list = list.concat([fresh])
    }
    return list
  }

  signal started(string tool, string cwd, bool create)
  signal chose(string cwd)
  signal canceled()

  function show(mode, places, cwd, tools, tool) {
    root.mode = mode
    root.places = places || []
    root.tools = tools || []
    root.query = ""
    root.toolIndex = 0
    for (var t = 0; t < root.tools.length; t++) {
      if (root.tools[t].id === tool) root.toolIndex = t
    }
    root.selectedIndex = Math.max(0, Model.workspaceIndex(root.shown, cwd || ""))
    root.opened = true
    Qt.callLater(function() { list.positionViewAtIndex(root.selectedIndex, ListView.Center) })
  }

  // The workspace in hand stays picked while the list narrows round it.
  function setQuery(text) {
    var was = root.shown[root.selectedIndex]
    root.query = text
    var at = was ? Model.workspaceIndex(root.shown, was.cwd) : -1
    root.selectedIndex = Math.max(0, at)
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function moveTo(index) {
    if (!root.shown.length) return
    root.selectedIndex = Math.max(0, Math.min(root.shown.length - 1, index))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function accept() {
    var place = root.shown[root.selectedIndex]
    if (!place) return
    if (root.mode === "filter") {
      root.chose(place.cwd)
    } else if (root.tools.length) {
      root.started(root.tools[root.toolIndex].id, place.cwd, !!place.create)
    }
  }

  function handleKey(event) {
    if (!root.opened) return false
    var toolCount = root.tools.length
    var picksTool = root.mode === "new" && toolCount > 0
    if (event.key === Qt.Key_Escape) {
      if (root.query) root.setQuery("")
      else root.canceled()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.accept()
    } else if (event.key === Qt.Key_Up) {
      root.moveTo(root.selectedIndex - 1)
    } else if (event.key === Qt.Key_Down) {
      root.moveTo(root.selectedIndex + 1)
    } else if (event.key === Qt.Key_PageUp) {
      root.moveTo(root.selectedIndex - root.visibleRows)
    } else if (event.key === Qt.Key_PageDown) {
      root.moveTo(root.selectedIndex + root.visibleRows)
    } else if (picksTool && (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
               || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))) {
      root.toolIndex = (root.toolIndex - 1 + toolCount) % toolCount
    } else if (picksTool && (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)) {
      root.toolIndex = (root.toolIndex + 1) % toolCount
    } else if (event.key === Qt.Key_Backspace) {
      root.setQuery(root.query.slice(0, -1))
    } else if (event.text && event.text.length === 1
               && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
               && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
      root.setQuery(root.query + event.text)
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
      width: Math.min(parent.width - Style.space(32), Style.space(560))
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
        spacing: Style.space(14)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.mode === "filter" ? "Show the sessions in" : "New session"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        // The tool it starts with.
        Row {
          id: toolButtons
          visible: root.mode === "new"
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.mode === "new" ? root.tools : []

            BorderSurface {
              required property int index
              required property var modelData
              readonly property bool selected: root.toolIndex === index

              width: (toolButtons.width - toolButtons.spacing * (root.tools.length - 1)) / Math.max(1, root.tools.length)
              height: Style.space(40)
              color: selected ? root.selectedBackground : "transparent"
              borderSpec: Border.flat(selected ? root.selectedText : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
              radius: 0

              Row {
                anchors.centerIn: parent
                spacing: Style.space(7)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: Model.toolColor(modelData.id, root.themeColors, root.accent)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: selected ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toolIndex = index
              }
            }
          }
        }

        // What is typed, with a caret, like the panel's search line.
        Item {
          width: parent.width
          height: Style.font.body + Style.space(12)

          Text {
            id: queryLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.query || (root.mode === "new" ? "Find a workspace, or name a new one…" : "Find a workspace…")
            leftPadding: root.query ? 0 : caret.width + Style.space(6)
            color: root.foreground
            opacity: root.query ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Rectangle {
            id: caret
            x: root.query ? Math.min(queryLine.contentWidth, queryLine.width) + Style.space(2) : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, Style.space(2))
            height: Style.font.body + Style.space(4)
            color: root.accent

            SequentialAnimation on opacity {
              running: root.opened
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 530 }
              NumberAnimation { to: 0; duration: 0 }
              PauseAnimation { duration: 530 }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.normalBorderWidth
            color: Util.alpha(root.foreground, 0.15)
          }
        }

        Item {
          width: parent.width
          height: root.rowHeight * root.visibleRows

          Text {
            visible: root.shown.length === 0
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "No workspace matches"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: list
            anchors.fill: parent
            model: root.shown.length
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: place
              required property int index
              readonly property var entry: root.shown[index]
              readonly property bool selected: root.selectedIndex === index

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: place.selected ? root.selectedBackground : "transparent"

              Text {
                id: placeLabel
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.45)
                textFormat: Text.PlainText
                text: place.entry ? (place.entry.create ? "+ new  " : "") + place.entry.label : ""
                color: place.selected ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Row {
                id: placeTools
                anchors.left: placeLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Repeater {
                  model: place.entry ? place.entry.tools : []

                  Rectangle {
                    required property var modelData
                    width: Style.space(6)
                    height: width
                    radius: width / 2
                    color: Model.toolColor(modelData, root.themeColors, root.accent)
                  }
                }
              }

              Text {
                anchors.left: placeTools.right
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: place.entry ? place.entry.path : ""
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideLeft
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: {
                  root.selectedIndex = index
                  root.accept()
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.mode === "filter"
            ? "type to narrow    ↑↓ workspace    enter shows it    esc cancels"
            : "type to narrow    ↑↓ workspace    ←→ tool    enter starts    esc cancels"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
