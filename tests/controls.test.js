// controls.test.js — node unit tests for Controls.js (Phase 5 quick
// actions, panels, power/session, timeline helpers).
// Run: node tests/controls.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level declarations and no exports — eval into scope,
// same pattern as providers.test.js / model.test.js.
// eslint-disable-next-line no-eval
eval(fs.readFileSync(path.join(__dirname, "..", "Controls.js"), "utf8"))

let passed = 0
let failed = 0

function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    passed++
  } else {
    failed++
    console.error(`FAIL ${name}\n  expected: ${e}\n  actual:   ${a}`)
  }
}

function ids(list) {
  return list.map((a) => a.id)
}

// Nerd Font glyphs above the BMP are surrogate pairs in JS strings —
// codePointAt reads the real codepoint (charCodeAt would return half).
function cp(s) {
  return s.codePointAt(0)
}

// ------------------------------------------------------- table integrity
check("unique action ids",
  new Set(ACTIONS.map((a) => a.id)).size, ACTIONS.length)

for (const a of ACTIONS) {
  check(`table: ${a.id} has kind`, typeof a.kind === "string" && a.kind.length > 0, true)
  check(`table: ${a.id} has non-empty keywords`,
    Array.isArray(a.keywords) && a.keywords.length > 0
      && a.keywords.every((k) => typeof k === "string" && k.length > 0), true)
  check(`table: ${a.id} has glyph`, typeof a.glyph === "string" && a.glyph.length > 0, true)
  if (a.kind === "toggle") {
    const shaped = !!a.toggleCmd !== !!(a.setOn && a.setOff)
    check(`table: ${a.id} toggle shape (script XOR radio setOn/setOff)`, shaped, true)
  }
  if (a.kind === "panel") {
    check(`table: ${a.id} panel id + desc`,
      [typeof a.panel, typeof a.desc].every((t) => t === "string"), true)
    check(`table: ${a.id} panel plugin is omarchy.*`,
      a.panel.indexOf("omarchy.") === 0, true)
  }
  if (a.kind === "power") {
    check(`table: ${a.id} has menu-style cmd`, typeof a.cmd === "string" && a.cmd.length > 0, true)
    if (a.confirm) {
      check(`table: ${a.id} confirm carries confirmMsg`,
        typeof a.confirmMsg === "string" && a.confirmMsg.includes("\n"), true)
    }
  }
}

// Lock is the only session action that may run without confirmation.
check("table: only lock is confirm-free",
  ACTIONS.filter((a) => a.kind === "power" && !a.confirm).map((a) => a.id), ["lock"])
check("table: every other power action confirms",
  ACTIONS.filter((a) => a.kind === "power" && a.confirm).length, 5)

// -------------------------------------------------------- menu drift guard
// The session/toggle commands must be EXACTLY what omarchy-menu.jsonc
// runs — the menu file is the source of truth (skip if absent).
const menuPath = "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
if (fs.existsSync(menuPath)) {
  const src = fs.readFileSync(menuPath, "utf8")
  const pairs = {
    lock: "system.lock",
    suspend: "system.suspend",
    hibernate: "system.hibernate",
    logout: "system.logout",
    reboot: "system.reboot",
    shutdown: "system.shutdown",
  }
  for (const [id, key] of Object.entries(pairs)) {
    const m = src.match(new RegExp(`"${key}":\\s*\\{[^}]*"action":"([^"]+)"`))
    check(`menu sync: ${id} cmd`, m ? m[1] : null, actionById(id).cmd)
  }
  const toggles = {
    dnd: "trigger.toggle.notifications",
    nightlight: "trigger.toggle.nightlight",
    stayawake: "trigger.toggle.idle-lock",
    screensaver: "trigger.toggle.screensaver",
  }
  for (const [id, key] of Object.entries(toggles)) {
    const m = src.match(new RegExp(`"${key}":\\s*\\{[^}]*"action":"([^"]+)"`))
    check(`menu sync: ${id} toggleCmd`, m ? m[1] : null, actionById(id).toggleCmd)
  }
} else {
  console.log("note: menu file absent — drift guard skipped")
}

// ------------------------------------------------------------ matchActions
check("match: exact short keyword dnd", ids(matchActions("dnd")), ["dnd"])
check("match: exact 2-char keyword bt", ids(matchActions("bt")), ["bluetooth"])
check("match: night → nightlight first", ids(matchActions("night")), ["nightlight"])
check("match: screen → display before screensaver",
  ids(matchActions("screen")).slice(0, 2), ["display", "screensaver"])
check("match: sleep → suspend, stayawake absent",
  ids(matchActions("sleep")), ["suspend"])
check("match: power → battery panel first, shutdown second",
  ids(matchActions("power")), ["battery", "shutdown"])
check("match: poweroff → shutdown only", ids(matchActions("poweroff")), ["shutdown"])
check("match: restart → reboot", ids(matchActions("restart")), ["reboot"])
check("match: monitor → display", ids(matchActions("monitor")), ["display"])
check("match: label-ish query log out → logout", ids(matchActions("log out")), ["logout"])
check("match: mic → audio panel", ids(matchActions("mic")), ["audio"])
check("match: volume → audio panel", ids(matchActions("volume")), ["audio"])
check("match: idempotent case/space folding",
  ids(matchActions("  DND  ")), ["dnd"])

check("match: empty query", matchActions(""), [])
check("match: whitespace query", matchActions("   "), [])
check("match: 1-char query stays quiet", matchActions("a"), [])
check("match: 2-char non-keyword stays quiet", matchActions("xy"), [])
check("match: over-long query rejected", matchActions("x".repeat(61)), [])

// Injection-shaped input must simply not match (no action row, and the
// builders never interpolate query text into commands at all).
check("match: shell metacharacters never match",
  ids(matchActions("dnd; rm -rf /")), [])
check("match: command substitution never matches",
  ids(matchActions("$(reboot)")), [])

// Ranking: exact beats prefix beats substring, stable table order on ties.
{
  const before = ACTIONS.length
  ACTIONS.push(
    { id: "t_sub", label: "Sub", glyph: "x", kind: "toggle", keywords: ["zzz substring here"] },
    { id: "t_pre", label: "Pre", glyph: "x", kind: "toggle", keywords: ["zzzword"] },
    { id: "t_exc", label: "Exc", glyph: "x", kind: "toggle", keywords: ["zzz"] },
    { id: "t_extra", label: "Extra", glyph: "x", kind: "toggle", keywords: ["zzz"] },
  )
  // t_sub's keyword STARTS with "zzz", so it (legitimately) matches by
  // prefix too — exact rows still rank first, substring can't outrank.
  check("match: rank exact > prefix > substring",
    ids(matchActions("zzz")), ["t_exc", "t_extra", "t_sub"])
  check("match: cap at 3 rows", matchActions("zzz").length, 3)
  check("match: prefix ranks above substring",
    ids(matchActions("zzzw")), ["t_pre"])
  check("match: substring-only (≥3) still matches",
    ids(matchActions("string here")), ["t_sub"])
  ACTIONS.length = before
  check("match: synthetic actions removed", matchActions("zzz"), [])
}

// ------------------------------------------------------ toggle/panel/power
check("toggle: script actions run as-is (dnd)",
  toggleCommand(actionById("dnd"), { dnd: "off" }),
  "omarchy-toggle-notification-silencing")
check("toggle: script actions ignore state (nightlight)",
  toggleCommand(actionById("nightlight"), { nightlight: "on" }),
  "omarchy-toggle-nightlight")
check("toggle: wifi on → turn off",
  toggleCommand(actionById("wifi"), { wifi: "on" }),
  "nmcli radio wifi off")
check("toggle: wifi off → turn on",
  toggleCommand(actionById("wifi"), { wifi: "off" }),
  "nmcli radio wifi on")
check("toggle: bluetooth on → power off",
  toggleCommand(actionById("bluetooth"), { bluetooth: "on" }),
  "bluetoothctl power off")
check("toggle: unknown action → empty command", toggleCommand(null, {}), "")

// Runtime path: argv arrays only (Quickshell.execDetached) — no shell.
check("argv: script toggle is one token",
  toggleArgv(actionById("dnd"), { dnd: "off" }),
  ["omarchy-toggle-notification-silencing"])
check("argv: nightlight ignores state",
  toggleArgv(actionById("nightlight"), { nightlight: "on" }),
  ["omarchy-toggle-nightlight"])
check("argv: wifi on → radio off",
  toggleArgv(actionById("wifi"), { wifi: "on" }),
  ["nmcli", "radio", "wifi", "off"])
check("argv: wifi off → radio on",
  toggleArgv(actionById("wifi"), { wifi: "off" }),
  ["nmcli", "radio", "wifi", "on"])
check("argv: bluetooth on → power off",
  toggleArgv(actionById("bluetooth"), { bluetooth: "on" }),
  ["bluetoothctl", "power", "off"])
check("argv: unknown toggle → empty", toggleArgv(null, {}), [])
check("argv: lock is one token",
  powerArgv(actionById("lock")), ["omarchy-system-lock"])
check("argv: suspend splits into two tokens",
  powerArgv(actionById("suspend")), ["systemctl", "suspend"])
check("argv: reboot exact menu command",
  powerArgv(actionById("reboot")), ["omarchy-system-reboot"])
check("argv: shutdown exact menu command",
  powerArgv(actionById("shutdown")), ["omarchy-system-shutdown"])
check("argv: unknown power → empty", powerArgv(null), [])
check("argv: no shell metacharacters anywhere in runtime argv",
  [...toggleArgv(actionById("dnd"), {}), ...toggleArgv(actionById("wifi"), { wifi: "on" }),
   ...powerArgv(actionById("reboot"))].some((t) => /[;&|`$><]/.test(t)), false)

check("nextState: on→off", nextState("dnd", { dnd: "on" }), "off")
check("nextState: off→on", nextState("dnd", { dnd: "off" }), "on")
check("nextState: unknown → empty", nextState("screensaver", {}), "")
check("nextState: no states at all", nextState("dnd", null), "")

check("stateLabel: plain on", stateLabel("dnd", { dnd: "on" }), "On")
check("stateLabel: plain off", stateLabel("dnd", { dnd: "off" }), "Off")
check("stateLabel: wifi on appends ssid",
  stateLabel("wifi", { wifi: "on" }, "HomeNet"), "On · HomeNet")
check("stateLabel: wifi off drops ssid",
  stateLabel("wifi", { wifi: "off" }, "HomeNet"), "Off")
check("stateLabel: unprobed → empty",
  stateLabel("screensaver", { dnd: "on" }), "")

check("actionById: known", actionById("reboot").label, "Reboot")
check("actionById: unknown", actionById("nope"), null)

// ------------------------------------------------------------ glyph proof
// Codepoints as verified by glyph name against the installed Nerd Font.
check("glyph: dnd = md-bell_off U+F009B", cp(actionById("dnd").glyph), 0xf009b)
check("glyph: nightlight = md-theme_light_dark U+F050E",
  cp(actionById("nightlight").glyph), 0xf050e)
check("glyph: wifi = md-wifi U+F05A9", cp(actionById("wifi").glyph), 0xf05a9)
check("glyph: bluetooth = md-bluetooth U+F00AF",
  cp(actionById("bluetooth").glyph), 0xf00af)
check("glyph: stayawake = md-coffee U+F0176", cp(actionById("stayawake").glyph), 0xf0176)
check("glyph: screensaver = md-monitor_shimmer U+F1104",
  cp(actionById("screensaver").glyph), 0xf1104)
check("glyph: audio = md-volume_high U+F057E", cp(actionById("audio").glyph), 0xf057e)
check("glyph: network = md-lan U+F0317", cp(actionById("network").glyph), 0xf0317)
check("glyph: display = md-monitor U+F0379", cp(actionById("display").glyph), 0xf0379)
check("glyph: battery = md-battery U+F0079", cp(actionById("battery").glyph), 0xf0079)
check("glyph: lock = fa-lock U+F023 (menu literal)",
  cp(actionById("lock").glyph), 0xf023)
check("glyph: suspend = md-sleep U+F04B2", cp(actionById("suspend").glyph), 0xf04b2)
check("glyph: hibernate = md-power_cycle U+F0901",
  cp(actionById("hibernate").glyph), 0xf0901)
check("glyph: logout = md-logout U+F0343", cp(actionById("logout").glyph), 0xf0343)
check("glyph: reboot = md-restart U+F0709", cp(actionById("reboot").glyph), 0xf0709)
check("glyph: shutdown = md-power U+F0425", cp(actionById("shutdown").glyph), 0xf0425)
check("glyph: controls group = md-tune U+F062E", cp(GROUP_GLYPHS.controls), 0xf062e)
check("glyph: history group = md-history U+F02DA", cp(GROUP_GLYPHS.history), 0xf02da)
check("glyph: status volume = md-volume_high U+F057E",
  cp(STATUS_GLYPHS.volume), 0xf057e)
check("glyph: status system = md-chip U+F061A", cp(STATUS_GLYPHS.system), 0xf061a)
check("glyph: status connection = md-lan U+F0317",
  cp(STATUS_GLYPHS.connection), 0xf0317)
check("glyph: status wifi = md-wifi U+F05A9", cp(STATUS_GLYPHS.wifi), 0xf05a9)
check("glyphFor: unknown falls back to md-cog U+F0493",
  cp(glyphFor("nope")), 0xf0493)

// ----------------------------------------------------------- isInstantKind
for (const k of ["calc", "convert", "web", "agent", "toggle", "panel",
  "power", "status", "history"]) {
  check(`instant: ${k}`, isInstantKind(k), true)
}
for (const k of ["cmd", "app", "", "bogus"]) {
  check(`instant: ${k} stays false`, isInstantKind(k), false)
}

// ------------------------------------------------------------- relativeTime
const NOW = 1_760_000_000_000
check("rel: seconds", relativeTime(NOW - 30_000, NOW), "just now")
check("rel: exactly 59s", relativeTime(NOW - 59_000, NOW), "just now")
check("rel: 1m", relativeTime(NOW - 60_000, NOW), "1m ago")
check("rel: 5m", relativeTime(NOW - 5 * 60_000, NOW), "5m ago")
check("rel: 59m", relativeTime(NOW - 59 * 60_000, NOW), "59m ago")
check("rel: 1h", relativeTime(NOW - 3_600_000, NOW), "1h ago")
check("rel: 3h", relativeTime(NOW - 3 * 3_600_000, NOW), "3h ago")
check("rel: 23h", relativeTime(NOW - 23 * 3_600_000, NOW), "23h ago")
check("rel: 1d", relativeTime(NOW - 86_400_000, NOW), "1d ago")
check("rel: 6d", relativeTime(NOW - 6 * 86_400_000, NOW), "6d ago")
check("rel: 7d → weeks", relativeTime(NOW - 7 * 86_400_000, NOW), "1w ago")
check("rel: 30d", relativeTime(NOW - 30 * 86_400_000, NOW), "4w ago")
check("rel: future clock skew", relativeTime(NOW + 60_000, NOW), "just now")
check("rel: garbage", relativeTime("nope", NOW), "just now")

// ---------------------------------------------------------- historyEntries
check("history: null usage", historyEntries(null), [])
check("history: non-object usage", historyEntries("x"), [])
{
  const usage = {
    "a:one": { count: 3, last: NOW - 1000 },
    "b:two": { count: 1, last: NOW - 60_000 },
    "c:three": { count: 9, last: NOW - 30_000 },
    "zero:count": { count: 0, last: NOW - 500 },
    "no:last": { count: 4, last: 0 },
    junk: "string-value",
    bare: null,
  }
  const got = historyEntries(usage)
  check("history: sorted newest first",
    got.map((e) => e.route), ["a:one", "c:three", "b:two"])
  check("history: junk filtered", got.length, 3)
  check("history: values preserved",
    [got[0].count, got[0].last], [3, NOW - 1000])
}
{
  const big = {}
  for (let i = 0; i < 50; i++) big["r" + i] = { count: 1, last: NOW - i * 1000 }
  check("history: capped at 40", historyEntries(big).length, 40)
  check("history: cap keeps newest",
    historyEntries(big)[0].route, "r0")
}

// ------------------------------------------------------- footer rail (Phase 5+)
{
  // Default probe (bare desktop): no wifi device, no bluetooth, no
  // connection — the four alert toggles, a plain network opener, audio
  // (popover), display, power (popover).
  const t = footerTiles({}, {})
  check("footer: bare-box tile ids",
    t.map((x) => x.id),
    ["dnd", "nightlight", "stayawake", "screensaver", "net",
      "audio", "display", "power"])
  check("footer: net tile opens the network panel",
    [t[4].actionId, t[4].popover], ["network", ""])
  check("footer: audio + power are the popover tiles",
    [t[5].popover, t[7].popover], ["audio", "power"])
  check("footer: popover tiles carry no direct action",
    [t[5].actionId, t[7].actionId], ["", ""])
  check("footer: dividers open each section once",
    t.map((x) => x.divider),
    [true, false, false, false, true, true, false, true])

  // Laptop with wifi + bluetooth on.
  const lap = footerTiles({ wifi: "on", bluetooth: "on" }, {})
  check("footer: laptop adds wifi + bluetooth",
    lap.map((x) => x.id),
    ["dnd", "nightlight", "stayawake", "screensaver",
      "wifi", "bluetooth", "audio", "display", "power"])
  check("footer: wifi tile keeps the ACTIONS glyph when on",
    lap.find((x) => x.id === "wifi").glyph, actionById("wifi").glyph)
  check("footer: bluetooth tile keeps the ACTIONS glyph when on",
    lap.find((x) => x.id === "bluetooth").glyph,
    actionById("bluetooth").glyph)

  // Off states swap in the verified off glyphs.
  const off = footerTiles({ wifi: "off", bluetooth: "off" }, {})
  check("footer: wifi-off tile glyph", cp(off.find((x) => x.id === "wifi").glyph),
    0xF05AA)   // md-wifi_off
  check("footer: bluetooth-off tile glyph",
    cp(off.find((x) => x.id === "bluetooth").glyph), 0xF00B2)  // md-bluetooth_off

  // Wired-only box: connection name shows on a Wired tile.
  const wired = footerTiles({}, { connection: "Wired connection 1" })
  const wt = wired.find((x) => x.id === "wired")
  check("footer: wired box gets a wired tile, not wifi",
    [!!wt, wired.some((x) => x.id === "wifi")], [true, false])
  check("footer: wired tile uses the connection glyph and opens network",
    [wt.glyph, wt.actionId], [STATUS_GLYPHS.connection, "network"])
  check("footer: wired label carries the connection name",
    wt.label.indexOf("Wired connection 1") >= 0, true)

  // Audio tile glyph flips to volume-off while output is muted.
  check("footer: audio tile glyph while muted",
    cp(footerTiles({}, { outputMuted: true }).find((x) => x.id === "audio").glyph),
    0xF0581)   // md-volume_off
  check("footer: audio tile glyph when not muted",
    footerTiles({}, { outputMuted: false }).find((x) => x.id === "audio").glyph,
    actionById("audio").glyph)

  // No-arg call never crashes (unprobed box).
  check("footer: no-arg call returns tiles", footerTiles().length, 8)

  // Section order: alerts → connectivity → media → session.
  check("footer: section order",
    [...new Set(footerTiles({ wifi: "on", bluetooth: "on" }, {})
      .map((x) => x.section))],
    ["alerts", "connectivity", "media", "session"])
}

// ------------------------------------------- power popover rows (Phase 5+)
{
  check("footer: power rows full",
    powerPopoverRows({}).map((r) => r.id),
    ["battery", "lock", "suspend", "hibernate", "logout", "reboot", "shutdown"])
  check("footer: power rows gate suspend + hibernate like the menu",
    powerPopoverRows({ suspend: "hidden", hibernate: "hidden" })
      .map((r) => r.id),
    ["battery", "lock", "logout", "reboot", "shutdown"])
  check("footer: power rows gate each independently",
    powerPopoverRows({ hibernate: "hidden" }).map((r) => r.id),
    ["battery", "lock", "suspend", "logout", "reboot", "shutdown"])
  const rows = powerPopoverRows({})
  check("footer: only battery + lock act without confirm",
    rows.filter((r) => !r.confirm).map((r) => r.id), ["battery", "lock"])
  check("footer: power panel row is kind panel",
    rows[0].kind, "panel")
  check("footer: session rows are kind power",
    rows.slice(1).every((r) => r.kind === "power"), true)
  check("footer: power rows all come from the ACTIONS table",
    rows.every((r) => !!actionById(r.id)), true)
}

// ------------------------------------------------ audio popover (Phase 5+)
{
  check("footer: mute argv output",
    muteToggleArgv("output"),
    ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
  check("footer: mute argv input",
    muteToggleArgv("input"),
    ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
  check("footer: mute argv unknown channel", muteToggleArgv("rear"), [])

  check("footer: set-volume argv rounds",
    setVolumeArgv("output", 42.4),
    ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "42%"])
  check("footer: set-volume argv clamps high",
    setVolumeArgv("output", 250),
    ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "100%"])
  check("footer: set-volume argv clamps low",
    setVolumeArgv("input", -3),
    ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", "0%"])
  check("footer: set-volume argv refuses garbage",
    setVolumeArgv("output", "abc"), [])
  check("footer: set-volume argv unknown channel",
    setVolumeArgv("rear", 10), [])

  // Glyph proofs — codepoints verified by NAME against the installed
  // Nerd Font (glyphnames.py), asserted here as codePointAt values.
  check("footer: wifiOff is md-wifi_off", cp(FOOTER_GLYPHS.wifiOff), 0xF05AA)
  check("footer: btOff is md-bluetooth_off", cp(FOOTER_GLYPHS.btOff), 0xF00B2)
  check("footer: volumeOff is md-volume_off", cp(FOOTER_GLYPHS.volumeOff), 0xF0581)
  check("footer: mic is md-microphone", cp(FOOTER_GLYPHS.mic), 0xF036C)
  check("footer: micOff is md-microphone_off", cp(FOOTER_GLYPHS.micOff), 0xF036D)
  check("footer: popover volume glyph reuses STATUS_GLYPHS.volume",
    FOOTER_GLYPHS.volume, STATUS_GLYPHS.volume)
  check("footer: chevron is U+25BE", cp(FOOTER_GLYPHS.chevron), 0x25BE)
}

// -------------------------------------------------- dedupeRecentEntries
// User rule: the recents strip never shows one command or app twice; a
// re-use promotes it to the front. Entries arrive sorted most-recent-first
// with an identity id (QML resolves app/command name twins to one key).
check("dedupe: app/command name twins keep the newest, drop the twin",
  dedupeRecentEntries([
    { route: "app:spotify", last: 3, id: "name:spotify" },
    { route: "cmd/spotify", last: 2, id: "name:spotify" },
    { route: "app:chromium", last: 1, id: "name:chromium" } ]),
  ["app:spotify", "app:chromium"])
check("dedupe: three-way twins collapse to the newest single entry",
  dedupeRecentEntries([
    { route: "cmd/x", id: "n" }, { route: "app:x", id: "n" },
    { route: "app:x", id: "n" } ]),
  ["cmd/x"])
check("dedupe: all-unique entries pass through in order",
  dedupeRecentEntries([
    { route: "a", id: "x" }, { route: "b", id: "y" }, { route: "c", id: "z" } ]),
  ["a", "b", "c"])
check("dedupe: missing id falls back to the route as identity",
  dedupeRecentEntries([{ route: "a" }, { route: "b" }, { route: "a" } ]),
  ["a", "b"])
check("dedupe: empty id string falls back to the route",
  dedupeRecentEntries([{ route: "a", id: "" }, { route: "a", id: "" } ]),
  ["a"])
check("dedupe: empty input", dedupeRecentEntries([]), [])

// --------------------------------------------------------------- isWebUrl
// Scheme gate before Qt.openUrlExternally (feed content and search URLs).
check("weburl: https passes", isWebUrl("https://example.com/a?b=c"), true)
check("weburl: http passes", isWebUrl("http://example.com"), true)
check("weburl: uppercase scheme passes", isWebUrl("HTTPS://EXAMPLE.COM/x"), true)
check("weburl: surrounding whitespace tolerated", isWebUrl("  https://a.b/c  "), true)
check("weburl: file scheme blocked", isWebUrl("file:///etc/passwd"), false)
check("weburl: javascript scheme blocked", isWebUrl("javascript:alert(1)"), false)
check("weburl: ftp scheme blocked", isWebUrl("ftp://example.com/"), false)
check("weburl: data scheme blocked", isWebUrl("data:text/html,hi"), false)
check("weburl: protocol-relative blocked", isWebUrl("//evil.example/x"), false)
check("weburl: embedded newline blocked", isWebUrl("https://a.b\njavascript:x"), false)
check("weburl: inner space blocked", isWebUrl("https://a b"), false)
check("weburl: empty/null blocked", isWebUrl(null) + "/" + isWebUrl(""), "false/false")

// ------------------------------------------------------------------ summary
console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
