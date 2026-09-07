# Omafinance

**Omafinance** is an Omarchy bar watchlist for stocks and crypto. A pinned ticker (or a rotating set) lives on the bar; click it for sparklines, search-to-favorite, range charts, and fundamentals - no API key.

| Watchlist | Detail |
| :-------: | :----: |
| ![Watchlist](assets/screenshots/home.png) | ![Detail](assets/screenshots/detail.png) |

## Features

- **Bar pill** - pinned ticker(s), current price, and % change in bold, on the right of the bar
- **After hours** - watchlist uses the latest pre/post print; 1D detail shows After Hours next to the close
- **Watchlist** - symbol, name, sparkline, price, and change pill
- **Search** - look up a ticker, open it, then Favorite to keep it
- **Crypto** - Yahoo-style symbols such as `BTC-USD` and `ETH-USD`
- **Rates and FX** - Canadian bond yields and mortgage rates, and ECB exchange rates, alongside tickers
- **Pin rotation** - pin several tickers; the bar cycles them every 5 seconds
- **Detail chart** - `1D` `1W` `1M` `YTD` `1Y` `5Y` `All`, with range % and hover price
- **Fundamentals** - market cap, P/E, dividends, next earnings, 52-week range, target, rating
- **Remembered prefs** - watchlist, pins, and last chart range

No API key. Quotes come from Yahoo Finance; rates and exchange rates come from
the Bank of Canada and the European Central Bank (see [Data sources](#data-sources)).

## Data sources

A watchlist entry is either a plain ticker, which comes from Yahoo Finance, or a
`provider:id` pair. Type the prefix into the search box to search that provider.

| Prefix | Source | Example |
|---|---|---|
| *(none)* | Yahoo Finance | `AAPL`, `BTC-USD` |
| `boc:` | Bank of Canada ([Valet](https://www.bankofcanada.ca/valet/docs)) | `boc:mortgage` to search, or `BOC:BD.CDN.5YR.DQ.YLD` |
| `fx:` | European Central Bank ([Frankfurter](https://frankfurter.dev)) | `fx:cad` to search, or `FX:USD/CAD` |

Rates are shown as percentages, and a change in one is shown in percentage
points (`+0.05 pp`) rather than as a currency amount.

Existing watchlists are unaffected - a plain ticker keeps working exactly as
before. To add a source of your own, see
[`src/Providers/README.md`](src/Providers/README.md).

## Install

```bash
omarchy plugin add https://github.com/mohamedmansour/omafinance.git --enable
```

Omafinance lands on the right of the bar (next to network / audio). A gear in the panel opens settings: independently show or hide the ticker symbol, price, percentage change, and last-updated time, and configure background refresh. The last-updated time is hidden by default. While the panel is open, quotes refresh every two seconds and the active 1D chart every fifteen seconds. Failed requests back off automatically.

## Update

Updates follow git. After new commits are on GitHub:

```bash
omarchy plugin update mohamedmansour.finance
```

You will see a diff, then a fast-forward. The `version` field in `manifest.json` is only a label - you do not need a new version number for the updater to run.

Update every git-managed plugin:

```bash
omarchy plugin update
```

## Uninstall

```bash
omarchy plugin remove mohamedmansour.finance
```

Your watchlist file is left in place (see Data below).

## Usage

| Action | What it does |
| --- | --- |
| Left click the bar pill | Open / close the watchlist |
| Middle click the bar pill | Refresh quotes |
| Type in search | Find a stock or crypto |
| Enter on a search result | Open detail (does not auto-favorite) |
| Favorite | Add or remove the ticker from the watchlist |
| Pin | Add or remove it from the bar rotation |
| Remove | Drop it from the watchlist |
| Click a watchlist row | Open the detail chart |
| Hover the detail chart | Price badge at that point |
| Esc | Back to the list, or close |

Keyboard while the panel is open: `/` to search, `p` to pin the selected row, Esc to go back.

From a terminal:

```bash
omarchy-shell mohamedmansour.finance toggle
```

## Data

Watchlist, pinned tickers, and chart range:

```
~/.local/state/omarchy/settings/finance.json
```

Quotes are fetched with `curl`, directly from whichever source a watchlist entry
belongs to: `query1`/`query2.finance.yahoo.com` and `finance.yahoo.com` for
tickers, `www.bankofcanada.ca` for `boc:` entries, and `api.frankfurter.dev` for
`fx:` entries. Only the symbols you watch, and what you type into the search box,
are sent. Nothing is sent to this project’s servers, and no source is contacted
unless your watchlist contains an entry that belongs to it.

## Tests

The data model and QML smoke tests use Node's built-in test runner and have no development dependencies:

```bash
node --test tests/*.test.js
omarchy plugin validate .
```

## License

MIT
