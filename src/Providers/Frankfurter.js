// Frankfurter provider - European Central Bank reference exchange rates.
//
// https://frankfurter.dev - open, no API key, no rate limit published.
//
// A third shape again, which is the point of it being here: the response is
// keyed by DATE with a nested map of currencies, not by series id, and a symbol
// is a PAIR ("USD/CAD") rather than a single instrument. It also cannot batch
// arbitrary pairs in one call - the API takes a single base per request - so
// this is the provider that requires quoteRequest to return several requests.

var REQUIRES = ["normalizeSymbol", "finiteOrNull"];

var BASE = "https://api.frankfurter.dev/v1/";
var PAIR_SEPARATOR = "/";

// Frankfurter publishes one rate per business day, so an intraday view would be
// a single point.
var RANGE_DAYS = { "1W": 7, "1M": 31, "1Y": 366, "5Y": 1827 };

// ECB reference rates start here; "All" asks from the beginning of the series.
var SERIES_START = "1999-01-04";

// There is no search endpoint, and a pair is not guessable from a ticker, so
// discovery is a small catalogue of the pairs people actually watch. Any other
// pair still works by typing it, e.g. FX:NOK/SEK.
var CATALOGUE = [
    { id: "USD/CAD", name: "US dollar to Canadian dollar" },
    { id: "EUR/USD", name: "Euro to US dollar" },
    { id: "GBP/USD", name: "British pound to US dollar" },
    { id: "USD/JPY", name: "US dollar to Japanese yen" },
    { id: "EUR/GBP", name: "Euro to British pound" },
    { id: "EUR/CAD", name: "Euro to Canadian dollar" },
    { id: "GBP/CAD", name: "British pound to Canadian dollar" },
    { id: "AUD/USD", name: "Australian dollar to US dollar" },
    { id: "USD/CHF", name: "US dollar to Swiss franc" },
    { id: "USD/MXN", name: "US dollar to Mexican peso" }
];

function create(Model) {
    for (var r = 0; r < REQUIRES.length; r++) {
        if (typeof (Model || {})[REQUIRES[r]] !== "function")
            throw new Error("Frankfurter provider: Model." + REQUIRES[r] + " is required");
    }

    var normalizeSymbol = Model.normalizeSymbol;
    var finiteOrNull = Model.finiteOrNull;

    function isoDay(date) {
        return date.toISOString().slice(0, 10);
    }

    function splitPair(id) {
        var raw = normalizeSymbol(id);
        var cut = raw.indexOf(PAIR_SEPARATOR);
        if (cut <= 0)
            return null;
        var base = raw.slice(0, cut);
        var quote = raw.slice(cut + 1);
        if (!base || !quote)
            return null;
        // The API answers 422 for a same-currency pair, which would fail the
        // whole base bucket.
        if (base === quote)
            return null;
        return { base: base, quote: quote, id: base + PAIR_SEPARATOR + quote };
    }

    function startDateFor(rangeKey) {
        var key = String(rangeKey || "");
        var now = new Date();
        if (key === "YTD")
            return isoDay(new Date(Date.UTC(now.getUTCFullYear(), 0, 1)));
        var days = RANGE_DAYS[key];
        if (!days)
            return SERIES_START;
        return isoDay(new Date(now.getTime() - days * 86400000));
    }

    function seriesUrl(base, quotes, from) {
        return BASE + from + ".." + "?base=" + encodeURIComponent(base) + "&symbols=" + encodeURIComponent(quotes.join(","));
    }

    function get(url, ids) {
        return { argv: ["curl", "-fsS", "--max-time", "10", url], ids: (ids || []).slice() };
    }

    // The API takes one base per call, so pairs are bucketed by base and each
    // bucket becomes its own request.
    function groupByBase(ids) {
        var buckets = {};
        var order = [];
        for (var i = 0; i < ids.length; i++) {
            var pair = splitPair(ids[i]);
            if (!pair)
                continue;
            if (!buckets[pair.base]) {
                buckets[pair.base] = [];
                order.push(pair.base);
            }
            if (buckets[pair.base].indexOf(pair.quote) === -1)
                buckets[pair.base].push(pair.quote);
        }
        var out = [];
        for (var j = 0; j < order.length; j++)
            out.push({ base: order[j], quotes: buckets[order[j]] });
        return out;
    }

    // Turns the date-keyed payload into one date-ascending series per pair. The
    // response names its own base, so no request state has to be carried across.
    function seriesFrom(payload) {
        var base = normalizeSymbol(payload && payload.base);
        var rates = (payload && payload.rates) || {};
        var dates = [];
        var date;
        for (date in rates) {
            if (Object.prototype.hasOwnProperty.call(rates, date))
                dates.push(date);
        }
        dates.sort();

        var byId = {};
        for (var i = 0; i < dates.length; i++) {
            var row = rates[dates[i]] || {};
            for (var quote in row) {
                if (!Object.prototype.hasOwnProperty.call(row, quote))
                    continue;
                var value = finiteOrNull(row[quote]);
                if (value === null)
                    continue;
                var id = base + PAIR_SEPARATOR + normalizeSymbol(quote);
                if (!byId[id])
                    byId[id] = { id: id, base: base, quote: normalizeSymbol(quote), points: [] };
                byId[id].points.push({ date: dates[i], value: value });
            }
        }
        return byId;
    }

    function quoteFromSeries(series) {
        if (!series || !series.points.length)
            return null;
        var closes = [];
        for (var i = 0; i < series.points.length; i++)
            closes.push(series.points[i].value);

        var last = closes[closes.length - 1];
        var prev = closes.length > 1 ? closes[closes.length - 2] : null;

        return {
            symbol: series.id,
            name: series.base + " to " + series.quote,
            // Priced in the quote currency, so the existing currency formatting
            // path applies unchanged.
            currency: series.quote,
            price: last,
            previousClose: prev,
            change: prev === null ? null : last - prev,
            changePercent: (prev === null || prev === 0) ? null : ((last - prev) / prev) * 100,
            regularPrice: last,
            regularChangePercent: (prev === null || prev === 0) ? null : ((last - prev) / prev) * 100,
            extendedPrice: null,
            extendedChangePercent: null,
            hasExtended: false,
            session: "closed",
            dayHigh: null,
            dayLow: null,
            volume: null,
            open: null,
            fiftyTwoWeekHigh: null,
            fiftyTwoWeekLow: null,
            // FX needs more precision than a two-decimal price.
            priceHint: 4,
            asOf: series.points[series.points.length - 1].date,
            closes: closes
        };
    }

    function parse(text) {
        try {
            return seriesFrom(JSON.parse(String(text || "{}")));
        } catch (e) {
            return {};
        }
    }

    return {
        id: "fx",
        label: "Frankfurter (ECB)",

        capabilities: {
            search: true,
            quote: true,
            chart: true,
            detail: false,
            extendedHours: false
        },

        // the ECB publishes one rate per business day, so there is nothing to gain from the
        // panel's live interval and a public API to be polite to.
        minRefreshMs: function () {
            return 900000;
        },

        chartRanges: function () {
            return ["1W", "1M", "YTD", "1Y", "5Y", "All"];
        },

        normalizeId: function (raw) {
            var pair = splitPair(raw);
            return pair ? pair.id : normalizeSymbol(raw);
        },

        displayLabel: function (id) {
            return String(id || "");
        },

        // Returns one request per distinct base currency.
        quoteRequest: function (ids) {
            if (!ids || !ids.length)
                return null;
            var groups = groupByBase(ids);
            var out = [];
            for (var i = 0; i < groups.length; i++) {
                // A short window still yields a sparkline and a previous close.
                var covered = [];
                for (var q = 0; q < groups[i].quotes.length; q++)
                    covered.push(groups[i].base + PAIR_SEPARATOR + groups[i].quotes[q]);
                out.push(get(seriesUrl(groups[i].base, groups[i].quotes, startDateFor("1M")), covered));
            }
            return out.length ? out : null;
        },

        chartRequest: function (id, rangeKey) {
            var pair = splitPair(id);
            if (!pair)
                return null;
            return get(seriesUrl(pair.base, [pair.quote], startDateFor(rangeKey)), [pair.id]);
        },

        // Discovery is local; there is no endpoint to call.
        searchLocal: function (query) {
            var q = String(query || "").toUpperCase().replace(/[^A-Z]/g, "");
            var out = [];
            for (var i = 0; i < CATALOGUE.length; i++) {
                var row = CATALOGUE[i];
                var haystack = row.id.replace(PAIR_SEPARATOR, "") + " " + row.name.toUpperCase().replace(/[^A-Z]/g, "");
                if (q && haystack.indexOf(q) === -1)
                    continue;
                out.push({ symbol: row.id, name: row.name, type: "FX", exchange: "ECB" });
            }
            return out;
        },

        detailRequests: function () {
            return [];
        },

        detailStats: function () {
            return [];
        },

        parseQuotes: function (text) {
            var series = parse(text);
            var out = {};
            for (var id in series) {
                if (!Object.prototype.hasOwnProperty.call(series, id))
                    continue;
                var quote = quoteFromSeries(series[id]);
                if (quote)
                    out[id] = quote;
            }
            return out;
        },

        parseChart: function (text, id) {
            var series = parse(text);
            if (id && series[normalizeSymbol(id)])
                return quoteFromSeries(series[normalizeSymbol(id)]);
            for (var key in series) {
                if (Object.prototype.hasOwnProperty.call(series, key))
                    return quoteFromSeries(series[key]);
            }
            return null;
        },

        servedRange: function () {
            return "";
        },

        expectedRange: function () {
            return "";
        }
    };
}

if (typeof module !== "undefined") {
    module.exports = { create: create, CATALOGUE: CATALOGUE };
}
