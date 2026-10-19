#!/usr/bin/env bash
# media-memory.test.sh — arg handling, JSON shape, art-copy lifecycle and
# escaping for the last-media snapshot (7.2 ghost tile). Fully offline:
# XDG_STATE_HOME points at a temp dir, jq does the JSON assertions.
# Run: bash tests/media-memory.test.sh
set -u
cd "$(dirname "$0")/.."

passed=0
failed=0

expect_exit() { # name want got
  if [ "$2" = "$3" ]; then passed=$((passed + 1)); else
    failed=$((failed + 1))
    echo "FAIL $1: exit $3, want $2" >&2
  fi
}

expect_eq() { # name got want
  if [ "$2" = "$3" ]; then passed=$((passed + 1)); else
    failed=$((failed + 1))
    echo "FAIL $1: got [$2], want [$3]" >&2
  fi
}

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export XDG_STATE_HOME="$sandbox/state"
# The art-src policy is "$HOME only, never a symlink" (MPRIS metadata is
# app-supplied) — model the real contract by making the sandbox HOME.
export HOME="$sandbox/home"
mkdir -p "$HOME"
mem=./media-memory.sh
json="$XDG_STATE_HOME/omarchy-cmdcenter/last-media.json"

# --- arg guards -----------------------------------------------------------
expect_exit "save no args" 2 "$(bash "$mem" save >/dev/null 2>&1; echo $?)"
expect_exit "save too few" 2 "$(bash "$mem" save a b c >/dev/null 2>&1; echo $?)"
expect_exit "unknown cmd" 2 "$(bash "$mem" frobnicate >/dev/null 2>&1; echo $?)"
expect_exit "load empty state" 3 "$(bash "$mem" load >/dev/null 2>&1; echo $?)"

# --- roundtrip with hostile title ------------------------------------------
# Quotes, a percent sign, and an embedded newline — the JSON killers.
title='He said "stop" — 100%
ok?'
bash "$mem" save "$title" "Some Artist" "spotify" "Spotify" "-" "-" \
  205000000 61500000 >/dev/null 2>&1
expect_exit "save ok" 0 "$?"
loaded=$(bash "$mem" load)
expect_eq "title survives quoting" \
  "$(printf '%s' "$loaded" | jq -r '.title')" "$title"
expect_eq "artist passthrough" \
  "$(printf '%s' "$loaded" | jq -r '.artist')" "Some Artist"
expect_eq "appId passthrough" \
  "$(printf '%s' "$loaded" | jq -r '.appId')" "spotify"
expect_eq "lenUs passthrough" \
  "$(printf '%s' "$loaded" | jq -r '.lenUs')" "205000000"
expect_eq "posUs passthrough" \
  "$(printf '%s' "$loaded" | jq -r '.posUs')" "61500000"
expect_eq "snapshot is valid json" \
  "$(printf '%s' "$loaded" | jq -e . >/dev/null 2>&1; echo $?)" "0"

# --- stdin protocol (8.13: MPRIS metadata never rides argv) --------------
printf 'Stream Title\x00Stream Artist\x00mpv\x00mpv\x00-\x00-\x000\x000\x00' \
  | bash "$mem" save >/dev/null 2>&1
expect_eq "stdin save exit" 0 "$?"
expect_eq "stdin save title" "$(bash "$mem" load | jq -r '.title')" "Stream Title"
expect_eq "stdin save artist" "$(bash "$mem" load | jq -r '.artist')" "Stream Artist"
# EOF with no fields is a usage error, not a phantom snapshot.
printf '' | bash "$mem" save >/dev/null 2>&1
expect_eq "stdin save empty rejected" 2 "$?"

# --- art copy lifecycle ----------------------------------------------------
printf 'PNGFAKE' >"$HOME/art.img"
bash "$mem" save "With Art" "B" "mpv" "mpv" "$HOME/art.img" "-" 10 5 >/dev/null 2>&1
ghost_art="$XDG_STATE_HOME/omarchy-cmdcenter/media/ghost-art.img"
expect_eq "art copied" "$(cat "$ghost_art" 2>/dev/null)" "PNGFAKE"
expect_eq "artFile points at copy" \
  "$(bash "$mem" load | jq -r '.artFile')" "$ghost_art"

# MPRIS-supplied art outside $HOME, or through a symlink, never reaches
# persistent state (any session-bus app controls trackArtUrl).
printf 'EVIL' >"$sandbox/evil.img"
bash "$mem" save "Evil" "B" "mpv" "mpv" "$sandbox/evil.img" "-" 10 5 >/dev/null 2>&1
expect_eq "art outside HOME refused" "$(cat "$ghost_art")" "PNGFAKE"
ln -sf "$HOME/art.img" "$HOME/link.img"
bash "$mem" save "Link" "B" "mpv" "mpv" "$HOME/link.img" "-" 10 5 >/dev/null 2>&1
expect_eq "symlinked art refused" "$(cat "$ghost_art")" "PNGFAKE"

# A "-" keeps the previous copy (art of a new track not fetched yet).
bash "$mem" save "Next Track" "B" "mpv" "mpv" "-" "-" 10 5 >/dev/null 2>&1
expect_eq "previous art kept on -" \
  "$(bash "$mem" load | jq -r '.artFile')" "$ghost_art"
expect_eq "kept art bytes intact" "$(cat "$ghost_art")" "PNGFAKE"

# A missing source file with no previous copy → empty artFile.
rm -f "$ghost_art"
bash "$mem" save "No Art" "" "" "" "$sandbox/gone.img" "-" 0 0 >/dev/null 2>&1
expect_eq "missing source → empty artFile" \
  "$(bash "$mem" load | jq -r '.artFile')" ""

# --- logo + numeric sanitizing ---------------------------------------------
bash "$mem" save "T" "A" "" "" "-" "/usr/share/pixmaps/x.png" \
  "oops" "-12" >/dev/null 2>&1
expect_eq "bad len sanitized" "$(bash "$mem" load | jq -r '.lenUs')" "0"
expect_eq "negative pos sanitized" "$(bash "$mem" load | jq -r '.posUs')" "0"
expect_eq "logo passthrough" \
  "$(bash "$mem" load | jq -r '.logoFile')" "/usr/share/pixmaps/x.png"
bash "$mem" save "T" "A" "" "" "-" "-" 0 0 >/dev/null 2>&1
expect_eq "logo - → empty" "$(bash "$mem" load | jq -r '.logoFile')" ""

# --- 8.14: env delivery keeps hostile strings intact on the palette path --
# Same JSON killers as above, but through the NUL-stdin hop the palette
# actually uses — proves the env-based jq write lost nothing.
printf 'Line1\nLine2 "quo" & <tag>\x00Björk\x00mpv\x00mpv\x00-\x00-\x000\x000\x00' \
  | bash "$mem" save >/dev/null 2>&1
expect_eq "stdin hostile save exit" 0 "$?"
expect_eq "stdin hostile title intact" \
  "$(bash "$mem" load | jq -r '.title')" $'Line1\nLine2 "quo" & <tag>'
expect_eq "stdin hostile artist intact" \
  "$(bash "$mem" load | jq -r '.artist')" "Björk"

# --- hygiene ---------------------------------------------------------------
expect_eq "no tmp leftovers" \
  "$(find "$XDG_STATE_HOME/omarchy-cmdcenter" -name '.last-media.*' | wc -l)" "0"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
