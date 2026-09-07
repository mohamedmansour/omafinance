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

function quoteSymbolsForView(watchlist, detailSymbol, view) {
  var detail = normalizeSymbol(detailSymbol)
  if (view === "detail" && detail) return [detail]
  return Array.isArray(watchlist) ? watchlist.slice() : []
}

function chartRanges() {
  return ["1D", "1W", "1M", "YTD", "1Y", "5Y", "All"]
}

function normalizeRange(value) {
  var key = String(value || "")
  var ranges = chartRanges()
  return ranges.indexOf(key) !== -1 ? key : defaultDetailRange()
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

if (typeof module !== "undefined") {
  module.exports = {
    defaultWatchlist: defaultWatchlist,
    defaultPinned: defaultPinned,
    defaultState: defaultState,
    normalizeSymbol: normalizeSymbol,
    finiteOrNull: finiteOrNull,
    parseState: parseState,
    serializeState: serializeState,
    addSymbol: addSymbol,
    removeSymbol: removeSymbol,
    parsePinned: parsePinned,
    isPinned: isPinned,
    togglePinned: togglePinned,
    barSymbol: barSymbol,
    quoteSymbolsForView: quoteSymbolsForView,
    chartRanges: chartRanges,
    normalizeRange: normalizeRange,
    rangeChangeAmount: rangeChangeAmount,
    rangeChangePercent: rangeChangePercent,
    rangeCaption: rangeCaption,
    extendedLabel: extendedLabel,
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
  }
}
