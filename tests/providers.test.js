const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../src/Model.js")
const Registry = require("../src/Providers/Registry.js")
const Yahoo = require("../src/Providers/Yahoo.js")

const root = path.resolve(__dirname, "..")

function freshRegistry() {
  Registry.reset()
  Registry.register(Yahoo.create(Model))
  return Registry
}

// Every provider that ships, discovered from disk so a new one is covered by
// the loops below without anyone remembering to add it.
function allProviders() {
  const R = freshRegistry()
  for (const file of fs.readdirSync(path.join(root, "src", "Providers"))) {
    if (file === "Registry.js" || file === "Yahoo.js" || !file.endsWith(".js"))
      continue
    R.register(require(path.join(root, "src", "Providers", file)).create(Model))
  }
  return R
}

test("provider files are plain JavaScript, not QML-only syntax", () => {
  // `.import` and `.pragma library` are QML dialect and would make these files
  // impossible to require here, which is how they get tested at all.
  // Scanned rather than listed, so a provider added later is covered too.
  const files = fs.readdirSync(path.join(root, "src", "Providers")).filter(f => f.endsWith(".js"))
  assert.ok(files.length >= 2)
  for (const file of files) {
    const src = fs.readFileSync(path.join(root, "src", "Providers", file), "utf8")
    assert.doesNotMatch(src, /^\s*\.import\s/m, `${file} uses .import`)
    assert.doesNotMatch(src, /^\s*\.pragma\s/m, `${file} uses .pragma`)
  }
})

test("bare symbols resolve to the default provider and stay bare on disk", () => {
  const R = freshRegistry()
  const parsed = R.parseRef("AAPL")
  assert.equal(parsed.providerId, "yahoo")
  assert.equal(parsed.id, "AAPL")
  assert.equal(parsed.explicit, false)
  // Round-tripping must not rewrite existing watchlists.
  assert.equal(R.formatRef("yahoo", "AAPL"), "AAPL")
})

test("an unknown prefix is treated as part of the symbol, not a provider", () => {
  const R = freshRegistry()
  // Otherwise a symbol containing a colon would silently resolve to nothing.
  assert.equal(R.parseRef("WEIRD:THING").providerId, "yahoo")
  assert.equal(R.parseRef("WEIRD:THING").id, "WEIRD:THING")
})

test("a Yahoo-only watchlist is still one batch, one request", () => {
  const R = freshRegistry()
  const groups = R.groupByProvider(["SPY", "AAPL", "BTC-USD"])
  assert.equal(groups.length, 1)
  assert.deepEqual(groups[0].ids, ["SPY", "AAPL", "BTC-USD"])
  assert.equal(R.requestList(groups[0].provider.quoteRequest(groups[0].ids)).length, 1)
})

test("Yahoo request URLs are unchanged by the move", () => {
  const Y = Yahoo.create(Model)
  const url = r => r.argv[r.argv.length - 1]
  assert.equal(url(Y.quoteRequest(["EQB.TO", "AAPL"])),
    "https://query1.finance.yahoo.com/v7/finance/spark?symbols=EQB.TO%2CAAPL&range=1d&interval=5m&includePrePost=true")
  assert.equal(url(Y.chartRequest("AAPL", "1Y")),
    "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1y&interval=1d&includePrePost=false")
  assert.equal(url(Y.searchRequest("apple")),
    "https://query2.finance.yahoo.com/v1/finance/search?q=apple&quotesCount=8&newsCount=0")
  const detail = Y.detailRequests("AAPL")
  assert.deepEqual(detail.map(d => d.kind), ["insights", "quotePage"])
  assert.equal(url(detail[0]), "https://query1.finance.yahoo.com/ws/insights/v2/finance/insights?symbol=AAPL")
  assert.equal(url(detail[1]), "https://finance.yahoo.com/quote/AAPL/")
  // The quote-page fetch is the only one that asks for compression.
  assert.ok(detail[1].argv.includes("--compressed"))
})

// Sample ids per provider, since a symbol shape is provider-specific.
const SAMPLE = { yahoo: "AAPL", boc: "V80691335", fx: "USD/CAD" }

test("every provider builds shell-free argv requests", () => {
  const R = allProviders()
  for (const provider of R.providers()) {
    const id = SAMPLE[provider.id]
    assert.ok(id, `no sample id for provider ${provider.id}`)
    const requests = [
      ...R.requestList(provider.quoteRequest([id])),
      ...R.requestList(provider.chartRequest(id, "1M"))
    ]
    assert.ok(requests.length > 0)
    for (const request of requests) {
      // argv arrays only: no shell string can be injected through a symbol.
      for (const arg of request.argv)
        assert.equal(typeof arg, "string")
      assert.equal(request.argv[0], "curl")
      assert.match(request.argv[request.argv.length - 1], /^https:\/\//)
    }
  }
})

test("empty inputs never produce a request", () => {
  const R = allProviders()
  for (const provider of R.providers()) {
    assert.deepEqual(R.requestList(provider.quoteRequest([])), [])
    assert.deepEqual(R.requestList(provider.chartRequest("", "1M")), [])
  }
})

test("a provider missing its Model dependencies fails loudly at creation", () => {
  // Silent degradation here would otherwise surface as a permanent stream of
  // nulls, because the parsers swallow exceptions.
  assert.throws(() => Yahoo.create({}), /Model\.normalizeSymbol is required/)
})

test("panel registers every provider that ships", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  for (const file of fs.readdirSync(path.join(root, "src", "Providers"))) {
    if (file === "Registry.js" || !file.endsWith(".js"))
      continue
    const name = file.replace(/\.js$/, "")
    assert.match(panel, new RegExp(`registerProvider\\(${name}\\)`),
      `Panel.qml never registers ${file}`)
  }
})

test("panel keeps the persisted range separate from the clamped one", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Opening a provider with no intraday range must not rewrite the saved range,
  // which would degrade every later intraday symbol.
  assert.match(panel, /readonly property string effectiveDetailRange/)
  assert.match(panel, /serializeState\(watchlist, pinned, detailRange\)/)
  assert.match(panel, /chartFetchRange = effectiveDetailRange/)
})

test("panel reports symbols no provider can serve", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Otherwise the queue is empty, neither tally moves, and the live timer
  // re-polls every 2s forever with a blank status.
  assert.match(panel, /No source for these symbols/)
  assert.match(panel, /quoteProc\.running \|\| quoteQueue\.length > 0/)
})

test("panel drives detail fetches off the provider's declared kinds", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /detailKindFor\(0\)/)
  assert.match(panel, /detailKindFor\(1\)/)
  // The Yahoo endpoint names must not be hardcoded into the panel.
  assert.doesNotMatch(panel, /detailRequest\(detailSymbol, "insights"\)/)
  assert.doesNotMatch(panel, /detailRequest\(detailSymbol, "quotePage"\)/)
})

test("capabilities gate the panel at runtime, not just registration", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /providerSupports\(ref, "detail"\)/)
  assert.match(panel, /providerSupports\(searchActiveQuery, "search"\)/)
})

test("the bar shows a provider's display label, not the raw ref", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // A raw source id can be unreadable on a status bar, so the provider names it.
  assert.match(panel, /readonly property string barDisplayLabel: displayLabelFor\(barSymbol\)/)
  assert.match(panel, /Model\.barLabel\(barDisplayLabel, pinnedQuote, false/)
  assert.match(panel, /Model\.barLabel\(barDisplayLabel, pinnedQuote, true/)
  assert.doesNotMatch(panel, /Model\.barLabel\(barSymbol/)
})

test("the panel advances the queue only onto an idle process", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Without this a refresh scheduled during a deferred advance can hand one
  // provider's response to another's parser.
  assert.match(panel, /function startNextQuoteBatch\(\)\s*\{[\s\S]{0,400}?if \(quoteProc\.running\)\s*return;/)
})

test("the panel credits a response only with the ids that request covered", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /wanted\.length > 0 && wanted\.indexOf\(id\) === -1/)
})

test("quote and chart fetches are gated on declared capabilities", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /providerSupports\(group\.refs\[0\], "quote"\)/)
  assert.match(panel, /providerSupports\(detailSymbol, "chart"\)/)
  // Every declared capability must be load-bearing, or it is documentation
  // that lies.
  assert.match(panel, /providerSupports\(detailSymbol, "extendedHours"\)/)
})

test("every declared capability is consulted somewhere in the panel", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  for (const capability of Registry.CAPABILITIES)
    assert.match(panel, new RegExp(`providerSupports\\([^)]+, "${capability}"\\)`), `${capability} is never consulted`)
})

test("one provider failing to construct does not strand the others", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // register() throws, so a shared sentinel plus unguarded calls would leave
  // every provider after the failing one unregistered forever.
  assert.match(panel, /function registerProvider\(module\)\s*\{\s*try\s*\{/)
  assert.match(panel, /catch \(error\)/)
})

test("the range chips highlight the range actually rendered", () => {
  const detail = fs.readFileSync(path.join(root, "src", "FinanceDetailView.qml"), "utf8")
  // Otherwise opening a daily-only provider highlights no chip at all.
  assert.match(detail, /String\(modelData\) === controller\.effectiveDetailRange/)
  assert.doesNotMatch(detail, /String\(modelData\) === controller\.detailRange/)
})
