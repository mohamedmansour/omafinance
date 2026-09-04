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
  property string listChrome: "rows"
  property int settingsCursor: 0
  property int detailSection: 0
  property int detailActionIndex: 0

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentUrgent: bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.45)
  readonly property color upColor: Qt.rgba(0.22, 0.50, 0.30, 1)
  readonly property color downColor: Qt.rgba(0.62, 0.22, 0.22, 1)
  readonly property color upFill: Qt.rgba(upColor.r, upColor.g, upColor.b, 1)
  readonly property color downFill: Qt.rgba(downColor.r, downColor.g, downColor.b, 1)
  readonly property int refreshSeconds: Math.max(15, parseInt(setting("refreshSeconds", 60), 10) || 60)
  readonly property bool showOnBar: setting("showOnBar", true) !== false
  readonly property string barSection: {
    var s = String(setting("barSection", "right") || "right")
    if (s === "left" || s === "center" || s === "right") return s
    return "right"
  }
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
  readonly property var sessionQuote: quotes[detailSymbol] || rangeChart || activeQuote
  readonly property var detailMainPrice: {
    if (detailRange === "1D" && sessionQuote && sessionQuote.regularPrice != null)
      return sessionQuote.regularPrice
    return activeQuote ? activeQuote.price : null
  }
  readonly property var detailMainChange: {
    if (detailRange === "1D" && sessionQuote && sessionQuote.regularChangePercent != null)
      return sessionQuote.regularChangePercent
    return detailRangeChange
  }
  property var heldMainChange: null
  readonly property bool awaitingRangeChart: {
    if (view !== "detail" || !detailSymbol) return false
    if (detailQuote && detailQuote.chartRange === detailRange) return false
    if (detailRange === "1D" && quotes[detailSymbol]) return false
    return true
  }
  readonly property var shownMainChange: {
    if (awaitingRangeChart) return heldMainChange
    var n = Number(detailMainChange)
    if (detailMainChange != null && isFinite(n)) return detailMainChange
    return heldMainChange
  }
  readonly property bool showExtended: detailRange === "1D" && sessionQuote && sessionQuote.hasExtended === true
  readonly property string priceCaption: Model.rangeCaption(detailRange, sessionQuote)
  readonly property bool detailIsFavorite: Model.isFavorite(watchlist, detailSymbol)
  readonly property var detailActionIds: {
    var actions = ["favorite", "pin"]
    if (detailIsFavorite) actions.push("remove")
    return actions
  }
  readonly property int rowHeight: Style.space(56)

  onDetailMainChangeChanged: {
    if (awaitingRangeChart) return
    var n = Number(detailMainChange)
    if (detailMainChange != null && isFinite(n)) heldMainChange = detailMainChange
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    stateFile.reload()
    root.refresh()
    root.view = "list"
    root.clearSearch()
    root.cursorActive = root.watchlist.length > 0
    root.selectedIndex = 0
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    stateFile.reload()
    root.refresh()
    root.view = "list"
    root.cursorActive = false
    root.startSearch("")
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

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var existing
    for (existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (existing in values) entry[existing] = values[existing]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setShowOnBar(enabled) {
    persistSettings({ showOnBar: !!enabled })
  }

  function setRefreshSeconds(value) {
    var n = Math.max(15, Math.min(3600, parseInt(value, 10) || 60))
    persistSettings({ refreshSeconds: n })
  }

  function setBarSection(section) {
    var next = String(section || "right")
    if (next !== "left" && next !== "center" && next !== "right") return
    if (next === root.barSection) return
    persistSettings({ barSection: next })
    barMoveProc.command = ["omarchy", "bar", "move", root.moduleName, "--section", next]
    barMoveProc.running = true
  }

  function openSettings() {
    root.clearSearch()
    root.settingsCursor = 0
    root.view = "settings"
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
    heldMainChange = null
    detailQuote = null
    detailPage = ({})
    detailInsights = ({})
    view = "detail"
    searching = false
    detailSection = 0
    detailActionIndex = 0
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
    startChartFetch(true)
  }

  function startChartFetch(force) {
    if (!detailSymbol) return
    if (chartProc.running) {
      if (!force) return
      chartProc.running = false
    }
    chartFetchRange = detailRange
    chartProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.chartUrl(detailSymbol, chartFetchRange)]
    chartProc.running = true
  }

  function fetchDetail() {
    if (!detailSymbol) return
    startChartFetch(true)
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
    listChrome = "rows"
    searching = false
    searchQuery = ""
    suggestions = []
    suggestionIndex = 0
    searchDebounce.stop()
    if (searchField.text !== "") searchField.text = ""
    Qt.callLater(function() { if (root.opened && keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function startSearch(prefix) {
    listChrome = "search"
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

  function focusSearchChrome() {
    listChrome = "search"
    searching = true
    Qt.callLater(function() {
      searchField.forceActiveFocus()
      searchField.cursorPosition = String(searchField.text).length
    })
  }

  function focusGearChrome() {
    listChrome = "gear"
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function focusRowsChrome() {
    listChrome = "rows"
    cursorActive = (searching && suggestions.length > 0) || watchlist.length > 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
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
      if (next < 0) {
        focusSearchChrome()
        return
      }
      if (next >= suggestions.length) next = suggestions.length - 1
      suggestionIndex = next
      return
    }
    if (watchlist.length === 0) {
      if (dy < 0) focusSearchChrome()
      return
    }
    var nextRow = selectedIndex + dy
    if (nextRow < 0) {
      focusSearchChrome()
      return
    }
    if (nextRow >= watchlist.length) nextRow = watchlist.length - 1
    selectedIndex = nextRow
  }

  function activateCursor() {
    if (view === "settings") {
      if (settingsCursor === 0) setShowOnBar(!showOnBar)
      return
    }
    if (view === "detail") {
      if (detailSection !== 0) return
      var action = detailActionIds[detailActionIndex]
      if (action === "favorite") toggleFavorite(detailSymbol)
      else if (action === "pin") pinSymbol(detailSymbol)
      else if (action === "remove") {
        removeSymbol(detailSymbol)
        closeDetail()
      }
      return
    }
    if (listChrome === "gear") {
      openSettings()
      return
    }
    if (listChrome === "search") {
      commitSearch()
      return
    }
    if (searching && searchQuery.length > 0 && suggestions.length > 0) {
      var pick = suggestions[Math.max(0, Math.min(suggestionIndex, suggestions.length - 1))]
      if (pick) openDetail(pick.symbol)
      return
    }
    if (watchlist.length === 0) return
    openDetail(watchlist[selectedIndex])
  }

  function moveFocus(dx, dy) {
    if (view === "settings") {
      if (dy !== 0) settingsCursor = Math.max(0, Math.min(2, settingsCursor + dy))
      if (dx !== 0) {
        if (settingsCursor === 0) setShowOnBar(dx > 0)
        else if (settingsCursor === 1) setRefreshSeconds(refreshSeconds + dx * 15)
        else if (settingsCursor === 2) {
          var sections = ["left", "center", "right"]
          var i = sections.indexOf(barSection)
          if (i < 0) i = 2
          i = Math.max(0, Math.min(2, i + dx))
          setBarSection(sections[i])
        }
      }
      return
    }
    if (view === "detail") {
      if (dy !== 0) {
        detailSection = Math.max(0, Math.min(1, detailSection + dy))
        return
      }
      if (dx === 0) return
      if (detailSection === 0) {
        var n = detailActionIds.length
        if (n > 0) detailActionIndex = (detailActionIndex + dx + n) % n
        return
      }
      var ranges = detailRanges
      var idx = ranges.indexOf(detailRange)
      if (idx < 0) idx = 0
      idx = (idx + dx + ranges.length) % ranges.length
      setDetailRange(ranges[idx])
      return
    }
    if (listChrome === "gear") {
      if (dx < 0) focusSearchChrome()
      else if (dy > 0) focusRowsChrome()
      return
    }
    if (dx !== 0) return
    if (dy !== 0) moveCursor(dy)
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
    id: barMoveProc
  }

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
        var expected = Model.chartSpec(root.detailRange).range
        if (parsed.yahooRange && parsed.yahooRange !== expected) return
        parsed.chartRange = root.detailRange
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
    running: root.showOnBar && !root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: liveTimer
    interval: 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      if (root.view === "detail" && root.detailRange === "1D")
        root.startChartFetch(false)
    }
  }

  Timer {
    id: pinRotateTimer
    interval: 5000
    running: root.showOnBar && (root.pinned || []).length > 1
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
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveFocus(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.view === "detail") root.closeDetail()
        else if (root.view === "settings") root.view = "list"
        else if (root.listChrome === "gear") root.focusSearchChrome()
        else if (root.searching) root.clearSearch()
        else root.close()
      }
      onDeleteRequested: {
        if (root.view !== "list" || root.searching || root.watchlist.length === 0) return
        root.removeSymbol(root.watchlist[root.selectedIndex])
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.view === "settings") return
        if (root.view === "detail") {
          if (t === "f" || t === "F") root.toggleFavorite(root.detailSymbol)
          else if (t === "p" || t === "P") root.pinSymbol(root.detailSymbol)
          else if ((t === "x" || t === "X") && root.detailIsFavorite) {
            root.removeSymbol(root.detailSymbol)
            root.closeDetail()
          }
          return
        }
        if (t === "/" || t === "?") { root.startSearch(""); return }
        if (t === "s" || t === "S") { root.openSettings(); return }
        if (t === "p" || t === "P") {
          if (root.searching && root.suggestions.length > 0)
            root.toggleFavorite(root.suggestions[root.suggestionIndex].symbol)
          else if (root.watchlist.length > 0) root.pinSymbol(root.watchlist[root.selectedIndex])
          return
        }
        if (t === "f" || t === "F") {
          if (root.searching && root.suggestions.length > 0)
            root.toggleFavorite(root.suggestions[root.suggestionIndex].symbol)
          else if (root.watchlist.length > 0) root.toggleFavorite(root.watchlist[root.selectedIndex])
          return
        }
        if (t === "x" || t === "X") return
        if (root.listChrome === "gear") return
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

            Item {
              width: parent.width
              height: searchField.implicitHeight

              TextField {
                id: searchField
                anchors.left: parent.left
                anchors.right: gearBtn.left
                anchors.rightMargin: Style.space(8)
                placeholderText: "Search tickers…"
                hasCursor: root.listChrome === "search" && !activeFocus
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
                  root.focusRowsChrome()
                  event.accepted = true
                } else if (event.key === Qt.Key_Right && searchField.cursorPosition >= String(searchField.text).length) {
                  root.focusGearChrome()
                  event.accepted = true
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitSearch()
                  event.accepted = true
                }
              }
              }

              PanelActionButton {
                id: gearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf013"
                tooltipText: "Settings"
                foreground: root.dim
                fontFamily: root.contentFontFamily
                hasCursor: root.listChrome === "gear"
                bordered: root.listChrome === "gear"
                onClicked: root.openSettings()
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

              Column {
                visible: root.watchlist.length === 0
                width: parent.width
                spacing: Style.space(8)
                topPadding: Style.space(36)

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "No favorites yet"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: "Search for a ticker, then Favorite it to add it to your watchlist."
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.view === "settings"

            Text {
              text: "‹ Watchlist"
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body

              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.view = "list"
              }
            }

            Text {
              text: "Settings"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Toggle {
              width: parent.width
              label: "Show ticker on bar"
              description: "When off, the bar shows a compact icon and quotes are fetched only while this panel is open."
              checked: root.showOnBar
              hasCursor: root.settingsCursor === 0
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.setShowOnBar(!root.showOnBar)
            }

            NumberField {
              width: parent.width
              label: "Background refresh (seconds)"
              value: root.refreshSeconds
              from: 15
              to: 3600
              stepSize: 15
              hasCursor: root.settingsCursor === 1
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onModified: function(v) { root.setRefreshSeconds(v) }
            }

            Text {
              text: "Bar position"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ButtonGroup {
              width: parent.width
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              value: root.barSection
              focusable: false
              cursorIndex: root.settingsCursor === 2 ? ["left", "center", "right"].indexOf(root.barSection) : -1
              options: [
                { value: "left", label: "Left" },
                { value: "center", label: "Center" },
                { value: "right", label: "Right" }
              ]
              onChanged: function(v) { root.setBarSection(v) }
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
                  hasCursor: root.detailSection === 0 && root.detailActionIndex === 0
                  foreground: root.detailIsFavorite ? root.contentForeground : root.dim
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.toggleFavorite(root.detailSymbol)
                }
                Button {
                  text: Model.isPinned(root.pinned, root.detailSymbol) ? "Pinned" : "Pin"
                  hasCursor: root.detailSection === 0 && root.detailActionIndex === 1
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
                  hasCursor: root.detailSection === 0 && root.detailActionIndex === 2
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
              width: parent.width
              spacing: Style.space(16)

              Column {
                width: root.showExtended ? (parent.width - parent.spacing) / 2 : parent.width
                spacing: Style.space(6)

                Row {
                  spacing: Style.space(12)

                  Text {
                    textFormat: Text.PlainText
                    text: root.activeQuote ? Model.formatPrice(root.detailMainPrice, root.activeQuote.currency, root.activeQuote.priceHint) : "—"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(6)
                    color: root.pillFill(root.shownMainChange)
                    implicitWidth: detailChange.implicitWidth + Style.space(14)
                    implicitHeight: detailChange.implicitHeight + Style.space(6)

                    Text {
                      id: detailChange
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: Model.formatPercent(root.shownMainChange)
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }

                Text {
                  visible: root.priceCaption !== ""
                  text: root.priceCaption
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Column {
                visible: root.showExtended
                width: (parent.width - parent.spacing) / 2
                spacing: Style.space(6)

                Row {
                  spacing: Style.space(12)

                  Text {
                    textFormat: Text.PlainText
                    text: root.sessionQuote ? Model.formatPrice(root.sessionQuote.extendedPrice, root.sessionQuote.currency, root.sessionQuote.priceHint) : "—"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Style.space(6)
                    color: root.pillFill(root.sessionQuote ? root.sessionQuote.extendedChangePercent : null)
                    implicitWidth: extChange.implicitWidth + Style.space(14)
                    implicitHeight: extChange.implicitHeight + Style.space(6)

                    Text {
                      id: extChange
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: root.sessionQuote ? Model.formatPercent(root.sessionQuote.extendedChangePercent) : "—"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }

                Text {
                  text: Model.extendedLabel(root.sessionQuote)
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
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
