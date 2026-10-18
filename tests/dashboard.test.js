// dashboard.test.js — node unit tests for Dashboard.js (Phase 6b home).
// Run: node tests/dashboard.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level declarations and no exports — eval into scope,
// same pattern as controls.test.js / feeds.test.js.
// eslint-disable-next-line no-eval
eval(fs.readFileSync(path.join(__dirname, "..", "Dashboard.js"), "utf8"))

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

// ------------------------------------------------- weather output parsing
{
  const out = parseWeatherOutput("\ue313\nIbadan  ·  Temp 23°C  ·  Wind ↑4km/h\n")
  check("output: icon + line split", out,
    { icon: "\ue313", line: "Ibadan  ·  Temp 23°C  ·  Wind ↑4km/h", detail: "" })
  check("output: lone status line", parseWeatherOutput("Lagos  ·  Temp 30°C\n").icon, "")
  check("output: lone glyph", parseWeatherOutput("\ue314"),
    { icon: "\ue314", line: "", detail: "" })
  check("output: empty → empty", parseWeatherOutput(""),
    { icon: "", line: "", detail: "" })
  check("output: null → empty", parseWeatherOutput(null),
    { icon: "", line: "", detail: "" })

  // Third line (8.3): "condition<TAB>country" — kept apart, not joined
  // into the status line.
  const three = parseWeatherOutput(
    "\ue313\nIbadan  ·  Temp 28°C  ·  Wind ↗10km/h\nLight rain showers\tNigeria\n")
  check("output: detail line kept separate", three,
    { icon: "\ue313", line: "Ibadan  ·  Temp 28°C  ·  Wind ↗10km/h",
      detail: "Light rain showers\tNigeria" })
}

// ------------------------------------------------------ weather detail (8.3)
{
  const d = parseWeatherDetail("Light rain showers\tNigeria")
  check("detail: condition", d.condition, "Light rain showers")
  check("detail: country", d.country, "Nigeria")
  const partial = parseWeatherDetail("Cloudy\t")
  check("detail: missing country tolerated", [partial.condition, partial.country],
    ["Cloudy", ""])
  const empty = parseWeatherDetail("")
  check("detail: empty → empty", [empty.condition, empty.country], ["", ""])
  const nullish = parseWeatherDetail(null)
  check("detail: null → empty", [nullish.condition, nullish.country], ["", ""])
}

// ------------------------------------------------------------- fmtClock (8.3)
{
  check("clock: pads", fmtClock(new Date(2026, 9, 17, 9, 5)), "09:05")
  check("clock: noon", fmtClock(new Date(2026, 9, 17, 14, 32)), "14:32")
  check("clock: invalid → empty", fmtClock(new Date("nope")), "")
  check("clock: non-date → empty", fmtClock("2026-10-17"), "")
  check("clock: null → empty", fmtClock(null), "")
}

// ------------------------------------------------------------- fmtBytes (8.3)
{
  check("bytes: zero", fmtBytes(0), "0 B")
  check("bytes: bytes", fmtBytes(912), "912 B")
  check("bytes: kb", fmtBytes(1536), "1.5 KB")
  check("bytes: mb", fmtBytes(3.4 * 1048576), "3.4 MB")
  check("bytes: gb", fmtBytes(12.1 * 1073741824), "12.1 GB")
  check("bytes: negative → empty", fmtBytes(-5), "")
  check("bytes: NaN → empty", fmtBytes("nope"), "")
  check("bytes: null → empty", fmtBytes(null), "")
}

// ---------------------------------------------------- weather line parsing
{
  const w = parseWeatherLine("Ibadan  ·  Temp 23°C  ·  Wind ↑4km/h")
  check("line: city", w.city, "Ibadan")
  check("line: temp", w.temp, "23°C")
  check("line: wind", w.wind, "↑4km/h")

  const single = parseWeatherLine("Ibadan only")
  check("line: single part = city", [single.city, single.temp, single.wind],
    ["Ibadan only", "", ""])

  const missing = parseWeatherLine("Accra  ·  Temp 31°C")
  check("line: missing wind tolerated", [missing.city, missing.temp, missing.wind],
    ["Accra", "31°C", ""])

  check("line: empty city", parseWeatherLine("").city, "")
  check("line: raw preserved", parseWeatherLine(" X  ·  Temp 1°C ").raw, " X  ·  Temp 1°C ")
}

// ------------------------------------------------------------- ISO weeks
check("week: 2026-01-01 → W1 (Thu year start)",
  isoWeek(new Date(2026, 0, 1)), 1)
check("week: 2026-10-17 → W42",
  isoWeek(new Date(2026, 9, 17)), 42)
check("week: 2026-12-31 → W53 (53-week year)",
  isoWeek(new Date(2026, 11, 31)), 53)
check("week: 2027-01-01 → still 2026's W53",
  isoWeek(new Date(2027, 0, 1)), 53)
check("week: 2025-12-29 → 2026's W1 (cross-year)",
  isoWeek(new Date(2025, 11, 29)), 1)

// ----------------------------------------------------------- date card
check("date: today (2026-10-17 = Saturday)",
  buildDateCard(new Date(2026, 9, 17)),
  { weekday: "Saturday", date: "17 Oct 2026", week: "Week 42" })

check("date: leap day (2028-02-29 = Tuesday)",
  buildDateCard(new Date(2028, 1, 29)),
  { weekday: "Tuesday", date: "29 Feb 2028", week: "Week 9" })

check("date: new year day (2027-01-01 = Friday)",
  buildDateCard(new Date(2027, 0, 1)),
  { weekday: "Friday", date: "1 Jan 2027", week: "Week 53" })

check("date: single-digit day is unpadded",
  buildDateCard(new Date(2026, 0, 5)).date, "5 Jan 2026")

// ------------------------------------------------------------- time fmt
check("fmtTime: zero", fmtTime(0), "0:00")
check("fmtTime: 83s → m:ss", fmtTime(83e6), "1:23")
check("fmtTime: rounds down", fmtTime(65.4e6), "1:05")
check("fmtTime: past the hour", fmtTime(3661e6), "1:01:01")
check("fmtTime: exactly an hour", fmtTime(3600e6), "1:00:00")
check("fmtTime: negative → empty", fmtTime(-1), "")
check("fmtTime: null → empty", fmtTime(null), "")

// ------------------------------------------------------------ short date
check("shortDate: drops the year", shortDate("17 Oct 2026"), "17 Oct")
check("shortDate: no year → unchanged", shortDate("5 Jan"), "5 Jan")
check("shortDate: empty/null safe", [shortDate(""), shortDate(null)], ["", ""])

// ---------------------------------------------------------------- summary
console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
