function defaultWatchlist() {
  return []
}

function defaultPinned() {
  return []
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
  if (value === null || value === undefined) return null
  if (typeof value === "string" && value.replace(/^\s+|\s+$/g, "") === "") return null
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
  var list = Array.isArray(watchlist) ? watchlist.slice() : []
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

function quoteSymbolsForView(watchlist, detailSymbol, view) {
  var detail = normalizeSymbol(detailSymbol)
  if (view === "detail" && detail) return [detail]
  return Array.isArray(watchlist) ? watchlist.slice() : []
}

function chartRanges() {
  return ["60", "1D", "1W", "1M", "YTD", "1Y"]
}

function normalizeRange(value) {
  var key = String(value || "")
  var ranges = chartRanges()
  return ranges.indexOf(key) !== -1 ? key : defaultDetailRange()
}

function chartSpec(range) {
  switch (String(range || "1D")) {
    case "60": return { range: "1mo", interval: "60m" }
    case "1W": return { range: "5y", interval: "1wk" }
    case "1M": return { range: "max", interval: "1mo" }
    case "YTD": return { range: "ytd", interval: "1d" }
    case "1Y": return { range: "max", interval: "1mo" }
    default: return { range: "1y", interval: "1d" }
  }
}

function rangeChangeAmount(quote, rangeKey) {
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
    if (prev != null && last !== null) return last - prev
    return finiteOrNull(quote.change)
  }
  if (nums.length < 2 || last === null) return finiteOrNull(quote.change)
  var first = nums[0]
  if (first == null) return null
  return last - first
}

function rangeChangePercent(quote, rangeKey) {
  if (!quote) return null
  var key = String(rangeKey || "1D")
  var last = finiteOrNull(quote.price)
  var closes = quote.closes || []
  var nums = []
  var i
  for (i = 0; i < closes.length; i++) {
    var n = finiteOrNull(closes[i])
    if (n !== null) nums.push(n)
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
  var prepost = "false"
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
    case "60": return "60-Minute Candles (1 Month)"
    case "1D": return "1-Day Candles (1 Year)"
    case "1W": return "1-Week Candles (5 Years)"
    case "1M": return "1-Month Candles (All Time)"
    case "YTD": return "Year to date (Daily)"
    case "1Y": return "1-Year Candles (All Time)"
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
      if (type === "OPTION") continue
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

function aggregateYearlyCandles(candles) {
  var map = {}
  var years = []
  for (var i = 0; i < candles.length; i++) {
    var c = candles[i]
    if (!c || !c.timestamp) continue
    var yr = new Date(c.timestamp * 1000).getFullYear()
    if (!map[yr]) {
      map[yr] = {
        timestamp: c.timestamp,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
        volume: c.volume || 0
      }
      years.push(yr)
    } else {
      var existing = map[yr]
      existing.high = Math.max(existing.high, c.high)
      existing.low = Math.min(existing.low, c.low)
      existing.close = c.close
      existing.volume += (c.volume || 0)
    }
  }
  var out = []
  for (var k = 0; k < years.length; k++) {
    out.push(map[years[k]])
  }
  return out
}

function parseCandles(timestamps, indicators) {
  var quote = indicators && indicators.quote && indicators.quote[0] ? indicators.quote[0] : null
  if (!quote || !quote.close) return []
  var ts = Array.isArray(timestamps) ? timestamps : []
  var opens = quote.open || []
  var highs = quote.high || []
  var lows = quote.low || []
  var closes = quote.close || []
  var volumes = quote.volume || []
  var out = []
  var len = closes.length
  for (var i = 0; i < len; i++) {
    var c = finiteOrNull(closes[i])
    if (c === null) continue
    var o = finiteOrNull(opens[i])
    var h = finiteOrNull(highs[i])
    var l = finiteOrNull(lows[i])
    var v = finiteOrNull(volumes[i])
    var t = i < ts.length ? finiteOrNull(ts[i]) : null
    if (o === null) o = c
    if (h === null) h = Math.max(o, c)
    if (l === null) l = Math.min(o, c)
    h = Math.max(h, o, c)
    l = Math.min(l, o, c)
    out.push({
      timestamp: t,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v != null ? v : 0
    })
  }
  return out
}

function quoteFromChart(result, fallbackSymbol, rangeKey) {
  if (!result || !result.meta) return null
  var meta = result.meta
  var symbol = normalizeSymbol(meta.symbol || fallbackSymbol)
  if (!symbol) return null

  var regularPrice = finiteOrNull(meta.regularMarketPrice)
  var prev = finiteOrNull(meta.chartPreviousClose)
  if (prev === null) prev = finiteOrNull(meta.previousClose)
  var regularPct = finiteOrNull(meta.regularMarketChangePercent)
  if (regularPct === null && regularPrice != null && prev !== null && prev !== 0)
    regularPct = ((regularPrice - prev) / prev) * 100

  var fullday = finiteOrNull(meta.fulldayPrice)
  var fulldayPct = finiteOrNull(meta.fulldayChangePercent)
  var session = sessionFromMeta(meta)
  var hasPrePost = !!meta.hasPrePostMarketData
  var extendedPct = null
  if (regularPrice && fullday != null && regularPrice !== 0)
    extendedPct = ((fullday - regularPrice) / regularPrice) * 100
  if (extendedPct == null && isFinite(fulldayPct)) extendedPct = fulldayPct
  var hasExtended = hasPrePost && fullday != null && regularPrice != null
    && Math.abs(fullday - regularPrice) >= 0.005
  var useExtended = hasExtended && session !== "regular" && session !== "live"
  var latest = useExtended ? fullday : regularPrice
  var latestPct = useExtended ? (fulldayPct != null ? fulldayPct : extendedPct) : regularPct
  var latestChange = null
  if (useExtended) {
    latestChange = finiteOrNull(meta.fulldayChange)
    if (latestChange == null && fullday != null && regularPrice != null)
      latestChange = fullday - regularPrice
  } else {
    latestChange = finiteOrNull(meta.regularMarketChange)
    if (latestChange == null && regularPrice != null && isFinite(prev))
      latestChange = regularPrice - prev
  }
  var openPx = finiteOrNull(meta.regularMarketOpen)
  if (openPx === 0) openPx = null

  var candles = parseCandles(result.timestamp, result.indicators)
  var closes = numericCloses(result.indicators)
  if (rangeKey === "1Y") {
    candles = aggregateYearlyCandles(candles)
    closes = []
    for (var k = 0; k < candles.length; k++) {
      closes.push(candles[k].close)
    }
  }

  return {
    symbol: symbol,
    name: String(meta.shortName || meta.longName || symbol),
    currency: String(meta.currency || "USD"),
    price: latest,
    previousClose: prev,
    change: latestChange,
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
    yahooRange: meta.range ? String(meta.range) : "",
    closes: closes,
    candles: candles
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
      var quote = quoteFromChart(resp, item && item.symbol, "1D")
      if (quote) out[quote.symbol] = quote
    }
    return out
  } catch (e) {
    return {}
  }
}

function parseChart(raw, rangeKey) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var result = data.chart && data.chart.result && data.chart.result[0] ? data.chart.result[0] : null
    return quoteFromChart(result, "", rangeKey)
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

function backoffDelay(baseMs, failures, maxMs) {
  var base = Math.max(1, parseInt(baseMs, 10) || 1)
  var count = Math.max(0, Math.min(10, parseInt(failures, 10) || 0))
  var ceiling = Math.max(base, parseInt(maxMs, 10) || base)
  return Math.min(ceiling, base * Math.pow(2, count))
}

function delayedLoaderDelayMs() {
  return 100
}

function shouldShowDelayedLoader(loading, startedAt, now, delayMs) {
  if (!loading) return false
  var started = Number(startedAt)
  var current = Number(now)
  var delay = delayMs == null || delayMs === undefined ? delayedLoaderDelayMs() : Number(delayMs)
  if (!isFinite(started) || started <= 0) return false
  if (!isFinite(current) || !isFinite(delay) || delay < 0) return false
  return (current - started) >= delay
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
  var n = finiteOrNull(price)
  if (n === null) return "-"
  var body = withCommas(n.toFixed(priceDecimals(n, hint)))
  var code = String(currency || "USD")
  if (code === "USD") return "$" + body
  return body + " " + code
}

function formatPercent(pct) {
  var n = finiteOrNull(pct)
  if (n === null) return "-"
  var sign = n > 0 ? "+" : ""
  return sign + n.toFixed(2) + "%"
}

function formatChange(amount, currency, hint) {
  var n = Number(amount)
  if (!isFinite(n)) return "-"
  var sign = n > 0 ? "+" : (n < 0 ? "-" : "")
  var decimals = Math.abs(n) >= 0.01 ? 2 : priceDecimals(n, hint)
  var body = withCommas(Math.abs(n).toFixed(decimals))
  if (String(currency || "USD") === "USD") return sign + "$" + body
  return sign + body + " " + String(currency)
}

function formatQuoteChange(quote, style) {
  if (!quote) return "-"
  if (style === "dollars") return formatChange(quote.change, quote.currency, quote.priceHint)
  return formatPercent(quote.changePercent)
}

function amountFromPercent(price, pct) {
  var p = Number(price)
  var c = Number(pct)
  if (!isFinite(p) || !isFinite(c) || c === -100) return null
  return p * c / (100 + c)
}

function formatChangePair(pct, amount, price, currency, hint) {
  var dollars = amount
  if (dollars == null || !isFinite(Number(dollars)))
    dollars = amountFromPercent(price, pct)
  var p = formatPercent(pct)
  var a = formatChange(dollars, currency, hint)
  if (p === "-" && a === "-") return "-"
  if (a === "-") return p
  if (p === "-") return a
  return a + " (" + p + ")"
}

function formatCompact(value) {
  var n = finiteOrNull(value)
  if (n === null) return "-"
  var abs = Math.abs(n)
  if (abs >= 1e12) return (n / 1e12).toFixed(2) + "T"
  if (abs >= 1e9) return (n / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return (n / 1e6).toFixed(2) + "M"
  if (abs >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

function changeTone(pct) {
  var n = finiteOrNull(pct)
  if (n === null || n === 0) return "flat"
  return n > 0 ? "up" : "down"
}

function barLabel(pinned, quote, vertical, showTicker, showPrice, showChange, style) {
  var symbol = normalizeSymbol(pinned)
  if (!symbol) return "$"
  var parts = []
  if (showTicker !== false) parts.push(symbol)
  var hasPrice = quote && quote.price !== null && quote.price !== undefined
  var hasChange = quote && (style === "dollars"
    ? quote.change !== null && quote.change !== undefined
    : quote.changePercent !== null && quote.changePercent !== undefined)
  var price = hasPrice ? formatPrice(quote.price, quote.currency, quote.priceHint) : ""
  var change = hasChange ? formatQuoteChange(quote, style) : ""
  if (showPrice !== false && price && price !== "-") parts.push(price)
  if (showChange !== false && change && change !== "-") parts.push(change)
  return parts.length ? parts.join(vertical ? "\n" : "  ") : "$"
}

function barLabelTone(quote, showTicker, showPrice, showChange, style) {
  if ((showTicker === false && showPrice === false && showChange === false) || !quote) return "flat"
  return changeTone(style === "dollars" ? quote.change : quote.changePercent)
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

function isInsightsResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    return !!(data.finance && data.finance.error == null && data.finance.result)
  } catch (e) {
    return false
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
  var n = finiteOrNull(value)
  if (n === null || n === 0) return "-"
  if (n > 0 && n <= 1) n = n * 100
  return n.toFixed(2) + "%"
}

function formatRatio(value) {
  var n = finiteOrNull(value)
  if (n === null) return "-"
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

function formatCandleTime(timestamp, rangeKey) {
  var t = Number(timestamp)
  if (!isFinite(t) || t <= 0) return ""
  var d = new Date(t * 1000)
  var range = String(rangeKey || "1D")
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var mon = months[d.getMonth()]
  var day = d.getDate()
  var year = d.getFullYear()
  var hours = d.getHours()
  var minutes = d.getMinutes()
  var ampm = hours >= 12 ? "PM" : "AM"
  var h12 = hours % 12 || 12
  var mStr = (minutes < 10 ? "0" : "") + minutes
  var timeStr = h12 + ":" + mStr + " " + ampm

  if (range === "60") return mon + " " + day + " " + timeStr
  if (range === "1Y") return String(year)
  if (range === "1M" || range === "All") return mon + " " + year
  return mon + " " + day + ", " + year
}

function buildDetailStats(quote, page, insights) {
  quote = quote || {}
  page = page || {}
  insights = insights || {}
  var rows = []
  function add(label, value) {
    if (value === undefined || value === null || value === "") return
    if (value === "-") return
    rows.push({ label: label, value: String(value) })
  }

  add("MARKET CAP", page.marketCap ? formatCompact(page.marketCap) : "")
  add("P/E", formatRatio(page.trailingPE) !== "-" ? formatRatio(page.trailingPE) : "")
  add("FWD P/E", formatRatio(page.forwardPE) !== "-" ? formatRatio(page.forwardPE) : "")
  add("EPS", page.trailingEps != null && isFinite(Number(page.trailingEps)) ? Number(page.trailingEps).toFixed(2) : "")
  add("DIV YIELD", yieldPercent(page.dividendYield) !== "-" ? yieldPercent(page.dividendYield) : "")
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
  add("BETA", formatRatio(page.beta) !== "-" ? formatRatio(page.beta) : "")
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
    quoteSymbolsForView: quoteSymbolsForView,
    chartRanges: chartRanges,
    normalizeRange: normalizeRange,
    chartSpec: chartSpec,
    chartUrl: chartUrl,
    rangeChangeAmount: rangeChangeAmount,
    rangeChangePercent: rangeChangePercent,
    rangeCaption: rangeCaption,
    extendedLabel: extendedLabel,
    parseSearch: parseSearch,
    parseSpark: parseSpark,
    parseChart: parseChart,
    parseCandles: parseCandles,
    aggregateYearlyCandles: aggregateYearlyCandles,
    mergeQuotes: mergeQuotes,
    backoffDelay: backoffDelay,
    delayedLoaderDelayMs: delayedLoaderDelayMs,
    shouldShowDelayedLoader: shouldShowDelayedLoader,
    formatPrice: formatPrice,
    formatPercent: formatPercent,
    formatChange: formatChange,
    formatQuoteChange: formatQuoteChange,
    amountFromPercent: amountFromPercent,
    formatChangePair: formatChangePair,
    formatCompact: formatCompact,
    changeTone: changeTone,
    barLabel: barLabel,
    barLabelTone: barLabelTone,
    suggestionMeta: suggestionMeta,
    isFavorite: isFavorite,
    insightsUrl: insightsUrl,
    quotePageUrl: quotePageUrl,
    parseQuotePage: parseQuotePage,
    parseInsights: parseInsights,
    isInsightsResponse: isInsightsResponse,
    formatIsoDate: formatIsoDate,
    formatCandleTime: formatCandleTime,
    buildDetailStats: buildDetailStats
  }
}
