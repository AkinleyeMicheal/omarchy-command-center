// FeedParser.js — pure RSS 2.0 / Atom parser for the News group
// (Phase 6). Hand-rolled on purpose: QML's JS engine has no DOMParser,
// and keeping it pure means node tests drive it with real feed
// fixtures. Input: raw feed XML (as embedded in news.json by
// fetch-feeds.sh). Output: items {title, url, published, source}.
//
// Limits (documented, deliberate): no namespaces beyond atom:link's
// href/rel, no nested item-in-item, no date → published 0 (sorts last).

function decodeEntities(s) {
  return String(s == null ? "" : s)
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&amp;/g, "&")   // &amp; LAST, or &amp;lt; double-decodes
}

function stripTags(s) {
  // Unwrap CDATA BEFORE tag-stripping: stripping `<![CDATA[<p>x</p>]]>`
  // raw would leave a literal "]]>" in the text.
  var t = String(s == null ? "" : s)
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/<[^>]*>/g, " ")
  return decodeEntities(t)
    .replace(/\s+/g, " ")
    // A stripped inline tag between word and punctuation ("</b>," in
    // "markup</b>, keep") must not leave a space before the mark.
    .replace(/\s+([,.;:!?)\]”])/g, "$1")
    .trim()
}

// First <name>…</name> block's inner text (case-insensitive).
function tag(block, name) {
  var m = String(block).match(
    new RegExp("<" + name + "[^>]*>([\\s\\S]*?)</" + name + ">", "i"))
  return m ? m[1].trim() : ""
}

// Atom links: prefer rel="alternate" (or no rel), fall back to the
// first href, then to a plain <link>…</link> body (RSS-style).
function atomLink(block) {
  var links = String(block).match(/<link[^>]*>/gi) || []
  var first = ""
  for (var i = 0; i < links.length; i++) {
    var h = links[i].match(/href="([^"]*)"/i)
    if (!h || !h[1]) continue
    var rel = links[i].match(/rel="([^"]*)"/i)
    if (!rel || rel[1] === "alternate") return h[1]
    if (!first) first = h[1]
  }
  if (first) return first
  return stripTags(tag(block, "link"))
}

// Double-quoted XML attribute reader (single-quote attributes are a
// documented v1 limit). Entities decoded — image URLs carry &amp;.
function attr(tagText, name) {
  var m = String(tagText).match(new RegExp(name + '="([^"]*)"', "i"))
  return m ? decodeEntities(m[1]) : ""
}

// Article hero image, preference order: media:content (image type or
// untyped), media:thumbnail, enclosure with an image type/extension,
// then the first <img> the feed embedded in its description HTML.
// First http(s) candidate wins; none → "" (the row keeps its feed logo,
// the card simply renders without a hero).
function heroImage(block) {
  var cands = []
  var m, re
  re = /<media:content\b[^>]*>/gi
  while ((m = re.exec(block)) !== null) {
    var t = attr(m[0], "type")
    if (t && !/^image\//i.test(t)) continue
    var u = attr(m[0], "url")
    if (u) cands.push(u)
  }
  re = /<media:thumbnail\b[^>]*>/gi
  while ((m = re.exec(block)) !== null) {
    var u2 = attr(m[0], "url")
    if (u2) cands.push(u2)
  }
  re = /<enclosure\b[^>]*>/gi
  while ((m = re.exec(block)) !== null) {
    var u3 = attr(m[0], "url")
    if (!u3) continue
    var t3 = attr(m[0], "type")
    var isImage = t3 ? /^image\//i.test(t3)
      : /\.(jpe?g|png|gif|webp|avif)([?#]|$)/i.test(u3)
    if (isImage) cands.push(u3)
  }
  // Decode first: the <img> may sit in escaped HTML (&lt;img src=…&gt;).
  var desc = decodeEntities(
    tag(block, "description") || tag(block, "summary") || "")
  var img = desc.match(/<img[^>]*src\s*=\s*["']([^"']+)["']/i)
  if (img) cands.push(img[1])
  for (var i = 0; i < cands.length; i++) {
    if (/^https?:\/\//i.test(cands[i])) return cands[i]
  }
  return ""
}

// Excerpt-only variant: decode FIRST so escaped markup (&lt;p&gt;…, as
// Lobsters ships it) becomes real tags and can be stripped, then strip,
// then decode what sat inside the markup. Deliberately different from
// stripTags (titles): a title's &lt;really&gt; is text, not markup.
function stripMarkup(s) {
  var t = decodeEntities(String(s == null ? "" : s)
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1"))
  return decodeEntities(t.replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:!?)\]”])/g, "$1")
    .trim()
}

// Feed-provided prose for the detail card: description → summary →
// content:encoded, HTML stripped, truncated at a word boundary. Feed
// text only — the reader never fetches article pages itself.
function excerptText(block, limit) {
  var raw = tag(block, "description") || tag(block, "summary")
    || tag(block, "content:encoded") || ""
  var text = stripMarkup(raw)
  // Too short to preview = no excerpt: link remnants like "Comments"
  // (what HN and Lobsters ship as descriptions) must not render as a
  // one-word preview. Real summaries clear this comfortably.
  if (text.length < 30) return ""
  var max = limit || 600
  if (text.length <= max) return text
  var cut = text.lastIndexOf(" ", max)
  if (cut < Math.floor(max * 0.6)) cut = max
  return text.slice(0, cut).trim() + "…"
}

function parseDate(s) {
  if (!s) return 0
  var t = Date.parse(s)
  return isNaN(t) ? 0 : t
}

// One feed's XML → newest-first items. Malformed/empty feeds → [].
function parse(xml, source) {
  var text = String(xml == null ? "" : xml)
  var blocks = text.match(/<(item|entry)[\s\S]*?<\/\1>/gi) || []
  var items = []
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i]
    var title = stripTags(tag(b, "title"))
    var url = atomLink(b)
    if (!url) {
      // RSS items with only a permalink-shaped <guid> (very common).
      var guid = stripTags(tag(b, "guid"))
      if (/^https?:\/\//i.test(guid)) url = guid
    }
    var dateStr = tag(b, "pubDate") || tag(b, "published")
      || tag(b, "updated") || tag(b, "date")
    if (!title || !url) continue
    items.push({
      title: title, url: url, published: parseDate(stripTags(dateStr)),
      source: String(source == null ? "" : source),
      excerpt: excerptText(b, 600),
      image: heroImage(b)
    })
  }
  items.sort(function(a, b) { return b.published - a.published })
  return items
}

// A whole news.json payload → flat newest-first list, capped.
function itemsFromPayload(payload, cap) {
  var out = []
  if (!payload || typeof payload !== "object") return out
  var feeds = payload.feeds || []
  for (var i = 0; i < feeds.length; i++) {
    var f = feeds[i]
    if (!f) continue
    var parsed = parse(f.xml, f.name)
    for (var j = 0; j < parsed.length; j++) {
      // Feed-level facts ride on every item (row logo + card footer).
      parsed[j].logo = String(f.logo || "")
      parsed[j].feedUrl = String(f.url || "")
      out.push(parsed[j])
    }
  }
  out.sort(function(a, b) { return b.published - a.published })
  return out.slice(0, cap || 80)
}
