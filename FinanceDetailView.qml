import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
    id: detailViewRoot
    required property var controller
    width: parent.width
    spacing: Style.space(12)
    visible: controller.view === "detail"
    property bool showDetailsSpinner: false
    property double detailsLoadStartedAt: 0
    readonly property int detailsSpinnerDelayMs: Model.delayedLoaderDelayMs()
    readonly property string detailsPendingKey: visible && controller.detailDataLoading ? String(controller.detailSymbol) : ""

    function armDetailsSpinner() {
        detailsSpinnerDelay.stop();
        showDetailsSpinner = false;
        if (!detailsPendingKey) {
            detailsLoadStartedAt = 0;
            return;
        }
        detailsLoadStartedAt = Date.now();
        detailsSpinnerDelay.interval = detailsSpinnerDelayMs;
        detailsSpinnerDelay.start();
    }

    onDetailsPendingKeyChanged: armDetailsSpinner()

    Timer {
        id: detailsSpinnerDelay
        interval: detailViewRoot.detailsSpinnerDelayMs
        repeat: false
        onTriggered: {
            var remaining = detailViewRoot.detailsSpinnerDelayMs - (Date.now() - detailViewRoot.detailsLoadStartedAt);
            if (remaining > 0 && controller.detailDataLoading && detailViewRoot.visible) {
                interval = remaining;
                start();
                return;
            }
            showDetailsSpinner = Model.shouldShowDelayedLoader(controller.detailDataLoading && detailViewRoot.visible, detailViewRoot.detailsLoadStartedAt, Date.now(), detailViewRoot.detailsSpinnerDelayMs);
        }
    }

    Item {
        width: parent.width
        height: Math.max(backLabel.implicitHeight, detailActions.implicitHeight)

        Text {
            id: backLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "‹ Watchlist"
            color: controller.dim
            font.family: controller.contentFontFamily
            font.pixelSize: Style.font.body

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: controller.closeDetail()
            }
        }

        Row {
            id: detailActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
                text: controller.detailIsFavorite ? "Favorited" : "Favorite"
                hasCursor: controller.detailSection === 0 && controller.detailActionIndex === 0
                foreground: controller.detailIsFavorite ? controller.contentForeground : controller.dim
                fontFamily: controller.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: controller.toggleFavorite(controller.detailSymbol)
            }
            Button {
                text: Model.isPinned(controller.pinned, controller.detailSymbol) ? "Pinned" : "Pin"
                hasCursor: controller.detailSection === 0 && controller.detailActionIndex === 1
                foreground: Model.isPinned(controller.pinned, controller.detailSymbol) ? controller.contentForeground : controller.dim
                fontFamily: controller.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: controller.pinSymbol(controller.detailSymbol)
            }
            Button {
                visible: controller.detailIsFavorite
                text: "Remove"
                hasCursor: controller.detailSection === 0 && controller.detailActionIndex === 2
                foreground: controller.contentUrgent
                accent: controller.contentUrgent
                fontFamily: controller.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: {
                    controller.removeSymbol(controller.detailSymbol);
                    controller.closeDetail();
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Style.space(2)

        Row {
            spacing: Style.space(8)

            Text {
                id: tickerLabel
                textFormat: Text.PlainText
                text: controller.detailSymbol
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
            }

            Item {
                visible: detailViewRoot.showDetailsSpinner
                width: Style.font.body
                height: tickerLabel.height

                Canvas {
                    id: detailsSpinner
                    width: Style.font.body
                    height: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible)
                        requestPaint()
                    onPaint: {
                        var ctx = getContext("2d");
                        var line = Math.max(1.5, width * 0.14);
                        var radius = Math.min(width, height) / 2 - line;
                        ctx.reset();
                        ctx.lineWidth = line;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = controller.dim;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, radius, 0, Math.PI * 1.5);
                        ctx.stroke();
                    }

                    RotationAnimation on rotation {
                        running: detailsSpinner.visible
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }
                }
            }
        }
        Text {
            textFormat: Text.PlainText
            text: controller.activeQuote && controller.activeQuote.name ? controller.activeQuote.name : ""
            color: controller.dim
            font.family: controller.contentFontFamily
            font.pixelSize: Style.font.body
        }
    }

    Text {
        visible: controller.detailDataStatusText !== ""
        width: parent.width
        text: controller.detailDataStatusText
        color: controller.detailDataHasError ? controller.contentUrgent : controller.dim
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
    }

    Row {
        width: parent.width
        spacing: Style.space(16)

        Column {
            width: controller.showExtended ? (parent.width - parent.spacing) / 2 : parent.width
            spacing: Style.space(6)

            Row {
                spacing: Style.space(12)

                Text {
                    textFormat: Text.PlainText
                    text: controller.activeQuote ? Model.formatPrice(controller.detailMainPrice, controller.activeQuote.currency, controller.activeQuote.priceHint) : "-"
                    color: controller.contentForeground
                    font.family: controller.contentFontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(6)
                    color: controller.pillFill(controller.shownMainChange)
                    implicitWidth: detailChange.implicitWidth + Style.space(14)
                    implicitHeight: detailChange.implicitHeight + Style.space(6)

                    Text {
                        id: detailChange
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: Model.formatChangePair(controller.shownMainChange, controller.shownMainChangeAmount, controller.detailMainPrice, controller.activeQuote ? controller.activeQuote.currency : "USD", controller.activeQuote ? controller.activeQuote.priceHint : 2)
                        color: controller.contentForeground
                        font.family: controller.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                }
            }

            Text {
                visible: controller.priceCaption !== ""
                text: controller.priceCaption
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }

        Column {
            visible: controller.showExtended
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(6)

            Row {
                spacing: Style.space(12)

                Text {
                    textFormat: Text.PlainText
                    text: controller.sessionQuote ? Model.formatPrice(controller.sessionQuote.extendedPrice, controller.sessionQuote.currency, controller.sessionQuote.priceHint) : "-"
                    color: controller.contentForeground
                    font.family: controller.contentFontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(6)
                    color: controller.pillFill(controller.sessionQuote ? controller.sessionQuote.extendedChangePercent : null)
                    implicitWidth: extChange.implicitWidth + Style.space(14)
                    implicitHeight: extChange.implicitHeight + Style.space(6)

                    Text {
                        id: extChange
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: controller.sessionQuote ? Model.formatChangePair(controller.sessionQuote.extendedChangePercent, controller.extendedChangeAmount, controller.sessionQuote.extendedPrice, controller.sessionQuote.currency, controller.sessionQuote.priceHint) : "-"
                        color: controller.contentForeground
                        font.family: controller.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                }
            }

            Text {
                text: Model.extendedLabel(controller.sessionQuote)
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }
    }

    Row {
        id: rangeRow
        spacing: Style.space(4)

        Repeater {
            model: controller.detailRanges

            Rectangle {
                required property var modelData
                readonly property bool current: String(modelData) === controller.detailRange
                radius: Style.space(6)
                color: current ? Style.hoverFillFor(controller.contentForeground, Color.accent) : "transparent"
                implicitWidth: rangeLabel.implicitWidth + Style.space(14)
                implicitHeight: rangeLabel.implicitHeight + Style.space(8)

                Text {
                    id: rangeLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String(modelData)
                    color: current ? controller.contentForeground : controller.dim
                    font.family: controller.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: current
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: controller.setDetailRange(String(modelData))
                }
            }
        }
    }

    Text {
        visible: controller.chartStatusText !== ""
        width: parent.width
        text: controller.chartStatusText
        color: controller.chartError ? controller.contentUrgent : controller.dim
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
    }

    Sparkline {
        width: parent.width
        height: Style.space(140)
        values: controller.rangeChart && controller.rangeChart.closes ? controller.rangeChart.closes : []
        lineColor: controller.toneColor(controller.detailRangeChange)
        fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18)
        interactive: true
        currency: controller.activeQuote && controller.activeQuote.currency ? controller.activeQuote.currency : "USD"
        priceHint: controller.activeQuote ? controller.activeQuote.priceHint : 2
    }

    Row {
        width: parent.width
        spacing: Style.space(24)

        Column {
            spacing: Style.space(4)
            width: (parent.width - Style.space(72)) / 4
            Text {
                text: "OPEN"
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }
            Text {
                textFormat: Text.PlainText
                text: controller.activeQuote ? Model.formatPrice(controller.activeQuote.open, controller.activeQuote.currency, controller.activeQuote.priceHint) : "-"
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.title
            }
        }
        Column {
            spacing: Style.space(4)
            width: (parent.width - Style.space(72)) / 4
            Text {
                text: "HIGH"
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }
            Text {
                textFormat: Text.PlainText
                text: controller.activeQuote ? Model.formatPrice(controller.activeQuote.dayHigh, controller.activeQuote.currency, controller.activeQuote.priceHint) : "-"
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.title
            }
        }
        Column {
            spacing: Style.space(4)
            width: (parent.width - Style.space(72)) / 4
            Text {
                text: "LOW"
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }
            Text {
                textFormat: Text.PlainText
                text: controller.activeQuote ? Model.formatPrice(controller.activeQuote.dayLow, controller.activeQuote.currency, controller.activeQuote.priceHint) : "-"
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.title
            }
        }
        Column {
            spacing: Style.space(4)
            width: (parent.width - Style.space(72)) / 4
            Text {
                text: "VOL"
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }
            Text {
                textFormat: Text.PlainText
                text: controller.activeQuote ? Model.formatCompact(controller.activeQuote.volume) : "-"
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.title
            }
        }
    }

    Grid {
        width: parent.width
        columns: 3
        columnSpacing: Style.space(16)
        rowSpacing: Style.space(12)

        Repeater {
            model: controller.detailStats

            Column {
                required property var modelData
                width: (detailViewRoot.width - Style.space(32)) / 3
                spacing: Style.space(4)

                Text {
                    text: modelData.label
                    color: controller.dim
                    font.family: controller.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                }
                Text {
                    textFormat: Text.PlainText
                    text: modelData.value
                    color: controller.contentForeground
                    font.family: controller.contentFontFamily
                    font.pixelSize: Style.font.title
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }
    }
}
