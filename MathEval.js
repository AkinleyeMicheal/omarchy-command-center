// MathEval.js — a tiny, SAFE arithmetic evaluator for the universal
// launcher's inline calculator.
//
// Deliberately avoids eval() and any shell: the expression is parsed by a
// recursive-descent parser into a value. Only numbers, + - * / % ^, parens,
// a fixed function set, and named constants are accepted — anything else
// makes it return { ok: false } (never throws), so a malformed query simply
// produces no calculator row.
//
// No .pragma library: pure functions only, imported per-file like the other
// model scripts.

// ------------------------------------------------------------ tokenizing
function tokenize(src) {
  var toks = []
  var i = 0
  var s = String(src)
  while (i < s.length) {
    var ch = s[i]
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") { i++; continue }
    if (ch >= "0" && ch <= "9" || (ch === "." && s[i + 1] >= "0" && s[i + 1] <= "9")) {
      var j = i
      while (j < s.length && (s[j] >= "0" && s[j] <= "9" || s[j] === ".")) j++
      // optional scientific-notation exponent: 1e3, 2.5e-3, 1E+12
      if (j < s.length && (s[j] === "e" || s[j] === "E")) {
        var ej = j + 1
        if (ej < s.length && (s[ej] === "+" || s[ej] === "-")) ej++
        if (ej < s.length && s[ej] >= "0" && s[ej] <= "9") {
          while (ej < s.length && s[ej] >= "0" && s[ej] <= "9") ej++
          j = ej
        }
      }
      var text = s.slice(i, j)
      var num = Number(text)
      if (!isFinite(num)) return null
      toks.push({ t: "num", v: num })
      i = j
      continue
    }
    if (/[a-zA-Z_]/.test(ch)) {
      var k = i
      while (k < s.length && /[a-zA-Z0-9_]/.test(s[k])) k++
      toks.push({ t: "name", v: s.slice(i, k) })
      i = k
      continue
    }
    if ("+-*/%^(),".indexOf(ch) >= 0) { toks.push({ t: ch }); i++; continue }
    return null // any other character (letters outside names, $, ;, quotes…) aborts
  }
  return toks
}

// ------------------------------------------------------------ functions
var FUNCS = {
  sqrt: Math.sqrt, cbrt: Math.cbrt,
  sin: Math.sin, cos: Math.cos, tan: Math.tan,
  asin: Math.asin, acos: Math.acos, atan: Math.atan,
  log: Math.log10, ln: Math.log, log2: Math.log2,
  abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  exp: Math.exp, sign: Math.sign,
  rad: function(x) { return x * Math.PI / 180 }, deg: function(x) { return x * 180 / Math.PI }
}
var CONSTS = { pi: Math.PI, e: Math.E, tau: 2 * Math.PI }

// ------------------------------------------------------------ parser
// expr   := term (('+'|'-') term)*
// term   := unary (('*'|'/'|'%') unary)*
// unary  := ('-'|'+') unary | power
// power  := primary ('^' unary)?        (right-associative)
// primary:= number | const | name '(' expr ')' | '(' expr ')'
function parse(src) {
  var toks = tokenize(src)
  if (!toks || toks.length === 0) return null
  var pos = 0

  function peek() { return pos < toks.length ? toks[pos] : null }
  function is(t) { var tk = peek(); return tk && tk.t === t }
  function eat(t) { if (is(t)) { pos++; return true } return false }

  function expr() {
    var left = term()
    while (is("+") || is("-")) {
      var op = toks[pos].t; pos++
      var right = term()
      if (left === null || right === null) return null
      left = op === "+" ? left + right : left - right
    }
    return left
  }

  function term() {
    var left = unary()
    while (is("*") || is("/") || is("%")) {
      var op = toks[pos].t; pos++
      var right = unary()
      if (left === null || right === null) return null
      if (op === "*") left = left * right
      else if (op === "/") { if (right === 0) return null; left = left / right }
      else { if (right === 0) return null; left = left % right }
    }
    return left
  }

  function unary() {
    if (is("-")) { pos++; var v = unary(); return v === null ? null : -v }
    if (is("+")) { pos++; return unary() }
    return power()
  }

  function power() {
    var base = primary()
    if (is("^")) { pos++; var exp = unary(); return base === null || exp === null ? null : Math.pow(base, exp) }
    return base
  }

  function primary() {
    var tk = peek()
    if (!tk) return null
    if (tk.t === "num") { pos++; return tk.v }
    if (tk.t === "(") {
      pos++
      var v = expr()
      if (!eat(")")) return null
      return v
    }
    if (tk.t === "name") {
      pos++
      var name = tk.v.toLowerCase()
      if (Object.prototype.hasOwnProperty.call(CONSTS, name)) return CONSTS[name]
      if (Object.prototype.hasOwnProperty.call(FUNCS, name)) {
        if (!eat("(")) return null
        var arg = expr()
        if (!eat(")")) return null
        if (arg === null) return null
        var out = FUNCS[name](arg)
        return typeof out === "number" && isFinite(out) ? out : null
      }
      return null
    }
    return null
  }

  var result = expr()
  if (result === null || pos !== toks.length) return null
  return result
}

// ------------------------------------------------------------ public
// Evaluate a math expression string. Returns { ok, value, pretty }.
// ok=false for anything that isn't a clean, finite arithmetic expression.
function evaluate(src) {
  var v = parse(src)
  if (v === null || typeof v !== "number" || !isFinite(v)) return { ok: false }
  return { ok: true, value: v, pretty: formatNumber(v) }
}

// Human-friendly number: round float noise, drop trailing zeros, cap digits.
function formatNumber(v) {
  if (Object.is(v, -0)) v = 0
  var rounded = Math.round(v * 1e6) / 1e6
  if (Math.abs(rounded) >= 1e15 || (rounded !== 0 && Math.abs(rounded) < 1e-6)) {
    return rounded.toExponential(6).replace(/\.?0+e/, "e")
  }
  var s = String(rounded)
  if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
  return s
}

// Does this text plausibly LOOK like a math expression (so we only show the
// calculator row when it's likely intended)? Requires at least one digit and
// one operator/paren — a bare word or number is not a calculation.
function looksLikeMath(text) {
  var q = String(text || "").trim()
  if (!q || q.length > 80) return false
  if (!/[0-9]/.test(q)) return false
  if (!/[+\-*/%^()]/.test(q)) return false
  // reject things that are clearly not math (dates, versions, paths, units)
  if (/[\/\\]/.test(q) && /\d+\.\d+\.\d+/.test(q)) return false // version numbers
  if (/:\d/.test(q)) return false // times / ranges like 12:30
  return true
}
