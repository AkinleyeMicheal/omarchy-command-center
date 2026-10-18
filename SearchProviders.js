// SearchProviders.js — pure matching logic for the Phase-7 providers:
// window switching (`;` none — automatic), clipboard history (`;`), file
// search (`/`), dictionary (`?`). Data in, rows out: no QML, no shell, no
// Date.now — unit-tested in node like MathEval/Units. Row *shaping* stays in
// Palette.qml (it owns computedRow); these return matched data only.

// The prefix that routes a query to a provider: ";" clipboard, "/" files,
// "?" dictionary. "@" (agents) keeps its own handling in Palette.qml.
function prefixOf(query) {
  var q = String(query || "")
  var c = q.charAt(0)
  return c === ";" || c === "/" || c === "?" ? c : ""
}

// Everything after the prefix, trimmed.
function bodyOf(query) {
  return String(query || "").replace(/^\s+/, "").slice(1)
}

// ------------------------------------------- window switching (automatic)
// Matches on class + title, case-insensitive substring. The current window
// and omarchy's own surfaces are already filtered by win-ctl.sh.
function windowMatches(wins, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  if (q.length < 2) return []
  var max = Number(limit) > 0 ? Number(limit) : 4
  var out = []
  var seen = Object.create(null)   // data-keyed; "__proto__"-safe
  var list = Array.isArray(wins) ? wins : []
  for (var i = 0; i < list.length && out.length < max; i++) {
    var w = list[i]
    if (!w || !w.addr || seen[w.addr]) continue
    var hay = (String(w.title || "") + " " + String(w.class || "")).toLowerCase()
    if (hay.indexOf(q) < 0) continue
    seen[w.addr] = true
    out.push({ addr: String(w.addr), class: String(w.class || ""),
      title: String(w.title || ""), ws: String(w.ws || "") })
  }
  return out
}

// ------------------------------------------------- clipboard (`;` prefix)
// Same entry contract as omarchy's first-party ClipboardHistory.js (text →
// {type,text}; image → {type,path,mime,capturedAt}); junk entries dropped.
function normalizeClip(raw) {
  var out = []
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length; i++) {
    var v = list[i]
    if (typeof v === "string") {
      if (v.trim().length > 0) out.push({ type: "text", text: v })
      continue
    }
    if (!v || typeof v !== "object") continue
    var type = String(v.type || v.kind || "")
    if (type === "text") {
      var text = String(v.text || "")
      if (text.trim().length > 0) out.push({ type: "text", text: text })
    } else if (type === "image") {
      var path = String(v.path || "")
      if (path) out.push({ type: "image", path: path,
        mime: String(v.mime || "image/png"),
        capturedAt: String(v.capturedAt || "") })
    }
  }
  return out
}

// Empty body → the most recent entries; otherwise substring match on the
// text (images match on nothing but stay listed for short queries? no —
// images are browse-only, they never match typed text). Index = array
// position, which is exactly what --history-index expects (0 = newest).
function clipMatches(entries, query, limit) {
  var max = Number(limit) > 0 ? Number(limit) : 8
  var q = String(query || "").trim().toLowerCase()
  var list = Array.isArray(entries) ? entries : []
  var out = []
  for (var i = 0; i < list.length && out.length < max; i++) {
    var e = list[i]
    if (!e) continue
    if (e.type !== "text") {
      if (q.length === 0) out.push({ index: i, entry: e })
      continue
    }
    if (q.length === 0 || String(e.text || "").toLowerCase().indexOf(q) >= 0)
      out.push({ index: i, entry: e })
  }
  return out
}

// One-line preview for a clipboard text: collapsed whitespace, trimmed,
// hard-capped so a pasted essay can't become a wall-of-text row.
function clipPreview(text) {
  var s = String(text || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  if (s.length > 64) s = s.slice(0, 64) + "…"
  return s
}

// ---------------------------------------------------- file search (`/`)
// Raw fd stdout (one path per line) → matched paths. win side is handled by
// the script; here we just keep the basename-substring contract consistent
// with it and cap the list.
function fileMatches(output, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  var max = Number(limit) > 0 ? Number(limit) : 8
  var out = []
  var lines = String(output || "").split("\n")
  for (var i = 0; i < lines.length && out.length < max; i++) {
    var p = lines[i].replace(/\r$/, "")
    if (!p) continue
    var slash = p.lastIndexOf("/")
    var base = slash >= 0 ? p.slice(slash + 1) : p
    if (base.toLowerCase().indexOf(q) >= 0) out.push(p)
  }
  return out
}

// Directory of a path (for the terminal "cd there" action).
function dirOf(path) {
  var p = String(path || "")
  var slash = p.lastIndexOf("/")
  return slash > 0 ? p.slice(0, slash) : "/"
}

// ------------------------------------------------ dictionary (`?` prefix)
// "?fr hello" reads as "translate hello into fr" — a web-search row, since
// offline translation isn't on this box. Returns {lang,text} or null.
function translateSpec(body) {
  var m = /^([a-z]{2,8})\s+(.+)$/.exec(String(body || "").trim())
  if (!m) return null
  var rest = m[2].replace(/^\s+|\s+$/g, "")
  if (!rest) return null
  return { lang: m[1], text: rest }
}

// A dictionary word: letters/apostrophe/hyphen/space only (mirrors
// dict-lookup.sh's validation so the UI never arms a doomed request).
function isDictWord(body) {
  var w = String(body || "").trim()
  if (!w || w.length > 64) return false
  return /^[A-Za-z][A-Za-z' -]*$/.test(w)
}
