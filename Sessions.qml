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
  // Open windows, as scan.py describes them, for marking what already runs.
  property var clients: []
  // Where sessions open: the installed apps, the default and each session's
  // own, from scan.py `apps`.
  property var apps: ({ available: ["terminal"], default: "terminal", sessions: {} })
  property var themeColors: ({})
  readonly property color matchColor: root.themeColors.yellow || root.accent
  readonly property color runningColor: root.themeColors.green || root.accent
  readonly property color warningColor: root.themeColors.yellow || root.accent
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
  readonly property int rowHeight: Math.max(Style.space(34), Style.font.title + Style.space(16))
  // Row text sits this far inside its highlight. The list reaches out by the
  // same amount, so the text lines up with the search line and chips.
  readonly property int rowInset: Style.space(10)
  // Sessions sit this far in under their folder; the running dot lives there.
  readonly property int titleIndent: Style.space(16)
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
    root.clients = []
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    themeFile.reload()
    root.runScan()
    root.runUsage()
    runningProc.running = false
    runningProc.command = root.scanCommand(["clients"])
    runningProc.running = true
    appsProc.running = false
    appsProc.command = root.scanCommand(["apps"])
    appsProc.running = true
  }

  function close() {
    root.opened = false
    scanProc.running = false
    usageProc.running = false
    clientProc.running = false
    runningProc.running = false
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
    // Before the sessions arrive no tool is present yet; that is not a reason
    // to drop the one asked for (the window scan can finish first).
    if (!stillThere && root.sessions.length > 0) root.tool = ""
    root.chips = chips
    var built = Model.rows(root.sessions, root.queryText, root.tool, Date.now(), root.home,
      Model.runningIds(root.sessions, root.clients))
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
    root.rememberPanes()
    if (root.sessions.length === 0 && payload.warnings && payload.warnings.length > 0)
      root.statusMessage = String(payload.warnings[0])
  }

  // Stops at the newest and the oldest rather than wrapping round, so Up
  // always heads back towards the newest.
  function move(delta) {
    root.selectAbsolute(root.selected + delta)
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

  // A click on the chip already picked goes back to all of them.
  function setTool(id) {
    root.showTool(root.tool === id ? "" : id)
  }

  function showTool(id) {
    root.tool = id
    root.selected = 0
    pointerGate.reset()
    root.refresh()
  }

  // A terminal whose command line already carries this session comes
  // forward. Otherwise the tool is opened resumed, in that directory.
  // `app` picks where it opens when it is not running already; without one
  // it opens where it was opened last, or in the default.
  function resume(row, app) {
    if (!row) return
    if (!Model.resumeArgv(row)) {
      root.flash("Can't resume this one")
      return
    }
    clientProc.pending = row
    clientProc.app = app || ""
    clientProc.running = false
    clientProc.command = root.scanCommand(["clients"])
    clientProc.running = true
  }

  // DEL asks first; a session some process is still running is not offered
  // at all. scan.py checks again, across every process, before it deletes.
  property var pendingDelete: null

  function askDelete(row) {
    if (!row) return
    if (row.running) {
      root.flash("Still running; close it first")
      return
    }
    root.pendingDelete = row
    confirm.selectedIndex = 1
    confirm.opened = true
  }

  function cancelDelete() {
    confirm.opened = false
    root.pendingDelete = null
  }

  function confirmDelete() {
    var row = root.pendingDelete
    confirm.opened = false
    if (!row) return
    deleteProc.pending = row
    deleteProc.command = root.scanCommand(["delete", row.tool, row.id])
    deleteProc.running = true
  }

  function forget(id) {
    root.sessions = root.sessions.filter(function(session) { return session.id !== id })
    root.refresh()
  }

  // A new conversation with the row's tool, in the row's folder.
  function startNew(row) {
    var argv = row ? Model.newArgv(row.tool) : null
    if (!argv) return
    root.openIn(root.apps.default, row, argv, false)
  }

  // Closed first, as for focusing: herdr and tmux bring their window
  // forward, and the overlay letting go of the keyboard afterwards would hand
  // focus straight back. What goes wrong after that is told as a notification.
  function openIn(app, row, argv, remember) {
    root.close()
    if (remember) {
      var sessions = Object.assign({}, root.apps.sessions)
      sessions[row.id] = app
      root.apps = Object.assign({}, root.apps, { sessions: sessions })
    }
    actProc.command = root.scanCommand(Model.openArgs(app, row, argv, remember))
    actProc.running = false
    actProc.running = true
  }

  function chooseApp(row) {
    if (!row) return
    if (row.running) {
      root.resume(row)
      return
    }
    chooser.title = row.title
    chooser.pending = row
    chooser.show(Model.appChoices(root.apps), Model.appFor(row, root.apps))
  }

  function makeDefault(app) {
    root.apps = Object.assign({}, root.apps, { default: app })
    defaultProc.command = root.scanCommand(["set-default", app])
    defaultProc.running = true
  }

  // Sessions found running in a herdr or tmux pane are remembered there, so
  // one started by hand opens there again too.
  function rememberPanes() {
    var pairs = Model.panesToRemember(root.sessions, root.clients, root.apps)
    if (!pairs.length) return
    var sessions = Object.assign({}, root.apps.sessions)
    for (var i = 0; i < pairs.length; i++) {
      var parts = pairs[i].split("=")
      sessions[parts[0]] = parts[1]
    }
    root.apps = Object.assign({}, root.apps, { sessions: sessions })
    rememberProc.command = root.scanCommand(["remember"].concat(pairs))
    rememberProc.running = true
  }

  function resumeWithClients(clients) {
    var row = clientProc.pending
    if (!row) return
    var hit = Model.matchClient(row, clients)
    if (hit) {
      // Closed first: while the overlay holds the keyboard, Hyprland hands
      // focus back to the previous window as it goes, undoing the focus.
      root.close()
      var pane = Model.matchPane(row, hit)
      actProc.command = root.scanCommand(pane
        ? ["focus", hit.address, pane.kind || "herdr", pane.pane, pane.tab || "", pane.workspace || ""]
        : ["focus", hit.address])
      actProc.running = false
      actProc.running = true
      return
    }
    var argv = Model.resumeArgv(row)
    if (!argv) return
    root.openIn(clientProc.app || Model.appFor(row, root.apps), row, argv, true)
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
    property string app: ""
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
        var error = payload && payload.error ? String(payload.error) : "Could not open it"
        if (payload && payload.ok === true) root.close()
        else if (root.opened) root.flash(error)
        else {
          notifyProc.command = ["notify-send", "-a", "Sessions", "Sessions", error]
          notifyProc.running = true
        }
      }
    }
  }

  // The widest tool name and age, so both columns line up down the list.
  TextMetrics {
    id: toolMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Cursor"
  }

  TextMetrics {
    id: whenMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "just now"
  }

  Process {
    id: deleteProc
    property var pending: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var row = deleteProc.pending
        var payload = root.parseJson(text)
        root.pendingDelete = null
        if (payload && payload.ok === true && row) {
          root.forget(row.id)
          root.flash(row.tool === "codex" ? "Deleted" : "Moved to the trash")
        } else {
          root.flash(payload && payload.error ? String(payload.error) : "Could not delete it")
        }
      }
    }
  }

  Process {
    id: appsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = root.parseJson(text)
        if (payload && payload.available) root.apps = payload
        root.rememberPanes()
      }
    }
  }

  Process { id: rememberProc }
  Process { id: defaultProc }
  Process { id: notifyProc }

  // The window scan Enter does, run once on opening so the list can show
  // which sessions are already running somewhere.
  Process {
    id: runningProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.clients = root.parseJson(text) || []
        root.refresh()
        root.rememberPanes()
      }
    }
  }

  // The theme's named colours, for the tools, matches and warnings. Read
  // again on every open so a theme switch is picked up.
  FileView {
    id: themeFile
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.themeColors = Model.themeColors(text())
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
          // While asking, DEL or Enter deletes and Esc cancels; nothing else
          // reaches the list or the search line.
          if (chooser.opened) {
            chooser.handleKey(event)
            event.accepted = true
            return
          }
          if (confirm.opened) {
            if (event.key === Qt.Key_Delete) root.confirmDelete()
            else confirm.handleKey(event)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Delete) {
            root.askDelete(root.current)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
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
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            root.showTool(Model.nextTool(root.chips, root.tool, back ? -1 : 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier) root.startNew(root.current)
            else if (event.modifiers & Qt.ShiftModifier) root.chooseApp(root.current)
            else root.resume(root.current)
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
            id: queryLine
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: statusLine.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.queryText || "Find a session…"
            leftPadding: root.queryText ? 0 : caret.width + Style.space(6)
            color: root.foreground
            opacity: root.queryText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Rectangle {
            id: caret
            x: root.queryText ? Math.min(queryLine.contentWidth, queryLine.width) + Style.space(2) : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, Style.space(2))
            height: Style.font.heading + Style.space(4)
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
            color: Util.alpha(root.borderColor, 0.2)
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
                width: chipLabel.implicitWidth + Style.space(18) + (chipMark.visible ? chipMark.width + Style.space(6) : 0)
                color: chip.active ? root.selectedBackground : "transparent"
                border.width: Style.normalBorderWidth
                border.color: chip.active ? Util.alpha(root.accent, 0.55) : Util.alpha(root.borderColor, 0.28)

                Rectangle {
                  id: chipMark
                  visible: chip.entry && chip.entry.id !== ""
                  width: Style.space(6)
                  height: width
                  radius: width / 2
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  color: chip.entry ? Model.toolColor(chip.entry.id, root.themeColors, root.accent) : "transparent"
                }

                Text {
                  id: chipLabel
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: chipMark.visible ? chipMark.right : parent.left
                  anchors.leftMargin: chipMark.visible ? Style.space(6) : Style.space(9)
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

        Item {
          width: parent.width
          height: Math.max(0, parent.height - root.headerHeight - root.metaLineHeight
            - root.footerHeight - root.contentSpacing * 3
            - (usageBand.visible ? usageBand.height + Style.normalBorderWidth + root.contentSpacing * 2 : 0))


          ListView {
            id: resultList
            anchors.fill: parent
            anchors.leftMargin: -root.rowInset
            anchors.rightMargin: -root.rowInset
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
                id: headerName
                visible: sessionRow.header
                textFormat: Text.StyledText
                anchors.left: parent.left
                anchors.leftMargin: root.rowInset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                text: sessionRow.entry && sessionRow.header
                  ? Model.highlightHtml(sessionRow.entry.project, root.queryText, root.matchColor)
                  : ""
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: sessionRow.header && sessionRow.entry.count > 1
                textFormat: Text.PlainText
                anchors.left: headerName.right
                anchors.leftMargin: Style.space(6)
                anchors.baseline: headerName.baseline
                text: sessionRow.entry && sessionRow.header ? String(sessionRow.entry.count) : ""
                color: root.foreground
                opacity: 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Already running in a window, so Enter focuses it rather than opening one.
              Rectangle {
                visible: !sessionRow.header && sessionRow.entry && sessionRow.entry.running
                width: Style.space(6)
                height: width
                radius: width / 2
                x: root.rowInset + (root.titleIndent - width) / 2 - Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                color: root.runningColor
              }

              Text {
                id: rowWhen
                visible: !sessionRow.header
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: root.rowInset
                anchors.verticalCenter: parent.verticalCenter
                width: whenMetrics.width
                horizontalAlignment: Text.AlignRight
                text: sessionRow.entry && sessionRow.entry.when ? sessionRow.entry.when : ""
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                id: rowTool
                // Picking a tool's chip makes the column say the same thing on every row.
                visible: !sessionRow.header && root.tool === ""
                anchors.right: rowWhen.left
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? toolMetrics.width + Style.space(12) : 0
                height: parent.height

                Rectangle {
                  id: toolMark
                  width: Style.space(6)
                  height: width
                  radius: width / 2
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  color: sessionRow.entry ? Model.toolColor(sessionRow.entry.tool, root.themeColors, root.accent) : "transparent"
                }

                Text {
                  anchors.left: toolMark.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: sessionRow.entry && sessionRow.entry.toolLabel ? sessionRow.entry.toolLabel : ""
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: !sessionRow.header
                textFormat: Text.StyledText
                anchors.left: parent.left
                anchors.leftMargin: root.rowInset + root.titleIndent
                anchors.right: rowTool.visible ? rowTool.left : rowWhen.left
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: sessionRow.entry && sessionRow.entry.title
                  ? Model.highlightHtml(sessionRow.entry.title, root.queryText, root.matchColor)
                  : ""
                color: sessionRow.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
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

          // The list goes on below: let it fade out rather than stop mid-row.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(36)
            visible: root.count > 0 && !resultList.atYEnd
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
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

        Rectangle {
          visible: usageBand.visible
          width: parent.width
          height: Style.normalBorderWidth
          color: Util.alpha(root.borderColor, 0.2)
        }

        // Every subscription at a glance, at a fixed height so the list
        // above keeps its size. The full picture is in the bar's popup.
        UsageBand {
          id: usageBand
          width: parent.width
          height: implicitHeight
          providers: root.usage
          fontFamily: root.fontFamily
          foreground: root.foreground
          borderColor: root.borderColor
          accent: root.accent
          warningColor: root.warningColor
          onPicked: function(id) { root.setTool(id) }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "enter resumes    shift+enter opens in…    ctrl+enter starts new    del deletes    tab switches tool    esc closes"
          color: root.foreground
          opacity: 0.35
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Shift+Enter: which app a session opens in, remembered for it.
      AppChooser {
        id: chooser
        property var pending: null
        anchors.fill: parent
        defaultId: root.apps.default
        background: root.background
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onPicked: function(id) {
          chooser.opened = false
          root.resume(chooser.pending, id)
        }
        onMadeDefault: function(id) {
          root.makeDefault(id)
          root.flash(Model.appChoices({ available: [id] })[0].label + " is the default")
        }
        onCanceled: chooser.opened = false
      }

      // Asked before a session is deleted. DEL or Enter deletes, Esc cancels.
      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        message: {
          var row = root.pendingDelete
          if (!row) return ""
          return "Delete \u201c" + row.title + "\u201d?\n"
            + (row.tool === "codex" ? "Codex deletes it for good." : "It goes to the trash.")
        }
        cancelText: "Cancel"
        confirmText: "Delete"
        background: root.background
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onConfirmed: root.confirmDelete()
        onCanceled: root.cancelDelete()
      }
    }
  }
}
