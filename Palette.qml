// fonsgaudii.cmdcenter — a browsable, searchable command center for every
// `omarchy` CLI command.
//
// Summon:   Super + Shift + K
//           omarchy-shell shell toggle fonsgaudii.cmdcenter '{"query":"…"}'
//           omarchy-shell cmdcenter open "screenshot"
//
// Data:     one cache built by build-catalog.sh — `omarchy commands --json`,
//           group descriptions scraped from the omarchy dispatcher, and the
//           installed apps enumerated through Omarchy's own .desktop
//           hide-filters (same source the built-in menu's AppLibrary uses),
//           cached under $XDG_STATE_HOME/omarchy-cmdcenter/commands.json.
//
// Layout:   search bar · groups pane · commands pane · detail pane.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "CommandsModel.js" as CmdModel
import "MathEval.js" as MathEval
import "Units.js" as Units
import "Agents.js" as Agents
import "Controls.js" as Controls
import "FeedParser.js" as FeedParser
import "Dashboard.js" as Dashboard
import "SearchProviders.js" as SearchP

Item {
  id: root

  // ---------------------------------------------------------- lifecycle
  // Injected by the shell host on load.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool rowsLoaded: false
  property string loadError: ""

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.opened = true
    if (payload.group) {
      root.activeGroup = String(payload.group)
      root.syncGroupSelection()
    }
    if (payload.query !== undefined) searchField.text = String(payload.query)
    // Freshness net: every summon re-reads history so external edits (or a
    // missed fileChanged from a rename-based write) can never leave the
    // strip showing stale or expired entries.
    usageFile.reload()
    root.refreshStatus()
    if (!metricsProc.running) metricsProc.running = true   // first live tick now
    root.refreshHome()
    root.rebuildDisplay()
    root.rebuildRecents()
    Qt.callLater(function() {
      searchField.forceActiveFocus()
      searchField.cursorPosition = searchField.text.length
    })
  }

  function close() { root.cancel() }

  function cancel() {
    root.opened = false
    root.confirmOpen = false
    root.pendingPower = null
    root.openPopover = ""
    searchField.text = ""
  }

  function ping() { return "ok" }

  // The shell's `omarchy-shell shell call <id> <method> <arg>` dispatches
  // through callIfLoaded → loader.item[method]: ROOT scope only. The
  // IpcHandler further down is the qs-native path and is invisible to
  // that dispatcher — every callable route must exist here (proven when
  // `toggle` answered "unknown" while living only in the handler; fixed
  // at root). toggle is the summon twin of open/close.
  function toggle(query) {
    if (root.opened) root.cancel()
    else root.openPayloadForIpc(query)
    return "ok"
  }

  function refresh() {
    root.startCatalogLoad()
    return "ok"
  }

  // ---------------------------------------------------------- theme
  // Same central [menu] color tokens the built-in menu uses, so the
  // command center matches whatever theme is active.
  readonly property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius

  property int cardWidth: Math.min(1180, panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(740, panel.height - Style.gapsOut * 2)
  readonly property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.space(16))
  readonly property int groupRowHeight: Math.max(Style.space(40), Style.font.body + Style.space(14))

  // ---------------------------------------------------------- catalog state
  property var catalog: []
  property var groupInfo: ({})
  property var recentRoutes: []
  // route -> {count, last} launch history: drives frecency ranking and the
  // persistent recents marker; recorded through update-usage.sh.
  property var usage: ({})
  // Per-token form values for the detail pane, aligned with detailCmd.tokens.
  property var formValues: []
  // Pinned favorites (routes, most recently pinned first) — commands and
  // apps alike; persisted to $XDG_STATE_HOME/omarchy-cmdcenter/pins.json
  // by toggle-pin.sh.
  property var pins: []
  // Lazy per-command help: fetched via `--help` on first selection, cached
  // in-memory for the session. helpLoading marks a fetch in flight.
  property var helpCache: ({})
  property string helpText: ""
  property bool helpLoading: false
  property string helpRoute: ""
  // Environment probe (detect-env.sh, one-shot at startup): installed agent
  // CLIs, the Omarchy default agent (primary ask row), and the default
  // browser's search engine for the web-search fallback row.
  property var availableAgents: []
  property string defaultAgent: ""
  property string webEngineName: "DuckDuckGo"
  property string webTemplate: "https://duckduckgo.com/?q=%s"
  // Installed applications, delivered with the catalog (same .desktop
  // sources and hide-filters as the shell's AppLibrary) so the palette works
  // like a start menu: browse and launch apps alongside commands.
  property var apps: []
  property var appById: ({})
  property string activeGroup: "*"
  property string filterText: ""
  property int focusPane: 1        // 0 = groups, 1 = commands, 2 = detail
  property int selectedGroupIndex: 0
  property int selectedCommand: 0
  property int actionIndex: 0      // 0 = Run, 1 = Terminal, 2 = Copy
  property int displaySerial: 0
  property bool confirmOpen: false
  property string pendingCmdline: ""
  property string lastRunInfo: ""
  // Phase 5 (Deep Omarchy): live system status for the Controls view.
  // controlStates: action id → "on"/"off" (toggles) or gating values
  // ("ok"/"hidden" for suspend/hibernate). statusInfo: readouts (battery,
  // volume, cpu/mem, connection). Filled by status.sh — re-probed on open,
  // on entering Controls, and after every toggle; never on a timer.
  property var controlStates: ({})
  property var statusInfo: ({})
  // NB: `double`, never `int` — QML ints are 32-bit, and every millisecond
  // timestamp (Date.now()) overflows them. Doubles hold ms exactly.
  property double statusAt: 0
  // Power/session action awaiting the shared confirmation dialog.
  property var pendingPower: null
  // Footer rail (Phase 5+): the sticky strip of control tiles at the
  // card's bottom edge. Tiles are a pure function of probed state
  // (Controls.footerTiles); openPopover names the multi-control tile
  // (audio/power) whose anchored mini-popover is open ("" = none),
  // popoverAnchor the tile Item it points at.
  readonly property var footerTiles: Controls.footerTiles(root.controlStates, root.statusInfo)
  property string openPopover: ""
  property var popoverAnchor: null

  readonly property int _detailKey: displaySerial * 100000 + selectedCommand
  // Full catalog command for the selected row, resolved from the catalog by
  // route — ListModel rows only carry the roles the delegates need, while
  // the detail pane wants tokens/examples too. _detailKey forces the
  // binding to re-evaluate on every rebuild and selection change.
  readonly property var detailCmd: {
    var key = _detailKey
    if (selectedCommand < 0 || selectedCommand >= displayModel.count) return null
    var row = displayModel.get(selectedCommand)
    if (row.kind === "app") {
      return root.appById[String(row.route).slice(4)] || null
    }
    for (var i = 0; i < root.catalog.length; i++) {
      if (root.catalog[i].route === row.route) return root.catalog[i]
    }
    return null
  }
  readonly property bool detailIsApp: detailCmd !== null && detailCmd.isApp === true
  // Raw selected-row access + computed-row helpers. detailCmd resolves only
  // catalog/app records (returns null for computed rows); detailKind/ayload
  // read the JSON payload carried by calculator/conversion/web/agent rows so
  // the detail pane can render them with their own card.
  readonly property var detailRow: {
    var key = _detailKey
    if (selectedCommand < 0 || selectedCommand >= displayModel.count) return null
    return displayModel.get(selectedCommand)
  }
  readonly property string detailKind: detailRow ? String(detailRow.kind || "") : ""
  readonly property var detailPayload: {
    var key = _detailKey
    var row = root.detailRow
    if (!row || !row.payload) return null
    try { return JSON.parse(row.payload) } catch (e) { return null }
  }
  readonly property bool detailIsCmd: detailKind === "cmd"
  // Computed-style rows render their own card: calculator/conversions,
  // web/agent, plus the Phase-5 control rows (toggle/panel/power/status)
  // and history entries.
  readonly property bool detailIsComputed: detailKind === "calc" || detailKind === "convert"
    || detailKind === "web" || detailKind === "agent"
    || detailKind === "window" || detailKind === "clip"
    || detailKind === "file" || detailKind === "dict"
    || detailKind === "toggle" || detailKind === "panel" || detailKind === "power"
    || detailKind === "status" || detailKind === "history"
    || detailKind === "newsitem" || detailKind === "newsrefresh"
    || detailKind === "newsfeeds" || detailKind === "feedadd"
  // Real image for the detail pane: computed rows carry theirs in the
  // payload (window → resolved app icon, clipboard image → the shot).
  readonly property string detailIcon: {
    var p = root.detailPayload
    if (!p) return ""
    if (p.kind === "window") return String(p.icon || "")
    if (p.kind === "clip" && String(p.type || "") === "image")
      return String(p.path || "")
    return ""
  }
  readonly property string activeGroupLabel: {
    if (filterText) return "Results"
    if (activeGroup === "*") return "All commands"
    if (activeGroup === "__apps") return "Apps"
    if (activeGroup === "__controls") return "Controls"
    if (activeGroup === "__history") return "History"
    if (activeGroup === "__news") return "News"
    return activeGroup
  }

  ListModel { id: displayModel }
  ListModel { id: groupListModel }
  // Recent strip: top few launches (apps + commands) by most-recent, fed
  // from the same usage.json that drives frecency — no extra tracking.
  ListModel { id: recentModel }

  // ---------------------------------------------------------- catalog loading
  // Mutable state (catalog cache, usage, pins) lives in the XDG state dir,
  // OUTSIDE the plugin tree: the shell's hot-reload watcher runs
  // `inotifywait -m -r` over the whole plugin directory, so writes under it
  // would reload the plugin mid-operation and recreate the palette.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-cmdcenter"
  readonly property string cachePath: root.stateDir + "/commands.json"

  // Builds the cache atomically (commands + group descriptions + apps), then
  // prints it. The builder lives next to the plugin; running it as a script
  // keeps shell quoting out of QML. Via login shell so `omarchy` is on PATH
  // and the XDG env the hide-filters expect is present.
  readonly property string catalogScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/build-catalog.sh"
  readonly property string usageScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/update-usage.sh"

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    printErrors: false
    onLoaded: { if (text().length) root.applyCatalog(text()) }
    onLoadFailed: { if (!root.rowsLoaded) root.startCatalogLoad() }
  }

  // Launch history, written by update-usage.sh. Missing file simply means
  // no history yet; a malformed one resets to empty rather than crashing.
  // watchChanges:true keeps memory in sync with the script's writes (and any
  // external edit) — without it, in-memory and on-disk history diverge until
  // the next restart, which silently revived forgotten recents.
  FileView {
    id: usageFile
    path: root.stateDir + "/usage.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var map = ({})
      try { map = JSON.parse(text() || "{}") || ({}) } catch (e) { map = ({}) }
      root.usage = map
      root.recentRoutes = root.recentRoutesFromUsage()
      root.updateHistoryGroupCount()
      root.rebuildDisplay(true)
      root.rebuildRecents()
    }
  }

  readonly property string pinsScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/toggle-pin.sh"

  // Pinned favorites, written by toggle-pin.sh. Same resilience contract
  // as the usage file above, including the omarchy-menu.qml watch pattern:
  // watchChanges only signals — onFileChanged must reload.
  FileView {
    id: pinsFile
    path: root.stateDir + "/pins.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var list = []
      try {
        var parsed = JSON.parse(text() || "[]")
        if (Array.isArray(parsed)) list = parsed.map(String)
      } catch (e) { list = [] }
      root.pins = list
      root.updatePinsGroupCount()
      root.rebuildDisplay(true)
    }
  }

  // ---------------------------------------------------------- news (Phase 6)
  // RSS/Atom reader: fetch-feeds.sh writes news.json (raw XML embedded;
  // feeds.json seeds with starter feeds on first run and is user-owned
  // afterwards), FeedParser.js flattens every feed into one newest-first
  // list. Same watch-reload contract as usage/pins: watchChanges only
  // signals — onFileChanged must reload.
  property var newsItems: []
  property var newsFeeds: []
  property double newsAt: 0
  property int newsErrors: 0
  // Rate-limiter for the quiet background refresh on entering News.
  property double newsCheckedAt: 0
  readonly property string newsScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/fetch-feeds.sh"
  readonly property string addFeedScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/add-feed.sh"
  readonly property string artScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/fetch-art.sh"
  readonly property string logoScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/player-icon.sh"
  readonly property string mprisCtlScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/mpris-ctl.sh"
  readonly property string raiseScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/raise-player.sh"
  readonly property string mediaMemoryScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/media-memory.sh"
  readonly property string idleScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/idle-settings.sh"

  // -------------------------------------------- search providers (Phase 7)
  readonly property string winCtlScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/win-ctl.sh"
  readonly property string dictScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/dict-lookup.sh"
  readonly property string fileSearchScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/file-search.sh"
  // Omarchy's first-party clipboard helpers (paste = copy + type into the
  // focused window); the history-index is the array position below.
  readonly property string clipPasteText: "/usr/share/omarchy/bin/omarchy-clipboard-paste-text"
  readonly property string clipPasteFile: "/usr/share/omarchy/bin/omarchy-clipboard-paste-file"
  // Shared clipboard history captured by omarchy-shell's clipboard plugin —
  // read-only here, same file its own menu reads (index 0 = newest).
  readonly property string clipHistoryPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property var clipHistory: []

  FileView {
    id: clipFile
    path: root.clipHistoryPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = null
      try { parsed = JSON.parse(text() || "[]") } catch (e) { parsed = null }
      root.clipHistory = SearchP.normalizeClip(parsed)
    }
  }

  // In-memory provider state: the window list is re-probed whenever the
  // palette is active (never on a timer); the dictionary answer is keyed to
  // the word that produced it; file results belong to one serial-tagged fd
  // run. (All invisible fields — guard anything the QML ever binds.)
  property var winList: []
  property var dictResult: ({})
  property string dictWord: ""
  property string fileQuery: ""
  property var fileResults: []
  property double fileSerial: 0
  property double dictSerial: 0
  // Last file-search exit for the debug probe (-1 = never ran).
  property int fileProcExit: -1

  FileView {
    id: newsFile
    path: root.stateDir + "/news.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root._applyNews(text())
  }

  function _applyNews(text) {
    var payload = null
    try { payload = JSON.parse(text || "{}") } catch (e) { payload = null }
    root.newsFeeds = payload && payload.feeds
      ? payload.feeds.map(function(f) {
          return { id: String(f.id || ""), name: String(f.name || ""),
            url: String(f.url || ""), logo: String(f.logo || "") }
        })
      : []
    root.newsItems = FeedParser.itemsFromPayload(payload, 80)
    root.newsAt = payload && payload.fetchedAt ? Number(payload.fetchedAt) : 0
    root.newsErrors = payload && payload.errors ? Number(payload.errors) : 0
    root.updateNewsGroupCount()
    // Best-effort article heroes: positional name=url pairs for the
    // newest stories; the script skips files already cached, so this is
    // near-free on every load and only new/missing images cost a fetch.
    var args = ["bash", root.newsScript, "--fetch-images"]
    var cap = Math.min(root.newsItems.length, 15)
    for (var k = 0; k < cap; k++) {
      var im = root.newsItems[k].image
      if (im) args.push("item" + k + "=" + im)
    }
    if (args.length > 3) Quickshell.execDetached(args)
    if (root.activeGroup === "__news" && !root.filterText) root.rebuildDisplay()
  }

  function updateNewsGroupCount() {
    for (var i = 0; i < groupListModel.count; i++) {
      if (groupListModel.get(i).name === "__news") {
        groupListModel.setProperty(i, "count", root.newsItems.length)
        return
      }
    }
  }

  // News group rows: a refresh row and an edit-feeds row first (age of
  // the last fetch), then the latest stories across every configured
  // feed — each carrying its feed logo (appIcon role → the row Image),
  // hero URL, and excerpt for the detail card.
  function newsRows() {
    var rows = []
    var age = root.newsAt ? Controls.relativeTime(root.newsAt, Date.now()) : ""
    var refresh = root.computedRow("newsrefresh", "Refresh feeds",
      age ? "Updated " + age : "Fetch the configured feeds now",
      { kind: "newsrefresh", label: "Refresh feeds" })
    refresh.group = Controls.NEWS_GLYPHS.refresh
    rows.push(refresh)
    var edit = root.computedRow("newsfeeds", "Edit feeds",
      root.newsFeeds.length + " feeds configured · opens in your editor",
      { kind: "newsfeeds", label: "Edit feeds" })
    edit.group = Controls.NEWS_GLYPHS.edit
    rows.push(edit)
    for (var i = 0; i < root.newsItems.length; i++) {
      var it = root.newsItems[i]
      var row = root.computedRow("newsitem", it.title,
        it.source + (it.published
          ? " · " + Controls.relativeTime(it.published, Date.now()) : ""),
        { kind: "newsitem", label: it.title, url: it.url,
          source: it.source, published: it.published, idx: i,
          image: it.image || "", excerpt: it.excerpt || "",
          logo: it.logo || "" })
      row.group = Controls.NEWS_GLYPHS.news
      row.appIcon = it.logo || ""   // feed favicon → the row's Image slot
      rows.push(row)
    }
    return rows
  }

  // A full http(s) URL typed/pasted as the query is feed intent: the
  // inline "Add as feed" row leads the results in any group. Validation
  // and feed discovery live in add-feed.sh (argv-only URL); Enter runs
  // it directly (instant kind).
  function isFeedUrlQuery(q) {
    return /^https?:\/\/\S+\.\S+/.test(String(q).trim())
  }

  function addFeedRow(url) {
    var u = String(url).trim()
    var row = root.computedRow("feedadd", "Add as feed",
      u + " · discovers the feed, validates, refreshes",
      { kind: "feedadd", label: u, url: u })
    row.group = Controls.NEWS_GLYPHS.add
    return row
  }

  Process {
    id: newsProc
    running: false
    command: ["bash", root.newsScript]
    stdout: StdioCollector { id: newsOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.osd(Controls.NEWS_GLYPHS.refresh,
        exitCode === 0 ? "Feeds updated" : "Feed refresh failed")
      newsFile.reload()   // the watcher fires too; reload is idempotent
    }
  }

  // Manual refresh (Refresh feeds row / its detail button). The palette
  // stays open — news.json's watch event rebuilds the list when done.
  function fetchNews() {
    if (newsProc.running) {
      root.osd(Controls.NEWS_GLYPHS.refresh, "Feeds already refreshing")
      return
    }
    root.osd(Controls.NEWS_GLYPHS.refresh, "Refreshing feeds…")
    newsProc.running = true
  }

  // Quiet background refresh when the News group is entered and the
  // cache is older than 30 minutes — fetch-feeds.sh's --max-age gate
  // makes a fresh cache a zero-cost no-op.
  function maybeNewsRefresh() {
    var now = Date.now()
    if (now - root.newsCheckedAt < 300000) return
    root.newsCheckedAt = now
    Quickshell.execDetached(["bash", root.newsScript, "--max-age", "1800"])
  }

  // Inline feed add (argv-only URL). Script exits: 0 ok (name on
  // stdout) · 3 already added · anything else a stderr reason. On
  // success we land in the News group — selectGroup clears the filter.
  Process {
    id: addFeedProc
    running: false
    command: ["bash", root.addFeedScript, ""]
    stdout: StdioCollector { id: addFeedOut; waitForEnd: true }
    stderr: StdioCollector { id: addFeedErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var name = String(addFeedOut.text || "").trim()
        root.osd(Controls.NEWS_GLYPHS.add, "Added " + (name || "feed"))
        for (var gi = 0; gi < groupListModel.count; gi++) {
          if (groupListModel.get(gi).name === "__news") { root.selectGroup(gi); break }
        }
      } else {
        root.osd(Controls.NEWS_GLYPHS.add,
          String(addFeedErr.text || "Couldn't add feed").trim().slice(0, 64))
      }
    }
  }

  function addFeed(url) {
    if (!url) return
    if (addFeedProc.running) {
      root.osd(Controls.NEWS_GLYPHS.add, "An add is already running")
      return
    }
    root.osd(Controls.NEWS_GLYPHS.add, "Validating feed…")
    addFeedProc.command = ["bash", root.addFeedScript, url]
    addFeedProc.running = true
  }

  // ---------------------------------------------------------- home (Phase 6b)
  // Ambient cards for the default view (group *, no query): weather,
  // now-playing, system stats, today. Same no-timer rule as status.sh —
  // weather refreshes on open with a 5-minute throttle, stats ride the
  // status probe, the date rebuilds on open; MPRIS is reactive by
  // nature. No calendar/events source exists on a stock box, so TODAY
  // is a date card (events = Phase 8, if ever configured).
  property var homeDate: new Date()
  readonly property var homeDay: Dashboard.buildDateCard(root.homeDate)
  property string weatherText: ""
  property string weatherIcon: ""
  property double weatherAt: 0
  readonly property bool homeVisible: root.opened && !root.filterText
    && root.activeGroup === "*"
  readonly property var homeWeather: Dashboard.parseWeatherLine(root.weatherText)
  // Condition text + country from the probe's third line (wttr.in's j1
  // payload — the same upstream omarchy's own weather commands use).
  property string weatherDetailText: ""
  readonly property var homeWeatherDetail:
    Dashboard.parseWeatherDetail(root.weatherDetailText)

  // The System & Network tile's 3×3 metric grid (8.3): link health,
  // traffic, identity. "—" until the open-cycle status probe lands;
  // rates are the probe's 1s window.
  readonly property var sysGrid: [
    [
      { l: "Ping",
        v: root.statusInfo.ping
          ? Math.round(Number(root.statusInfo.ping)) + "ms" : "—" },
      { l: "Loss",
        v: root.statusInfo.loss !== undefined ? root.statusInfo.loss + "%" : "—" },
      { l: "Receiving",
        v: root.statusInfo.rxRate !== undefined
          ? Dashboard.fmtBytes(root.statusInfo.rxRate) + "/s" : "—" }
    ],
    [
      { l: "Sending",
        v: root.statusInfo.txRate !== undefined
          ? Dashboard.fmtBytes(root.statusInfo.txRate) + "/s" : "—" },
      { l: "Downloaded",
        v: root.statusInfo.rxB !== undefined
          ? Dashboard.fmtBytes(root.statusInfo.rxB) : "—" },
      { l: "Uploaded",
        v: root.statusInfo.txB !== undefined
          ? Dashboard.fmtBytes(root.statusInfo.txB) : "—" }
    ],
    [
      { l: "IP", v: root.statusInfo.ip || "—" },
      { l: "Gateway", v: root.statusInfo.gateway || "—" },
      { l: "CPU", v: root.statusInfo.cpu || "—" }
    ]
  ]

  // First MPRIS player holding a title, preferring the one actually
  // playing. Quickshell's own service — no playerctl dependency (same
  // guard idiom Omarchy's media service uses).
  readonly property var nowPlaying: {
    var players = Mpris.players ? Mpris.players.values : []
    var fallback = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.trackTitle) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }

  // One subprocess: condition glyph + status line + detail line
  // (condition text · country from wttr.in's j1 — same location source
  // and upstream as omarchy's own weather commands). The three fetches
  // run in parallel (worst case ≈ slowest single curl, ~5s) so the
  // tile fills within a transient palette's lifetime; each writes to
  // its own slot in a trap-cleaned temp dir so line order is stable.
  // Static command string, no user input.
  Process {
    id: weatherProc
    running: false
    command: ["bash", "-lc",
      "d=$(mktemp -d); trap 'rm -rf \"$d\"' EXIT; " +
      "omarchy weather icon >\"$d/i\" 2>/dev/null & " +
      "omarchy weather status >\"$d/s\" 2>/dev/null & " +
      "{ place=$(omarchy weather location 2>/dev/null); " +
      "[ -n \"$place\" ] && curl -fsS --max-time 4 " +
      "\"https://wttr.in/$(jq -rn --arg p \"$place\" '$p | @uri')?format=j1\" " +
      "2>/dev/null | jq -r '[(.current_condition[0].weatherDesc[0].value // \"\"), " +
      "(.nearest_area[0].country[0].value // \"\")] | @tsv'; } " +
      ">\"$d/d\" 2>/dev/null & wait; " +
      "cat \"$d/i\"; echo; cat \"$d/s\"; echo; cat \"$d/d\""]
    stdout: StdioCollector { id: weatherOut; waitForEnd: true }
    onExited: function() {
      var o = Dashboard.parseWeatherOutput(weatherOut.text)
      root.weatherIcon = o.icon
      root.weatherText = o.line
      root.weatherDetailText = o.detail
      root.weatherAt = Date.now()
    }
  }

  function refreshHome() {
    root.homeDate = new Date()
    if (Date.now() - root.weatherAt > 300000 && !weatherProc.running)
      weatherProc.running = true
    root.refreshMediaPos()   // playback clock snaps on every open
  }

  // ------------------------------------------------- media strip (6b.1)
  // Album art + player logo for the now-playing tile. QML's Image never
  // fetches http(s) (pitfall), so downloads go through fetch-art.sh into
  // state/media/art.img, cache-busted by artVersion (?v= on the file
  // URL); file:// art (mpv etc.) is used as-is. The player logo resolves
  // via player-icon.sh (MPRIS desktopEntry → .desktop Icon= → hicolor /
  // pixmaps), cached per identity in JS for the palette's lifetime.
  // Both sync on title/art changes AND on player swaps (Connections +
  // onNowPlayingChanged below — a player swap doesn't emit track
  // signals on the new object).
  property string mediaArt: ""         // full local file:// source (or "")
  property string mediaLogo: ""
  property string mediaLogoFor: ""
  property string mediaArtUrl: ""      // remote url being fetched
  property string mediaPendingUrl: ""  // arrived while a fetch was in flight
  property int artVersion: 0
  property var logoCache: ({})
  property double mediaPosUs: -1       // fresh µs off the bus (-1 = unknown)

  // Track length comes from the MPRIS metadata map (spec: µs) — refreshed
  // by the player itself on every track change. Position does NOT: quickshell's
  // cached `position` only moves when a player emits change signals, and
  // Spotify never does (bar froze after prev/next — verified live), so
  // position is read straight off the session bus by mpris-ctl.sh.
  readonly property double mediaLenUs: {
    var p = root.nowPlaying
    if (!p || !p.metadata) return 0
    return Number(p.metadata["mpris:length"] || 0)
  }
  readonly property double mediaFrac: {
    if (!(root.mediaLenUs > 0) || root.mediaPosUs < 0) return -1
    return Math.min(1, root.mediaPosUs / root.mediaLenUs)
  }
  readonly property string mediaElapsed: Dashboard.fmtTime(root.mediaPosUs)
  readonly property string mediaTotal: Dashboard.fmtTime(root.mediaLenUs)

  function syncMediaArt() {
    var p = root.nowPlaying
    var url = p ? String(p.trackArtUrl || "") : ""
    if (!url) { root.mediaArt = ""; root.mediaPendingUrl = ""; return }
    if (url.indexOf("file://") === 0) { root.mediaArt = url; return }
    if (url.indexOf("http") !== 0) { root.mediaArt = ""; return }
    if (url === root.mediaArtUrl) return
    if (artProc.running) { root.mediaPendingUrl = url; return }
    root.mediaArtUrl = url
    artProc.command = [root.artScript, url]
    artProc.running = true
  }

  function syncMediaLogo() {
    var p = root.nowPlaying
    var key = p ? String(p.desktopEntry || p.identity || "") : ""
    if (!key) { root.mediaLogo = ""; root.mediaLogoFor = ""; return }
    if (key === root.mediaLogoFor) return
    root.mediaLogoFor = key
    if (root.logoCache.hasOwnProperty(key)) {
      root.mediaLogo = root.logoCache[key]; return
    }
    if (logoProc.running) return     // vanishingly rare; next change retries
    logoProc.command = [root.logoScript, key]
    logoProc.running = true
  }

  Process {
    id: artProc
    running: false
    command: ["bash", root.artScript, ""]
    stdout: StdioCollector { id: artOut; waitForEnd: true }
    stderr: StdioCollector { id: artErr; waitForEnd: true }
    onExited: function(exitCode) {
      // 0 downloaded · 3 already cached — both mean art.img is current.
      if (exitCode === 0 || exitCode === 3) {
        root.artVersion++
        root.mediaArt = "file://" + root.stateDir + "/media/art.img?v="
          + root.artVersion
      }
      // A track skip landed mid-fetch: re-run for the newer url.
      if (root.mediaPendingUrl) {
        root.mediaPendingUrl = ""
        root.syncMediaArt()
      }
    }
  }

  Process {
    id: logoProc
    running: false
    command: ["bash", root.logoScript, ""]
    stdout: StdioCollector { id: logoOut; waitForEnd: true }
    onExited: function(exitCode) {
      var path = exitCode === 0 ? String(logoOut.text || "").trim() : ""
      root.logoCache[root.mediaLogoFor] = path
      root.mediaLogo = path
    }
  }

  // ---------------------------------------------------- playback clock (6b.2)
  // Position/seek talk straight to the session bus (MPRIS µs end to end):
  // quickshell's cached position only moves when a player emits change
  // signals — Spotify doesn't (bar froze after prev/next — verified live),
  // so mpris-ctl.sh does a Get on every tick. The 1s Timer runs ONLY while
  // the palette is open and a track is playing; paused/stopped snaps once
  // and goes quiet. This is a UI playback clock, not a data refresh — the
  // dashboard's no-timer rule is respected.
  function refreshMediaPos() {
    var p = root.nowPlaying
    if (!p || posProc.running) return
    posProc.command = [root.mprisCtlScript, "pos", String(p.dbusName || "")]
    posProc.running = true
  }

  // Drag-release / click on the bar: seek to an absolute target µs. The
  // script computes the relative offset itself from a fresh Get, so a stale
  // cache can never skew the jump. The bar updates optimistically first.
  function seekMediaTo(frac) {
    var p = root.nowPlaying
    if (!p || !(root.mediaLenUs > 0) || seekProc.running) return
    var target = Math.max(0, Math.min(root.mediaLenUs,
      Math.round(frac * root.mediaLenUs)))
    root.mediaPosUs = target
    seekProc.command = [root.mprisCtlScript, "seek", String(p.dbusName || ""),
      String(target)]
    seekProc.running = true
  }

  // Clicking art/title raises the player for ANY media player: try MPRIS
  // Raise() first (some clients honor it), then omarchy's Hyprland focus
  // helper — raw hyprctl dispatch is broken upstream (0.56.2 Lua configs,
  // known issue #16224) and Spotify ignores Raise() entirely (verified).
  function raisePlayer() {
    var p = root.nowPlaying
    if (!p) return
    if (p.canRaise) p.raise()
    raiseProc.command = [root.raiseScript,
      String(p.desktopEntry || p.identity || "")]
    raiseProc.running = true
  }

  Process {
    id: posProc
    running: false
    command: ["bash", root.mprisCtlScript, "pos", ""]
    stdout: StdioCollector { id: posOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var v = parseInt(String(posOut.text || "").trim(), 10)
      if (!isNaN(v) && v >= 0) root.mediaPosUs = v
    }
  }

  Process {
    id: seekProc
    running: false
    command: ["bash", root.mprisCtlScript, "seek", "", "0"]
    onExited: root.refreshMediaPos()   // settle onto the player's real spot
  }

  Process {
    id: raiseProc
    running: false
    command: ["bash", root.raiseScript, ""]
  }

  Timer {
    id: posTimer
    interval: 1000
    repeat: true
    running: root.opened && root.nowPlaying !== null
      && root.nowPlaying.isPlaying && root.mediaLenUs > 0
    onTriggered: root.refreshMediaPos()
  }

  // In-player track changes (title/art) — the swap case is handled by
  // onNowPlayingChanged next to it. Title changes also mean a new track:
  // snap the clock (a seek timer may still be mid-flight; posProc guards).
  Connections {
    target: root.nowPlaying
    function onTrackTitleChanged() {
      root.syncMediaArt(); root.syncMediaLogo(); root.refreshMediaPos()
    }
    function onTrackArtUrlChanged() { root.syncMediaArt() }
    function onIsPlayingChanged() { root.refreshMediaPos() }
    function onPositionChanged() { root.refreshMediaPos() }  // players that do emit
  }
  onNowPlayingChanged: {
    root.mediaPosUs = -1
    root.syncMediaArt(); root.syncMediaLogo(); root.refreshMediaPos()
    root.saveMediaMemory()   // freeze the new track for the ghost tile
  }

  // ------------------------------------------------ last-media ghost (7.2)
  // Windows-style pin: the last-played track stays on the strip after the
  // player closes — dimmed, frozen at the last saved position; clicking
  // relaunches the player. media-memory.sh persists the snapshot (and a
  // copy of the fetched art) on every meaningful playback moment; the
  // FileView watches the snapshot so an external write updates the tile.
  property var ghostMedia: null
  readonly property bool ghostHasMedia: root.ghostMedia !== null
    && String(root.ghostMedia.title || "") !== ""
  readonly property real ghostFrac: {
    var g = root.ghostMedia
    if (!g || !(Number(g.lenUs) > 0)) return -1
    return Math.min(1, Math.max(0, Number(g.posUs) / Number(g.lenUs)))
  }

  FileView {
    id: ghostFile
    path: root.stateDir + "/last-media.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var snap = null
      try { snap = JSON.parse(text() || "null") || null } catch (e) { snap = null }
      root.ghostMedia = snap
    }
  }

  // Persist the current playback (or refresh the art copy once a fetch
  // lands). Silent no-op while nothing plays — the old snapshot stays.
  // All values are argv elements; the script's jq does the encoding.
  function saveMediaMemory() {
    var p = root.nowPlaying
    if (!p || saveMediaProc.running) return
    var title = String(p.trackTitle || "")
    if (!title) return
    var app = root.appForPlayer(p)
    var art = ""
    if (root.mediaArt.indexOf("file://") === 0)
      art = root.mediaArt.split("?")[0].replace("file://", "")
    saveMediaProc.command = [root.mediaMemoryScript, "save",
      title, String(p.trackArtist || ""),
      app ? String(app.id) : "", String(p.identity || p.desktopEntry || ""),
      art || "-", root.mediaLogo || "-",
      String(root.mediaLenUs > 0 ? Math.round(root.mediaLenUs) : 0),
      String(root.mediaPosUs >= 0 ? Math.round(root.mediaPosUs) : 0)]
    saveMediaProc.running = true
  }

  // The ghost tile's launch target: the player's desktop app in the
  // catalog (same resolution shape as window icons), or null.
  function appForPlayer(p) {
    if (!p) return null
    var keys = [String(p.desktopEntry || "").toLowerCase(),
      String(p.identity || "").toLowerCase()]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i].replace(/\.desktop$/, "")
      if (k && root.appById[k] && root.appById[k].isApp) return root.appById[k]
    }
    for (var j = 0; j < root.apps.length; j++) {
      var n = String(root.apps[j].name || "").toLowerCase()
      if (keys.indexOf(n) !== -1) return root.apps[j]
    }
    return null
  }

  function launchGhostPlayer() {
    var g = root.ghostMedia
    if (!g) return
    var app = root.appById[String(g.appId || "")]
    if (app && app.isApp) root.launchAppRecord(app)  // closes the palette
  }

  Process {
    id: saveMediaProc
    running: false
    command: ["bash", root.mediaMemoryScript, "load"]
  }

  // Closing the palette hands off mid-track: save once more so the ghost
  // freezes at the position the user actually left it at.
  onOpenedChanged: { if (!root.opened) root.saveMediaMemory() }

  // Debounce for the --help fetch: fires once the selection settles.
  Timer {
    id: helpTimer
    interval: 300
    onTriggered: root.fetchHelp()
  }

  Process {
    id: helpProc
    running: false
    stdout: StdioCollector { id: helpOut; waitForEnd: true }
    onExited: function(exitCode) {
      var route = root.helpRoute
      var text = exitCode === 0 ? String(helpOut.text || "") : ""
      var cacheCopy = ({})
      for (var k in root.helpCache) cacheCopy[k] = root.helpCache[k]
      cacheCopy[route] = text
      root.helpCache = cacheCopy
      // Apply only if this is still the selected command. If a newer
      // request came in while we were running, re-arm the debounce.
      if (root.detailCmd && root.detailCmd.route === route) {
        root.helpLoading = false
        root.helpText = text
      } else if (root.helpLoading) {
        helpTimer.restart()
      }
    }
  }

  // ------------------------------------------------- window switching (7)
  // A fresh list whenever the palette is doing something (open, status
  // refresh) — never on a timer. win-ctl.sh already filters out the
  // current window, omarchy's own surfaces, and the Window Controls shelf.
  Process {
    id: winListProc
    running: false
    stdout: StdioCollector { id: winListOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try { root.winList = JSON.parse(String(winListOut.text || "[]")) || [] }
      catch (e) { root.winList = [] }
    }
  }
  function refreshWindows() {
    if (winListProc.running) return
    winListProc.command = ["bash", root.winCtlScript, "list"]
    winListProc.running = true
  }

  // ---------------------------------------------------- file search (7)
  // Debounced like the --help fetch: one fd run once the query settles;
  // the serial guard drops results for a query the user already left.
  Timer {
    id: fileSearchTimer
    interval: 250
    onTriggered: root.runFileSearch()
  }
  Process {
    id: fileSearchProc
    running: false
    stdout: StdioCollector { id: fileSearchOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.fileProcExit = exitCode
      var serial = root.fileSerial
      var q = root.fileQuery
      var paths = exitCode === 0
        ? SearchP.fileMatches(String(fileSearchOut.text || ""), q, 8) : []
      if (q === root.fileQuery && serial === root.fileSerial) {
        root.fileResults = paths
        root.rebuildDisplay()
      }
    }
  }
  function runFileSearch() {
    if (fileSearchProc.running) return
    if (!root.fileQuery) return
    fileSearchProc.command = ["bash", root.fileSearchScript, root.fileQuery]
    fileSearchProc.running = true
  }

  // --------------------------------------------------- dictionary (7)
  // "?word" → dictionaryapi.dev via dict-lookup.sh, same debounce and
  // serial contract as the file search; misses resolve on their own.
  Timer {
    id: dictTimer
    interval: 400
    onTriggered: root.runDictLookup()
  }
  Process {
    id: dictProc
    running: false
    stdout: StdioCollector { id: dictOut; waitForEnd: true }
    onExited: function(exitCode) {
      var word = root.dictWord
      var serial = root.dictSerial
      if (word === root.dictWord && serial === root.dictSerial) {
        root.dictResult = { word: word,
          definition: exitCode === 0 ? String(dictOut.text || "").trim() : "" }
        root.rebuildDisplay()
      }
    }
  }
  function runDictLookup() {
    if (dictProc.running) return
    if (!root.dictWord) return
    dictProc.command = ["bash", root.dictScript, root.dictWord]
    dictProc.running = true
  }

  Process {
    id: catalogProc
    running: false
    command: ["bash", "-lc", "exec bash " + Util.shellQuote(root.catalogScript)]
    stdout: StdioCollector { id: catalogOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && catalogOut.text.length) {
        root.applyCatalog(catalogOut.text)
      } else if (!root.rowsLoaded) {
        root.loadError = "Could not load the command catalog"
      }
    }
  }

  function startCatalogLoad() {
    root.loadError = ""
    if (!catalogProc.running) catalogProc.running = true
  }

  function applyCatalog(jsonText) {
    var data = null
    try { data = JSON.parse(jsonText) } catch (e) { data = null }
    if (!data || !data.commands) {
      root.loadError = "Command catalog is malformed"
      return
    }
    root.catalog = CmdModel.parseCatalog(data.commands)
    root.groupInfo = data.groups || ({})
    root.applyApps(data.apps || [])
    console.log("cmdcenter: catalog loaded: " + root.catalog.length + " commands, " + root.apps.length + " apps")
    var groups = CmdModel.buildGroupList(root.catalog, root.groupInfo)

    groupListModel.clear()
    groupListModel.append({
      name: "*", label: "All commands", glyph:"󰒓",
      description: "Every omarchy command", count: root.catalog.length
    })
    groupListModel.append({
      name: "__pins", label: "Pinned", glyph: "★",
      description: "Your favorites", count: root.pins.length
    })
    groupListModel.append({
      name: "__apps", label: "Apps", glyph: "󰀻",
      description: "Installed applications", count: root.apps.length
    })
    groupListModel.append({
      name: "__controls", label: "Controls", glyph: Controls.GROUP_GLYPHS.controls,
      description: "Toggles, settings, and session actions",
      count: Controls.ACTIONS.length
    })
    groupListModel.append({
      name: "__history", label: "History", glyph: Controls.GROUP_GLYPHS.history,
      description: "Launches over time",
      count: Controls.historyEntries(root.usage).length
    })
    groupListModel.append({
      name: "__news", label: "News", glyph: Controls.NEWS_GLYPHS.news,
      description: "Feeds you follow",
      count: root.newsItems.length
    })
    for (var i = 0; i < groups.length; i++) {
      groupListModel.append({
        name: groups[i].name, label: groups[i].label,
        glyph: CmdModel.groupGlyph(groups[i].name),
        description: groups[i].description, count: groups[i].count
      })
    }

    root.rowsLoaded = true
    root.loadError = ""
    root.syncGroupSelection()
    root.rebuildDisplay()
    root.rebuildRecents()
  }

  // ---------------------------------------------------------- apps
  // Apps arrive with the catalog JSON: build-catalog.sh enumerates the same
  // .desktop entries and hide-filters the shell's AppLibrary itself uses.
  // The shell's appLibrary facade is currently null for third-party menu
  // plugins (upstream omacom/omarchy#10973, #11068, #10876), so the cache
  // path is the reliable equivalent. Records are normalized to the command
  // shape so CmdModel's fuzzy search ranks them together (apps below hits).
  function applyApps(list) {
    var out = []
    var map = ({})
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      var id = String(a && a.id || "")
      var name = String(a && a.name || "")
      if (!id || !name) continue
      var subtext = String(a.comment || "")
      var rec = {
        isApp: true,
        id: id,
        route: "app:" + id,
        name: name,
        subtext: subtext,
        icon: String(a.iconPath || ""),
        group: "app",
        summary: subtext,
        bare: name.toLowerCase(),
        searchText: (name + " " + subtext).toLowerCase(),
        aliases: Array.isArray(a.keywords) ? a.keywords.map(String) : [],
        tokens: [],
        examples: [],
        argCount: 0,
        complex: false,
        requiresSudo: false
      }
      out.push(rec)
      map[id] = rec
    }
    root.apps = out
    root.appById = map
  }

  function syncGroupSelection() {
    for (var i = 0; i < groupListModel.count; i++) {
      if (groupListModel.get(i).name === root.activeGroup) {
        root.selectedGroupIndex = i
        return
      }
    }
    root.selectedGroupIndex = 0
  }

  // ---------------------------------------------------------- universal providers
  // Computed rows: inline calculator + unit conversion, both pure-JS (no
  // shell, no eval) and instant. A row is only produced when the query
  // cleanly matches, so "2+2" becomes an answer while "theme set" does not.
  function computedRows(query) {
    var q = String(query || "").trim()
    var out = []
    if (!q || q.length > 80) return out
    if (MathEval.looksLikeMath(q)) {
      var m = MathEval.evaluate(q)
      if (m.ok) out.push(computedRow("calc", m.pretty, q + "  =", {
        kind: "calc", expr: q, result: m.pretty
      }))
    }
    var conv = Units.convert(q)
    if (conv.ok) out.push(computedRow("convert", conv.pretty, q, {
      kind: "convert", expr: q, result: conv.pretty
    }))
    return out
  }

  // Fallback rows: minimal by default — the DEFAULT agent, then web search —
  // so every query ends with exactly two suggestions. The "@" prefix opens
  // the full agent surface on demand instead:
  //   @            browse every installed agent (default first)
  //   @codex       open Codex (no prompt)
  //   @codex fix…  ask Codex with that prompt
  // When a query matches no commands/apps, these rows land directly under the
  // computed rows — i.e. at the top — so Enter asks the default agent
  // (user decision: agent rows above command matches when there are none).
  function fallbackRows(query) {
    var q = String(query || "").trim()
    var out = []
    if (!q || q.length > 200) return out
    if (q.charAt(0) === "@") return root.agentPrefixRows(q)
    if (SearchP.prefixOf(q)) return root.prefixProviderRows(q)
    if (root.defaultAgent) {
      out.push(computedRow("agent", "Ask " + Agents.displayName(root.defaultAgent),
        "with “" + q + "”",
        { kind: "agent", mode: "default", query: q,
          agentId: root.defaultAgent,
          agentName: Agents.displayName(root.defaultAgent) }))
    } else {
      out.push(computedRow("agent", "Choose default agent…", "set it up once",
        { kind: "agent", mode: "pick" }))
    }
    out.push(computedRow("web", "Search the web",
      "“" + q + "” in " + root.webEngineName,
      { kind: "web", query: q, url: root.webUrl(q), engine: root.webEngineName }))
    return out
  }

  // ----------------------------------------------- Phase-7 providers
  // Prefix-routed rows (";" clipboard, "/" files, "?" dictionary). Each
  // returns shaped rows straight from memory and arms its fetch when the
  // query outgrew the cache — the next rebuild (on exit) picks results up.
  // Window switching is the one automatic provider: matched rows lead the
  // catalog when a window's class/title fits the query.
  function prefixProviderRows(q) {
    var c = SearchP.prefixOf(q)
    var body = SearchP.bodyOf(q)
    if (c === ";") return root.clipRows(body)
    if (c === "/") return root.fileRows(body)
    return root.dictRows(body)
  }

  // ";" → clipboard history: bare ";" browses the newest entries, a typed
  // body filters them. Index = array position = --history-index target.
  // Image entries carry their stored file so the row renders a thumbnail.
  function clipRows(body) {
    var hits = SearchP.clipMatches(root.clipHistory, body, 8)
    var out = []
    for (var i = 0; i < hits.length; i++) {
      var h = hits[i]
      var e = h.entry
      if (e.type === "image") {
        out.push(computedRow("clip", "Image " + String(e.capturedAt || "").trim(),
          "clipboard image · Enter to paste",
          { kind: "clip", index: h.index, type: "image", path: e.path,
            mime: e.mime, body: e.path }, e.path))
      } else {
        var prev = SearchP.clipPreview(e.text)
        out.push(computedRow("clip", prev,
          "clipboard · Enter to paste",
          { kind: "clip", index: h.index, type: "text", text: e.text,
            body: prev }))
      }
    }
    return out
  }

  // "/" → file search: rows come from the last fd run; a query that
  // outgrew the cache arms the debounced fetch (results rebuild on exit).
  function fileRows(body) {
    var q = body.trim()
    if (!q) return []
    if (q !== root.fileQuery) {
      root.fileQuery = q
      root.fileSerial++
      root.fileResults = []
      fileSearchTimer.restart()
    }
    var out = []
    for (var i = 0; i < root.fileResults.length; i++) {
      var p = String(root.fileResults[i])
      var slash = p.lastIndexOf("/")
      var base = slash >= 0 ? p.slice(slash + 1) : p
      out.push(computedRow("file", base, p,
        { kind: "file", path: p, body: p }))
    }
    return out
  }

  // "?" → dictionary. "?fr hello" reads as a translate request and stays a
  // plain web row; a word waits on dict-lookup.sh; a miss or timeout falls
  // back to searching the web for the word itself.
  function dictRows(body) {
    var b = body.trim()
    if (!b) return []
    var spec = SearchP.translateSpec(b)
    if (spec) {
      var tq = "translate " + spec.text + " to " + spec.lang
      return [computedRow("web", "Translate “" + spec.text + "” → " + spec.lang,
        "in " + root.webEngineName,
        { kind: "web", query: tq, url: root.webUrl(tq),
          engine: root.webEngineName })]
    }
    if (!SearchP.isDictWord(b)) return []
    if (b !== root.dictWord) {
      root.dictWord = b
      root.dictSerial++
      dictTimer.restart()
    }
    var r = root.dictResult
    if (r && r.word === b && r.definition) {
      return [computedRow("dict", b, "definition · Enter to copy",
        { kind: "dict", word: b, definition: r.definition,
          body: r.definition })]
    }
    if (r && r.word === b && !r.definition) {
      return [computedRow("web", "Search the web",
        "“" + b + "” in " + root.webEngineName,
        { kind: "web", query: b, url: root.webUrl(b),
          engine: root.webEngineName })]
    }
    return []
  }

  // Resolve a window's class to a catalog app's icon path ("Spotify" →
  // the spotify desktop id → its iconPath). Unresolvable → "" and the row
  // falls back to its glyph, like apps without installed icons.
  function appIconForClass(cls) {
    var c = String(cls || "").trim().toLowerCase().replace(/\.desktop$/, "")
    if (!c) return ""
    var rec = root.appById[c]
    if (rec && rec.icon) return rec.icon
    for (var i = 0; i < root.apps.length; i++) {
      if (String(root.apps[i].name || "").toLowerCase() === c && root.apps[i].icon)
        return root.apps[i].icon
    }
    return ""
  }

  // Automatic window rows for a typed query (never for prefix queries;
  // win-ctl.sh keeps the list clean of current/omarchy/shelf windows).
  function windowRows(query) {
    var q = String(query || "").trim()
    if (!q || SearchP.prefixOf(q)) return []
    var hits = SearchP.windowMatches(root.winList, q, 4)
    var out = []
    for (var i = 0; i < hits.length; i++) {
      var w = hits[i]
      var where = w.ws ? " · " + w.ws : ""
      var icon = root.appIconForClass(w.class)
      out.push(computedRow("window", w.title || w.class, w.class + where,
        { kind: "window", addr: w.addr, title: w.title, class: w.class,
          icon: icon, body: w.class + where }, icon))
    }
    return out
  }

  // "@"-prefix rows: the full agent roster on demand, kept out of normal
  // searches so a dozen installed agents never flood the list.
  function agentPrefixRows(q) {
    var body = q.slice(1)
    var sp = body.indexOf(" ")
    var id = (sp < 0 ? body : body.slice(0, sp)).trim().toLowerCase()
    var prompt = sp < 0 ? "" : body.slice(sp + 1).trim()
    var i
    if (id) {
      var hit = null
      var prefix = []
      for (i = 0; i < root.availableAgents.length; i++) {
        var a = root.availableAgents[i]
        if (a.id === id) hit = a
        else if (a.id.indexOf(id) === 0) prefix.push(a)
      }
      if (!hit && prefix.length === 1) hit = prefix[0]
      if (hit) return [root.agentRow(hit, prompt)]
    }
    // No (or ambiguous) id → browse: default agent first, then the rest.
    var ids = []
    for (i = 0; i < root.availableAgents.length; i++) {
      var aid = root.availableAgents[i].id
      if (aid === root.defaultAgent) ids.unshift(aid)
      else ids.push(aid)
    }
    var out = []
    for (i = 0; i < ids.length; i++) out.push(root.agentRow(root.agentById(ids[i]), ""))
    return out
  }

  // One agent row: "Ask <name>" when it carries a prompt, "Open <name>" bare.
  function agentRow(a, prompt) {
    if (!a) return null
    var isDefault = a.id === root.defaultAgent
    return computedRow("agent",
      (prompt ? "Ask " : "Open ") + a.name,
      prompt ? "“" + prompt + "”" : (isDefault ? "default agent" : "agent"),
      { kind: "agent",
        mode: isDefault ? "default" : "agent",
        query: String(prompt || ""),
        agentId: a.id, agentName: a.name })
  }

  function agentById(id) {
    for (var i = 0; i < root.availableAgents.length; i++) {
      if (root.availableAgents[i].id === id) return root.availableAgents[i]
    }
    return null
  }

  function isInstalledAgent(id) {
    for (var i = 0; i < root.availableAgents.length; i++) {
      if (root.availableAgents[i].id === id) return true
    }
    return false
  }

  // Shorthand to shape a display-model row for a computed action: all the
  // command-only roles get safe defaults, payload carries the action data as
  // JSON (a string role — robust for ListModel's dynamic typing). The
  // optional appIcon hands provider rows a real image (window rows resolve
  // their app's icon; clipboard image rows carry the stored shot).
  function computedRow(kind, label, summary, payload, appIcon) {
    return {
      route: "", label: label, appIcon: appIcon || "", kind: kind,
      summary: summary,
      group: "", sudo: false, args: 0, recent: false, pinned: false,
      payload: JSON.stringify(payload)
    }
  }

  // Engine template (from detect-env.sh; %s = the URL-encoded query), with a
  // DuckDuckGo safety net if detection produced nothing usable.
  function webUrl(q) {
    var u = Agents.webSearchUrl(root.webTemplate, q)
    return u.length ? u : Agents.webSearchUrl("https://duckduckgo.com/?q=%s", q)
  }

  // Row glyph: computed kinds get a meaningful icon, apps their initial,
  // commands their group glyph (same as before). Codepoints verified against
  // the installed Nerd Font's glyph names: md-calculator, md-swap_horizontal,
  // fa-globe, md-robot.
  function rowGlyph(kind, group, label) {
    if (kind === "calc") return "󰃬"       // md-calculator
    if (kind === "convert") return "󰓡"    // md-swap_horizontal
    if (kind === "web") return ""         // fa-globe
    if (kind === "agent") return "󰚩"      // md-robot
    // Phase-7 provider rows: md-application, md-clipboard, md-file,
    // md-book (all verified against the installed Nerd Font's charset).
    if (kind === "window") return "󰖲"    // md-application
    if (kind === "clip") return "󰆇"       // md-clipboard
    if (kind === "file") return "󰈔"       // md-file
    if (kind === "dict") return "󰙊"       // md-book
    // Phase-5 control rows: toggles/panels/power resolve their icon from
    // the table by action id (rides the group role); status readouts carry
    // the glyph character itself in the group role.
    if (kind === "toggle" || kind === "panel" || kind === "power")
      return Controls.glyphFor(group)
    if (kind === "status") return group
    if (kind === "newsitem") return Controls.NEWS_GLYPHS.news
    if (kind === "newsrefresh") return Controls.NEWS_GLYPHS.refresh
    if (kind === "newsfeeds") return Controls.NEWS_GLYPHS.edit
    if (kind === "feedadd") return Controls.NEWS_GLYPHS.add
    if (kind === "app") return label.length ? label.charAt(0).toUpperCase() : "?"
    if (kind === "history" && group === "app")
      return label.length ? label.charAt(0).toUpperCase() : "?"
    return CmdModel.groupGlyph(group) || "󰒓"
  }

  // One-shot startup probe (detect-env.sh, read-only): installed agents, the
  // Omarchy default agent, and the default browser's search engine. Run via
  // login shell so the omarchy helpers and XDG vars are on PATH/env.
  readonly property string detectScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/detect-env.sh"
  Process {
    id: envProbeProc
    running: false
    command: ["bash", "-lc", "exec bash " + Util.shellQuote(root.detectScript)]
    stdout: StdioCollector { id: envProbeOut; waitForEnd: true }
    onExited: function(exitCode) { root._envProbed() }
  }
  function _envProbed() {
    var agents = []
    var seen = ({})
    var def = ""
    var wName = ""
    var wUrl = ""
    var lines = String(envProbeOut.text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      var key = lines[i].slice(0, eq)
      var val = lines[i].slice(eq + 1)
      if (key === "DEFAULT_AGENT") def = val.trim()
      else if (key === "AGENT" && val && !seen[val]) {
        seen[val] = true
        agents.push({ id: val, name: Agents.displayName(val), bin: val })
      } else if (key === "WEB_NAME") wName = val.trim()
      else if (key === "WEB_URL") wUrl = val.trim()
    }
    root.availableAgents = agents
    root.defaultAgent = def
    if (wName) root.webEngineName = wName
    if (wUrl.indexOf("%s") >= 0) root.webTemplate = wUrl
  }
  Component.onCompleted: {
    envProbeProc.running = true
    startupChoresTimer.start()
  }

  // Quiet startup chores, delayed so they never race the first open: the
  // catalog staleness gate (rebuild only when a source changed) and the
  // news cache (--max-age makes a fresh cache a zero-cost no-op).
  Timer {
    id: startupChoresTimer
    interval: 12000
    onTriggered: {
      Quickshell.execDetached(["bash", root.catalogScript, "--if-stale"])
      Quickshell.execDetached(["bash", root.newsScript, "--max-age", "1800"])
    }
  }

  // ------------------------------------------------------ system status probe
  // Read-only one-shot probe (status.sh): battery, volume/mic, CPU/mem, DND,
  // night light, Stay Awake, radios, and the session-action gates the menu
  // itself uses. Re-probed on open, on entering Controls, and after every
  // toggle — never on a timer (a launcher, not a dashboard).
  readonly property string statusScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/status.sh"
  Process {
    id: statusProc
    running: false
    command: ["bash", "-lc", "exec bash " + Util.shellQuote(root.statusScript)]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function() { root._applyStatus(String(statusOut.text || "")) }
  }

  // Live feed for the System & Network tile (8.4) — the user's explicit
  // direction that these metrics read and change while the palette is
  // open. Scoped like everything else in the charter: the palette's only
  // timer, ticking only while the home cards are up, skipped while a run
  // is in flight, dead the moment the palette closes. Identity fields
  // (IP/gateway) and the rest of the dashboard stay open-cycle only.
  readonly property string metricsScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/fonsgaudii.cmdcenter/metrics.sh"
  Process {
    id: metricsProc
    running: false
    command: ["bash", "-lc", "exec bash " + Util.shellQuote(root.metricsScript)]
    stdout: StdioCollector { id: metricsOut; waitForEnd: true }
    onExited: function() { root._applyMetrics(String(metricsOut.text || "")) }
  }

  // Tick merge: only the keys metrics.sh emits (CPU + traffic + link
  // health) over a COPY of statusInfo — the reassignment (never
  // in-place mutation) is what fires the sysGrid binding.
  function _applyMetrics(text) {
    var info = ({})
    for (var k in root.statusInfo) info[k] = root.statusInfo[k]
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      var key = lines[i].slice(0, eq)
      var val = lines[i].slice(eq + 1)
      if (key === "CPU") info.cpu = val
      else if (key === "NET_RXB") info.rxB = parseInt(val, 10) || 0
      else if (key === "NET_TXB") info.txB = parseInt(val, 10) || 0
      else if (key === "NET_RX_RATE") info.rxRate = parseInt(val, 10) || 0
      else if (key === "NET_TX_RATE") info.txRate = parseInt(val, 10) || 0
      else if (key === "NET_LOSS") info.loss = val
      else if (key === "NET_PING") info.ping = val
    }
    root.statusInfo = info
  }

  Timer {
    id: metricsTimer
    interval: 2000
    repeat: true
    running: root.homeVisible
    onTriggered: if (!metricsProc.running) metricsProc.running = true
  }

  function refreshStatus() {
    if (statusProc.running) return   // in-flight; its result still applies
    root.statusAt = Date.now()
    statusProc.running = true
    root.refreshWindows()            // same cadence; the list is one jq run
  }

  function _applyStatus(text) {
    var st = ({})
    var info = ({})
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      var key = lines[i].slice(0, eq)
      var val = lines[i].slice(eq + 1)
      if (key === "DND") st.dnd = val
      else if (key === "NIGHTLIGHT") st.nightlight = val
      else if (key === "STAYAWAKE") st.stayawake = val
      else if (key === "SCREENSAVER") st.screensaver = val
      else if (key === "WIFI") st.wifi = val
      else if (key === "BT") st.bluetooth = val
      else if (key === "WIFI_SSID") info.ssid = val
      else if (key === "WIFI_SIGNAL") info.signal = val
      else if (key === "CONNECTION") info.connection = val
      else if (key === "NET_IP") info.ip = val
      else if (key === "NET_GW") info.gateway = val
      else if (key === "NET_RXB") info.rxB = parseInt(val, 10) || 0
      else if (key === "NET_TXB") info.txB = parseInt(val, 10) || 0
      else if (key === "NET_RX_RATE") info.rxRate = parseInt(val, 10) || 0
      else if (key === "NET_TX_RATE") info.txRate = parseInt(val, 10) || 0
      else if (key === "NET_LOSS") info.loss = val
      else if (key === "NET_PING") info.ping = val
      else if (key === "BATTERY") info.battery = val
      else if (key === "VOLUME") info.volume = val
      else if (key === "VOLUME_PCT") info.volumePct = parseInt(val, 10) || 0
      else if (key === "OUTPUTMUTED") info.outputMuted = val === "true"
      else if (key === "INPUT_PCT") info.inputPct = parseInt(val, 10) || 0
      else if (key === "MICMUTED") info.micMuted = val === "true"
      else if (key === "CPU") info.cpu = val
      else if (key === "MEM") info.mem = val
      else if (key === "SUSPEND_OK") st.suspend = val === "true" ? "ok" : "hidden"
      else if (key === "HIBERNATE_OK") st.hibernate = val === "true" ? "ok" : "hidden"
    }
    root.controlStates = st
    root.statusInfo = info
    // Refresh the live view in place. Controls rows keep their position by
    // label; search rows don't reorder from state, so the index itself holds
    // (and the details shown in the card — ON/OFF, On·SSID — update too).
    if (root.rowsLoaded
        && (root.activeGroup === "__controls" || root.filterText)) {
      var inSearch = !!root.filterText
      var selIdx = root.selectedCommand
      var selLabel = ""
      if (!inSearch && root.selectedCommand >= 0
          && root.selectedCommand < displayModel.count)
        selLabel = String(displayModel.get(root.selectedCommand).label)
      root.rebuildDisplay()
      if (inSearch) {
        if (displayModel.count > 0)
          root.selectedCommand = Math.max(0, Math.min(selIdx, displayModel.count - 1))
      } else {
        for (var j = 0; j < displayModel.count; j++) {
          if (String(displayModel.get(j).label) === selLabel) {
            root.selectedCommand = j
            break
          }
        }
        cmdList.positionViewAtIndex(root.selectedCommand, ListView.Contain)
      }
    }
  }

  // ---------------------------------------------------------- controls rows
  // The Controls group: live status readouts first, then curated toggles,
  // settings panels, and power/session actions — the same commands the
  // built-in menu runs, with confirmation on anything destructive.
  function controlRows() {
    var rows = []
    var st = root.controlStates
    var info = root.statusInfo

    // ---- status readouts (Enter opens the related settings panel)
    if (info.battery) rows.push(root.statusRow("battery", "Battery", String(info.battery)))
    if (info.volume) rows.push(root.statusRow("volume", "Volume",
      String(info.volume) + (info.micMuted ? " · mic muted" : "")))
    if (info.cpu) rows.push(root.statusRow("system", "System",
      String(info.cpu) + " cpu" + (info.mem ? " · " + String(info.mem) + " mem" : "")))
    if (info.ssid || info.connection) rows.push(root.statusRow(
      info.ssid ? "wifi" : "connection", "Connection",
      String(info.ssid || info.connection)))

    // ---- curated actions (table order: toggles, panels, tools, session)
    for (var i = 0; i < Controls.ACTIONS.length; i++) {
      var a = Controls.ACTIONS[i]
      // Session actions the menu gates off (suspend disabled, no hibernate)
      // stay out of the list entirely, exactly like omarchy-menu.jsonc's `when`.
      if (a.kind === "power" && st[a.id] === "hidden") continue
      // Doc links (8.6 menu parity) are search-only: they'd pad the
      // browsed list without being controls.
      if (a.section === Controls.SECTION_LEARN) continue
      rows.push(root.actionRow(a))
    }
    return rows
  }

  // One curated action row — shared by the Controls group and search results.
  function actionRow(a) {
    var st = root.controlStates
    var summary = ""
    if (a.kind === "toggle") {
      summary = Controls.stateLabel(a.id, st, root.statusInfo.ssid) || "Toggle"
    } else if (a.kind === "panel") {
      summary = a.desc
    } else if (a.kind === "run") {
      summary = a.desc || "Runs immediately"
    } else {
      summary = a.confirm ? "Asks before running" : "Runs immediately"
    }
    var row = root.computedRow(a.kind, a.label, summary, {
      kind: a.kind, actionId: a.id, label: a.label,
      state: st[a.id] || "", confirm: !!a.confirm,
      panel: a.panel || "", desc: a.desc || "",
      confirmMsg: a.confirmMsg || "", body: a.body || ""
    })
    row.group = a.id   // rowGlyph resolves the icon from the id
    return row
  }

  // One live status readout row. group role carries the glyph character
  // (rowGlyph returns it verbatim for kind "status").
  function statusRow(key, label, value) {
    var panelId = key === "battery" ? "battery"
      : key === "volume" ? "audio"
      : key === "system" ? ""
      : "network"
    var row = root.computedRow("status", label, value, {
      kind: "status", label: label, panelId: panelId, value: value
    })
    row.group = Controls.STATUS_GLYPHS[key] || Controls.GROUP_GLYPHS.controls
    return row
  }

  // Curated action rows for a query: rank-matched from the same table and
  // seated right after the calculator/conversions, BEFORE command matches —
  // typing "reboot" must offer the confirmed reboot row first.
  function controlActionRows(query) {
    var hits = Controls.matchActions(query)
    var out = []
    for (var i = 0; i < hits.length; i++) {
      var a = hits[i]
      if (a.kind === "power" && root.controlStates[a.id] === "hidden") continue
      out.push(root.actionRow(a))
    }
    return out
  }

  // The History group: every persisted launch, newest first — the timeline
  // half of Phase 5. Enter re-runs apps / re-opens commands; the detail pane
  // offers per-entry Forget.
  function historyRows() {
    var entries = Controls.historyEntries(root.usage)
    var now = Date.now()
    var rows = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var rec = null
      if (e.route.indexOf("app:") === 0) rec = root.appById[e.route.slice(4)]
      else {
        for (var j = 0; j < root.catalog.length; j++) {
          if (root.catalog[j].route === e.route) { rec = root.catalog[j]; break }
        }
      }
      if (!rec) continue   // uninstalled app / removed command
      var ago = Controls.relativeTime(e.last, now)
      var row = root.computedRow("history",
        rec.isApp ? rec.name : rec.bare,
        e.count + "× · " + ago,
        { kind: "history", route: rec.route, isApp: !!rec.isApp,
          count: e.count, last: e.last, ago: ago })
      row.route = rec.route   // keep-restore + detailCmd resolution
      row.group = rec.isApp ? "app" : rec.group
      row.appIcon = rec.isApp ? rec.icon : ""
      row.pinned = root.isPinned(rec.route)
      row.recent = root.isRecent(rec.route)
      rows.push(row)
    }
    return rows
  }

  // ---------------------------------------------------------- display model
  function rebuildDisplay(preserveRoute) {
    // Keep the selected row across rebuilds: prefer the resolved record's
    // route, else the raw row's own route (history rows carry one even
    // though they aren't catalog records). Evaluated before clear().
    var keep = ""
    if (preserveRoute) {
      if (root.detailCmd && root.detailCmd.route) keep = root.detailCmd.route
      else if (root.detailRow && root.detailRow.route) keep = root.detailRow.route
    }
    displayModel.clear()

    if (!root.rowsLoaded) {
      root.displaySerial++
      root.selectedCommand = 0
      return
    }

    var list = null
    var prerows = null
    if (root.filterText) {
      if (String(root.filterText).trim().charAt(0) === "@") {
        // "@" = agent mode: only agent rows apply, so commands/apps stand
        // down and Enter can never launch something that merely fuzzy-matched.
        list = []
      } else {
        // Commands first, then matching apps — mirrors the built-in menu's
        // ranking where apps sit just below exact command matches.
        var cmdHits = CmdModel.search(root.catalog, root.filterText, root.usage, Date.now())
        var appHits = CmdModel.search(root.apps, root.filterText)
        list = cmdHits.concat(appHits)
      }
    } else if (root.activeGroup === "__controls") {
      // Pre-built rows: live status readouts + curated actions.
      prerows = root.controlRows()
    } else if (root.activeGroup === "__history") {
      // Pre-built rows: the launch timeline.
      prerows = root.historyRows()
    } else if (root.activeGroup === "__news") {
      // Pre-built rows: refresh + the latest stories. Entering the group
      // also nudges a quiet background fetch when the cache is old.
      prerows = root.newsRows()
      root.maybeNewsRefresh()
    } else if (root.activeGroup === "__pins") {
      // Pinned favorites first — commands and apps, in pin order.
      list = root.pinnedRecords()
    } else if (root.activeGroup === "__apps") {
      list = root.apps
    } else {
      list = CmdModel.commandsInGroup(root.catalog, root.activeGroup)
    }

    if (prerows) {
      for (var pi = 0; pi < prerows.length; pi++) displayModel.append(prerows[pi])
    } else {
      var cap = root.filterText ? 150 : list.length
      var n = Math.min(list.length, cap)

      // Universal-search providers: computed results (calculator / unit
      // conversion) lead, then curated quick actions (Phase 5), then
      // window-switch rows (Phase 7), then the matches, with fallback
      // actions (web search, ask-an-agent, prefix providers) trailing —
      // all only while a query is typed, never while browsing groups.
      var computed = root.filterText ? root.computedRows(root.filterText) : []
      var actions = root.filterText ? root.controlActionRows(root.filterText) : []
      var windows = root.filterText ? root.windowRows(root.filterText) : []
      var fallback = root.filterText ? root.fallbackRows(root.filterText) : []
      // Pasted URL → the inline feed-add row leads everything: the only
      // unambiguous reading of a full URL as a query.
      if (root.filterText && root.isFeedUrlQuery(root.filterText))
        displayModel.append(root.addFeedRow(root.filterText))
      for (var ci = 0; ci < computed.length; ci++) displayModel.append(computed[ci])
      for (var ai = 0; ai < actions.length; ai++) displayModel.append(actions[ai])
      // Window-switch rows lead the catalog: jumping to a live window is
      // the most time-sensitive match a typed query can make.
      for (var wi = 0; wi < windows.length; wi++) displayModel.append(windows[wi])

      for (var i = 0; i < n; i++) {
        var c = list[i]
        displayModel.append({
          route: c.route,
          label: c.isApp ? c.name : c.bare,
          appIcon: c.isApp ? c.icon : "",
          kind: c.isApp ? "app" : "cmd",
          summary: c.summary, group: c.group,
          sudo: c.requiresSudo, args: c.argCount,
          recent: root.recentRoutes.indexOf(c.route) >= 0,
          pinned: root.isPinned(c.route),
          payload: ""
        })
      }

      for (var fi = 0; fi < fallback.length; fi++) displayModel.append(fallback[fi])
    }

    root.displaySerial++
    root.selectedCommand = 0
    if (keep) {
      for (var j = 0; j < displayModel.count; j++) {
        if (displayModel.get(j).route === keep) { root.selectedCommand = j; break }
      }
    }
    cmdList.positionViewAtIndex(root.selectedCommand, ListView.Contain)
  }

  function isRecent(route) { return root.recentRoutes.indexOf(route) >= 0 }

  // Most-recently-launched first, from the persisted history — so recents
  // survive shell restarts instead of resetting every session. Entries
  // untouched for 30 days drop off the strip (the automatic half of the
  // hybrid recents design; update-usage.sh sweeps them from disk at 90).
  function recentRoutesFromUsage() {
    var cutoff = Date.now() - 30 * 86400000
    var entries = []
    for (var r in root.usage) {
      var u = root.usage[r]
      var last = u ? Number(u.last) || 0 : 0
      if (u && Number(u.count) > 0 && last >= cutoff) entries.push({ route: r, last: last })
    }
    entries.sort(function(a, b) { return b.last - a.last })
    var out = []
    for (var i = 0; i < entries.length && out.length < 20; i++) out.push(entries[i].route)
    return out
  }

  // ---------------------------------------------------------- recent strip
  // Rebuild the top quick-launch row from usage: most-recent-first, mixing
  // apps and commands, capped at 8. Stale routes (an uninstalled app, a
  // removed command) resolve to null and are skipped silently.
  function rebuildRecents() {
    // The strip is part of the pinned home block: a rebuild (new launch,
    // usage reload) must not yank the scroll position back to the start.
    var keepX = recentList.contentX
    recentModel.clear()
    if (!root.rowsLoaded) return
    var routes = root.recentRoutesFromUsage()
    for (var i = 0; i < routes.length && recentModel.count < 8; i++) {
      var r = routes[i]
      var rec = null
      if (r.indexOf("app:") === 0) rec = root.appById[r.slice(4)]
      else {
        for (var j = 0; j < root.catalog.length; j++) {
          if (root.catalog[j].route === r) { rec = root.catalog[j]; break }
        }
      }
      if (!rec) continue
      recentModel.append({
        route: rec.route,
        label: rec.isApp ? rec.name : rec.bare,
        appIcon: rec.isApp ? rec.icon : "",
        kind: rec.isApp ? "app" : "cmd",
        group: rec.isApp ? "app" : rec.group
      })
    }
    // Restore the position, clamped once the count shrinks below it.
    recentList.contentX = Math.min(keepX, Math.max(0,
      recentList.contentWidth - recentList.width))
  }

  // Click a recent tile: apps launch straight away; commands jump to the
  // All-commands list with the row selected in the detail pane (they may
  // take arguments, so a bare click shouldn't execute them).
  function activateRecent(index) {
    var row = recentModel.get(index)
    if (!row) return
    if (row.kind === "app") {
      var app = root.appById[String(row.route).slice(4)]
      if (app) root.launchAppRecord(app)
      return
    }
    root.selectRoute(row.route)
  }

  // Bring any command route into view: switch to All commands, rebuild,
  // then select and scroll to its row.
  function selectRoute(route) {
    root.filterText = ""
    searchField.text = ""
    root.activeGroup = "*"
    root.syncGroupSelection()
    root.rebuildDisplay()
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).route === route) {
        root.selectedCommand = i
        root.focusPane = 2
        cmdList.positionViewAtIndex(i, ListView.Contain)
        break
      }
    }
    searchField.forceActiveFocus()
  }

  // ---------------------------------------------------------- pins
  function isPinned(route) { return root.pins.indexOf(route) >= 0 }

  // Pinned records in pin order; commands resolve from the catalog, apps
  // from the app map (app routes are "app:<id>"). Stale pins — an app that
  // was uninstalled — are skipped silently.
  function pinnedRecords() {
    var out = []
    for (var i = 0; i < root.pins.length; i++) {
      var r = root.pins[i]
      if (r.indexOf("app:") === 0) {
        var app = root.appById[r.slice(4)]
        if (app) out.push(app)
        continue
      }
      for (var j = 0; j < root.catalog.length; j++) {
        if (root.catalog[j].route === r) { out.push(root.catalog[j]); break }
      }
    }
    return out
  }

  function updatePinsGroupCount() {
    for (var i = 0; i < groupListModel.count; i++) {
      if (groupListModel.get(i).name === "__pins") {
        groupListModel.setProperty(i, "count", root.pins.length)
        return
      }
    }
  }

  function updateHistoryGroupCount() {
    var n = Controls.historyEntries(root.usage).length
    for (var i = 0; i < groupListModel.count; i++) {
      if (groupListModel.get(i).name === "__history") {
        groupListModel.setProperty(i, "count", n)
        return
      }
    }
  }

  // String-returning state probe for IPC debugging (arrays/objects come
  // back as "unknown" through `shell call`, strings survive).
  function debugPins() {
    var top = []
    for (var i = 0; i < Math.min(6, displayModel.count); i++) {
      var r = displayModel.get(i)
      top.push(r.kind + ":" + r.label)
    }
    var recents = []
    for (var j = 0; j < recentModel.count; j++) recents.push(recentModel.get(j).route)
    return JSON.stringify({
      opened: root.opened,
      rows: displayModel.count,
      top: top,
      recents: recents,
      detailRoute: root.detailCmd ? root.detailCmd.route : null,
      pins: root.pins,
      pinsScript: root.pinsScript
    })
  }

  // IPC probe for the universal-search providers: environment detection
  // (default agent, web engine) plus whether calc/conversion/fallback/agent
  // rows fire on demand — including the "@" prefix surface.
  function debugProviders() {
    function labels(rows) {
      return rows.map(function(r) { return r.kind + ":" + r.label })
    }
    return JSON.stringify({
      defaultAgent: root.defaultAgent,
      agents: root.availableAgents.map(function(a) { return a.id }),
      engine: root.webEngineName,
      template: root.webTemplate,
      webUrl: root.webUrl("hello world"),
      calc2p2: labels(root.computedRows("2+2")),
      sqrt144: labels(root.computedRows("sqrt(144)")),
      km2mi: labels(root.computedRows("5 km to mi")),
      notMath: labels(root.computedRows("theme set")),
      fallback: labels(root.fallbackRows("hello world")),
      atBrowse: labels(root.fallbackRows("@")),
      atCodex: labels(root.fallbackRows("@codex fix the tests")),
      atOpen: labels(root.fallbackRows("@claude")),
      atUnknown: labels(root.fallbackRows("@nope"))
    })
  }

  // IPC probe for Phase 5 (Deep Omarchy): probed live state, the Controls
  // and History row inventories, and what representative queries match.
  // query: optional — probes the inline feed-add row for a URL query.
  function debugControls(query) {
    function labels(rows) {
      // "*" marks a row carrying a real image (app/window icon or shot).
      return rows.map(function(r) {
        return r.kind + ":" + r.label + (r.appIcon ? "*" : "")
      })
    }
    var hist = root.historyRows()
    return JSON.stringify({
      states: root.controlStates,
      info: root.statusInfo,
      statusAt: root.statusAt,
      controls: labels(root.controlRows()),
      historyCount: hist.length,
      historyTop: labels(hist).slice(0, 5),
      qWifi: labels(root.controlActionRows("wifi")),
      qReboot: labels(root.controlActionRows("reboot")),
      qSleep: labels(root.controlActionRows("sleep")),
      qDnd: labels(root.controlActionRows("dnd")),
      // Footer rail (Phase 5+): tile ids ("*" = popover tiles) and the
      // power popover's gated row inventory ("?" = confirm-gated).
      footer: root.footerTiles.map(function(t) {
        return t.id + (t.popover ? "*" : "")
      }),
      footerGlyphs: root.footerTiles.map(function(t) {
        return t.glyph ? t.glyph.codePointAt(0).toString(16) : "none"
      }),
      powerPopover: Controls.powerPopoverRows(root.controlStates).map(function(r) {
        return r.id + (r.confirm ? "?" : "")
      }),
      // Phase-7.3 idle section: live timeouts (shell.json idle block via
      // shellConfigFile) + the Stay Awake switch state.
      idle: {
        screensaver: root.idleScreensaver,
        lock: root.idleLock,
        awake: root.controlStates["stayawake"] || "off"
      },
      news: {
        feeds: root.newsFeeds.length,
        items: root.newsItems.length,
        fetchedAt: root.newsAt,
        errors: root.newsErrors,
        withLogo: root.newsFeeds.filter(function(f) { return f.logo }).length,
        heroes: root.newsItems.filter(function(i) { return i.image }).length,
        excerpt: root.newsItems.length
          ? String(root.newsItems[0].excerpt || "").slice(0, 40) : "",
        top: root.newsItems.slice(0, 3).map(function(i) {
          return i.source + ":" + String(i.title).slice(0, 28)
        })
      },
      // Inline feed-add row for an arbitrary URL query ("" or non-URL → "").
      feedAdd: query && root.isFeedUrlQuery(query)
        ? (function() { var r = root.addFeedRow(query); return r.kind + ":" + r.label })()
        : "",
      // Phase-7 provider rows for an arbitrary query: prefix queries ("
      // clipboard, / files, ? dictionary) route to their provider,
      // everything else gets the automatic window rows.
      qProvider: query
        ? (SearchP.prefixOf(query)
            ? labels(root.prefixProviderRows(query))
            : labels(root.windowRows(query)))
        : [],
      // Phase-7 providers: window list, clipboard history, file/dict state.
      // mediaGhost: the 7.2 last-media snapshot the ghost tile renders.
      providers: {
        wins: root.winList.length,
        winTop: root.winList.slice(0, 3).map(function(w) { return w.class }),
        clip: root.clipHistory.length,
        fileQuery: root.fileQuery,
        fileHits: root.fileResults.length,
        fileExit: root.fileProcExit,
        fileRunning: fileSearchProc.running,
        dictWord: root.dictWord,
        dictDef: root.dictResult && root.dictResult.definition
          ? String(root.dictResult.definition).slice(0, 40) : "",
        mediaGhost: root.ghostHasMedia,
        mediaGhostTitle: root.ghostHasMedia
          ? String(root.ghostMedia.title).slice(0, 24) : ""
      },
      home: {
        visible: root.homeVisible,
        weather: root.homeWeather.raw
          ? root.homeWeather.city + "|" + root.homeWeather.temp : "(pending)",
        cond: root.homeWeatherDetail.condition || "",
        country: root.homeWeatherDetail.country || "",
        clock: Dashboard.fmtClock(root.homeDate),
        weatherIcon: root.weatherIcon
          ? root.weatherIcon.codePointAt(0).toString(16) : "none",
        cpu: root.statusInfo.cpu || "",
        mem: root.statusInfo.mem || "",
        day: root.homeDay.weekday + "|" + root.homeDay.date + "|" + root.homeDay.week,
        player: root.nowPlaying
          ? String(root.nowPlaying.desktopEntry || root.nowPlaying.identity || "") : "",
        bus: root.nowPlaying ? String(root.nowPlaying.dbusName || "") : "",
        playing: root.nowPlaying ? String(root.nowPlaying.trackTitle || "") : "",
        artist: root.nowPlaying ? String(root.nowPlaying.trackArtist || "") : "",
        isPlaying: root.nowPlaying ? !!root.nowPlaying.isPlaying : false,
        art: root.mediaArt ? root.mediaArt.replace("file://", "").split("?")[0] : "",
        artUrl: root.nowPlaying ? String(root.nowPlaying.trackArtUrl || "") : "",
        logo: root.mediaLogo ? root.mediaLogo.replace("file://", "") : "",
        frac: Math.round(root.mediaFrac * 100),
        posUs: root.mediaPosUs,
        lenUs: root.mediaLenUs,
        elapsed: root.mediaElapsed,
        total: root.mediaTotal
      }
    })
  }

  function togglePin() {
    var cmd = root.detailCmd
    if (!cmd) return JSON.stringify({ error: "no selection" })
    var route = cmd.route
    var wasPinned = root.isPinned(route)
    var next = []
    if (!wasPinned) next.push(route)   // most recently pinned lands on top
    for (var i = 0; i < root.pins.length; i++) {
      if (root.pins[i] !== route) next.push(root.pins[i])
    }
    root.pins = next
    Util.execDetached("bash " + Util.shellQuote(root.pinsScript) + " " + Util.shellQuote(route))
    var name = cmd.isApp ? cmd.name : cmd.bare
    root.osd(wasPinned ? "☆" : "★", (wasPinned ? "Unpinned " : "Pinned ") + name)
    root.updatePinsGroupCount()
    root.rebuildDisplay(true)
    return JSON.stringify({ route: route, wasPinned: wasPinned, pins: root.pins })
  }

  // ---------------------------------------------------------- lazy help
  function requestHelp() {
    root.helpText = ""
    root.helpLoading = false
    var cmd = root.detailCmd
    if (!cmd || cmd.isApp) return
    if (root.helpCache[cmd.route] !== undefined) {
      root.helpText = root.helpCache[cmd.route]
      return
    }
    root.helpLoading = true
    helpTimer.restart()
  }

  function fetchHelp() {
    var cmd = root.detailCmd
    if (!cmd || cmd.isApp) { root.helpLoading = false; return }
    if (helpProc.running) return   // in-flight; onExited re-arms the timer
    // Routes come from the trusted catalog (dispatcher metadata, safe
    // charset) — sanitized anyway before they touch a shell string.
    var safe = String(cmd.route).replace(/[^A-Za-z0-9 _-]/g, "")
    if (!safe) { root.helpLoading = false; return }
    root.helpRoute = cmd.route
    helpProc.command = ["bash", "-lc", "exec " + safe + " --help"]
    helpProc.running = true
  }

  function noteLaunch(route) {
    var next = [route]
    for (var i = 0; i < root.recentRoutes.length && next.length < 20; i++) {
      if (root.recentRoutes[i] !== route) next.push(root.recentRoutes[i])
    }
    root.recentRoutes = next
    // Update the in-memory map for immediate ranking feedback and persist
    // the increment for next time (flock-serialized in the helper).
    var usageCopy = ({})
    for (var k in root.usage) usageCopy[k] = root.usage[k]
    var prev = usageCopy[route] || ({ count: 0, last: 0 })
    usageCopy[route] = { count: (Number(prev.count) || 0) + 1, last: Date.now() }
    root.usage = usageCopy
    Util.execDetached("bash " + Util.shellQuote(root.usageScript) + " " + Util.shellQuote(route))
    root.updateHistoryGroupCount()
    root.rebuildDisplay(true)
  }

  // Forget a route entirely — the manual half of the hybrid recents design:
  // drops it from the strip, from frecency ranking, and (through
  // update-usage.sh forget, flock-serialized) from the persisted history.
  function forgetRoute(route) {
    if (!route) return
    var usageCopy = ({})
    for (var k in root.usage) {
      if (k !== route) usageCopy[k] = root.usage[k]
    }
    root.usage = usageCopy
    var next = []
    for (var i = 0; i < root.recentRoutes.length; i++) {
      if (root.recentRoutes[i] !== route) next.push(root.recentRoutes[i])
    }
    root.recentRoutes = next
    Util.execDetached("bash " + Util.shellQuote(root.usageScript) + " forget " + Util.shellQuote(route))
    root.updateHistoryGroupCount()
  }

  // Hover-✕ on a recent tile: forget it in place, no confirmation — it's
  // history, not a destructive action. The row vanishes immediately.
  function forgetRecent(index) {
    index = Number(index)
    var row = recentModel.get(index)
    if (!row) return
    // Capture the route BEFORE remove(): ListModel.get() returns a live view,
    // and remove(index) invalidates it — row.route would read undefined and
    // forgetRoute would silently no-op (found by tracing the call sequence).
    var route = row.route
    recentModel.remove(index)
    root.forgetRoute(route)
    root.osd("⌫", "Removed from recents")
  }

  // ---------------------------------------------------------- navigation
  function selectGroup(index) {
    if (index < 0 || index >= groupListModel.count) return
    root.selectedGroupIndex = index
    var name = groupListModel.get(index).name
    if (root.filterText) searchField.text = ""
    root.activeGroup = name
    root.rebuildDisplay()
    // Entering Controls re-probes live state (throttled — arrowing back and
    // forth must not spawn probe storms).
    if (name === "__controls" && Date.now() - root.statusAt > 4000) root.refreshStatus()
  }

  function moveSelection(dir) {
    if (root.focusPane === 0) {
      var g = Math.max(0, Math.min(groupListModel.count - 1, root.selectedGroupIndex + dir))
      if (g !== root.selectedGroupIndex) {
        root.selectGroup(g)
        groupList.positionViewAtIndex(g, ListView.Contain)
      }
    } else if (root.focusPane === 1) {
      if (displayModel.count === 0) return
      root.selectedCommand = Math.max(0, Math.min(displayModel.count - 1, root.selectedCommand + dir))
      cmdList.positionViewAtIndex(root.selectedCommand, ListView.Contain)
    } else {
      root.actionIndex = Math.max(0, Math.min(2, root.actionIndex + dir))
    }
  }

  function enterPressed() {
    if (root.confirmOpen) return
    if (root.focusPane === 0) {
      root.focusPane = 1
    } else if (root.focusPane === 1) {
      if (displayModel.count === 0) return
      // Computed + control rows act immediately — Enter on a calculator
      // answer copies it, Enter on web/agent/toggle/power/history runs the
      // action (power still passes through its confirmation dialog first).
      var sel = displayModel.get(root.selectedCommand)
      var k = sel ? sel.kind : ""
      if (Controls.isInstantKind(k)) {
        root.activateComputed()
        return
      }
      root.focusPane = 2
      root.actionIndex = 0
    } else {
      root.activate(["auto", "terminal", "copy"][root.actionIndex])
    }
  }

  // ---------------------------------------------------------- execution
  function currentCommandLine() {
    var t = cmdLine.text.trim()
    return t.length ? t : (root.detailCmd ? root.detailCmd.route : "")
  }

  function copyCommandLine(cmdline) {
    Util.execDetached("printf '%s' " + Util.shellQuote(cmdline) + " | wl-copy")
    root.osd("⧉", "Command copied")
  }

  // Form control changes re-assemble the editable command line live; hand
  // edits made in the field stay authoritative until the next form change.
  function setFormValue(index, value) {
    var next = root.formValues.slice()
    next[index] = value
    root.formValues = next
    if (root.detailCmd) cmdLine.text = CmdModel.assembleCommandLine(root.detailCmd, next)
  }

  function openTerminal(cmdline) {
    Util.execDetached("xdg-terminal-exec bash -lc " + Util.shellQuote(cmdline + "; exec bash"))
  }

  // Start-menu behavior: launching an app closes the palette. This is the
  // same entry point AppLibrary.launch uses (uwsm-app + gtk-launch, so the
  // app lands in app-graphical.slice rather than the shell's cgroup).
  function launchAppRecord(rec) {
    if (!rec || !rec.isApp) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(rec.id + ".desktop"))
    root.osd("󰀻", "Launching " + rec.name + "…")
    root.noteLaunch(rec.route)
    root.cancel()
  }

  function launchApp() { root.launchAppRecord(root.detailCmd) }

  // ---------------------------------------------------------- computed actions
  // Clipboard write for computed results — same mechanism as copyCommandLine.
  function copyText(text, message) {
    Util.execDetached("printf '%s' " + Util.shellQuote(text) + " | wl-copy")
    root.osd("⧉", message || "Copied")
  }

  // Hand a query to an agent in a terminal — three modes:
  //   "default" → `omarchy agent prompt …`, Omarchy's canonical path (its own
  //     per-agent flags, work dir, omarchy-launch-tui); bare `omarchy agent`
  //     when there's no prompt to seed.
  //   "pick"    → no default set yet: open Omarchy's agent picker.
  //   "agent"   → any other installed agent, argv from Agents.js (mirrors
  //     omarchy-agent's table), each element shell-quoted, through
  //     omarchy-launch-tui with the shared org.omarchy.agent app-id.
  // The conditional cd-to-Work mirrors omarchy-agent so agents don't re-ask
  // trust for $HOME on every launch.
  function openAgent(p) {
    if (!p) return
    if (p.mode === "pick") {
      Util.execDetached("bash -lc " + Util.shellQuote("exec " + Agents.pickDefaultAgentCommand()))
      root.osd("󰚩", "Choose a default agent…")
      root.cancel()
      return
    }
    var cmd
    if (p.mode === "default") cmd = p.query ? Agents.defaultAgentCommand(p.query) : "omarchy agent"
    else cmd = Agents.agentCommand(p.agentId, p.query)
    if (!cmd) return
    var inner = "[[ $PWD == $HOME && -d $HOME/Work ]] && cd $HOME/Work; exec " + cmd
    Util.execDetached("bash -lc " + Util.shellQuote(inner))
    root.osd("󰚩", (p.query ? "Asking " : "Opening ") + (p.agentName || "agent") + "…")
    root.cancel()
  }

  // The exact shell command an agent row would run — used for Ctrl+C copy
  // and kept in one place with openAgent so they can't drift apart.
  function agentCommandFor(p) {
    if (!p) return ""
    if (p.mode === "pick") return Agents.pickDefaultAgentCommand()
    if (p.mode === "default") return p.query ? Agents.defaultAgentCommand(p.query) : "omarchy agent"
    return Agents.agentCommand(p.agentId, p.query) || ""
  }

  // Route the selected computed row. Action semantics: a calculator answer
  // and a conversion always copy; a web row copies its URL on "copy" and
  // otherwise opens the browser; an agent row opens the terminal (copying the
  // launch command on "copy"); Phase-5 control rows hand off to
  // activateControl, history rows to activateHistoryRow.
  function activateComputed(action) {
    var p = root.detailPayload
    if (!p) return
    if (p.kind === "calc" || p.kind === "convert") {
      root.copyText(p.result, "Copied " + p.result)
      return
    }
    if (p.kind === "web") {
      if (action === "copy") { root.copyText(p.url, "Search URL copied"); return }
      Qt.openUrlExternally(p.url)
      root.cancel()
      return
    }
    // Phase-7 providers: window → focus and get out of the way; clipboard
    // → omarchy's paste helper (copy + type); file → open / cd / copy
    // path; dictionary → the definition is the answer, so it copies.
    if (p.kind === "window") {
      if (action === "copy") {
        root.copyText(String(p.title || p.class || ""), "Window title copied")
        return
      }
      Quickshell.execDetached(["bash", root.winCtlScript, "focus", String(p.addr || "")])
      root.cancel()
      return
    }
    if (p.kind === "clip") {
      if (action === "copy") {
        if (p.type === "image") root.copyText(String(p.path || ""), "Image path copied")
        else root.copyText(String(p.text || ""), "Copied to clipboard")
        return
      }
      if (p.type === "image") {
        Quickshell.execDetached([root.clipPasteFile, String(p.mime || "image/png"),
          String(p.path || "")])
      } else {
        Quickshell.execDetached([root.clipPasteText, "--history-index",
          String(Number(p.index) || 0)])
      }
      root.cancel()
      return
    }
    if (p.kind === "file") {
      if (action === "copy") { root.copyText(String(p.path || ""), "Path copied"); return }
      if (action === "terminal") {
        root.openTerminal("cd " + Util.shellQuote(SearchP.dirOf(String(p.path || ""))))
        root.cancel()
        return
      }
      Quickshell.execDetached(["xdg-open", String(p.path || "")])
      root.cancel()
      return
    }
    if (p.kind === "dict") {
      root.copyText(String(p.definition || ""), "Definition copied")
      return
    }
    if (p.kind === "newsitem") {
      if (action === "copy") { root.copyText(p.url, "Link copied"); return }
      Qt.openUrlExternally(String(p.url))
      root.cancel()
      return
    }
    if (p.kind === "newsrefresh") {
      root.fetchNews()
      return
    }
    if (p.kind === "newsfeeds") {
      if (action === "copy") {
        root.copyText(root.stateDir + "/feeds.json", "Feeds file path copied")
        return
      }
      // User-owned file in the user's own editor — the same shell-string
      // shape openTerminal already uses for agents ($EDITOR is the
      // user's environment; the path is our fixed state file, quoted).
      root.openTerminal("${EDITOR:-nano} " + Util.shellQuote(root.stateDir + "/feeds.json"))
      root.cancel()
      return
    }
    if (p.kind === "feedadd") {
      if (action === "copy") { root.copyText(p.url, "Feed URL copied"); return }
      root.addFeed(String(p.url))
      return
    }
    if (p.kind === "agent") {
      if (action === "copy") {
        var c = root.agentCommandFor(p)
        if (c) root.copyText(c, "Copied launch command")
        return
      }
      root.openAgent(p)
      return
    }
    if (p.kind === "toggle" || p.kind === "panel" || p.kind === "power"
        || p.kind === "status" || p.kind === "run") {
      root.activateControl(p, action)
      return
    }
    if (p.kind === "history") root.activateHistoryRow(p)
  }

  // ------------------------------------------------------ controls actions
  // Toggle / panel / power / status rows (Phase 5). "copy" yields the exact
  // command text; everything that RUNS goes through argv arrays — no shell
  // string is ever built from a runtime value (injection surface: none).
  // Power actions that confirm (everything but Lock) stop at the shared
  // dialog; Ctrl+T ("terminal") cannot bypass it.
  function activateControl(p, action) {
    if (!p) return
    var a = Controls.actionById(String(p.actionId || ""))
    if (p.kind === "toggle") {
      if (!a) return
      var tc = Controls.toggleCommand(a, root.controlStates)
      if (action === "copy") { root.copyText(tc, "Copied toggle command"); return }
      if (action === "terminal") { root.openTerminal(tc); return }
      root.runToggle(a)
      return
    }
    if (p.kind === "panel" || p.kind === "status") {
      var panelId = p.kind === "panel" ? (a ? a.panel : "") : String(p.panelId || "")
      if (!panelId) {
        // System readout with no settings page: Enter is a no-op; copy
        // still lifts the stats line.
        if (action === "copy" && p.value) root.copyText(String(p.value), "Copied stats")
        return
      }
      var pc = "omarchy-shell shell toggle " + panelId
      if (action === "copy") { root.copyText(pc, "Copied command"); return }
      if (action === "terminal") { root.openTerminal(pc); return }
      root.openPanel(panelId,
        p.kind === "panel" && a ? a.label : String(p.label || "settings"),
        a ? a.glyph : "")
      return
    }
    if (p.kind === "run") {
      if (!a) return
      if (action === "copy") { root.copyText(a.cmd, "Copied command"); return }
      if (action === "terminal") { root.openTerminal(a.cmd); return }
      // Static, omarchy-authored command strings (8.6 Super+Space parity,
      // byte-matched to omarchy-menu.jsonc by tests/parity.test.js). Same
      // bash -lc path the menu itself uses (Util.execDetached) — no runtime
      // value ever enters the string, so there is no injection surface.
      Util.execDetached(a.cmd)
      root.osd(a.glyph, a.label + "…")
      root.cancel()
      return
    }
    if (p.kind === "power") {
      if (!a) return
      if (action === "copy") { root.copyText(a.cmd, "Copied command"); return }
      if (a.confirm) {
        root.pendingPower = {
          id: a.id, label: a.label, cmdline: a.cmd,
          message: a.confirmMsg || (a.label + " now?"),
          confirmText: a.label + "…"
        }
        root.confirmOpen = true
        return
      }
      if (action === "terminal") { root.openTerminal(a.cmd); return }
      root.runPower(a)
    }
  }

  // Flip a quick toggle: argv (no shell), optimistic OSD copy, then re-probe
  // so the row's On/Off label reflects reality a moment later.
  function runToggle(a) {
    var argv = Controls.toggleArgv(a, root.controlStates)
    if (!argv.length) return
    Quickshell.execDetached(argv)
    var after = Controls.nextState(a.id, root.controlStates)
    root.osd(a.glyph, after ? a.label + " " + after : a.label + " toggled")
    root.refreshStatus()
  }

  // Open a shell settings panel (audio/network/display/battery) and step
  // aside — the same toggle entry the keybindings use.
  function openPanel(id, label, glyph) {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", String(id)])
    root.osd(glyph || Controls.GROUP_GLYPHS.controls, "Opening " + label + "…")
    root.cancel()
  }

  // Session actions run detached via argv; the palette steps aside so lock /
  // logout / power-off land on a clean slate. Confirmation (when due) has
  // already happened before this is ever called.
  function runPower(a) {
    var argv = Controls.powerArgv(a)
    if (!argv.length) return
    Quickshell.execDetached(argv)
    root.osd(a.glyph, a.label + "…")
    root.cancel()
  }

  // ---------------------------------------------- footer rail actions
  // Tile click: single-control tiles reuse the exact same action-table
  // paths as the Controls group (toggles flip + keep the palette open,
  // panels step aside); multi-control tiles (audio/power) toggle their
  // anchored popover instead — the "toggle vs dialog" split.
  function activateFooterTile(t, item) {
    if (!t) return
    if (t.popover) {
      if (root.openPopover === String(t.id)) root.openPopover = ""
      else {
        root.popoverAnchor = item
        root.openPopover = String(t.id)
      }
      return
    }
    var a = Controls.actionById(String(t.actionId || ""))
    if (!a) return
    if (a.kind === "toggle") { root.runToggle(a); return }
    if (a.kind === "panel") root.openPanel(a.panel, a.label, a.glyph)
  }

  // Power-popover row: panel → open it; confirm-gated session action →
  // the shared dialog (the popover steps aside first); Lock runs now.
  function activatePowerRow(row) {
    root.openPopover = ""
    if (!row) return
    var a = Controls.actionById(String(row.id || ""))
    if (!a) return
    if (row.kind === "panel") { root.openPanel(a.panel, a.label, a.glyph); return }
    if (a.confirm) {
      root.pendingPower = {
        id: a.id, label: a.label, cmdline: a.cmd,
        message: a.confirmMsg || (a.label + " now?"),
        confirmText: a.label + "…"
      }
      root.confirmOpen = true
      return
    }
    root.runPower(a)
  }

  // Audio-popover mute + volume: argv only (no shell parses them), OSD
  // mirrors the change optimistically, the re-probe confirms it a beat
  // later — the same rhythm as the toggle rows.
  function toggleAudioMute(channel) {
    var argv = Controls.muteToggleArgv(channel)
    if (!argv.length) return
    Quickshell.execDetached(argv)
    var out = channel === "output"
    var muted = out ? root.statusInfo.outputMuted : root.statusInfo.micMuted
    root.osd(out ? Controls.FOOTER_GLYPHS.volume : Controls.FOOTER_GLYPHS.mic,
      (out ? "Output " : "Mic ") + (muted ? "unmuted" : "muted"))
    root.refreshStatus()
  }

  function setAudioVolume(channel, pct) {
    var argv = Controls.setVolumeArgv(channel, pct)
    if (!argv.length) return
    Quickshell.execDetached(argv)
    var out = channel === "output"
    root.osd(out ? Controls.FOOTER_GLYPHS.volume : Controls.FOOTER_GLYPHS.mic,
      (out ? "Output " : "Input ") + Math.round(pct) + "%")
    root.refreshStatus()
  }

  // ------------------------------------------------- idle timeouts (7.3)
  // Screensaver/lock delays from shell.json's idle block, live (the shell
  // FileViews the same file and re-applies on change; ours watches too).
  // "Off" is 86400 s — Omarchy's idle service has no true "never" (0
  // would fire immediately), the Stay Awake switch is the real off.
  property int idleScreensaver: 150
  property int idleLock: 300
  readonly property var idleChips: [
    { label: "Off", secs: 86400 }, { label: "1", secs: 60 },
    { label: "2", secs: 120 }, { label: "5", secs: 300 },
    { label: "10", secs: 600 }, { label: "15", secs: 900 },
    { label: "30", secs: 1800 }, { label: "60", secs: 3600 }
  ]

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var cfg = null
      try { cfg = JSON.parse(text() || "null") } catch (e) { cfg = null }
      var idle = cfg && cfg.idle ? cfg.idle : ({})
      var ss = Number(idle.screensaver)
      var lk = Number(idle.lock)
      root.idleScreensaver = isFinite(ss) && ss >= 0 ? Math.floor(ss) : 150
      root.idleLock = isFinite(lk) && lk >= 0 ? Math.floor(lk) : 300
    }
  }

  function idleLabelFor(secs) {
    var s = Number(secs)
    if (s >= 86400) return "Off"
    if (s >= 3600) return (s / 3600) + " h"
    return Math.round(s / 60) + " min"
  }

  // Chip click: argv-only write through idle-settings.sh (closed value
  // allowlist), optimistic OSD, then the FileView confirms from disk —
  // and the shell's own watcher applies the new timeout immediately.
  function setIdleTimeout(key, secs) {
    if (idleSetProc.running) return
    idleSetProc.command = [root.idleScript, "set", key, String(secs)]
    idleSetProc.running = true
    var name = key === "lock" ? "Lock" : "Screensaver"
    root.osd(Controls.glyphFor("screensaver"), name + " " + root.idleLabelFor(secs))
  }

  Process {
    id: idleSetProc
    running: false
    command: ["bash", root.idleScript, "get"]
    onExited: shellConfigFile.reload()   // belt & braces if the watcher lags
  }

  // History row: apps launch again (and re-record); commands jump to their
  // selected row in the All-commands list (they may take arguments).
  function activateHistoryRow(p) {
    if (!p || !p.route) return
    if (p.isApp) {
      var app = root.appById[String(p.route).slice(4)]
      if (app) root.launchAppRecord(app)
      return
    }
    root.selectRoute(String(p.route))
  }

  // Detail-pane "Forget from history" — drops the entry from the timeline,
  // the strip, frecency ranking, and disk (forgetRoute → update-usage.sh).
  function forgetHistoryRow() {
    var p = root.detailPayload
    if (!p || p.kind !== "history" || !p.route) return
    root.forgetRoute(String(p.route))
    root.osd("⌫", "Removed from history")
    root.rebuildDisplay(true)
  }

  function activate(action) {
    if (root.detailIsComputed) { root.activateComputed(action); return }
    var cmd = root.detailCmd
    if (!cmd) return
    if (cmd.isApp) { root.launchApp(); return }
    var cmdline = root.currentCommandLine()

    if (action === "copy") { root.copyCommandLine(cmdline); return }
    if (action === "terminal") { root.openTerminal(cmdline); root.noteLaunch(cmd.route); return }

    // Smart hybrid default: sudo and interactive commands go to a terminal
    // (sudo first asking for confirmation), the rest run in the background
    // with OSD feedback.
    if (cmd.sudo) {
      root.pendingCmdline = cmdline
      root.confirmOpen = true
      return
    }
    if (CmdModel.needsTerminal(cmd)) {
      root.openTerminal(cmdline)
      root.noteLaunch(cmd.route)
    } else {
      root.runBackground(cmdline, cmd.route)
    }
  }

  function runBackground(cmdline, route) {
    if (runProc.running) {
      root.osd("󰅚", "Another command is still running")
      return
    }
    runProc.command = ["bash", "-lc", cmdline]
    runProcRoute = route
    runProc.running = true
    root.noteLaunch(route)
  }

  property string runProcRoute: ""

  Process {
    id: runProc
    running: false
    stdout: StdioCollector { id: runOut; waitForEnd: true }
    stderr: StdioCollector { id: runErr; waitForEnd: true }
    onExited: function(exitCode) {
      var detail = exitCode === 0 ? "" : (runErr.text.trim() || runOut.text.trim()).split("\n")[0]
      root.lastRunInfo = runProcRoute + " — " + (exitCode === 0 ? "ok" : "failed (" + exitCode + ")" + (detail ? ": " + detail : ""))
      root.osd(exitCode === 0 ? "✔" : "✖", root.lastRunInfo)
    }
  }

  function osd(icon, message) {
    Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: icon, message: message })])
  }

  function confirmPending() {
    root.confirmOpen = false
    var pw = root.pendingPower
    if (pw) {
      root.pendingPower = null
      var a = Controls.actionById(String(pw.id || ""))
      if (a) root.runPower(a)
      return
    }
    root.openTerminal(root.pendingCmdline)
    root.noteLaunch(root.detailCmd ? root.detailCmd.route : "")
    root.pendingCmdline = ""
  }

  function cancelConfirm() {
    root.confirmOpen = false
    root.pendingCmdline = ""
    root.pendingPower = null
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  // ---------------------------------------------------------- IPC
  IpcHandler {
    target: "cmdcenter"

    function open(query: string): string {
      root.openPayloadForIpc(query)
      return "ok"
    }
    function close(): string {
      root.cancel()
      return "ok"
    }
    function toggle(query: string): string {
      if (root.opened) root.cancel()
      else root.openPayloadForIpc(query)
      return "ok"
    }
    function ping(): string { return "ok" }
  }

  function openPayloadForIpc(query) {
    var q = (query === undefined || query === null) ? "" : String(query)
    root.open(JSON.stringify({ query: q }))
  }

  // ---------------------------------------------------------- window
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cmdcenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      // Absorb clicks that land on the card but not on any control.
      MouseArea { anchors.fill: parent; onClicked: {} }

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ------------------------------------------------ header: name + counts
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(Style.space(30), Style.font.title + Style.space(8))
          spacing: Style.spacing.md

          Text {
            Layout.fillWidth: true
            text: "󰒓 Command Center"
            color: root.foreground
            opacity: 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }

          Text {
            visible: root.rowsLoaded
            text: root.catalog.length + " commands · " + Math.max(0, groupListModel.count - 5) + " groups · " + root.apps.length + " apps"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ------------------------------------------------ search field
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(Style.space(28), Style.font.title + Style.space(10))
          spacing: Style.spacing.md

          TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: root.rowsLoaded
              ? "Search " + root.catalog.length + " commands and apps…"
              : "Loading commands…"
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            foreground: root.foreground
            accent: root.selectedBorder
            onTextChanged: {
              root.filterText = text
              root.rebuildDisplay()
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (root.confirmOpen) {
                if (confirmDialog.handleKey(event)) event.accepted = true
                return
              }
              // A footer popover open swallows Esc first (same precedence
              // the confirmation dialog has), then everything else.
              if (root.openPopover !== "") {
                root.openPopover = ""
                event.accepted = true
                return
              }
              var k = event.key
              if (k === Qt.Key_Escape) {
                if (searchField.text) searchField.text = ""
                else if (root.focusPane !== 1) root.focusPane = 1
                else root.cancel()
                event.accepted = true
              } else if (k === Qt.Key_Up) {
                root.moveSelection(-1); event.accepted = true
              } else if (k === Qt.Key_Down) {
                root.moveSelection(1); event.accepted = true
              } else if (k === Qt.Key_Left) {
                // In the commands pane arrows move the caret until it hits a
                // boundary; in the group/detail panes they switch panes at once.
                if (!(root.focusPane === 1 && searchField.cursorPosition > 0)) {
                  root.focusPane = Math.max(0, root.focusPane - 1); event.accepted = true
                }
              } else if (k === Qt.Key_Right) {
                if (!(root.focusPane === 1 && searchField.cursorPosition < searchField.text.length)) {
                  root.focusPane = Math.min(2, root.focusPane + 1); event.accepted = true
                }
              } else if (k === Qt.Key_Tab) {
                root.focusPane = (root.focusPane + 1) % 3; event.accepted = true
              } else if (k === Qt.Key_Backtab) {
                root.focusPane = (root.focusPane + 2) % 3; event.accepted = true
              } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                root.enterPressed(); event.accepted = true
              } else if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_C && !searchField.selectedText) {
                if (root.detailIsComputed) root.activateComputed("copy")
                else root.copyCommandLine(root.currentCommandLine())
                event.accepted = true
              } else if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_T) {
                root.activate("terminal"); event.accepted = true
              }
            }
          }
        }

        // -------------------------------------------------- home cards (6b)
        // Double-height tiles: wide media strip (square art · title/
        // artist/counter · transport) plus weather·today and system,
        // each now two-line. Media joins only while a MPRIS player
        // has a title — cover art with the player's logo badge, transport
        // buttons, and a seekable progress bar along the bottom edge;
        // clicking off the buttons raises the player (Windows-tile style).
        // Data rules unchanged: open-cycle refresh, no timers; art/logo
        // react to their sources. Hidden once a query is typed.
        // PINNED: this row and the recents strip below are a fixed block —
        // nothing between the search field and the results pane scrolls,
        // and the row is three EQUAL thirds (media slot / weather /
        // system — all fillWidth with no preferred width, content
        // centered): the slot's transparent spacer keeps the others from
        // shifting sideways when a player starts/stops.
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: root.homeVisible ? Style.space(70) : 0
          visible: root.homeVisible
          spacing: Style.spacing.md

          // Reserved slot for the media strip (see PINNED above): live
          // card, else the last-media ghost, else a transparent spacer.
          // Every tile in this row fills one equal third, so the layout
          // is identical in all three states.
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.nowPlaying === null && !root.ghostHasMedia
          }

          // ---- last-media ghost (7.2): Windows-style pin. The last
          // played track stays after the player closes — dimmed, frozen
          // at the saved position; click relaunches the player. No
          // transport buttons (nothing to control) and no seek (frozen).
          HomeCard {
            visible: root.nowPlaying === null && root.ghostHasMedia
            hoverable: true
            opacity: ghostHover.containsMouse ? 0.85 : 0.55
            caption: "Last played"
            Layout.fillWidth: true
            onClicked: root.launchGhostPlayer()
            HoverHandler { id: ghostHover }
            overlays: [
              // Frozen progress line at the last saved position.
              Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, root.ghostFrac)
                height: Style.space(2)
                radius: Style.space(1)
                color: Util.alpha(root.selectedBorder, 0.5)
                visible: root.ghostFrac >= 0
              }
            ]

            RowLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              spacing: Style.space(5)

              Item {
                Layout.preferredWidth: Style.space(50)
                Layout.fillHeight: true

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: Util.alpha(root.foreground, 0.08)
                  clip: true
                  Image {
                    id: ghostArtImage
                    anchors.fill: parent
                    // ?v= = the snapshot's save time: a replaced copy
                    // re-decodes even though the path is unchanged.
                    source: root.ghostHasMedia && root.ghostMedia.artFile
                      ? "file://" + root.ghostMedia.artFile + "?v="
                        + String(root.ghostMedia.at || 0) : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: ghostArtImage.status !== Image.Ready
                    text: Controls.MEDIA_GLYPHS.music
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }
                }
                // Player logo badge (persisted path; hides if the file
                // is gone after an update).
                Item {
                  width: Style.space(15)
                  height: Style.space(15)
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.rightMargin: Style.space(-2)
                  anchors.bottomMargin: Style.space(-2)
                  visible: root.ghostHasMedia
                    && String(root.ghostMedia.logoFile || "") !== ""
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(3)
                    color: root.background
                    border.width: Math.max(1, Style.space(1))
                    border.color: Util.alpha(root.foreground, 0.15)
                  }
                  Image {
                    anchors.fill: parent
                    anchors.margins: Style.space(1)
                    source: root.ghostHasMedia && root.ghostMedia.logoFile
                      ? String(root.ghostMedia.logoFile) : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                  }
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Text {
                  Layout.fillWidth: true
                  text: root.ghostHasMedia
                    ? String(root.ghostMedia.title || "") : ""
                  color: root.foreground
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.weight: Font.DemiBold
                }
                Text {
                  Layout.fillWidth: true
                  text: root.ghostHasMedia
                    ? String(root.ghostMedia.artist || "") : ""
                  color: root.foreground
                  opacity: 0.6
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                // Frozen elapsed / total — the last saved position.
                Text {
                  Layout.fillWidth: true
                  visible: root.ghostHasMedia && Number(root.ghostMedia.lenUs) > 0
                  text: root.ghostHasMedia
                    ? Dashboard.fmtTime(Number(root.ghostMedia.posUs))
                      + " / " + Dashboard.fmtTime(Number(root.ghostMedia.lenUs))
                    : ""
                  color: root.foreground
                  opacity: 0.5
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---- media strip: art + badge · title/artist · transport
          HomeCard {
            visible: root.nowPlaying !== null
            hoverable: true
            // Equal third of the row — see the ghost card's note.
            Layout.fillWidth: true
            // Card click (anywhere off the transport buttons and the seek
            // zone): raise the player, then dismiss the palette — hand the
            // screen over to the app you just summoned.
            onClicked: { root.raisePlayer(); root.close() }
            overlays: [
              // Seekable progress bar on the card's bottom edge —
              // rides the finger while dragging the handle.
              Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0,
                  seekZone.dragMode ? seekZone.dragFrac : root.mediaFrac)
                height: Style.space(2)
                radius: Style.space(1)
                color: Util.alpha(root.selectedBorder, 0.85)
                visible: root.mediaFrac >= 0
              },
              MouseArea {
                id: seekZone
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(12)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.mediaFrac >= 0 && root.nowPlaying !== null
                  && root.nowPlaying.canSeek
                property bool dragMode: false
                property real dragFrac: 0
                function fracAt(x) { return Math.min(1, Math.max(0, x / width)) }
                onPressed: function(mouse) {
                  dragMode = true
                  dragFrac = fracAt(mouseX)
                }
                onPositionChanged: function(mouse) {
                  if (dragMode) dragFrac = fracAt(mouseX)
                }
                onReleased: function(mouse) {
                  if (dragMode) {
                    dragFrac = fracAt(mouseX)
                    root.seekMediaTo(dragFrac)
                  }
                  dragMode = false
                }
                onCanceled: dragMode = false
              },
              // Handle dot: appears on hover, drags to seek. Centered on
              // the fill's end (or under the finger mid-drag).
              Rectangle {
                width: Style.space(10)
                height: Style.space(10)
                radius: Style.space(5)
                color: root.background
                border.width: Math.max(1, Style.space(1))
                border.color: root.selectedBorder
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(-4)
                visible: root.mediaFrac >= 0
                  && (seekZone.containsMouse || seekZone.dragMode)
                x: parent.width * Math.max(0,
                  seekZone.dragMode ? seekZone.dragFrac : root.mediaFrac)
                  - width / 2
              }
            ]

            // The media strip's content is one horizontal row: art ·
            // title/artist · transport (HomeCard content stays a
            // column — the Qt Quick Layouts here have no writable
            // orientation, so the row is injected as a child).
            RowLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              spacing: Style.space(5)
              // Cover art with the player logo badge pinned to the corner.
              Item {
                Layout.preferredWidth: Style.space(50)
                Layout.fillHeight: true

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: Util.alpha(root.foreground, 0.08)
                  clip: true
                  Image {
                    id: mediaArtImage
                    anchors.fill: parent
                    source: root.mediaArt
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: mediaArtImage.status !== Image.Ready
                    text: Controls.MEDIA_GLYPHS.music
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }
                }
                Item {
                  width: Style.space(15)
                  height: Style.space(15)
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.rightMargin: Style.space(-2)
                  anchors.bottomMargin: Style.space(-2)
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(3)
                    color: root.background
                    border.width: Math.max(1, Style.space(1))
                    border.color: Util.alpha(root.foreground, 0.15)
                  }
                  Image {
                    anchors.fill: parent
                    anchors.margins: Style.space(1)
                    source: root.mediaLogo
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    visible: status === Image.Ready
                  }
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: root.nowPlaying ? String(root.nowPlaying.trackTitle || "") : ""
                  color: root.foreground
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.weight: Font.DemiBold
                }
                Text {
                  Layout.fillWidth: true
                  text: root.nowPlaying ? String(root.nowPlaying.trackArtist || "") : ""
                  color: root.foreground
                  opacity: 0.6
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                // Elapsed / total (Spotify-style). While dragging the
                // handle the elapsed side previews the target spot.
                Text {
                  Layout.fillWidth: true
                  visible: root.mediaLenUs > 0
                    && (seekZone.dragMode || root.mediaPosUs >= 0)
                  text: (seekZone.dragMode
                    ? Dashboard.fmtTime(seekZone.dragFrac * root.mediaLenUs)
                    : root.mediaElapsed)
                    + " / " + root.mediaTotal
                  color: root.foreground
                  opacity: 0.5
                  elide: Text.ElideRight
                  lineHeight: 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MediaBtn {
                glyph: Controls.MEDIA_GLYPHS.prev
                available: root.nowPlaying !== null && root.nowPlaying.canGoPrevious
                onTriggered: if (root.nowPlaying) root.nowPlaying.previous()
              }
              MediaBtn {
                glyph: root.nowPlaying && root.nowPlaying.isPlaying
                  ? Controls.MEDIA_GLYPHS.pause : Controls.MEDIA_GLYPHS.play
                available: root.nowPlaying !== null && root.nowPlaying.canTogglePlaying
                onTriggered: if (root.nowPlaying) root.nowPlaying.togglePlaying()
              }
              MediaBtn {
                glyph: Controls.MEDIA_GLYPHS.next
                available: root.nowPlaying !== null && root.nowPlaying.canGoNext
                onTriggered: if (root.nowPlaying) root.nowPlaying.next()
              }
            }
          }

          // ---- weather + today (8.3): three left-aligned rows — full
          // date, location (city, country — country from the same wttr.in
          // payload as the condition), and clock · temp — condition.
          // Every row is fillWidth + elide, so nothing overshoots.
          HomeCard {
            caption: root.homeDay.week

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              // Sat 17 Oct 2026
              Text {
                Layout.fillWidth: true
                text: (root.homeDay.weekday
                  ? root.homeDay.weekday.slice(0, 3) : "")
                  + (root.homeDay.date ? " " + root.homeDay.date : "")
                color: root.foreground
                elide: Text.ElideRight
                lineHeight: 1.0
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              // Ibadan, Nigeria
              Text {
                Layout.fillWidth: true
                text: [root.homeWeather.city, root.homeWeatherDetail.country]
                  .filter(function(s) { return s }).join(", ")
                color: root.foreground
                opacity: 0.6
                elide: Text.ElideRight
                lineHeight: 1.0
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              // 14:32 · 28°C - Light rain showers
              Text {
                Layout.fillWidth: true
                text: [Dashboard.fmtClock(root.homeDate),
                  [root.homeWeather.temp, root.homeWeatherDetail.condition]
                    .filter(function(s) { return s }).join(" - ")]
                  .filter(function(s) { return s }).join(" · ")
                color: root.foreground
                opacity: 0.6
                elide: Text.ElideRight
                lineHeight: 1.0
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---- system & network (8.3): a 3×3 metric grid — link health
          // (ping · loss · receiving), traffic (sending · downloaded ·
          // uploaded), identity (IP · gateway · CPU). Caption-size cells
          // of equal width with elide, so nothing can overshoot the
          // tile; values ride the open-cycle status probe (the rates
          // are its 1s window, the totals are since-boot counters).
          HomeCard {
            caption: "System & Network"

            ColumnLayout {
              id: sysCol
              Layout.fillWidth: true
              spacing: Style.space(3)

              Repeater {
                model: root.sysGrid
                delegate: RowLayout {
                  required property var modelData
                  readonly property var cells: modelData
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  Repeater {
                    model: cells
                    delegate: RowLayout {
                      required property var modelData
                      Layout.fillWidth: true
                      spacing: Style.space(3)

                      Text {
                        text: modelData.l
                        color: root.foreground
                        opacity: 0.5
                        elide: Text.ElideRight
                        lineHeight: 1.0
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        Layout.fillWidth: true
                        text: modelData.v
                        color: root.foreground
                        elide: Text.ElideRight
                        lineHeight: 1.0
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------ recent strip
        // Quick-launch row of the last few things you ran (apps + commands),
        // most recent first, under a clear "Recently Used" heading.
        // Hidden while searching — the results list takes over. Apps
        // launch on click; commands jump to their selected row.
        ColumnLayout {
          Layout.fillWidth: true
          // Clear breathing room under the tall tiles.
          Layout.topMargin: Style.space(12)
          Layout.preferredHeight: visible ? implicitHeight : 0
          visible: recentModel.count > 0 && !root.filterText
          spacing: Style.spacing.md

          Text {
            text: "Recently Used"
            color: root.foreground
            opacity: 0.5
            lineHeight: 1.0
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }

          ListView {
            id: recentList
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(44)
            orientation: ListView.Horizontal
            spacing: Style.space(10)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: recentModel

            delegate: Rectangle {
              required property int index
              required property string route
              required property string label
              required property string appIcon
              required property string kind
              required property string group

              property bool tileHover: tileHoverHandler.hovered
              width: Style.space(46)      // 6b.2: halved — the strip
              height: Style.space(44)     // shouldn't own the fold
              radius: root.cornerRadius
              color: tileHover ? Util.alpha(root.foreground, 0.09) : Util.alpha(root.foreground, 0.04)

              HoverHandler { id: tileHoverHandler }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activateRecent(index)
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                spacing: Style.space(3)

                Item {
                  Layout.fillWidth: true
                  Layout.fillHeight: true

                  Image {
                    visible: kind === "app" && appIcon !== ""
                    anchors.centerIn: parent
                    source: kind === "app" && appIcon !== "" ? "file://" + appIcon : ""
                    sourceSize.width: 20
                    sourceSize.height: 20
                    width: Style.space(20)
                    height: Style.space(20)
                    fillMode: Image.PreserveAspectFit
                  }
                  Rectangle {
                    visible: !(kind === "app" && appIcon !== "")
                    anchors.centerIn: parent
                    width: Style.space(18)
                    height: Style.space(18)
                    radius: Style.space(4)
                    color: Util.alpha(root.foreground, 0.14)
                    Text {
                      anchors.centerIn: parent
                      text: root.rowGlyph(kind, group, label)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.DemiBold
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: label
                  color: root.foreground
                  opacity: 0.85
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignHCenter
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }
              }

              // Hover-only ✕: forget this recent in place — the manual half
              // of the hybrid recents design. Declared last so it stacks
              // above the tile's click area and intercepts the press.
              Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(2)
                width: Style.space(12)
                height: Style.space(12)
                radius: Style.space(6)
                visible: tileHover
                color: Util.alpha(root.foreground, 0.25)

                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.forgetRecent(index)
                }
              }
            }
          }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.18) }

        // ------------------------------------------------ loading / error
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: !root.rowsLoaded

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.spacing.md

            Text {
              text: root.loadError ? root.loadError : "Loading commands…"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ActionButton {
              visible: root.loadError.length > 0
              label: "Retry"
              primary: true
              Layout.alignment: Qt.AlignHCenter
              onTriggered: root.startCatalogLoad()
            }
          }
        }

        // ------------------------------------------------ three panes
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.rowsLoaded
          spacing: Style.spacing.md

          // ---- groups pane
          Rectangle {
            Layout.fillWidth: false
            Layout.preferredWidth: Style.space(220)
            Layout.fillHeight: true
            radius: root.cornerRadius
            color: root.focusPane === 0 ? Util.alpha(root.foreground, 0.05) : "transparent"

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.spacing.xs

              Text {
                text: "GROUPS"
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                Layout.leftMargin: Style.space(8)
              }

              ListView {
                id: groupList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: groupListModel
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  required property int index
                  required property string name
                  required property string label
                  required property string glyph
                  required property int count

                  width: ListView.view.width
                  height: root.groupRowHeight
                  radius: root.cornerRadius
                  color: {
                    if (index === root.selectedGroupIndex && !root.filterText) return root.selectedBackground
                    if (hover.hovered) return Util.alpha(root.foreground, 0.06)
                    return "transparent"
                  }

                  HoverHandler { id: hover }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      root.focusPane = 0
                      root.selectGroup(index)
                      searchField.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: glyph
                      color: index === root.selectedGroupIndex && !root.filterText ? root.selectedText : root.foreground
                      opacity: 0.85
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      Layout.fillWidth: true
                      text: label
                      color: index === root.selectedGroupIndex && !root.filterText ? root.selectedText : root.foreground
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: index === 0 ? Font.DemiBold : Font.Normal
                    }
                    Text {
                      text: count
                      color: index === root.selectedGroupIndex && !root.filterText ? root.selectedText : root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          Rectangle { Layout.fillWidth: false; Layout.preferredHeight: Style.space(300); Layout.preferredWidth: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.15); Layout.alignment: Qt.AlignVCenter }

          // ---- commands pane
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.cornerRadius
            color: root.focusPane === 1 ? Util.alpha(root.foreground, 0.05) : "transparent"

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.spacing.xs

              RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.space(8)
                Text {
                  Layout.fillWidth: true
                  text: root.activeGroupLabel.toUpperCase()
                  color: root.foreground
                  opacity: 0.5
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: displayModel.count + (root.filterText ? " matches" : "")
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              ListView {
                id: cmdList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: displayModel
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                delegate: BorderSurface {
                  required property int index
                  required property string route
                  required property string label
                  required property string appIcon
                  required property string kind
                  required property string summary
                  required property string group
                  required property bool sudo
                  required property int args
                  required property bool recent
                  required property bool pinned

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: index === root.selectedCommand ? root.selectedBackground : (rowHover.hovered ? Util.alpha(root.foreground, 0.06) : "transparent")
                  borderSpec: index === root.selectedCommand && root.focusPane === 1 ? root.selectedBorderSpec : Border.none()
                  padding: Style.space(16)

                  HoverHandler { id: rowHover }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      root.focusPane = 1
                      root.selectedCommand = index
                      searchField.forceActiveFocus()
                    }
                    onDoubleClicked: {
                      root.selectedCommand = index
                      root.focusPane = 2
                      root.activate("auto")
                    }
                  }

                  ColumnLayout {
                    anchors.fill: parent
                    spacing: 2

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(8)

                      Image {
                        visible: (kind === "app" || kind === "history"
                          || kind === "newsitem" || kind === "window"
                          || kind === "clip") && appIcon !== ""
                        source: (kind === "app" || kind === "history"
                          || kind === "newsitem" || kind === "window"
                          || kind === "clip") && appIcon !== ""
                          ? "file://" + appIcon : ""
                        sourceSize.width: 24
                        sourceSize.height: 24
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.rightMargin: Style.space(4)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                      }
                      Rectangle {
                        visible: !((kind === "app" || kind === "history"
                          || kind === "newsitem" || kind === "window"
                          || kind === "clip") && appIcon !== "")
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.rightMargin: Style.space(4)
                        radius: Style.space(4)
                        color: Util.alpha(root.foreground, 0.14)
                        Text {
                          anchors.centerIn: parent
                          // Control + news rows show their curated nerd
                          // glyph (the table's icon); every other row
                          // keeps its letter-box initial, as before.
                          text: kind === "toggle" || kind === "panel"
                            || kind === "power" || kind === "status"
                            || kind === "newsitem" || kind === "newsrefresh"
                            || kind === "newsfeeds"
                            ? root.rowGlyph(kind, group, label)
                            : label.length ? label.charAt(0).toUpperCase() : "?"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.weight: Font.DemiBold
                        }
                      }
                      Text {
                        Layout.fillWidth: true
                        text: label
                        color: index === root.selectedCommand ? root.selectedText : root.foreground
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                      }
                      Text {
                        visible: recent
                        text: "🕘"
                        color: index === root.selectedCommand ? root.selectedText : root.foreground
                        opacity: 0.7
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        visible: pinned
                        text: "★"
                        color: index === root.selectedCommand ? root.selectedText : root.foreground
                        opacity: 0.8
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        visible: sudo
                        text: "sudo"
                        color: index === root.selectedCommand ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        visible: args > 0
                        text: "⚙ " + args
                        color: index === root.selectedCommand ? root.selectedText : root.foreground
                        opacity: 0.7
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      Layout.fillWidth: true
                      text: summary
                      color: index === root.selectedCommand ? root.selectedText : root.foreground
                      opacity: 0.6
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                Text {
                  visible: displayModel.count === 0 && root.rowsLoaded
                  anchors.centerIn: parent
                  text: root.filterText ? "No commands match “" + root.filterText + "”" : "No commands in this group"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          Rectangle { Layout.fillWidth: false; Layout.preferredHeight: Style.space(300); Layout.preferredWidth: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.15); Layout.alignment: Qt.AlignVCenter }

          // ---- detail pane
          Rectangle {
            Layout.fillWidth: false
            Layout.preferredWidth: Style.space(370)
            Layout.fillHeight: true
            radius: root.cornerRadius
            color: root.focusPane === 2 ? Util.alpha(root.foreground, 0.05) : "transparent"

            // Hints when nothing is selected.
            Text {
              visible: root.detailCmd === null && !root.detailIsComputed
              anchors.centerIn: parent
              width: parent.width - Style.space(32)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: "Select a command to see its details,\narguments, and examples."
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              contentHeight: detailCol.implicitHeight + Style.space(16)
              clip: true
              visible: root.detailCmd !== null || root.detailIsComputed
              boundsBehavior: Flickable.StopAtBounds

              ColumnLayout {
                id: detailCol
                width: parent.width - Style.space(8)
                x: Style.space(4)
                y: Style.space(8)
                spacing: Style.spacing.md

                // ---- computed result card: calculator / converter / web /
                // ask-an-agent rows carry their own action payload instead of
                // a catalog record, so they render their own panel here.
                // Deliberately minimal for web/agent (user decision): caption,
                // the query, one action button — nothing else.
                ColumnLayout {
                  visible: root.detailIsComputed
                  Layout.fillWidth: true
                  spacing: root.detailKind === "web" || root.detailKind === "agent"
                    ? Style.spacing.xs : Style.spacing.sm

                  Text {
                    text: root.detailKind === "calc" ? "CALCULATION"
                        : root.detailKind === "convert" ? "CONVERSION"
                        : root.detailKind === "web" ? "WEB SEARCH"
                        : root.detailKind === "window" ? "WINDOW"
                        : root.detailKind === "clip" ? "CLIPBOARD"
                        : root.detailKind === "file" ? "FILE"
                        : root.detailKind === "dict" ? "DICTIONARY"
                        : root.detailKind === "toggle" ? "QUICK ACTION"
                        : root.detailKind === "panel" ? "SETTINGS"
                        : root.detailKind === "power" ? "SESSION"
                        : root.detailKind === "status" ? "SYSTEM"
                        : root.detailKind === "history" ? "LAUNCH HISTORY"
                        : root.detailKind === "newsitem" ? "NEWS"
                        : root.detailKind === "newsrefresh" || root.detailKind === "newsfeeds"
                          || root.detailKind === "feedadd"
                          ? "NEWS" : "AI AGENT"
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  Image {
                    visible: root.detailIcon !== ""
                    source: root.detailIcon !== "" ? "file://" + root.detailIcon : ""
                    sourceSize.width: 48
                    sourceSize.height: 48
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  Text {
                    visible: root.detailKind === "calc" || root.detailKind === "convert"
                    Layout.fillWidth: true
                    // Guarded on the field itself: invisible items still
                    // evaluate their bindings, and web/agent payloads carry
                    // no `result` (assigning undefined to a QString warns).
                    text: root.detailPayload && root.detailPayload.result !== undefined
                      ? String(root.detailPayload.result) : ""
                    color: root.selectedBorder
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.weight: Font.Bold
                  }

                  // Control/history big readout: the live state (ON/OFF), a
                  // measured value, or the age of a launch. Guarded on the
                  // fields themselves — invisible items still evaluate
                  // bindings, and undefined → QString warns.
                  Text {
                    visible: {
                      if (root.detailKind === "toggle")
                        return !!root.detailPayload
                          && (root.detailPayload.state === "on"
                              || root.detailPayload.state === "off")
                      return (root.detailKind === "status"
                              || root.detailKind === "history")
                        && !!root.detailPayload
                    }
                    Layout.fillWidth: true
                    text: {
                      if (!root.detailPayload) return ""
                      if (root.detailKind === "toggle") {
                        var s = String(root.detailPayload.state || "")
                        return s === "on" ? "ON" : s === "off" ? "OFF" : ""
                      }
                      if (root.detailKind === "status")
                        return String(root.detailPayload.value || "")
                      return String(root.detailPayload.ago || "")
                    }
                    color: root.selectedBorder
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.weight: Font.Bold
                  }

                  Text {
                    visible: !!root.detailPayload
                      && (root.detailPayload.expr || root.detailPayload.query
                          || root.detailPayload.body)
                    Layout.fillWidth: true
                    text: {
                      if (!root.detailPayload) return ""
                      if (root.detailPayload.expr)
                        return String(root.detailPayload.expr)
                      if (root.detailKind === "web" || root.detailKind === "agent")
                        return "“" + String(root.detailPayload.query || "") + "”"
                      return String(root.detailPayload.body || "")
                    }
                    color: root.foreground
                    opacity: 0.7
                    wrapMode: Text.WrapAnywhere
                    font.family: root.fontFamily
                    font.pixelSize: root.detailKind === "web" || root.detailKind === "agent"
                      ? Style.font.caption : Style.font.body
                  }

                  Button {
                    visible: root.detailKind === "calc" || root.detailKind === "convert"
                      || root.detailKind === "dict"
                    text: "Copy result"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "web"
                    text: root.detailPayload && root.detailPayload.engine
                      ? "Open in " + root.detailPayload.engine : "Open in browser"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "agent"
                    text: !root.detailPayload || root.detailPayload.mode === "pick"
                        ? "Choose default agent…"
                        : root.detailPayload.query
                          ? "Ask " + (root.detailPayload.agentName || "agent")
                          : "Open " + (root.detailPayload.agentName || "agent")
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  // ---- news card (Phase 6): hero image when the feed
                  // provided one (cached locally by fetch-feeds.sh — a
                  // missing/failed download just means no hero), then
                  // title, feed logo + source/age, the feed-provided
                  // excerpt, and the continue-reading CTA. Ctrl+C copies
                  // the link.
                  Rectangle {
                    visible: root.detailKind === "newsitem" && heroImg.status === Image.Ready
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(120)
                    radius: Style.space(10)
                    clip: true
                    color: Util.alpha(root.foreground, 0.06)
                    Image {
                      id: heroImg
                      anchors.fill: parent
                      source: root.detailKind === "newsitem" && root.detailPayload
                        && root.detailPayload.image !== ""
                        ? "file://" + root.stateDir + "/news-img/item"
                          + root.detailPayload.idx + ".img"
                        : ""
                      sourceSize.width: 640
                      sourceSize.height: 360
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }
                  }
                  Text {
                    visible: root.detailKind === "newsitem" && !!root.detailPayload
                    Layout.fillWidth: true
                    text: root.detailPayload
                      ? String(root.detailPayload.label || "") : ""
                    color: root.foreground
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                  }
                  RowLayout {
                    visible: root.detailKind === "newsitem" && !!root.detailPayload
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Image {
                      visible: root.detailPayload && root.detailPayload.logo !== ""
                      source: root.detailPayload && root.detailPayload.logo !== ""
                        ? "file://" + root.detailPayload.logo : ""
                      sourceSize.width: 32
                      sourceSize.height: 32
                      Layout.preferredWidth: 16
                      Layout.preferredHeight: 16
                      fillMode: Image.PreserveAspectFit
                    }
                    Text {
                      Layout.fillWidth: true
                      text: {
                        if (!root.detailPayload) return ""
                        var src = String(root.detailPayload.source || "")
                        var pub = Number(root.detailPayload.published || 0)
                        return src + (pub ? " · " + Controls.relativeTime(pub, Date.now()) : "")
                      }
                      color: root.foreground
                      opacity: 0.6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Text {
                    visible: root.detailKind === "newsitem" && root.detailPayload
                      && root.detailPayload.excerpt !== ""
                    Layout.fillWidth: true
                    text: root.detailPayload ? String(root.detailPayload.excerpt) : ""
                    color: root.foreground
                    opacity: 0.68
                    wrapMode: Text.Wrap
                    maximumLineCount: 7
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Button {
                    visible: root.detailKind === "newsitem"
                    text: "Continue reading in browser"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Text {
                    visible: root.detailKind === "newsrefresh"
                    Layout.fillWidth: true
                    text: root.newsFeeds.length + " feeds · "
                      + root.newsItems.length + " stories"
                      + (root.newsErrors ? " · " + root.newsErrors + " failed" : "")
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Button {
                    visible: root.detailKind === "newsrefresh"
                    text: newsProc.running ? "Refreshing…" : "Refresh feeds now"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  // ---- edit-feeds card: which feeds are configured, then
                  // open the user-owned feeds.json in $EDITOR.
                  Text {
                    visible: root.detailKind === "newsfeeds"
                    Layout.fillWidth: true
                    text: root.newsFeeds.map(function(f) { return f.name }).join(" · ")
                    color: root.foreground
                    opacity: 0.7
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Button {
                    visible: root.detailKind === "newsfeeds"
                    text: "Open feeds file in editor"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  // ---- inline add-feed card: the URL, what will happen,
                  // one action. Enter already runs it (instant kind).
                  Text {
                    visible: root.detailKind === "feedadd" && !!root.detailPayload
                    Layout.fillWidth: true
                    text: root.detailPayload ? String(root.detailPayload.url || "") : ""
                    color: root.foreground
                    opacity: 0.7
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    visible: root.detailKind === "feedadd"
                    Layout.fillWidth: true
                    text: "Fetches the URL, follows any feed it declares, validates it as RSS/Atom, adds it to your feeds, and refreshes the list."
                    color: root.foreground
                    opacity: 0.55
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Button {
                    visible: root.detailKind === "feedadd"
                    text: addFeedProc.running ? "Adding…" : "Add feed"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  // ---- Phase-5 control buttons (one row per kind, plus the
                  // history pair). Power verbs spell out the consequence.
                  Button {
                    visible: root.detailKind === "toggle"
                    text: {
                      if (!root.detailPayload) return "Toggle"
                      var s = String(root.detailPayload.state || "")
                      var lbl = String(root.detailPayload.label || "")
                      if (s === "on") return "Turn off " + lbl
                      if (s === "off") return "Turn on " + lbl
                      return "Toggle " + lbl
                    }
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "panel"
                      || (root.detailKind === "status" && !!root.detailPayload
                          && String(root.detailPayload.panelId || "") !== "")
                    text: "Open settings"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "power"
                    text: {
                      if (!root.detailPayload) return "Run"
                      var lbl = String(root.detailPayload.label || "")
                      return root.detailPayload.confirm ? lbl + "…" : lbl + " now"
                    }
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "history"
                    text: root.detailPayload && root.detailPayload.isApp
                      ? "Launch again" : "Show command"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.activateComputed()
                  }

                  Button {
                    visible: root.detailKind === "history"
                    text: "Forget from history"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.forgetHistoryRow()
                  }
                }

                RowLayout {
                  visible: root.detailIsApp
                  spacing: Style.space(10)
                  Image {
                    visible: root.detailCmd && root.detailCmd.icon !== ""
                    source: root.detailIsApp && root.detailCmd && root.detailCmd.icon !== "" ? "file://" + root.detailCmd.icon : ""
                    sourceSize.width: 48
                    sourceSize.height: 48
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    fillMode: Image.PreserveAspectFit
                  }
                  Rectangle {
                    visible: root.detailIsApp && root.detailCmd && root.detailCmd.icon === ""
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Style.space(8)
                    color: Util.alpha(root.foreground, 0.14)
                    Text {
                      anchors.centerIn: parent
                      text: root.detailCmd && root.detailCmd.name ? root.detailCmd.name.charAt(0).toUpperCase() : "?"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    text: root.detailIsApp && root.detailCmd ? root.detailCmd.name : ""
                    color: root.foreground
                    wrapMode: Text.Wrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.weight: Font.DemiBold
                  }
                  Button {
                    text: root.detailCmd && root.isPinned(root.detailCmd.route) ? "★ Pinned" : "☆ Pin"
                    selected: !!root.detailCmd && root.isPinned(root.detailCmd.route)
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.togglePin()
                  }
                }

                RowLayout {
                  visible: root.detailIsCmd
                  Layout.fillWidth: true
                  spacing: Style.space(10)

                  Text {
                    Layout.fillWidth: true
                    text: root.detailCmd ? root.detailCmd.bare : ""
                    color: root.foreground
                    wrapMode: Text.WrapAnywhere
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.weight: Font.DemiBold
                  }
                  Button {
                    text: root.detailCmd && root.isPinned(root.detailCmd.route) ? "★ Pinned" : "☆ Pin"
                    selected: !!root.detailCmd && root.isPinned(root.detailCmd.route)
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.selectedBorder
                    onClicked: root.togglePin()
                  }
                }

                RowLayout {
                  visible: root.detailIsCmd
                  spacing: Style.space(8)
                  ArgPill { label: root.detailCmd ? root.detailCmd.group : "" }
                  ArgPill { visible: !!(root.detailCmd && root.detailCmd.sudo); label: "⚠ sudo"; }
                  ArgPill { visible: !!(root.detailCmd && root.detailCmd.complex); label: "complex" }
                }

                Text {
                  Layout.fillWidth: true
                  visible: !!(root.detailCmd && root.detailCmd.summary.length > 0)
                  text: root.detailCmd ? root.detailCmd.summary : ""
                  color: root.foreground
                  opacity: 0.8
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                // ---- parameter form: one control per token, feeding the
                // command line below as values change. Pills for small enums,
                // searchable dropdown for large ones, switches for flags.
                ColumnLayout {
                  visible: !!(root.detailCmd && root.detailCmd.tokens.length > 0 && !root.detailCmd.complex)
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)

                    Text {
                      Layout.fillWidth: true
                      text: "PARAMETERS"
                      color: root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                    }
                    Text {
                      // Static cap — binding this to parent.width would feed
                      // the row's own reflow back into layout (recursive
                      // rearrange warnings).
                      Layout.maximumWidth: Style.space(300)
                      text: root.detailCmd ? root.detailCmd.args : ""
                      color: root.foreground
                      opacity: 0.35
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Repeater {
                    model: root.detailCmd ? root.detailCmd.tokens : []
                    delegate: RowLayout {
                      id: tokRow
                      required property int index
                      required property var modelData

                      readonly property var tok: modelData
                      readonly property var value: index < root.formValues.length ? root.formValues[index] : undefined

                      Layout.fillWidth: true
                      spacing: Style.space(10)

                      // Label column: what this parameter is, and whether it
                      // is optional (required ones show no hint — they start
                      // with a sensible value already).
                      ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                          Layout.fillWidth: true
                          text: tok.kind === "flag" ? tok.label
                            : tok.kind === "keyval" ? tok.key + "=…"
                            : tok.kind === "enum" ? tok.options.join(" | ")
                            : tok.label
                          color: root.foreground
                          elide: Text.ElideRight
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                        }
                        Text {
                          visible: tok.required !== true
                          text: "optional"
                          color: root.foreground
                          opacity: 0.45
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      ToggleSwitch {
                        visible: tok.kind === "flag"
                        Layout.alignment: Qt.AlignVCenter
                        checked: tokRow.value === true
                        onToggled: root.setFormValue(tokRow.index, !tokRow.value)
                      }

                      // Small enums: segmented pills; clicking the selected
                      // pill clears it again (optional ones only — a required
                      // enum always keeps a choice).
                      RowLayout {
                        visible: tok.kind === "enum" && tok.options.length <= 4
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Style.space(4)
                        Repeater {
                          model: tok.options
                          delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: tokRow.value === modelData
                            radius: Style.space(6)
                            color: selected ? root.selectedBackground : Util.alpha(root.foreground, 0.07)
                            border.width: selected ? Math.max(1, Style.space(2)) : 1
                            border.color: selected ? root.selectedBorder : Util.alpha(root.foreground, 0.2)
                            implicitWidth: optionText.implicitWidth + Style.space(16)
                            implicitHeight: Math.max(Style.space(26), optionText.implicitHeight + Style.space(10))
                            Text {
                              id: optionText
                              anchors.centerIn: parent
                              text: modelData
                              color: selected ? root.selectedText : root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.weight: selected ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.setFormValue(tokRow.index,
                                selected && tok.required !== true ? "" : modelData)
                            }
                          }
                        }
                      }

                      // Large enums: searchable dropdown instead of a wall of
                      // pills (the catalog has a few 18-option enums).
                      SearchableDropdown {
                        visible: tok.kind === "enum" && tok.options.length > 4
                        showLabel: false
                        Layout.alignment: Qt.AlignVCenter
                        value: tokRow.value || ""
                        // Non-enum tokens have no options; invisible instances
                        // still evaluate bindings, so never feed undefined.
                        options: tok.kind === "enum" && tok.options ? tok.options : []
                        fontFamily: root.fontFamily
                        foreground: root.foreground
                        accent: root.selectedBorder
                        onChanged: function(v) { root.setFormValue(tokRow.index, v) }
                      }

                      TextField {
                        visible: tok.kind === "text" || tok.kind === "rest"
                        Layout.preferredWidth: Style.space(150)
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: tok.label
                        text: tokRow.value || ""
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        foreground: root.foreground
                        accent: root.selectedBorder
                        onTextChanged: {
                          if (text !== (tokRow.value || "")) root.setFormValue(tokRow.index, text)
                        }
                      }

                      TextField {
                        visible: tok.kind === "keyval"
                        Layout.preferredWidth: Style.space(130)
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: tok.label
                        text: tokRow.value || ""
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        foreground: root.foreground
                        accent: root.selectedBorder
                        onTextChanged: {
                          if (text !== (tokRow.value || "")) root.setFormValue(tokRow.index, text)
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: !!(root.detailCmd && root.detailCmd.complex)
                  Layout.fillWidth: true
                  text: root.detailCmd ? ("Subcommand spec: " + root.detailCmd.args + "\nEdit the command line below, or run it in a terminal.") : ""
                  color: root.foreground
                  opacity: 0.7
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // ---- examples
                ColumnLayout {
                  visible: !!(root.detailCmd && root.detailCmd.examples.length > 0)
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  Text {
                    text: "EXAMPLES"
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                  Repeater {
                    model: root.detailCmd ? root.detailCmd.examples : []
                    delegate: Text {
                      required property var modelData
                      Layout.fillWidth: true
                      text: modelData
                      color: root.foreground
                      opacity: 0.75
                      wrapMode: Text.WrapAnywhere
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                // ---- lazy help: fetched from `--help` on first selection of
                // the command, cached for the session. The omarchy dispatcher
                // intercepts --help centrally and prints usage instead of
                // forwarding it, so this can never execute the command.
                ColumnLayout {
                  visible: root.helpText.length > 0 || root.helpLoading
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  Text {
                    text: "HELP"
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                  Text {
                    visible: root.helpLoading
                    text: "Loading help…"
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    Layout.fillWidth: true
                    visible: root.helpText.length > 0
                    text: root.helpText
                    color: root.foreground
                    opacity: 0.7
                    wrapMode: Text.Wrap
                    maximumLineCount: 16
                    elide: Text.ElideRight
                    font.family: "monospace"
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle { visible: root.detailCmd !== null; Layout.fillWidth: true; Layout.preferredHeight: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.15) }

                // ---- command line + actions
                Text {
                  visible: root.detailIsCmd
                  text: "COMMAND LINE"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                TextField {
                  id: cmdLine
                  visible: root.detailIsCmd
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.max(Style.space(40), Style.font.body + Style.space(20))
                  text: root.detailCmd ? CmdModel.initialCommandLine(root.detailCmd) : ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  foreground: root.foreground
                  accent: root.selectedBorder
                }

                // Re-seed the form values and the command line whenever the
                // selection changes. Complex subcommand specs keep the
                // example-seeded freeform line (no per-token controls).
                Connections {
                  target: root
                  function on_DetailKeyChanged() {
                    var cmd = root.detailCmd
                    if (cmd && cmd.complex) {
                      root.formValues = []
                      cmdLine.text = CmdModel.initialCommandLine(cmd)
                    } else {
                      root.formValues = cmd ? CmdModel.seedFormValues(cmd) : []
                      cmdLine.text = cmd ? CmdModel.assembleCommandLine(cmd, root.formValues) : ""
                    }
                    root.requestHelp()
                  }
                }

                RowLayout {
                  visible: root.detailIsApp
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  ActionButton {
                    Layout.fillWidth: true
                    label: "▶  Launch"
                    primary: true
                    focused: root.focusPane === 2 && root.actionIndex === 0
                    onTriggered: { root.focusPane = 2; root.actionIndex = 0; root.activate("auto") }
                  }
                }

                RowLayout {
                  visible: root.detailIsCmd
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  ActionButton {
                    Layout.fillWidth: true
                    label: "▶  Run"
                    primary: true
                    focused: root.focusPane === 2 && root.actionIndex === 0
                    onTriggered: { root.focusPane = 2; root.actionIndex = 0; root.activate("auto") }
                  }
                  ActionButton {
                    Layout.fillWidth: true
                    label: "Terminal"
                    focused: root.focusPane === 2 && root.actionIndex === 1
                    onTriggered: { root.focusPane = 2; root.actionIndex = 1; root.activate("terminal") }
                  }
                  ActionButton {
                    Layout.fillWidth: true
                    label: "Copy"
                    focused: root.focusPane === 2 && root.actionIndex === 2
                    onTriggered: { root.focusPane = 2; root.actionIndex = 2; root.activate("copy") }
                  }
                }

                Text {
                  visible: root.detailCmd !== null && root.lastRunInfo.length > 0
                  Layout.fillWidth: true
                  text: root.lastRunInfo
                  color: root.foreground
                  opacity: 0.6
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.18) }

        // ------------------------------------------- sticky control rail
        // Always-visible footer of control tiles (Phase 5+): single-
        // control tiles toggle/open right here; the multi-control tiles
        // (audio, power) pop the anchored mini-popover above. Mouse-only
        // by design — the three-pane keyboard model stays untouched, and
        // everything here is also reachable in the Controls group.
        RowLayout {
          id: controlFooter
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(36)
          spacing: 0

          Repeater {
            model: root.footerTiles
            delegate: FooterTile {
              required property int index
              required property var modelData
              Layout.fillHeight: true
              tileData: modelData
              isFirst: index === 0
              activePopover: root.openPopover === String(modelData.id)
              onTriggered: function(item) { root.activateFooterTile(modelData, item) }
            }
          }

          Item { Layout.fillWidth: true }
        }

        // ------------------------------------------------ footer
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(26)
          spacing: Style.spacing.md

          Text {
            Layout.fillWidth: true
            text: "Type to search · ↑↓ move · ←/→ or Tab switch pane · Enter open/run · Ctrl+C copy · Ctrl+T terminal · Esc close"
            color: root.foreground
            opacity: 0.5
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: root.loadError.length ? root.loadError : (root.focusPane === 0 ? "groups" : root.focusPane === 1 ? "commands" : "detail")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // --------------------------------------- footer popovers (audio / power)
      // Anchored mini-popover for the multi-control footer tiles. The
      // shared kit's PopupCard needs a bar QtObject (requestPopout +
      // position), so this is an in-card surface positioned from the
      // anchor tile instead. Esc closes it before the palette; the
      // click-away catcher behind it dismisses it on any other card
      // click (the scrim outside the card still dismisses everything).
      MouseArea {
        anchors.fill: parent
        z: 15
        visible: root.openPopover.length > 0
        onClicked: root.openPopover = ""
      }

      Rectangle {
        id: footerPopover
        z: 20
        visible: root.openPopover.length > 0
        width: root.openPopover === "audio" ? Style.space(330) : Style.space(300)
        height: popoverCol.implicitHeight + Style.space(28)
        color: root.background
        border.color: root.border
        border.width: Math.max(1, Style.space(2))
        radius: root.cornerRadius

        // Position above the anchor tile, clamped inside the card.
        function place() {
          var a = root.popoverAnchor
          if (!a) return
          var p = a.mapToItem(card, 0, 0)
          x = Math.max(Style.space(12),
            Math.min(card.width - width - Style.space(12),
              p.x + a.width / 2 - width / 2))
          y = p.y - height - Style.space(10)
        }
        Connections {
          target: root
          function onOpenPopoverChanged() {
            if (root.openPopover) Qt.callLater(footerPopover.place)
          }
        }

        // Absorb clicks on the popover surface itself so they never
        // reach the click-away catcher behind it.
        MouseArea { anchors.fill: parent; onPressed: {} }

        ColumnLayout {
          id: popoverCol
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: 0

          // ------------------------------------------------ audio
          ColumnLayout {
            visible: root.openPopover === "audio"
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.space(4)
              text: "AUDIO"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.hairline
              Layout.bottomMargin: Style.space(4)
              color: Util.alpha(root.foreground, 0.18)
            }

            // ---- output channel: click row = mute, slider = volume
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(32)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(8)
                color: outRowMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.14) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
              }
              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                Text {
                  text: root.statusInfo.outputMuted ? Controls.FOOTER_GLYPHS.volumeOff : Controls.FOOTER_GLYPHS.volume
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: "Output"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: root.statusInfo.outputMuted ? "Muted"
                    : (root.statusInfo.volumePct !== undefined ? root.statusInfo.volumePct + "%" : "")
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea {
                id: outRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleAudioMute("output")
              }
            }
            PanelSlider {
              Layout.fillWidth: true
              value: root.statusInfo.volumePct !== undefined ? root.statusInfo.volumePct : 0
              minimum: 0
              maximum: 100
              step: 1
              integer: true
              trackColor: Util.alpha(root.foreground, 0.25)
              fillColor: root.selectedBorder
              knobColor: root.foreground
              onReleased: function(v) { root.setAudioVolume("output", v) }
              onRightClicked: root.toggleAudioMute("output")
            }

            // ---- input channel: same pattern, mic glyphs
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(32)
              Layout.topMargin: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(8)
                color: inRowMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.14) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
              }
              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                Text {
                  text: root.statusInfo.micMuted ? Controls.FOOTER_GLYPHS.micOff : Controls.FOOTER_GLYPHS.mic
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: "Input"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: root.statusInfo.micMuted ? "Muted"
                    : (root.statusInfo.inputPct !== undefined ? root.statusInfo.inputPct + "%" : "")
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea {
                id: inRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleAudioMute("input")
              }
            }
            PanelSlider {
              Layout.fillWidth: true
              value: root.statusInfo.inputPct !== undefined ? root.statusInfo.inputPct : 0
              minimum: 0
              maximum: 100
              step: 1
              integer: true
              trackColor: Util.alpha(root.foreground, 0.25)
              fillColor: root.selectedBorder
              knobColor: root.foreground
              onReleased: function(v) { root.setAudioVolume("input", v) }
              onRightClicked: root.toggleAudioMute("input")
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.hairline
              Layout.topMargin: Style.space(8)
              Layout.bottomMargin: Style.space(4)
              color: Util.alpha(root.foreground, 0.18)
            }
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(32)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(8)
                color: audRowMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.14) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
              }
              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                Text {
                  text: Controls.glyphFor("audio")
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: "Open audio settings"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: Controls.FOOTER_GLYPHS.chevron
                  color: root.foreground
                  opacity: 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea {
                id: audRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.openPopover = ""
                  root.openPanel("omarchy.audio", "Audio settings", Controls.glyphFor("audio"))
                }
              }
            }
          }

          // ------------------------------------------------ session & power
          ColumnLayout {
            visible: root.openPopover === "power"
            Layout.fillWidth: true
            spacing: 0

            // ---- idle timeouts (7.3): chips for the screensaver/lock
            // delays plus the Stay Awake inhibit switch. Off = 86400 s —
            // Omarchy's idle service has no true "never" (0 would fire
            // immediately), so the switch is the real off for both.
            Text {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.space(4)
              text: "IDLE"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.hairline
              Layout.bottomMargin: Style.space(6)
              color: Util.alpha(root.foreground, 0.18)
            }

            // One chip row per timer. `row` reaches the outer delegate
            // through the nested-delegate context chain (a parent-chain
            // walk is off by one here: chip → chips RowLayout → delegate).
            Repeater {
              model: [
                { title: "Screensaver", key: "screensaver", secs: root.idleScreensaver },
                { title: "Lock", key: "lock", secs: root.idleLock }
              ]
              delegate: ColumnLayout {
                required property var modelData
                readonly property var row: modelData
                Layout.fillWidth: true
                Layout.bottomMargin: Style.space(6)
                spacing: Style.space(3)

                RowLayout {
                  Layout.fillWidth: true
                  Text {
                    Layout.fillWidth: true
                    text: row.title
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: root.idleLabelFor(row.secs)
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)

                  Repeater {
                    model: root.idleChips
                    delegate: Rectangle {
                      id: chip
                      required property var modelData
                      readonly property bool selected: modelData.secs === row.secs
                      Layout.fillWidth: true
                      Layout.preferredHeight: Style.space(20)
                      radius: Style.space(6)
                      color: chipMouse.containsMouse
                        ? Util.alpha(root.selectedBorder, selected ? 0.32 : 0.16)
                        : (selected ? Util.alpha(root.selectedBorder, 0.22)
                                   : Util.alpha(root.foreground, 0.06))
                      border.width: selected ? Math.max(1, Style.space(1)) : 0
                      border.color: Util.alpha(root.selectedBorder, 0.6)
                      Behavior on color { ColorAnimation { duration: 100 } }

                      Text {
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: root.foreground
                        opacity: selected ? 1 : 0.65
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setIdleTimeout(row.key, chip.modelData.secs)
                      }
                    }
                  }
                }
              }
            }

            // Stay Awake: the same dispatch the control rows use (argv-only
            // omarchy-toggle-idle); state lives in controlStates. The
            // popover stays open — it's a toggle, not a navigation.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(28)

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                Text {
                  text: Controls.glyphFor("stayawake")
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  text: "Stay Awake"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Rectangle {
                  readonly property bool awakeOn:
                    root.controlStates["stayawake"] === "on"
                  Layout.preferredWidth: Style.space(26)
                  Layout.preferredHeight: Style.space(14)
                  radius: Style.space(7)
                  color: awakeOn ? Util.alpha(root.selectedBorder, 0.85)
                    : Util.alpha(root.foreground, 0.18)
                  Behavior on color { ColorAnimation { duration: 120 } }

                  Rectangle {
                    width: Style.space(10)
                    height: Style.space(10)
                    radius: Style.space(5)
                    color: root.background
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.awakeOn ? parent.width - width - Style.space(2)
                                      : Style.space(2)
                    Behavior on x { NumberAnimation { duration: 120 } }
                  }
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var a = Controls.actionById("stayawake")
                  if (a) root.runToggle(a)
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.hairline
              Layout.topMargin: Style.space(4)
              Layout.bottomMargin: Style.space(8)
              color: Util.alpha(root.foreground, 0.18)
            }

            Text {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.space(4)
              text: "SESSION & POWER"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.hairline
              Layout.bottomMargin: Style.space(4)
              color: Util.alpha(root.foreground, 0.18)
            }

            // Battery readout (laptops) — status only, not clickable.
            RowLayout {
              visible: !!root.statusInfo.battery
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(30)
              spacing: Style.space(8)

              Text {
                text: Controls.glyphFor("battery")
                color: root.foreground
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                Layout.fillWidth: true
                text: String(root.statusInfo.battery)
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Repeater {
              model: Controls.powerPopoverRows(root.controlStates)
              delegate: Item {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(32)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(8)
                  color: popRowMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.14) : "transparent"
                  Behavior on color { ColorAnimation { duration: 100 } }
                }
                RowLayout {
                  anchors.fill: parent
                  spacing: Style.space(8)

                  Text {
                    text: modelData.glyph
                    color: root.foreground
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    visible: modelData.kind === "panel"
                    text: Controls.FOOTER_GLYPHS.chevron
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: modelData.kind === "power" && modelData.confirm
                    text: "confirm"
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  id: popRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activatePowerRow(modelData)
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------ sudo confirmation
      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 30
        opened: root.confirmOpen
        message: root.pendingPower
          ? String(root.pendingPower.message)
          : root.detailCmd
            ? ("“" + root.detailCmd.bare + "” needs sudo.\nIt will open in a terminal so you can enter your password.")
            : "This command needs sudo."
        confirmText: root.pendingPower
          ? String(root.pendingPower.confirmText) : "Open in terminal"
        background: root.background
        foreground: root.foreground
        scrim: "transparent"
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onCanceled: root.cancelConfirm()
        onConfirmed: root.confirmPending()
      }
    }
  }

  // ---------------------------------------------------------- local parts

  // ---------------------------------------------------- footer rail tile
  // One control tile in the sticky footer: glyph (+ chevron for popover
  // tiles), accent while the toggle is on, hover tooltip with the live
  // state, section-divider hairline on each section's first tile.
  // --------------------------------------------------- home card (Phase 6b)
  // Dashboard tile: caption header + injected content column (default
  // property). Optional hover affordance (tint + pointing hand +
  // clicked signal) for actionable cards — hover feedback on every
  // clickable surface, per the footer lesson.
  component HomeCard: Rectangle {
    id: card
    default property alias content: col.data
    property alias overlays: overlayHost.data
    property alias caption: captionText.text
    property bool hoverable: false
    signal clicked()

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: Style.space(6)
    color: Util.alpha(root.foreground, 0.06)

    // Hover tint via HoverHandler — independent of any child MouseArea,
    // so the media buttons hover cleanly on top of the card's tint.
    HoverHandler { id: cardHover }
    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: card.hoverable && cardHover.hovered
        ? Util.alpha(root.selectedBorder, 0.12) : "transparent"
      Behavior on color { ColorAnimation { duration: 100 } }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: card.hoverable
      cursorShape: card.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: card.clicked()
    }

    // Full-bleed siblings (progress bar, seek zone) live BEHIND the
    // content column: visuals clear the column's margins, and buttons
    // inside the column still win the clicks over the seek zone.
    Item { id: overlayHost; anchors.fill: parent }

    ColumnLayout {
      id: col
      anchors.fill: parent
      anchors.margins: Style.space(5)
      spacing: Style.space(1)

      Text {
        id: captionText
        visible: text.length > 0
        color: root.foreground
        opacity: 0.5
        lineHeight: 1.0
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ------------------------------------------------- media button (6b.1)
  // Transport button inside the media strip: dimmed (and inert) when the
  // player can't do it — hover tint + pointing hand like every other
  // clickable surface.
  component MediaBtn: Rectangle {
    id: btn
    property string glyph: ""
    property bool available: true
    signal triggered()

    Layout.preferredWidth: Style.space(24)
    Layout.fillHeight: true
    radius: Style.space(4)
    color: btnMouse.containsMouse && btn.available
      ? Util.alpha(root.selectedBorder, 0.18) : "transparent"
    opacity: btn.available ? 1 : 0.35
    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      enabled: btn.available
      hoverEnabled: btn.available
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.triggered()
    }
  }

  component FooterTile: Item {
    id: tile
    property var tileData: null
    property bool activePopover: false
    property bool isFirst: false
    property bool tipReady: false
    signal triggered(var item)

    readonly property var td: tileData || ({})
    readonly property bool lit: root.controlStates[String(td.id || "")] === "on"
    readonly property string tipText: {
      var t = td
      var label = String(t.label || "")
      var id = String(t.id || "")
      var s = root.controlStates[id]
      if (s === "on" || s === "off") label += " — " + (s === "on" ? "On" : "Off")
      if (id === "wifi" && s === "on" && root.statusInfo.ssid)
        label += " · " + String(root.statusInfo.ssid)
      if (id === "audio") {
        var bits = []
        if (root.statusInfo.volume) bits.push(String(root.statusInfo.volume))
        if (root.statusInfo.micMuted) bits.push("mic muted")
        if (bits.length) label += " — " + bits.join(" · ")
      }
      if (id === "power" && root.statusInfo.battery)
        label += " — " + String(root.statusInfo.battery)
      if (t.popover) label += " · more"
      return label
    }

    implicitWidth: contentRow.implicitWidth + Style.space(24)
    implicitHeight: Style.space(36)

    // Hover/active background, kept behind the glyph row.
    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: tileMouse.containsMouse || tile.activePopover
        ? Util.alpha(root.selectedBorder, tile.activePopover ? 0.16 : 0.10)
        : "transparent"
      Behavior on color { ColorAnimation { duration: 100 } }
    }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        text: String(tile.td.glyph || "")
        color: tile.lit ? root.selectedBorder : root.foreground
        opacity: tile.lit ? 1.0 : 0.68
        font.family: root.fontFamily
        font.pixelSize: Style.font.body + Style.space(2)
      }
      Text {
        visible: !!tile.td.popover
        text: Controls.FOOTER_GLYPHS.chevron
        color: tile.activePopover ? root.selectedBorder : root.foreground
        opacity: tile.activePopover ? 1.0 : 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Section-divider hairline at each section's first tile.
    Rectangle {
      visible: !!tile.td.divider && !tile.isFirst
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.spacing.hairline
      height: parent.height - Style.space(16)
      color: Util.alpha(root.foreground, 0.18)
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        tile.tipReady = false
        tile.triggered(tile)
      }
      onContainsMouseChanged: {
        if (containsMouse) tipTimer.restart()
        else { tipTimer.stop(); tile.tipReady = false }
      }
    }

    // Hover tooltip (0.42s delay): the same live state the detail card
    // shows, so the rail is readable without clicking.
    Timer {
      id: tipTimer
      interval: 420
      onTriggered: tile.tipReady = true
    }

    Rectangle {
      id: tip
      visible: tileMouse.containsMouse && tile.tipReady && tile.tipText.length > 0
      z: 5
      // Clamped inside the card so the first/last tile's tip never
      // hangs off the edge.
      x: Math.max(Style.space(10) - tile.x,
        Math.min(tile.parent ? tile.parent.width - width - Style.space(10) - tile.x : 0,
          tile.width / 2 - width / 2))
      anchors.bottom: parent.top
      anchors.bottomMargin: Style.space(6)
      width: tipLabel.implicitWidth + Style.space(22)
      height: tipLabel.implicitHeight + Style.space(14)
      color: root.background
      border.color: root.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.space(8)

      Text {
        id: tipLabel
        anchors.centerIn: parent
        text: tile.tipText
        color: root.foreground
        opacity: 0.9
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ArgPill: BorderSurface {
    required property string label
    implicitWidth: Math.min(pillText.implicitWidth + Style.space(22), Style.space(250))
    implicitHeight: Style.space(26)
    radius: root.cornerRadius
    color: Util.alpha(root.foreground, 0.07)
    borderSpec: Border.none()

    Text {
      id: pillText
      anchors.centerIn: parent
      width: parent.width - Style.space(16)
      text: parent.label
      color: root.foreground
      opacity: 0.85
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component ActionButton: BorderSurface {
    id: btn
    required property string label
    property bool primary: false
    property bool focused: false
    signal triggered()

    implicitHeight: Style.space(40)
    implicitWidth: btnText.implicitWidth + Style.space(40)
    radius: root.cornerRadius
    color: btn.primary
      ? root.selectedBackground
      : (btnHover.hovered ? Util.alpha(root.foreground, 0.12) : Util.alpha(root.foreground, 0.06))
    borderSpec: Border.surfaceSpec("menu", "border", btn.focused ? root.selectedBorder : root.border, Math.max(1, Style.space(1)))

    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? root.selectedText : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: btn.primary ? Font.DemiBold : Font.Normal
    }

    HoverHandler { id: btnHover }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.triggered()
    }
  }
}
