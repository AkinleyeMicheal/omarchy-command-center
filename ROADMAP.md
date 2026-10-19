# Command Center — Roadmap

Living tracker for `fonsgaudii.cmdcenter`. Update status here whenever a phase
lands. Decisions and open questions live at the bottom.

## Vision

A universal launcher for Omarchy: browsable command center (367 omarchy
commands + apps) as the core, with Raycast-style universal search, a calm
dashboard, deep Omarchy integration, and an RSS news reader.

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 1–3 | Core palette: search, groups, apps launch, parameters/forms, frecency, pins, lazy `--help`, recents strip, IPC, confirm dialogs, state in XDG dir | ✅ done |
| 4 | **Universal search foundation**: provider pipeline (computed rows + fallback rows), inline calculator (`MathEval.js`, no eval/shell), unit conversion (`Units.js`), web-search fallback, agent-search fallback, action routing (Enter instant-act, Ctrl+C/T semantics), verified glyphs | ✅ done |
| 4b | Browser-default web engine detection (`detect-env.sh` + override file), default-agent-first rows via `omarchy agent prompt` (`Agents.js` mirrors omarchy-agent's table), `@` agent-prefix mode, minimalistic web/agent detail card | ✅ done |
| 4c | **Hybrid recents removal**: hover ✕ on recent tiles (manual forget via `update-usage.sh forget`), 30-day strip auto-expiry, 90-day usage.json sweep — ✅ verified end-to-end (forget hits disk; 40d-aging drops the tile live via file watch; state restored) | ✅ done |
| — | Cache-staleness check: `build-catalog.sh --if-stale` mtime gate (sources newer than cache → full rebuild, else 20ms no-op), triggered once per session from a delayed startup timer — ✅ verified (fresh: ~21ms exit; stale: 2.5s rebuild) | ✅ done |
| 5 | **Deep Omarchy**: Controls group (live status readouts + 6 toggles + 4 settings panels + 6 session actions with confirmation), search integration (curated action rows seat above command matches — `"wifi"` → toggle row first), History timeline from usage.json with per-entry forget, live `status.sh` probe. All runs argv-only (`Quickshell.execDetached`, no shell string); commands mirror omarchy-menu.jsonc, drift-guarded by tests. Playbooks/chained commands deferred | ✅ done |
| 5+ | **Sticky footer control rail**: always-visible tile strip at the card's bottom edge — domain tiles with live state lighting + hover tooltips **and hover backgrounds on tiles and popover rows**; single-control tiles act directly (toggles flip in place, panels open), multi-control tiles (audio, power) pop an anchored mini-popover. Audio popover = output/mic mute rows + volume sliders (PanelSlider, right-click also mutes) + open-panel row; power popover = battery line + gated session actions reusing the shared confirm dialog. Wired-only boxes get a Wired tile; all glyphs verified by name; controls tests 197→236 | ✅ done |
| 6a | **RSS/Atom news reader**: News group with Refresh + Edit-feeds rows and the latest stories across user-configured feeds; `feeds.json` (user-owned, seeds with Hacker News + Lobsters on first run), `fetch-feeds.sh` (curl, atomic `news.json` with raw XML embedded, `--max-age` quiet-refresh gate, per-feed **feed favicons** cached in `news-img/`, `--fetch-images` mode for positional **article heroes**), pure `FeedParser.js` (RSS 2.0 + Atom, CDATA/entities/guid-permalinks, hero extraction: media:content/thumbnail/enclosure/desc-`<img>`, feed-provided **excerpts** ~600 chars word-cut (≥30 chars substance — lone "Comments" links dropped), 45 fixture tests). List rows show the feed logo (fallback: newspaper glyph); story card = hero image + title + inline favicon · source/age + excerpt (7 lines) + **"Continue reading in browser"** (Ctrl+C copies link); Edit-feeds row opens `feeds.json` in `$EDITOR`; list. **Inline add**: paste any URL (page or feed) as the query → an "Add as feed" row leads the results; `add-feed.sh` follows a page's declared `<link rel=alternate>`, validates XML, dedupes, then refreshes. Quiet background fetch on startup + on entering News when cache >30min old; opens via `Qt.openUrlExternally` | ✅ done |
| 6b | **Dashboard home cards**: ambient tile row above the recents strip, shown only on the default view (group `*`, no query — hidden the instant a query is typed). **Weather** = one `omarchy weather icon` + `weather status` subprocess (5-min throttle on open; the U+E313 condition glyph renders because JetBrains Mono NF covers legacy-PUA — verified by cmap scan before use), parsed by `Dashboard.parseWeatherOutput`/`parseWeatherLine` into city/temp/wind. **Now-playing** = Quickshell's own `Quickshell.Services.Mpris` (`Mpris.players.values`, `player.isPlaying`/`canTogglePlaying` — no playerctl needed), tile joins only while a player has a title, whole-card click = play/pause with hover tint. **System** = CPU/MEM from the existing status probe. **Today** = weekday/date/ISO week (no stock events source exists → date card; events = Phase 8 if ever configured). `Dashboard.js` pure builders + 21 fixture tests (ISO-week cross-year/leap vectors) | ✅ done |
| 6b.1 | **Media strip refinement** (user QA): dashboard shrunk to one slim row — every tile 35px (⅓ of the original 104; the middle pane is only ~512px wide, so 3 tiles, not 4): wide **media strip** + **weather·today** merged (city/ISO-week caption, `24°C · 17 Oct` value via `Dashboard.shortDate`) + **system** (`CPU · MEM` caption, `pct · used/total` value). Media strip = 25px cover art (`file://` art used as-is; http art → `fetch-art.sh` → `state/media/art.img`, atomic rename, URL-cached, `?v=` bust) + player **logo badge** (`player-icon.sh`: MPRIS `desktopEntry`/`identity` → `.desktop Icon=` → hicolor largest-PNG → scalable SVG → pixmaps; path cached per identity; Spotify's `Icon=spotify-client` only exists in pixmaps) + title/artist + `MediaBtn` transport (prev / play-pause / next — dimmed and inert when the player can't) + **2px seekable progress bar** on the bottom edge (bound to `position/length`, no timer per live-verification agreement; MPRIS Seek is relative so `seek(frac·length − position)` is unit-agnostic); click off the buttons = `raise()` the player. Transport glyphs live in `Controls.MEDIA_GLYPHS` (fa-backward · md-play · md-pause · fa-forward · md-music) — typed characters came out wrong (U+E04A/E04E/F0084) and only the codepoint test caught them | ✅ done |
| 6b.2 | **Playback counter, drag-seek, real raise, compact recents** (user QA round 2): the strip gained a Spotify-style **elapsed/total counter** (`Dashboard.fmtTime` µs → `m:ss` / `h:mm:ss`; while dragging, the elapsed side previews the target), a **hover handle dot** with **drag-to-seek** (press pins the dot under the finger, the bar rides along, release seeks; plain click still seeks), and **clicking art/title now raises the player for any player**: MPRIS `Raise()` first (some clients honor it), then `raise-player.sh` → `omarchy hyprland focus app <name>` over candidates (id sans `.desktop`, `.desktop StartupWMClass`, raw id, lowercase) — Spotify ignores Raise under Wayland and raw `hyprctl dispatch focuswindow` is broken in Hyprland 0.56.2 (Lua-evaluated dispatch args, known issue #16224; `focuswindow` isn't even exposed in the `hl.dsp` tree — exhaustively introspected via `hyprctl eval`). **Live clock**: quickshell's cached `position` only moves on player change-signals and Spotify never emits (bar froze after prev/next — verified live), so position is read off the session bus by `mpris-ctl.sh pos` (`busctl get-property`, spec µs; `dbusName` confirmed to carry the well-known `org.mpris.MediaPlayer2.*` name) and seeks go through `mpris-ctl.sh seek` (fresh Get → relative `Seek(target − pos)` — stale caches can't skew the jump); a **1s Timer scoped to palette-open + playing only** (a playback clock, not a data refresh — the no-timer rule still governs refreshes), snapped instantly by track/play/seek events and every open (`refreshHome`). **Recents halved**: strip 96→50, tiles 92×88 → 46×44 (icon 40→20, letter frame 36→18, hover ✕ 18→12). +14 tests (fmtTime vectors, mpris-ctl/raise-player arg validation) | ✅ done |
| 6b.3 | **Backward seek, dismiss-on-raise, section heading** (user QA round 3): backward seek was broken — `busctl call … Seek x <negative>` dies inside getopt (`unrecognized option '-5'`, exit 1) so the seek never reached the player and the post-seek refresh snapped the bar back to the old position (forward always worked: positive offsets aren't parsed as flags). Fixed by passing the offset after `--`; verified live exact in both directions (661752000 → 646752000 → 661752000, paused state untouched). **Seek order matters**: Spotify replies success to `SetPosition` but never applies it (exit 0, position unchanged) — relative `Seek` (fresh Get → `Seek x -- rel`) is now primary and `SetPosition(trackid, target)` the fallback for players without Seek; trackid parsing accepts type `s` as well as `o` (Spotify sends mpris:trackid as a string). **Clicking the media card now raises the player AND closes the palette** (hand the screen over to the app you summoned; transport buttons and the seek zone stay open for repeat use). **Recents gained a "Recently Used" heading**: outer strip Row→Column (heading + list), list pinned `Layout.preferredHeight: Style.space(44)`, block height `visible ? implicitHeight : 0` | ✅ done |
| 7 | **Providers: windows, clipboard, files, dictionary**: **window switching** — automatic rows for any typed query matching a window's class/title (≤4, leading the catalog), from `win-ctl.sh list` (`hyprctl clients -j` filtered: current window, `org.omarchy.*`/quickshell surfaces, the Window Controls `special:` shelf) refreshed on every palette-active moment (never a timer); focus via `hyprctl eval 'hl.dsp.focus({ window = "address:0x…" })'` — the exact Lua form the li.window-controls plugin uses (raw dispatch args are Lua-evaluated in Hyprland 0.56.2; the address is regex-validated hex before it can reach the eval string). **clipboard history** — `;` prefix (bare `;` browses the newest 8) over omarchy's own `clipboard-history.json` (FileView; same file, indexes and helpers as omarchy's clipboard menu: 0 = newest); Enter pastes via `omarchy-clipboard-paste-text --history-index N` (images via paste-file), copy lifts the text. **file search** — `/` prefix, debounced `file-search.sh` (fd walk of `$HOME`; case-insensitive basename substring via awk's literal `index()` — glob/regex metacharacters can never reach a parser); rows open with `xdg-open`, terminal = `cd` there, copy = path. **dictionary** — `?word` via `dict-lookup.sh` (dictionaryapi.dev; letters-only validation before the URL; up to 3 definitions; miss/timeout → web-search fallback row); `?fr hello` reads as a translate request → web row. New pure logic in `SearchProviders.js`; all four kinds are instant kinds with detail-panel captions | ✅ done |
| 7.1 | **Icons everywhere + pinned home block** (user QA round 4): every surface that represents an app renders its real icon — window-switching rows resolve the window class through the catalog (class `Spotify` → desktop id `spotify` → `iconPath`, name-match fallback; unresolvable → glyph) via `appIconForClass`, clipboard **image** rows carry their stored shot as a row/detail thumbnail (`sourceSize` 24/48 keeps decode cheap; `asynchronous: true`), the detail pane gained `detailIcon` (window → app icon, clipboard image → the shot), and the row delegate's Image conditions extend to `window`/`clip`. Probe marker: rows carrying a real image end in `*` (`debugControls` labels). **Pinned home**: the cards row and recents strip are a fixed block — a reserved 235-unit transparent slot holds the media strip's place so weather/system never shift sideways when a player starts/stops, and `rebuildRecents` preserves (clamped) `contentX` so a usage reload or new launch never yanks the strip's scroll | ✅ done |
| 7.2 | **Last-media ghost tile** (user request): the reserved media slot no longer goes empty when the player closes — a Windows-style ghost pins the last-played track: cover art (durable copy in `state/media/ghost-art.img`), player-logo badge, title/artist, frozen elapsed/total counter and progress line at the last saved position, dimmed (0.55 → 0.85 on hover) with a "Last played" caption; clicking relaunches the player via its catalog app id (desktopEntry/identity/name resolution, same shape as window icons) and closes the palette. New `media-memory.sh` (argv-only; jq encodes every value — quotes/newlines in titles are safe; atomic tmp+mv `last-media.json`; art copy kept across `-` saves, exit 0/2/1·3) + FileView watch; snapshots freeze on track change, art-fetch completion, seek release, and palette close. 21 new tests | ✅ done |
| 7.3 | **Idle settings in the power popover** (user request): the footer Power popover opens with an IDLE section — Screensaver and Lock timeout chip rows (Off · 1 · 2 · 5 · 10 · 15 · 30 · 60 min, current value highlighted, read live from shell.json's `idle` block via a watching FileView) plus a Stay Awake switch (same argv dispatch as the control rows, `omarchy-toggle-idle`). New `idle-settings.sh` (argv-only; closed key + value allowlist — `set <screensaver\|lock> <seconds>` rejects anything else with exit 2, verified even against the user's own original value 150; jq atomic edit preserving `version: 1` and every other key). Writes apply live: omarchy-shell FileViews shell.json with `watchChanges` and re-binds the idle service (verified both directions round trip). "Off" = 86400 s because Omarchy's idle service has no true never (0 fires immediately — verified in `idle/Service.qml`); the Stay Awake switch is the real off. 22 new tests | ✅ done |
| 8.1 | **Tall home tiles** (user request): the pinned home-cards row doubles (35 → 70 units, still a fixed non-shifting block; the 235-unit media slot reservation unchanged). Content re-laid-out for the height: media + ghost cards grow square art (25 → 50, badge 13 → 15) and stack the elapsed/total counter under the artist (drag-preview logic kept live); weather·today splits into icon + big temp over the date; system card becomes one label·value line per metric (CPU / MEM, fixed caption gutter); recents strip gains a clear 12-unit gap under the tiles. Media tiles (ghost + live) also got `Layout.fillWidth: false` — the HomeCard default made them stretch past their 235-slot and eat the weather/system cards' share. Further fix per user: the row is now three EQUAL thirds (media slot / weather / system — all fillWidth with no preferred width, non-media content centered), so the ghost no longer runs wide and the layout is identical in all three states (slot / ghost / playing) | ✅ done |
| 8.2 | **Tile data depth** (user request): the System tile grows a NET line — SSID (or connection name) over a "signal% · IPv4" sub-line, the key facts network settings shows; `status.sh` extended (WIFI_SIGNAL via `nmcli ACTIVE,SIGNAL`; NET_IP from the first connected physical device — `con show` rejects detail fields on this nmcli version, so device-level `dev show`; loopback/tun/VPN skipped like the CONNECTION filter). The weather tile gains wind next to the date (already parsed from omarchy's weather line — nothing new fetched). All values ride the existing open-cycle status probe (state at open + after toggles — the same rhythm as the settings panel itself); guarded degradation verified on this wifi-less box: ssid/signal absent, connection/IP present. Deliberately minimal — three metric lines per tile, no new timers or fetches | ✅ done |
| 8.3 | **Two-tile redesign** (user spec): **System & Network** = left-aligned 3×3 metric grid — [Ping · Loss · Receiving] / [Sending · Downloaded · Uploaded] / [IP · Gateway · CPU]; MEM dropped per the exact spec. Caption-size label+value cells of equal width (fillWidth + elide, so nothing can overshoot), uniform 6/3-unit spacing; new `status.sh` metrics: ping+loss to 1.1.1.1 (3 probes, parsed unconditionally, ordered before the rate window), gateway (`nmcli -g IP4.GATEWAY dev show`), since-boot RX/TX counters and live rates from a 1s double-read of `/proc/net/dev` (the probe's only added latency, async at open). **Weather·Today** = left-aligned rows — full date ("Sat 17 Oct 2026"), location ("city, country"), "clock · temp — condition"; condition text + country come from wttr.in's j1 payload (the same upstream omarchy's own weather commands use, location read via `omarchy weather location`), and the probe's three fetches now run in parallel (~2s, was up to 12s sequential). New `Dashboard.fmtClock/fmtBytes/parseWeatherDetail` (14 new assertions). Live-verified end-to-end via the open route: full grid populated (ping/loss/rates/totals/IP/gateway/CPU), weather + condition + country + clock landed within the hold; suite 623/0 | ✅ done |
| 8.4 | **Live System & Network tile** (user request — explicit amendment scoped to this tile): the metrics now *change while the palette sits open*, not just per summon. New `metrics.sh` (~0.8s bounded run: `omarchy-system-stats` CPU + 0.5s `/proc/net/dev` window for rates/totals + a 2-packet ping overlapping that window in a trap-cleaned temp slot; identity fields IP/gateway stay open-cycle — they only change on link events) + the palette's **only Timer** (2s, `running: root.homeVisible` — dead on close, silent while searching) with an immediate first tick on summon; `_applyMetrics` merges its keys over a copy of `statusInfo` by reassignment so `sysGrid` rebinds. Proven in-session: tick A→B under injected traffic moved ping 14.9→21.6ms, rxRate 87.5K→16.3K, rxB +87KB, CPU 78→34%. **Location fix** (same round): user's real place set via `omarchy weather location --set Ibadan 7.3775,3.9470` (wttr.in IP auto-detect had drifted to `10.000000,8.000000`/UAE) — tile now reads "Ibadan, Nigeria" with real conditions (Fog, 23°C). Suite 623/0, journal clean | ✅ done |
| 8.5a | Settings infrastructure + Home cards & density — **built, then REMOVED at user request** (the panel opened empty; root cause: Flickable `contentWidth` defaults to 0 when only `contentHeight` is set, so the panel column sized to zero width — silent, journal-clean). Removal was complete and verified: panel markup, `showSettings` view state + all its gates (home/recents/panes/loading/keys/Enter), `settings.json` + `settings-write.sh` + its 27 tests + state file deleted — suite back to **623/0**, probe keys gone, open/close/toggle all green. **What survived (independent fix)**: `toggle` was latent-broken since phase 1 (IpcHandler-only → `callIfLoaded` answered "unknown") — root-scope `toggle` kept. History lives in commit `6065226` (settings UI dropped from the Phase 8 scope; feeds keep their existing News → Edit feeds surface) | ❌ removed |
| 8 | **Polish** (continued): ~~settings UI~~ dropped at user request (8.5a), ~~Super+SPACE parity~~ ✅ (8.6), ~~bar-widget variant~~ ✅ (8.7), ~~public packaging~~ ✅ (8.8: screenshots, LICENSE, topics, v0.3.0 pushed) | ✅ done |
| 8.6 | **Super+Space parity** (user directive): inventoried Omarchy's menu (334 items: Apps/Learn/Trigger/Style/Setup/Install/Remove/Update — default `omarchy-menu.jsonc` + the user extension) against the CC catalog — ~320 already reachable (underlying `omarchy-*` commands all present, apps incl. localsend, power actions in the popover; 3 rows hardware-gated off this box: wifi QR, battery %, Dell haptics). Added the **12 genuine gaps** as curated ACTIONS rows: 2 panel summons (Network/Disk speed test on the existing openPanel path) + 10 static-run rows (color picker `hyprpicker`, change password, and the theme/background/unlock switchers — those only *print* a selection, so the menu's `choice=$(…); set` composition is byte-copied — plus the 5 Learn doc links, search-only via the new `SECTION_LEARN` so they don't pad the Controls browse list). New `kind:"run"` activation runs `Util.execDetached(a.cmd)` — the menu's own bash -lc path, static strings only. **`tests/parity.test.js` (105 assertions) byte-matches every cmd against the live menu JSONC**, so an Omarchy update can't silently drift us. Suite **768/0**, journal clean; probe showed all 7 tools rows browsable, learn correctly search-only, both panel ids summoning. **QA fix round (`f5f43f2`)**: the user found the rows but the right pane was empty and Enter did nothing — `run` was missing from `isInstantKind` (Enter parked on pane 2) and from `detailIsComputed` (card hidden → `activate()` bailed on a null `detailCmd`), and panel cards were skeletal (caption + button only). Fix: ACTION/SETTINGS cards now show title + desc + the exact static command + Run/Open; screenshots verified both card types; `debugControls` gained a `detail` probe; suite **772/0** | ✅ done |
| 8.7 | **Bar widget variant** (Phase-8 tail): `BarWidget.qml` — a one-slot launcher beside the Omarchy menu (same 󰒓 glyph the palette header wears): left click toggles the palette via `bar.run("omarchy-shell shell toggle fonsgaudii.cmdcenter '{}'")`, right click opens a terminal (menu-widget convention). Deliberately **stats-free**: no timers, no processes at rest, no contention with `metrics.sh` state files. Manifest gained `kinds:["bar-widget"]`, `entryPoints.barWidget`, and the `barWidget` metadata block (category Compositor). **Pitfall — the `plugins[]` trap**: the id had been parked in `shell.json`'s top-level `plugins[]` since install (enable with a menu-only manifest), and `PluginRegistry.setEnabled` skips the layout insert when the entry is already "found", so `omarchy bar put --after omarchy.menu` answered "is on the bar" while changing nothing visible; migration = `omarchy plugin disable <id>` (splices `plugins[]`) → `omarchy bar put <id> --after <anchor>` (now inserts into `bar.layout.left`). Verified: layout `[menu, cmdcenter, workspaces]`, widget renders in the zoomed bar crop, toggle route alive, plugin remounted (catalog loaded), journal clean; suite **772/0** | ✅ done |
| 8.8 | **Recents dedupe + public packaging** (user directives: no emoji in the README; recents never twice; host like rosakodu/omarchy-dock for plugin.omarchy.com). **Recents**: usage is route-keyed, so one thing reached two ways (the "Spotify" app route and a "spotify" command route) became two strip tiles — new identity dedupe (`recentIdentity`: apps by display name, commands by bare name, normalized; catalog verified collision-free) feeds `Controls.dedupeRecentEntries`, keeping the newest launch per identity in most→least recent order; 6 new assertions. **Packaging**: six real screenshots captured via the `open {"group"/"query"}` IPC route (home/search/calc/controls/history/news) as 164 KB WebP in `docs/`, dock-style README rewritten WITHOUT emoji (hero image, features, screenshot table, `omarchy plugin add` install, keybinding lua, remove, dev loop), MIT LICENSE, repo topics `omarchy hyprland quickshell`, version 0.3.0. Note: plugin.omarchy.com itself was unreachable from this machine (transport error) — discoverability rests on the topics + README conventions the dock also carries | ✅ done |
| 8.9 | **Live publish drill** (publish-page checklist item "safe install and removal", user-requested): removed the plugin (`omarchy plugin remove` — dir gone, bar entry auto-spliced, palette unloaded, ALL state in `~/.local/state/omarchy-cmdcenter/` intact), re-installed per README from GitHub (`plugin add ... --enable --yes` — fresh clone at HEAD, catalog loaded 367/38, suite 780/0 in the new dir, pins/feeds/usage/history identical). Two README gaps caught and fixed live: `plugin add` requires `--yes`, and `add --enable` already places the bar widget (center), so repositioning needs `omarchy bar move`, not `put` (put no-ops on an already-placed widget — the plugins[] trap's twin). Journal noise during the drill was rosakodu.dock's own `minimizeRefreshTimer` warning, zero cmdcenter errors | ✅ done |
| 8.10 | **Marketplace SSRF finding + full security sweep** (user: "ensure there are no security issues like this all-through"). **Maintainer finding**: feed-supplied image URLs were auto-fetched with `curl -L` and no destination policy → a hostile feed could hit localhost/private services without the user opening anything. **Fix — `fetch-guard.sh`**: scheme http(s) only, no userinfo, every resolved address must be publicly routable (0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.168/16, TEST-NETs, benchmark, multicast/reserved; v6 loopback/ULA/link-local/multicast/doc + v4-mapped and NAT64 embeddings), enforced as one shared policy across item images, favicons, album art, and content-declared feed links; redirects followed MANUALLY with the check re-applied per hop (max 5); validated addresses pinned into curl `--resolve` (v4 preferred — curl gives up entirely after an unroutable pinned v6, verified live) so a DNS rebind between check and connect cannot win. Wired into `fetch-feeds.sh` (heroes + favicons), `fetch-art.sh`. **Sweep fixes**: `add-feed.sh` rejects non-web schemes and guards the href a pasted page DECLARES (content → public-only) while honoring the pasted URL itself (user intent, LAN feeds included), both curls `--proto`-pinned + 8 MB cap; feed-XML curl `--proto '=http,https'` + cap; `player-icon.sh` rejects `/` in the MPRIS id (path join); `Qt.openUrlExternally` gated by new `Controls.isWebUrl` for BOTH news links (feed content) and search URLs. **Sweep verified clean**: every exec is argv or shellQuote'd (the editable command line is the user's own intent and no remote data seeds it; Agents prompt per-element `'\\''`-quoted; win-ctl `hyprctl eval` arg charset-gated; jq --arg everywhere; file-search literal awk index (no regex/glob); dict-lookup charset+length gated to a fixed host; mpris-ctl bus names charset-gated; weather URL jq-@uri-encoded to fixed host; no eval/new Function in any JS; all QML Image sources file://; news titles strip-tagged so no RichText path). Tests: `fetch-guard.test.sh` **93** (policy table incl. obfuscated literals/userinfo/mapped/NAT64, redirect join, e2e image + add-feed discovery rejections via local server, wiring canaries, live fetch) + 12 `Controls.isWebUrl`. Suite **885/0** | ✅ done |
| 8.11 | **Follow-up review: hex-embedding bypass → news pipeline goes image-free** (maintainer: `::ffff:7f00:1` — hex v4-mapped — passed the guard and its literal form went to curl unchanged, dialing embedded loopback; same for v4-compatible `::7f00:1` / 6to4 `2002:7f00:1::`). **User decision: stop fetching feed-supplied images entirely** — rows and cards render the feed's initials (`FeedParser.initialsFor`: "Hacker News" → "HN") instead of favicons/heroes, so feed content can no longer cause ANY download; `--fetch-images` mode and the favicon cache are deleted, `news.json` slimmed to `{id,name,url,xml}`, card hero + logo Image replaced by an initials badge, `letter` role added through computedRow/delegate. **Guard hardened anyway** (remaining callers: album art, declared feed links, feed-XML redirect hops): every IPv4-embedding v6 form rejected outright on the EXPANDED hextets — dotted (`::ffff:127.0.0.1`), hex-mapped (`::ffff:7f00:1`), v4-compatible (`::7f00:1`), NAT64 (`64:ff9b::/96` + `64:ff9b:1::/48`), 6to4 (`2002::/16`), Teredo (`2001:0::/32`) — plus `fec0::/10`; strict decimal octets (leading zeros are octal to some parsers → rejected); raw control chars rejected; bracketed authority must be v6-literal; new `netguard_fetch_user` seed mode: the pasted feed URL is honored at any host (LAN feeds work), every redirect hop beyond it must be public or return to the pasted host (wired into `fetch-feeds.sh` + `add-feed.sh`, which now has zero raw curl). **FeedParser hardened**: split-based linear block extraction + all regexes bounded `{0,4096}` + 64KB per-item cap (a 20k unclosed-`<item>` flood went 5998ms → 2ms; previously an 8MB hostile feed could freeze the shell for minutes on QV4) and no image-URL extraction at all. **Palette**: all 99 `Text` elements pinned `textFormat: Text.PlainText` (feed strings can never render as rich text — no remote `<img>` load path). Tests: `fetch-guard.test.sh` **133** (full embedding-form table, ambiguous octets, control chars, brackets, seed-mode e2e via a local redirect server — cross-host and `[::1]` hops blocked, same-host honored — no-image/PlainText wiring canaries) + `feeds.test.js` **47** (initials, flood, mixed-case close, unclosed-tail drop). Suite **925/0** | ✅ done |
| 8.12 | **Follow-up review #2: copied payload no longer rides argv** (maintainer: copying a clipboard-history entry sent its full text through `Palette.qml`'s `copyText` into `Util.execDetached("printf … \| wl-copy")` → `bash -lc` argv → world-readable `/proc/<pid>/cmdline`, exposing private clipboard contents to other local users; "every other related one like copying commands" too). **Fix**: both copy sinks (`copyText` + `copyCommandLine`, which now delegates to it) write the payload to a dedicated `Process { stdinEnabled: true; command: ["wl-copy"] }` — `write(text)` then `stdinEnabled = false` closes the write channel (`QProcess::closeWriteChannel` → the EOF wl-copy needs; verified against Quickshell's process.cpp). Copies queue (a second copy mid-drain starts when the first wl-copy exits), the toggle re-arms per run (fresh QProcess per start), and a missing wl-copy cannot wedge the queue. All17 copy call sites (clipboard history text, command lines, calc/convert results, window titles, paths, definitions, links, stats, launch commands) now flow through the one stdin sink; the calc OSD message ("Copied <result>") was scrubbed to static "Result copied" since `root.osd` spawns `omarchy-shell osd show <json>` (argv). Documented boundary: COMMAND EXECUTION surfaces (terminal/agent launches via `bash -lc`, pins/usage bookkeeping, `xdg-open <path>`) still carry the executed command in argv — identical to running that command in any terminal, and remote/clipboard data provably never reaches them (existing canaries); payload sinks never do. 5 new canaries (no `printf`→wl-copy sink, wl-copy only as the stdin Process command, delegation, no payload in OSD). Live E2E: `wl-paste` returns the calc result copied through stdin; second copy re-arms. Documented boundary in the reply; suite lands with 8.13 | ✅ done |
| 8.13 | **Full-plugin security audit — every agent finding fixed** (user request after review #2; three parallel line-by-line audits of Palette.qml, all 18 scripts, the JS modules/BarWidget/manifest, each claim re-verified against source before fixing). **HIGH — add-feed.sh declared-href join**: the sed building a page-relative feed href was unterminated (silent exit-1 under `pipefail` instead of the documented error) *and* the join could hand the URL authority to page content (`https://host` + `href="169.254.169.254/x"` → link-local fetch). Fixed: origin always extracted from the user's pasted URL (pathless URLs resolve under `/`), plus 3 new e2e cases (path-relative, directory-relative, authority-injection) and stdin URL delivery (pasted URL no longer sits in argv during the multi-second probe). **Confused deputy — omarchy's `shell call` dispatcher** resolves `loader.item[method]` and invokes ANY root-scope function with one caller-chosen string (proven live). Every exec/network sink steerable by state (`activate`, `activateComputed`, `activateRecent`, `runBackground`, `openTerminal`, `addFeed`, `fetchHelp`, `launchApp`, `launchAppRecord`) moved to a `priv` QtObject the dispatcher cannot see; object-shaped exec sinks (`openAgent`, `activateControl`, `runToggle`, `runPower`, `activatePowerRow`, `activateFooterTile`, `activateHistoryRow`) got `typeof` shape guards. Live-verified: all nine probes return `unknown`, no side effects, `ping`/`open` unaffected. **MPRIS metadata off argv**: media save now ships title/artist/identity as eight NUL-separated stdin fields (D-Bus strings are NUL-free → lossless; empty-stdin saves rejected); file-search/dict queries ride stdin (scripts keep argv for tests, awk moved to `ENVIRON` to kill `-v` backslash expansion). **OSD argv class closed**: feed add success/error messages were remote-derived (`<title>`, echoed URL) — now static in argv with the reason displayed in-palette on the feedadd row; the run OSD dropped the command-output first line (may carry tokens) — route + exit status only, detail stays in-palette; `osd()` itself strips control chars and caps length for everything else. **Cache poisoning**: `commands.json` is untrusted input — `parseCatalog` now drops any route outside `^omarchy [A-Za-z0-9 ._:,@+-]*$` (shipped catalog passes 367/367) before routes can reach `bash -lc` via Run or the `--help` probe. **Image-source policy**: MPRIS `file://` art must decode to a path inside `$HOME` (QML gate) and `media-memory.sh` re-checks (`$HOME` only, never a symlink) before persisting; ghost snapshot `artFile`/`logoFile` and clipboard image `detailIcon` are prefix-checked at load; `player-icon.sh` rejects `Icon=` values with `/` or `..` (the pixmaps glob could otherwise match `id_rsa.*`). **JS hygiene**: `quoteArg` now quotes glob/tilde/comment chars (`* ? [ ] { } ~ #`); FeedParser's lazy tag scans run on an 8 KB head window (adversarial-feed worst case cut ~4×); data-keyed dedupe maps use `Object.create(null)` (`__proto__`-safe); the web-search template must be `http(s)://` at both the `detect-env.sh` emitter and the QML consumer. **Shell hygiene across 8 state-touching scripts**: state dir `chmod 700` (migrating pre-0.8.13 dirs), owner-only umask for seed/marker writes, fetch-guard port parsed decimal (`10#`, no octal surprise), `dict-lookup.sh` curl `--max-filesize`+`--proto`, `metrics.sh set -u`, `mpris-ctl.sh` strict `^-?[0-9]+$` position validation, `build-catalog.sh` tab-safe ids + `omarchy`-on-PATH guard. ~40 new canaries + 6 new functional tests; live smoke: stdin copy, `/` file search (8 matches), dict definition, media save round-trip, dispatcher probes. Suite **976/0** | ✅ done |
| 8.14 | **Follow-up review #3: no payload in child-process argv** (maintainer at `f43e075`: the stdin fixes landed, but three script→child hops still re-emitted payload — feed URLs incl. access tokens in `curl` args (`fetch-guard.sh:312–315`) and `jq --arg` args (`add-feed.sh:130–143`), and the stdin-delivered track title/artist/identity went back into `jq --arg` argv (`media-memory.sh:92–98`)). **Mechanisms, both verified on-box**: `/proc/<pid>/cmdline` is world-readable (0444) while `/proc/<pid>/environ` is owner-only (0400) — so jq now receives every value via environment prefixes (`TITLE="$t" jq …` → `$ENV.TITLE`; env is NUL-free by construction, string-typed, hostile bytes proven intact) and curl reads its URL from a one-line config on stdin (`printf 'url = "%s"\n' "$cur" | curl … -K -`; curl 8.22 — token query + `--resolve` pinning + `-D/-o/-w` verified byte-identical, fragment handling unchanged). Same-UID processes share the trust they already have over the state dir; other local users see neither channel. **Sweep beyond the three cited sites** (same class, per user decision): `fetch-feeds.sh` token URLs + remote names via env and bodies via `--rawfile`/`--slurpfile` — which also fixes a latent crash (the old `--argjson xml`/`--argjson feeds` put whole feed bodies in a single argv arg; ≳128KB hits E2BIG at execve and `set -e` aborted the ENTIRE refresh — proven by a 150KB e2e that fails on the old code); `dict-lookup.sh` query word in the URL → config stdin; QML `artProc` signed MPRIS art URL → stdin (fetch-art keeps argv for direct CLI); the weather tile's location (jq `@uri` via env, curl via config). **Hardening**: `netguard_url_parts` rejects raw `"`/`\` (invalid per RFC 3986 and the only config-line breakout chars; `%22`/`%5C` still accepted) — both fetch modes and every redirect hop funnel through it, so no escaped form was needed anywhere. **Disposition of remaining dynamic argv** (documented, non-private): `--arg route` in update-usage/toggle-pin (omarchy command names), idle-settings key/value, build-catalog local .desktop data, player keys; scripts keep argv fallbacks for direct CLI/test use (the palette never calls them — same boundary as 8.13); upstream `omarchy-weather-icon/status` still put the location in their own curl argv — outside the plugin (`/usr/share/omarchy` is read-only by policy). **Tests +25**: per-file wiring canaries (every curl paired with `-K -`, zero `--arg` in add-feed/fetch-feeds/media-memory/Palette, charset rejection, no art-URL argv), e2e proving the token query intact through the config path plus a fork-free `/proc` scan observing the live curl and finding ZERO token bytes in any curl cmdline (deliberately scoped past the test's own debug-CLI argv — the documented fallback), the 150KB E2BIG regression, and a hostile NUL-stdin media round-trip. Live: restart + `open` ok, the extracted weather command observed16× as `curl … -K -` with no URL, real feed refresh 0 errors/3 feeds; dictionaryapi.dev was timing out on-box during the run — positional and config-stdin curl both rc=28 (wiring-neutral). Suite **1003/0** | ✅ done |

## Key technical decisions (settled)

- **Direction**: universal launcher + command center + dashboard + deep Omarchy
  integration — everything, sequenced as phases above (user decision).
- **News**: RSS/Atom, user-configured, ships with optional starter feeds —
  never an algorithmic feed (user decision; Windows is retreating from MSN
  feeds in 2026 — "calm" wins).
- **Web search**: use the configured browser's default search engine
  (user decision). Detection: override file `~/.config/omarchy/defaults/websearch`
  → browser profile Preferences (chromium-family custom provider) → browser
  built-in (Google for stock chromium/firefox) → DuckDuckGo fallback.
  Settings UI for this lands in Phase 8.
- **Agent rows**: the Omarchy **default agent** (`~/.config/omarchy/defaults/agent`)
  is the primary ask row, launched via `omarchy agent prompt "<query>"` —
  canonical machinery (per-agent flags, work dir, `omarchy-launch-tui`).
  Other installed agents get rows using argv mirrored from
  `/usr/share/omarchy/bin/omarchy-agent` (see `Agents.js`, re-check when
  omarchy updates). No default set → "Choose default agent" row runs
  `omarchy agent --pick`.
- **Fallback ordering**: computed rows (calc/convert) top → command/app
  matches → [default agent, web] last. When there are **no** matches,
  fallbacks sit at the top, so Enter asks the default agent (user decision:
  "agent rows above command matches when there are none"). Other agents are
  never trailing rows — they live behind the `@` prefix (`@`, `@codex`,
  `@codex fix…`, `@claude`), since 12+ installed agents would flood the list.
- **Recents removal — hybrid, confirmed by user**: hover ✕ on a recent tile
  forgets it immediately (flock-serialized `update-usage.sh forget`); the
  strip auto-expires entries unused for 30 days; `usage.json` sweeps them at
  90 days on every write. No clear-all action (user chose plain hybrid).
- **Non-default agent rows** run with omarchy-agent's unattended permission
  flags, mirroring the Super+Shift+Ctrl+A keybinding behavior (user decision).
- **State stays outside the plugin dir** (`~/.local/state/omarchy-cmdcenter/`)
  — the shell's inotify watcher reloads the plugin on any write inside it.
- QML edits require `omarchy restart shell` to verify (hot-reload serves
  stale bytecode after multi-edit batches).
- Invisible QML items still evaluate bindings: every payload-derived string
  binding must guard the field itself (`payload.result !== undefined`), not
  just visibility — undefined→QString warnings otherwise.
- **`ListModel.get()` returns a live view**: capture needed roles into
  locals BEFORE `model.remove(index)` — afterwards `row.route` reads
  `undefined` (caused a silently no-op forget; found via console.log tracing
  through journalctl, since no error is thrown).
- **FileView `watchChanges: true` only signals** — you must add
  `onFileChanged: reload()` yourself (see omarchy Menu.qml) or memory never
  re-reads. Pair it with `reload()` on open as a freshness net for
  rename-based (`mktemp`+`mv`) writers. Applied to usageFile + pinsFile.
- **Phase-5 commands mirror omarchy-menu.jsonc exactly** (lock/suspend/
  hibernate/logout/reboot/shutdown + the `trigger.toggle.*` scripts), with the
  same availability gates the menu's `when:` clauses use
  (`omarchy-toggle-enabled suspend-off`, `omarchy-hibernation-available`) —
  `tests/controls.test.js` fails if the menu file and `Controls.js` drift.
  Confirmation covers every session action except Lock (user requirement:
  confirms on destructive actions; Ctrl+T cannot bypass it).
- **Phase-5 execution is argv-only**: `Quickshell.execDetached([...])` from
  `toggleArgv`/`powerArgv` — no shell parses a control command, so there is no
  injection surface at all (stricter than the shellQuote pattern used for
  catalog routes).
- **Wi-Fi row only exists when a Wi-Fi device exists**: `nmcli radio wifi`
  reports "enabled" on wired-only desktops, which would show a dead toggle.
  `status.sh` gates on a `:wifi` device and emits `CONNECTION=` instead.
- **Plane-16 glyph gotcha (tests)**: Nerd Font codepoints above U+FFFF are
  surrogate pairs in JS — `charCodeAt(0)` returns half a character; tests use
  `codePointAt`. And never re-type glyph literals by eye: emission can come
  out empty/wrong (the fa-lock literal did) — splice/audit glyph bytes
  programmatically (`glyphnames.py --find <name>` for names, python `ord()`
  for bytes). Python `%r` in a splice emits repr TEXT (`'\U000f00b2'`), which
  JS then treats as a literal string — always splice raw UTF-8 (`%s`).
- **Footer rail (user decisions)**: domain tiles (~10) over a flat 16-icon
  strip; anchored mini-popover for multi-control tiles; one Power tile whose
  popover holds battery + all session actions (each keeping its confirm);
  audio popover includes **volume sliders** (v2 candidate: brightness).
  `footerTiles()` is a pure function of probed state (wired-only → Wired
  tile, no bluetoothctl → no BT tile), so node tests gate the whole layout.
- **The shared kit's PopupCard/PanelToolTip are bar-coupled**: PopupCard
  requires a bar QtObject (`requestPopout`, `position`) and PanelToolTip is a
  bar-edge PartWindow — unusable from the palette. The footer popover is an
  in-card Rectangle positioned from the anchor tile (`mapToItem(card,…)`,
  clamped); PanelSlider however works standalone (`bar: null` +
  explicit track/fill/knob colors) and its `moved`/`released` signals give
  drag-preview + commit-on-release for free.
- **Anchors inside layout-managed children = undefined behavior** (Qt scene
  warning): a MouseArea with `anchors.fill: parent` directly inside a
  RowLayout delegate triggers "Detected anchors on an item that is managed
  by a layout". Wrap: Item root gets the `Layout.*` attached props, the
  RowLayout + MouseArea anchor INTO it.
- **QML6 Repeater required-property trap**: a delegate that declares ANY
  `required property` only receives model roles that are ALSO declared —
  `index` without `modelData` silently yields undefined (blank footer
  tiles that still took layout space). Declare both.
- **News reader architecture (Phase 6a, user decisions: RSS + optional
  starter feeds, never algorithmic)**: `feeds.json` is user-owned (seeds
  Hacker News + Lobsters once); `fetch-feeds.sh` curl-fetches with
  timeouts and embeds RAW XML in `news.json` via `jq -Rs` — XML parsing
  happens QML-side in the pure `FeedParser.js` (no DOMParser in QML's JS
  engine, no xmllint dependency, node-testable with fixtures). One
  FileView on news.json = the whole list; `--max-age` makes cache-fresh
  checks free so startup/group-entry refreshes never cost a fetch.
- **Hover feedback is expected on every clickable surface** (user
  report): cursorShape alone is not enough — popover rows and footer
  tiles need `hoverEnabled` + a background Rectangle bound to
  `containsMouse` with a short ColorAnimation.
- **QML `int` properties silently overflow millisecond timestamps**
  (found via a garbled `fetchedAt: 1200779568` in the news probe):
  `property int x` is 32-bit, and every `Date.now()` exceeds 2^31 (which
  caps ~24 days after epoch), so the value wraps. Any property holding a
  timestamp must be `double`. Cost `statusAt` (Phase 5), `newsAt`, and
  `newsCheckedAt` until fixed — `newsAt` even fed `relativeTime`, so the
  story age would have rendered as garbage.
- **Concurrent script runs must not share a temp filename**: two
  `fetch-feeds.sh` invocations (startup timer + group-entry nudge)
  writing one `news_file.tmp` would interleave. Use `mktemp` per run,
  then `mv` to publish atomically.
- **Stripping inline tags must not leave space before punctuation**:
  `markup</b>, keep` stripped to `markup , keep`. Fix in `stripTags`
  (`\s+([,.;:!?)\]])` → `$1`), and unwrap CDATA *before* tag-stripping
  or a literal `]]>` leaks into the text.
- **News images are local-file only**: QML `Image` never fetches
  http(s) here — the shell script downloads into `news-img/` (position
  `item<i>.img` matches item index in the *sorted* list; names must be
  assigned by the QML side, which owns the sort). `visible: status ===
  Image.Ready` gives graceful fallback; caveat: an Image that errors
  before the download finishes does not retry this selection (it does
  on re-select) — accepted for v1.
- **Glyphs outside plane 16 need a coverage check**: `omarchy weather
  icon` emits U+E313 (legacy PUA) — verify a target font's cmap
  actually covers a codepoint before rendering it (the earlier
  glyphnames.py cmap walk found JetBrains Mono NF does cover it).
- **Media without playerctl**: Quickshell ships
  `Quickshell.Services.Mpris` — `Mpris.players.values` (guard the
  ternary like Omarchy's own media service), `player.trackTitle`,
  `player.isPlaying`, `player.canTogglePlaying` + `togglePlaying()`.
  Never depend on the `playerctl` CLI (absent on stock Omarchy).
- **Inline components can carry a `default property alias`**: the
  HomeCard pattern (caption + injected content column + optional
  hoverable/clicked) keeps card markup at the call site while overlays
  (tint, MouseArea) stay anchored in the component — remember
  full-bleed overlays must NOT go through the default alias (they'd
  become layout-managed children → anchors warning). The 6b.1 fix:
  an explicit `overlays` alias to an Item declared BEFORE the content
  column — the bar stays full-bleed and in-column buttons still win
  their clicks over the seek zone beneath them.
- **Typed icon glyphs are wrong until byte-verified**: writing PUA or
  astral characters "by hand" silently produced U+E04A/U+E04E/U+F0084
  instead of the intended U+F04A/U+F04E/U+F03E4 (3 of 5 transport
  glyphs). Always splice codepoints programmatically and assert them
  in a test (tests/media.test.sh) — never trust a rendered preview.
- **quickshell's MPRIS `position` is a signal-driven cache — it never
  ticks on its own**: Spotify emits no Position change signals, so the
  bar froze after prev/next (verified live — the 6b.1 "bar + verify
  live" checkpoint). Read Position off the session bus instead
  (`mpris-ctl.sh pos` → `busctl get-property … Position`, spec µs) on a
  1s Timer scoped to *palette-open + playing only* (a playback clock,
  not a data refresh — the no-timer rule still governs refreshes);
  metadata `mpris:length` (also spec µs) refreshes per track, and
  `MprisPlayer.dbusName` carries the well-known `org.mpris.MediaPlayer2.*`
  name the script validates. Seek the same way: the script does a fresh
  Get then a relative `Seek(target − pos)` — quickshell's own
  `position`/`length`/`seek` units are undocumented, so never do the
  arithmetic in them.
- **MPRIS `Raise()` is unreliable and `hyprctl dispatch` is broken
  here**: Spotify ignores Raise under Wayland (clicked card → nothing,
  verified live), and Hyprland 0.56.2 evaluates `hyprctl dispatch` args
  as Lua (known issue #16224) where `focuswindow` isn't exposed in the
  `hl.dsp` tree at all (exhaustively introspected via `hyprctl eval` —
  window namespace has close/kill/move/swap/… but no focus). Only
  omarchy's own `omarchy hyprland focus app <name>` works;
  `raise-player.sh` derives candidates (id sans `.desktop`,
  `.desktop StartupWMClass=`, raw id, lowercase) and loops the helper
  until one focuses. MPRIS `Raise` still fires first for clients that
  honor it.
- **busctl eats negative method args; Spotify lies about SetPosition**:
  `busctl call … Seek x -5000000` → getopt reports `unrecognized
  option '-5'` before anything reaches the bus — that was the
  "backward seek snaps back" bug (script exits 1, the post-seek refresh
  re-reads the unchanged position). Always pass negative numbers after
  `--`. Then verify against a real player: Spotify answers `SetPosition`
  with success yet silently ignores it (exit 0, position unchanged),
  while relative `Seek` moves exactly in both directions — primary vs
  fallback order is not cosmetic. Spotify's `mpris:trackid` also arrives
  as variant type `s` (string), not `o` (object path) — parse `[os]`.
- **fd's `--max-results` silently randomizes results**: with a
  match-everything pattern (`.`), the cap truncates to an arbitrary
  subset of fd's *parallel* walk — the same query returned 0/1/2/14
  results across runs, which masqueraded as "the Process stdout
  collector is broken" (exit 0, empty text) and cost a hunt through
  env replicas and file-redirect experiments. Never cap fd's walk
  when a later filter decides what matches; let the consumer exit
  early instead (awk exits at N matches → SIGPIPE stops fd).
- **A literal `'` inside a case bracket pattern eats the script**:
  `case $w in *[!A-Za-z"'"' -]*)` — the quote-splice backfires inside
  `[...]`; the span ran to the next `'` in the file (the jq program)
  and surfaced as `syntax error near unexpected token` lines away.
  Strip the allowed specials with `tr` first, then match the remainder.
- **dictionaryapi.dev answers 200 with `[]` for some lookups** ("don't")
  and 404s for others; both must read as "no entry" (exit 2), while
  curl's timeout (rc 28) is a transport failure (exit 1) — the UI
  falls back to a web row for the word either way.
- **Local file sources accept `?v=` cache-busting**: QUrl strips the
  query for `file://` paths, so `file:///…/art.img?v=7` reloads a
  replaced file — the standard trick to make QML `Image` re-read a
  same-path download (no FileView needed).
- **Player logos resolve via .desktop, not icon guessing**:
  player-icon.sh takes MPRIS `desktopEntry` (exact hit) or
  `identity` (case-insensitive `Name=` match), then `Icon=` →
  hicolor largest PNG → scalable SVG → pixmaps (Spotify ships only
  `/usr/share/pixmaps/spotify-client.png` for its Icon key — a pure
  hicolor lookup would miss it). SVG is safe: libqsvg is installed.
- **Inserting into a multi-line QML property orphans its continuation
  lines**: `readonly property bool x: a || b\n  || c\n  || d` — an edit
  anchored on the first lines that splices a new property in between
  leaves `|| c || d` dangling after the new block ("Unexpected token
  `||`"), and one parse error drops the WHOLE plugin: the IPC route
  answers `unknown`, the journal shows `WARN scene: … Unexpected token`,
  and the (perfectly registered) summon keybinding has nothing to
  toggle. `omarchy plugin validate` does not parse QML — only a real
  shell restart surfaces this. Symptom-to-cause path: keybind dead →
  `hyprctl binds` shows the bind → toggle exits 0 → `shell call` says
  unknown → journal.
- **`hyprctl binds` never shows Lua-dispatched commands**: `o.bind(…)`
  registers through the `__lua` dispatcher with a numeric registry
  index as arg — the command string is absent from the output. Verify
  bindings by their *description* ("Command center"), not by grepping
  the command text (which reports 0 hits and looks "unregistered").
- **An interrupted write can pad the file with NUL bytes**: a server
  restart mid-`edit` left 162 `\0` bytes after Palette.qml's final `}`
  — invisible to sed/read (they render as blank space) and invisible
  to brace counting, but fatal to the QML parser ("Syntax error" at
  EOF+1:1): the whole plugin drops, the IPC route answers `unknown`,
  and the summon keybinding goes dead — including across reboots, which
  reads as "the bind isn't wired". `omarchy plugin validate` did NOT
  catch it. Diagnose with `tail -c 48 file | od -c`; fix with
  `data.rstrip(b'\x00')` (python) and re-verify via a real shell
  restart + route probe. When a plugin suddenly "unregisters"
  everywhere, byte-inspect the file tail first.
- **QML evaluates every binding regardless of `visible`**: an unguarded
  `root.ghostMedia.posUs` inside a hidden Text threw `TypeError:
  Cannot read property 'posUs' of null` at delegate creation (journal
  `WARN scene:`). Visibility gates rendering only. Guard every
  dereference of a nullable model with `&&` short-circuit or a ternary
  — even in invisible subtrees; one unguarded binding is enough to
  dirty the journal on every shell start.
- **Nested-delegate property access goes through the context, not the
  parent chain**: in the idle chips the outer delegate is only
  `chip.parent.parent` (chip → chips RowLayout → delegate) — a
  three-hop walk lands on the popover layout, which has no `row`
  property, and the failure is silent (selection never highlights, no
  error). Alias the outer model (`readonly property var row:
  modelData`) and read `row.x` — the delegate context chain resolves
  it; a parent chain is off-by-one-able with no diagnostic.
- **Omarchy's idle service has no "never"**: `0` means *fire
  immediately* (delay 0 in `startIdleCycle`), not "off" — never expose
  0 in a timeout picker. "Off" is encoded as 86400 s; the Stay Awake
  inhibit is the true off. The chip allowlist also refuses to restore
  an original non-chip value (the stock 150 s) — by design; restore
  as-found values out-of-band with a direct jq edit.
- **A session interruption can silently drop an in-flight edit call**:
  after resuming, the transcript showed a large Palette.qml edit
  "applied" whose call had never executed (no result recorded). The
  file was healthy but the whole section was missing. After any
  interrupted session, grep for an anchor string from the last edit
  before trusting it landed.
- **Omarchy's shell.json applies live**: the shell FileViews it with
  `watchChanges: true` and the idle service binds `shellConfig.idle`
  reactively — an atomic tmp+mv write needs no restart or refresh to
  take effect (verified by probe round trip).
- **Bash reads scripts lazily — never rewrite one that is executing**:
  a stray background instance of status.sh kept running while the file
  was rewritten (the re-applied edit of a dropped call); it re-read at
  the new byte offset with stale variables and emitted garbage
  (`NET_LOSS=3333`). The parse itself was correct (3 clean runs + a
  `bash -x` trace proved it). Ensure no live instance (pgrep) before
  editing a script; the anchor-grep habit catches the twin failure
  mode (edit silently dropped, then replayed later).
- **Parse probe output unconditionally when partial failure is
  data**: guarding `ping` with `if out=$(ping …)` skipped BOTH metrics
  on a transient non-zero exit (ping still prints its stats on heavy
  loss — 100% loss is a value, not an error). Use `|| true`, then
  parse whatever arrived; order link health before the ~1s rate window
  so a short-lived run loses only the rates.
- **A transient palette bounds probe latency — parallelize fetches**:
  the weather probe ran three wttr.in curls sequentially (icon ≤3s +
  status ≤4s + j1 detail ≤4s ≈ 12s worst case); the tile was still
  "(pending)" when the palette closed. The three now run concurrently
  into trap-cleaned mktemp slots (`cat` in fixed order) — worst case
  ≈ slowest single curl (1.7s observed). Same argv-only shape, no new
  timers: one bounded subprocess per open-cycle, as before.
- **"No timers" now has exactly one scoped exception (user-directed)**:
  the System & Network tile ticks `metrics.sh` every 2s via the
  palette's only `Timer`, gated `running: root.homeVisible` — it stops
  on close, goes silent while searching, skips if a run is in flight
  (~0.8s runs vs 2s interval), and refreshes identity fields (IP/
  gateway) never — those ride the open-cycle status probe. Weather,
  recents, home cards and every other surface remain strictly
  open-cycle; do not add a second timer without an explicit request.
  Evidence the amendment was needed: the user watched the grid hold
  still across a whole session ("showing just some static metrics") —
  per-open refresh alone doesn't read as "real-time" when the palette
  is left open.
- **IPC routes must be ROOT functions, not IpcHandler functions**:
  omarchy's `omarchy-shell shell call <id> <method> <arg>` lands in
  `shell.qml callIfLoaded` → `loader.item[method](arg)` — a plain
  property lookup on the plugin's ROOT object. Functions declared in
  the Quickshell IpcHandler are the qs-native path and invisible to
  that dispatcher: they answer "unknown" (stdout, exit 0 — distinct
  from qs-level "Function not found."/"Target not found." which the
  wrapper turns into exit 1). Caught when `settings`/`settingsPanel`
  answered "unknown" while `ping`/`open` answered "ok"; inspection
  showed `toggle` had lived ONLY in the IpcHandler since phase 1 —
  it was never callable through omarchy-shell either (latent bug,
  fixed at root in 8.5a). Every new route: declare it at root (the
  IpcHandler copy is optional), then prove it with a real call.
- **A Flickable whose `contentHeight` is set but `contentWidth` isn't
  has content width 0** — every child sized `width: parent.width`
  inside it collapses to nothing, with no QML error anywhere (the
  8.5a settings panel rendered as empty space; the user reported
  "I see nothing in the settings panel"). If a scrollable panel ever
  returns, set BOTH dimensions (or size children from anchors/fill
  rather than `parent.width`). Also: a panel the user can't see is a
  removal candidate, not a debugging session — user verdict rules.

## Open questions

1. RSS starter feeds: which feeds ship by default? (candidates: Hacker News,
   Lobsters, Linux/Omarchy news — user picks in Phase 6 settings anyway)

## Test / verify commands

```sh
node tests/model.test.js          # catalog model (35)
node tests/providers.test.js      # math + units (53)
node tests/agents.test.js         # agent argv + web template (48)
node tests/controls.test.js       # Phase 5 actions/timeline/glyphs + footer rail (294)
node tests/feeds.test.js          # FeedParser RSS/Atom fixtures + flood guards (47)
node tests/dashboard.test.js      # weather parse + ISO-week date card + time fmt (50)
node tests/search.test.js         # Phase-7 provider matching: windows/clip/files/dict (60)
bash tests/media.test.sh          # art/logo/mpris-ctl/raise-player scripts + glyph codepoints (19)
bash tests/search-scripts.test.sh # win-ctl/dict-lookup/file-search validation + shapes (20)
bash tests/fetch-guard.test.sh    # URL/destination policy + seed-mode + wiring canaries (133)
bash tests/usage.test.sh          # update-usage.sh (14)
bash build-catalog.sh --if-stale  # ~20ms no-op when fresh; full rebuild when stale
bash fetch-feeds.sh               # seeds feeds.json once, fetches into news.json
jq '.feeds[].name' ~/.local/state/omarchy-cmdcenter/feeds.json   # your feed list
omarchy plugin validate .         # silent = OK
omarchy restart shell             # then:
omarchy-shell shell call fonsgaudii.cmdcenter debugProviders ""
omarchy-shell shell call fonsgaudii.cmdcenter debugControls ""   # states + rows + footer tiles + power popover + news probe
omarchy-shell cmdcenter open "2+2"
omarchy-shell cmdcenter open "wifi"                              # toggle row must be first
omarchy-shell cmdcenter open ";o"                                # clipboard rows (sync)
omarchy-shell cmdcenter open "spo"                               # window rows when a window matches (sync)
omarchy-shell cmdcenter open "/palette"                          # file rows (fd debounce ~250ms; probe after 2s)
omarchy-shell cmdcenter open "?serendipity"                      # dictionary row (API; probe after ~4s)
omarchy-shell shell call fonsgaudii.cmdcenter debugControls "/palette"  # qProvider + providers{wins,clip,file*,dict*}
journalctl _PID=$(pgrep -x quickshell | head -1) --since "-5min" | grep -iE "cmdcenter|TypeError|ReferenceError"
```
