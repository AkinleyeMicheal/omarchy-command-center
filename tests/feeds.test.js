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

// ------------------------------------------------------- hero extraction
{
  const media = `<rss><channel><item>
    <title>Hero</title><link>https://e.com/hero</link>
    <media:content type="video/mp4" url="https://e.com/v.mp4"/>
    <media:thumbnail url="https://e.com/thumb.jpg"/>
  </item></channel></rss>`
  check("hero: video media:content skipped → thumbnail",
    parse(media, "X")[0].image, "https://e.com/thumb.jpg")

  const mediaImg = `<rss><channel><item>
    <title>M</title><link>https://e.com/m</link>
    <media:content url="https://e.com/pic.png"/>
  </item></channel></rss>`
  check("hero: untyped media:content accepted",
    parse(mediaImg, "X")[0].image, "https://e.com/pic.png")

  const enc = `<rss><channel><item>
    <title>E</title><link>https://e.com/e</link>
    <enclosure url="https://e.com/audio.mp3" type="audio/mpeg"/>
    <enclosure url="https://e.com/pic.jpg?w=800" type="image/jpeg"/>
  </item></channel></rss>`
  check("hero: image enclosure wins, audio skipped",
    parse(enc, "X")[0].image, "https://e.com/pic.jpg?w=800")

  const encExt = `<rss><channel><item>
    <title>X</title><link>https://e.com/x</link>
    <enclosure url="https://e.com/pic.webp"/>
  </item></channel></rss>`
  check("hero: untyped enclosure accepted by extension",
    parse(encExt, "X")[0].image, "https://e.com/pic.webp")

  const descImg = `<rss><channel><item>
    <title>D</title><link>https://e.com/d</link>
    <description><![CDATA[<p><img src="https://cdn.e.com/lead.png" alt=""></p><p>Body</p>]]></description>
  </item></channel></rss>`
  check("hero: first <img> in description used as last resort",
    parse(descImg, "X")[0].image, "https://cdn.e.com/lead.png")

  const plain = `<rss><channel><item>
    <title>P</title><link>https://e.com/p</link>
    <description>no images here</description>
  </item></channel></rss>`
  check("hero: none → empty string", parse(plain, "X")[0].image, "")
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

  const escImg = `<rss><channel><item>
    <title>I</title><link>https://e.com/i</link>
    <description>&lt;img src="https://e.com/esc.png"&gt;body&lt;/description&gt;</description>
  </item></channel></rss>`
  check("hero: image found inside escaped description",
    parse(escImg, "X")[0].image, "https://e.com/esc.png")
}

// ------------------------------------------- feed facts on every item
{
  const payload = {
    fetchedAt: 1, errors: 0,
    feeds: [{ id: "a", name: "A", url: "https://a.example/feed.xml",
      logo: "/s/news-img/feed-a.img", xml: RSS }]
  }
  const items = itemsFromPayload(payload, 10)
  check("payload: feed logo rides on items", items[0].logo,
    "/s/news-img/feed-a.img")
  check("payload: feed url rides on items", items[0].feedUrl,
    "https://a.example/feed.xml")
  const bare = itemsFromPayload({ feeds: [{ name: "B", xml: RSS }] }, 10)
  check("payload: missing logo/feedUrl → empty strings",
    [bare[0].logo, bare[0].feedUrl], ["", ""])
}

// ---------------------------------------------------------------- summary
console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
