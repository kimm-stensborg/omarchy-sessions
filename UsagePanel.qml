import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup under the bar button: one tool at a time with its allowances and
// when they renew, today's prompts and sessions, the last seven days and the
// split by model. A switch at the foot picks what the bar button shows.
//
// Keys: h / l or the arrows switch tool, r refreshes, s opens the Sessions
// search, Esc closes.
Panel {
  id: root
  moduleName: "io.github.kimm-stensborg.sessions"
  // The bar button owns what the shell routes to this plugin; the popup is
  // only ever opened by clicking it.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var panels: []
  property string barTool: "fullest"
  property color warningColor: Color.accent
  property var themeColors: ({})
  property bool refreshing: false

  signal refreshRequested()
  signal sessionsRequested()
  signal barToolPicked(string id)

  property string shownTool: ""
  readonly property var shown: {
    for (var i = 0; i < root.panels.length; i++) {
      if (root.panels[i].id === root.shownTool) return root.panels[i]
    }
    return root.panels.length ? root.panels[0] : null
  }
  readonly property var choices: Model.barChoices(root.panels)
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property color fg: Color.popups.text

  function open() {
    // Open on the tool the bar is showing, so the popup explains the number.
    var summary = Model.barSummary(root.panels, root.barTool)
    root.shownTool = summary ? summary.tool : ""
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function step(delta) {
    if (!root.panels.length) return
    var at = 0
    for (var i = 0; i < root.panels.length; i++) {
      if (root.shown && root.panels[i].id === root.shown.id) at = i
    }
    root.shownTool = root.panels[(at + delta + root.panels.length) % root.panels.length].id
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool active: false
    property color mark: "transparent"
    signal picked()

    radius: Style.cornerRadius
    height: Math.max(Style.space(20), Style.font.caption + Style.space(8))
    width: chipText.implicitWidth + Style.space(18) + (chipDot.visible ? chipDot.width + Style.space(6) : 0)
    color: chip.active ? Color.menu.selectedBackground : "transparent"
    border.width: Style.normalBorderWidth
    border.color: chip.active ? Util.alpha(Color.accent, 0.55) : Util.alpha(root.fg, 0.2)

    Rectangle {
      id: chipDot
      visible: chip.mark.a > 0
      width: Style.space(6)
      height: width
      radius: width / 2
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      color: chip.mark
    }

    Text {
      id: chipText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: chipDot.visible ? chipDot.right : parent.left
      anchors.leftMargin: chipDot.visible ? Style.space(6) : Style.space(9)
      textFormat: Text.PlainText
      text: chip.label
      color: chip.active ? Color.menu.selectedText : root.fg
      opacity: chip.active ? 1 : 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.picked()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.step(dx) }
      onTextKey: function(t) {
        if (t === "h") root.step(-1)
        else if (t === "l") root.step(1)
        else if (t === "r") root.refreshRequested()
        else if (t === "s") root.sessionsRequested()
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(12)

          // One chip per tool with numbers, when there is more than one.
          Flow {
            visible: root.panels.length > 1
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.panels.length

              delegate: Chip {
                required property int index
                readonly property var entry: root.panels[index]
                label: entry ? entry.name : ""
                active: root.shown && entry && root.shown.id === entry.id
                mark: entry ? Model.toolColor(entry.id, root.themeColors, "transparent") : "transparent"
                onPicked: root.shownTool = entry.id
              }
            }
          }

          Text {
            visible: root.panels.length === 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.refreshing ? "Reading usage…" : "No AI subscription has recorded any usage yet."
            color: root.fg
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          UsageBand {
            width: parent.width
            providers: root.shown ? [root.shown] : []
            expanded: true
            showDays: true
            fontFamily: root.fontFamily
            foreground: root.fg
            borderColor: Color.popups.border
            accent: Color.accent
            warningColor: root.warningColor
          }

          Rectangle {
            visible: root.choices.length > 1
            width: parent.width
            height: Style.normalBorderWidth
            color: Util.alpha(root.fg, 0.15)
          }

          // What the bar button shows, written to the widget's settings.
          Flow {
            visible: root.choices.length > 1
            width: parent.width
            spacing: Style.space(6)

            Text {
              height: Math.max(Style.space(20), Style.font.caption + Style.space(8))
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: "Show in bar"
              color: root.fg
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.choices.length

              delegate: Chip {
                required property int index
                readonly property var entry: root.choices[index]
                label: entry ? entry.label : ""
                active: entry && (root.barTool || "fullest") === entry.id
                mark: entry ? Model.toolColor(entry.id, root.themeColors, "transparent") : "transparent"
                onPicked: root.barToolPicked(entry.id)
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "h/l tool    r refresh    s sessions    esc closes"
            color: root.fg
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
