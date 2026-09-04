# Omafinance

An [Omarchy](https://omarchy.org) bar plugin: an iOS Stocks-style watchlist for equities and crypto.

A pinned ticker sits on the bar. Click it for sparklines, prices, and colored % pills. Search to open a symbol, star it to favorite, then tap through for charts and fundamentals.

## Install

Omarchy loads third-party plugins from git. There is no separate plugin store — users install from the repo URL:

```bash
omarchy plugin add https://github.com/mohamedmansour/omafinance.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/mohamedmansour.finance` and puts **Omafinance** on the bar (center, by default).

Update later with:

```bash
omarchy plugin update mohamedmansour.finance
```

Remove with:

```bash
omarchy plugin remove mohamedmansour.finance
```

## Usage

- **Left click** the bar pill to open the watchlist
- **Middle click** to refresh quotes
- **Search** to find a ticker (stocks or crypto like `BTC-USD`)
- **☆ Favorite** on a search result or the detail header to add it
- **Tap a row** for the detail chart (`1D` `1W` `1M` `YTD` `1Y` `5Y`)
- Hover the detail chart for a price badge
- **Pin** sets which ticker the bar shows
- **Remove** (detail header) deletes a favorite
- **Esc** goes back or closes

The last chart range is remembered.

Toggle from a terminal:

```bash
omarchy-shell mohamedmansour.finance toggle
```

## Data

Quotes come from Yahoo Finance (no API key). Watchlist, pinned ticker, and chart range are stored at:

```
~/.local/state/omarchy/settings/finance.json
```

## Publish / share

Omarchy does not currently have a central plugin catalog. Shipping Omafinance to other Omarchy users is:

1. Push this repo to GitHub (public).
2. Tell people to run:

   ```bash
   omarchy plugin add https://github.com/mohamedmansour/omafinance.git --enable
   ```

3. Optionally share that command on the [Omarchy Discord](https://omarchy.org), Reddit, or a community plugin list.

The installer clones the git URL, validates `manifest.json` at the repo root, and refuses the reserved `omarchy.*` plugin id namespace. This plugin’s id is `mohamedmansour.finance`.

### First-time GitHub publish

From this directory, after `gh auth login`:

```bash
git init
git add .
git commit -m "Initial Omafinance plugin"
gh repo create mohamedmansour/omafinance --public --source=. --remote=origin --push
```

Keep `manifest.json` at the **root** of the default branch. `omarchy plugin add` clones that root; it will not find a nested plugin folder.

## Development

```bash
omarchy plugin validate .
mkdir -p ~/.config/omarchy/plugins
ln -sfn "$(pwd)" ~/.config/omarchy/plugins/mohamedmansour.finance
omarchy-shell shell rescanPlugins
omarchy plugin enable mohamedmansour.finance --section center
```

Validate the **repo path**, not the symlink. The installer forbids symlinks inside a plugin folder.

Saves under `~/.config/omarchy/plugins/` hot-reload. If the shell is showing an old build:

```bash
omarchy restart shell
```

## License

MIT
