import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
    id: listViewRoot
    property alias field: searchField
    required property var controller
    width: parent.width
    spacing: Style.space(10)
    visible: controller.view === "list"

    Item {
        width: parent.width
        height: searchField.implicitHeight

        TextField {
            id: searchField
            anchors.left: parent.left
            anchors.right: gearBtn.left
            anchors.rightMargin: Style.space(8)
            placeholderText: "Search tickers…"
            hasCursor: controller.listChrome === "search" && !activeFocus
            foreground: controller.contentForeground
            font.family: controller.contentFontFamily

            onActiveFocusChanged: {
                if (activeFocus)
                    controller.searching = true;
            }
            onTextChanged: {
                controller.searchQuery = text;
                if (controller.searching)
                    controller.scheduleSearch();
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    controller.clearSearch();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    controller.focusRowsChrome();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right && searchField.cursorPosition >= String(searchField.text).length) {
                    controller.focusGearChrome();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    controller.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    controller.commitSearch();
                    event.accepted = true;
                }
            }
        }

        PanelActionButton {
            id: gearBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf013"
            tooltipText: "Settings"
            foreground: controller.dim
            fontFamily: controller.contentFontFamily
            hasCursor: controller.listChrome === "gear"
            bordered: controller.listChrome === "gear"
            onClicked: controller.openSettings()
        }
    }

    Text {
        visible: controller.quoteStatusText !== ""
        width: parent.width
        text: controller.quoteStatusText
        color: controller.quoteError ? controller.contentUrgent : controller.dim
        font.family: controller.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
    }

    Column {
        width: parent.width
        spacing: Style.space(2)
        visible: controller.searching && controller.searchQuery.length > 0

        Repeater {
            model: controller.suggestions

            Item {
                required property int index
                required property var modelData
                width: parent.width
                height: Style.space(44)
                readonly property bool favorited: Model.isFavorite(controller.watchlist, modelData.symbol)

                CursorSurface {
                    anchors.fill: parent
                    foreground: controller.contentForeground
                    hasCursor: controller.cursorActive && index === controller.suggestionIndex

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            controller.cursorActive = true;
                            controller.suggestionIndex = index;
                        }
                        onClicked: controller.openDetail(modelData.symbol)
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: starBtn.left
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.symbol
                            color: controller.contentForeground
                            font.family: controller.contentFontFamily
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData.name + (Model.suggestionMeta(modelData) ? "  " + Model.suggestionMeta(modelData) : "")
                            color: controller.dim
                            font.family: controller.contentFontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    PanelActionButton {
                        id: starBtn
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        z: 2
                        iconText: favorited ? "★" : "☆"
                        tooltipText: favorited ? "Remove from watchlist" : "Add to watchlist"
                        foreground: favorited ? controller.contentForeground : controller.dim
                        fontFamily: controller.contentFontFamily
                        onClicked: controller.toggleFavorite(modelData.symbol)
                    }
                }
            }
        }

        Text {
            visible: controller.suggestions.length === 0 && controller.searchQuery.length > 0
            text: controller.searchRunning ? "Searching…" : (controller.searchError || "No matches")
            color: controller.searchError ? controller.contentUrgent : controller.dim
            font.family: controller.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            leftPadding: Style.space(4)
        }
    }

    Column {
        width: parent.width
        spacing: 0
        visible: !(controller.searching && controller.searchQuery.length > 0)

        Repeater {
            model: controller.watchlist

            Item {
                required property int index
                required property var modelData
                width: parent ? parent.width : 0
                height: controller.rowHeight

                readonly property string symbol: String(modelData)
                readonly property var quote: controller.quotes[symbol] || null
                readonly property bool selected: controller.cursorActive && index === controller.selectedIndex
                readonly property bool isPinned: Model.isPinned(controller.pinned, symbol)
                readonly property color sparkColor: controller.toneColor(quote ? quote.changePercent : null)

                CursorSurface {
                    anchors.fill: parent
                    foreground: controller.contentForeground
                    hasCursor: selected

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            controller.cursorActive = true;
                            controller.selectedIndex = index;
                        }
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.LeftButton)
                                controller.prefetchDetail(symbol);
                        }
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton)
                                controller.pinSymbol(symbol);
                            else
                                controller.openDetail(symbol);
                        }
                    }

                    Column {
                        id: nameCol
                        anchors.left: parent.left
                        anchors.right: spark.left
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Row {
                            spacing: Style.space(6)
                            width: parent.width
                            Text {
                                textFormat: Text.PlainText
                                text: symbol
                                color: controller.contentForeground
                                font.family: controller.contentFontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            Text {
                                visible: isPinned
                                text: "★"
                                color: controller.dim
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: quote && quote.name ? quote.name : ""
                            color: controller.dim
                            font.family: controller.contentFontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Sparkline {
                        id: spark
                        width: Style.space(72)
                        height: Style.space(28)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8) + Style.space(108) + Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        values: quote && quote.closes ? quote.closes : []
                        lineColor: sparkColor
                        fillColor: Qt.rgba(sparkColor.r, sparkColor.g, sparkColor.b, 0.2)
                        showZeroLine: quote && Model.changeTone(quote.changePercent) === "down"
                        zeroValue: quote && quote.previousClose != null ? quote.previousClose : Number.NaN
                        zeroLineColor: controller.dim
                    }

                    Column {
                        id: priceCol
                        width: Style.space(108)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: quote ? Model.formatPrice(quote.price, quote.currency, quote.priceHint) : "-"
                            color: controller.contentForeground
                            font.family: controller.contentFontFamily
                            font.pixelSize: Style.font.body
                        }

                        Rectangle {
                            anchors.right: parent.right
                            radius: Style.space(6)
                            color: controller.pillFill(quote ? quote.changePercent : null)
                            implicitWidth: changeLabel.implicitWidth + Style.space(12)
                            implicitHeight: changeLabel.implicitHeight + Style.space(4)

                            Text {
                                id: changeLabel
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: quote ? Model.formatQuoteChange(quote, controller.changeStyle) : "-"
                                color: controller.contentForeground
                                font.family: controller.contentFontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }

        Column {
            visible: controller.watchlist.length === 0
            width: parent.width
            spacing: Style.space(8)
            topPadding: Style.space(36)

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "No favorites yet"
                color: controller.contentForeground
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Search for a ticker, then Favorite it to add it to your watchlist."
                color: controller.dim
                font.family: controller.contentFontFamily
                font.pixelSize: Style.font.body
            }
        }
    }
}
