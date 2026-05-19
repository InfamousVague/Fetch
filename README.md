# Fetch

A native macOS menu-bar BitTorrent client for **legal** content.

- Real engine: a C shim over **libtorrent 2.0**, vendored & self-contained (no Homebrew at runtime).
- Built-in legal sources: **Internet Archive** (broad search), **Free media**
  (LibriVox / Gutenberg / Blender / Prelinger), **official Linux/BSD ISOs**,
  **Academic Torrents**.
- Add a magnet, import a `.torrent`, choose a download folder, watch
  Downloads/Seeding live from the menu bar (`.accessory`, no Dock icon).
- **Extensible, neutrally:** bring your own **Torznab/Newznab** indexer
  endpoint (URL + key) or **RSS/Atom** feeds, plus extra trackers — all
  user-supplied. Fetch ships and scrapes **no** index sites; what you point
  a custom indexer/feed at is your responsibility.

Not a tool for piracy. The built-in catalog is legal by source; the custom
indexer/feed fields are the standard neutral mechanism (same as
Prowlarr/Jackett/qBittorrent RSS) and exist for legitimate sources you run
or are entitled to use.

## Build / run

```
swift build && swift run            # dev
bash scripts/make-app.sh            # self-contained, Developer-ID-signed Fetch.app
bash scripts/notarize.sh            # notarize + staple (uses suite Apple creds)
```

Requires **macOS 26+** (vendored libtorrent/openssl bottles target 26;
a from-source rebuild would lower that).
