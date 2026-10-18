// model.test.js — node unit tests for CommandsModel.js
// Run: node tests/model.test.js

const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "..", "CommandsModel.js"), "utf8")
eval(src) // function declarations land in this scope

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

function cmd(args, extra) {
  return Object.assign(
    { route: "omarchy foo", tokens: tokenizeArgs(args), examples: [], complex: false },
    extra || {}
  )
}

// ------------------------------------------------------------ tokenizeArgs
check("tokenize: enum required", tokenizeArgs("<on|off>"),
  [{ kind: "enum", required: true, label: "on|off", options: ["on", "off"] }])
check("tokenize: enum optional with flag",
  tokenizeArgs("<on|off|status> [--force]"),
  [
    { kind: "enum", required: true, label: "on|off|status", options: ["on", "off", "status"] },
    { kind: "flag", required: false, label: "--force" },
  ])
check("tokenize: keyval optional", tokenizeArgs("[--except <agent>]"),
  [{ kind: "keyval", required: false, key: "--except", label: "agent" }])
check("tokenize: text + rest", tokenizeArgs("<name> [rest...]"),
  [
    { kind: "text", required: true, label: "name" },
    { kind: "rest", required: false, label: "rest" },
  ])
check("tokenize: complex", tokenizeArgs("set | get | reset"),
  [{ kind: "complex", label: "set | get | reset" }])

// ------------------------------------------------------------ quoteArg
check("quote: plain passthrough", quoteArg("on"), "on")
check("quote: spaces", quoteArg("My Theme"), "'My Theme'")
check("quote: embedded single quote", quoteArg("it's"), "'it'\\''s'")
check("quote: empty", quoteArg(""), "")

// ------------------------------------------------------------ assemble
{
  const c = cmd("<on|off> [--force] <name>")
  check("assemble: defaults only", assembleCommandLine(c, ["on", false, ""]),
    "omarchy foo on")
  check("assemble: flag + text", assembleCommandLine(c, ["off", true, "bar"]),
    "omarchy foo off --force bar")
  check("assemble: text with spaces gets quoted", assembleCommandLine(c, ["on", false, "my file"]),
    "omarchy foo on 'my file'")
  check("assemble: no values at all", assembleCommandLine(c, ["", false, ""]),
    "omarchy foo")
}
{
  const c = cmd("[--except <agent>] [name...]")
  check("assemble: keyval + rest", assembleCommandLine(c, ["alice", "x y z"]),
    "omarchy foo --except=alice 'x y z'")
  check("assemble: keyval empty is skipped", assembleCommandLine(c, ["", ""]),
    "omarchy foo")
}
check("assemble: null cmd", assembleCommandLine(null, []), "")

// ------------------------------------------------------------ splitWords
check("split: simple", splitWords("on --force bar"), ["on", "--force", "bar"])
check("split: double quotes keep spaces", splitWords('set "My Theme" x'), ["set", "My Theme", "x"])
check("split: single quotes keep spaces", splitWords("set 'My Theme' x"), ["set", "My Theme", "x"])
check("split: empty", splitWords("   "), [])

// ------------------------------------------------------------ seedFormValues
{
  // Flags and keyvals are claimed anywhere; positionals take the rest in order.
  const c = cmd("[on|off] [--force] [--except <agent>] <name>", {
    examples: ["omarchy foo off --force --except=bob hello"],
  })
  check("seed: mixed example", seedFormValues(c), ["off", true, "bob", "hello"])
}
{
  // A rest token swallows the remainder, quotes included.
  const c = cmd("<prompt...> [--inline]", {
    examples: ['omarchy foo "say hi there" --inline'],
  })
  check("seed: rest swallows quoted remainder", seedFormValues(c), ["say hi there", true])
}
{
  // A word outside the enum's option set is left for later tokens; the
  // required default stands.
  const c = cmd("[on|off] <name>", { examples: ["omarchy foo hello"] })
  check("seed: enum mismatch keeps default", seedFormValues(c), ["", "hello"])
}
{
  // Required enum picks its first option when the example says nothing.
  const c = cmd("<a|b|c> [x]", { examples: [] })
  check("seed: required enum defaults to first", seedFormValues(c), ["a", ""])
}
{
  // An example that does not start with the route seeds nothing.
  const c = cmd("<name>", { examples: ["sudo omarchy foo something"] })
  check("seed: non-route example ignored", seedFormValues(c), [""])
}

// ------------------------------------------------------------ frecencyBonus
const now = 1e12
const usageFresh = { "omarchy foo": { count: 10, last: now - 2 * 86400000 } }
check("frecency: no usage", frecencyBonus({ route: "omarchy foo" }, null, now), 0)
check("frecency: unknown route", frecencyBonus({ route: "omarchy bar" }, usageFresh, now), 0)
check("frecency: capped at 300", frecencyBonus({ route: "omarchy foo" }, usageFresh, now), 300)
check("frecency: small count", frecencyBonus({ route: "omarchy foo" },
  { "omarchy foo": { count: 2, last: now - 86400000 } }, now), 80)
check("frecency: 30d decay 0.6", frecencyBonus({ route: "omarchy foo" },
  { "omarchy foo": { count: 2, last: now - 20 * 86400000 } }, now), 48)
check("frecency: quarter decay 0.3", frecencyBonus({ route: "omarchy foo" },
  { "omarchy foo": { count: 5, last: now - 60 * 86400000 } }, now), 60)
check("frecency: ancient decay 0.15", frecencyBonus({ route: "omarchy foo" },
  { "omarchy foo": { count: 100, last: now - 400 * 86400000 } }, now), 45)

// ------------------------------------------------------------ search + usage
{
  const catalog = [
    normalizeCommand({ route: "omarchy alpha", group: "g", summary: "alpha tool" }),
    normalizeCommand({ route: "omarchy beta", group: "g", summary: "beta tool" }),
    normalizeCommand({ route: "omarchy gamma", group: "g", summary: "unrelated" }),
  ]
  // Both alpha and beta are prefix-tier hits for "a"... only alpha matches "al",
  // so use a query both match: "b" vs summary-tier gamma? Keep it deterministic:
  // "tool" matches alpha + beta via summary; frecency must lift beta above alpha.
  const plain = search(catalog, "tool", null, now)
  check("search: baseline order", plain.map(c => c.route), ["omarchy alpha", "omarchy beta"])
  const boosted = search(catalog, "tool",
    { "omarchy beta": { count: 9, last: now - 86400000 } }, now)
  check("search: frecency reorders ties", boosted.map(c => c.route), ["omarchy beta", "omarchy alpha"])
  // But exact matches (tier 0) stay on top no matter how loved a prefix
  // match is — the bonus is bounded below the exact-vs-prefix tier gap.
  const catalog2 = [
    normalizeCommand({ route: "omarchy alpha", group: "g", summary: "" }),
    normalizeCommand({ route: "omarchy alphatool", group: "g", summary: "" }),
  ]
  const exact = search(catalog2, "alpha",
    { "omarchy alphatool": { count: 9, last: now - 86400000 } }, now)
  check("search: exact still wins", exact.map(c => c.route),
    ["omarchy alpha", "omarchy alphatool"])
}

console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
