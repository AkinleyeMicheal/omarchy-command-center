#!/bin/bash
# add-feed.sh <url> — add a feed to feeds.json and refresh news.json.
#
# Accepts either a feed URL (RSS/Atom/XML) or a PAGE URL that declares
# one (<link rel="alternate" type="application/rss+xml|atom+xml"
# href="…"> — which is what issue pages like
# https://aiweekly.co/ai-news-today actually are): the declared feed is
# discovered, never guessed. The result must sniff as XML, its <title>
# becomes the display name, and the entry is appended to the user-owned
# feeds.json (deduped by URL, id suffixed on host collision) before the
# normal fetch runs — the palette picks news.json up via its file watch.
#
# argv-only: the URL travels as an argument, never in a shell string.
# Prints the added feed's name on stdout.
# Exit: 0 ok · 2 bad usage · 3 already added · 4 fetch/discovery failed.
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
feeds_file="$state/feeds.json"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

url="${1:-}"
if [[ -z $url ]]; then
  echo "usage: add-feed.sh <url>" >&2
  exit 2
fi
# Tolerate a copy-pasted URL with stray trailing whitespace.
url="${url%"${url##*[![:space:]]}"}"
# A feed URL is a web URL: file://, dict:// and friends have no place
# here (the probe would otherwise happily read a local file as a "feed").
case "$url" in
  http://* | https://*) ;;
  *) echo "not an http(s) url" >&2; exit 4 ;;
esac
# URLs the USER pasted are their own intent (LAN/homelab feeds included);
# links a pasted PAGE declares are content — those get the full
# destination guard below, like every other feed-supplied URL.
# shellcheck source=fetch-guard.sh
. "$here/fetch-guard.sh"
mkdir -p "$state"
[[ -f $feeds_file ]] || printf '{"feeds":[]}' > "$feeds_file"

tmps=()
cleanup() { rm -f "${tmps[@]:-}"; }
trap cleanup EXIT

UA="omarchy-cmdcenter/1.0 (RSS reader)"
probe=$(mktemp); tmps+=("$probe")

curl -fsSL --max-time 15 --max-filesize 8388608 \
  --proto '=http,https' --proto-redir '=http,https' \
  -A "$UA" "$url" -o "$probe" 2>/dev/null \
  || { echo "could not fetch $url" >&2; exit 4; }

feed_url="$url"
if ! head -c 512 "$probe" | grep -qiE '<\?xml|<rss|<feed[ >]'; then
  # HTML page: take the feed IT declares (rel=alternate + rss/atom/xml).
  href=$(grep -oiE '<link[^>]*rel="alternate"[^>]*>' "$probe" \
    | grep -iE 'rss|atom|xml' \
    | grep -oiE 'href="[^"]+"' | head -1 | cut -d'"' -f2 || true)
  [[ -n $href ]] || { echo "no feed declared by $url" >&2; exit 4; }
  case "$href" in
    http://*|https://*)
      feed_url="$href"
      # Content-declared absolute URL → public destinations only
      # (fetch-guard.sh: the same policy every item image obeys).
      netguard_check_url "$feed_url" \
        || { echo "declared feed host not allowed (${NETGUARD_REASON})" >&2; exit 4; }
      ;;
    /*)
      feed_url="$(printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+).*#\1#')$href"
      ;;
    *)
      feed_url="$(printf '%s' "$url" | sed -E 's#^(.*/)[^/]*$#\1/')$href"
      ;;
  esac
  curl -fsSL --max-time 15 --max-filesize 8388608 \
    --proto '=http,https' --proto-redir '=http,https' \
    -A "$UA" "$feed_url" -o "$probe" 2>/dev/null \
    || { echo "declared feed $feed_url not fetchable" >&2; exit 4; }
fi

head -c 512 "$probe" | grep -qiE '<\?xml|<rss|<feed[ >]' \
  || { echo "$feed_url is not an RSS/Atom feed" >&2; exit 4; }

# Display name from the channel/feed <title> (CDATA tolerated), falling
# back to the feed's host.
name=$(grep -oiE '<title[^>]*>[^<]*</title>' "$probe" | head -1 \
  | sed -E 's#</?title[^>]*>##gi; s#<!\[CDATA\[##g; s#\]\]>##g' \
  | sed -E 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' || true)
if [[ -z $name ]]; then
  name=$(printf '%s' "$feed_url" | sed -E 's#^https?://([^/]+).*#\1#')
fi

# Identity: slug of the feed's host; same URL → already added (3);
# same id from a different URL → id2, id3, …
id=$(printf '%s' "$feed_url" | sed -E 's#^https?://([^/]+).*#\1#' \
  | sed -E 's/^www\.//; s/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')
[[ -n $id ]] || id="feed"
if jq -e --arg url "$feed_url" '.feeds | any(.url == $url)' \
    "$feeds_file" >/dev/null 2>&1; then
  echo "already added: $name" >&2
  exit 3
fi
base="$id"; n=2
while jq -e --arg id "$id" '.feeds | any(.id == $id)' \
    "$feeds_file" >/dev/null 2>&1; do
  id="$base$((n))"; n=$((n + 1))
done

out=$(mktemp "$state/.feeds.XXXXXX"); tmps+=("$out")
jq --arg id "$id" --arg name "$name" --arg url "$feed_url" \
  '.feeds += [{id: $id, name: $name, url: $url}]' \
  "$feeds_file" > "$out"
mv "$out" "$feeds_file"

# Refresh everything (existing feeds too — cheap, keeps news coherent).
bash "$here/fetch-feeds.sh" >/dev/null 2>&1 || true

echo "$name"
