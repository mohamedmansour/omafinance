const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const root = path.resolve(__dirname, "..")
const source = file => path.join(root, "src", file)
const qmlFiles = [
  "BarWidget.qml",
  "Panel.qml",
  "Sparkline.qml",
  "CandlestickChart.qml",
  "FinanceListView.qml",
  "FinanceSettingsView.qml",
  "FinanceDetailView.qml",
  "PriceRoll.qml"
]

test("all plugin QML files parse with qmlformat", () => {
  for (const file of qmlFiles) {
    const result = spawnSync("/usr/lib/qt6/bin/qmlformat", [source(file)], {
      encoding: "utf8"
    })
    assert.equal(result.status, 0, `${file}: ${result.stderr || result.stdout}`)
  }
})

test("panel composes the extracted views", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")
  for (const component of ["FinanceListView", "FinanceSettingsView", "FinanceDetailView"])
    assert.match(panel, new RegExp(`\\b${component}\\s*\\{`))
  assert.match(panel, /backoffDelay\(2000, quoteFailureCount, 60000\)/)
})

test("panel presents before scheduling one non-blocking open refresh", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.doesNotMatch(panel, /stateFile\.reload\(\)/)
  assert.match(panel, /function open\(\)[\s\S]*?root\.controller\.show\(\);\s*scheduleOpenRefresh\(\);/)
  assert.match(panel, /function toggle\(\)[\s\S]*?else\s*root\.open\(\);/)
  assert.match(panel, /function scheduleOpenRefresh\(\)\s*\{\s*openRefreshTimer\.restart\(\);?\s*\}/)
  assert.match(panel, /function scheduleBarRefresh\(\)[\s\S]*?root\.showBarQuote && !quoteProc\.running/)
  assert.doesNotMatch(panel, /triggeredOnStart:\s*true/)
})

test("ticker-only bar mode suspends background quote requests", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")
  const tickerSetter = panel.match(/function setShowTicker\(enabled\)\s*\{[\s\S]*?\n    \}/)

  assert.match(panel, /readonly property bool showBarData:\s*showTicker \|\| showPrice \|\| showChange/)
  assert.match(panel, /readonly property bool showBarQuote:\s*showPrice \|\| showChange/)
  assert.match(panel, /id:\s*refreshTimer[\s\S]*?running:\s*root\.showBarQuote && !root\.opened/)
  assert.match(panel, /before !== after && \(opened \|\| showBarQuote\)/)
  assert.ok(tickerSetter)
  assert.doesNotMatch(tickerSetter[0], /scheduleBarRefresh/)
})

test("search renders immediately, uses a short debounce, and caches results", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.match(panel, /function startSearch\(prefix\)[\s\S]*?listView\.field\.text = prefix;[\s\S]*?Qt\.callLater/)
  assert.match(panel, /id:\s*searchDebounce[\s\S]*?interval:\s*100/)
  assert.match(panel, /function cachedSearchResults\(query\)/)
  assert.match(panel, /function cacheSearchResults\(query, results\)/)
  assert.match(panel, /searchCacheTtlMs:\s*300000/)
  assert.match(panel, /id:\s*openRefreshTimer[\s\S]*?searchStarted/)
})

test("background quote refreshes do not show updating status", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.doesNotMatch(panel, /Updating quotes/)
  assert.doesNotMatch(panel, /Updating chart/)
  assert.match(panel, /quoteProc\.running\)\s*return hasQuotes \? "" : "Loading quotes…";/)
  assert.match(panel, /chartProc\.running && currentFetch\)\s*return rangeChart \? "" : "Loading chart…";/)
  assert.match(panel, /return showLastUpdated && chartUpdatedAt > 0 && detailQuote \? "Last updated "/)
})

test("quote refresh uses symbols selected for the active view", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.match(panel, /quoteSymbolsForView\(watchlist, detailSymbol, view\)/)
  assert.match(panel, /Model\.sparkUrl\(quoteSymbols\)/)
})

test("detail loading is a delayed icon beside the ticker", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")

  assert.match(panel, /readonly property bool detailDataLoading/)
  assert.doesNotMatch(panel, /Loading market details/)
  assert.match(detail, /id:\s*tickerLabel/)
  assert.match(detail, /shouldShowDelayedLoader/)
  assert.match(detail, /detailsPendingKey/)
  assert.match(detail, /showDetailsSpinner/)
  assert.match(detail, /id:\s*detailsSpinner\b/)
  assert.doesNotMatch(detail, /Loading market details/)
  const ticker = detail.indexOf("id: tickerLabel")
  const spinner = detail.search(/id:\s*detailsSpinner\b/)
  const status = detail.indexOf("controller.detailDataStatusText")
  assert.notEqual(ticker, -1)
  assert.notEqual(spinner, -1)
  assert.ok(ticker < spinner)
  assert.ok(status === -1 || spinner < status)
})

test("detail enrichment uses a bounded five-minute cache", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.match(panel, /detailCacheTtlMs:\s*300000/)
  assert.match(panel, /detailCacheLimit:\s*16/)
  assert.match(panel, /function restoreDetailCache\(symbol\)/)
  assert.match(panel, /restoreDetailCache\(next\);\s*fetchDetail\(\);/)
  assert.match(panel, /cacheDetailData\(root\.insightsFetchSymbol, "insights"/)
  assert.match(panel, /cacheDetailData\(root\.quotePageFetchSymbol, "page"/)
  assert.match(panel, /if \(insightsLoaded\)\s*return;/)
  assert.match(panel, /if \(quotePageLoaded\)\s*return;/)
})

test("detail header stacks small ticker, company name, then price", () => {
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")
  const ticker = detail.indexOf("id: tickerLabel")
  const company = detail.indexOf("id: companyName")
  const price = detail.indexOf("price: controller.activeQuote ? controller.detailMainPrice")

  assert.notEqual(ticker, -1)
  assert.notEqual(company, -1)
  assert.notEqual(price, -1)
  assert.ok(ticker < company)
  assert.ok(company < price)
  assert.match(detail, /id:\s*tickerLabel[\s\S]*?font\.pixelSize:\s*Style\.font\.body[\s\S]*?font\.bold:\s*true/)
  assert.match(detail, /id:\s*companyName[\s\S]*?font\.pixelSize:\s*Style\.font\.display/)
})

test("extended-hours price sits beside the at-close block", () => {
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")

  assert.match(detail, /Row\s*\{\s*width:\s*parent\.width\s*spacing:\s*Style\.space\(32\)/)
  assert.match(detail, /width:\s*controller\.showExtended \? implicitWidth : parent\.width/)
  assert.doesNotMatch(detail, /width:\s*\(parent\.width - parent\.spacing\) \/ 2/)
})

test("watchlist pointer-down prefetches details without duplicating the click fetch", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")
  const list = fs.readFileSync(source("FinanceListView.qml"), "utf8")

  assert.match(list, /onPressed:\s*function\s*\(mouse\)[\s\S]*?mouse\.button === Qt\.LeftButton[\s\S]*?controller\.prefetchDetail\(symbol\)/)
  assert.match(panel, /function prefetchDetail\(symbol\)[\s\S]*?detailEnrichmentTimer\.stop\(\);[\s\S]*?fetchInsights\(\);[\s\S]*?fetchQuotePage\(\);/)
  assert.match(panel, /function prepareDetail\(symbol\)[\s\S]*?if \(detailSymbol === next\)\s*return true;/)
  assert.match(panel, /function openDetail\(symbol\)\s*\{\s*if \(!prepareDetail\(symbol\)\)/)
})

test("detail chart starts immediately while large enrichment waits one frame", () => {
  const panel = fs.readFileSync(source("Panel.qml"), "utf8")

  assert.match(panel, /function fetchDetail\(\)\s*\{[\s\S]*?startChartFetch\(\);[\s\S]*?detailEnrichmentTimer\.restart\(\);/)
  assert.match(panel, /id:\s*detailEnrichmentTimer\s*\n\s*interval:\s*16/)
  assert.match(panel, /onTriggered:\s*\{[\s\S]*?root\.fetchInsights\(\);[\s\S]*?root\.fetchQuotePage\(\);/)
})

test("watchlist virtualizes a capped set of reusable rows", () => {
  const list = fs.readFileSync(source("FinanceListView.qml"), "utf8")

  assert.match(list, /ListView\s*\{\s*id:\s*watchlistRows/)
  assert.match(list, /height:\s*Math\.min\(controller\.watchlist\.length, 8\) \* controller\.rowHeight/)
  assert.match(list, /reuseItems:\s*true/)
  assert.match(list, /cacheBuffer:\s*controller\.rowHeight/)
  assert.match(list, /positionViewAtIndex\(currentIndex, ListView\.Contain\)/)
})

test("sparklines cache normalized geometry for paint and hover", () => {
  const sparkline = fs.readFileSync(source("Sparkline.qml"), "utf8")

  assert.match(sparkline, /property var cachedGeometry:\s*null/)
  assert.match(sparkline, /function refreshGeometry\(\)/)
  assert.match(sparkline, /geometry\.xs\.push\(xAt\(geometry, i\)\)/)
  assert.match(sparkline, /geometry\.ys\.push\(yAt\(geometry, nums\[i\]\)\)/)
  assert.match(sparkline, /function updateHover\(px\)\s*\{\s*var g = cachedGeometry/)
  assert.match(sparkline, /var g = root\.cachedGeometry/)
  assert.match(sparkline, /onValuesChanged:\s*refreshGeometry\(\)/)
  assert.match(sparkline, /onPadChanged:\s*refreshGeometry\(\)/)
})

test("candlestick chart renders OHLC candles and interactive crosshairs", () => {
  const candleChart = fs.readFileSync(source("CandlestickChart.qml"), "utf8")
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")

  assert.match(candleChart, /property var candles:\s*\[\]/)
  assert.match(candleChart, /property string symbol:\s*""/)
  assert.match(candleChart, /onSymbolChanged:\s*resetZoom\(\)/)
  assert.match(candleChart, /onRangeKeyChanged:\s*resetZoom\(\)/)
  assert.match(candleChart, /onCandlesChanged:\s*refreshGeometry\(\)/)
  assert.match(candleChart, /Model\.stratScenario/)
  assert.match(candleChart, /function buildGeom\(\)/)
  assert.match(candleChart, /updateHover\(mouse\.x\)/)
  assert.match(candleChart, /ctx\.fillRect\(bodyLeft, bodyTop/)
  assert.match(detail, /\bCandlestickChart\s*\{/)
  assert.match(detail, /symbol:\s*controller\.detailSymbol/)
})

test("detail price changes use tone-colored text without pill backgrounds", () => {
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")
  const price = detail.indexOf("price: controller.activeQuote ? controller.detailMainPrice")
  const change = detail.indexOf("id: detailChange")

  assert.doesNotMatch(detail, /pillFill\(/)
  assert.ok(price < change)
  assert.match(detail, /id:\s*detailChange[\s\S]*?color:\s*controller\.toneColor\(controller\.shownMainChange\)/)
  assert.match(detail, /id:\s*extChange[\s\S]*?color:\s*controller\.toneColor\(controller\.sessionQuote \? controller\.sessionQuote\.extendedChangePercent : null\)/)
})

test("only changed detail price digits roll in their direction color", () => {
  const detail = fs.readFileSync(source("FinanceDetailView.qml"), "utf8")
  const roll = fs.readFileSync(source("PriceRoll.qml"), "utf8")

  assert.equal((detail.match(/\bPriceRoll\s*\{/g) || []).length, 2)
  assert.match(detail, /active:\s*controller\.opened && controller\.view === "detail"/)
  assert.match(roll, /rollDirection = next > lastPrice \? 1 : -1/)
  assert.match(roll, /changed: oldCharacter !== newCharacter/)
  assert.match(roll, /modelData\.changed && root\.animating \? root\.activeColor : root\.neutralColor/)
  assert.match(roll, /NumberAnimation[\s\S]*?property:\s*"rollProgress"[\s\S]*?Easing\.OutCubic/)
})

test("change style follows the show-change setting and precedes refresh", () => {
  const settings = fs.readFileSync(source("FinanceSettingsView.qml"), "utf8")
  const changeStyle = settings.indexOf('text: "Change on bar"')
  const refresh = settings.indexOf('label: "Background refresh (seconds)"')

  assert.notEqual(changeStyle, -1)
  assert.ok(changeStyle < refresh)
  assert.match(settings, /visible:\s*controller\.showChange[\s\S]*text:\s*"Change on bar"/)
  assert.match(settings, /ButtonGroup\s*{[\s\S]*?visible:\s*controller\.showChange[\s\S]*?value:\s*controller\.changeStyle/)
})

test("manifest entry points exist", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.id, "mohamedmansour.finance")
  assert.equal(manifest.barWidget.defaults.showLastUpdated, false)
  assert.equal(manifest.barWidget.schema.find(item => item.key === "showLastUpdated").defaultValue, false)
  for (const entry of Object.values(manifest.entryPoints))
    assert.equal(fs.existsSync(path.join(root, entry)), true, `missing ${entry}`)
})
