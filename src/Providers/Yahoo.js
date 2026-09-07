// Yahoo Finance provider.
//
// Owns every Yahoo-specific concern: the undocumented query1/query2 endpoints,
// the extended-hours session model, the HTML scrape behind the fundamentals
// table, and the shape of that table itself. Nothing outside this file should
// know Yahoo exists.
//
// create(Model) returns the provider object. Dependencies arrive by injection
// rather than import because `.import` is QML-only syntax that Node cannot
// require, and the tests require this file directly.

// Checked up front so a missing export fails at startup instead of being
// swallowed by a parser's catch block and degrading into a stream of nulls.
var REQUIRES = ["normalizeSymbol", "finiteOrNull", "formatPrice", "formatCompact"];

// Yahoo answers some errors with HTTP 200, so detail payloads are validated
// rather than trusted.
var DETAIL_KINDS = ["insights", "quotePage"];

function create(Model) {
    for (var r = 0; r < REQUIRES.length; r++) {
        if (typeof (Model || {})[REQUIRES[r]] !== "function")
            throw new Error("Yahoo provider: Model." + REQUIRES[r] + " is required");
    }

    var normalizeSymbol = Model.normalizeSymbol;
    var finiteOrNull = Model.finiteOrNull;
    var formatPrice = Model.formatPrice;
    var formatPercent = Model.formatPercent;
    var formatCompact = Model.formatCompact;

    var UA = "Mozilla/5.0";

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

    function chartUrl(symbol, rangeKey) {
      var spec = chartSpec(rangeKey)
      var prepost = String(rangeKey || "1D") === "1D" ? "true" : "false"
      return "https://query1.finance.yahoo.com/v8/finance/chart/"
        + encodeURIComponent(normalizeSymbol(symbol))
        + "?range=" + spec.range
        + "&interval=" + spec.interval
        + "&includePrePost=" + prepost
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

    function insightsUrl(symbol) {
      return "https://query1.finance.yahoo.com/ws/insights/v2/finance/insights?symbol="
        + encodeURIComponent(normalizeSymbol(symbol))
    }

    function quotePageUrl(symbol) {
      return "https://finance.yahoo.com/quote/"
        + encodeURIComponent(normalizeSymbol(symbol)) + "/"
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

    function quoteFromChart(result, fallbackSymbol) {
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

    return {
        id: "yahoo",
        label: "Yahoo Finance",

        // Yahoo is the reference implementation: it can do everything.
        capabilities: {
            search: true,
            quote: true,
            chart: true,
            detail: true,
            extendedHours: true
        },

        chartRanges: function () {
            return ["1D", "1W", "1M", "YTD", "1Y", "5Y", "All"];
        },

        normalizeId: function (raw) {
            return normalizeSymbol(raw);
        },

        // A ticker is already the shortest useful label.
        displayLabel: function (id) {
            return String(id || "");
        },

        // One spark call covers the whole batch.
        quoteRequest: function (ids) {
            if (!ids || !ids.length)
                return null;
            return { argv: ["curl", "-fsS", "--max-time", "8", "-A", UA, sparkUrl(ids)], ids: ids.slice() };
        },

        chartRequest: function (id, rangeKey) {
            if (!id)
                return null;
            return { argv: ["curl", "-fsS", "--max-time", "8", "-A", UA, chartUrl(id, rangeKey)] };
        },

        searchRequest: function (query) {
            if (!query)
                return null;
            return { argv: ["curl", "-fsS", "--max-time", "5", "-A", UA, searchUrl(query)] };
        },

        // Two endpoints, fetched independently and merged into one stats table.
        detailRequests: function (id) {
            if (!id)
                return [];
            return [
                { kind: "insights", argv: ["curl", "-fsS", "--max-time", "8", "-A", UA, insightsUrl(id)] },
                { kind: "quotePage", argv: ["curl", "-fsS", "--compressed", "--max-time", "12", "-A", UA, quotePageUrl(id)] }
            ];
        },

        parseQuotes: function (text) {
            return parseSpark(text);
        },

        parseChart: function (text) {
            return parseChart(text);
        },

        parseSearch: function (text) {
            return parseSearch(text);
        },

        parseDetail: function (kind, text) {
            if (kind === "insights")
                return isInsightsResponse(text) ? parseInsights(text) : null;
            if (kind === "quotePage")
                return parseQuotePage(text);
            return null;
        },

        detailStats: function (quote, data) {
            var bag = data || {};
            return buildDetailStats(quote, bag.quotePage, bag.insights);
        },

        // Yahoo silently substitutes a different range than the one requested;
        // the panel drops responses where the two disagree.
        servedRange: function (quote) {
            return quote && quote.yahooRange ? String(quote.yahooRange) : "";
        },

        expectedRange: function (rangeKey) {
            return chartSpec(rangeKey).range;
        }
    };
}

if (typeof module !== "undefined") {
    module.exports = { create: create, DETAIL_KINDS: DETAIL_KINDS };
}
