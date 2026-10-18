// CommandsModel.js — pure JS model for the omarchy command catalog.
//
// Data source: `omarchy commands --json` (plus GROUP_DESCRIPTIONS scraped
// from the omarchy dispatcher), cached on disk by Palette.qml. No Qt
// dependencies, so this stays testable outside QML.

// ------------------------------------------------------------ normalization

function normalizeCommand(c) {
  var route = String(c.route || "")
  var bare = route.replace(/^omarchy\s+/, "")
  var args = String(c.args || "")
  var tokens = tokenizeArgs(args)
  var complex = tokens.length === 1 && tokens[0].kind === "complex"
  var aliases = (c.aliases || []).map(String)
  var summary = String(c.summary || "")
  return {
    route: route,
    bare: bare,
    group: String(c.group || ""),
    summary: summary,
    requiresSudo: !!c.requires_sudo,
    args: args,
    examples: (c.examples || []).map(String),
    aliases: aliases,
    tokens: tokens,
    complex: complex,
    argCount: complex ? 0 : tokens.length,
    searchText: (bare + " " + aliases.join(" ") + " " + summary).toLowerCase()
  }
}

function parseCatalog(commands) {
  var out = []
  var list = commands || []
  // The cache file is loaded from the state dir, so it is treated as
  // UNTRUSTED input: a poisoned commands.json must not be able to name
  // an arbitrary binary (routes reach `bash -lc` when run, and the
  // selected row's `--help` probe fires on browse). Every genuine
  // catalog route is `omarchy <subcommand>` over a safe charset — the
  // shipped catalog passes 367/367 — so anything else is dropped.
  var safeRoute = /^omarchy [A-Za-z0-9 ._:,@+-]*$/
  for (var i = 0; i < list.length; i++) {
    var c = normalizeCommand(list[i])
    if (!safeRoute.test(String(c.route || ""))) continue
    out.push(c)
  }
  out.sort(function(a, b) {
    if (a.group !== b.group) return a.group < b.group ? -1 : 1
    return a.bare < b.bare ? -1 : (a.bare > b.bare ? 1 : 0)
  })
  return out
}

function buildGroupList(catalog, descriptions) {
  var seen = Object.create(null)   // data-keyed; "__proto__"-safe
  for (var i = 0; i < catalog.length; i++) {
    var g = catalog[i].group
    if (!seen[g]) seen[g] = { name: g, label: g, description: (descriptions || {})[g] || "", count: 0 }
    seen[g].count++
  }
  var out = []
  for (var k in seen) out.push(seen[k])
  out.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
  return out
}

// ------------------------------------------------------------ args spec
//
// The `args` field is an informal, human-written spec. We parse the common
// shapes into tokens so the detail pane can render argument chips (and, in
// a later phase, real form controls):
//
//   <name>            required text          [name]      optional text
//   <a|b|c>           required enum          [a|b|c]     optional enum
//   <rest...>         required rest          [rest...]   optional rest
//   --flag            required flag          [--flag]    optional flag
//   --key=<val>       key/value              [--k=<val>] optional key/value
//   [--k <val>]       optional key/value, space-separated form
//   a | b | c         complex subcommands    -> single "complex" token,
//                     rendered as an editable command line instead.

function tokenizeArgs(argsText) {
  var text = String(argsText || "").trim()
  if (!text) return []
  if (text.indexOf(" | ") >= 0) return [{ kind: "complex", label: text }]

  var tokens = []
  var re = /<[^<>]*>|\[[^\]]*\]|[^\s]+/g
  var m
  while ((m = re.exec(text)) !== null) {
    var tok = m[0]
    if (tok.charAt(0) === "<" && tok.charAt(tok.length - 1) === ">") {
      var inner = tok.slice(1, -1)
      if (inner.indexOf("|") >= 0) {
        tokens.push({ kind: "enum", required: true, label: inner, options: inner.split("|") })
      } else if (inner.slice(-3) === "...") {
        tokens.push({ kind: "rest", required: true, label: inner.slice(0, -3) })
      } else {
        tokens.push({ kind: "text", required: true, label: inner })
      }
    } else if (tok.charAt(0) === "[" && tok.charAt(tok.length - 1) === "]") {
      var inr = tok.slice(1, -1).trim()
      if (!inr) continue
      if (inr.charAt(0) === "-") {
        var eq = inr.indexOf("=")
        if (eq >= 0) {
          tokens.push({ kind: "keyval", required: false, key: inr.slice(0, eq), label: inr.slice(eq + 1).replace(/^<|>$/g, "") })
        } else if (/\s/.test(inr)) {
          // "--key <value>" — space-separated flag/value pair.
          var kw = inr.split(/\s+/)
          tokens.push({ kind: "keyval", required: false, key: kw[0], label: (kw[1] || "value").replace(/^<|>$/g, "") })
        } else {
          tokens.push({ kind: "flag", required: false, label: inr })
        }
      } else if (inr.indexOf("|") >= 0) {
        tokens.push({ kind: "enum", required: false, label: inr, options: inr.split("|") })
      } else if (inr.slice(-3) === "...") {
        tokens.push({ kind: "rest", required: false, label: inr.slice(0, -3) })
      } else {
        tokens.push({ kind: "text", required: false, label: inr })
      }
    } else if (tok.charAt(0) === "-" && tok.length > 1) {
      var eq2 = tok.indexOf("=")
      if (eq2 >= 0) {
        tokens.push({ kind: "keyval", required: true, key: tok.slice(0, eq2), label: tok.slice(eq2 + 1).replace(/^<|>$/g, "") })
      } else {
        tokens.push({ kind: "flag", required: true, label: tok })
      }
    }
    // Bare words are subcommand vocabulary already encoded in the route.
  }
  return tokens
}

function tokenChipText(tok) {
  if (tok.kind === "flag") return (tok.required ? "" : "[") + tok.label + (tok.required ? "" : "]")
  if (tok.kind === "keyval") return (tok.required ? tok.key + " <" : "[") + tok.key + "=<" + tok.label + ">" + (tok.required ? ">" : "]")
  if (tok.kind === "enum") return (tok.required ? "<" : "[") + tok.options.join("|") + (tok.required ? ">" : "]")
  if (tok.kind === "rest") return (tok.required ? "<" : "[") + tok.label + "..." + (tok.required ? ">" : "]")
  return (tok.required ? "<" : "[") + tok.label + (tok.required ? ">" : "]")
}

// ------------------------------------------------------------ form controls
//
// The detail pane renders one control per token (segmented pills or a
// searchable dropdown for enums, text fields for names, switches for flags)
// and assembles an executable command line from their values. values[ i ]
// aligns with tokens[ i ] — true for flags, a string otherwise. Seeding
// pulls concrete values back out of the command's first example so the form
// and the command-line field start consistent.

function quoteArg(v) {
  var s = String(v === undefined || v === null ? "" : v)
  if (!s) return s
  // The class covers command separators/substitution AND the
  // expansion/comment chars — `*`, `~`, `#` and friends must not reach
  // bash -lc unquoted either (glob, tilde and comment expansion).
  return /[\s"'\\$`|&;<>()*?[\]{}~#]/.test(s)
    ? "'" + s.replace(/'/g, "'\\''") + "'" : s
}

function assembleCommandLine(cmd, values) {
  if (!cmd) return ""
  var parts = [String(cmd.route || "")]
  var toks = cmd.tokens || []
  for (var i = 0; i < toks.length; i++) {
    var t = toks[i]
    var v = values ? values[i] : undefined
    if (t.kind === "flag") {
      if (v === true) parts.push(t.label)
    } else {
      var s = v === undefined || v === null ? "" : String(v)
      if (!s) continue
      if (t.kind === "keyval") parts.push(t.key + "=" + quoteArg(s))
      else parts.push(quoteArg(s))
    }
  }
  return parts.join(" ")
}

// Split a command example into words, respecting single/double quotes so
// seeded values keep multi-word arguments intact.
function splitWords(text) {
  var out = []
  var cur = ""
  var quote = ""
  var has = false
  var s = String(text || "")
  for (var i = 0; i < s.length; i++) {
    var ch = s.charAt(i)
    if (quote) {
      if (ch === quote) quote = ""
      else cur += ch
      has = true
    } else if (ch === "'" || ch === '"') {
      quote = ch
      has = true
    } else if (/\s/.test(ch)) {
      if (has) { out.push(cur); cur = ""; has = false }
    } else {
      cur += ch
      has = true
    }
  }
  if (has) out.push(cur)
  return out
}

function seedFormValues(cmd) {
  var toks = cmd ? (cmd.tokens || []) : []
  var values = []
  var i
  for (i = 0; i < toks.length; i++) {
    var t = toks[i]
    if (t.kind === "flag") values.push(t.required === true)
    else if (t.kind === "enum" && t.required === true) values.push(String(t.options[0] || ""))
    else values.push("")
  }
  if (!cmd || cmd.complex || !cmd.examples || !cmd.examples.length) return values

  var example = String(cmd.examples[0] || "").trim()
  var route = String(cmd.route || "")
  if (!route || example.indexOf(route) !== 0) return values
  var words = splitWords(example.slice(route.length).trim())
  if (!words.length) return values

  // Pass 1: flags and key/values live anywhere in the example — claim them
  // first so the positional walk only sees positional words.
  var positional = []
  for (i = 0; i < words.length; i++) {
    var w = words[i]
    var claimed = false
    for (var f = 0; f < toks.length; f++) {
      var tf = toks[f]
      if (tf.kind === "flag" && w === tf.label) { values[f] = true; claimed = true; break }
      if (tf.kind === "keyval" && w.indexOf(tf.key + "=") === 0) {
        values[f] = w.slice(tf.key.length + 1)
        claimed = true
        break
      }
    }
    if (!claimed) positional.push(w)
  }

  // Pass 2: positional tokens take the remaining words in order; a rest
  // token swallows the remainder. An enum word outside the option set is
  // left for later tokens (the required default stands).
  var pos = 0
  for (i = 0; i < toks.length && pos < positional.length; i++) {
    var tok = toks[i]
    if (tok.kind === "rest") {
      values[i] = positional.slice(pos).join(" ")
      pos = positional.length
    } else if (tok.kind === "enum") {
      if (tok.options && tok.options.indexOf(positional[pos]) >= 0) {
        values[i] = positional[pos]
        pos++
      }
    } else if (tok.kind === "text") {
      values[i] = positional[pos]
      pos++
    }
  }
  return values
}

// ------------------------------------------------------------ fuzzy search
//
// Tiered scoring adapted from Omarchy's own AppSearch.js approach: exact
// route beats route prefix beats alias beats substring beats summary
// matches, with acronym matches as a low-confidence fallback. All terms
// must match (AND), so "shot region" narrows fast.

function acronymMatch(bare, term) {
  if (term.length > 5 || term.length < 2) return false
  var words = bare.split(/[ .\/_-]+/)
  var ac = ""
  for (var i = 0; i < words.length; i++) if (words[i]) ac += words[i].charAt(0)
  return ac.indexOf(term) === 0
}

function termScore(c, t) {
  var bare = c.bare
  if (bare === t) return 0
  if (bare.indexOf(t) === 0) return 1000 - Math.min(999, bare.length - t.length)
  if (c.aliases.length) {
    for (var i = 0; i < c.aliases.length; i++) {
      var a = c.aliases[i].toLowerCase()
      if (a === t || a.indexOf(t) === 0) return 1200
    }
  }
  var pos = bare.indexOf(t)
  if (pos > 0) return 2000 - Math.min(999, pos * 10)
  var hpos = c.searchText.indexOf(t)
  if (hpos >= 0) return 3000 - Math.min(999, Math.floor(hpos / 10))
  if (acronymMatch(bare, t)) return 4000
  return -1
}

function searchScore(c, terms) {
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var s = termScore(c, terms[i])
    if (s < 0) return -1
    total += s
  }
  return total
}

// ------------------------------------------------------------ frecency
//
// Launch history (route -> {count, last}) lifts well-used commands above
// equally-good matches. The bonus is bounded at 300 so it reorders matches
// within a tier and can lift a summary-tier hit over an acronym-tier one,
// but never overtakes exact or prefix matches (tiers 0 and 1). Recency
// decays the weight: a week stays full, a month drops to 0.6, a quarter
// to 0.3, ancient history to 0.15.

function frecencyBonus(c, usage, now) {
  if (!usage) return 0
  var u = usage[c.route]
  if (!u) return 0
  var count = Number(u.count) || 0
  if (count <= 0) return 0
  var t = Number(u.last) || 0
  var days = t > 0 ? (Number(now || Date.now()) - t) / 86400000 : 3650
  var weight = days <= 7 ? 1 : (days <= 30 ? 0.6 : (days <= 90 ? 0.3 : 0.15))
  return Math.min(300, count * 40) * weight
}

function search(catalog, query, usage, now) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return catalog
  var terms = q.split(/\s+/)
  var hits = []
  for (var i = 0; i < catalog.length; i++) {
    var s = searchScore(catalog[i], terms)
    if (s >= 0) hits.push({ cmd: catalog[i], score: s - frecencyBonus(catalog[i], usage, now) })
  }
  hits.sort(function(a, b) { return a.score - b.score || (a.cmd.bare < b.cmd.bare ? -1 : 1) })
  var out = []
  for (var j = 0; j < hits.length; j++) out.push(hits[j].cmd)
  return out
}

function commandsInGroup(catalog, group) {
  if (group === "*") return catalog
  var out = []
  for (var i = 0; i < catalog.length; i++) if (catalog[i].group === group) out.push(catalog[i])
  return out
}

// ------------------------------------------------------------ execution

// Commands that should open in a terminal by default under the smart
// hybrid policy: sudo, complex subcommand specs, and groups whose commands
// are interactive, TUI, long-running, or destructive. The Terminal button
// remains available for every command, so this is a default, not a cage.
var TERMINAL_GROUPS = {
  agent: 1, tui: 1, dev: 1, setup: 1, update: 1, upgrade: 1, remove: 1,
  reinstall: 1, snapshot: 1, channel: 1, sudo: 1, dns: 1, drive: 1,
  branding: 1, hibernation: 1, plymouth: 1, tailscale: 1, migrate: 1,
  openclaw: 1, install: 1, plugin: 1
}

function needsTerminal(cmd) {
  if (!cmd) return false
  if (cmd.requiresSudo) return true
  if (cmd.complex) return true
  return !!TERMINAL_GROUPS[cmd.group]
}

function initialCommandLine(cmd) {
  if (!cmd) return ""
  if (cmd.examples && cmd.examples.length) return cmd.examples[0]
  return cmd.route
}

// ------------------------------------------------------------ glyphs

var GROUP_GLYPHS = {
  capture: "󰑊", theme: "󰆼", plugin: "󰏗", system: "󰍹", toggle: "󰈈",
  update: "󰚄", upgrade: "󰚄", launch: "󰀻", pkg: "󰏖", install: "󰏗",
  bar: "󰂢", audio: "󰕾", display: "󰈈", monitor: "󰈈", network: "󰖩",
  power: "󰒤", agent: "󰚩", dev: "󰣀", menu: "󰀄", reminder: "󰋌",
  shell: "󰞷", font: "󰛖", setup: "󰒓", brightness: "󰃠", bluetooth: "󰂯",
  weather: "󰖐", clipboard: "󰅌", windows: "󰘲", screensaver: "󰸸",
  battery: "󰁹", notification: "󰂞", osd: "󰕾", restart: "󰝢", refresh: "󰁯",
  remove: "󰆴", version: "󰂷", cmd: "󰆍", file: "󰈔", webapp: "󰖟", hook: "󰌘"
}

function groupGlyph(name) {
  return GROUP_GLYPHS[name] || "󰲋"
}
