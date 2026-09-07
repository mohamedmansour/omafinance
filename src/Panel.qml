import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Providers/Registry.js" as Registry
import "Providers/Yahoo.js" as Yahoo
import "Providers/BankOfCanada.js" as BankOfCanada

Panel {
    id: root
    moduleName: "mohamedmansour.finance"
    ipcTarget: "mohamedmansour.finance"
    manageIpc: false

    // Providers are wired up here rather than inside Registry.js because
    // `.import` is QML-only syntax that Node cannot require, and the registry
    // has to stay loadable by the test suite.
    //
    // Registration is lazy: QML evaluates property bindings before
    // Component.onCompleted runs, so registering there would let the first
    // round of bindings observe an empty registry.
    function registry() {
        if (!Registry.bootstrapped()) {
            Registry.markBootstrapped();
            registerProvider(Yahoo);
            registerProvider(BankOfCanada);
        }
        return Registry;
    }

    // Registration is per-provider so one that fails to construct is reported
    // and skipped, rather than stranding every provider after it.
    function registerProvider(module) {
        try {
            Registry.register(module.create(Model));
        } catch (error) {
            console.warn("omafinance: provider failed to register - " + error.message);
        }
    }

    function providerFor(ref) {
        return registry().resolve(ref);
    }

    function providerIdFor(ref) {
        return registry().parseRef(ref).id;
    }

    function providerSupports(ref, capability) {
        return registry().supports(ref, capability);
    }

    // What the bar and list show for a ref, so a raw source id - a Valet series,
    // say - never has to be readable on its own.
    function displayLabelFor(ref) {
        var provider = providerFor(ref);
        var id = providerIdFor(ref);
        if (provider && typeof provider.displayLabel === "function")
            return provider.displayLabel(id, quotes[ref] || null) || id;
        return id;
    }

    // The detail payloads a provider publishes, in its own vocabulary. Yahoo
    // happens to use "insights" and "quotePage"; nothing here assumes that.
    function detailKinds(ref) {
        var provider = providerFor(ref);
        if (!provider || !providerSupports(ref, "detail") || typeof provider.detailRequests !== "function")
            return [];
        var requests = provider.detailRequests(providerIdFor(ref)) || [];
        var kinds = [];
        for (var i = 0; i < requests.length; i++) {
            if (requests[i] && requests[i].kind)
                kinds.push(String(requests[i].kind));
        }
        return kinds;
    }

    // There are two detail process slots, so a provider's first two declared
    // kinds are the ones fetched. Yahoo declares exactly two.
    function detailKindFor(index) {
        var kinds = detailKindList;
        return index < kinds.length ? kinds[index] : "";
    }

    function detailRequest(ref, kind) {
        if (!kind)
            return null;
        var provider = providerFor(ref);
        if (!provider || !providerSupports(ref, "detail") || typeof provider.detailRequests !== "function")
            return null;
        var requests = provider.detailRequests(providerIdFor(ref)) || [];
        for (var i = 0; i < requests.length; i++) {
            if (requests[i] && requests[i].kind === kind && registry().isRequest(requests[i]))
                return requests[i];
        }
        return null;
    }

    // Null means the payload was unusable, which makes the caller count a
    // failure and retry with backoff. Validating is the provider's job, since
    // only it knows what a valid response looks like - Yahoo, for one, answers
    // some errors with HTTP 200.
    function parseDetailPayload(ref, kind, raw) {
        var provider = providerFor(ref);
        if (!provider || typeof provider.parseDetail !== "function")
            return null;
        return provider.parseDetail(kind, raw);
    }

    // Typing "boc:mortgage" searches that provider; a bare query searches the
    // default one. The prefix is consumed here so providers never see it.
    function searchProvider(query) {
        return registry().provider(registry().parseQuery(query).providerId);
    }

    function searchTerm(query) {
        return registry().parseQuery(query).term;
    }

    // Suggestion rows arrive keyed by the provider's own id and are promoted to
    // namespaced refs, so picking one adds an entry that resolves back to the
    // provider it came from.
    function namespaceSuggestions(provider, rows) {
        var list = rows || [];
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var row = list[i];
            if (!row || !row.symbol)
                continue;
            out.push({
                symbol: registry().formatRef(provider ? provider.id : "", row.symbol),
                name: row.name,
                type: row.type,
                exchange: row.exchange
            });
        }
        return out;
    }

    function applySuggestions(provider, rows) {
        suggestions = namespaceSuggestions(provider, rows);
        suggestionIndex = 0;
    }

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

    // One refresh fans out into a queue of requests: a watchlist can span
    // providers, and a provider may itself need several calls. These track the
    // request in flight and the tally that decides overall success.
    property var quoteQueue: []
    property string quoteBatchProviderId: ""
    property var quoteBatchIds: []
    property bool quoteBatchSplit: false
    property int quoteBatchOk: 0
    property int quoteBatchFailed: 0
    property int quoteBatchMissing: 0
    property var providerFetchedAt: ({})
    property int quoteUnservable: 0
    property int quoteThrottled: 0
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
    property var detailCache: ({})
    property var detailCacheOrder: []
    readonly property int detailCacheTtlMs: 300000
    readonly property int detailCacheLimit: 16
    property string searchQuery: ""
    property var suggestions: []
    property int suggestionIndex: 0
    property string searchPendingQuery: ""
    property string searchActiveQuery: ""
    property string searchError: ""
    property bool searching: false
    property var searchCache: ({})
    property var searchCacheOrder: []
    readonly property int searchCacheTtlMs: 300000
    readonly property int searchCacheLimit: 32
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
    readonly property bool showBarQuote: showPrice || showChange
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
    readonly property var quoteSymbols: Model.quoteSymbolsForView(watchlist, detailSymbol, view)
    readonly property var pinnedQuote: quotes[barSymbol] || null
    readonly property string barDisplayLabel: displayLabelFor(barSymbol)
    readonly property string label: Model.barLabel(barDisplayLabel, pinnedQuote, false, showTicker, showPrice, showChange, changeStyle)
    readonly property string verticalLabel: Model.barLabel(barDisplayLabel, pinnedQuote, true, showTicker, showPrice, showChange, changeStyle)
    readonly property string labelTone: Model.barLabelTone(pinnedQuote, showTicker, showPrice, showChange, changeStyle)
    readonly property string quoteStatusText: {
        var hasQuotes = Object.keys(quotes || {}).length > 0;
        // A drain spans several requests, so the process being idle between two
        // of them does not mean the refresh has finished.
        if (quoteProc.running || quoteQueue.length > 0)
            return hasQuotes ? "" : "Loading quotes…";
        if (quoteError) {
            var suffix = showLastUpdated && quotesUpdatedAt > 0 ? " · Last updated " + timeLabel(quotesUpdatedAt) : "";
            return quoteError + suffix;
        }
        return showLastUpdated && quotesUpdatedAt > 0 ? "Updated " + timeLabel(quotesUpdatedAt) : "";
    }
    readonly property string chartStatusText: {
        var currentFetch = chartFetchSymbol === detailSymbol && chartFetchRange === effectiveDetailRange;
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
    // A provider that cannot serve intraday data has 1D trimmed, so the detail
    // view never offers a range the source will not answer.
    readonly property var detailRanges: registry().chartRangesFor(detailSymbol, Model.chartRanges())

    // The saved range is global, but a provider may not support it. Clamping is
    // kept to the view instead of being written back, so opening a daily series
    // cannot degrade every later intraday symbol.
    readonly property string effectiveDetailRange: {
        var ranges = detailRanges;
        if (!detailSymbol || ranges.indexOf(detailRange) !== -1)
            return detailRange;
        return ranges.length ? ranges[0] : detailRange;
    }
    readonly property var activeQuote: quotes[detailSymbol] || detailQuote
    readonly property var rangeChart: {
        if (detailQuote && detailQuote.chartRange === effectiveDetailRange)
            return detailQuote;
        if (effectiveDetailRange === "1D" && quotes[detailSymbol])
            return quotes[detailSymbol];
        return null;
    }
    // Each provider decides what its detail rows are; one with no fundamentals
    // returns none and the section collapses.
    readonly property var detailKindList: detailKinds(detailSymbol)

    // The two payload slots are handed back under the provider's own kind
    // names, so nothing outside the provider needs to know what they mean.
    readonly property var detailStats: {
        var p = providerFor(detailSymbol);
        if (!p || !providerSupports(detailSymbol, "detail") || typeof p.detailStats !== "function")
            return [];
        var bag = {};
        var kinds = detailKindList;
        if (kinds.length > 0)
            bag[kinds[0]] = detailInsights;
        if (kinds.length > 1)
            bag[kinds[1]] = detailPage;
        return p.detailStats(activeQuote, bag) || [];
    }
    readonly property var detailRangeChange: Model.rangeChangePercent(rangeChart, effectiveDetailRange)
    readonly property var detailRangeChangeAmount: Model.rangeChangeAmount(rangeChart, effectiveDetailRange)
    readonly property var sessionQuote: quotes[detailSymbol] || rangeChart || activeQuote
    readonly property var detailMainPrice: {
        if (effectiveDetailRange === "1D" && sessionQuote && sessionQuote.regularPrice != null)
            return sessionQuote.regularPrice;
        return activeQuote ? activeQuote.price : null;
    }
    readonly property var detailMainChange: {
        if (effectiveDetailRange === "1D" && sessionQuote && sessionQuote.regularChangePercent != null)
            return sessionQuote.regularChangePercent;
        return detailRangeChange;
    }
    readonly property var detailMainChangeAmount: {
        if (effectiveDetailRange === "1D" && sessionQuote && sessionQuote.regularPrice != null && sessionQuote.previousClose != null)
            return sessionQuote.regularPrice - sessionQuote.previousClose;
        return detailRangeChangeAmount;
    }
    property var heldMainChange: null
    property var heldMainChangeAmount: null
    readonly property bool awaitingRangeChart: {
        if (view !== "detail" || !detailSymbol)
            return false;
        if (detailQuote && detailQuote.chartRange === effectiveDetailRange)
            return false;
        if (effectiveDetailRange === "1D" && quotes[detailSymbol])
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
    readonly property bool showExtended: effectiveDetailRange === "1D" && providerSupports(detailSymbol, "extendedHours") && sessionQuote && sessionQuote.hasExtended === true
    readonly property var extendedChangeAmount: {
        if (!sessionQuote || sessionQuote.extendedPrice == null || sessionQuote.regularPrice == null)
            return null;
        return sessionQuote.extendedPrice - sessionQuote.regularPrice;
    }
    readonly property string priceCaption: Model.rangeCaption(effectiveDetailRange, sessionQuote)
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
        openRefreshTimer.stop();
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
        if (before !== after && (opened || showBarQuote))
            Qt.callLater(refresh);
    }

    function refresh() {
        if (quoteSymbols.length === 0) {
            quoteRefreshPending = false;
            return;
        }
        // Guard on the whole drain, not just the live process: between one
        // request exiting and the next starting, running is false while the
        // queue is still non-empty, and starting a second fan-out there would
        // cross-wire a response to the wrong provider's parser.
        if (quoteProc.running || quoteQueue.length > 0) {
            quoteRefreshPending = true;
            return;
        }
        quoteRefreshPending = false;
        quoteQueue = buildQuoteQueue();
        quoteBatchOk = 0;
        quoteBatchFailed = 0;
        quoteBatchMissing = quoteUnservable;
        if (quoteQueue.length === 0) {
            // Nothing queued because every provider is within its own refresh
            // floor is normal; nothing queued because nothing can serve these
            // symbols is worth saying, but is not a source failure to back off.
            if (quoteThrottled === 0)
                quoteError = quoteUnservable > 0 ? "No source for these symbols" : quoteError;
            return;
        }
        startNextQuoteBatch();
    }

    // Flattens the watchlist into individual requests. A provider may need more
    // than one - an API taking a single base currency per call cannot cover an
    // arbitrary set of pairs - so each request carries the ids it actually
    // covers rather than the whole provider group's.
    function buildQuoteQueue() {
        var groups = registry().groupByProvider(quoteSymbols);
        var queue = [];
        var now = Date.now();
        quoteUnservable = 0;
        quoteThrottled = 0;

        for (var i = 0; i < groups.length; i++) {
            var group = groups[i];
            if (!providerSupports(group.refs[0], "quote")) {
                quoteUnservable += group.ids.length;
                continue;
            }

            // A source that publishes once a day does not need the live
            // interval; asking it every two seconds is waste the provider
            // itself declares the bound for.
            var floor = typeof group.provider.minRefreshMs === "function" ? group.provider.minRefreshMs() : 0;
            var last = providerFetchedAt[group.providerId] || 0;
            if (floor > 0 && last > 0 && now - last < floor) {
                quoteThrottled++;
                continue;
            }

            var requests = registry().requestList(group.provider.quoteRequest ? group.provider.quoteRequest(group.ids) : null);
            var covered = {};
            for (var j = 0; j < requests.length; j++) {
                var ids = requests[j].ids || group.ids;
                for (var k = 0; k < ids.length; k++)
                    covered[ids[k]] = true;
                queue.push({
                    providerId: group.providerId,
                    ids: ids,
                    argv: requests[j].argv
                });
            }
            // A ref its own provider refuses to build a request for would
            // otherwise be silently dead: never fetched, never reported.
            for (var m = 0; m < group.ids.length; m++) {
                if (!Object.prototype.hasOwnProperty.call(covered, group.ids[m]))
                    quoteUnservable++;
            }
        }
        return queue;
    }

    function startNextQuoteBatch() {
        // A refresh can be scheduled while a deferred advance is still pending;
        // starting a request on a running process would hand its response to
        // the wrong provider's parser.
        if (quoteProc.running)
            return;
        if (quoteQueue.length === 0) {
            finishQuoteRefresh();
            return;
        }
        var batch = quoteQueue.shift();
        quoteBatchProviderId = batch.providerId;
        quoteBatchIds = batch.ids;
        quoteBatchSplit = batch.split === true;
        quoteProc.command = batch.argv;
        quoteProc.running = true;
        quoteWatchdog.restart();
    }

    // A curl that fails to exec never emits exited, which would strand the queue
    // and, because refresh() waits for the queue to drain, stop the widget
    // refreshing for the rest of the session. Abandon the drain instead.
    // Reassigned rather than mutated so the change is visible to anything that
    // reads it; QML does not notify on in-place edits of a var property.
    function noteProviderFetched(providerId) {
        if (!providerId)
            return;
        var next = {};
        for (var key in providerFetchedAt) {
            if (Object.prototype.hasOwnProperty.call(providerFetchedAt, key))
                next[key] = providerFetchedAt[key];
        }
        next[providerId] = Date.now();
        providerFetchedAt = next;
    }

    function abandonQuoteDrain() {
        quoteQueue = [];
        quoteBatchFailed++;
        finishQuoteRefresh();
    }

    // A batched endpoint can fail wholesale because of a single bad id - Valet
    // 404s the entire request if one series is unknown - so retry the ids one at
    // a time before writing the whole provider off.
    function splitFailedBatch() {
        var provider = registry().provider(quoteBatchProviderId);
        var ids = quoteBatchIds || [];
        var retries = [];
        for (var i = 0; i < ids.length; i++) {
            var requests = registry().requestList(provider && provider.quoteRequest ? provider.quoteRequest([ids[i]]) : null);
            for (var j = 0; j < requests.length; j++) {
                retries.push({
                    providerId: quoteBatchProviderId,
                    ids: requests[j].ids || [ids[i]],
                    argv: requests[j].argv,
                    split: true
                });
            }
        }
        if (retries.length === 0)
            return false;
        quoteQueue = retries.concat(quoteQueue);
        return true;
    }

    // Failure is judged once the whole queue has run, so one dead provider does
    // not mark a healthy one as failing.
    function finishQuoteRefresh() {
        quoteWatchdog.stop();
        quoteBatchProviderId = "";
        quoteBatchIds = [];
        quoteBatchSplit = false;
        // Backoff answers "is the source failing", so only a failed request
        // drives it. An id the source simply never returns is usually a
        // permanent condition, and counting it would saturate the counter and
        // stall every healthy symbol alongside it.
        if (quoteBatchFailed > 0) {
            quoteFailureCount = Math.min(10, quoteFailureCount + 1);
            quoteError = quoteBatchOk > 0 ? "Some quotes unavailable" : "Quotes unavailable";
        } else {
            quoteFailureCount = 0;
            quoteError = quoteBatchMissing > 0 ? "Some quotes unavailable" : "";
        }
        if (quoteBatchOk > 0)
            quotesUpdatedAt = Date.now();
        if (quoteRefreshPending)
            Qt.callLater(refresh);
    }

    function scheduleOpenRefresh() {
        openRefreshTimer.restart();
    }

    function scheduleBarRefresh() {
        Qt.callLater(function () {
            if (root.showBarQuote && !quoteProc.running)
                root.refresh();
        });
    }

    function addSymbol(symbol) {
        var next = Model.addSymbol(watchlist, registry().canonicalRef(Model.normalizeSymbol(symbol)));
        if (next.length === watchlist.length) {
            var already = registry().canonicalRef(Model.normalizeSymbol(symbol));
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
        restoreDetailCache(next);
        fetchDetail();
        return true;
    }

    function detailCacheKey(symbol) {
        return Model.normalizeSymbol(symbol);
    }

    function cacheDetailData(symbol, field, value) {
        var key = detailCacheKey(symbol);
        if (!key)
            return;
        var existing = detailCache[key] || {};
        var entry = {
            page: existing.page || ({}),
            pageStoredAt: existing.pageStoredAt || 0,
            insights: existing.insights || ({}),
            insightsStoredAt: existing.insightsStoredAt || 0
        };
        entry[field] = value;
        entry[field + "StoredAt"] = Date.now();

        var nextCache = {};
        var nextOrder = [];
        for (var i = 0; i < detailCacheOrder.length; i++) {
            var existingKey = detailCacheOrder[i];
            if (existingKey !== key && detailCache[existingKey]) {
                nextCache[existingKey] = detailCache[existingKey];
                nextOrder.push(existingKey);
            }
        }
        nextCache[key] = entry;
        nextOrder.push(key);
        while (nextOrder.length > detailCacheLimit)
            delete nextCache[nextOrder.shift()];
        detailCache = nextCache;
        detailCacheOrder = nextOrder;
    }

    function restoreDetailCache(symbol) {
        var entry = detailCache[detailCacheKey(symbol)];
        if (!entry)
            return;
        var now = Date.now();
        if (entry.insightsStoredAt > 0 && now - entry.insightsStoredAt <= detailCacheTtlMs) {
            detailInsights = entry.insights;
            insightsLoaded = true;
        }
        if (entry.pageStoredAt > 0 && now - entry.pageStoredAt <= detailCacheTtlMs) {
            detailPage = entry.page;
            quotePageLoaded = true;
        }
    }

    function prefetchDetail(symbol) {
        if (!prepareDetail(symbol))
            return;
        detailEnrichmentTimer.stop();
        fetchInsights();
        fetchQuotePage();
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
        var provider = providerFor(detailSymbol);
        if (!provider || !providerSupports(detailSymbol, "chart") || !provider.chartRequest)
            return;
        var request = provider.chartRequest(providerIdFor(detailSymbol), effectiveDetailRange);
        if (!registry().isRequest(request)) {
            chartFetchSymbol = detailSymbol;
            chartFetchRange = effectiveDetailRange;
            chartError = "No chart for this entry";
            return;
        }
        chartFetchSymbol = detailSymbol;
        chartFetchRange = effectiveDetailRange;
        chartError = "";
        chartProc.command = request.argv;
        chartProc.running = true;
    }

    function fetchDetail() {
        if (!detailSymbol)
            return;
        startChartFetch();
        detailEnrichmentTimer.restart();
    }

    function fetchInsights() {
        if (!detailSymbol)
            return;
        if (insightsLoaded)
            return;
        if (insightsProc.running)
            return;
        var request = detailRequest(detailSymbol, detailKindFor(0));
        if (!request) {
            insightsLoaded = true;
            return;
        }
        insightsFetchSymbol = detailSymbol;
        insightsError = "";
        insightsProc.command = request.argv;
        insightsProc.running = true;
    }

    function fetchQuotePage() {
        if (!detailSymbol)
            return;
        if (quotePageLoaded)
            return;
        if (quotePageProc.running)
            return;
        var request = detailRequest(detailSymbol, detailKindFor(1));
        if (!request) {
            quotePageLoaded = true;
            return;
        }
        quotePageFetchSymbol = detailSymbol;
        quotePageError = "";
        quotePageProc.command = request.argv;
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
        if (prefix) {
            listView.field.text = prefix;
            listView.field.cursorPosition = listView.field.text.length;
        }
        Qt.callLater(function () {
            listView.field.forceActiveFocus();
            if (!prefix)
                listView.field.selectAll();
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
        var cached = cachedSearchResults(query);
        if (cached !== null) {
            suggestions = cached;
            suggestionIndex = 0;
            searchPendingQuery = "";
            searchError = "";
            return;
        }
        searchError = "";
        searchPendingQuery = query;
        if (!searchProc.running)
            startSearchFetch();
    }

    function searchCacheKey(query) {
        return String(query || "").replace(/^\s+|\s+$/g, "").toUpperCase();
    }

    function cachedSearchResults(query) {
        var key = searchCacheKey(query);
        var entry = searchCache[key];
        if (!entry || Date.now() - entry.storedAt > searchCacheTtlMs)
            return null;
        return entry.results;
    }

    function cacheSearchResults(query, results) {
        var key = searchCacheKey(query);
        if (!key)
            return;
        var nextCache = {};
        var nextOrder = [];
        for (var i = 0; i < searchCacheOrder.length; i++) {
            var existingKey = searchCacheOrder[i];
            if (existingKey !== key && searchCache[existingKey]) {
                nextCache[existingKey] = searchCache[existingKey];
                nextOrder.push(existingKey);
            }
        }
        nextCache[key] = {
            storedAt: Date.now(),
            results: results
        };
        nextOrder.push(key);
        while (nextOrder.length > searchCacheLimit)
            delete nextCache[nextOrder.shift()];
        searchCache = nextCache;
        searchCacheOrder = nextOrder;
    }

    function startSearchFetch() {
        if (!searching || !searchPendingQuery)
            return;
        searchActiveQuery = searchPendingQuery;
        var provider = searchProvider(searchActiveQuery);
        var term = searchTerm(searchActiveQuery);

        if (!provider || !providerSupports(searchActiveQuery, "search")) {
            // Say so, rather than leaving it indistinguishable from "no matches".
            applySuggestions(provider, []);
            searchError = provider ? (provider.label || provider.id) + " has no search - enter an id directly" : "";
            return;
        }
        searchError = "";

        // A provider with an offline catalogue answers without any request.
        if (typeof provider.searchLocal === "function") {
            applySuggestions(provider, provider.searchLocal(term));
            if (searchPendingQuery !== searchActiveQuery)
                Qt.callLater(startSearchFetch);
            return;
        }
        var request = provider.searchRequest ? provider.searchRequest(term) : null;
        if (!registry().isRequest(request)) {
            applySuggestions(provider, []);
            return;
        }
        searchProc.command = request.argv;
        searchProc.running = true;
    }

    function commitSearch() {
        if (suggestions.length > 0) {
            var pick = suggestions[Math.max(0, Math.min(suggestionIndex, suggestions.length - 1))];
            if (pick)
                openDetail(pick.symbol);
            return;
        }
        var typed = registry().canonicalRef(Model.normalizeSymbol(searchQuery || listView.field.text));
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
            var idx = ranges.indexOf(effectiveDetailRange);
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
            var provider = root.registry().provider(root.quoteBatchProviderId);
            var parsed = (exitCode === 0 && raw && provider) ? (provider.parseQuotes(raw, root.quoteBatchIds) || {}) : {};

            // Providers key results by their own ids; they are stored under the
            // namespaced ref so entries from different sources cannot collide.
            var keyed = {};
            var count = 0;
            var wanted = root.quoteBatchIds || [];
            var seen = {};
            for (var id in parsed) {
                if (!Object.prototype.hasOwnProperty.call(parsed, id))
                    continue;
                // A request names what it covers, so a response cannot add
                // entries this call never asked for.
                if (wanted.length > 0 && wanted.indexOf(id) === -1)
                    continue;
                keyed[root.registry().formatRef(root.quoteBatchProviderId, id)] = parsed[id];
                seen[id] = true;
                count++;
            }

            // A response that answers only some of what it was asked for is
            // partial: the rest keep their previous value, so reporting success
            // would present stale prices as freshly updated.
            var missing = 0;
            for (var w = 0; w < wanted.length; w++) {
                if (!Object.prototype.hasOwnProperty.call(seen, wanted[w]))
                    missing++;
            }

            if (count > 0 && missing > 0) {
                root.quotes = Model.mergeQuotes(root.quotes, keyed);
                root.quoteBatchOk++;
                root.quoteBatchMissing += missing;
                root.noteProviderFetched(root.quoteBatchProviderId);
            } else if (count > 0) {
                root.quotes = Model.mergeQuotes(root.quotes, keyed);
                root.quoteBatchOk++;
                root.noteProviderFetched(root.quoteBatchProviderId);
            } else if (exitCode === 22 && !root.quoteBatchSplit && (root.quoteBatchIds || []).length > 1 && root.splitFailedBatch()) {
                // Retrying id-by-id; the tally is only touched once those land.
            } else {
                root.quoteBatchFailed++;
            }
            // Deferred so the queue advances from a clean stack rather than from
            // inside the signal handler of the process it is about to reuse.
            Qt.callLater(root.startNextQuoteBatch);
        }
        stdout: StdioCollector {
            id: quoteStdout
            waitForEnd: true
        }
    }

    Process {
        id: searchProc
        onExited: function (exitCode) {
            var provider = root.searchProvider(root.searchActiveQuery);
            var results = [];
            if (exitCode === 0 && provider) {
                results = root.namespaceSuggestions(provider, provider.parseSearch(searchStdout.text));
                root.cacheSearchResults(root.searchActiveQuery, results);
            }
            if (root.searching && root.searchActiveQuery === root.searchQuery) {
                if (exitCode === 0 && provider) {
                    root.suggestions = results;
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
            var currentFetch = root.chartFetchSymbol === root.detailSymbol && root.chartFetchRange === root.effectiveDetailRange;
            if (currentFetch) {
                var provider = root.providerFor(root.detailSymbol);
                var wantId = root.providerIdFor(root.detailSymbol);
                var parsed = (exitCode === 0 && provider) ? provider.parseChart(chartStdout.text, wantId, root.effectiveDetailRange) : null;
                // Range reconciliation is a Yahoo quirk; a provider that serves
                // exactly what it was asked reports neither side.
                var served = (parsed && provider.servedRange) ? provider.servedRange(parsed) : "";
                var expected = (provider && provider.expectedRange) ? provider.expectedRange(root.effectiveDetailRange) : "";
                var valid = parsed && parsed.symbol === wantId && (!served || !expected || served === expected);
                if (valid) {
                    parsed.chartRange = root.effectiveDetailRange;
                    root.detailQuote = parsed;
                    root.chartFailureCount = 0;
                    root.chartError = "";
                    root.chartUpdatedAt = Date.now();
                } else {
                    root.chartFailureCount = Math.min(10, root.chartFailureCount + 1);
                    root.chartError = "Chart unavailable";
                }
            }
            if (root.detailSymbol && (root.chartFetchSymbol !== root.detailSymbol || root.chartFetchRange !== root.effectiveDetailRange))
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
                var parsedInsights = exitCode === 0 ? root.parseDetailPayload(root.detailSymbol, root.detailKindFor(0), raw) : null;
                if (parsedInsights) {
                    root.detailInsights = parsedInsights;
                    root.cacheDetailData(root.insightsFetchSymbol, "insights", root.detailInsights);
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
                var parsedPage = (exitCode === 0 && raw) ? root.parseDetailPayload(root.detailSymbol, root.detailKindFor(1), raw) : null;
                if (parsedPage) {
                    root.detailPage = parsedPage;
                    root.cacheDetailData(root.quotePageFetchSymbol, "page", root.detailPage);
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
        interval: 100
        onTriggered: root.requestSearch()
    }

    Timer {
        id: detailEnrichmentTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.fetchInsights();
            root.fetchQuotePage();
        }
    }

    Timer {
        id: openRefreshTimer
        interval: 250
        repeat: false
        onTriggered: {
            var searchStarted = root.searching && root.searchQuery.length > 0;
            if (root.opened && !searchStarted && !quoteProc.running)
                root.refresh();
        }
    }

    Timer {
        id: refreshTimer
        interval: root.backgroundRefreshMs
        running: root.showBarQuote && !root.opened
        repeat: true
        onTriggered: if (!quoteProc.running)
            root.refresh()
    }

    // Longer than the longest --max-time any provider sets, so it only fires
    // when a request produced no exit signal at all.
    Timer {
        id: quoteWatchdog
        interval: 20000
        repeat: false
        onTriggered: if (!quoteProc.running)
            root.abandonQuoteDrain()
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
        running: root.opened && root.view === "detail" && root.effectiveDetailRange === "1D"
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
