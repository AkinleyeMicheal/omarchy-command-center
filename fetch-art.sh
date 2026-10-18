#!/usr/bin/env bash
# fetch-art.sh <mpris:artUrl> — album-art download for the now-playing
# tile (Phase 6b.1). The QML Image never fetches http(s) itself, so the
# palette shells out here and displays state/media/art.img (atomic
# rename; cached by source URL in media/art.url — same URL → no-op).
# One argv URL, never interpolated: whatever comes in is data.
# Exit: 0 downloaded · 3 already cached · 4 rejected arg · 1 failed.
set -u

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"

url="$(printf '%s' "${1:-}" | tr -d '\n\r\0' | cut -c1-2048)"
case "$url" in
  http://*|https://*) ;;
  *) echo "fetch-art: not an http(s) url" >&2; exit 4 ;;
esac

if [ -f "$STATE/media/art.url" ] && [ -f "$STATE/media/art.img" ] \
   && [ "$(cat "$STATE/media/art.url" 2>/dev/null)" = "$url" ]; then
  exit 3
fi

mkdir -p "$STATE/media"
tmp="$(mktemp "$STATE/media/.art-XXXXXX")"
if ! curl -fsSL --max-time 12 --max-filesize 4194304 \
    -A "Mozilla/5.0 (X11; Linux x86_64) quickshell-art-fetch" \
    -o "$tmp" "$url"; then
  rm -f "$tmp"
  echo "fetch-art: download failed" >&2
  exit 1
fi
[ -s "$tmp" ] || { rm -f "$tmp"; echo "fetch-art: empty download" >&2; exit 1; }

mime="$(file -b --mime-type "$tmp" 2>/dev/null || echo unknown)"
case "$mime" in
  image/*) ;;
  *) rm -f "$tmp"; echo "fetch-art: not an image ($mime)" >&2; exit 1 ;;
esac

mv -f "$tmp" "$STATE/media/art.img"
printf '%s\n' "$url" > "$STATE/media/art.url"   # cache marker last
exit 0
