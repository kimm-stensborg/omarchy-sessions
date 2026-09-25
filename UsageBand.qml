import QtQuick
import qs.Commons

// The strip above the list: the subscriptions side by side, each with its
// headline and a meter. Expanded (one tool picked), that subscription opens
// into its limits and its per-model split instead.
Column {
  id: band

  property var providers: []
  property bool expanded: false
  property int lineHeight: Style.space(22)
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color accent: Color.accent

  signal picked(string id)

  spacing: Style.space(8)
  visible: band.providers.length > 0

  // A thin track with the used share filled in, red once it is nearly gone.
  component Meter: Rectangle {
    property real share: 0
    property bool alarming: false
    property color fill: band.accent
    property real trackAlpha: 0.28

    height: Math.max(2, Style.space(2))
    radius: height / 2
    color: Util.alpha(band.borderColor, trackAlpha)

    Rectangle {
      width: parent.width * parent.share
      height: parent.height
      radius: parent.radius
      color: parent.alarming ? Color.urgent : parent.fill
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: band.foreground
    font.family: band.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    id: summary
    visible: !band.expanded
    width: band.width
    spacing: Style.space(18)

    Repeater {
      model: band.providers.length

      delegate: Item {
        id: cell
        required property int index
        readonly property var provider: band.providers[index]
        width: (summary.width - summary.spacing * (band.providers.length - 1)) / Math.max(1, band.providers.length)
        height: cellText.implicitHeight

        Column {
          id: cellText
          width: parent.width
          spacing: Style.space(3)

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

          Caption {
            width: parent.width
            text: cell.provider ? (cell.provider.headline || cell.provider.todayLabel || "") : ""
            color: cell.provider && cell.provider.alarming ? Color.urgent : band.foreground
            opacity: cell.provider && cell.provider.alarming ? 1 : 0.6
            elide: Text.ElideRight
          }

          Meter {
            width: parent.width
            height: Math.max(2, Style.space(3))
            share: cell.provider ? cell.provider.meter : 0
            alarming: cell.provider ? cell.provider.alarming : false
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

  Repeater {
    model: band.expanded ? band.providers.length : 0

    delegate: Column {
      id: providerBlock
      required property int index
      readonly property var provider: band.providers[index]
      width: band.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: band.lineHeight

        Caption {
          anchors.left: parent.left
          anchors.right: providerAside.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (!providerBlock.provider) return ""
            var bits = [providerBlock.provider.name]
            if (providerBlock.provider.tier) bits.push(providerBlock.provider.tier)
            return bits.join("  ·  ")
          }
          elide: Text.ElideRight
        }

        Caption {
          id: providerAside
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: providerBlock.provider ? providerBlock.provider.todayLabel || "" : ""
          opacity: 0.7
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        visible: providerBlock.provider && providerBlock.provider.limits.length > 0

        Repeater {
          model: providerBlock.provider ? providerBlock.provider.limits.length : 0

          delegate: Item {
            id: limitRow
            required property int index
            readonly property var window: providerBlock.provider.limits[index]
            width: providerBlock.width
            height: band.lineHeight

            Caption {
              anchors.left: parent.left
              anchors.right: limitPercent.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: limitRow.window
                ? limitRow.window.label + (limitRow.window.reset ? "  ·  " + limitRow.window.reset : "")
                : ""
              opacity: 0.75
              elide: Text.ElideRight
            }

            Caption {
              id: limitPercent
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: limitRow.window ? limitRow.window.text : ""
              color: limitRow.window && limitRow.window.alarming ? Color.urgent : band.foreground
            }

            Meter {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              share: limitRow.window ? limitRow.window.percent : 0
              alarming: limitRow.window ? limitRow.window.alarming : false
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: providerBlock.provider && providerBlock.provider.models.length > 0

        Caption {
          text: "Models"
          opacity: 0.4
        }

        Repeater {
          model: providerBlock.provider ? providerBlock.provider.models.length : 0

          delegate: Item {
            id: modelRow
            required property int index
            readonly property var stats: providerBlock.provider.models[index]
            width: providerBlock.width
            height: Math.max(band.lineHeight, Style.font.caption * 2 + Style.space(8))

            Caption {
              id: modelTotal
              anchors.right: parent.right
              anchors.top: parent.top
              text: modelRow.stats ? modelRow.stats.totalLabel : ""
            }

            Caption {
              anchors.left: parent.left
              anchors.right: modelTotal.left
              anchors.rightMargin: Style.space(8)
              anchors.top: parent.top
              text: modelRow.stats ? modelRow.stats.name + (modelRow.stats.cost ? "  ·  " + modelRow.stats.cost : "") : ""
              elide: Text.ElideRight
            }

            Caption {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: modelBar.top
              anchors.bottomMargin: Style.space(2)
              text: modelRow.stats ? modelRow.stats.detail : ""
              opacity: 0.45
              elide: Text.ElideRight
            }

            Meter {
              id: modelBar
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              share: modelRow.stats ? modelRow.stats.share : 0
              fill: Util.alpha(band.accent, 0.85)
              trackAlpha: 0.18
            }
          }
        }
      }
    }
  }
}
