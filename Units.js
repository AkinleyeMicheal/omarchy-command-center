// Units.js — unit conversion for the universal launcher.
//
// A registry of dimensions, each with a base unit and named units carrying a
// linear transform to/from that base: base = value * f + o (offset is only
// non-zero for temperature). Pure data + pure functions — no I/O, no eval —
// so it is fully unit-testable in node and safe to run on any query text.

// Each unit: { f: multiplier, o: offset (default 0), names: [aliases] }.
// Alias lookup is case-insensitive. base = value*f + o ; value = (base-o)/f.
var DIMENSIONS = {
  length: {
    base: "m",
    units: {
      km: { f: 1000, names: ["km", "kilometer", "kilometers", "kilometre", "kilometres"] },
      m: { f: 1, names: ["m", "meter", "meters", "metre", "metres"] },
      cm: { f: 0.01, names: ["cm", "centimeter", "centimeters", "centimetre", "centimetres"] },
      mm: { f: 0.001, names: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"] },
      um: { f: 1e-6, names: ["um", "micrometer", "micrometers", "micron", "microns"] },
      nm: { f: 1e-9, names: ["nm", "nanometer", "nanometers"] },
      mi: { f: 1609.344, names: ["mi", "mile", "miles", "statutemile"] },
      yd: { f: 0.9144, names: ["yd", "yard", "yards"] },
      ft: { f: 0.3048, names: ["ft", "foot", "feet"] },
      in: { f: 0.0254, names: ["in", "inch", "inches", "\""] },
      nmi: { f: 1852, names: ["nmi", "nauticalmile", "nauticalmiles"] }
    }
  },
  mass: {
    base: "kg",
    units: {
      t: { f: 1000, names: ["t", "tonne", "tonnes", "metricton"] },
      kg: { f: 1, names: ["kg", "kilogram", "kilograms", "kilo", "kilos"] },
      g: { f: 0.001, names: ["g", "gram", "grams"] },
      mg: { f: 1e-6, names: ["mg", "milligram", "milligrams"] },
      lb: { f: 0.45359237, names: ["lb", "lbs", "pound", "pounds"] },
      oz: { f: 0.028349523125, names: ["oz", "ounce", "ounces"] },
      st: { f: 6.35029318, names: ["st", "stone", "stones"] }
    }
  },
  temperature: {
    base: "c",
    special: true,
    units: {
      c: { f: 1, o: 0, names: ["c", "celsius", "centigrade", "°c"] },
      f: { f: 5 / 9, o: -32 * 5 / 9, names: ["f", "fahrenheit", "°f"] },
      k: { f: 1, o: -273.15, names: ["k", "kelvin", "°k"] }
    }
  },
  data: {
    base: "B",
    units: {
      bit: { f: 0.125, names: ["bit", "bits"] },
      B: { f: 1, names: ["b", "byte", "bytes"] },
      kb: { f: 1e3, names: ["kb", "kilobyte", "kilobytes"] },
      mb: { f: 1e6, names: ["mb", "megabyte", "megabytes"] },
      gb: { f: 1e9, names: ["gb", "gigabyte", "gigabytes"] },
      tb: { f: 1e12, names: ["tb", "terabyte", "terabytes"] },
      pb: { f: 1e15, names: ["pb", "petabyte", "petabytes"] },
      kib: { f: 1024, names: ["kib", "kibibyte", "kibibytes"] },
      mib: { f: 1048576, names: ["mib", "mebibyte", "mebibytes"] },
      gib: { f: 1073741824, names: ["gib", "gibibyte", "gibibytes"] }
    }
  },
  time: {
    base: "s",
    units: {
      ms: { f: 0.001, names: ["ms", "millisecond", "milliseconds"] },
      s: { f: 1, names: ["s", "sec", "secs", "second", "seconds"] },
      min: { f: 60, names: ["min", "mins", "minute", "minutes"] },
      h: { f: 3600, names: ["h", "hr", "hrs", "hour", "hours"] },
      d: { f: 86400, names: ["d", "day", "days"] },
      wk: { f: 604800, names: ["wk", "week", "weeks"] },
      yr: { f: 31557600, names: ["yr", "year", "years"] }
    }
  },
  speed: {
    base: "mps",
    units: {
      mps: { f: 1, names: ["mps", "m/s", "meterspersecond"] },
      kmh: { f: 1 / 3.6, names: ["kmh", "kph", "km/h", "kmph"] },
      mph: { f: 0.44704, names: ["mph", "mi/h", "milesperhour"] },
      knot: { f: 0.514444, names: ["kn", "knot", "knots"] },
      fts: { f: 0.3048, names: ["fts", "ft/s", "feetpersecond"] }
    }
  },
  area: {
    base: "m2",
    units: {
      m2: { f: 1, names: ["m2", "m²", "sqm", "squaremeter", "squaremeters"] },
      km2: { f: 1e6, names: ["km2", "km²", "sqkm", "squarekilometer"] },
      ft2: { f: 0.09290304, names: ["ft2", "ft²", "sqft", "squarefoot", "squarefeet"] },
      in2: { f: 0.00064516, names: ["in2", "in²", "sqin", "squareinch"] },
      acre: { f: 4046.8564224, names: ["acre", "acres"] },
      ha: { f: 10000, names: ["ha", "hectare", "hectares"] },
      mi2: { f: 2589988.110336, names: ["mi2", "mi²", "sqmi", "squaremile"] }
    }
  },
  volume: {
    base: "L",
    units: {
      L: { f: 1, names: ["l", "liter", "liters", "litre", "litres"] },
      mL: { f: 0.001, names: ["ml", "milliliter", "milliliters", "millilitre"] },
      m3: { f: 1000, names: ["m3", "m³", "cubicmeter", "cubicmeters"] },
      gal: { f: 3.785411784, names: ["gal", "gallon", "gallons", "usgal"] },
      qt: { f: 0.946352946, names: ["qt", "quart", "quarts"] },
      pt: { f: 0.473176473, names: ["pt", "pint", "pints"] },
      cup: { f: 0.2365882365, names: ["cup", "cups"] },
      floz: { f: 0.0295735295625, names: ["floz", "fl oz", "fluidounce"] },
      tbsp: { f: 0.0147867647813, names: ["tbsp", "tablespoon", "tablespoons"] },
      tsp: { f: 0.00492892159375, names: ["tsp", "teaspoon", "teaspoons"] }
    }
  },
  pressure: {
    base: "Pa",
    units: {
      Pa: { f: 1, names: ["pa", "pascal", "pascals"] },
      kPa: { f: 1000, names: ["kpa", "kilopascal"] },
      bar: { f: 100000, names: ["bar", "bars"] },
      mbar: { f: 100, names: ["mbar", "millibar", "hpa"] },
      atm: { f: 101325, names: ["atm", "atmosphere", "atmospheres"] },
      psi: { f: 6894.757293168, names: ["psi", "poundsqin"] },
      mmHg: { f: 133.322387415, names: ["mmhg", "torr"] }
    }
  },
  energy: {
    base: "J",
    units: {
      J: { f: 1, names: ["j", "joule", "joules"] },
      kJ: { f: 1000, names: ["kj", "kilojoule", "kilojoules"] },
      cal: { f: 4.184, names: ["cal", "calorie", "calories"] },
      kcal: { f: 4184, names: ["kcal", "kilocalorie", "foodcalorie"] },
      Wh: { f: 3600, names: ["wh", "watthour"] },
      kWh: { f: 3.6e6, names: ["kwh", "kilowatthour"] },
      btu: { f: 1055.05585262, names: ["btu"] }
    }
  },
  power: {
    base: "W",
    units: {
      W: { f: 1, names: ["w", "watt", "watts"] },
      kW: { f: 1000, names: ["kw", "kilowatt", "kilowatts"] },
      MW: { f: 1e6, names: ["mw", "megawatt", "megawatts"] },
      hp: { f: 745.6998715822702, names: ["hp", "horsepower"] }
    }
  },
  angle: {
    base: "deg",
    units: {
      deg: { f: 1, names: ["deg", "degree", "degrees", "°"] },
      rad: { f: 57.29577951308232, names: ["rad", "radian", "radians"] },
      grad: { f: 0.9, names: ["grad", "gradian", "gradians"] }
    }
  },
  force: {
    base: "N",
    units: {
      N: { f: 1, names: ["n", "newton", "newtons"] },
      kN: { f: 1000, names: ["kn", "kilonewton"] },
      lbf: { f: 4.4482216152605, names: ["lbf", "poundforce"] },
      kgf: { f: 9.80665, names: ["kgf", "kilogramforce"] }
    }
  },
  frequency: {
    base: "Hz",
    units: {
      Hz: { f: 1, names: ["hz", "hertz"] },
      kHz: { f: 1000, names: ["khz", "kilohertz"] },
      MHz: { f: 1e6, names: ["mhz", "megahertz"] },
      GHz: { f: 1e9, names: ["ghz", "gigahertz"] }
    }
  }
}

// Build a lowercase alias -> { dim, unit, f, o } lookup once.
var ALIAS = (function() {
  var map = {}
  for (var dim in DIMENSIONS) {
    var units = DIMENSIONS[dim].units
    for (var key in units) {
      var u = units[key]
      var f = u.f
      var o = u.o || 0
      for (var i = 0; i < u.names.length; i++) {
        map[u.names[i].toLowerCase()] = { dim: dim, unit: key, f: f, o: o }
      }
    }
  }
  return map
})()

// Resolve a unit token to its registry entry (case-insensitive).
function resolveUnit(token) {
  if (!token) return null
  return ALIAS[String(token).trim().toLowerCase()] || null
}

// Does this text look like a conversion ("5 km to mi", "100 f in c")?
function looksLikeConversion(text) {
  return conversionMatch(text) !== null
}

// Parse a conversion phrase. Returns { value, from, to } or null.
// Accepted shapes (optionally prefixed with "convert"):
//   <num> <from> (to|in|as|→|->) <to>
function conversionMatch(text) {
  var q = String(text || "").trim().toLowerCase()
  q = q.replace(/^convert\s+/, "").replace(/^how\s+many\s+/, "").trim()
  var m = q.match(/^([+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?)\s*([a-z°"][a-z0-9°"/]*)\s+(?:to|in|as|=|→|->|→)\s*([a-z°"][a-z0-9°"/]*)$/)
  if (!m) return null
  var value = Number(m[1])
  var from = resolveUnit(m[2])
  var to = resolveUnit(m[3])
  if (!isFinite(value) || !from || !to) return null
  if (from.dim !== to.dim) return null // "5 km to celsius" makes no sense
  return { value: value, from: from, to: to }
}

// Convert using registry entries. base = value*f + o ; value = (base-o)/f.
function convertValue(value, from, to) {
  var base = value * from.f + (from.o || 0)
  return (base - (to.o || 0)) / to.f
}

// Full conversion from a phrase. Returns { ok, value, pretty, fromLabel,
// toLabel } — pretty is the formatted result.
function convert(text) {
  var m = conversionMatch(text)
  if (!m) return { ok: false }
  var out = convertValue(m.value, m.from, m.to)
  if (!isFinite(out)) return { ok: false }
  return {
    ok: true,
    value: out,
    pretty: formatNumber(out),
    fromUnit: m.from.unit,
    toUnit: m.to.unit,
    fromDim: m.from.dim
  }
}

// Shared number formatting (kept local so Units has no cross-file dependency).
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
