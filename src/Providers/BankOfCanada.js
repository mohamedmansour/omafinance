// Bank of Canada provider, backed by the Valet API.
//
// https://www.bankofcanada.ca/valet/docs - open, no API key, no rate limit
// published. Serves the StatCan/CANSIM vectors (V-codes) alongside the Bank's
// own series ids.
//
// This provider is deliberately the inverse of Yahoo in almost every way, which
// is the point: it quotes rates rather than prices, has no intraday data, no
// fundamentals, and no search endpoint. If the registry can carry both, it can
// carry most things.
//
// Valet quirks the parser has to absorb:
//   - Observations come back UNSORTED.
//   - Rows are SPARSE: a batch mixing a daily and a weekly series yields rows
//     that carry only whichever series reported on that date.
//   - Values are strings, and a reported-but-empty value is "".

var REQUIRES = ["normalizeSymbol", "finiteOrNull"];

var BASE = "https://www.bankofcanada.ca/valet/observations/";

// Valet has no search endpoint, so discovery is a curated catalogue. Typing an
// unlisted series id still works - it goes straight through to the API.
var CATALOGUE = [
    { id: "BD.CDN.5YR.DQ.YLD", short: "GoC 5Y", name: "GoC benchmark bond yield: 5 year", group: "Bond yields" },
    { id: "BD.CDN.2YR.DQ.YLD", short: "GoC 2Y", name: "GoC benchmark bond yield: 2 year", group: "Bond yields" },
    { id: "BD.CDN.3YR.DQ.YLD", short: "GoC 3Y", name: "GoC benchmark bond yield: 3 year", group: "Bond yields" },
    { id: "BD.CDN.7YR.DQ.YLD", short: "GoC 7Y", name: "GoC benchmark bond yield: 7 year", group: "Bond yields" },
    { id: "BD.CDN.10YR.DQ.YLD", short: "GoC 10Y", name: "GoC benchmark bond yield: 10 year", group: "Bond yields" },
    { id: "BD.CDN.LONG.DQ.YLD", short: "GoC Long", name: "GoC benchmark bond yield: long-term", group: "Bond yields" },
    { id: "BD.CDN.RRB.DQ.YLD", short: "GoC RRB", name: "Real return bond yield: long-term", group: "Bond yields" },
    { id: "V80691311", short: "Prime", name: "Prime rate", group: "Bank rates" },
    { id: "V80691333", short: "Mtg 1Y", name: "Conventional mortgage: 1-year (posted)", group: "Mortgages" },
    { id: "V80691334", short: "Mtg 3Y", name: "Conventional mortgage: 3-year (posted)", group: "Mortgages" },
    { id: "V80691335", short: "Mtg 5Y", name: "Conventional mortgage: 5-year (posted)", group: "Mortgages" },
    { id: "V122667798", short: "Mtg 5Y+ eff", name: "Effective fixed rate charged, 5yr+", group: "Mortgages" },
    { id: "V122667780", short: "Mtg 5Y+ ins", name: "Insured fixed rate charged, 5yr+", group: "Mortgages" },
    { id: "V122667786", short: "Mtg 5Y+ unins", name: "Uninsured fixed rate charged, 5yr+", group: "Mortgages" },
    { id: "V80691339", short: "GIC 1Y", name: "GIC: 1-year", group: "Deposits" },
    { id: "V80691341", short: "GIC 5Y", name: "GIC: 5-year", group: "Deposits" }
];

// Valet takes an explicit start date; these are the windows behind each range.
var RANGE_DAYS = { "1W": 7, "1M": 31, "1Y": 366, "5Y": 1827 };

function create(Model) {
    for (var r = 0; r < REQUIRES.length; r++) {
        if (typeof (Model || {})[REQUIRES[r]] !== "function")
            throw new Error("BankOfCanada provider: Model." + REQUIRES[r] + " is required");
    }

    var normalizeSymbol = Model.normalizeSymbol;
    var finiteOrNull = Model.finiteOrNull;
    var RATE_UNIT = Model.RATE_UNIT || "%";

    // "5-year", "5 year" and "5yr" all flatten to the same haystack, so the
    // catalogue matches however the user happens to type it.
    function loosen(value) {
        return String(value || "")
            .toLowerCase()
            .replace(/yr\b/g, "year")
            .replace(/[^a-z0-9]+/g, "");
    }

    function isoDay(date) {
        return date.toISOString().slice(0, 10);
    }

    function startDateFor(rangeKey) {
        var key = String(rangeKey || "");
        var now = new Date();
        if (key === "YTD")
            return isoDay(new Date(Date.UTC(now.getUTCFullYear(), 0, 1)));
        var days = RANGE_DAYS[key];
        if (!days)
            return "";
        return isoDay(new Date(now.getTime() - days * 86400000));
    }

    function url(ids, query) {
        var list = [];
        for (var i = 0; i < ids.length; i++) {
            var id = String(ids[i] || "");
            if (id)
                list.push(encodeURIComponent(id));
        }
        return BASE + list.join(",") + "/json" + (query ? "?" + query : "");
    }

    // A request carries the ids it actually covers, so the panel never credits a
    // response with entries it did not ask that call for.
    function request(ids, query) {
        if (!ids || !ids.length)
            return null;
        return { argv: ["curl", "-fsS", "--max-time", "10", url(ids, query)], ids: ids.slice() };
    }

    // Rebuilds one dense, date-ascending series per id out of the sparse rows.
    function seriesFrom(payload) {
        var detail = (payload && payload.seriesDetail) || {};
        var rows = (payload && payload.observations) || [];
        var byId = {};
        var id;

        for (id in detail) {
            if (Object.prototype.hasOwnProperty.call(detail, id))
                byId[id] = { id: id, label: String(detail[id].label || id), points: [] };
        }

        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (!row || !row.d)
                continue;
            for (id in row) {
                if (id === "d" || !Object.prototype.hasOwnProperty.call(row, id))
                    continue;
                if (!byId[id])
                    byId[id] = { id: id, label: id, points: [] };
                var value = finiteOrNull(row[id] && row[id].v);
                if (value === null)
                    continue;
                byId[id].points.push({ date: String(row.d), value: value });
            }
        }

        for (id in byId) {
            if (Object.prototype.hasOwnProperty.call(byId, id)) {
                byId[id].points.sort(function (a, b) {
                    return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0);
                });
            }
        }
        return byId;
    }

    function quoteFromSeries(series) {
        if (!series || !series.points.length)
            return null;
        var points = series.points;
        var closes = [];
        for (var i = 0; i < points.length; i++)
            closes.push(points[i].value);

        var last = closes[closes.length - 1];
        var prev = closes.length > 1 ? closes[closes.length - 2] : null;

        // For a rate, the honest absolute move is in percentage points; the
        // relative move is also true and is what the percent style shows.
        var change = prev === null ? null : last - prev;
        var changePercent = (prev === null || prev === 0) ? null : ((last - prev) / prev) * 100;

        return {
            symbol: series.id,
            name: series.label,
            currency: RATE_UNIT,
            price: last,
            previousClose: prev,
            change: change,
            changePercent: changePercent,
            regularPrice: last,
            regularChangePercent: changePercent,
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
            priceHint: 2,
            asOf: points[points.length - 1].date,
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
        id: "boc",
        label: "Bank of Canada",

        // No search endpoint and no intraday or fundamental data.
        capabilities: {
            search: true,
            quote: true,
            chart: true,
            detail: false,
            extendedHours: false
        },

        // Daily-at-best data, so an intraday range would be a single point.
        // Valet publishes daily at most, so there is nothing to gain from the
        // panel's live interval and a public API to be polite to.
        minRefreshMs: function () {
            return 900000;
        },

        chartRanges: function () {
            return ["1W", "1M", "YTD", "1Y", "5Y", "All"];
        },

        normalizeId: function (raw) {
            return normalizeSymbol(raw);
        },

        // Valet ids are unreadable on a status bar, so the catalogue carries a
        // short human label. An uncatalogued series falls back to its raw id.
        displayLabel: function (id) {
            var key = String(id || "");
            for (var i = 0; i < CATALOGUE.length; i++) {
                if (CATALOGUE[i].id === key)
                    return CATALOGUE[i].short || key;
            }
            return key;
        },

        // Valet batches comma-separated series in one call.
        quoteRequest: function (ids) {
            return request(ids, "recent=40");
        },

        chartRequest: function (id, rangeKey) {
            if (!id)
                return null;
            var start = startDateFor(rangeKey);
            return request([id], start ? "start_date=" + start + "&order_dir=asc" : "order_dir=asc");
        },

        // Discovery is local; there is no endpoint to call.
        searchLocal: function (query) {
            // Match loosely: "5 year", "5-year" and "5yr" should all find the
            // same series, so punctuation is flattened on both sides.
            var q = loosen(query);
            var out = [];
            for (var i = 0; i < CATALOGUE.length; i++) {
                var row = CATALOGUE[i];
                var haystack = loosen(row.id) + " " + loosen(row.name) + " " + loosen(row.group);
                if (q && haystack.indexOf(q) === -1)
                    continue;
                out.push({ symbol: row.id, name: row.name, type: "RATE", exchange: row.group });
            }
            return out;
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
            if (id && series[id])
                return quoteFromSeries(series[id]);
            for (var key in series) {
                if (Object.prototype.hasOwnProperty.call(series, key))
                    return quoteFromSeries(series[key]);
            }
            return null;
        },

        // Valet publishes no fundamentals; a rate series has nothing that maps
        // onto market cap, P/E or a dividend, so the section stays empty.
        detailRequests: function () {
            return [];
        },

        detailStats: function () {
            return [];
        },

        // Valet serves exactly the window asked for, so there is nothing to
        // reconcile the way Yahoo's substituted ranges need.
        servedRange: function () {
            return "";
        },

        expectedRange: function () {
            return "";
        },

        catalogue: function () {
            return CATALOGUE.slice();
        }
    };
}

if (typeof module !== "undefined") {
    module.exports = { create: create, CATALOGUE: CATALOGUE };
}
