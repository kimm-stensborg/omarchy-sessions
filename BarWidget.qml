import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The AI usage bar button, in place of Omarchy's Agents: the tool's colour,
// a small meter and the share used, amber from three quarters and red near
// the end. Which tool is set in the popup ("Show in bar"); by default it is
// whichever allowance is fullest. Left click opens the usage popup, middle
// click the Sessions search. The tooltip lists every allowance.
//
// The numbers come from the cache scan.py keeps, so every monitor's bar and
// the panel agree. Each bar asks for a refresh every five minutes, and the
// cache's lock means only the first one actually fetches.
BarWidget {
  id: root
  moduleName: "io.github.kimm-stensborg.sessions"

  // Injected for third-party entry points that declare them.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.kimm-stensborg.sessions"
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir)
    : root.home + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || root.home + "/.cache")
    + "/omarchy/sessions/usage.json"
  readonly property int refreshSeconds: 300

  property var panels: []
  readonly property string barTool: String(root.setting("barTool", "fullest") || "fullest")
  readonly property var summary: Model.barSummary(root.panels, root.barTool)
  property var themeColors: ({})
  readonly property color warningColor: root.themeColors.yellow || Color.accent
  readonly property color levelColor: {
    if (root.summary && root.summary.alarming) return Color.urgent
    if (root.summary && root.summary.warning) return root.warningColor
    return button.foreground
  }

  visible: root.summary !== null
  implicitWidth: visible ? row.implicitWidth : 0
  implicitHeight: row.implicitHeight

  function readCache(content) {
    var payload = null
    try { payload = JSON.parse(String(content || "")) } catch (e) { return }
    if (!payload || typeof payload !== "object") return
    root.panels = Model.usageFrom(
      payload.subscriptions || [], payload.grok || [], Date.now(),
      payload.allowance || null, payload.cursor || null)
  }

  // Shape contract for the bar's summon/hide/toggle routing: it looks for
  // open/close/opened on the widget in its slot, not on the popup.
  readonly property bool opened: popup.item ? popup.item.opened === true : false
  readonly property bool popoutSwitchClosing: popup.item ? popup.item.popoutSwitchClosing === true : false
  function open() { if (popup.item) popup.item.open() }
  function close() { if (popup.item) popup.item.close() }
  function toggle() { if (popup.item) popup.item.toggle() }
  function closeForPopoutSwitch() { if (popup.item) popup.item.closeForPopoutSwitch() }

  // ---- A key for the popup.
  //
  // The shell sends this plugin's own id to its overlay, the Sessions search,
  // so the popup has a target of its own:
  //   omarchy-shell io.github.kimm-stensborg.sessions.usage toggle
  // Every monitor's bar has a copy of this widget and a target belongs to
  // whichever registers first, so only the copy on the focused screen holds it.
  readonly property string screenName: {
    var window = root.QsWindow ? root.QsWindow.window : null
    var screen = window && window.screen ? window.screen : null
    if (!screen) return ""
    if (typeof Hyprland.monitorFor === "function") {
      var hypr = Hyprland.monitorFor(screen)
      if (hypr && hypr.name) return String(hypr.name)
    }
    return String(screen.name || "")
  }
  readonly property bool focusedHere: root.screenName !== "" && !!Hyprland.focusedMonitor
    && root.screenName === String(Hyprland.focusedMonitor.name || "")
  property bool ipcOwner: false

  onFocusedHereChanged: {
    if (!root.focusedHere) root.ipcOwner = false
    else ipcClaim.restart()
  }
  Component.onCompleted: if (root.focusedHere) ipcClaim.restart()

  // The claim waits a beat, so the copy giving the target up has let go first.
  Timer {
    id: ipcClaim
    interval: 150
    onTriggered: root.ipcOwner = root.focusedHere
  }

  IpcHandler {
    enabled: root.ipcOwner
    target: root.pluginId + ".usage"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  function press(which) {
    if (which === Qt.MiddleButton) root.openSessions()
    else root.toggle()
  }

  function refreshNow() {
    if (forceProc.running) return
    forceProc.running = true
  }

  function pickBarTool(id) {
    setProc.command = ["omarchy", "bar", "set", root.moduleName, "barTool", id]
    setProc.running = true
  }

  function openSessions() {
    root.close()
    if (root.shell && typeof root.shell.toggle === "function") root.shell.toggle(root.pluginId, "{}")
    else if (root.bar) root.bar.run("omarchy-shell shell toggle " + root.pluginId + " '{}'")
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readCache(text())
  }

  FileView {
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeColors = Model.themeColors(text())
  }

  Loader {
    id: popup
    active: true
    source: Qt.resolvedUrl("UsagePanel.qml")
    visible: false
  }

  Binding { target: popup.item; property: "bar"; value: root.bar; when: popup.item !== null }
  Binding { target: popup.item; property: "settings"; value: root.settings; when: popup.item !== null }
  Binding { target: popup.item; property: "anchorItem"; value: button; when: popup.item !== null }
  Binding { target: popup.item; property: "hostWidget"; value: root; when: popup.item !== null }
  Binding { target: popup.item; property: "panels"; value: root.panels; when: popup.item !== null }
  Binding { target: popup.item; property: "barTool"; value: root.barTool; when: popup.item !== null }
  Binding { target: popup.item; property: "themeColors"; value: root.themeColors; when: popup.item !== null }
  Binding { target: popup.item; property: "warningColor"; value: root.warningColor; when: popup.item !== null }
  Binding { target: popup.item; property: "refreshing"; value: refreshProc.running || forceProc.running; when: popup.item !== null }

  Connections {
    target: popup.item
    function onRefreshRequested() { root.refreshNow() }
    function onSessionsRequested() { root.openSessions() }
    function onBarToolPicked(id) { root.pickBarTool(id) }
  }

  // Asked for from the popup: the numbers now, whatever the cache's age.
  Process {
    id: forceProc
    command: ["python3", root.pluginDir + "/scan.py", "usage"]
    onExited: cacheFile.reload()
  }

  Process {
    id: setProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn(root.pluginId + " bar set:", text.trim())
    }
  }

  Process {
    id: refreshProc
    command: ["python3", root.pluginDir + "/scan.py", "usage", "--max-age", String(root.refreshSeconds)]
    // The cache may not have existed for the watcher to watch until now.
    onExited: cacheFile.reload()
  }

  // Also re-reads the cache so the renewal countdowns in the tooltip move on.
  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!refreshProc.running) refreshProc.running = true
      cacheFile.reload()
    }
  }

  // The meter and the percent are two items rather than one button: the
  // kit's bar button paints either a glyph or a label. The label carries the
  // same clicks and tooltip so the pair behaves as one.
  Row {
    id: row
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      slotSize: Style.bar.statusSlot
      tooltipText: root.summary && !root.opened ? root.summary.tooltip : ""
      iconComponent: meter
      onPressed: function(which) { root.press(which) }
    }

    Item {
      visible: !root.vertical
      width: visible ? label.implicitWidth + Style.spaceReal(8.5) : 0
      height: button.implicitHeight

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: root.summary ? root.summary.text : ""
        color: root.levelColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar && root.summary && !root.opened) root.bar.showTooltip(button, root.summary.tooltip)
        onExited: if (root.bar) root.bar.hideTooltip(button)
        onPressed: function(mouse) { root.press(mouse.button) }
      }
    }
  }

  // The tool's colour, then a short track filled to the share used, on the
  // icon canvas.
  Component {
    id: meter

    Item {
      Rectangle {
        id: toolDot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(4, Math.round(parent.height / 3))
        height: width
        radius: width / 2
        color: root.summary ? Model.toolColor(root.summary.tool, root.themeColors, button.foreground) : button.foreground
      }

      Rectangle {
        id: track
        anchors.left: toolDot.right
        anchors.leftMargin: Math.max(2, Math.round(parent.width / 8))
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(3, Math.round(parent.height / 4))
        radius: height / 2
        color: Util.alpha(button.foreground, 0.25)

        Rectangle {
          width: track.width * (root.summary ? Math.min(1, root.summary.percent) : 0)
          height: track.height
          radius: track.radius
          color: root.levelColor
        }
      }
    }
  }
}
