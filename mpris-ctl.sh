#!/usr/bin/env bash
# mpris-ctl.sh pos|seek — live MPRIS Position for the media strip
# (Phase 6b.2). quickshell's cached `position` only moves when a player
# emits change signals — Spotify rarely does (verified live: the bar
# froze after prev/next), so the palette reads Position straight off the
# session bus here.
#   pos <busname>             → stdout position in µs
#   seek <busname> <targetµs> → seek to that absolute position
# Exit: 0 ok · 4 rejected args · 1 bus error / no such player.
#
# Seek uses a relative Seek(offset) from a fresh Get, with the offset behind
# `--`: busctl's getopt eats negative method args ("Seek x -5000000" →
# `unrecognized option '-5'` — the reason backward seeks snapped back; forward
# offsets are positive and always worked). Verified live: Spotify honors
# negative relative Seek both directions. SetPosition(trackid, target) is the
# fallback for players that lack Seek — note Spotify ACCEPTS SetPosition with
# exit 0 yet never applies it, so it must never come first here.
set -u

mode="${1:-}"
dest="$(printf '%s' "${2:-}" | tr -d '\n\r\0')"
obj=/org/mpris/MediaPlayer2
iface=org.mpris.MediaPlayer2.Player

valid_dest() {
  case "$dest" in
    org.mpris.MediaPlayer2.*)
      node="${dest#org.mpris.MediaPlayer2.}"
      case "$node" in
        ""|*[!A-Za-z0-9_.-]*) return 1 ;;
        *) return 0 ;;
      esac ;;
    *) return 1 ;;
  esac
}
valid_dest || { echo "mpris-ctl: bad destination" >&2; exit 4; }

get_pos() {
  busctl --user get-property "$dest" "$obj" "$iface" Position 2>/dev/null \
    | awk '{print $2}'
}

get_trackid() {
  # busctl prints the variant's inner type: Spotify sends mpris:trackid as
  # `s "..."` (string), spec-typical players as `o "..."` — accept both.
  busctl --user get-property "$dest" "$obj" "$iface" Metadata 2>/dev/null \
    | sed -n 's/.*"mpris:trackid" [os] "\([^"]*\)".*/\1/p'
}

case "$mode" in
  pos)
    pos="$(get_pos)"
    # Strict ^-?[0-9]+$ — "5-3" or "-" must not reach arithmetic.
    case "${pos#-}" in ''|*[!0-9]*) exit 1 ;; esac
    printf '%s\n' "$pos"; exit 0 ;;
  seek)
    target="$(printf '%s' "${3:-}" | tr -d '\n\r\0')"
    case "$target" in
      ''|*[!0-9]*) echo "mpris-ctl: bad target" >&2; exit 4 ;;
    esac
    # Primary: relative Seek from a fresh Get — `--` keeps a negative
    # offset out of getopt's reach. One atomic script-side computation,
    # so a stale palette value can't skew the jump.
    pos="$(get_pos)"
    # Strict ^-?[0-9]+$ — "5-3" or "-" must not reach arithmetic.
    case "${pos#-}" in ''|*[!0-9]*) exit 1 ;; esac
    rel=$((target - pos))
    if busctl --user call "$dest" "$obj" "$iface" Seek x -- "$rel" \
      >/dev/null 2>&1; then
      exit 0
    fi
    # Fallback: absolute SetPosition for players without Seek support.
    tid="$(get_trackid)"
    [ -n "$tid" ] || exit 1
    busctl --user call "$dest" "$obj" "$iface" SetPosition ox "$tid" "$target" \
      >/dev/null 2>&1 || exit 1
    exit 0 ;;
  *)
    echo "mpris-ctl: mode must be pos or seek" >&2; exit 4 ;;
esac
