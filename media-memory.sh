#!/usr/bin/env bash
# media-memory.sh — persist the last-played track for the home strip's
# Windows-style ghost tile (7.2): when the player closes, the tile keeps
# the cover art, title/artist, and frozen counter instead of going blank.
#
#   media-memory.sh save TITLE ARTIST APP_ID IDENTITY ART_SRC LOGO LEN_US POS_US
#   media-memory.sh load
#
# save copies the already-fetched cover art (ART_SRC: a plain path — the
# palette strips file:// and ?v= before calling) into
# state/media/ghost-art.img so the tile survives reboots and offline, then
# writes last-media.json atomically (tmp + mv). ART_SRC "-" keeps the
# previous copy (a track change before its art lands); LOGO "-" means none.
# APP_ID is the catalog desktop id used to relaunch the player on click.
#
# Every runtime value is a single argv element — jq does all JSON
# encoding, so quotes/newlines/control bytes in titles can never break
# the file or the command line (no eval, no string-built JSON).
#
# Exit codes: save 0 ok · 2 usage · 1 write failure. load 0 · 3 no snapshot.
set -u

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
json="$state_dir/last-media.json"

cmd="${1:-}"

case "$cmd" in
  save)
    if [ "$#" -eq 1 ]; then
      # stdin mode (the palette): eight NUL-separated fields, EOF after
      # the last. D-Bus strings can never contain NUL, so the framing is
      # lossless — and titles/artists/identity never touch world-readable
      # argv (8.13 review: MPRIS metadata is app-supplied AND private
      # listening history).
      fields=()
      for _ in 1 2 3 4 5 6 7 8; do
        IFS= read -r -d '' f || f=""
        fields+=("$f")
      done
      title="${fields[0]}"
      artist="${fields[1]}"
      app_id="${fields[2]}"
      identity="${fields[3]}"
      art_src="${fields[4]}"
      logo="${fields[5]}"
      len_us="${fields[6]}"
      pos_us="${fields[7]}"
    elif [ "$#" -eq 9 ]; then
      title="$2"
      artist="$3"
      app_id="$4"
      identity="$5"
      art_src="$6"
      logo="$7"
      len_us="${8:-0}"
      pos_us="${9:-0}"
    else
      exit 2
    fi
    # A save without a title is a usage error in both modes (an EOF'd
    # stdin must not produce a phantom empty snapshot).
    [ -n "$title" ] || exit 2
    # Only plain non-negative integers may reach --argjson.
    case $len_us in '' | *[!0-9]*) len_us=0 ;; esac
    case $pos_us in '' | *[!0-9]*) pos_us=0 ;; esac

    mkdir -p "$state_dir/media" || exit 1
    chmod 700 "$state_dir" "$state_dir/media" 2>/dev/null || true

    # ART_SRC is MPRIS-supplied — any session-bus app controls it. Only
    # a plain existing file INSIDE $HOME, never a symlink, may be copied
    # into persistent state: no /etc, /proc, ~/.ssh probing by pointing
    # trackArtUrl at it (8.13 review).
    case "$art_src" in
      "$HOME"/*) [ -f "$art_src" ] && [ ! -L "$art_src" ] || art_src="-" ;;
      *) art_src="-" ;;
    esac

    ghost_art="$state_dir/media/ghost-art.img"
    art_file=""
    if [ "$art_src" != "-" ] && [ -f "$art_src" ]; then
      cp -f "$art_src" "$ghost_art" || exit 1
      art_file="$ghost_art"
    elif [ -f "$ghost_art" ]; then
      art_file="$ghost_art" # keep the previous copy
    fi
    [ "$logo" = "-" ] && logo=""

    tmp=$(mktemp "$state_dir/.last-media.XXXXXX") || exit 1
    trap 'rm -f "$tmp"' EXIT
    jq -n \
      --arg t "$title" \
      --arg ar "$artist" \
      --arg id "$app_id" \
      --arg ide "$identity" \
      --arg art "$art_file" \
      --arg logo "$logo" \
      --argjson len "$len_us" \
      --argjson pos "$pos_us" \
      '{title: $t, artist: $ar, appId: $id, identity: $ide,
        artFile: $art, logoFile: $logo, lenUs: $len, posUs: $pos,
        at: (now * 1000)}' >"$tmp" || exit 1
    mv -f "$tmp" "$json" || exit 1
    trap - EXIT
    ;;
  load)
    [ -f "$json" ] || exit 3
    cat "$json"
    ;;
  *)
    exit 2
    ;;
esac
