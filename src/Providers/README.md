# Writing a provider

A provider teaches the plugin to read one data source. It owns that source's URL
shapes and response parsing, and nothing else in the codebase knows the source
exists.

Three ship today, chosen to be different shapes on purpose:

| File | Provides | Shape it exercises |
|---|---|---|
| `Yahoo.js` | equities, ETFs, crypto | search, intraday, fundamentals, extended hours |
| `BankOfCanada.js` | Canadian rates and bond yields | percentages not prices, daily at best, offline catalogue instead of search |
| `Frankfurter.js` | ECB reference FX rates | responses keyed by date, symbols are pairs, several requests per batch |

## The rules

**Plain JavaScript only.** No `.import`, no `.pragma library`. Both are QML-only
syntax that Node cannot `require`, and the test suite requires these files
directly. Export through the `typeof module !== "undefined"` guard at the bottom,
like every other file here.

**Take `Model` by injection.** Export `create(Model)` returning the provider
object, and check the helpers you need up front:

```js
var REQUIRES = ["normalizeSymbol", "finiteOrNull"];

function create(Model) {
    for (var r = 0; r < REQUIRES.length; r++) {
        if (typeof (Model || {})[REQUIRES[r]] !== "function")
            throw new Error("MyProvider: Model." + REQUIRES[r] + " is required");
    }
    // ...
}
```

That check is not ceremony. The parsers all swallow exceptions, so a missing
helper otherwise degrades into a permanent stream of `null` with no error
anywhere.

**Build argv arrays, never shell strings.** A request is
`{ argv: ["curl", "-fsS", ...] }`. Nothing is passed through a shell, so a
symbol cannot inject a command. Put user input in the URL through
`encodeURIComponent`, and make sure the URL is the last element and starts with
`https://` — a test enforces both.

**Ids arrive uppercased.** The state file uppercases everything, so a source
with lowercase ids must fold case in `normalizeId`, which the registry applies
whenever a ref is parsed.

**Declared capabilities are enforced.** `Registry.register` rejects a provider
whose declared capability lacks the methods it needs, and the panel checks
`supports()` before searching or fetching detail — declaring `detail: true` and
not implementing it fails at load, not silently at runtime.

## Registering

Add the file, then register it in `Panel.qml` — imports are QML syntax, so this
is the one place that names each provider:

```qml
import "Providers/MyProvider.js" as MyProvider
// ...
Registry.register(MyProvider.create(Model));
```

`Registry.register` validates the object and throws if a declared capability is
not backed by the methods it needs. A test also asserts that every file in this
directory is registered, so a provider cannot be added and silently forgotten.

## The interface

`id`, `capabilities`, and whatever those capabilities oblige. Everything else is
optional.

```js
{
    id: "myprovider",              // lowercase; namespaces refs as "MYPROVIDER:<id>"
    label: "My Provider",

    capabilities: {
        quote: true,               // needs quoteRequest + parseQuotes
        chart: true,               // needs chartRequest + parseChart
        search: false,             // needs searchRequest + parseSearch, OR searchLocal
        detail: false,             // needs detailRequests + parseDetail
        extendedHours: false       // pre/post-market pricing is meaningful
    }
}
```

### Required by capability

| Method | Returns |
|---|---|
| `quoteRequest(ids)` | one request, or an array of them |
| | each request may carry `ids: [...]` naming what it actually covers; it defaults to the whole batch |
| `parseQuotes(text, ids)` | `{ <id>: quote }`, keyed by **your** ids — the panel namespaces them |
| `chartRequest(id, rangeKey)` | a request |
| `parseChart(text, id, rangeKey)` | one quote, or `null` |
| `searchRequest(query)` + `parseSearch(text)` | a request, then `[{ symbol, name, type, exchange }]` |
| `searchLocal(query)` | the same rows, with no request at all |
| `detailRequests(id)` | `[{ kind, argv }]` — the first **two** kinds are fetched |
| `parseDetail(kind, text)` | parsed payload, or `null` when unusable |

`rangeKey` is one of `1D 1W 1M YTD 1Y 5Y All`.

Return `null` from any `*Request` when you cannot serve the input — an empty id
list, an unparseable symbol. The panel skips the fetch rather than issuing a
broken one.

`parseDetail` returning `null` means "unusable", which makes the panel count a
failure and retry with backoff. Validate there: Yahoo answers some errors with
HTTP 200.

### Optional

| Method | Default if absent |
|---|---|
| `chartRanges()` | all ranges offered |
| `displayLabel(id, quote)` | the raw id |
| `detailStats(quote, data)` | no detail rows |
| `normalizeId(raw)` | used as-is |
| `servedRange(quote)` / `expectedRange(rangeKey)` | no range reconciliation |

`servedRange`/`expectedRange` exist because Yahoo silently substitutes a
different range than the one requested; the panel drops responses where the two
disagree. If your API serves exactly what it is asked, return `""` from both.

`detailStats` receives a bag keyed by your own `detailRequests` kinds and returns
`[{ label, value }]`. There are two detail process slots, so only the first two
kinds you declare are fetched.

### The quote object

`parseQuotes` and `parseChart` both produce these. Only the first five matter;
everything else may be `null` and the UI adapts.

```js
{
    symbol: "USD/CAD",      // your id, not the namespaced ref
    name: "USD to CAD",
    currency: "CAD",        // or Model.RATE_UNIT ("%") for a rate
    price: 1.38,
    closes: [1.37, 1.38],   // date-ascending; drives the sparkline

    previousClose, change, changePercent,
    regularPrice, regularChangePercent,
    extendedPrice, extendedChangePercent, hasExtended,
    session,                // "regular" | "pre" | "post" | "closed" | "live"
    dayHigh, dayLow, open, volume,
    fiftyTwoWeekHigh, fiftyTwoWeekLow,
    priceHint: 4,           // decimal places; 2 if omitted
    asOf: "2026-09-04"
}
```

Set `currency` to `Model.RATE_UNIT` when the value is a percentage rather than a
price. It then renders as `3.41%`, and changes render in percentage points
(`+0.05 pp`) instead of a currency amount.

## A minimal provider

```js
var REQUIRES = ["finiteOrNull"];

function create(Model) {
    for (var r = 0; r < REQUIRES.length; r++) {
        if (typeof (Model || {})[REQUIRES[r]] !== "function")
            throw new Error("Example: Model." + REQUIRES[r] + " is required");
    }

    return {
        id: "example",
        label: "Example",
        capabilities: { quote: true, chart: false, search: false, detail: false, extendedHours: false },

        quoteRequest: function (ids) {
            if (!ids || !ids.length)
                return null;
            return { argv: ["curl", "-fsS", "--max-time", "10",
                "https://example.com/api?ids=" + encodeURIComponent(ids.join(","))] };
        },

        parseQuotes: function (text) {
            try {
                var rows = JSON.parse(String(text || "{}")).rows || [];
                var out = {};
                for (var i = 0; i < rows.length; i++) {
                    out[rows[i].id] = {
                        symbol: rows[i].id,
                        name: rows[i].name,
                        currency: "USD",
                        price: Model.finiteOrNull(rows[i].price),
                        closes: rows[i].history || []
                    };
                }
                return out;
            } catch (e) {
                return {};
            }
        }
    };
}

if (typeof module !== "undefined") {
    module.exports = { create: create };
}
```

## Testing

`node --test tests/` runs everything. The suite in `tests/providers.test.js`
walks this directory and iterates every registered provider, so a new one is
automatically checked for QML-only syntax, shell-free HTTPS requests,
empty-input handling, and registration in `Panel.qml`. Register it in
`freshRegistry()`/`withAll()` there so those loops cover it.

Parser tests should use a recorded payload rather than a live call — see the
Bank of Canada sparse-rows test for the pattern.

While developing: `omarchy restart shell`. Saving a file is not enough, and
`rescanPlugins` re-registers the plugin but reuses the cached QML component.

## Sources verified as usable

Free, no key, reachable with `curl` as of September 2026:

- **Bank of Canada Valet** — Canadian rates, CANSIM vectors. *(shipped)*
- **Frankfurter** — ECB FX reference rates. *(shipped)*
- **US Treasury FiscalData** — yield curve and average interest rates. Note its
  query parameters use brackets, so `curl` needs `-g` or percent-encoding.
- **World Bank** — country indicators; slow, around 20s.
- **CoinGecko** — crypto, though Yahoo already covers it.

**Stooq** is behind a JavaScript bot wall and cannot be read with `curl`.
