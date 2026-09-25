import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A bar button: a small meter and the share used of whichever allowance is
// fullest, amber from three quarters and red near the end. The tooltip lists
// every allowance and when it renews; a click opens Sessions.
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

  property var summary: null
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
    root.summary = Model.barSummary(Model.usageFrom(
      payload.subscriptions || [], payload.grok || [], Date.now(),
      payload.allowance || null, payload.cursor || null))
  }

  function openSessions() {
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
      tooltipText: root.summary ? root.summary.tooltip : ""
      iconComponent: meter
      onPressed: root.openSessions()
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar && root.summary) root.bar.showTooltip(button, root.summary.tooltip)
        onExited: if (root.bar) root.bar.hideTooltip(button)
        onClicked: root.openSessions()
      }
    }
  }

  // A short track filled to the share used, on the icon canvas.
  Component {
    id: meter

    Item {
      Rectangle {
        id: track
        anchors.centerIn: parent
        width: parent.width
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
