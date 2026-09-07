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

// --- rate formatting ---

test("rates format as percentages and their moves as percentage points", () => {
  assert.equal(Model.formatPrice(3.41, Model.RATE_UNIT, 2), "3.41%")
  assert.equal(Model.formatChange(-0.01, Model.RATE_UNIT), "-0.01 pp")
  assert.equal(Model.formatChange(0, Model.RATE_UNIT), "0.00 pp")
  // Currency behaviour must be untouched by the rate path.
  assert.equal(Model.formatPrice(321.02, "USD", 2), "$321.02")
  assert.equal(Model.formatChange(-1.5, "USD"), "-$1.50")
  assert.equal(Model.formatPrice(133.86, "CAD", 2), "133.86 CAD")
})

test("bar labels keep provider casing instead of uppercasing", () => {
  const quote = { price: 3.41, currency: Model.RATE_UNIT, changePercent: -0.29, priceHint: 2 }
  assert.match(Model.barLabel("GoC 5Y", quote, false, true, true, true, "percent"), /^GoC 5Y {2}3\.41%/)
  assert.match(Model.barLabel("AAPL", { price: 1, currency: "USD" }, false, true, true, false, "percent"), /^AAPL/)
})

// --- Bank of Canada -------------------------------------------------------

const BankOfCanada = require("../src/Providers/BankOfCanada.js")

function withBoc() {
  const R = freshRegistry()
  R.register(BankOfCanada.create(Model))
  return R
}

test("namespaced refs resolve to their provider and round-trip", () => {
  const R = withBoc()
  const parsed = R.parseRef("BOC:BD.CDN.5YR.DQ.YLD")
  assert.equal(parsed.providerId, "boc")
  assert.equal(parsed.id, "BD.CDN.5YR.DQ.YLD")
  assert.equal(parsed.explicit, true)
  assert.equal(R.formatRef(parsed.providerId, parsed.id), "BOC:BD.CDN.5YR.DQ.YLD")
})

test("watchlists split into one batch per provider, preserving order", () => {
  const R = withBoc()
  const groups = R.groupByProvider(["EQB.TO", "BOC:V80691335", "AAPL", "BOC:BD.CDN.5YR.DQ.YLD"])
  assert.equal(groups.length, 2)
  assert.deepEqual(groups[0].ids, ["EQB.TO", "AAPL"])
  assert.deepEqual(groups[1].ids, ["V80691335", "BD.CDN.5YR.DQ.YLD"])
})

test("capabilities differ per provider", () => {
  const R = withBoc()
  assert.equal(R.supports("AAPL", "detail"), true)
  assert.equal(R.supports("AAPL", "extendedHours"), true)
  assert.equal(R.supports("BOC:V80691335", "detail"), false)
  assert.equal(R.supports("BOC:V80691335", "quote"), true)
})

test("a provider without intraday data has 1D trimmed from its ranges", () => {
  const R = withBoc()
  const canonical = Model.chartRanges()
  assert.deepEqual(R.chartRangesFor("AAPL", canonical), canonical)
  const boc = R.chartRangesFor("BOC:BD.CDN.5YR.DQ.YLD", canonical)
  assert.equal(boc.includes("1D"), false)
  assert.equal(boc[0], "1W")
})

test("Bank of Canada rebuilds dense series from sparse, unsorted rows", () => {
  const B = BankOfCanada.create(Model)
  // Valet returns rows out of order, and a batch of mixed frequencies yields
  // rows carrying only whichever series reported that day.
  const quotes = B.parseQuotes(JSON.stringify({
    seriesDetail: {
      "BD.CDN.5YR.DQ.YLD": { label: "Benchmark bond yield: 5 year" },
      V80691335: { label: "Conventional mortgage: 5-year" }
    },
    observations: [
      { d: "2026-09-02", V80691335: { v: "6.09" }, "BD.CDN.5YR.DQ.YLD": { v: "3.42" } },
      { d: "2026-09-03", "BD.CDN.5YR.DQ.YLD": { v: "3.41" } },
      { d: "2026-09-01", "BD.CDN.5YR.DQ.YLD": { v: "3.30" } }
    ]
  }))
  const yield5 = quotes["BD.CDN.5YR.DQ.YLD"]
  assert.deepEqual(yield5.closes, [3.30, 3.42, 3.41], "series must be date-ascending")
  assert.equal(yield5.price, 3.41)
  assert.equal(yield5.asOf, "2026-09-03")
  assert.equal(yield5.currency, Model.RATE_UNIT)
  // The weekly series reported on only one of the three days.
  assert.deepEqual(quotes.V80691335.closes, [6.09])
})


test("catalogue search matches however the term is punctuated", () => {
  const B = BankOfCanada.create(Model)
  const ids = q => B.searchLocal(q).map(r => r.symbol)
  assert.deepEqual(ids("5 year"), ids("5-year"))
  assert.deepEqual(ids("5 year"), ids("5yr"))
  assert.ok(ids("mortgage").includes("V80691335"))
})

test("every catalogue entry has a short label for the bar", () => {
  for (const row of BankOfCanada.CATALOGUE) {
    assert.ok(row.short, `${row.id} has no short label`)
    assert.ok(row.short.length <= 14, `${row.id} short label is too long for a bar`)
  }
})

// --- ECB FX, and providers that need more than one request ----------------

const Frankfurter = require("../src/Providers/Frankfurter.js")

function withAll() {
  const R = withBoc()
  R.register(Frankfurter.create(Model))
  return R
}

// Frankfurter takes one base currency per call, so a set of pairs spanning
// several bases cannot be covered by a single request.
test("a provider may answer with several requests for one batch", () => {
  const R = withAll()
  const fx = R.provider("fx")
  assert.equal(R.requestList(fx.quoteRequest(["USD/CAD", "USD/JPY"])).length, 1)
  assert.equal(R.requestList(fx.quoteRequest(["USD/CAD", "EUR/GBP"])).length, 2)
  // Single-request providers still normalise to a one-element list.
  assert.equal(R.requestList(R.provider("boc").quoteRequest(["V80691335", "V80691311"])).length, 1)
})

test("each request carries only the ids it actually covers", () => {
  const R = withAll()
  const requests = R.requestList(R.provider("fx").quoteRequest(["USD/CAD", "EUR/GBP"]))
  // Handing both requests the whole group would credit a response with entries
  // it never asked for.
  assert.deepEqual(requests[0].ids, ["USD/CAD"])
  assert.deepEqual(requests[1].ids, ["EUR/GBP"])
  assert.deepEqual(R.requestList(R.provider("boc").quoteRequest(["V1", "V2"]))[0].ids, ["V1", "V2"])
})

test("requestList drops malformed requests instead of passing them on", () => {
  const R = withAll()
  assert.deepEqual(R.requestList(null), [])
  assert.deepEqual(R.requestList([]), [])
  assert.deepEqual(R.requestList({ argv: [] }), [])
  assert.deepEqual(R.requestList([{ argv: [] }, null]), [])
})

test("FX rates are rebuilt from a date-keyed response", () => {
  const F = Frankfurter.create(Model)
  // Frankfurter keys by date with a nested currency map, and names its own base,
  // so no request state has to be carried across.
  const quotes = F.parseQuotes(JSON.stringify({
    base: "USD",
    rates: {
      "2026-09-03": { CAD: 1.3812, JPY: 156.01 },
      "2026-09-01": { CAD: 1.3888, JPY: 155.4 },
      "2026-09-02": { CAD: 1.3799, JPY: 156.25 }
    }
  }))
  assert.deepEqual(Object.keys(quotes).sort(), ["USD/CAD", "USD/JPY"])
  assert.deepEqual(quotes["USD/CAD"].closes, [1.3888, 1.3799, 1.3812])
  assert.equal(quotes["USD/CAD"].currency, "CAD", "priced in the quote currency")
  assert.equal(quotes["USD/CAD"].priceHint, 4, "FX needs more than two decimals")
  assert.equal(quotes["USD/CAD"].asOf, "2026-09-03")
})

// --- registry hardening ---------------------------------------------------

test("a provider id cannot contain the ref separator", () => {
  const R = withAll()
  // "a:b" would format to "A:B:XYZ" and parse back as a bare symbol, breaking
  // the round trip the registry rests on.
  assert.equal(R.validate({ id: "a:b", capabilities: {} }).length, 1)
  assert.throws(() => R.register({ id: "a:b", capabilities: {} }), /must match/)
  assert.deepEqual(R.validate({ id: "sec-edgar_2", capabilities: {} }), [])
})

test("registering a duplicate id is refused, not silently accepted", () => {
  const R = withAll()
  // Clobbering "yahoo" would silently break every existing watchlist.
  assert.throws(() => R.register({ id: "yahoo", capabilities: {} }), /already registered/)
  assert.equal(R.provider("yahoo").label, "Yahoo Finance")
})

test("registration rejects a provider whose capabilities are unbacked", () => {
  const R = withAll()
  const problems = R.validate({ id: "broken", capabilities: { quote: true, chart: true } })
  assert.equal(problems.length, 4)
  assert.ok(problems.some(p => /quote.*quoteRequest/.test(p)))
  assert.ok(problems.some(p => /chart.*parseChart/.test(p)))
  assert.throws(() => R.register({ id: "broken", capabilities: { quote: true } }), /invalid provider/)
  // A rejected provider must not be left half-registered.
  assert.equal(R.has("broken"), false)
})

test("search may be satisfied by a local catalogue instead of a request", () => {
  const R = withAll()
  assert.deepEqual(R.validate({ id: "local", capabilities: { search: true }, searchLocal: () => [] }), [])
  assert.deepEqual(R.validate({
    id: "remote", capabilities: { search: true }, searchRequest: () => null, parseSearch: () => []
  }), [])
})

test("normalizeId is actually applied when a ref is parsed", () => {
  const R = withAll()
  R.register({
    id: "lower",
    capabilities: { quote: true },
    normalizeId: raw => String(raw).toLowerCase(),
    quoteRequest: () => null,
    parseQuotes: () => ({})
  })
  // Refs are stored uppercased; a lowercase-id source must get its case back.
  assert.equal(R.parseRef("LOWER:BITCOIN").id, "bitcoin")
  assert.equal(R.parseRef("AAPL").id, "AAPL", "Yahoo ids stay uppercase")
})

test("every shipped provider satisfies the documented contract", () => {
  const R = withAll()
  for (const provider of R.providers())
    assert.deepEqual(R.validate(provider), [], `${provider.id} violates the contract`)
})

// Keeps src/Providers/README.md honest: its minimal example must register.
test("the minimal provider documented in the README is valid", () => {
  const R = withAll()
  const example = {
    id: "example",
    label: "Example",
    capabilities: { quote: true, chart: false, search: false, detail: false, extendedHours: false },
    quoteRequest: ids => ids && ids.length
      ? { argv: ["curl", "-fsS", "--max-time", "10", "https://example.com/api?ids=" + encodeURIComponent(ids.join(","))] }
      : null,
    parseQuotes: () => ({})
  }
  assert.deepEqual(R.validate(example), [])
  assert.ok(R.register(example))
  assert.equal(R.parseRef("EXAMPLE:ABC").providerId, "example")
  assert.equal(R.formatRef("example", "ABC"), "EXAMPLE:ABC")
  assert.equal(R.requestList(example.quoteRequest(["ABC"])).length, 1)
})

test("a search query is split without folding its case", () => {
  const R = allProviders()
  // parseRef would run the remainder through normalizeId and uppercase it,
  // changing the request Yahoo receives.
  assert.deepEqual(R.parseQuery("apple"), { providerId: "yahoo", term: "apple" })
  assert.deepEqual(R.parseQuery("BOC:5 year"), { providerId: "boc", term: "5 year" })
  assert.deepEqual(R.parseQuery("boc:mortgage"), { providerId: "boc", term: "mortgage" })
  assert.equal(R.parseRef("BOC:v80691335").id, "V80691335", "ids are still folded")
})

test("an explicitly prefixed default-provider ref collapses to the bare symbol", () => {
  const R = allProviders()
  // Quotes are keyed by formatRef, which returns bare for the default provider,
  // so "YAHOO:AAPL" would otherwise never receive a price.
  assert.equal(R.canonicalRef("YAHOO:AAPL"), "AAPL")
  assert.equal(R.canonicalRef("AAPL"), "AAPL")
  assert.equal(R.canonicalRef("BOC:V80691335"), "BOC:V80691335")
})

test("FX pairs are discoverable rather than requiring exact recall", () => {
  const R = allProviders()
  const fx = R.provider("fx")
  assert.equal(fx.capabilities.search, true)
  assert.ok(fx.searchLocal("cad").map(r => r.symbol).includes("USD/CAD"))
  assert.ok(fx.searchLocal("euro").map(r => r.symbol).includes("EUR/USD"))
  assert.equal(fx.searchLocal("").length, Frankfurter.CATALOGUE.length)
  for (const row of Frankfurter.CATALOGUE)
    assert.match(row.id, /^[A-Z]{3}\/[A-Z]{3}$/)
})

// --- third review pass ----------------------------------------------------

test("the default provider is never silently reassigned", () => {
  Registry.reset()
  // Falling back to whatever registered first would route bare symbols to it
  // AND collapse its own namespaced refs to bare form: a total silent cascade.
  Registry.register(BankOfCanada.create(Model))
  assert.equal(Registry.defaultProviderId(), "")
  assert.equal(Registry.formatRef("boc", "V80691335"), "BOC:V80691335")
  Registry.register(Yahoo.create(Model))
  assert.equal(Registry.defaultProviderId(), "yahoo")
})

test("the registration sentinel lives outside QML property bindings", () => {
  const R = allProviders()
  assert.equal(typeof R.bootstrapped, "function")
  assert.equal(typeof R.markBootstrapped, "function")
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // registry() runs during binding evaluation, so writing a QML property here
  // would be a binding loop.
  assert.match(panel, /if \(!Registry\.bootstrapped\(\)\)/)
  assert.doesNotMatch(panel, /property bool providersRegistered/)
})

test("a batched request that fails wholesale is retried id by id", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Valet 404s the entire request if one series id is unknown, which would
  // otherwise blank every entry from that provider.
  assert.match(panel, /function splitFailedBatch\(\)/)
  assert.match(panel, /!root\.quoteBatchSplit && \(root\.quoteBatchIds \|\| \[\]\)\.length > 1 && root\.splitFailedBatch\(\)/)
})

test("a drain that produces no exit signal is abandoned, not latched", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // refresh() waits for the queue to drain, so a curl that never execs would
  // stop the widget refreshing for the rest of the session.
  assert.match(panel, /function abandonQuoteDrain\(\)/)
  assert.match(panel, /id: quoteWatchdog/)
  assert.match(panel, /quoteWatchdog\.restart\(\)/)
  assert.match(panel, /quoteWatchdog\.stop\(\)/)
})

test("adding a symbol matches an existing entry in the same canonical form", () => {
  const R = allProviders()
  // The insert canonicalizes; if the lookup does not, indexOf returns -1 and
  // the list ends up with no row selected.
  const watchlist = ["AAPL", "MSFT"]
  const canonical = R.canonicalRef(Model.normalizeSymbol("yahoo:aapl"))
  assert.equal(canonical, "AAPL")
  assert.equal(Model.addSymbol(watchlist, canonical).length, watchlist.length)
  assert.equal(watchlist.indexOf(canonical), 0)
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /var already = registry\(\)\.canonicalRef\(Model\.normalizeSymbol\(symbol\)\)/)
  assert.match(panel, /var typed = registry\(\)\.canonicalRef\(Model\.normalizeSymbol\(searchQuery/)
})

test("a same-currency FX pair is rejected rather than sent", () => {
  const F = Frankfurter.create(Model)
  // The API answers 422, which would fail the whole base bucket.
  assert.equal(F.chartRequest("USD/USD", "1M"), null)
  assert.equal(F.normalizeId("USD/USD"), "USD/USD")
  const R = allProviders()
  assert.deepEqual(R.requestList(R.provider("fx").quoteRequest(["USD/USD"])), [])
})

test("the user-facing README documents every host the plugin contacts", () => {
  const readme = fs.readFileSync(path.join(root, "README.md"), "utf8")
  // The plugin makes an explicit claim about where data goes; adding hosts
  // without documenting them is a disclosure gap, not a stale doc.
  for (const host of ["finance.yahoo.com", "bankofcanada.ca", "frankfurter.dev"])
    assert.ok(readme.includes(host), `README does not mention ${host}`)
  // And the ref syntax must be discoverable outside the contributor doc.
  assert.match(readme, /`boc:`/)
  assert.match(readme, /`fx:`/)
})

test("a prototype-named provider id registers instead of looking like a duplicate", () => {
  Registry.reset()
  Registry.register(Yahoo.create(Model))
  // The id pattern permits these; a plain {} map resolves them as inherited
  // properties and register() wrongly reports them as already registered.
  // "toString" is correctly rejected by the id pattern (uppercase); these two are not.
  for (const id of ["constructor", "__proto__"]) {
    assert.deepEqual(Registry.validate({ id, capabilities: {} }), [], `${id} should validate`)
    assert.ok(Registry.register({ id, capabilities: {} }), `${id} should register`)
    assert.equal(Registry.provider(id).id, id)
  }
  assert.equal(Registry.provider("yahoo").label, "Yahoo Finance")
})

test("only a failed request drives backoff, never a permanently missing id", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // A delisted ticker or a renamed symbol is missing on every refresh forever.
  // Counting that as a failure saturates the counter at 10 and freezes every
  // healthy symbol in the watchlist behind the one-hour ceiling.
  assert.match(panel, /if \(quoteBatchFailed > 0\)\s*\{[\s\S]{0,200}?quoteFailureCount = Math\.min\(10, quoteFailureCount \+ 1\)/)
  assert.match(panel, /root\.quoteBatchMissing \+= missing;/)
  assert.doesNotMatch(panel, /missing > 0\)\s*\{[\s\S]{0,200}?quoteBatchFailed\+\+/)
  // Missing ids are still reported, just without backing off.
  assert.match(panel, /quoteError = quoteBatchMissing > 0 \? "Some quotes unavailable" : ""/)
})

test("a batch is split only on an HTTP rejection, not a transport failure", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // curl 22 is what -f produces for 4xx/5xx. A DNS failure, reset or 429 hits
  // every id equally, and fanning 30 symbols into 30 sequential requests would
  // make rate limiting worse, not better.
  assert.match(panel, /exitCode === 22 && !root\.quoteBatchSplit/)
})

test("daily-publishing providers declare a refresh floor", () => {
  const R = allProviders()
  // The panel polls every 2s while open; these sources publish once a day.
  for (const id of ["boc", "fx"]) {
    const p = R.provider(id)
    assert.equal(typeof p.minRefreshMs, "function", `${id} declares no refresh floor`)
    assert.ok(p.minRefreshMs() >= 600000, `${id} floor is too short to be polite`)
  }
  // Yahoo is intraday and must stay on the live interval.
  assert.equal(typeof R.provider("yahoo").minRefreshMs, "undefined")
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /now - last < floor/)
})

test("a ref no request covers is reported rather than silently dropped", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Frankfurter refuses a malformed pair, which would otherwise never be
  // fetched and never appear as unavailable.
  assert.match(panel, /quoteUnservable\+\+/)
  assert.match(panel, /No source for these symbols/)
  // Being inside a provider's refresh floor is not an error.
  assert.match(panel, /if \(quoteThrottled === 0\)/)
})

test("a chart the provider refuses reports instead of blanking the view", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  assert.match(panel, /chartError = "No chart for this entry"/)
})

test("a response missing requested ids counts as partial, not success", () => {
  const panel = fs.readFileSync(path.join(root, "src", "Panel.qml"), "utf8")
  // Otherwise the previous value survives in the quote map while the status
  // line claims everything was just updated.
  assert.match(panel, /var missing = 0;/)
  assert.match(panel, /if \(count > 0 && missing > 0\)/)
})
