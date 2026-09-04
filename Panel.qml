import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "mohamedmansour.finance"
  ipcTarget: "mohamedmansour.finance"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var watchlist: Model.defaultWatchlist()
  property var pinned: Model.defaultPinned()
  property int pinIndex: 0
  property var quotes: ({})
  property int selectedIndex: 0
  property bool cursorActive: false
  property string view: "list"
  property string detailSymbol: ""
  property string detailRange: "1D"
  property var detailQuote: null
  property string chartFetchRange: ""
  property var detailPage: ({})
  property var detailInsights: ({})
  property string searchQuery: ""
  property var suggestions: []
  property int suggestionIndex: 0
  property string searchPendingQuery: ""
  property string searchActiveQuery: ""
  property bool searching: false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentUrgent: bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.45)
  readonly property color upColor: Qt.rgba(0.22, 0.50, 0.30, 1)
  readonly property color downColor: Qt.rgba(0.62, 0.22, 0.22, 1)
  readonly property color upFill: Qt.rgba(upColor.r, upColor.g, upColor.b, 1)
  readonly property color downFill: Qt.rgba(downColor.r, downColor.g, downColor.b, 1)
  readonly property int refreshSeconds: Math.max(15, parseInt(setting("refreshSeconds", 60), 10) || 60)
  readonly property string barSymbol: Model.barSymbol(pinned, watchlist, pinIndex)
  readonly property var pinnedQuote: quotes[barSymbol] || null
  readonly property string label: Model.barLabel(barSymbol, pinnedQuote, false)
  readonly property string verticalLabel: Model.barLabel(barSymbol, pinnedQuote, true)
  readonly property string labelTone: Model.changeTone(pinnedQuote ? pinnedQuote.changePercent : null)
  readonly property var detailRanges: Model.chartRanges()
  readonly property var activeQuote: quotes[detailSymbol] || detailQuote
  readonly property var rangeChart: {
    if (detailQuote && detailQuote.chartRange === detailRange) return detailQuote
    if (detailRange === "1D" && quotes[detailSymbol]) return quotes[detailSymbol]
    return null
  }
  readonly property var detailStats: Model.buildDetailStats(activeQuote, detailPage, detailInsights)
  readonly property var detailRangeChange: Model.rangeChangePercent(rangeChart, detailRange)
  readonly property bool detailIsFavorite: Model.isFavorite(watchlist, detailSymbol)
  readonly property int rowHeight: Style.space(56)

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    stateFile.reload()
    root.refresh()
    root.view = "list"
    root.clearSearch()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    stateFile.reload()
    root.refresh()
    root.view = "list"
    root.clearSearch()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.clearSearch()
    root.view = "list"
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function toneColor(pct) {
    var tone = Model.changeTone(pct)
    if (tone === "up") return upColor
    if (tone === "down") return downColor
    return dim
  }

  function pillFill(pct) {
    var tone = Model.changeTone(pct)
    if (tone === "up") return upFill
    if (tone === "down") return downFill
    return Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.18)
  }

  function clampSelected() {
    if (watchlist.length === 0) {
      selectedIndex = 0
      return
    }
    if (selectedIndex < 0) selectedIndex = 0
    if (selectedIndex >= watchlist.length) selectedIndex = watchlist.length - 1
  }

  function persist() {
    stateFile.setText(Model.serializeState(watchlist, pinned, detailRange))
  }

  function applyState(raw) {
    var state = Model.parseState(raw)
    var before = (watchlist || []).join("\n")
    var after = (state.watchlist || []).join("\n")
    watchlist = state.watchlist
    pinned = state.pinned
    if (state.detailRange) detailRange = state.detailRange
    clampSelected()
    if (before !== after) Qt.callLater(refresh)
  }

  function refresh() {
    if (watchlist.length === 0) return
    if (quoteProc.running) return
    quoteProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.sparkUrl(watchlist)]
    quoteProc.running = true
  }

  function addSymbol(symbol) {
    var next = Model.addSymbol(watchlist, symbol)
    if (next.length === watchlist.length) {
      var already = Model.normalizeSymbol(symbol)
      if (already) {
        selectedIndex = next.indexOf(already)
        cursorActive = true
      }
      return
    }
    watchlist = next
    selectedIndex = next.length - 1
    cursorActive = true
    persist()
    refresh()
  }

  function removeSymbol(symbol) {
    var next = Model.removeSymbol(watchlist, symbol)
    watchlist = next
    pinned = Model.parsePinned(pinned, next)
    clampSelected()
    persist()
  }

  function pinSymbol(symbol) {
    var next = Model.normalizeSymbol(symbol)
    if (!next) return
    var list = Model.addSymbol(watchlist, next)
    watchlist = list
    pinned = Model.togglePinned(pinned, list, next)
    persist()
    refresh()
  }

  function toggleFavorite(symbol) {
    var next = Model.normalizeSymbol(symbol)
    if (!next) return
    if (Model.isFavorite(watchlist, next)) removeSymbol(next)
    else addSymbol(next)
  }

  function openDetail(symbol) {
    var next = Model.normalizeSymbol(symbol)
    if (!next) return
    detailSymbol = next
    detailQuote = null
    detailPage = ({})
    detailInsights = ({})
    view = "detail"
    searching = false
    fetchDetail()
  }

  function closeDetail() {
    view = "list"
    detailSymbol = ""
    detailQuote = null
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function setDetailRange(range) {
    var next = Model.normalizeRange(range)
    if (detailRange === next) return
    detailRange = next
    persist()
    if (!detailSymbol) return
    detailQuote = null
    startChartFetch()
  }

  function startChartFetch() {
    if (!detailSymbol) return
    chartFetchRange = detailRange
    if (chartProc.running) chartProc.running = false
    chartProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.chartUrl(detailSymbol, chartFetchRange)]
    chartProc.running = true
  }

  function fetchDetail() {
    if (!detailSymbol) return
    startChartFetch()
    fetchInsights()
    fetchQuotePage()
  }

  function fetchInsights() {
    if (!detailSymbol) return
    if (insightsProc.running) insightsProc.running = false
    insightsProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.insightsUrl(detailSymbol)]
    insightsProc.running = true
  }

  function fetchQuotePage() {
    if (!detailSymbol) return
    if (quotePageProc.running) quotePageProc.running = false
    quotePageProc.command = ["curl", "-fsS", "--compressed", "--max-time", "12", "-A", "Mozilla/5.0", Model.quotePageUrl(detailSymbol)]
    quotePageProc.running = true
  }

  function clearSearch() {
    searching = false
    searchQuery = ""
    suggestions = []
    suggestionIndex = 0
    searchDebounce.stop()
    if (searchField.text !== "") searchField.text = ""
    Qt.callLater(function() { if (root.opened && keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function startSearch(prefix) {
    searching = true
    Qt.callLater(function() {
      searchField.forceActiveFocus()
      if (prefix) {
        searchField.text = prefix
        searchField.cursorPosition = searchField.text.length
      } else {
        searchField.selectAll()
      }
    })
  }

  function requestSearch() {
    var query = searchField.text.replace(/^\s+|\s+$/g, "")
    searchQuery = query
    if (query.length < 1) {
      suggestions = []
      return
    }
    searchPendingQuery = query
    if (!searchProc.running) startSearchFetch()
  }

  function startSearchFetch() {
    searchActiveQuery = searchPendingQuery
    searchProc.command = ["curl", "-fsS", "--max-time", "5", "-A", "Mozilla/5.0", Model.searchUrl(searchActiveQuery)]
    searchProc.running = true
  }

  function commitSearch() {
    if (suggestions.length > 0) {
      var pick = suggestions[Math.max(0, Math.min(suggestionIndex, suggestions.length - 1))]
      if (pick) openDetail(pick.symbol)
      return
    }
    var typed = Model.normalizeSymbol(searchQuery || searchField.text)
    if (typed) openDetail(typed)
  }

  function moveCursor(dy) {
    cursorActive = true
    if (searching && suggestions.length > 0) {
      var next = suggestionIndex + dy
      if (next < 0) next = 0
      if (next >= suggestions.length) next = suggestions.length - 1
      suggestionIndex = next
      return
    }
    if (watchlist.length === 0) return
    selectedIndex = (selectedIndex + dy + watchlist.length) % watchlist.length
  }

  function activateCursor() {
    if (searching) {
      commitSearch()
      return
    }
    if (watchlist.length === 0) return
    openDetail(watchlist[selectedIndex])
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/finance.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: {
      root.applyState("")
      if (mkdirProc.running) root.seedOnReady = true
      else root.persist()
    }
    onFileChanged: reload()
  }

  property bool seedOnReady: false

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/settings"]
    onExited: {
      if (root.seedOnReady) {
        root.seedOnReady = false
        root.persist()
      }
    }
  }

  Component.onCompleted: mkdirProc.running = true

  Process {
    id: quoteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var parsed = Model.parseSpark(raw)
        root.quotes = Model.mergeQuotes(root.quotes, parsed)
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.suggestions = root.searching ? Model.parseSearch(text) : []
        root.suggestionIndex = 0
        if (root.searchPendingQuery !== root.searchActiveQuery) Qt.callLater(root.startSearchFetch)
      }
    }
  }

  Process {
    id: chartProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseChart(text)
        if (!parsed || parsed.symbol !== root.detailSymbol) return
        if (root.chartFetchRange !== root.detailRange) return
        parsed.chartRange = root.chartFetchRange
        root.detailQuote = parsed
      }
    }
  }

  Process {
    id: insightsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.detailSymbol) return
        root.detailInsights = Model.parseInsights(text)
      }
    }
  }

  Process {
    id: quotePageProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.detailSymbol) return
        root.detailPage = Model.parseQuotePage(text)
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: root.requestSearch()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: pinRotateTimer
    interval: 5000
    running: (root.pinned || []).length > 1
    repeat: true
    onTriggered: root.pinIndex = root.pinIndex + 1
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.view === "detail") {
          if (dx !== 0) {
            var ranges = root.detailRanges
            var idx = ranges.indexOf(root.detailRange)
            if (idx < 0) idx = 0
            idx = (idx + dx + ranges.length) % ranges.length
            root.setDetailRange(ranges[idx])
          }
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.view === "detail") return
        root.activateCursor()
      }
      onCloseRequested: {
        if (root.view === "detail") root.closeDetail()
        else if (root.searching) root.clearSearch()
        else root.close()
      }
      onDeleteRequested: {
        if (root.view !== "list" || root.searching || root.watchlist.length === 0) return
        root.removeSymbol(root.watchlist[root.selectedIndex])
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.view === "detail") return
        if (t === "/" || t === "?") { root.startSearch(""); return }
        if (t === "p" || t === "P") {
          if (root.watchlist.length > 0) root.pinSymbol(root.watchlist[root.selectedIndex])
          return
        }
        if (t === "x" || t === "X") return
        if (t && t.length === 1 && t !== " ") root.startSearch(t)
      }

      Flickable {
        id: bodyScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: bodyColumn
          width: bodyScroll.width
          spacing: Style.space(10)

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.view === "list"

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search tickers…"
              foreground: root.contentForeground
              font.family: root.contentFontFamily

              onActiveFocusChanged: {
                if (activeFocus) root.searching = true
              }
              onTextChanged: {
                root.searchQuery = text
                if (root.searching) searchDebounce.restart()
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.clearSearch()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  root.moveCursor(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  root.moveCursor(-1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitSearch()
                  event.accepted = true
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(2)
              visible: root.searching && root.searchQuery.length > 0

              Repeater {
                model: root.suggestions

                Item {
                  required property int index
                  required property var modelData
                  width: parent.width
                  height: Style.space(44)
                  readonly property bool favorited: Model.isFavorite(root.watchlist, modelData.symbol)

                  CursorSurface {
                    anchors.fill: parent
                    foreground: root.contentForeground
                    hasCursor: root.cursorActive && index === root.suggestionIndex

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: {
                        root.cursorActive = true
                        root.suggestionIndex = index
                      }
                      onClicked: root.openDetail(modelData.symbol)
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
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.name + (Model.suggestionMeta(modelData) ? "  " + Model.suggestionMeta(modelData) : "")
                        color: root.dim
                        font.family: root.contentFontFamily
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
                      foreground: favorited ? root.contentForeground : root.dim
                      fontFamily: root.contentFontFamily
                      onClicked: root.toggleFavorite(modelData.symbol)
                    }
                  }
                }
              }

              Text {
                visible: root.suggestions.length === 0 && root.searchQuery.length > 0
                text: "No matches"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                leftPadding: Style.space(4)
              }
            }

            Column {
              width: parent.width
              spacing: 0
              visible: !(root.searching && root.searchQuery.length > 0)

              Repeater {
                model: root.watchlist

                Item {
                  required property int index
                  required property var modelData
                  width: parent ? parent.width : 0
                  height: root.rowHeight

                  readonly property string symbol: String(modelData)
                  readonly property var quote: root.quotes[symbol] || null
                  readonly property bool selected: root.cursorActive && index === root.selectedIndex
                  readonly property bool isPinned: Model.isPinned(root.pinned, symbol)
                  readonly property color sparkColor: root.toneColor(quote ? quote.changePercent : null)

                  CursorSurface {
                    anchors.fill: parent
                    foreground: root.contentForeground
                    hasCursor: selected

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      cursorShape: Qt.PointingHandCursor
                      onEntered: {
                        root.cursorActive = true
                        root.selectedIndex = index
                      }
                      onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) root.pinSymbol(symbol)
                        else root.openDetail(symbol)
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
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.title
                          font.bold: true
                        }
                        Text {
                          visible: isPinned
                          text: "★"
                          color: root.dim
                          font.pixelSize: Style.font.bodySmall
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: quote && quote.name ? quote.name : ""
                        color: root.dim
                        font.family: root.contentFontFamily
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
                      zeroLineColor: root.dim
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
                        text: quote ? Model.formatPrice(quote.price, quote.currency, quote.priceHint) : "—"
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                      }

                      Rectangle {
                        anchors.right: parent.right
                        radius: Style.space(6)
                        color: root.pillFill(quote ? quote.changePercent : null)
                        implicitWidth: changeLabel.implicitWidth + Style.space(12)
                        implicitHeight: changeLabel.implicitHeight + Style.space(4)

                        Text {
                          id: changeLabel
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: quote ? Model.formatPercent(quote.changePercent) : "—"
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }
                    }

                  }
                }
              }

              Text {
                visible: root.watchlist.length === 0
                text: "Search to add a ticker"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                leftPadding: Style.space(4)
                topPadding: Style.space(8)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.view === "detail"

            Item {
              width: parent.width
              height: Math.max(backLabel.implicitHeight, detailActions.implicitHeight)

              Text {
                id: backLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹ Watchlist"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.closeDetail()
                }
              }

              Row {
                id: detailActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  text: root.detailIsFavorite ? "Favorited" : "Favorite"
                  foreground: root.detailIsFavorite ? root.contentForeground : root.dim
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.toggleFavorite(root.detailSymbol)
                }
                Button {
                  text: Model.isPinned(root.pinned, root.detailSymbol) ? "Pinned" : "Pin"
                  foreground: Model.isPinned(root.pinned, root.detailSymbol) ? root.contentForeground : root.dim
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.pinSymbol(root.detailSymbol)
                }
                Button {
                  visible: root.detailIsFavorite
                  text: "Remove"
                  foreground: root.contentUrgent
                  accent: root.contentUrgent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: {
                    root.removeSymbol(root.detailSymbol)
                    root.closeDetail()
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: root.detailSymbol
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: root.activeQuote && root.activeQuote.name ? root.activeQuote.name : ""
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
            }

            Row {
              spacing: Style.space(12)

              Text {
                textFormat: Text.PlainText
                text: root.activeQuote ? Model.formatPrice(root.activeQuote.price, root.activeQuote.currency, root.activeQuote.priceHint) : "—"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.space(6)
                color: root.pillFill(root.detailRangeChange)
                implicitWidth: detailChange.implicitWidth + Style.space(14)
                implicitHeight: detailChange.implicitHeight + Style.space(6)

                Text {
                  id: detailChange
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: Model.formatPercent(root.detailRangeChange)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }

            Row {
              id: rangeRow
              spacing: Style.space(4)

              Repeater {
                model: root.detailRanges

                Rectangle {
                  required property var modelData
                  readonly property bool current: String(modelData) === root.detailRange
                  radius: Style.space(6)
                  color: current ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  implicitWidth: rangeLabel.implicitWidth + Style.space(14)
                  implicitHeight: rangeLabel.implicitHeight + Style.space(8)

                  Text {
                    id: rangeLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String(modelData)
                    color: current ? root.contentForeground : root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: current
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setDetailRange(String(modelData))
                  }
                }
              }
            }

            Sparkline {
              width: parent.width
              height: Style.space(140)
              values: root.rangeChart && root.rangeChart.closes ? root.rangeChart.closes : []
              lineColor: root.toneColor(root.detailRangeChange)
              fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18)
              interactive: true
              currency: root.activeQuote && root.activeQuote.currency ? root.activeQuote.currency : "USD"
              priceHint: root.activeQuote ? root.activeQuote.priceHint : 2
            }

            Row {
              width: parent.width
              spacing: Style.space(24)

              Column {
                spacing: Style.space(4)
                width: (parent.width - Style.space(72)) / 4
                Text {
                  text: "OPEN"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.activeQuote ? Model.formatPrice(root.activeQuote.open, root.activeQuote.currency, root.activeQuote.priceHint) : "—"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                }
              }
              Column {
                spacing: Style.space(4)
                width: (parent.width - Style.space(72)) / 4
                Text {
                  text: "HIGH"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.activeQuote ? Model.formatPrice(root.activeQuote.dayHigh, root.activeQuote.currency, root.activeQuote.priceHint) : "—"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                }
              }
              Column {
                spacing: Style.space(4)
                width: (parent.width - Style.space(72)) / 4
                Text {
                  text: "LOW"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.activeQuote ? Model.formatPrice(root.activeQuote.dayLow, root.activeQuote.currency, root.activeQuote.priceHint) : "—"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                }
              }
              Column {
                spacing: Style.space(4)
                width: (parent.width - Style.space(72)) / 4
                Text {
                  text: "VOL"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.activeQuote ? Model.formatCompact(root.activeQuote.volume) : "—"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
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
                model: root.detailStats

                Column {
                  required property var modelData
                  width: (bodyColumn.width - Style.space(32)) / 3
                  spacing: Style.space(4)

                  Text {
                    text: modelData.label
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.value
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.title
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
