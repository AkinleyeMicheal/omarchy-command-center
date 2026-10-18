#!/bin/bash
# fetch-feeds.sh — fetch the user's RSS/Atom feeds into news.json for the
# Command Center's News group (Phase 6).
#
# Output: $XDG_STATE_HOME/omarchy-cmdcenter/news.json, written atomically
# (the palette's FileView watches it and rebuilds the list on change):
#   { "fetchedAt": <ms>, "errors": <n>,
#     "feeds": [ { "id", "name", "url", "xml": "<raw response>",
#                  "logo": "<abs path to cached favicon | ''>" } ] }
# Raw XML travels embedded (jq -Rs) and is parsed QML-side by the pure
# FeedParser.js — no XML tooling required on the box. Feed favicons and
# article hero images are cached under news-img/ (size/time capped;
# failures are silent — rows fall back to their glyph, cards render
# without a hero).
#
# --max-age N: exit immediately (no network) when news.json is younger
# than N seconds — the startup / group-entry trigger uses this so a
# fresh cache never costs a fetch.
#
# --fetch-images name=url …: download article heroes as positional
# files (item0.img, item1.img, …) named by the QML side; skips files
# already cached. Never touches news.json.
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
feeds_file="$state/feeds.json"
news_file="$state/news.json"
mkdir -p "$state"

# Asset mode (placed before the seed block and the EXIT trap: it needs
# neither feeds.json nor the feed-fetch temps).
if [[ "${1:-}" == "--fetch-images" ]]; then
  mkdir -p "$state/news-img"
  shift
  pids=()
  for pair in "$@"; do
    name="${pair%%=*}"
    url="${pair#*=}"
    [[ -n $name && -n $url && "$name" != "$pair" ]] || continue
    name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')
    dest="$state/news-img/$name.img"
    if [[ -f $dest ]]; then continue; fi
    ( tmp=$(mktemp "$state/news-img/.hero.XXXXXX")
      if curl -fsSL --max-time 8 --max-filesize 4194304 \
          -A "omarchy-cmdcenter/1.0 (RSS reader)" "$url" -o "$tmp" 2>/dev/null \
         && [[ -s $tmp ]]; then mv "$tmp" "$dest"; else rm -f "$tmp"; fi
    ) &
    pids+=($!)
  done
  if ((${#pids[@]})); then wait "${pids[@]}" 2>/dev/null || true; fi
  exit 0
fi

# Seed the starter feeds ONCE (decision: ships with optional starter
# feeds). The file is user-owned afterwards — edit or empty it freely.
if [[ ! -f $feeds_file ]]; then
  cat > "$feeds_file.tmp" <<'JSON'
{
  "feeds": [
    { "id": "hackernews", "name": "Hacker News", "url": "https://news.ycombinator.com/rss" },
    { "id": "lobsters", "name": "Lobsters", "url": "https://lobste.rs/rss" }
  ]
}
JSON
  mv "$feeds_file.tmp" "$feeds_file"
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

# Feed logos, launched in parallel with the feed fetches below: each
# feed's host favicon (square — the right shape for the 20px row icon),
# cached under news-img/ and referenced from news.json's logo field.
# Best effort: a 404 leaves the field empty and the row its glyph.
# NB: the subshells fork while tmps is still empty, so the inherited
# EXIT trap in each can only rm "" — the parent's feed temps stay safe.
mkdir -p "$state/news-img"
logo_pids=()
for ((i = 0; i < n; i++)); do
  fid=$(jq -r ".feeds[$i].id // \"feed$i\"" "$feeds_file")
  furl=$(jq -r ".feeds[$i].url // \"\"" "$feeds_file")
  host=$(printf '%s' "$furl" | sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/]+).*#\1#p')
  [[ -n $host ]] || continue
  fid=$(printf '%s' "$fid" | tr -c 'A-Za-z0-9._-' '-')
  dest="$state/news-img/feed-${fid}.img"
  if [[ -f $dest ]]; then continue; fi
  ( tmp=$(mktemp "$state/news-img/.logo.XXXXXX")
    if curl -fsSL --max-time 6 --max-filesize 524288 \
        -A "omarchy-cmdcenter/1.0 (RSS reader)" "https://$host/favicon.ico" -o "$tmp" 2>/dev/null \
       && [[ -s $tmp ]]; then mv "$tmp" "$dest"; else rm -f "$tmp"; fi
  ) &
  logo_pids+=($!)
done

errors=0
for ((i = 0; i < n; i++)); do
  url=$(jq -r ".feeds[$i].url" "$feeds_file")
  [[ -n $url && $url != null ]] || continue
  f=$(mktemp); tmps+=("$f")
  if curl -fsSL --max-time 10 --retry 1 \
      -A "omarchy-cmdcenter/1.0 (RSS reader)" "$url" -o "$f" 2>/dev/null; then
    got[$i]=$f
  else
    errors=$((errors + 1))
  fi
done

if ((${#logo_pids[@]})); then wait "${logo_pids[@]}" 2>/dev/null || true; fi

entries="[]"
for ((i = 0; i < n; i++)); do
  id=$(jq -r ".feeds[$i].id // \"feed$i\"" "$feeds_file")
  name=$(jq -r ".feeds[$i].name // .feeds[$i].url" "$feeds_file")
  url=$(jq -r ".feeds[$i].url // \"\"" "$feeds_file")
  if [[ -n ${got[$i]:-} ]]; then xml=$(jq -Rs . < "${got[$i]}")
  else xml='""'; fi
  fid=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '-')
  logo_path="$state/news-img/feed-${fid}.img"
  if [[ -f $logo_path ]]; then logo=$(printf '%s' "$logo_path" | jq -Rs .)
  else logo='""'; fi
  entries=$(jq -c --arg id "$id" --arg name "$name" --arg url "$url" \
    --argjson xml "$xml" --argjson logo "$logo" \
    '. + [{id: $id, name: $name, url: $url, xml: $xml, logo: $logo}]' <<<"$entries")
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
