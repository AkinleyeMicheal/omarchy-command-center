// Dashboard.js — pure builders for the home cards (Phase 6b).
// No I/O, no QML: node-testable (tests/dashboard.test.js).
//
// The dashboard is ambient and never polls on a timer: these builders
// run on palette open (the weather subprocess has its own 5-minute
// throttle in QML; MPRIS is reactive by nature; date/stats ride the
// same open-cycle refresh as status.sh).

var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday",
  "Thursday", "Friday", "Saturday"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Combined stdout of `omarchy weather icon; echo; omarchy weather
// status; echo; <detail probe>`: two lines normally (condition glyph,
// then the "·"-line), three with the 8.3 detail line ("condition<TAB>
// country" from wttr.in's j1 payload). Tolerates missing halves: a lone
// short token is the icon, a longer one is the status line.
function parseWeatherOutput(raw) {
  var out = { icon: "", line: "", detail: "" }
  var parts = String(raw == null ? "" : raw).split("\n")
  var kept = []
  for (var i = 0; i < parts.length; i++) {
    var t = parts[i].trim()
    if (t) kept.push(t)
  }
  if (kept.length >= 2) {
    out.icon = kept[0]
    out.line = kept[1]
    if (kept.length >= 3) out.detail = kept[2]
  } else if (kept.length === 1) {
    if (kept[0].length <= 4) out.icon = kept[0]
    else out.line = kept[0]
  }
  return out
}

// The third weather line: "condition<TAB>country" (@tsv from jq).
// Missing/blank → both "" (the tile falls back gracefully).
function parseWeatherDetail(line) {
  var parts = String(line == null ? "" : line).split("\t")
  return {
    condition: (parts[0] || "").trim(),
    country: (parts[1] || "").trim()
  }
}

// `omarchy weather status` prints one "·"-separated line:
//   "Ibadan  ·  Temp 23°C  ·  Wind ↑4km/h"
// → { city, temp, wind, raw }. Missing parts stay "".
function parseWeatherLine(line) {
  var out = { city: "", temp: "", wind: "", raw: String(line == null ? "" : line) }
  var parts = out.raw.split("·")
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].replace(/\s+/g, " ").trim()
    if (!p) continue
    if (/^temp\b/i.test(p)) out.temp = p.replace(/^temp\s*/i, "")
    else if (/^wind\b/i.test(p)) out.wind = p.replace(/^wind\s*/i, "")
    else if (!out.city) out.city = p
  }
  return out
}

// ISO-8601 week number (weeks start Monday; Jan 4 is always week 1 —
// so late-December days can belong to next year's week 1, and Jan 1-3
// can belong to last year's W52/W53).
function isoWeek(d) {
  var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  var day = t.getUTCDay() || 7
  t.setUTCDate(t.getUTCDate() + 4 - day)
  var yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
  return Math.ceil((((t - yearStart) / 86400000) + 1) / 7)
}

// The TODAY card: { weekday, date, week }.
function buildDateCard(d) {
  return {
    weekday: DAYS[d.getDay()],
    date: d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear(),
    week: "Week " + isoWeek(d)
  }
}

// "17 Oct 2026" → "17 Oct" — the slim weather·today tile drops the year
// (already implied by context; the width is precious).
function shortDate(dateStr) {
  return String(dateStr == null ? "" : dateStr).replace(/\s+\d{4}$/, "")
}

// µs (MPRIS Position / mpris:length) → "m:ss", "h:mm:ss" past an hour.
// Null/undefined/invalid or negative → "" (the media strip shows no
// clock until the data is real). Shared by the elapsed/total counter
// and the drag preview.
function fmtTime(us) {
  if (us === null || us === undefined || us === "") return ""
  var n = Number(us)
  if (!isFinite(n) || n < 0) return ""
  var s = Math.floor(n / 1e6)
  var pad = function(x) { return x < 10 ? "0" + x : String(x) }
  var sec = s % 60
  var min = Math.floor(s / 60) % 60
  var hr = Math.floor(s / 3600)
  return hr > 0 ? hr + ":" + pad(min) + ":" + pad(sec) : min + ":" + pad(sec)
}

// Date → "HH:MM" (24h, zero-padded local time) — the weather tile's
// third row opens with the clock. Invalid date → "".
function fmtClock(d) {
  if (!(d instanceof Date) || isNaN(d.getTime())) return ""
  var pad = function(x) { return x < 10 ? "0" + x : String(x) }
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

// Byte counts (traffic totals / rates) → compact human units:
// "912 B", "1.2 KB", "3.4 MB", "12.1 GB". Invalid/negative → "".
function fmtBytes(n) {
  if (n === null || n === undefined || n === "") return ""
  var v = Number(n)
  if (!isFinite(v) || v < 0) return ""
  if (v < 1024) return Math.round(v) + " B"
  if (v < 1048576) return (v / 1024).toFixed(1) + " KB"
  if (v < 1073741824) return (v / 1048576).toFixed(1) + " MB"
  return (v / 1073741824).toFixed(1) + " GB"
}
