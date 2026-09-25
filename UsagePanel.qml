import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup under the bar button, laid out as Omarchy's own Agents panel is:
// the tool's mark, name and plan, a switch between tools, then its limits,
// its tokens for each of the last seven days and its tokens by model. The
// footer says what the bar button shows and changes it.
//
// Keys: h / l or the arrows switch tool, b changes what the bar shows,
// r refreshes, s opens the Sessions search, Esc closes.
Panel {
  id: root
  moduleName: "io.github.kimm-stensborg.sessions"
  // The bar button owns what the shell routes to this plugin; the popup is
  // opened by clicking it or through the button's own IPC target.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var panels: []
  property string barTool: "fullest"
  property color warningColor: Color.accent
  property bool refreshing: false

  signal refreshRequested()
  signal sessionsRequested()
  signal barToolPicked(string id)

  property string shownTool: ""
  readonly property int shownIndex: {
    for (var i = 0; i < root.panels.length; i++) {
      if (root.panels[i].id === root.shownTool) return i
    }
    return 0
  }
  readonly property var shown: root.panels.length ? root.panels[root.shownIndex] : null
  readonly property var choices: Model.barChoices(root.panels)
  readonly property string barLabel: {
    for (var i = 0; i < root.choices.length; i++) {
      if (root.choices[i].id === root.barTool) return root.choices[i].label
    }
    return "Fullest"
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Omarchy's Agents ships marks for the tools it knows; the others fall back
  // to the bar glyph.
  readonly property string marksDir: Quickshell.shellDir + "/plugins/agents/assets/"
  readonly property string glyph: "󱚣"

  function open() {
    // Open on the tool the bar is showing, so the popup explains the number.
    var summary = Model.barSummary(root.panels, root.barTool)
    root.shownTool = summary ? summary.tool : ""
    root.controller.show()
  }

  function close() { root.controller.hide() }

  function step(delta) {
    if (!root.panels.length) return
    var at = (root.shownIndex + delta + root.panels.length) % root.panels.length
    root.shownTool = root.panels[at].id
  }

  function nextBarTool() {
    root.barToolPicked(Model.nextTool(root.choices, root.barTool, 1))
  }

  function levelColor(limit, normal) {
    if (limit && limit.alarming) return root.urgent
    if (limit && limit.warning) return root.warningColor
    return normal
  }

  function heroMeta(p) {
    if (!p) return ""
    var bits = []
    if (p.tier) bits.push(p.tier)
    if (p.activity) bits.push(p.activity + " today")
    else if (p.todayLabel) bits.push(p.todayLabel)
    return bits.join(" · ")
  }

  function capitalized(text) {
    var value = String(text || "")
    return value ? value.charAt(0).toUpperCase() + value.slice(1) : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.step(dx)
        if (dy !== 0)
          flick.contentY = Math.max(0, Math.min(flick.contentY + dy * Style.space(56),
                                                flick.contentHeight - flick.height))
      }
      onActivateRequested: root.refreshRequested()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "h") root.step(-1)
        else if (t === "l") root.step(1)
        else if (t === "b") root.nextBarTool()
        else if (t === "r") root.refreshRequested()
        else if (t === "s") root.sessionsRequested()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ---------- Mark · name · plan ----------
          PanelHero {
            visible: !!root.shown
            width: parent.width
            title: root.shown ? root.shown.name : ""
            meta: root.heroMeta(root.shown)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: mark
                width: Style.font.display
                height: Style.font.display

                Image {
                  id: markImage
                  anchors.fill: parent
                  source: root.shown ? root.marksDir + root.shown.id + ".svg" : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.centerIn: parent
                  visible: markImage.status !== Image.Ready
                  textFormat: Text.PlainText
                  text: root.glyph
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            visible: root.panels.length === 0
            width: parent.width
            topPadding: Style.space(24)
            textFormat: Text.PlainText
            text: root.refreshing ? "Reading usage…" : "No AI subscriptions found.\nThey show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Tool switch ----------
          Row {
            id: toolSwitch
            visible: root.panels.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.panels.length > 0
              ? (width - spacing * (root.panels.length - 1)) / root.panels.length
              : 0

            Repeater {
              model: root.panels

              Button {
                required property var modelData
                required property int index
                width: toolSwitch.cellWidth
                // Each tool's share, so the switch compares them at a glance.
                text: Model.switchLabel(modelData)
                selected: index === root.shownIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.shownTool = modelData.id
              }
            }
          }

          // ---------- Why numbers are missing ----------
          BorderSurface {
            visible: !!root.shown && (root.shown.status !== "" || root.shown.help !== "")
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: Util.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(Util.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              textFormat: Text.PlainText
              text: root.shown ? [root.shown.status, root.shown.help].filter(function(t) { return t }).join(". ") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Limits ----------
          PanelSeparator {
            visible: limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: limitsSection
            visible: !!root.shown && root.shown.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.shown ? root.shown.limits : []

              LimitRow {
                required property var modelData
                width: limitsSection.width
                limit: modelData
              }
            }
          }

          // ---------- Tokens by day ----------
          PanelSeparator {
            visible: daysSection.visible
            foreground: root.foreground
          }

          Column {
            id: daysSection
            visible: !!root.shown && root.shown.days.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.shown ? root.shown.days : []

              DayRow {
                required property var modelData
                width: daysSection.width
                day: modelData
              }
            }
          }

          // ---------- Tokens by model ----------
          PanelSeparator {
            visible: modelsSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelsSection
            visible: !!root.shown && root.shown.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.shown ? root.shown.models : []

              ModelRow {
                required property var modelData
                width: modelsSection.width
                row: modelData
              }
            }
          }

          // ---------- What the bar shows ----------
          Item {
            visible: root.choices.length > 1
            width: parent.width
            implicitHeight: barLine.implicitHeight + Style.space(2)

            Text {
              id: barLine
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              textFormat: Text.StyledText
              text: "In the bar: <b>" + root.barLabel + "</b>"
              color: barHover.containsMouse ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: barHover
              anchors.fill: barLine
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.nextBarTool()
            }
          }
        }
      }
    }
  }

  // A limit: its name and share used, a meter, and when it renews.
  component LimitRow: Column {
    id: limitRow
    property var limit: null
    readonly property bool measured: !!limit && /%$/.test(String(limit.text || ""))

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: limitRow.limit ? limitRow.limit.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: limitValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: limitRow.limit ? limitRow.limit.text : ""
        color: root.levelColor(limitRow.limit, limitRow.measured ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Meter {
      visible: limitRow.measured
      width: parent.width
      value: limitRow.limit ? limitRow.limit.percent : 0
      fill: root.levelColor(limitRow.limit, root.foreground)
    }

    Text {
      visible: text !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: limitRow.limit ? root.capitalized(limitRow.limit.reset) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A rounded track filled to a share.
  component Meter: Item {
    id: meter
    property real value: 0
    property color fill: root.foreground

    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * Math.max(0, Math.min(1, meter.value))
      color: meter.fill

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  // One day: its name, a bar scaled to the busiest day, and its tokens.
  // Today is in full foreground, so the week reads as a run-up to now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    readonly property bool today: !!day && day.today

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
      textFormat: Text.PlainText
      text: dayRow.today ? "Today" : (dayRow.day ? dayRow.day.day : "")
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
    }

    Meter {
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      value: dayRow.day ? dayRow.day.share : 0
      fill: dayRow.today ? root.foreground : Util.alpha(root.foreground, 0.55)
    }

    Text {
      id: dayValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: dayRow.day && dayRow.day.label ? dayRow.day.label : "0"
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  // A model as a table row, its share filling the row behind the name. The
  // split between input, output and cache is in the tooltip.
  component ModelRow: Item {
    id: modelRow
    property var row: null

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * Math.max(0, Math.min(1, modelRow.row ? modelRow.row.share : 0))
      radius: Style.cornerRadius
      color: Util.alpha(root.foreground, 0.14)
    }

    Text {
      id: modelName
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: modelTokens
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: modelRow.row ? (modelRow.row.cost ? modelRow.row.cost + " · " : "") + modelRow.row.totalLabel : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse && modelRow.row && modelRow.row.detail !== ""
      text: modelRow.row ? modelRow.row.detail : ""
      fontFamily: root.fontFamily
    }
  }
}
