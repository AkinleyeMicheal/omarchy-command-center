// parity.test.js — Super+Space (Omarchy menu) parity tests (Phase 8.6).
//
// Every curated row added for menu parity must match omarchy-menu.jsonc:
// run rows byte-for-byte, panel rows by the summoned panel id — so an
// Omarchy update that rewrites the menu can't silently drift us.
// Run: node tests/parity.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level declarations and no exports — eval into scope,
// same pattern as controls.test.js / dashboard.test.js.
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

// Same jsonc-tolerant parse the shell's MenuModel.js uses: strip // line
// comments and trailing commas, then JSON.parse.
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

const menu = {}
for (const p of [
  "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc",
  path.join(process.env.HOME || "", ".config/omarchy/extensions/omarchy-menu.jsonc"),
]) {
  if (!fs.existsSync(p)) continue
  const parsed = JSON.parse(stripJsonc(fs.readFileSync(p, "utf8")))
  const src = parsed.items && typeof parsed.items === "object" ? parsed.items : parsed
  for (const [id, entry] of Object.entries(src)) menu[id] = entry
}

// ---- menu parse sanity ------------------------------------------------
check("menu parsed (>300 items)", Object.keys(menu).length > 300, true)

const byId = {}
for (const a of ACTIONS) byId[a.id] = a

// ---- the 12 parity rows exist ----------------------------------------
const parityIds = [
  "speedtest", "diskspeedtest", "colorpicker", "changepassword",
  "switchtheme", "switchbackground", "switchunlock",
  "learn-omarchy", "learn-hyprland", "learn-arch", "learn-lazyvim",
  "learn-bash",
]
for (const id of parityIds) check(`row exists: ${id}`, !!byId[id], true)

// ---- table hygiene ----------------------------------------------------
check("action ids unique", new Set(ACTIONS.map((a) => a.id)).size,
  ACTIONS.length)
for (const id of parityIds) {
  if (!byId[id]) continue
  check(`keywords present: ${id}`, byId[id].keywords.length > 0, true)
  check(`desc present: ${id}`, typeof byId[id].desc === "string", true)
}

// ---- panel rows: panel id == last token of the menu action ------------
check("speedtest panel id", byId.speedtest.panel,
  String(menu["trigger.tests.network-speedtest"].action).split(/\s+/).pop())
check("speedtest kind", byId.speedtest.kind, "panel")
check("diskspeedtest panel id", byId.diskspeedtest.panel,
  String(menu["trigger.tests.disk-speedtest"].action).split(/\s+/).pop())
check("diskspeedtest kind", byId.diskspeedtest.kind, "panel")

// ---- run rows: cmd byte-matches the menu's action string --------------
const runMap = {
  colorpicker: "trigger.capture.color",
  changepassword: "update.password.user",
  switchtheme: "style.theme",
  switchbackground: "style.background",
  switchunlock: "style.unlock",
  "learn-omarchy": "learn.omarchy",
  "learn-hyprland": "learn.hyprland",
  "learn-arch": "learn.arch",
  "learn-lazyvim": "learn.neovim",
  "learn-bash": "learn.bash",
}
for (const [ourId, menuId] of Object.entries(runMap)) {
  if (!byId[ourId] || !menu[menuId]) {
    check(`menu entry for ${ourId} (${menuId})`, "missing", "present")
    continue
  }
  check(`cmd matches menu action: ${ourId}`, byId[ourId].cmd, menu[menuId].action)
  check(`kind run: ${ourId}`, byId[ourId].kind, "run")
}

// ---- sections: tools browsable, learn search-only ---------------------
const toolIds = ["speedtest", "diskspeedtest", "colorpicker", "changepassword",
  "switchtheme", "switchbackground", "switchunlock"]
for (const id of toolIds) {
  if (byId[id]) check(`tools section: ${id}`, byId[id].section, SECTION_TOOLS)
}
for (const id of parityIds.filter((i) => i.startsWith("learn-"))) {
  if (byId[id]) check(`learn section: ${id}`, byId[id].section, SECTION_LEARN)
}

// ---- ranking: the new rows surface for their natural queries ----------
const rankIds = (q) => matchActions(q).map((a) => a.id)
check("rank 'speed' offers speedtest", rankIds("speed").includes("speedtest"), true)
check("rank 'speedtest' offers speedtest", rankIds("speedtest").includes("speedtest"), true)
check("rank 'disk' offers diskspeedtest", rankIds("disk").includes("diskspeedtest"), true)
check("rank 'theme' offers switchtheme", rankIds("theme").includes("switchtheme"), true)
check("rank 'wallpaper' offers switchbackground",
  rankIds("wallpaper").includes("switchbackground"), true)
check("rank 'hyprpicker' offers colorpicker",
  rankIds("hyprpicker").includes("colorpicker"), true)
check("rank 'passwd' offers changepassword",
  rankIds("passwd").includes("changepassword"), true)
const wiki = rankIds("wiki")
check("rank 'wiki' offers learn-hyprland", wiki.includes("learn-hyprland"), true)
check("rank 'wiki' offers learn-arch", wiki.includes("learn-arch"), true)
// Existing ranking must survive the table growth: toggles still win their
// own terms.
check("rank 'dnd' still top-dnd", rankIds("dnd")[0], "dnd")
check("rank 'lock' still top-lock", rankIds("lock")[0], "lock")

// ---- Enter must fire run rows directly (8.6 dead-Enter regression: run
// was missing from isInstantKind, so Enter parked on an empty detail pane
// and activate() bailed on a null detailCmd) -----------------------------
check("run is an instant kind", isInstantKind("run"), true)
check("panel still instant", isInstantKind("panel"), true)
check("power still instant", isInstantKind("power"), true)
check("plain commands stay non-instant", isInstantKind("cmd"), false)

// ---- activation shape: run rows carry a non-empty static cmd ----------
for (const [ourId, menuId] of Object.entries(runMap)) {
  if (!byId[ourId]) continue
  check(`cmd non-empty: ${ourId}`, byId[ourId].cmd.length > 0, true)
  check(`cmd never empty vs menu: ${ourId}`,
    menu[menuId].action.length > 0, true)
}

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
