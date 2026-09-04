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

  assert.doesNotMatch(detail, /pillFill\(/)
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
  for (const entry of Object.values(manifest.entryPoints))
    assert.equal(fs.existsSync(path.join(root, entry)), true, `missing ${entry}`)
})
