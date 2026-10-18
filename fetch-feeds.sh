#!/bin/bash
# fetch-feeds.sh — fetch the user's RSS/Atom feeds into news.json for the
# Command Center's News group (Phase 6).
#
# Output: $XDG_STATE_HOME/omarchy-cmdcenter/news.json, written atomically
# (the palette's FileView watches it and rebuilds the list on change):
#   { "fetchedAt": <ms>, "errors": <n>,
#     "feeds": [ { "id", "name", "url", "xml": "<raw response>" } ] }
# Raw XML travels embedded (jq -Rs) and is parsed QML-side by the pure
# FeedParser.js — no XML tooling required on the box.
#
# SECURITY (8.11): the News group downloads NO feed-supplied images —
# no item heroes, no favicons. Feed rows/cards render the feed's
# initials instead (FeedParser.js). The only network activity left in
# the news pipeline is the feed XML itself, whose URL the USER entered:
# fetched via fetch-guard.sh's user-seed mode (any host the user chose,
# including LAN feeds; a feed server's redirect hops must be public or
# return to the pasted host).
#
# --max-age N: exit immediately (no network) when news.json is younger
# than N seconds — the startup / group-entry trigger uses this so a
# fresh cache never costs a fetch.
set -euo pipefail

# Destination policy + validated fetch for the user's feed URLs (and
# their redirect hops). See fetch-guard.sh's header for the boundary.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fetch-guard.sh
. "$here/fetch-guard.sh"

state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
feeds_file="$state/feeds.json"
news_file="$state/news.json"
mkdir -p "$state"
chmod 700 "$state" 2>/dev/null || true   # holds feed URLs, news, history

# Seed the starter feeds ONCE (decision: ships with optional starter
# feeds). The file is user-owned afterwards — edit or empty it freely.
if [[ ! -f $feeds_file ]]; then
  old_umask=$(umask); umask 077   # the seed stays owner-only (0600)
  cat > "$feeds_file.tmp" <<'JSON'
{
  "feeds": [
    { "id": "hackernews", "name": "Hacker News", "url": "https://news.ycombinator.com/rss" },
    { "id": "lobsters", "name": "Lobsters", "url": "https://lobste.rs/rss" }
  ]
}
JSON
  mv "$feeds_file.tmp" "$feeds_file"
  umask "$old_umask"
fi

if [[ "${1:-}" == "--max-age" ]]; then
  max_age="${2:-0}"
  if [[ -f $news_file ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$news_file") ))
    (( age < max_age )) && exit 0
  fi
fi

n=$(jq '.feeds | length' "$feeds_file" 2>/dev/null || echo 0)
declare -A got
tmps=()
cleanup() { rm -f "${tmps[@]:-}"; }
trap cleanup EXIT

errors=0
for ((i = 0; i < n; i++)); do
  url=$(jq -r ".feeds[$i].url" "$feeds_file")
  [[ -n $url && $url != null ]] || continue
  f=$(mktemp); tmps+=("$f")
  # User-seed mode: the pasted URL is honored wherever it points; the
  # redirect hops beyond it are server-chosen and must be public (or
  # back on the user's own host).
  if netguard_fetch_user "$url" "$f" 8388608; then
    got[$i]=$f
  else
    errors=$((errors + 1))
  fi
done

entries="[]"
for ((i = 0; i < n; i++)); do
  id=$(jq -r ".feeds[$i].id // \"feed$i\"" "$feeds_file")
  name=$(jq -r ".feeds[$i].name // .feeds[$i].url" "$feeds_file")
  url=$(jq -r ".feeds[$i].url // \"\"" "$feeds_file")
  if [[ -n ${got[$i]:-} ]]; then xml=$(jq -Rs . < "${got[$i]}")
  else xml='""'; fi
  entries=$(jq -c --arg id "$id" --arg name "$name" --arg url "$url" \
    --argjson xml "$xml" \
    '. + [{id: $id, name: $name, url: $url, xml: $xml}]' <<<"$entries")
done

# Assemble on a per-run temp name (concurrent runs — startup timer +
# group-entry nudge — must never interleave writes into one file), then
# publish atomically.
out=$(mktemp); tmps+=("$out")
jq -n --argjson feeds "$entries" --argjson errors "$errors" \
  --arg now "$(date +%s)000" \
  '{fetchedAt: ($now | tonumber), errors: $errors, feeds: $feeds}' \
  > "$out"
mv "$out" "$news_file"
