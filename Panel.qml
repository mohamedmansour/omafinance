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
    property string chartFetchSymbol: ""
    property string chartFetchRange: ""
    property string insightsFetchSymbol: ""
    property string quotePageFetchSymbol: ""
    property bool quoteRefreshPending: false
    property int quoteFailureCount: 0
    property string quoteError: ""
    property double quotesUpdatedAt: 0
    property int chartFailureCount: 0
    property string chartError: ""
    property double chartUpdatedAt: 0
    property int insightsFailureCount: 0
    property string insightsError: ""
    property bool insightsLoaded: false
    property int quotePageFailureCount: 0
    property string quotePageError: ""
    property bool quotePageLoaded: false
    property var detailPage: ({})
    property var detailInsights: ({})
    property string searchQuery: ""
    property var suggestions: []
    property int suggestionIndex: 0
    property string searchPendingQuery: ""
    property string searchActiveQuery: ""
    property string searchError: ""
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
    readonly property string changeStyle: {
        var style = String(setting("changeStyle", "percent") || "percent");
        return style === "dollars" ? style : "percent";
    }
    readonly property bool legacyShowOnBar: setting("showOnBar", true) !== false
    readonly property bool showTicker: setting("showTicker", legacyShowOnBar) !== false
    readonly property bool showPrice: setting("showPrice", legacyShowOnBar) !== false
    readonly property bool showChange: setting("showChange", legacyShowOnBar) !== false
    readonly property bool showLastUpdated: setting("showLastUpdated", false) === true
    readonly property bool showBarData: showTicker || showPrice || showChange
    readonly property bool showBarQuote: showBarData
    readonly property int changeStyleSettingsIndex: 3
    readonly property int refreshSettingsIndex: showChange ? 4 : 3
    readonly property int lastUpdatedSettingsIndex: showChange ? 5 : 4
    readonly property int barSectionSettingsIndex: showChange ? 6 : 5
    readonly property int settingsLastIndex: barSectionSettingsIndex
    readonly property int backgroundRefreshMs: Model.backoffDelay(refreshSeconds * 1000, quoteFailureCount, 3600000)
    readonly property int liveRefreshMs: Model.backoffDelay(2000, quoteFailureCount, 60000)
    readonly property int chartRefreshMs: Model.backoffDelay(15000, chartFailureCount, 120000)
    readonly property int insightsRetryMs: Model.backoffDelay(5000, insightsFailureCount, 120000)
    readonly property int quotePageRetryMs: Model.backoffDelay(5000, quotePageFailureCount, 120000)
    readonly property bool searchRunning: searchProc.running
    readonly property string barSection: {
        var s = String(setting("barSection", "right") || "right");
        if (s === "left" || s === "center" || s === "right")
            return s;
        return "right";
    }
    readonly property string barSymbol: Model.barSymbol(pinned, watchlist, pinIndex)
    readonly property var pinnedQuote: quotes[barSymbol] || null
    readonly property string label: Model.barLabel(barSymbol, pinnedQuote, false, showTicker, showPrice, showChange, changeStyle)
    readonly property string verticalLabel: Model.barLabel(barSymbol, pinnedQuote, true, showTicker, showPrice, showChange, changeStyle)
    readonly property string labelTone: Model.barLabelTone(pinnedQuote, showTicker, showPrice, showChange, changeStyle)
    readonly property string quoteStatusText: {
        var hasQuotes = Object.keys(quotes || {}).length > 0;
        if (quoteProc.running)
            return hasQuotes ? "" : "Loading quotes…";
        if (quoteError) {
            var suffix = showLastUpdated && quotesUpdatedAt > 0 ? " · Last updated " + timeLabel(quotesUpdatedAt) : "";
            return quoteError + suffix;
        }
        return showLastUpdated && quotesUpdatedAt > 0 ? "Updated " + timeLabel(quotesUpdatedAt) : "";
    }
    readonly property string chartStatusText: {
        var currentFetch = chartFetchSymbol === detailSymbol && chartFetchRange === detailRange;
        if (chartProc.running && currentFetch)
            return rangeChart ? "" : "Loading chart…";
        if (chartError)
            return chartError;
        return showLastUpdated && chartUpdatedAt > 0 && detailQuote ? "Last updated " + timeLabel(chartUpdatedAt) : "";
    }
    readonly property bool detailDataLoading: {
        var loadingInsights = insightsProc.running && insightsFetchSymbol === detailSymbol && !insightsLoaded;
        var loadingPage = quotePageProc.running && quotePageFetchSymbol === detailSymbol && !quotePageLoaded;
        return loadingInsights || loadingPage;
    }
    readonly property bool detailDataHasError: insightsError !== "" || quotePageError !== ""
    readonly property string detailDataStatusText: {
        var errors = [];
        if (insightsError)
            errors.push(insightsError);
        if (quotePageError)
            errors.push(quotePageError);
        return errors.join(" · ");
    }
    readonly property var detailRanges: Model.chartRanges()
    readonly property var activeQuote: quotes[detailSymbol] || detailQuote
    readonly property var rangeChart: {
        if (detailQuote && detailQuote.chartRange === detailRange)
            return detailQuote;
        if (detailRange === "1D" && quotes[detailSymbol])
            return quotes[detailSymbol];
        return null;
    }
    readonly property var detailStats: Model.buildDetailStats(activeQuote, detailPage, detailInsights)
    readonly property var detailRangeChange: Model.rangeChangePercent(rangeChart, detailRange)
    readonly property var detailRangeChangeAmount: Model.rangeChangeAmount(rangeChart, detailRange)
    readonly property var sessionQuote: quotes[detailSymbol] || rangeChart || activeQuote
    readonly property var detailMainPrice: {
        if (detailRange === "1D" && sessionQuote && sessionQuote.regularPrice != null)
            return sessionQuote.regularPrice;
        return activeQuote ? activeQuote.price : null;
    }
    readonly property var detailMainChange: {
        if (detailRange === "1D" && sessionQuote && sessionQuote.regularChangePercent != null)
            return sessionQuote.regularChangePercent;
        return detailRangeChange;
    }
    readonly property var detailMainChangeAmount: {
        if (detailRange === "1D" && sessionQuote && sessionQuote.regularPrice != null && sessionQuote.previousClose != null)
            return sessionQuote.regularPrice - sessionQuote.previousClose;
        return detailRangeChangeAmount;
    }
    property var heldMainChange: null
    property var heldMainChangeAmount: null
    readonly property bool awaitingRangeChart: {
        if (view !== "detail" || !detailSymbol)
            return false;
        if (detailQuote && detailQuote.chartRange === detailRange)
            return false;
        if (detailRange === "1D" && quotes[detailSymbol])
            return false;
        return true;
    }
    readonly property var shownMainChange: {
        if (awaitingRangeChart)
            return heldMainChange;
        var n = Number(detailMainChange);
        if (detailMainChange != null && isFinite(n))
            return detailMainChange;
        return heldMainChange;
    }
    readonly property var shownMainChangeAmount: {
        if (awaitingRangeChart)
            return heldMainChangeAmount;
        var n = Number(detailMainChangeAmount);
        if (detailMainChangeAmount != null && isFinite(n))
            return detailMainChangeAmount;
        return heldMainChangeAmount;
    }
    readonly property bool showExtended: detailRange === "1D" && sessionQuote && sessionQuote.hasExtended === true
    readonly property var extendedChangeAmount: {
        if (!sessionQuote || sessionQuote.extendedPrice == null || sessionQuote.regularPrice == null)
            return null;
        return sessionQuote.extendedPrice - sessionQuote.regularPrice;
    }
    readonly property string priceCaption: Model.rangeCaption(detailRange, sessionQuote)
    readonly property bool detailIsFavorite: Model.isFavorite(watchlist, detailSymbol)
    readonly property var detailActionIds: {
        var actions = ["favorite", "pin"];
        if (detailIsFavorite)
            actions.push("remove");
        return actions;
    }
    readonly property int rowHeight: Style.space(56)

    onDetailMainChangeChanged: {
        if (awaitingRangeChart)
            return;
        var n = Number(detailMainChange);
        if (detailMainChange != null && isFinite(n))
            heldMainChange = detailMainChange;
    }

    onDetailMainChangeAmountChanged: {
        if (awaitingRangeChart)
            return;
        var n = Number(detailMainChangeAmount);
        if (detailMainChangeAmount != null && isFinite(n))
            heldMainChangeAmount = detailMainChangeAmount;
    }

    function open() {
        openedFromHotkey = false;
        setCenterHoverRevealSuppressed(false);
        root.view = "list";
        root.clearSearch();
        root.cursorActive = root.watchlist.length > 0;
        root.selectedIndex = 0;
        root.controller.show();
        scheduleOpenRefresh();
    }

    function openFromHotkey() {
        openedFromHotkey = true;
        root.view = "list";
        root.cursorActive = false;
        root.controller.show();
        root.startSearch("");
        scheduleOpenRefresh();
        Qt.callLater(function () {
            if (root.opened)
                setCenterHoverRevealSuppressed(true);
        });
    }

    function close() {
        setCenterHoverRevealSuppressed(false);
        root.clearSearch();
        root.view = "list";
        root.controller.hide();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);
        return false;
    }

    function setCenterHoverRevealSuppressed(value) {
        if (root.bar && "centerHoverRevealSuppressed" in root.bar)
            root.bar.centerHoverRevealSuppressed = value;
    }

    function toneColor(pct) {
        var tone = Model.changeTone(pct);
        if (tone === "up")
            return upColor;
        if (tone === "down")
            return downColor;
        return dim;
    }

    function pillFill(pct) {
        var tone = Model.changeTone(pct);
        if (tone === "up")
            return upFill;
        if (tone === "down")
            return downFill;
        return Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.18);
    }

    function timeLabel(timestamp) {
        var date = new Date(Number(timestamp) || 0);
        var hours = date.getHours();
        var minutes = date.getMinutes();
        var seconds = date.getSeconds();
        function pad(value) {
            return value < 10 ? "0" + value : String(value);
        }
        return pad(hours) + ":" + pad(minutes) + ":" + pad(seconds);
    }

    function clampSelected() {
        if (watchlist.length === 0) {
            selectedIndex = 0;
            return;
        }
        if (selectedIndex < 0)
            selectedIndex = 0;
        if (selectedIndex >= watchlist.length)
            selectedIndex = watchlist.length - 1;
    }

    function persist() {
        stateFile.setText(Model.serializeState(watchlist, pinned, detailRange));
    }

    function persistSettings(values) {
        var entry = {
            id: root.moduleName
        };
        var existing;
        for (existing in root.settings)
            if (existing !== "id")
                entry[existing] = root.settings[existing];
        for (existing in values)
            entry[existing] = values[existing];
        root.settings = entry;
        if (root.hostWidget && "settings" in root.hostWidget)
            root.hostWidget.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
    }

    function setShowTicker(enabled) {
        persistSettings({
            showTicker: !!enabled
        });
        if (enabled)
            scheduleBarRefresh();
    }

    function setShowPrice(enabled) {
        persistSettings({
            showPrice: !!enabled
        });
        if (enabled)
            scheduleBarRefresh();
    }

    function setShowChange(enabled) {
        persistSettings({
            showChange: !!enabled
        });
        if (enabled)
            scheduleBarRefresh();
    }

    function setShowLastUpdated(enabled) {
        persistSettings({
            showLastUpdated: !!enabled
        });
    }

    function setRefreshSeconds(value) {
        var n = Math.max(15, Math.min(3600, parseInt(value, 10) || 60));
        persistSettings({
            refreshSeconds: n
        });
    }

    function setChangeStyle(style) {
        var next = String(style || "percent");
        if (next !== "percent" && next !== "dollars")
            return;
        persistSettings({
            changeStyle: next
        });
    }

    function setBarSection(section) {
        var next = String(section || "right");
        if (next !== "left" && next !== "center" && next !== "right")
            return;
        if (next === root.barSection)
            return;
        persistSettings({
            barSection: next
        });
        barMoveProc.command = ["omarchy", "bar", "move", root.moduleName, "--section", next];
        barMoveProc.running = true;
    }

    function openSettings() {
        root.clearSearch();
        root.settingsCursor = 0;
        root.view = "settings";
    }

    function applyState(raw) {
        var state = Model.parseState(raw);
        var before = (watchlist || []).join("\n");
        var after = (state.watchlist || []).join("\n");
        watchlist = state.watchlist;
        pinned = state.pinned;
        if (state.detailRange)
            detailRange = state.detailRange;
        clampSelected();
        if (before !== after)
            Qt.callLater(refresh);
    }

    function refresh() {
        if (watchlist.length === 0) {
            quoteRefreshPending = false;
            return;
        }
        if (quoteProc.running) {
            quoteRefreshPending = true;
            return;
        }
        quoteRefreshPending = false;
        quoteProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.sparkUrl(watchlist)];
        quoteProc.running = true;
    }

    function scheduleOpenRefresh() {
        Qt.callLater(function () {
            if (root.opened && !quoteProc.running)
                root.refresh();
        });
    }

    function scheduleBarRefresh() {
        Qt.callLater(function () {
            if (root.showBarData && !quoteProc.running)
                root.refresh();
        });
    }

    function addSymbol(symbol) {
        var next = Model.addSymbol(watchlist, symbol);
        if (next.length === watchlist.length) {
            var already = Model.normalizeSymbol(symbol);
            if (already) {
                selectedIndex = next.indexOf(already);
                cursorActive = true;
            }
            return;
        }
        watchlist = next;
        selectedIndex = next.length - 1;
        cursorActive = true;
        persist();
        refresh();
    }

    function removeSymbol(symbol) {
        var next = Model.removeSymbol(watchlist, symbol);
        watchlist = next;
        pinned = Model.parsePinned(pinned, next);
        clampSelected();
        persist();
    }

    function pinSymbol(symbol) {
        var next = Model.normalizeSymbol(symbol);
        if (!next)
            return;
        var list = Model.addSymbol(watchlist, next);
        watchlist = list;
        pinned = Model.togglePinned(pinned, list, next);
        persist();
        refresh();
    }

    function toggleFavorite(symbol) {
        var next = Model.normalizeSymbol(symbol);
        if (!next)
            return;
        if (Model.isFavorite(watchlist, next))
            removeSymbol(next);
        else
            addSymbol(next);
    }

    function prepareDetail(symbol) {
        var next = Model.normalizeSymbol(symbol);
        if (!next)
            return false;
        if (detailSymbol === next)
            return true;
        detailSymbol = next;
        heldMainChange = null;
        detailQuote = null;
        chartFailureCount = 0;
        chartError = "";
        chartUpdatedAt = 0;
        insightsFailureCount = 0;
        insightsError = "";
        insightsLoaded = false;
        quotePageFailureCount = 0;
        quotePageError = "";
        quotePageLoaded = false;
        detailPage = ({});
        detailInsights = ({});
        fetchDetail();
        return true;
    }

    function prefetchDetail(symbol) {
        prepareDetail(symbol);
    }

    function openDetail(symbol) {
        if (!prepareDetail(symbol))
            return;
        view = "detail";
        searching = false;
        detailSection = 0;
        detailActionIndex = 0;
    }

    function closeDetail() {
        view = "list";
        detailSymbol = "";
        detailQuote = null;
        Qt.callLater(function () {
            if (keyCatcher)
                keyCatcher.forceActiveFocus();
        });
    }

    function setDetailRange(range) {
        var next = Model.normalizeRange(range);
        if (detailRange === next)
            return;
        detailRange = next;
        persist();
        if (!detailSymbol)
            return;
        chartFailureCount = 0;
        chartError = "";
        chartUpdatedAt = 0;
        startChartFetch();
    }

    function startChartFetch() {
        if (!detailSymbol)
            return;
        if (chartProc.running)
            return;
        chartFetchSymbol = detailSymbol;
        chartFetchRange = detailRange;
        chartError = "";
        chartProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.chartUrl(chartFetchSymbol, chartFetchRange)];
        chartProc.running = true;
    }

    function fetchDetail() {
        if (!detailSymbol)
            return;
        startChartFetch();
        fetchInsights();
        fetchQuotePage();
    }

    function fetchInsights() {
        if (!detailSymbol)
            return;
        if (insightsProc.running)
            return;
        insightsFetchSymbol = detailSymbol;
        insightsError = "";
        insightsProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", Model.insightsUrl(insightsFetchSymbol)];
        insightsProc.running = true;
    }

    function fetchQuotePage() {
        if (!detailSymbol)
            return;
        if (quotePageProc.running)
            return;
        quotePageFetchSymbol = detailSymbol;
        quotePageError = "";
        quotePageProc.command = ["curl", "-fsS", "--compressed", "--max-time", "12", "-A", "Mozilla/5.0", Model.quotePageUrl(quotePageFetchSymbol)];
        quotePageProc.running = true;
    }

    function clearSearch() {
        listChrome = "rows";
        searching = false;
        searchQuery = "";
        suggestions = [];
        suggestionIndex = 0;
        searchDebounce.stop();
        if (listView.field.text !== "")
            listView.field.text = "";
        Qt.callLater(function () {
            if (root.opened && keyCatcher)
                keyCatcher.forceActiveFocus();
        });
    }

    function startSearch(prefix) {
        listChrome = "search";
        searching = true;
        Qt.callLater(function () {
            listView.field.forceActiveFocus();
            if (prefix) {
                listView.field.text = prefix;
                listView.field.cursorPosition = listView.field.text.length;
            } else {
                listView.field.selectAll();
            }
        });
    }

    function focusSearchChrome() {
        listChrome = "search";
        searching = true;
        Qt.callLater(function () {
            listView.field.forceActiveFocus();
            listView.field.cursorPosition = String(listView.field.text).length;
        });
    }

    function focusGearChrome() {
        listChrome = "gear";
        Qt.callLater(function () {
            if (keyCatcher)
                keyCatcher.forceActiveFocus();
        });
    }

    function focusRowsChrome() {
        listChrome = "rows";
        cursorActive = (searching && suggestions.length > 0) || watchlist.length > 0;
        Qt.callLater(function () {
            if (keyCatcher)
                keyCatcher.forceActiveFocus();
        });
    }

    function requestSearch() {
        var query = listView.field.text.replace(/^\s+|\s+$/g, "");
        searchQuery = query;
        if (query.length < 1) {
            suggestions = [];
            searchPendingQuery = "";
            searchError = "";
            return;
        }
        searchError = "";
        searchPendingQuery = query;
        if (!searchProc.running)
            startSearchFetch();
    }

    function startSearchFetch() {
        if (!searching || !searchPendingQuery)
            return;
        searchActiveQuery = searchPendingQuery;
        searchProc.command = ["curl", "-fsS", "--max-time", "5", "-A", "Mozilla/5.0", Model.searchUrl(searchActiveQuery)];
        searchProc.running = true;
    }

    function commitSearch() {
        if (suggestions.length > 0) {
            var pick = suggestions[Math.max(0, Math.min(suggestionIndex, suggestions.length - 1))];
            if (pick)
                openDetail(pick.symbol);
            return;
        }
        var typed = Model.normalizeSymbol(searchQuery || listView.field.text);
        if (typed)
            openDetail(typed);
    }

    function scheduleSearch() {
        searchDebounce.restart();
    }

    function moveCursor(dy) {
        cursorActive = true;
        if (searching && suggestions.length > 0) {
            var next = suggestionIndex + dy;
            if (next < 0) {
                focusSearchChrome();
                return;
            }
            if (next >= suggestions.length)
                next = suggestions.length - 1;
            suggestionIndex = next;
            return;
        }
        if (watchlist.length === 0) {
            if (dy < 0)
                focusSearchChrome();
            return;
        }
        var nextRow = selectedIndex + dy;
        if (nextRow < 0) {
            focusSearchChrome();
            return;
        }
        if (nextRow >= watchlist.length)
            nextRow = watchlist.length - 1;
        selectedIndex = nextRow;
    }

    function activateCursor() {
        if (view === "settings") {
            if (settingsCursor === 0)
                setShowTicker(!showTicker);
            else if (settingsCursor === 1)
                setShowPrice(!showPrice);
            else if (settingsCursor === 2)
                setShowChange(!showChange);
            else if (settingsCursor === lastUpdatedSettingsIndex)
                setShowLastUpdated(!showLastUpdated);
            return;
        }
        if (view === "detail") {
            if (detailSection !== 0)
                return;
            var action = detailActionIds[detailActionIndex];
            if (action === "favorite")
                toggleFavorite(detailSymbol);
            else if (action === "pin")
                pinSymbol(detailSymbol);
            else if (action === "remove") {
                removeSymbol(detailSymbol);
                closeDetail();
            }
            return;
        }
        if (listChrome === "gear") {
            openSettings();
            return;
        }
        if (listChrome === "search") {
            commitSearch();
            return;
        }
        if (searching && searchQuery.length > 0 && suggestions.length > 0) {
            var pick = suggestions[Math.max(0, Math.min(suggestionIndex, suggestions.length - 1))];
            if (pick)
                openDetail(pick.symbol);
            return;
        }
        if (watchlist.length === 0)
            return;
        openDetail(watchlist[selectedIndex]);
    }

    function moveFocus(dx, dy) {
        if (view === "settings") {
            if (dy !== 0)
                settingsCursor = Math.max(0, Math.min(settingsLastIndex, settingsCursor + dy));
            if (dx !== 0) {
                if (settingsCursor === 0)
                    setShowTicker(dx > 0);
                else if (settingsCursor === 1)
                    setShowPrice(dx > 0);
                else if (settingsCursor === 2)
                    setShowChange(dx > 0);
                else if (showChange && settingsCursor === changeStyleSettingsIndex)
                    setChangeStyle(dx > 0 ? "dollars" : "percent");
                else if (settingsCursor === refreshSettingsIndex)
                    setRefreshSeconds(refreshSeconds + dx * 15);
                else if (settingsCursor === lastUpdatedSettingsIndex)
                    setShowLastUpdated(dx > 0);
                else if (settingsCursor === barSectionSettingsIndex) {
                    var sections = ["left", "center", "right"];
                    var i = sections.indexOf(barSection);
                    if (i < 0)
                        i = 2;
                    i = Math.max(0, Math.min(2, i + dx));
                    setBarSection(sections[i]);
                }
            }
            return;
        }
        if (view === "detail") {
            if (dy !== 0) {
                detailSection = Math.max(0, Math.min(1, detailSection + dy));
                return;
            }
            if (dx === 0)
                return;
            if (detailSection === 0) {
                var n = detailActionIds.length;
                if (n > 0)
                    detailActionIndex = (detailActionIndex + dx + n) % n;
                return;
            }
            var ranges = detailRanges;
            var idx = ranges.indexOf(detailRange);
            if (idx < 0)
                idx = 0;
            idx = (idx + dx + ranges.length) % ranges.length;
            setDetailRange(ranges[idx]);
            return;
        }
        if (listChrome === "gear") {
            if (dx < 0)
                focusSearchChrome();
            else if (dy > 0)
                focusRowsChrome();
            return;
        }
        if (dx !== 0)
            return;
        if (dy !== 0)
            moveCursor(dy);
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/finance.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(text())
        onLoadFailed: {
            root.applyState("");
            if (mkdirProc.running)
                root.seedOnReady = true;
            else
                root.persist();
        }
        onFileChanged: reload()
    }

    property bool seedOnReady: false

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/settings"]
        onExited: {
            if (root.seedOnReady) {
                root.seedOnReady = false;
                root.persist();
            }
        }
    }

    Component.onCompleted: mkdirProc.running = true

    Process {
        id: barMoveProc
    }

    Process {
        id: quoteProc
        onExited: function (exitCode) {
            var raw = String(quoteStdout.text || "").trim();
            var parsed = exitCode === 0 && raw ? Model.parseSpark(raw) : ({});
            if (Object.keys(parsed).length > 0) {
                root.quotes = Model.mergeQuotes(root.quotes, parsed);
                root.quoteFailureCount = 0;
                root.quoteError = "";
                root.quotesUpdatedAt = Date.now();
            } else {
                root.quoteFailureCount = Math.min(10, root.quoteFailureCount + 1);
                root.quoteError = "Quotes unavailable";
            }
            if (root.quoteRefreshPending)
                Qt.callLater(root.refresh);
        }
        stdout: StdioCollector {
            id: quoteStdout
            waitForEnd: true
        }
    }

    Process {
        id: searchProc
        onExited: function (exitCode) {
            if (root.searching && root.searchActiveQuery === root.searchQuery) {
                if (exitCode === 0) {
                    root.suggestions = Model.parseSearch(searchStdout.text);
                    root.searchError = "";
                } else {
                    root.suggestions = [];
                    root.searchError = "Search unavailable";
                }
                root.suggestionIndex = 0;
            }
            if (root.searching && root.searchPendingQuery && root.searchPendingQuery !== root.searchActiveQuery)
                Qt.callLater(root.startSearchFetch);
        }
        stdout: StdioCollector {
            id: searchStdout
            waitForEnd: true
        }
    }

    Process {
        id: chartProc
        onExited: function (exitCode) {
            var currentFetch = root.chartFetchSymbol === root.detailSymbol && root.chartFetchRange === root.detailRange;
            if (currentFetch) {
                var parsed = exitCode === 0 ? Model.parseChart(chartStdout.text) : null;
                var expected = Model.chartSpec(root.detailRange).range;
                var valid = parsed && parsed.symbol === root.detailSymbol && (!parsed.yahooRange || parsed.yahooRange === expected);
                if (valid) {
                    parsed.chartRange = root.detailRange;
                    root.detailQuote = parsed;
                    root.chartFailureCount = 0;
                    root.chartError = "";
                    root.chartUpdatedAt = Date.now();
                } else {
                    root.chartFailureCount = Math.min(10, root.chartFailureCount + 1);
                    root.chartError = "Chart unavailable";
                }
            }
            if (root.detailSymbol && (root.chartFetchSymbol !== root.detailSymbol || root.chartFetchRange !== root.detailRange))
                Qt.callLater(root.startChartFetch);
        }
        stdout: StdioCollector {
            id: chartStdout
            waitForEnd: true
        }
    }

    Process {
        id: insightsProc
        onExited: function (exitCode) {
            var currentFetch = root.insightsFetchSymbol === root.detailSymbol;
            if (currentFetch) {
                var raw = String(insightsStdout.text || "").trim();
                if (exitCode === 0 && Model.isInsightsResponse(raw)) {
                    root.detailInsights = Model.parseInsights(raw);
                    root.insightsFailureCount = 0;
                    root.insightsError = "";
                    root.insightsLoaded = true;
                } else {
                    root.insightsFailureCount = Math.min(10, root.insightsFailureCount + 1);
                    root.insightsError = "Insights unavailable";
                }
            }
            if (root.detailSymbol && root.insightsFetchSymbol !== root.detailSymbol)
                Qt.callLater(root.fetchInsights);
        }
        stdout: StdioCollector {
            id: insightsStdout
            waitForEnd: true
        }
    }

    Process {
        id: quotePageProc
        onExited: function (exitCode) {
            var currentFetch = root.quotePageFetchSymbol === root.detailSymbol;
            if (currentFetch) {
                var raw = String(quotePageStdout.text || "").trim();
                if (exitCode === 0 && raw) {
                    root.detailPage = Model.parseQuotePage(raw);
                    root.quotePageFailureCount = 0;
                    root.quotePageError = "";
                    root.quotePageLoaded = true;
                } else {
                    root.quotePageFailureCount = Math.min(10, root.quotePageFailureCount + 1);
                    root.quotePageError = "Fundamentals unavailable";
                }
            }
            if (root.detailSymbol && root.quotePageFetchSymbol !== root.detailSymbol)
                Qt.callLater(root.fetchQuotePage);
        }
        stdout: StdioCollector {
            id: quotePageStdout
            waitForEnd: true
        }
    }

    Timer {
        id: searchDebounce
        interval: 300
        onTriggered: root.requestSearch()
    }

    Timer {
        id: refreshTimer
        interval: root.backgroundRefreshMs
        running: root.showBarQuote && !root.opened
        repeat: true
        onTriggered: if (!quoteProc.running)
            root.refresh()
    }

    Timer {
        id: liveTimer
        interval: root.liveRefreshMs
        running: root.opened
        repeat: true
        onTriggered: if (!quoteProc.running)
            root.refresh()
    }

    Timer {
        id: chartLiveTimer
        interval: root.chartRefreshMs
        running: root.opened && root.view === "detail" && root.detailRange === "1D"
        repeat: true
        onTriggered: root.startChartFetch()
    }

    Timer {
        interval: root.insightsRetryMs
        running: root.opened && root.view === "detail" && root.insightsError !== ""
        repeat: false
        onTriggered: root.fetchInsights()
    }

    Timer {
        interval: root.quotePageRetryMs
        running: root.opened && root.view === "detail" && root.quotePageError !== ""
        repeat: false
        onTriggered: root.fetchQuotePage()
    }

    Timer {
        id: pinRotateTimer
        interval: 5000
        running: root.showBarData && (root.pinned || []).length > 1
        repeat: true
        onTriggered: root.pinIndex = root.pinIndex + 1
    }

    IpcHandler {
        target: root.ipcTarget

        function open(): void {
            root.openFromHotkey();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.openFromHotkey();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }
        function refresh(): void {
            root.refresh();
        }
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
            blocked: listView.field.activeFocus
            onMoveRequested: function (dx, dy) {
                root.moveFocus(dx, dy);
            }
            onActivateRequested: root.activateCursor()
            onCloseRequested: {
                if (root.view === "detail")
                    root.closeDetail();
                else if (root.view === "settings")
                    root.view = "list";
                else if (root.listChrome === "gear")
                    root.focusSearchChrome();
                else if (root.searching)
                    root.clearSearch();
                else
                    root.close();
            }
            onDeleteRequested: {
                if (root.view !== "list" || root.searching || root.watchlist.length === 0)
                    return;
                root.removeSymbol(root.watchlist[root.selectedIndex]);
            }
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (t) {
                if (root.view === "settings")
                    return;
                if (root.view === "detail") {
                    if (t === "f" || t === "F")
                        root.toggleFavorite(root.detailSymbol);
                    else if (t === "p" || t === "P")
                        root.pinSymbol(root.detailSymbol);
                    else if ((t === "x" || t === "X") && root.detailIsFavorite) {
                        root.removeSymbol(root.detailSymbol);
                        root.closeDetail();
                    }
                    return;
                }
                if (t === "/" || t === "?") {
                    root.startSearch("");
                    return;
                }
                if (t === "s" || t === "S") {
                    root.openSettings();
                    return;
                }
                if (t === "p" || t === "P") {
                    if (root.searching && root.suggestions.length > 0)
                        root.toggleFavorite(root.suggestions[root.suggestionIndex].symbol);
                    else if (root.watchlist.length > 0)
                        root.pinSymbol(root.watchlist[root.selectedIndex]);
                    return;
                }
                if (t === "f" || t === "F") {
                    if (root.searching && root.suggestions.length > 0)
                        root.toggleFavorite(root.suggestions[root.suggestionIndex].symbol);
                    else if (root.watchlist.length > 0)
                        root.toggleFavorite(root.watchlist[root.selectedIndex]);
                    return;
                }
                if (t === "x" || t === "X")
                    return;
                if (root.listChrome === "gear")
                    return;
                if (t && t.length === 1 && t !== " ")
                    root.startSearch(t);
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

                    FinanceListView {
                        id: listView
                        width: parent.width
                        controller: root
                        visible: root.view === "list"
                    }

                    FinanceSettingsView {
                        width: parent.width
                        controller: root
                        visible: root.view === "settings"
                    }

                    FinanceDetailView {
                        width: parent.width
                        controller: root
                        visible: root.view === "detail"
                    }
                }
            }
        }
    }
}
