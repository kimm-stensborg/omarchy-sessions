import QtQuick
import qs.Commons

// The strip at the foot of the Sessions panel: every subscription side by
// side, each with a line and a meter per allowance that renews. Its height is
// fixed at room for `lines` allowances, so the list above never moves as the
// numbers come and go. Clicking a subscription shows only that tool's sessions.
Item {
  id: band

  property var providers: []
  property int lines: 2
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color accent: Color.accent
  property color warningColor: Color.accent

  signal picked(string id)

  readonly property int gap: Style.space(3)
  readonly property int meterHeight: Math.max(2, Style.space(3))
  readonly property int lineHeight: Math.ceil(captionMetrics.height)

  visible: band.providers.length > 0
  implicitHeight: band.lineHeight + band.lines * (band.gap + band.lineHeight + band.gap + band.meterHeight)

  FontMetrics {
    id: captionMetrics
    font.family: band.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Amber from three quarters, red near the end.
  function levelColor(limit, normal) {
    if (limit && limit.alarming) return Color.urgent
    if (limit && limit.warning) return band.warningColor
    return normal
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: band.foreground
    font.family: band.fontFamily
    font.pixelSize: Style.font.caption
    height: band.lineHeight
    verticalAlignment: Text.AlignVCenter
  }

  Row {
    id: summary
    width: band.width
    height: band.height
    spacing: Style.space(18)

    Repeater {
      model: band.providers.length

      delegate: Item {
        id: cell
        required property int index
        readonly property var provider: band.providers[index]
        readonly property var shown: cell.provider ? cell.provider.summary.slice(0, band.lines) : []
        width: (summary.width - summary.spacing * (band.providers.length - 1)) / Math.max(1, band.providers.length)
        height: summary.height

        Column {
          width: parent.width
          spacing: band.gap

          Caption {
            width: parent.width
            text: {
              if (!cell.provider) return ""
              var bits = [cell.provider.name]
              if (cell.provider.tier) bits.push(cell.provider.tier)
              return bits.join(" · ")
            }
            elide: Text.ElideRight
          }

          // Nothing that renews, as with Grok counted on this machine alone:
          // what was recorded stands in for the allowance lines.
          Caption {
            visible: cell.shown.length === 0
            width: parent.width
            text: cell.provider ? cell.provider.todayLabel || "" : ""
            opacity: 0.6
            elide: Text.ElideRight
          }

          Repeater {
            model: cell.shown.length

            delegate: Column {
              id: allowance
              required property int index
              readonly property var limit: cell.shown[index]
              width: cell.width
              spacing: band.gap

              Item {
                width: parent.width
                height: band.lineHeight

                Caption {
                  id: allowanceUsed
                  anchors.left: parent.left
                  text: allowance.limit ? allowance.limit.short + " " + allowance.limit.text : ""
                  color: band.levelColor(allowance.limit, band.foreground)
                  opacity: allowance.limit && (allowance.limit.alarming || allowance.limit.warning) ? 1 : 0.75
                }

                Caption {
                  anchors.left: allowanceUsed.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  horizontalAlignment: Text.AlignRight
                  text: allowance.limit ? allowance.limit.reset : ""
                  opacity: 0.5
                  elide: Text.ElideLeft
                }
              }

              Rectangle {
                width: parent.width
                height: band.meterHeight
                radius: height / 2
                color: Util.alpha(band.borderColor, 0.28)

                Rectangle {
                  width: parent.width * (allowance.limit ? Math.min(1, allowance.limit.percent) : 0)
                  height: parent.height
                  radius: parent.radius
                  color: band.levelColor(allowance.limit, band.accent)
                }
              }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (cell.provider) band.picked(cell.provider.id)
        }
      }
    }
  }
}
