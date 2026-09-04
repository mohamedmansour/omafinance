const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const root = path.resolve(__dirname, "..")
const qmlFiles = [
  "BarWidget.qml",
  "Panel.qml",
  "Sparkline.qml",
  "FinanceListView.qml",
  "FinanceSettingsView.qml",
  "FinanceDetailView.qml"
]

test("all plugin QML files parse with qmlformat", () => {
  for (const file of qmlFiles) {
    const result = spawnSync("/usr/lib/qt6/bin/qmlformat", [path.join(root, file)], {
      encoding: "utf8"
    })
    assert.equal(result.status, 0, `${file}: ${result.stderr || result.stdout}`)
  }
})

test("panel composes the extracted views", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  for (const component of ["FinanceListView", "FinanceSettingsView", "FinanceDetailView"])
    assert.match(panel, new RegExp(`\\b${component}\\s*\\{`))
  assert.match(panel, /backoffDelay\(2000, quoteFailureCount, 60000\)/)
})

test("panel presents before scheduling one non-blocking open refresh", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")

  assert.doesNotMatch(panel, /stateFile\.reload\(\)/)
  assert.match(panel, /function open\(\)[\s\S]*?root\.controller\.show\(\);\s*scheduleOpenRefresh\(\);/)
  assert.match(panel, /function toggle\(\)[\s\S]*?else\s*root\.open\(\);/)
  assert.match(panel, /function scheduleOpenRefresh\(\)[\s\S]*?Qt\.callLater/)
  assert.match(panel, /function scheduleBarRefresh\(\)[\s\S]*?root\.showBarData && !quoteProc\.running/)
  assert.doesNotMatch(panel, /triggeredOnStart:\s*true/)
})

test("background quote refreshes do not show updating status", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")

  assert.doesNotMatch(panel, /Updating quotes/)
  assert.doesNotMatch(panel, /Updating chart/)
  assert.match(panel, /quoteProc\.running\)\s*return hasQuotes \? "" : "Loading quotes…";/)
  assert.match(panel, /chartProc\.running && currentFetch\)\s*return rangeChart \? "" : "Loading chart…";/)
  assert.match(panel, /return showLastUpdated && chartUpdatedAt > 0 && detailQuote \? "Last updated "/)
})

test("detail loading is a delayed icon beside the ticker", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const detail = fs.readFileSync(path.join(root, "FinanceDetailView.qml"), "utf8")

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

test("detail header stacks small ticker, company name, then price", () => {
  const detail = fs.readFileSync(path.join(root, "FinanceDetailView.qml"), "utf8")
  const ticker = detail.indexOf("id: tickerLabel")
  const company = detail.indexOf("id: companyName")
  const price = detail.indexOf("Model.formatPrice(controller.detailMainPrice")

  assert.notEqual(ticker, -1)
  assert.notEqual(company, -1)
  assert.notEqual(price, -1)
  assert.ok(ticker < company)
  assert.ok(company < price)
  assert.match(detail, /id:\s*tickerLabel[\s\S]*?font\.pixelSize:\s*Style\.font\.body[\s\S]*?font\.bold:\s*true/)
  assert.match(detail, /id:\s*companyName[\s\S]*?font\.pixelSize:\s*Style\.font\.display/)
})

test("watchlist pointer-down prefetches details without duplicating the click fetch", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const list = fs.readFileSync(path.join(root, "FinanceListView.qml"), "utf8")

  assert.match(list, /onPressed:\s*function\s*\(mouse\)[\s\S]*?mouse\.button === Qt\.LeftButton[\s\S]*?controller\.prefetchDetail\(symbol\)/)
  assert.match(panel, /function prefetchDetail\(symbol\)\s*\{\s*prepareDetail\(symbol\);?\s*\}/)
  assert.match(panel, /function prepareDetail\(symbol\)[\s\S]*?if \(detailSymbol === next\)\s*return true;/)
  assert.match(panel, /function openDetail\(symbol\)\s*\{\s*if \(!prepareDetail\(symbol\)\)/)
})

test("detail price changes use tone-colored text without pill backgrounds", () => {
  const detail = fs.readFileSync(path.join(root, "FinanceDetailView.qml"), "utf8")
  const price = detail.indexOf("Model.formatPrice(controller.detailMainPrice")
  const change = detail.indexOf("id: detailChange")

  assert.doesNotMatch(detail, /pillFill\(/)
  assert.ok(price < change)
  assert.match(detail, /id:\s*detailChange[\s\S]*?color:\s*controller\.toneColor\(controller\.shownMainChange\)/)
  assert.match(detail, /id:\s*extChange[\s\S]*?color:\s*controller\.toneColor\(controller\.sessionQuote \? controller\.sessionQuote\.extendedChangePercent : null\)/)
})

test("change style follows the show-change setting and precedes refresh", () => {
  const settings = fs.readFileSync(path.join(root, "FinanceSettingsView.qml"), "utf8")
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
