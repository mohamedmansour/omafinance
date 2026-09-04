function defaultWatchlist() {
  return ["AAPL", "MSFT", "NVDA", "BTC-USD", "ETH-USD"]
}

function defaultPinned() {
  return ["AAPL"]
}

function defaultDetailRange() {
  return "1D"
}

function defaultState() {
  return { watchlist: defaultWatchlist().slice(), pinned: defaultPinned(), detailRange: defaultDetailRange() }
}

function normalizeSymbol(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toUpperCase()
}

function finiteOrNull(value) {
  var n = Number(value)
  return isFinite(n) ? n : null
}

function parseState(raw) {
  var fallback = defaultState()
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return fallback

    var src = Array.isArray(data.watchlist) ? data.watchlist : fallback.watchlist
    var list = []
    var seen = {}
    for (var i = 0; i < src.length; i++) {
      var symbol = normalizeSymbol(src[i])
      if (!symbol || seen[symbol]) continue
      seen[symbol] = true
      list.push(symbol)
    }
    if (list.length === 0) list = fallback.watchlist.slice()

    return {
      watchlist: list,
      pinned: parsePinned(data.pinned, list),
      detailRange: normalizeRange(data.detailRange)
    }
  } catch (e) {
    return fallback
  }
}

function serializeState(watchlist, pinned, detailRange) {
  var list = Array.isArray(watchlist) ? watchlist.slice() : defaultWatchlist().slice()
  return JSON.stringify({
    watchlist: list,
    pinned: parsePinned(pinned, list),
    detailRange: normalizeRange(detailRange)
  }, null, 2) + "\n"
}

function addSymbol(watchlist, symbol) {
  var list = Array.isArray(watchlist) ? watchlist.slice() : []
  var next = normalizeSymbol(symbol)
  if (!next || list.indexOf(next) !== -1 || list.length >= 30) return list
  list.push(next)
  return list
}

function removeSymbol(watchlist, symbol) {
  var drop = normalizeSymbol(symbol)
  var list = Array.isArray(watchlist) ? watchlist : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (normalizeSymbol(list[i]) !== drop) out.push(list[i])
  }
  return out
}

function parsePinned(raw, watchlist) {
  var list = Array.isArray(watchlist) ? watchlist : []
  var src = []
  if (Array.isArray(raw)) src = raw
  else if (typeof raw === "string" && raw) src = [raw]
  var out = []
  var seen = {}
  for (var i = 0; i < src.length; i++) {
    var symbol = normalizeSymbol(src[i])
    if (!symbol || seen[symbol] || list.indexOf(symbol) === -1) continue
    seen[symbol] = true
    out.push(symbol)
  }
  return out
}

function isPinned(pinned, symbol) {
  var next = normalizeSymbol(symbol)
  var pins = Array.isArray(pinned) ? pinned : []
  return next !== "" && pins.indexOf(next) !== -1
}

function togglePinned(pinned, watchlist, symbol) {
  var next = normalizeSymbol(symbol)
  if (!next) return parsePinned(pinned, watchlist)
  var pins = parsePinned(pinned, watchlist)
  var idx = pins.indexOf(next)
  if (idx !== -1) {
    pins.splice(idx, 1)
    return pins
  }
  if (watchlist && watchlist.indexOf(next) !== -1) pins.push(next)
  return pins
}

function barSymbol(pinned, watchlist, index) {
  var pins = Array.isArray(pinned) ? pinned : []
  if (pins.length > 0) {
    var len = pins.length
    var i = ((parseInt(index, 10) || 0) % len + len) % len
    return pins[i]
  }
  var list = Array.isArray(watchlist) ? watchlist : []
  return list.length ? list[0] : ""
}

function searchUrl(query) {
  return "https://query2.finance.yahoo.com/v1/finance/search?q="
    + encodeURIComponent(String(query || ""))
    + "&quotesCount=8&newsCount=0"
}

function sparkUrl(symbols) {
  var list = Array.isArray(symbols) ? symbols.slice() : []
  return "https://query1.finance.yahoo.com/v7/finance/spark?symbols="
    + encodeURIComponent(list.join(","))
    + "&range=1d&interval=5m&includePrePost=true"
}

function chartRanges() {
  return ["1D", "1W", "1M", "YTD", "1Y", "5Y", "All"]
}

function normalizeRange(value) {
  var key = String(value || "")
  var ranges = chartRanges()
  return ranges.indexOf(key) !== -1 ? key : defaultDetailRange()
}

function chartSpec(range) {
  switch (String(range || "1D")) {
    case "1W": return { range: "5d", interval: "15m" }
    case "1M": return { range: "1mo", interval: "1d" }
    case "YTD": return { range: "ytd", interval: "1d" }
    case "1Y": return { range: "1y", interval: "1d" }
    case "5Y": return { range: "5y", interval: "1wk" }
    case "All": return { range: "max", interval: "1mo" }
    default: return { range: "1d", interval: "5m" }
  }
}

function rangeChangePercent(quote, rangeKey) {
  if (!quote) return null
  var key = String(rangeKey || "1D")
  var last = finiteOrNull(quote.price)
  var closes = quote.closes || []
  var nums = []
  var i
  for (i = 0; i < closes.length; i++) {
    var n = Number(closes[i])
    if (isFinite(n)) nums.push(n)
  }
  if (last === null && nums.length) last = nums[nums.length - 1]
  if (key === "1D") {
    var prev = finiteOrNull(quote.previousClose)
    if (prev && last !== null) return ((last - prev) / prev) * 100
    return finiteOrNull(quote.changePercent)
  }
  if (nums.length < 2 || last === null) return finiteOrNull(quote.changePercent)
  var first = nums[0]
  if (!first) return null
  return ((last - first) / first) * 100
}

function chartUrl(symbol, rangeKey) {
  var spec = chartSpec(rangeKey)
  var prepost = String(rangeKey || "1D") === "1D" ? "true" : "false"
  return "https://query1.finance.yahoo.com/v8/finance/chart/"
    + encodeURIComponent(normalizeSymbol(symbol))
    + "?range=" + spec.range
    + "&interval=" + spec.interval
    + "&includePrePost=" + prepost
}

function collectPeriods(value) {
  var out = []
  function walk(v) {
    if (!v) return
    if (Array.isArray(v)) {
      for (var i = 0; i < v.length; i++) walk(v[i])
      return
    }
    if (typeof v === "object" && v.start != null && v.end != null) {
      var a = Number(v.start)
      var b = Number(v.end)
      if (isFinite(a) && isFinite(b)) out.push({ start: a, end: b })
    }
  }
  walk(value)
  return out
}

function inWindows(windows, now) {
  for (var i = 0; i < windows.length; i++) {
    if (now >= windows[i].start && now < windows[i].end) return true
  }
  return false
}

function sessionFromMeta(meta) {
  if (!meta) return "closed"
  if (String(meta.instrumentType || "") === "CRYPTOCURRENCY") return "live"
  var now = Date.now() / 1000
  var periods = meta.tradingPeriods || {}
  var current = meta.currentTradingPeriod || {}
  var pre = collectPeriods(periods.pre).concat(collectPeriods(current.pre))
  var regular = collectPeriods(periods.regular).concat(collectPeriods(current.regular))
  var post = collectPeriods(periods.post).concat(collectPeriods(current.post))
  if (inWindows(regular, now)) return "regular"
  if (inWindows(pre, now)) return "pre"
  if (inWindows(post, now)) return "post"
  return "closed"
}

function rangeCaption(rangeKey, quote) {
  switch (String(rangeKey || "1D")) {
    case "1D":
      var session = quote && quote.session
      if (session === "regular" || session === "live") return "Live"
      return "At Close"
    case "1W": return "Past Week"
    case "1M": return "Past Month"
    case "YTD": return "Year to date"
    case "1Y": return "Past Year"
    case "5Y": return "Past 5 Years"
    case "All": return "All time"
    default: return ""
  }
}

function extendedLabel(quote) {
  if (!quote || !quote.hasExtended) return ""
  if (quote.session === "pre") return "Pre-Market"
  return "After Hours"
}

function parseSearch(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var quotes = data.quotes || []
    var out = []
    var seen = {}
    for (var i = 0; i < quotes.length; i++) {
      var row = quotes[i]
      if (!row || !row.symbol) continue
      var type = String(row.quoteType || "")
      if (type === "FUTURE" || type === "OPTION") continue
      var symbol = normalizeSymbol(row.symbol)
      if (!symbol || seen[symbol]) continue
      seen[symbol] = true
      out.push({
        symbol: symbol,
        name: String(row.shortname || row.longname || symbol),
        type: type,
        exchange: String(row.exchDisp || row.exchange || "")
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function numericCloses(indicators) {
  var quote = indicators && indicators.quote && indicators.quote[0] ? indicators.quote[0] : null
  var closes = quote && quote.close ? quote.close : []
  var out = []
  for (var i = 0; i < closes.length; i++) {
    if (closes[i] === null || closes[i] === undefined || closes[i] === "") continue
    var n = Number(closes[i])
    if (isFinite(n)) out.push(n)
  }
  return out
}

function quoteFromChart(result, fallbackSymbol) {
  if (!result || !result.meta) return null
  var meta = result.meta
  var symbol = normalizeSymbol(meta.symbol || fallbackSymbol)
  if (!symbol) return null

  var regularPrice = finiteOrNull(meta.regularMarketPrice)
  var prev = Number(meta.chartPreviousClose)
  if (!isFinite(prev)) prev = Number(meta.previousClose)
  var regularPct = Number(meta.regularMarketChangePercent)
  if (!isFinite(regularPct) && regularPrice != null && isFinite(prev) && prev !== 0)
    regularPct = ((regularPrice - prev) / prev) * 100
  if (!isFinite(regularPct)) regularPct = null

  var fullday = finiteOrNull(meta.fulldayPrice)
  var fulldayPct = Number(meta.fulldayChangePercent)
  if (!isFinite(fulldayPct)) fulldayPct = null
  var session = sessionFromMeta(meta)
  var hasPrePost = !!meta.hasPrePostMarketData
  var latest = (hasPrePost && fullday != null) ? fullday : regularPrice
  var latestPct = (hasPrePost && fulldayPct != null) ? fulldayPct : regularPct
  var extendedPct = null
  if (regularPrice && fullday != null && regularPrice !== 0)
    extendedPct = ((fullday - regularPrice) / regularPrice) * 100
  var hasExtended = hasPrePost && fullday != null && regularPrice != null
    && Math.abs(fullday - regularPrice) >= 0.005
  var openPx = finiteOrNull(meta.regularMarketOpen)
  if (openPx === 0) openPx = null

  return {
    symbol: symbol,
    name: String(meta.shortName || meta.longName || symbol),
    currency: String(meta.currency || "USD"),
    price: latest,
    previousClose: isFinite(prev) ? prev : null,
    changePercent: latestPct,
    regularPrice: regularPrice,
    regularChangePercent: regularPct,
    extendedPrice: fullday,
    extendedChangePercent: extendedPct,
    hasExtended: hasExtended,
    session: session,
    dayHigh: finiteOrNull(meta.regularMarketDayHigh),
    dayLow: finiteOrNull(meta.regularMarketDayLow),
    volume: finiteOrNull(meta.regularMarketVolume),
    open: openPx,
    fiftyTwoWeekHigh: finiteOrNull(meta.fiftyTwoWeekHigh),
    fiftyTwoWeekLow: finiteOrNull(meta.fiftyTwoWeekLow),
    priceHint: meta.priceHint,
    closes: numericCloses(result.indicators)
  }
}

function parseSpark(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.spark && data.spark.result ? data.spark.result : []
    var out = {}
    for (var i = 0; i < results.length; i++) {
      var item = results[i]
      var resp = item && item.response && item.response[0] ? item.response[0] : null
      var quote = quoteFromChart(resp, item && item.symbol)
      if (quote) out[quote.symbol] = quote
    }
    return out
  } catch (e) {
    return {}
  }
}

function parseChart(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var result = data.chart && data.chart.result && data.chart.result[0] ? data.chart.result[0] : null
    return quoteFromChart(result, "")
  } catch (e) {
    return null
  }
}

function mergeQuotes(current, incoming) {
  var out = {}
  var key
  if (current) {
    for (key in current) {
      if (Object.prototype.hasOwnProperty.call(current, key)) out[key] = current[key]
    }
  }
  if (incoming) {
    for (key in incoming) {
      if (Object.prototype.hasOwnProperty.call(incoming, key)) out[key] = incoming[key]
    }
  }
  return out
}

function withCommas(text) {
  var parts = String(text).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

function priceDecimals(price, hint) {
  var n = Number(price)
  var abs = Math.abs(n)
  var h = parseInt(hint, 10)
  if (isFinite(h) && h >= 0 && h <= 8) {
    if (isFinite(abs) && abs > 0 && abs < 1) return Math.max(h, 4)
    return h
  }
  if (!isFinite(abs)) return 2
  if (abs >= 1) return 2
  if (abs >= 0.01) return 4
  return 6
}

function formatPrice(price, currency, hint) {
  var n = Number(price)
  if (!isFinite(n)) return "—"
  var body = withCommas(n.toFixed(priceDecimals(n, hint)))
  var code = String(currency || "USD")
  if (code === "USD") return "$" + body
  return body + " " + code
}

function formatPercent(pct) {
  var n = Number(pct)
  if (!isFinite(n)) return "—"
  var sign = n > 0 ? "+" : ""
  return sign + n.toFixed(2) + "%"
}

function formatCompact(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  var abs = Math.abs(n)
  if (abs >= 1e12) return (n / 1e12).toFixed(2) + "T"
  if (abs >= 1e9) return (n / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return (n / 1e6).toFixed(2) + "M"
  if (abs >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

function changeTone(pct) {
  var n = Number(pct)
  if (!isFinite(n) || n === 0) return "flat"
  return n > 0 ? "up" : "down"
}

function barLabel(pinned, quote, vertical) {
  var symbol = normalizeSymbol(pinned)
  if (!symbol) return "—"
  var pct = quote ? formatPercent(quote.changePercent) : ""
  if (!pct || pct === "—") return symbol
  return vertical ? (symbol + "\n" + pct) : (symbol + "  " + pct)
}

function suggestionMeta(row) {
  if (!row) return ""
  var parts = []
  if (row.type) parts.push(row.type)
  if (row.exchange) parts.push(row.exchange)
  return parts.join(" · ")
}

function isFavorite(watchlist, symbol) {
  var next = normalizeSymbol(symbol)
  var list = Array.isArray(watchlist) ? watchlist : []
  return next !== "" && list.indexOf(next) !== -1
}

function insightsUrl(symbol) {
  return "https://query1.finance.yahoo.com/ws/insights/v2/finance/insights?symbol="
    + encodeURIComponent(normalizeSymbol(symbol))
}

function quotePageUrl(symbol) {
  return "https://finance.yahoo.com/quote/"
    + encodeURIComponent(normalizeSymbol(symbol)) + "/"
}

function decodeYahooHtml(html) {
  var s = String(html || "")
  if (s.indexOf("\\\"") !== -1) s = s.split("\\\"").join("\"")
  return s
}

function extractRawFmt(decoded, key) {
  var token = "\"" + key + "\":{\"raw\":"
  var i = decoded.indexOf(token)
  if (i < 0) return { raw: null, fmt: "" }
  var rest = decoded.slice(i + token.length)
  var m = String(rest).match(/^(-?[0-9.eE+]+)(?:,\"fmt\":\"([^\"]*)\")?/)
  if (!m) return { raw: null, fmt: "" }
  return { raw: Number(m[1]), fmt: m[2] || "" }
}

function extractQuoted(decoded, key) {
  var token = "\"" + key + "\":\""
  var i = decoded.indexOf(token)
  if (i < 0) return ""
  var rest = decoded.slice(i + token.length)
  var end = rest.indexOf("\"")
  if (end < 0) return ""
  return rest.slice(0, end)
}

function extractEarningsDate(decoded) {
  var token = "\"earningsDate\":["
  var i = decoded.indexOf(token)
  if (i < 0) return { raw: null, fmt: "", estimated: false }
  var rest = decoded.slice(i, i + 600)
  var m = rest.match(/\"raw\":(-?\d+),\"fmt\":\"([^\"]*)\"/)
  var estimated = rest.indexOf("isEarningsDateEst") !== -1 && rest.indexOf("true") !== -1
  if (!m) return { raw: null, fmt: "", estimated: estimated }
  return { raw: Number(m[1]), fmt: m[2], estimated: estimated }
}

function parseQuotePage(html) {
  var decoded = decodeYahooHtml(html)
  var earnings = extractEarningsDate(decoded)
  var marketCap = extractRawFmt(decoded, "marketCap")
  var trailingPE = extractRawFmt(decoded, "trailingPE")
  var forwardPE = extractRawFmt(decoded, "forwardPE")
  var trailingEps = extractRawFmt(decoded, "trailingEps")
  var dividendYield = extractRawFmt(decoded, "dividendYield")
  var dividendRate = extractRawFmt(decoded, "dividendRate")
  var exDividendDate = extractRawFmt(decoded, "exDividendDate")
  var dividendDate = extractRawFmt(decoded, "dividendDate")
  var targetMean = extractRawFmt(decoded, "targetMeanPrice")
  var averageVolume = extractRawFmt(decoded, "averageVolume")
  var beta = extractRawFmt(decoded, "beta")
  var circulating = extractRawFmt(decoded, "circulatingSupply")
  var volume24 = extractRawFmt(decoded, "volume24Hr")
  return {
    marketCap: marketCap.raw,
    trailingPE: trailingPE.raw,
    forwardPE: forwardPE.raw,
    trailingEps: trailingEps.raw,
    dividendYield: dividendYield.raw,
    dividendRate: dividendRate.raw,
    exDividendDate: exDividendDate.fmt || "",
    dividendDate: dividendDate.fmt || "",
    earningsDate: earnings.fmt || "",
    earningsEstimated: earnings.estimated,
    targetMeanPrice: targetMean.raw,
    averageVolume: averageVolume.raw,
    beta: beta.raw,
    sector: extractQuoted(decoded, "sector"),
    industry: extractQuoted(decoded, "industry"),
    circulatingSupply: circulating.raw,
    volume24Hr: volume24.raw
  }
}

function parseInsights(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var result = data.finance && data.finance.result ? data.finance.result : null
    if (!result) return {}
    var rec = result.recommendation || {}
    var valuation = result.instrumentInfo && result.instrumentInfo.valuation ? result.instrumentInfo.valuation : {}
    var technicals = result.instrumentInfo && result.instrumentInfo.keyTechnicals ? result.instrumentInfo.keyTechnicals : {}
    var snapshot = result.companySnapshot || {}
    return {
      rating: rec.rating ? String(rec.rating) : "",
      targetPrice: finiteOrNull(rec.targetPrice),
      valuation: valuation.description ? String(valuation.description) : "",
      valuationDiscount: valuation.discount ? String(valuation.discount) : "",
      support: finiteOrNull(technicals.support),
      resistance: finiteOrNull(technicals.resistance),
      sector: snapshot.sectorInfo ? String(snapshot.sectorInfo) : ""
    }
  } catch (e) {
    return {}
  }
}

function formatIsoDate(iso) {
  var text = String(iso || "")
  var parts = text.split("-")
  if (parts.length < 3) return text
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var month = parseInt(parts[1], 10) - 1
  var day = parseInt(parts[2], 10)
  if (month < 0 || month > 11 || !isFinite(day)) return text
  return months[month] + " " + day + ", " + parts[0]
}

function yieldPercent(value) {
  var n = Number(value)
  if (!isFinite(n) || n === 0) return "—"
  if (n > 0 && n <= 1) n = n * 100
  return n.toFixed(2) + "%"
}

function formatRatio(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  return n.toFixed(2)
}

function nextDividendIso(exIso) {
  var iso = String(exIso || "")
  if (!iso) return { iso: "", estimated: false }
  var stamp = Date.parse(iso + "T00:00:00Z")
  if (!isFinite(stamp)) return { iso: "", estimated: false }
  if (stamp >= Date.now() - 86400000) return { iso: iso, estimated: false }
  var next = new Date(stamp + 91 * 86400000)
  var y = next.getUTCFullYear()
  var m = next.getUTCMonth() + 1
  var d = next.getUTCDate()
  var mm = (m < 10 ? "0" : "") + m
  var dd = (d < 10 ? "0" : "") + d
  return { iso: y + "-" + mm + "-" + dd, estimated: true }
}

function buildDetailStats(quote, page, insights) {
  quote = quote || {}
  page = page || {}
  insights = insights || {}
  var rows = []
  function add(label, value) {
    if (value === undefined || value === null || value === "") return
    if (value === "—") return
    rows.push({ label: label, value: String(value) })
  }

  add("MARKET CAP", page.marketCap ? formatCompact(page.marketCap) : "")
  add("P/E", formatRatio(page.trailingPE) !== "—" ? formatRatio(page.trailingPE) : "")
  add("FWD P/E", formatRatio(page.forwardPE) !== "—" ? formatRatio(page.forwardPE) : "")
  add("EPS", page.trailingEps != null && isFinite(Number(page.trailingEps)) ? Number(page.trailingEps).toFixed(2) : "")
  add("DIV YIELD", yieldPercent(page.dividendYield) !== "—" ? yieldPercent(page.dividendYield) : "")
  add("DIV RATE", page.dividendRate ? formatPrice(page.dividendRate, quote.currency || "USD", 2) : "")
  add("EX-DIVIDEND", page.exDividendDate ? formatIsoDate(page.exDividendDate) : "")
  var nextDiv = nextDividendIso(page.exDividendDate)
  if (nextDiv.iso && nextDiv.estimated) add("EST. NEXT DIV", formatIsoDate(nextDiv.iso))
  else if (nextDiv.iso && page.exDividendDate && nextDiv.iso !== page.exDividendDate)
    add("NEXT DIVIDEND", formatIsoDate(nextDiv.iso))
  add("DIV PAY DATE", page.dividendDate ? formatIsoDate(page.dividendDate) : "")
  add("NEXT EARNINGS", page.earningsDate ? ((page.earningsEstimated ? "Est. " : "") + formatIsoDate(page.earningsDate)) : "")
  add("52W HIGH", quote.fiftyTwoWeekHigh ? formatPrice(quote.fiftyTwoWeekHigh, quote.currency, quote.priceHint) : "")
  add("52W LOW", quote.fiftyTwoWeekLow ? formatPrice(quote.fiftyTwoWeekLow, quote.currency, quote.priceHint) : "")
  add("AVG VOLUME", page.averageVolume ? formatCompact(page.averageVolume) : "")
  add("BETA", formatRatio(page.beta) !== "—" ? formatRatio(page.beta) : "")
  var target = insights.targetPrice || page.targetMeanPrice
  add("TARGET", target ? formatPrice(target, quote.currency || "USD", 2) : "")
  add("RATING", insights.rating ? String(insights.rating).toUpperCase() : "")
  add("VALUATION", insights.valuation || "")
  add("SUPPORT", insights.support ? formatPrice(insights.support, quote.currency, quote.priceHint) : "")
  add("RESISTANCE", insights.resistance ? formatPrice(insights.resistance, quote.currency, quote.priceHint) : "")
  add("SECTOR", page.sector || insights.sector || "")
  add("INDUSTRY", page.industry || "")
  add("SUPPLY", page.circulatingSupply ? formatCompact(page.circulatingSupply) : "")
  add("24H VOL", page.volume24Hr ? formatCompact(page.volume24Hr) : "")
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultWatchlist: defaultWatchlist,
    defaultPinned: defaultPinned,
    defaultState: defaultState,
    normalizeSymbol: normalizeSymbol,
    parseState: parseState,
    serializeState: serializeState,
    addSymbol: addSymbol,
    removeSymbol: removeSymbol,
    parsePinned: parsePinned,
    isPinned: isPinned,
    togglePinned: togglePinned,
    barSymbol: barSymbol,
    searchUrl: searchUrl,
    sparkUrl: sparkUrl,
    chartRanges: chartRanges,
    normalizeRange: normalizeRange,
    chartSpec: chartSpec,
    chartUrl: chartUrl,
    rangeChangePercent: rangeChangePercent,
    rangeCaption: rangeCaption,
    extendedLabel: extendedLabel,
    parseSearch: parseSearch,
    parseSpark: parseSpark,
    parseChart: parseChart,
    mergeQuotes: mergeQuotes,
    formatPrice: formatPrice,
    formatPercent: formatPercent,
    formatCompact: formatCompact,
    changeTone: changeTone,
    barLabel: barLabel,
    suggestionMeta: suggestionMeta,
    isFavorite: isFavorite,
    insightsUrl: insightsUrl,
    quotePageUrl: quotePageUrl,
    parseQuotePage: parseQuotePage,
    parseInsights: parseInsights,
    formatIsoDate: formatIsoDate,
    buildDetailStats: buildDetailStats
  }
}
