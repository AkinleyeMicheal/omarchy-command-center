// providers.test.js — node unit tests for MathEval.js and Units.js
// Run: node tests/providers.test.js

const fs = require("fs")
const path = require("path")

// Both modules are QML JS with top-level function declarations and no
// exports; eval them into this scope exactly like model.test.js does.
// (They share an identical `formatNumber`, so the overlap is harmless.)
for (const name of ["MathEval.js", "Units.js"]) {
  // eslint-disable-next-line no-eval
  eval(fs.readFileSync(path.join(__dirname, "..", name), "utf8"))
}

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

function okEval(expr) {
  const r = evaluate(expr)
  return r.ok ? r.pretty : null
}

// ------------------------------------------------------------ MathEval
check("math: 2+2", okEval("2+2"), "4")
check("math: order of ops", okEval("2+3*4"), "14")
check("math: parentheses", okEval("(2+3)*4"), "20")
check("math: power right-assoc", okEval("2^3^2"), "512")
check("math: unary minus", okEval("-5+3"), "-2")
check("math: division", okEval("10/4"), "2.5")
check("math: modulo", okEval("10%3"), "1")
check("math: decimals", okEval("1.5*2"), "3")
check("math: sqrt", okEval("sqrt(144)"), "12")
check("math: nested fn", okEval("sqrt(3^2+4^2)"), "5")
check("math: constants", okEval("pi"), "3.141593")
check("math: sin(pi/2)", okEval("sin(pi/2)"), "1")
check("math: log10", okEval("log(1000)"), "3")
check("math: ln(e)", okEval("ln(e)"), "1")
check("math: float noise rounded", okEval("0.1+0.2"), "0.3")
check("math: big", okEval("1e3*2"), "2000")
check("math: abs/floor", okEval("floor(abs(-3.7))"), "3")

// things that must NOT evaluate (no calculator row)
check("math: plain word rejected", evaluate("hello").ok, false)
check("math: bare number evaluates (gate is looksLikeMath)", evaluate("42").ok, true)
check("math: div by zero rejected", evaluate("1/0").ok, false)
check("math: injection rejected", evaluate("2); rm -rf /; (").ok, false)
check("math: semicolon rejected", evaluate("2;3").ok, false)
check("math: quote rejected", evaluate("2+\"x\"").ok, false)
check("math: unknown fn rejected", evaluate("foo(2)").ok, false)
check("math: unbalanced rejected", evaluate("(2+3").ok, false)

check("looksLikeMath: 2+2", looksLikeMath("2+2"), true)
check("looksLikeMath: sqrt(144)", looksLikeMath("sqrt(144)"), true)
check("looksLikeMath: word", looksLikeMath("firefox"), false)
check("looksLikeMath: bare num", looksLikeMath("42"), false)
check("looksLikeMath: version 1.2.3", looksLikeMath("1.2.3"), false)
check("looksLikeMath: time 12:30", looksLikeMath("12:30"), false)

// ------------------------------------------------------------ Units
check("units: km to mi", convert("5 km to mi").pretty, "3.106856")
check("units: mi to km", convert("5 mi to km").pretty, "8.04672")
check("units: c to f", convert("0 c to f").pretty, "32")
check("units: f to c", convert("98.6 f to c").pretty, "37")
check("units: k to c", convert("300 k to c").pretty, "26.85")
check("units: kg to lb", convert("10 kg to lb").pretty, "22.046226")
check("units: gb to mb", convert("2 gb to mb").pretty, "2000")
check("units: gib to mib", convert("1 gib to mib").pretty, "1024")
check("units: hour to min", convert("1.5 h to min").pretty, "90")
check("units: mph to kmh", convert("60 mph to kmh").pretty, "96.56064")
check("units: in to cm", convert("12 in to cm").pretty, "30.48")
check("units: full words", convert("5 kilometers to miles").pretty, "3.106856")
check("units: prefix convert", convert("convert 5 km to mi").pretty, "3.106856")
check("units: keyword 'in'", convert("100 f in c").pretty, "37.777778")
check("units: arrow", convert("5 km -> mi").pretty, "3.106856")
check("units: energy kcal to j", convert("1 kcal to j").pretty, "4184")

// must not convert
check("units: mismatched dim", convert("5 km to c").ok, false)
check("units: no unit", convert("5 to mi").ok, false)
check("units: garbage", convert("hello world").ok, false)
check("units: not a conversion", convert("2+2").ok, false)

check("looksLikeConversion: yes", looksLikeConversion("5 km to mi"), true)
check("looksLikeConversion: no", looksLikeConversion("theme set"), false)

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
