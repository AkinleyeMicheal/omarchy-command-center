#!/usr/bin/env bash
# player-icon.sh <mpris-desktopEntry|identity> — resolve a media player's
# logo for the now-playing tile (Phase 6b.1). An explicit *.desktop id
# wins; otherwise the .desktop files' Name= is matched case-insensitively
# (MPRIS identities are usually lowercase, desktop Names capitalized).
# The Icon= key then resolves largest-PNG-first through the hicolor
# theme, then scalable SVG, then pixmaps — same order the desktop uses.
# Resolved path cached in state/media/logo-<slug>.path (icon files
# rarely move; a vanished file just degrades to the glyph frame).
# Exit: 0 path on stdout · 4 rejected arg · 1 not found.
set -u

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"

arg="$(printf '%s' "${1:-}" | tr -d '\n\r\0' | cut -c1-64)"
[ -n "$arg" ] || { echo "player-icon: empty identity" >&2; exit 4; }
# The id joins path strings below — a slash would walk out of the
# .desktop dirs (MPRIS identities and desktop ids never carry one).
case "$arg" in
  */*) echo "player-icon: bad identity" >&2; exit 4 ;;
esac

slug="$(printf '%s' "$arg" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' \
  | sed 's/^-//; s/-$//' | cut -c1-40)"
cache="$STATE/media/logo-$slug.path"
if [ -f "$cache" ]; then cat "$cache"; exit 0; fi

dirs=(/usr/share/applications /usr/local/share/applications \
  "$HOME/.local/share/applications" \
  /var/lib/flatpak/exports/share/applications \
  "$HOME/.local/share/flatpak/exports/share/applications")

match=""
case "$arg" in
  *.desktop)
    for d in "${dirs[@]}"; do
      [ -f "$d/$arg" ] && { match="$d/$arg"; break; }
    done ;;
esac
if [ -z "$match" ]; then
  shopt -s nullglob
  for d in "${dirs[@]}"; do
    for f in "$d"/*.desktop; do
      [ -f "$f" ] || continue
      grep -qiFx "Name=$arg" "$f" 2>/dev/null && { match="$f"; break 2; }
    done
  done
  shopt -u nullglob
fi
[ -n "$match" ] || exit 1

icon="$(sed -n 's/^Icon=//p' "$match" | head -1)"
[ -n "$icon" ] || exit 1

best=""
shopt -s nullglob
for base in "$HOME/.local/share/icons" /usr/share/icons /usr/local/share/icons; do
  for size in 512x512 256x256 128x128 96x96 64x64 48x48 32x32 24x24 22x22; do
    for ext in png svg; do
      f="$base/hicolor/$size/apps/$icon.$ext"
      [ -f "$f" ] && { best="$f"; break 3; }
    done
  done
done
if [ -z "$best" ]; then
  for f in /usr/share/pixmaps/"$icon".* "$HOME/.local/share/icons/$icon".*; do
    [ -f "$f" ] && { best="$f"; break; }
  done
fi
shopt -u nullglob
[ -n "$best" ] || exit 1

mkdir -p "$STATE/media"
tmp="$(mktemp "$STATE/media/.logo-XXXXXX")"
printf '%s\n' "$best" > "$tmp" && mv -f "$tmp" "$cache"
printf '%s\n' "$best"
exit 0
