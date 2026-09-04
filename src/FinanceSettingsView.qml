import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
    id: settingsViewRoot
    required property var controller
    width: parent.width
    spacing: Style.space(14)
    visible: controller.view === "settings"

    Text {
        text: "‹ Watchlist"
        color: controller.dim
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.body

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: controller.view = "list"
        }
    }

    Text {
        text: "Settings"
        color: controller.contentForeground
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
    }

    Toggle {
        width: parent.width
        label: "Show ticker symbol"
        description: "Show the market symbol on the bar."
        checked: controller.showTicker
        hasCursor: controller.settingsCursor === 0
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        onClicked: controller.setShowTicker(!controller.showTicker)
    }

    Toggle {
        width: parent.width
        label: "Show price"
        description: "Show the latest price on the bar."
        checked: controller.showPrice
        hasCursor: controller.settingsCursor === 1
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        onClicked: controller.setShowPrice(!controller.showPrice)
    }

    Toggle {
        width: parent.width
        label: "Show change"
        description: "Show the price change on the bar."
        checked: controller.showChange
        hasCursor: controller.settingsCursor === 2
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        onClicked: controller.setShowChange(!controller.showChange)
    }

    Text {
        visible: controller.showChange
        text: "Change on bar"
        color: Qt.darker(controller.contentForeground, 1.4)
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
        visible: controller.showChange
        width: parent.width
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        fontSize: Style.font.bodySmall
        value: controller.changeStyle
        focusable: false
        cursorIndex: controller.settingsCursor === controller.changeStyleSettingsIndex ? ["percent", "dollars"].indexOf(controller.changeStyle) : -1
        options: [
            {
                value: "percent",
                label: "Percent"
            },
            {
                value: "dollars",
                label: "Dollars"
            }
        ]
        onChanged: function (v) {
            controller.setChangeStyle(v);
        }
    }

    NumberField {
        width: parent.width
        label: "Background refresh (seconds)"
        value: controller.refreshSeconds
        from: 15
        to: 3600
        stepSize: 15
        hasCursor: controller.settingsCursor === controller.refreshSettingsIndex
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        onModified: function (v) {
            controller.setRefreshSeconds(v);
        }
    }

    Toggle {
        width: parent.width
        label: "Show last updated time"
        description: "Show refresh times in the watchlist and detail views."
        checked: controller.showLastUpdated
        hasCursor: controller.settingsCursor === controller.lastUpdatedSettingsIndex
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        onClicked: controller.setShowLastUpdated(!controller.showLastUpdated)
    }

    Text {
        text: "Bar position"
        color: Qt.darker(controller.contentForeground, 1.4)
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.bodySmall
    }

    ButtonGroup {
        width: parent.width
        foreground: controller.contentForeground
        fontFamily: controller.contentFontFamily
        fontSize: Style.font.bodySmall
        value: controller.barSection
        focusable: false
        cursorIndex: controller.settingsCursor === controller.barSectionSettingsIndex ? ["left", "center", "right"].indexOf(controller.barSection) : -1
        options: [
            {
                value: "left",
                label: "Left"
            },
            {
                value: "center",
                label: "Center"
            },
            {
                value: "right",
                label: "Right"
            }
        ]
        onChanged: function (v) {
            controller.setBarSection(v);
        }
    }
}
