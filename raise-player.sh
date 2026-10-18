#!/usr/bin/env bash
# raise-player.sh <mpris-desktopEntry|identity> — bring a media player's
# window forward (Phase 6b.2). MPRIS Raise() proved unreliable here
# (Spotify ignores it under Wayland — verified live) and raw
# `hyprctl dispatch focuswindow` is broken upstream: Hyprland 0.56.2 +
# Lua configs evaluate dispatch args as Lua (known issue #16224), and
# focuswindow isn't exposed in the Lua dispatcher tree at all. So this
# leans on omarchy's own helper: `omarchy hyprland focus app <name>`.
# Candidates tried in order: id without .desktop, the .desktop's
# StartupWMClass, the raw id, lowercased — first success wins.
# Player-agnostic: works for anything with a window.
# Exit: 0 a window was focused · 4 rejected arg · 1 nothing matched.
set -u

arg="$(printf '%s' "${1:-}" | tr -d '\n\r\0' | cut -c1-64)"
[ -n "$arg" ] || { echo "raise-player: empty id" >&2; exit 4; }

cands=()
case "$arg" in
  *.desktop) cands+=("${arg%.desktop}") ;;
esac

dirs=(/usr/share/applications /usr/local/share/applications \
  "$HOME/.local/share/applications" \
  /var/lib/flatpak/exports/share/applications \
  "$HOME/.local/share/flatpak/exports/share/applications")
shopt -s nullglob
for d in "${dirs[@]}"; do
  for f in "$d"/*.desktop; do
    [ -f "$f" ] || continue
    if [ "$arg" = "$(basename "$f")" ] || grep -qiFx "Name=$arg" "$f" 2>/dev/null; then
      wm="$(sed -n 's/^StartupWMClass=//p' "$f" | head -1)"
      [ -n "$wm" ] && cands+=("$wm")
      break
    fi
  done
done
shopt -u nullglob
cands+=("$arg")
low="$(printf '%s' "$arg" | tr 'A-Z' 'a-z')"
[ "$low" != "$arg" ] && cands+=("$low")

tried=" "
for c in "${cands[@]}"; do
  case "$tried" in *" $c "*) continue ;; esac
  tried="$tried$c "
  if omarchy hyprland focus app "$c" >/dev/null 2>&1; then exit 0; fi
done
exit 1
