// Controls.js — Phase 5 "Deep Omarchy": the quick-action / panel /
// power-session table and its pure helpers (query matching, relative
// time, history shaping). Pure data + pure functions: node-testable,
// no I/O. Runtime commands and live state live in Palette.qml.
//
// Mirrors of Omarchy machinery (re-check when omarchy updates — paths
// recorded in ROADMAP.md):
//   ACTIONS[].cmd       the exact `action` strings from
//                       /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc
//                       (lock / suspend / hibernate / logout / reboot /
//                       shutdown — same commands the built-in menu runs)
//   ACTIONS[].toggleCmd the `trigger.toggle.*` action strings from the
//                       same menu file
//   ACTIONS[].panel     registered shell plugin ids (omarchy-shell shell
//                       listPlugins), opened with
//                       `omarchy-shell shell toggle <id>`
//
// Glyphs are codepoints verified BY GLYPH NAME against the installed
// JetBrainsMono Nerd Font (via /tmp/opencode/glyphnames.py); the
// power/session ones are the very characters omarchy-menu.jsonc uses.

var SECTION_TOGGLES = "toggles"
var SECTION_PANELS = "panels"
var SECTION_SESSION = "session"
// Super+Space parity rows (8.6): tools = run/panel actions the menu
// exposes; learn = doc links, which stay search-only (not browsed).
var SECTION_TOOLS = "tools"
var SECTION_LEARN = "learn"

var ACTIONS = [
  // ---------------------------------------------------- quick toggles
  { id: "dnd", label: "Do Not Disturb", glyph: "󰂛", kind: "toggle",
    section: SECTION_TOGGLES,
    toggleCmd: "omarchy-toggle-notification-silencing",
    keywords: ["dnd", "disturb", "notification", "notifications",
      "silence", "quiet", "do not disturb"] },
  { id: "nightlight", label: "Night Light", glyph: "󰔎", kind: "toggle",
    section: SECTION_TOGGLES,
    toggleCmd: "omarchy-toggle-nightlight",
    keywords: ["nightlight", "night", "warm", "sunset", "gamma",
      "hyprsunset", "temperature"] },
  { id: "wifi", label: "Wi-Fi", glyph: "󰖩", kind: "toggle",
    section: SECTION_TOGGLES,
    setOn: "nmcli radio wifi on", setOff: "nmcli radio wifi off",
    keywords: ["wifi", "wi-fi", "wireless"] },
  { id: "bluetooth", label: "Bluetooth", glyph: "󰂯", kind: "toggle",
    section: SECTION_TOGGLES,
    setOn: "bluetoothctl power on", setOff: "bluetoothctl power off",
    keywords: ["bluetooth", "bt"] },
  { id: "stayawake", label: "Stay Awake", glyph: "󰅶", kind: "toggle",
    section: SECTION_TOGGLES,
    toggleCmd: "omarchy-toggle-idle",
    keywords: ["awake", "caffeine", "idle", "stay awake"] },
  { id: "screensaver", label: "Screensaver", glyph: "󱄄", kind: "toggle",
    section: SECTION_TOGGLES,
    toggleCmd: "omarchy-toggle-screensaver",
    keywords: ["screensaver", "screensave"] },

  // --------------------------------------------- settings panels (shell)
  { id: "audio", label: "Audio settings", glyph: "󰕾", kind: "panel",
    section: SECTION_PANELS, panel: "omarchy.audio",
    desc: "Output, input, and volume controls",
    keywords: ["volume", "audio", "sound", "output", "input", "sink",
      "microphone", "mic", "pipewire"] },
  { id: "network", label: "Network settings", glyph: "󰌗", kind: "panel",
    section: SECTION_PANELS, panel: "omarchy.network",
    desc: "Connections, Wi-Fi, and VPN",
    keywords: ["network", "connection", "ethernet", "vpn", "ip", "dns"] },
  { id: "display", label: "Display settings", glyph: "󰍹", kind: "panel",
    section: SECTION_PANELS, panel: "omarchy.monitor",
    desc: "Monitors, arrangement, and scale",
    keywords: ["display", "monitor", "screen", "resolution",
      "arrangement", "scale"] },
  { id: "battery", label: "Power & battery", glyph: "󰁹", kind: "panel",
    section: SECTION_PANELS, panel: "omarchy.power",
    desc: "Battery, power profile, and charging",
    keywords: ["battery", "power", "charge", "charging", "profile",
      "performance", "upower"] },

  // ------------------------------ tools (8.6: Super+Space menu parity)
  // Everything here exists in omarchy-menu.jsonc; tests/parity.test.js
  // asserts the cmd strings byte-match the menu's own action strings.
  { id: "speedtest", label: "Network speed test", glyph: "󰓅", kind: "panel",
    section: SECTION_TOOLS, panel: "omarchy.speedtest",
    desc: "Measure download and upload speed",
    keywords: ["speed", "speedtest", "speed test", "internet", "bandwidth",
      "download", "upload", "fast"] },
  { id: "diskspeedtest", label: "Disk speed test", glyph: "󰋊", kind: "panel",
    section: SECTION_TOOLS, panel: "omarchy.disk-speedtest",
    desc: "Benchmark local disk read and write",
    keywords: ["disk", "disk speed", "ssd", "hdd", "benchmark", "io"] },
  { id: "colorpicker", label: "Pick color", glyph: "󰃉", kind: "run",
    section: SECTION_TOOLS, cmd: "pkill hyprpicker || hyprpicker -a",
    desc: "Sample a screen color to the clipboard",
    keywords: ["color", "colour", "picker", "hyprpicker", "eyedropper",
      "hex"] },
  { id: "changepassword", label: "Change password", glyph: "󰌋", kind: "run",
    section: SECTION_TOOLS,
    cmd: "omarchy-launch-floating-terminal-with-presentation passwd",
    desc: "Change your user password in a floating terminal",
    keywords: ["password", "passwd", "credential", "change password"] },
  { id: "switchtheme", label: "Switch theme", glyph: "󰸌", kind: "run",
    section: SECTION_TOOLS,
    cmd: 'theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set "$theme"',
    desc: "Pick a theme from previews and apply it",
    keywords: ["theme", "themes", "switch theme", "appearance", "colorscheme"] },
  { id: "switchbackground", label: "Switch background", glyph: "󰏍", kind: "run",
    section: SECTION_TOOLS,
    cmd: 'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set "$background"',
    desc: "Pick a wallpaper and apply it",
    keywords: ["background", "wallpaper", "bg", "desktop background"] },
  { id: "switchunlock", label: "Switch unlock screen", glyph: "󰟵", kind: "run",
    section: SECTION_TOOLS,
    cmd: 'unlock=$(omarchy-plymouth-switcher); if [[ $unlock == default ]]; then omarchy-launch-floating-terminal-with-presentation omarchy-plymouth-reset; elif [[ -n $unlock ]]; then omarchy-launch-floating-terminal-with-presentation "omarchy-plymouth-set-by-theme $(printf %q "$unlock")"; fi',
    desc: "Pick the unlock / boot splash style",
    keywords: ["unlock", "plymouth", "splash", "boot splash", "lock screen style"] },

  // --------------------- learn (8.6: search-only doc links, menu parity)
  { id: "learn-omarchy", label: "Omarchy manual", glyph: "󰋖", kind: "run",
    section: SECTION_LEARN,
    cmd: "omarchy-launch-webapp 'https://omarchy.org/manual/'",
    desc: "Open the Omarchy manual",
    keywords: ["omarchy", "manual", "docs", "documentation", "guide"] },
  { id: "learn-hyprland", label: "Hyprland wiki", glyph: "󰍙", kind: "run",
    section: SECTION_LEARN,
    cmd: "omarchy-launch-webapp 'https://wiki.hypr.land/'",
    desc: "Open the Hyprland wiki",
    keywords: ["hyprland", "hypr", "wiki", "compositor"] },
  { id: "learn-arch", label: "Arch wiki", glyph: "󰣇", kind: "run",
    section: SECTION_LEARN,
    cmd: "omarchy-launch-webapp 'https://wiki.archlinux.org/title/Main_page'",
    desc: "Open the Arch Linux wiki",
    keywords: ["arch", "archlinux", "arch wiki", "wiki"] },
  { id: "learn-lazyvim", label: "LazyVim keymaps", glyph: "󰌄", kind: "run",
    section: SECTION_LEARN,
    cmd: "omarchy-launch-webapp 'https://www.lazyvim.org/keymaps'",
    desc: "Open the LazyVim keymaps reference",
    keywords: ["lazyvim", "vim", "neovim", "nvim", "keymaps", "editor keys"] },
  { id: "learn-bash", label: "Bash cheatsheet", glyph: "󱆃", kind: "run",
    section: SECTION_LEARN,
    cmd: "omarchy-launch-webapp 'https://devhints.io/bash'",
    desc: "Open the Bash cheatsheet",
    keywords: ["bash", "shell", "cheatsheet", "devhints"] },

  // ------------------------------------------- power / session (menu!)
  { id: "lock", label: "Lock", glyph: "", kind: "power",
    section: SECTION_SESSION, confirm: false,
    cmd: "omarchy-system-lock", body: "Lock this session now.",
    keywords: ["lock", "lockscreen", "lock screen"] },
  { id: "suspend", label: "Suspend", glyph: "󰒲", kind: "power",
    section: SECTION_SESSION, confirm: true,
    cmd: "systemctl suspend",
    confirmMsg: "Suspend now?\nOpen apps stay running in memory.",
    keywords: ["suspend", "sleep", "doze"] },
  { id: "hibernate", label: "Hibernate", glyph: "󰤁", kind: "power",
    section: SECTION_SESSION, confirm: true,
    cmd: "systemctl hibernate",
    confirmMsg: "Hibernate now?\nOpen apps are written to disk.",
    keywords: ["hibernate", "hibernation"] },
  { id: "logout", label: "Log out", glyph: "󰍃", kind: "power",
    section: SECTION_SESSION, confirm: true,
    cmd: "omarchy-system-logout",
    confirmMsg: "Log out now?\nUnsaved work in open apps will be lost.",
    keywords: ["logout", "log out", "signout", "sign out"] },
  { id: "reboot", label: "Reboot", glyph: "󰜉", kind: "power",
    section: SECTION_SESSION, confirm: true,
    cmd: "omarchy-system-reboot",
    confirmMsg: "Reboot now?\nUnsaved work in open apps will be lost.",
    keywords: ["reboot", "restart"] },
  { id: "shutdown", label: "Shut down", glyph: "󰐥", kind: "power",
    section: SECTION_SESSION, confirm: true,
    cmd: "omarchy-system-shutdown",
    confirmMsg: "Shut down now?\nUnsaved work in open apps will be lost.",
    keywords: ["shutdown", "shut down", "poweroff", "power off"] }
]

// Group + status-row glyphs (same verified provenance as ACTIONS).
var GROUP_GLYPHS = { controls: "󰘮", history: "󰋚" }
var STATUS_GLYPHS = {
  battery: "󰁹", volume: "󰕾", system: "󰘚",
  connection: "󰌗", wifi: "󰖩"
}

// News group glyphs (Phase 6): verified by name with glyphnames.py —
//   md-newspaper U+F0395   md-refresh U+F0450
var NEWS_GLYPHS = {
  news: "󰎕",
  refresh: "󰑐",
  edit: "󰏫",
  add: "󰐕"
}

// Media transport glyphs for the now-playing tile (6b.1). Raw UTF-8,
// codepoint-verified by tests/media.test.sh — never trusted by eye:
// fa-backward · md-play · md-pause · fa-forward · md-music.
var MEDIA_GLYPHS = {
  prev: "",
  play: "󰐊",
  pause: "󰏤",
  next: "",
  music: "󰝚"
}

// Recents dedupe (user rule): the strip may never show one command or app
// twice, and a re-use promotes it to the front. Callers pass entries sorted
// most-recent-first, each carrying an identity id (the QML side resolves an
// app and any same-named command to one key); the first — newest — entry
// per identity wins and older twins drop.
// Web-link gate for Qt.openUrlExternally: only scheme-correct,
// whitespace-free http(s) URLs ever leave the palette (article links
// are feed content; search URLs are built locally — both pass through
// here so nothing else can slip out: file://, javascript:, embedded
// newlines).
function isWebUrl(u) {
  var s = String(u == null ? "" : u).trim()
  return /^https?:\/\/[^\s]+$/i.test(s)
}

function dedupeRecentEntries(entries) {
  // null-prototype map: data-keyed (routes/ids may be anything) — a
  // literal "__proto__" key must not read Object.prototype.
  var seen = Object.create(null)
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    var k = e.id !== undefined && e.id !== null && String(e.id) !== ""
      ? String(e.id) : String(e.route)
    if (seen[k]) continue
    seen[k] = true
    out.push(e.route)
  }
  return out
}

// Kinds that act immediately on Enter (no Run/Terminal/Copy button hop).
function isInstantKind(kind) {
  return kind === "calc" || kind === "convert" || kind === "web"
    || kind === "agent" || kind === "toggle" || kind === "panel"
    || kind === "power" || kind === "status" || kind === "history"
    // 8.6 fix: menu-parity run rows must fire on Enter like the other
    // control kinds — without this Enter parked on an empty detail pane.
    || kind === "run"
    || kind === "newsitem" || kind === "newsrefresh"
    || kind === "newsfeeds" || kind === "feedadd"
    // Phase-7 providers: focus / paste / open / copy-the-answer.
    || kind === "window" || kind === "clip" || kind === "file"
    || kind === "dict"
}

function normalize(s) {
  return String(s == null ? "" : s).toLowerCase().trim()
}

function actionById(id) {
  for (var i = 0; i < ACTIONS.length; i++)
    if (ACTIONS[i].id === id) return ACTIONS[i]
  return null
}

function glyphFor(id) {
  var a = actionById(id)
  return a ? a.glyph : "󰒓"
}

// Rank curated actions against a query: label-exact (4) > keyword-exact
// (3) > keyword-prefix (2) > keyword-substring (1). Prefix/substring need
// ≥3 chars so two-letter noise never fires them; exact keywords ("bt",
// "dnd", "mic") still match short. Returns at most 3 actions, best first.
function matchActions(query) {
  var q = normalize(query)
  if (!q || q.length > 60) return []
  var hits = []
  for (var i = 0; i < ACTIONS.length; i++) {
    var a = ACTIONS[i]
    var best = 0
    if (normalize(a.label) === q) best = 4
    for (var k = 0; k < a.keywords.length && best < 4; k++) {
      var kw = normalize(a.keywords[k])
      if (q === kw) { if (best < 3) best = 3 }
      else if (q.length >= 3 && kw.indexOf(q) === 0) { if (best < 2) best = 2 }
      else if (q.length >= 3 && kw.indexOf(q) >= 0) { if (best < 1) best = 1 }
    }
    if (best > 0) hits.push({ action: a, score: best, index: i })
  }
  hits.sort(function (x, y) {
    return y.score - x.score || x.index - y.index
  })
  var out = []
  for (var h = 0; h < hits.length && h < 3; h++) out.push(hits[h].action)
  return out
}

// "on"/"off" as the user reads it; "" when unprobed (row builder falls
// back to "Toggle"). Wi-Fi appends the SSID while on.
function stateLabel(id, states, ssid) {
  var s = states && states[id]
  if (s !== "on" && s !== "off") return ""
  if (id === "wifi" && s === "on" && ssid) return "On · " + ssid
  return s === "on" ? "On" : "Off"
}

// State AFTER flipping (for OSD copy). "" when the current state is
// unknown (state-less scripts like the screensaver toggle).
function nextState(id, states) {
  var s = states && states[id]
  if (s === "on") return "off"
  if (s === "off") return "on"
  return ""
}

// Exact command that flips a toggle. Scripts with a single meaning
// (dnd/nightlight/stayawake/screensaver) run as-is; radio toggles take
// the direction from live state. All fixed strings — never interpolated
// user input (no injection surface).
function toggleCommand(a, states) {
  if (!a) return ""
  if (a.toggleCmd) return a.toggleCmd
  var current = states && states[a.id]
  return current === "on" ? a.setOff : a.setOn
}

// Argv form of a toggle for Quickshell.execDetached — the runtime path
// takes these arrays, so no shell ever parses a Phase-5 command string.
function toggleArgv(a, states) {
  if (!a) return []
  if (a.toggleCmd) return [a.toggleCmd]
  var current = states && states[a.id]
  var cmd = current === "on" ? a.setOff : a.setOn
  return String(cmd).split(" ")
}

// Argv form of a session action (cmd may be two tokens, e.g.
// "systemctl suspend") — fixed table constants, so splitting is exact.
function powerArgv(a) {
  if (!a || !a.cmd) return []
  return String(a.cmd).split(" ")
}

function relativeTime(ts, now) {
  var s = (Number(now) - Number(ts)) / 1000
  if (!(s >= 0)) return "just now"
  if (s < 60) return "just now"
  if (s < 60 * 60) return Math.floor(s / 60) + "m ago"
  if (s < 24 * 60 * 60) return Math.floor(s / 3600) + "h ago"
  if (s < 7 * 24 * 60 * 60) return Math.floor(s / 86400) + "d ago"
  return Math.floor(s / (7 * 24 * 60 * 60)) + "w ago"
}

// Usage.json → launch timeline, newest first, capped. Entries need both
// a count and a timestamp (junk keys never qualify).
function historyEntries(usage) {
  var out = []
  if (!usage || typeof usage !== "object") return out
  for (var route in usage) {
    var u = usage[route]
    if (!u || typeof u !== "object") continue
    var count = Number(u.count) || 0
    var last = Number(u.last) || 0
    if (count > 0 && last > 0) out.push({ route: route, count: count, last: last })
  }
  out.sort(function (a, b) { return b.last - a.last })
  return out.slice(0, 40)
}

// ------------------------------------------------------------------
// Footer rail model (Phase 5+): the sticky control strip along the
// card's bottom edge. One rule drives every tile: a tile with a SINGLE
// control acts directly; a tile aggregating several related controls
// (audio, power) opens a mini-popover instead — the "toggle vs dialog"
// split. footerTiles() is a pure function of the probed state, so node
// tests gate the wired-only/desktop differences and the off-glyph swaps.
//
// Glyph provenance (verified BY NAME with /tmp/opencode/glyphnames.py):
//   md-wifi_off U+F05AA   md-bluetooth_off U+F00B2
//   md-volume_off U+F0581 md-microphone U+F036C md-microphone_off U+F036D
//   volume reuses STATUS_GLYPHS.volume (same verified bytes)
var FOOTER_GLYPHS = {
  wifiOff: "󰖪", btOff: '󰂲', volumeOff: '󰖁',
  volume: STATUS_GLYPHS.volume, mic: '󰍬', micOff: '󰍭',
  chevron: "\u25be"
}

// The footer tile list. Fields:
//   id        identity ("wired"/"net" are footer-only variants)
//   section   divider group: alerts | connectivity | media | session
//   glyph     FINAL glyph given probed state (off-variants swapped in)
//   label     tooltip text basis
//   actionId  ACTIONS id to run directly ("" for popover tiles)
//   popover   "" | "audio" | "power"
//   divider   true when the tile opens a new section (draws a hairline)
// Gating mirrors status.sh exactly: the Wi-Fi tile exists ONLY when a
// wifi device was probed (states.wifi present); wired-only boxes get a
// "Wired" tile that opens the network panel instead; Bluetooth only
// shows when bluetoothctl answered.
function footerTiles(states, info) {
  var st = states || {}
  var inf = info || {}
  var tiles = []

  // ---- alerts & rest: the stateful toggles, always present
  var alertIds = ["dnd", "nightlight", "stayawake", "screensaver"]
  for (var i = 0; i < alertIds.length; i++) {
    var a = actionById(alertIds[i])
    if (a) tiles.push({ id: a.id, section: "alerts", glyph: a.glyph,
      label: a.label, actionId: a.id, popover: "", divider: i === 0 })
  }

  // ---- connectivity: wifi toggle, or wired/net opener on boxes
  // without a wifi device
  var conn = []
  if (st.wifi === "on" || st.wifi === "off") {
    var w = actionById("wifi")
    conn.push({ id: "wifi", section: "connectivity",
      glyph: st.wifi === "off" ? FOOTER_GLYPHS.wifiOff : w.glyph,
      label: "Wi-Fi", actionId: "wifi", popover: "" })
  } else if (inf.connection) {
    conn.push({ id: "wired", section: "connectivity",
      glyph: STATUS_GLYPHS.connection,
      label: "Wired \u00b7 " + inf.connection,
      actionId: "network", popover: "" })
  } else {
    conn.push({ id: "net", section: "connectivity",
      glyph: actionById("network").glyph,
      label: "Network", actionId: "network", popover: "" })
  }
  if (st.bluetooth === "on" || st.bluetooth === "off") {
    var b = actionById("bluetooth")
    conn.push({ id: "bluetooth", section: "connectivity",
      glyph: st.bluetooth === "off" ? FOOTER_GLYPHS.btOff : b.glyph,
      label: "Bluetooth", actionId: "bluetooth", popover: "" })
  }
  for (var c = 0; c < conn.length; c++) {
    conn[c].divider = c === 0
    tiles.push(conn[c])
  }

  // ---- media: audio is the multi-control domain (mutes + volume
  // sliders + panel) -> popover; display opens its panel directly
  tiles.push({ id: "audio", section: "media", divider: true,
    glyph: inf.outputMuted ? FOOTER_GLYPHS.volumeOff
      : actionById("audio").glyph,
    label: "Audio", actionId: "", popover: "audio" })
  var d = actionById("display")
  tiles.push({ id: "display", section: "media", divider: false,
    glyph: d.glyph, label: "Display", actionId: "display", popover: "" })

  // ---- session: one power tile; the popover carries battery + every
  // gated session action
  tiles.push({ id: "power", section: "session", divider: true,
    glyph: actionById("battery").glyph, label: "Session",
    actionId: "", popover: "power" })
  return tiles
}

// Power popover rows (pure): the power panel first, then Lock and the
// confirmed session actions — gated exactly like the Controls group
// (st.suspend/st.hibernate = "hidden" when the menu's when: clauses
// fail). kind/confirm route the QML into openPanel / the shared
// confirm dialog.
function powerPopoverRows(states) {
  var st = states || {}
  var rows = []
  var panel = actionById("battery")
  if (panel) rows.push({ id: "battery", glyph: panel.glyph,
    label: panel.label, kind: "panel", confirm: false })
  var ids = ["lock", "suspend", "hibernate", "logout", "reboot", "shutdown"]
  for (var i = 0; i < ids.length; i++) {
    var a = actionById(ids[i])
    if (!a) continue
    if (st[a.id] === "hidden") continue
    rows.push({ id: a.id, glyph: a.glyph, label: a.label,
      kind: "power", confirm: !!a.confirm })
  }
  return rows
}

// Audio popover channels: WirePlumber's default endpoints — fixed
// table constants, never interpolated.
var AUDIO_CHANNELS = {
  output: "@DEFAULT_AUDIO_SINK@",
  input: "@DEFAULT_AUDIO_SOURCE@"
}

// Mute-toggle argv for Quickshell.execDetached (no shell parses it).
function muteToggleArgv(channel) {
  var ep = AUDIO_CHANNELS[channel]
  if (!ep) return []
  return ["wpctl", "set-mute", ep, "toggle"]
}

// Set-volume argv; pct is clamped to the slider's 0-100 range. A
// non-finite value yields [] (no-op) rather than a junk command.
function setVolumeArgv(channel, pct) {
  var ep = AUDIO_CHANNELS[channel]
  if (!ep) return []
  var n = Math.round(Number(pct))
  if (!isFinite(n)) return []
  n = Math.max(0, Math.min(100, n))
  return ["wpctl", "set-volume", ep, n + "%"]
}
