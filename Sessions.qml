import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Sessions. One search line, a chip per tool that actually has something,
// and the recent conversations grouped by the folder they belong to.
// Enter goes back to the one in hand: a terminal already running it comes
// forward, otherwise a new terminal resumes it.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.kimm-stensborg.sessions"
  readonly property string pluginDir: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property string queryText: ""
  property string tool: ""
  property int selected: 0
  property var sessions: []
  property var viewRows: []
  property int count: 0
  property var chips: [{ id: "", label: "All" }]
  property var usage: []
  readonly property var usageShown: {
    if (!root.tool) return root.usage
    for (var i = 0; i < root.usage.length; i++) {
      if (root.usage[i].id === root.tool) return [root.usage[i]]
    }
    return []
  }
  readonly property bool usageOpen: root.tool !== "" && root.usageShown.length > 0
  readonly property int usageLine: Math.max(Style.space(22), Style.font.caption + Style.space(8))
  property bool scanning: false
  property string statusMessage: ""
  property int serial: 0

  readonly property var current: {
    for (var i = 0; i < root.viewRows.length; i++) {
      var row = root.viewRows[i]
      if (row.kind === "session" && row.cursor === root.selected) return row
    }
    return null
  }

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int metaLineHeight: Math.max(Style.space(26), Style.font.caption + Style.space(12))
  readonly property int footerHeight: Math.max(Style.space(20), Style.font.caption + Style.space(6))
  readonly property int rowHeight: Math.max(Style.space(46), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int headerRowHeight: Math.max(Style.space(28), Style.font.caption + Style.space(14))
  readonly property int cardWidth: Math.min(Style.space(820), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    var payload = root.parseJson(payloadJson || "{}") || ({})
    root.opened = true
    root.queryText = payload.query ? String(payload.query) : ""
    root.tool = payload.tool ? String(payload.tool) : ""
    root.selected = 0
    root.statusMessage = ""
    root.sessions = []
    root.viewRows = []
    root.count = 0
    root.usage = []
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    root.runScan()
    root.runUsage()
  }

  function close() {
    root.opened = false
    scanProc.running = false
    usageProc.running = false
    clientProc.running = false
  }

  function ping() { return "ok" }

  function scanCommand(args) {
    return ["python3", root.pluginDir + "/scan.py"].concat(args)
  }

  function parseJson(text) {
    try { return JSON.parse(text) } catch (e) { return null }
  }

  function flash(message) {
    root.statusMessage = message
    statusTimer.restart()
  }

  function refresh() {
    var present = Model.toolsPresent(root.sessions)
    var chips = [{ id: "", label: "All" }]
    var stillThere = root.tool === ""
    for (var i = 0; i < present.length; i++) {
      chips.push(present[i])
      if (present[i].id === root.tool) stillThere = true
    }
    if (!stillThere) root.tool = ""
    root.chips = chips
    var built = Model.rows(root.sessions, root.queryText, root.tool, Date.now(), root.home)
    root.viewRows = built.rows
    root.count = built.count
    if (root.selected >= root.count) root.selected = Math.max(0, root.count - 1)
    if (root.count > 0) resultList.positionViewAtIndex(root.visualOf(root.selected), ListView.Contain)
  }

  function visualOf(cursor) {
    for (var i = 0; i < root.viewRows.length; i++) {
      if (root.viewRows[i].kind === "session" && root.viewRows[i].cursor === cursor) return i
    }
    return 0
  }

  function runUsage() {
    usageProc.running = false
    usageProc.command = root.scanCommand(["usage"])
    usageProc.running = true
  }

  function applyUsage(text) {
    var payload = root.parseJson(text)
    if (!payload) return
    root.usage = Model.usageFrom(
      payload.subscriptions || [], payload.grok || [], Date.now(),
      payload.allowance || null, payload.cursor || null)
  }

  function runScan() {
    root.serial = root.serial + 1
    root.scanning = true
    scanProc.running = false
    scanProc.command = root.scanCommand(["list"])
    scanProc.serial = root.serial
    scanProc.running = true
  }

  function applyScan(text, serial) {
    if (serial !== root.serial) return
    var payload = root.parseJson(text)
    root.scanning = false
    if (!payload || !payload.sessions) {
      root.statusMessage = "Could not read sessions"
      return
    }
    root.sessions = Model.normalize(payload.sessions, root.home)
    root.refresh()
    if (root.sessions.length === 0 && payload.warnings && payload.warnings.length > 0)
      root.statusMessage = String(payload.warnings[0])
  }

  function move(delta) {
    if (root.count > 0) root.selectAbsolute((root.selected + delta + root.count) % root.count)
  }

  function selectAbsolute(index) {
    if (root.count === 0) return
    pointerGate.reset()
    root.selected = Math.max(0, Math.min(index, root.count - 1))
    resultList.positionViewAtIndex(root.visualOf(root.selected), ListView.Contain)
  }

  function setQuery(next) {
    root.queryText = next
    root.selected = 0
    pointerGate.reset()
    root.refresh()
  }

  function setTool(id) {
    root.tool = root.tool === id ? "" : id
    root.selected = 0
    pointerGate.reset()
    root.refresh()
  }

  // A terminal whose command line already carries this session comes
  // forward. Otherwise the tool is opened resumed, in that directory.
  function resume(row) {
    if (!row) return
    if (!Model.resumeArgv(row)) {
      root.flash("Can't resume this one")
      return
    }
    clientProc.pending = row
    clientProc.running = false
    clientProc.command = root.scanCommand(["clients"])
    clientProc.running = true
  }

  function resumeWithClients(clients) {
    var row = clientProc.pending
    if (!row) return
    var hit = Model.matchClient(row, clients)
    if (hit) {
      // Closed first: while the overlay holds the keyboard, Hyprland hands
      // focus back to the previous window as it goes, undoing the focus.
      root.close()
      actProc.command = root.scanCommand(["focus", hit.address])
    } else {
      var argv = Model.resumeArgv(row)
      if (!argv) return
      actProc.command = root.scanCommand(["launch", row.cwd || ""].concat(argv))
    }
    actProc.running = false
    actProc.running = true
  }

  Timer {
    id: statusTimer
    interval: 3000
    onTriggered: root.statusMessage = ""
  }

  Process {
    id: scanProc
    property int serial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text, scanProc.serial)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim().length > 0) console.warn(root.pluginId + " scan:", text.trim())
    }
  }

  Process {
    id: usageProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyUsage(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim().length > 0) console.warn(root.pluginId + " usage:", text.trim())
    }
  }

  Process {
    id: clientProc
    property var pending: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var clients = root.parseJson(text)
        if (clients) root.resumeWithClients(clients)
        else root.flash("Could not look at open windows")
      }
    }
  }

  Process {
    id: actProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = root.parseJson(text)
        var error = payload && payload.error ? payload.error : "Could not open it"
        if (payload && payload.ok === true) root.close()
        else if (root.opened) root.flash(error)
        else console.warn(root.pluginId + ":", error)
      }
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-sessions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.queryText) root.setQuery("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move(1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectAbsolute(root.selected - 6); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectAbsolute(root.selected + 6); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(root.count - 1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.resume(root.current)
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.setQuery(root.queryText.slice(0, -1))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            root.setQuery(root.queryText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          id: headerLine
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: statusLine.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.queryText || "Find a session…"
            color: root.foreground
            opacity: root.queryText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: statusLine
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.statusMessage) return root.statusMessage
              if (root.scanning) return "looking…"
              if (root.count === 0) return ""
              return root.count === 1 ? "1 session" : root.count + " sessions"
            }
            color: root.statusMessage ? root.selectedText : root.foreground
            opacity: root.statusMessage ? 0.95 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: root.metaLineHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Repeater {
              model: root.chips.length

              delegate: Rectangle {
                id: chip
                required property int index
                readonly property var entry: root.chips[index]
                readonly property bool active: entry && root.tool === entry.id

                radius: root.cornerRadius
                height: Math.max(Style.space(20), Style.font.caption + Style.space(8))
                width: chipLabel.implicitWidth + Style.space(18)
                color: chip.active ? root.selectedBackground : "transparent"
                border.width: Style.normalBorderWidth
                border.color: chip.active ? Util.alpha(root.accent, 0.55) : Util.alpha(root.borderColor, 0.28)

                Text {
                  id: chipLabel
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: chip.entry ? chip.entry.label : ""
                  color: chip.active ? root.selectedText : root.foreground
                  opacity: chip.active ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (chip.entry) root.setTool(chip.entry.id)
                }
              }
            }
          }
        }

        UsageBand {
          id: usageBand
          width: parent.width
          providers: root.usageShown
          expanded: root.usageOpen
          lineHeight: root.usageLine
          fontFamily: root.fontFamily
          foreground: root.foreground
          borderColor: root.borderColor
          accent: root.accent
          onPicked: function(id) { root.setTool(id) }
        }

        Item {
          width: parent.width
          height: Math.max(0, parent.height - root.headerHeight - root.metaLineHeight
            - root.footerHeight - root.contentSpacing * 3
            - (usageBand.visible ? usageBand.height + root.contentSpacing : 0))

          ListView {
            id: resultList
            anchors.fill: parent
            model: root.viewRows.length
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: sessionRow
              required property int index
              readonly property var entry: root.viewRows[index]
              readonly property bool header: entry && entry.kind === "header"
              readonly property bool hasCursor: entry && entry.kind === "session" && entry.cursor === root.selected

              width: ListView.view.width
              height: sessionRow.header ? root.headerRowHeight : root.rowHeight
              radius: root.cornerRadius
              color: sessionRow.hasCursor ? root.selectedBackground : "transparent"

              Text {
                visible: sessionRow.header
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                text: sessionRow.entry ? sessionRow.entry.project : ""
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: rowWhen
                visible: !sessionRow.header
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: sessionRow.entry && sessionRow.entry.when ? sessionRow.entry.when : ""
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                visible: !sessionRow.header
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: rowWhen.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: sessionRow.entry && sessionRow.entry.title ? sessionRow.entry.title : ""
                  color: sessionRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: sessionRow.entry && sessionRow.entry.toolLabel ? sessionRow.entry.toolLabel : ""
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !sessionRow.header
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (!sessionRow.entry || sessionRow.header) return
                  if (!pointerGate.moved(sessionRow, mouse)) return
                  root.selected = sessionRow.entry.cursor
                }
                onClicked: {
                  if (!sessionRow.entry || sessionRow.header) return
                  root.selected = sessionRow.entry.cursor
                  root.resume(sessionRow.entry)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.count === 0
            textFormat: Text.PlainText
            text: root.scanning ? "Looking…" : (root.queryText || root.tool ? "Nothing matches" : "No sessions yet")
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "enter resumes    esc closes"
          color: root.foreground
          opacity: 0.35
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
