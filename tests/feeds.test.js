// feeds.test.js — node unit tests for FeedParser.js (Phase 6 news).
// Run: node tests/feeds.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level declarations and no exports — eval into scope,
// same pattern as controls.test.js.
// eslint-disable-next-line no-eval
eval(fs.readFileSync(path.join(__dirname, "..", "FeedParser.js"), "utf8"))

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

// ------------------------------------------------------------ RSS 2.0
const RSS = `<?xml version="1.0"?>
<rss version="2.0"><channel>
<title>Fixture Feed</title>
<item>
  <title>First &amp; foremost &lt;really&gt;</title>
  <link>https://example.com/a?x=1&amp;y=2</link>
  <pubDate>Mon, 12 Jan 2026 10:00:00 +0000</pubDate>
  <description><![CDATA[<p>Hello <b>world</b></p>]]></description>
</item>
<item>
  <title>Second story</title>
  <link>https://example.com/b</link>
  <pubDate>Tue, 13 Jan 2026 10:00:00 +0000</pubDate>
</item>
<item>
  <title>Third, no description</title>
  <guid>https://example.com/c</guid>
  <pubDate>Sun, 11 Jan 2026 10:00:00 +0000</pubDate>
</item>
</channel></rss>`

{
  const items = parse(RSS, "Fixture")
  check("rss: item count", items.length, 3)
  check("rss: newest first", items.map((i) => i.title),
    ["Second story", "First & foremost <really>", "Third, no description"])
  check("rss: entities decoded in title",
    items[1].title, "First & foremost <really>")
  check("rss: &amp; in link decoded",
    items[1].url, "https://example.com/a?x=1&y=2")
  check("rss: source attached", items[0].source, "Fixture")
  check("rss: dates parsed to ms",
    items[0].published > 0 && items[0].published > items[2].published, true)
  check("rss: guid-only item kept via guid fallback",
    items.some((i) => i.title.startsWith("Third")), true)
}

// The guid-only item: our parser needs <link>; a guid that is a URL is a
// common pattern — accept it as link fallback.
{
  const feed = `<rss><channel><item>
    <title>G</title><guid>https://example.com/g</guid>
    <pubDate>Mon, 12 Jan 2026 10:00:00 +0000</pubDate>
  </item></channel></rss>`
  const items = parse(feed, "G")
  check("rss: guid URL used when no link",
    items.length === 1 ? items[0].url : "missing", "https://example.com/g")
}

// ---------------------------------------------------------------- Atom
const ATOM = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Fixture</title>
  <entry>
    <title>Atom one</title>
    <link rel="self" href="https://example.net/self"/>
    <link rel="alternate" href="https://example.net/one"/>
    <published>2026-01-14T09:00:00Z</published>
    <summary>hi</summary>
  </entry>
  <entry>
    <title>Atom two</title>
    <link href="https://example.net/two"/>
    <updated>2026-01-15T09:00:00Z</updated>
  </entry>
  <entry>
    <title>No date entry</title>
    <link href="https://example.net/three"/>
  </entry>
</feed>`

{
  const items = parse(ATOM, "Atom Fixture")
  check("atom: entry count", items.length, 3)
  check("atom: rel=alternate beats rel=self",
    items.find((i) => i.title === "Atom one").url, "https://example.net/one")
  check("atom: bare href accepted",
    items.find((i) => i.title === "Atom two").url, "https://example.net/two")
  check("atom: updated parsed",
    items[0].title, "Atom two")
  check("atom: undated entry sorts last",
    items[2].title, "No date entry")
  check("atom: undated published is 0", items[2].published, 0)
}

// ------------------------------------------------------------- junk in
{
  check("empty string → []", parse("", "X"), [])
  check("null → []", parse(null, "X"), [])
  check("no items → []", parse("<rss><channel><title>x</title></channel></rss>", "X"), [])
  check("truncated xml → graceful", parse("<item><title>Half", "X"), [])
  check("title without link skipped",
    parse("<rss><channel><item><title>lonely</title></item></channel></rss>", "X"), [])
  check("html junk does not crash",
    parse("<<<<>>><item><title>t</title><link>u</link></item>", "X").length, 1)
}

// ------------------------------------------------------- payload shaping
{
  const payload = {
    fetchedAt: 1, errors: 0,
    feeds: [
      { id: "a", name: "A", url: "u", xml: RSS },
      { id: "b", name: "B", url: "u", xml: ATOM },
      { id: "c", name: "C", url: "u", xml: "" } // failed fetch → no items
    ]
  }
  const all = itemsFromPayload(payload, 100)
  check("payload: both feeds flattened", all.length, 6)
  check("payload: global newest-first", all[0].title, "Atom two")
  check("payload: sources correct",
    [...new Set(all.map((i) => i.source))].sort(), ["A", "B"])
  check("payload: cap enforced", itemsFromPayload(payload, 2).length, 2)
  check("payload: junk payload → []", itemsFromPayload(null, 10), [])
  check("payload: missing feeds → []", itemsFromPayload({}, 10), [])
}

// ------------------------------------------------------- initials (8.11)
// The reader downloads no feed-supplied images: rows and cards show the
// feed's initials instead of favicons.
{
  check("initials: two words", initialsFor("Hacker News"), "HN")
  check("initials: one word", initialsFor("Lobsters"), "L")
  check("initials: punctuation-only words skipped", initialsFor("the @ 37"), "T3")
  check("initials: empty", initialsFor(""), "")
  check("initials: null", initialsFor(null), "")
  check("initials: unicode", initialsFor("Héllo Wörld"), "HW")
}

// ---------------------------------------------------------- excerpts
{
  const d = `<rss><channel><item>
    <title>E</title><link>https://e.com/e</link>
    <description><![CDATA[<p>Strip the <b>markup</b>, keep the &amp; entities.</p>]]></description>
  </item></channel></rss>`
  check("excerpt: CDATA HTML stripped + entities decoded",
    parse(d, "X")[0].excerpt, "Strip the markup, keep the & entities.")
  check("excerpt: no ]]&gt; leak from CDATA",
    parse(d, "X")[0].excerpt.indexOf("]]>"), -1)

  const words = Array.from({ length: 120 }, (_, i) => "word" + i).join(" ")
  const long = `<rss><channel><item>
    <title>L</title><link>https://e.com/l</link>
    <description>${words}</description>
  </item></channel></rss>`
  const ex = parse(long, "X")[0].excerpt
  check("excerpt: truncated ≤ 601 chars", ex.length <= 601, true)
  check("excerpt: ends with ellipsis", ex.slice(-1), "…")
  // The char right after the kept text (in the source) must be the
  // space we cut at — proves no mid-token cut.
  check("excerpt: cut lands on a word boundary",
    words.charAt(ex.slice(0, -1).length), " ")

  const encoded = `<rss><channel><item>
    <title>C</title><link>https://e.com/c</link>
    <content:encoded><![CDATA[<p>Full content body with enough words to qualify.</p>]]></content:encoded>
  </item></channel></rss>`
  check("excerpt: content:encoded fallback",
    parse(encoded, "X")[0].excerpt, "Full content body with enough words to qualify.")

  const none = `<rss><channel><item>
    <title>N</title><link>https://e.com/n</link>
  </item></channel></rss>`
  check("excerpt: none → empty string", parse(none, "X")[0].excerpt, "")

  // Lobsters-style: HTML arrives entity-escaped, not CDATA'd.
  const esc = `<rss><channel><item>
    <title>S</title><link>https://e.com/s</link>
    <description>&lt;p&gt;Escaped &lt;b&gt;markup&lt;/b&gt; in the description becomes plain readable text.&lt;/p&gt;</description>
  </item></channel></rss>`
  check("excerpt: escaped HTML stripped (Lobsters style)",
    parse(esc, "X")[0].excerpt,
    "Escaped markup in the description becomes plain readable text.")

  // HN/Lobsters ship a lone Comments link as the description — must be
  // treated as "no excerpt", not a one-word preview.
  const hnComments = `<rss><channel><item>
    <title>H</title><link>https://e.com/h</link>
    <description><![CDATA[<a href="https://e.com/item?id=1">Comments</a>]]></description>
  </item></channel></rss>`
  check("excerpt: Comments link remnant dropped",
    parse(hnComments, "X")[0].excerpt, "")
}

// ------------------------------------- feed-borne hang guards (8.11)
{
  // A feed of unclosed <item> openers must not make the parser go
  // quadratic (measured: minutes of frozen shell on QML's JS engine
  // before the split-based extraction). Correctness check: nothing
  // parses, and it parses instantly.
  check("flood: unclosed <item> openers → []",
    parse("<item><title>x</title>".repeat(20000), "X"), [])
  // Mixed-case closings still close (the old regex was /i too).
  const mixed = "<rss><channel><item><title>M</title><link>https://e.com/m</link></ITEM></channel></rss>"
  check("mixed-case </ITEM> closes", parse(mixed, "X").length, 1)
  // An unclosed trailing item is dropped (as the old regex did).
  const trail = "<rss><channel><item><title>Closed</title><link>https://e.com/c</link></item><item><title>Half</title>"
  check("unclosed trailing item dropped", parse(trail, "X").map((i) => i.title), ["Closed"])
}

// ------------------------------------------- feed facts on every item
{
  const payload = {
    fetchedAt: 1, errors: 0,
    feeds: [{ id: "a", name: "Hacker News", url: "https://a.example/feed.xml",
      xml: RSS }]
  }
  const items = itemsFromPayload(payload, 10)
  check("payload: feed initials ride on items", items[0].initials, "HN")
  check("payload: feed url rides on items", items[0].feedUrl,
    "https://a.example/feed.xml")
  const bare = itemsFromPayload({ feeds: [{ name: "B", xml: RSS }] }, 10)
  check("payload: missing initials/feedUrl → expected defaults",
    [bare[0].initials, bare[0].feedUrl], ["B", ""])
}

// ---------------------------------------------------------------- summary
console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
