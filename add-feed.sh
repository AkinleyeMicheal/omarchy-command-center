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
# Delivery: stdin preferred (the palette writes the URL there), argv for
# direct CLI/test use; jq receives every value via the environment —
# never argv, which is world-readable in /proc/<pid>/cmdline.
# Prints the added feed's name on stdout.
# Exit: 0 ok · 2 bad usage · 3 already added · 4 fetch/discovery failed.
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
feeds_file="$state/feeds.json"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# URL delivery: argv, or stdin (the palette writes it there so the
# pasted URL — possibly a signed/tokenized link — never sits in
# world-readable /proc cmdline during the multi-second probe).
url="${1:-}"
if [[ -z $url && ! -t 0 ]]; then IFS= read -r url || true; fi
if [[ -z $url ]]; then
  echo "usage: add-feed.sh <url>   (argv, or one line on stdin)" >&2
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
chmod 700 "$state" 2>/dev/null || true     # state dir holds private data
if [[ ! -f $feeds_file ]]; then             # seed stays owner-only (0600)
  old_umask=$(umask); umask 077
  printf '{"feeds":[]}' > "$feeds_file"
  umask "$old_umask"
fi

tmps=()
cleanup() { rm -f "${tmps[@]:-}"; }
trap cleanup EXIT

UA="omarchy-cmdcenter/1.0 (RSS reader)"
probe=$(mktemp); tmps+=("$probe")

# Probe the pasted URL: user-seed mode (any host the user chose; a
# redirect beyond it must be public or return to the pasted host).
netguard_fetch_user "$url" "$probe" 8388608 "$UA" \
  || { echo "could not fetch $url" >&2; exit 4; }

feed_url="$url"
feed_mode=user
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
      # (fetch-guard.sh: the strict mode, redirects included).
      netguard_check_url "$feed_url" \
        || { echo "declared feed host not allowed (${NETGUARD_REASON})" >&2; exit 4; }
      feed_mode=public
      ;;
    /*)
      feed_url="$(printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+).*#\1#')$href"
      ;;
    *)
      # Path-relative declared href: resolve against the pasted URL's
      # DIRECTORY — the origin always comes from the user's own URL, and
      # a URL without a path resolves under "/". Content must never
      # influence the authority (the 8.13 review point: a bare
      # `https://host` base plus href="169.254.169.254/x" previously
      # built a link-local URL, and the sed that was meant to prevent it
      # was unterminated — silently aborting the whole add under
      # pipefail).
      base_origin=$(printf '%s' "$url" \
        | sed -nE 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]+).*$#\1#p')
      base_dir=$(printf '%s' "$url" \
        | sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]+([^?#]*).*$#\1#p')
      base_dir="${base_dir%/*}"
      feed_url="$base_origin$base_dir/$href"
      ;;
  esac
  # A relative declared href stays on the host the USER chose → seed
  # mode; an absolute declared one is content → strict mode.
  if [[ $feed_mode == public ]]; then
    netguard_fetch "$feed_url" "$probe" 8388608 "$UA" \
      || { echo "declared feed $feed_url not fetchable" >&2; exit 4; }
  else
    netguard_fetch_user "$feed_url" "$probe" 8388608 "$UA" \
      || { echo "declared feed $feed_url not fetchable" >&2; exit 4; }
  fi
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
# jq gets every value through the environment (owner-only
# /proc/<pid>/environ), never as jq argv flags: the URL can carry an
# access token and the name comes from remote content — neither may sit
# in world-readable argv (8.14 review).
id=$(printf '%s' "$feed_url" | sed -E 's#^https?://([^/]+).*#\1#' \
  | sed -E 's/^www\.//; s/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')
[[ -n $id ]] || id="feed"
if FEED_URL="$feed_url" jq -e '.feeds | any(.url == $ENV.FEED_URL)' \
    "$feeds_file" >/dev/null 2>&1; then
  echo "already added: $name" >&2
  exit 3
fi
base="$id"; n=2
while FEED_ID="$id" jq -e '.feeds | any(.id == $ENV.FEED_ID)' \
    "$feeds_file" >/dev/null 2>&1; do
  id="$base$((n))"; n=$((n + 1))
done

out=$(mktemp "$state/.feeds.XXXXXX"); tmps+=("$out")
FEED_ID="$id" FEED_NAME="$name" FEED_URL="$feed_url" \
  jq '.feeds += [{id: $ENV.FEED_ID, name: $ENV.FEED_NAME, url: $ENV.FEED_URL}]' \
  "$feeds_file" > "$out"
mv "$out" "$feeds_file"

# Refresh everything (existing feeds too — cheap, keeps news coherent).
bash "$here/fetch-feeds.sh" >/dev/null 2>&1 || true

echo "$name"
