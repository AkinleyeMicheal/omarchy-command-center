// search.test.js — node unit tests for SearchProviders.js (Phase-7
// providers: window switching, clipboard history, file search, dictionary).
// Run: node tests/search.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level function declarations and no exports; eval it into
// this scope exactly like providers.test.js does for MathEval/Units.
// eslint-disable-next-line no-eval
eval(fs.readFileSync(path.join(__dirname, "..", "SearchProviders.js"), "utf8"))

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

// ---------------------------------------------------------------- prefixes
check("prefix ;", prefixOf(";notes"), ";")
check("prefix /", prefixOf("/report"), "/")
check("prefix ?", prefixOf("?serendipity"), "?")
check("prefix none", prefixOf("theme set"), "")
check("prefix @ not ours", prefixOf("@codex"), "")
check("prefix empty", prefixOf(""), "")
check("prefix null", prefixOf(null), "")
check("body strips prefix", bodyOf(";hello world"), "hello world")
check("body keeps inner spaces", bodyOf("/  my file"), "  my file")

// ---------------------------------------------------------- windowMatches
const wins = [
  { addr: "0xaa", class: "Spotify", title: "Spotify Premium", ws: "1" },
  { addr: "0xbb", class: "foot", title: "news — foot", ws: "2" },
  { addr: "0xcc", class: "firefox", title: "Mozilla Firefox", ws: "1" }
]
check("wins need 2+ chars", windowMatches(wins, "s", 4), [])
check("wins match title", windowMatches(wins, "prem", 4).map(w => w.addr), ["0xaa"])
check("wins match class ci", windowMatches(wins, "FIRE", 4).map(w => w.addr), ["0xcc"])
check("wins match both fields", windowMatches(wins, "foot", 4).map(w => w.addr), ["0xbb"])
check("wins cap", windowMatches(wins, "re", 2).length, 2)
check("wins skip bad addr", windowMatches([{ addr: "", class: "x" }, ...wins], "prem", 4).map(w => w.addr), ["0xaa"])
const dupWins = wins.concat([{ addr: "0xaa", class: "Spotify", title: "again" }])
check("wins dedupe by addr", windowMatches(dupWins, "spotify", 4).length, 1)
check("wins non-array safe", windowMatches(null, "x", 4), [])
check("wins keeps ws", windowMatches(wins, "prem", 4)[0].ws, "1")

// ----------------------------------------------------------- normalizeClip
check("clip norm strings", normalizeClip(["hello", "  ", "bye"]).map(e => e.text), ["hello", "bye"])
check("clip norm text obj", normalizeClip([{ type: "text", text: "abc" }])[0], { type: "text", text: "abc" })
check("clip norm image", normalizeClip([{ type: "image", path: "/tmp/a.png" }])[0],
  { type: "image", path: "/tmp/a.png", mime: "image/png", capturedAt: "" })
check("clip norm drops junk", normalizeClip([null, 42, { type: "video" }, { type: "text", text: "   " }]), [])
check("clip norm non-array", normalizeClip("nope"), [])

// ------------------------------------------------------------ clipMatches
const clip = [
  { type: "text", text: "omarchy plugin add https://github.com/x/y.git" },
  { type: "image", path: "/s/a.png", mime: "image/png" },
  { type: "text", text: "https://aiweekly.co/ai-news-today" }
]
check("clip browse newest first", clipMatches(clip, "", 8).map(h => h.index), [0, 1, 2])
check("clip filter ci", clipMatches(clip, "AIWEEKLY", 8).map(h => h.index), [2])
check("clip filter keeps index", clipMatches(clip, "plugin", 8)[0].index, 0)
check("clip images browse-only", clipMatches(clip, "png", 8), [])
check("clip cap", clipMatches(clip, "", 1).length, 1)
check("clip empty on no match", clipMatches(clip, "zzz", 8), [])
check("clip non-array safe", clipMatches(undefined, "", 4), [])

// ------------------------------------------------------------- clipPreview
check("clip preview collapse", clipPreview("  a\n\tb  c  "), "a b c")
check("clip preview cap", clipPreview("x".repeat(100)).length, 65)
check("clip preview ellipsis", clipPreview("x".repeat(100)).endsWith("…"), true)
check("clip preview short", clipPreview("hello"), "hello")
check("clip preview null", clipPreview(null), "")

// ------------------------------------------------------------- fileMatches
const fdOut = [
  "/home/u/.config/omarchy/plugins/fonsgaudii.cmdcenter/Palette.qml",
  "/home/u/Documents/palette-mock.png",
  "/home/u/notes.txt",
  "",
  "/home/u/NOTES-2.md"
].join("\n")
check("file basename ci", fileMatches(fdOut, "palette", 8),
  ["/home/u/.config/omarchy/plugins/fonsgaudii.cmdcenter/Palette.qml", "/home/u/Documents/palette-mock.png"])
check("file no dir match", fileMatches(fdOut, "documents", 8), [])
check("file cap", fileMatches(fdOut, "notes", 1).length, 1)
check("file empty query", fileMatches(fdOut, "", 8), [])
check("file junk query", fileMatches(fdOut, "[", 8), [])
check("file non-string safe", fileMatches(null, "x", 4), [])

// ------------------------------------------------------------------ dirOf
check("dirOf nested", dirOf("/a/b/c.txt"), "/a/b")
check("dirOf root child", dirOf("/x"), "/")
check("dirOf no slash", dirOf("rel"), "/")
check("dirOf empty", dirOf(""), "/")

// --------------------------------------------------------- translateSpec
check("translate parses", translateSpec("fr hello world"), { lang: "fr", text: "hello world" })
check("translate trims", translateSpec("  de   hallo  "), { lang: "de", text: "hallo" })
check("translate lone word", translateSpec("hello"), null)
check("translate bare lang", translateSpec("fr "), null)
check("translate uppercase lang", translateSpec("FR hello"), null)

// -------------------------------------------------------------- isDictWord
check("dict word plain", isDictWord("serendipity"), true)
check("dict word hyphen", isDictWord("well-being"), true)
check("dict word apostrophe", isDictWord("don't"), true)
check("dict word spaces", isDictWord("new york"), true)
check("dict word rejects digits", isDictWord("covid-19"), false)
check("dict word rejects empty", isDictWord(""), false)
check("dict word rejects space", isDictWord("  "), false)
check("dict word rejects injection", isDictWord("a;rm -rf /"), false)
check("dict word trims outer space", isDictWord(" x"), true)
check("dict word rejects too long", isDictWord("a".repeat(65)), false)

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
