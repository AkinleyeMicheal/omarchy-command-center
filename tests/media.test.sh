#!/bin/bash
# Tests for fetch-art.sh and player-icon.sh (Phase 6b.1) against a
# throwaway XDG_STATE_HOME — the live state dir is never touched and no
# network is required (only rejected-arg paths run, which exit before
# curl). Also byte-verifies the MEDIA_GLYPHS codepoints in Controls.js.
# Run: bash tests/media.test.sh
set -u
cd "$(dirname "$0")/.."
export XDG_STATE_HOME
XDG_STATE_HOME=$(mktemp -d)
art="$PWD/fetch-art.sh"
icon="$PWD/player-icon.sh"
pass=0
fail=0

check() { # name expected actual
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $1: expected [$2] got [$3]"
  fi
}

# ---- fetch-art: argument validation (exit before any network)
bash "$art" >/dev/null 2>&1
check "art: missing arg → 4" "4" "$?"
bash "$art" "file:///etc/passwd" >/dev/null 2>&1
check "art: file:// arg → 4" "4" "$?"
bash "$art" "ftp://host/art.png" >/dev/null 2>&1
check "art: ftp arg → 4" "4" "$?"
bash "$art" "$XDG_STATE_HOME/mark" >/dev/null 2>&1
check "art: bare path arg → 4" "4" "$?"

# ---- player-icon: arg validation + real resolution (offline)
bash "$icon" >/dev/null 2>&1
check "icon: empty arg → 4" "4" "$?"
out="$(bash "$icon" spotify.desktop 2>/dev/null)"
check "icon: spotify.desktop resolves → 0" "0" "$?"
check "icon: resolved file exists" "yes" "$([[ -f "$out" ]] && echo yes)"
out2="$(bash "$icon" spotify 2>/dev/null)"
check "icon: identity 'spotify' resolves → 0" "0" "$?"
check "icon: both paths agree" "$out" "$out2"
check "icon: cache hit returns same path" "$out" "$(bash "$icon" spotify.desktop 2>/dev/null)"
bash "$icon" definitely-not-a-player >/dev/null 2>&1
check "icon: unknown player → 1" "1" "$?"

# ---- mpris-ctl: argument validation (bus calls only for plausible args)
ctl="$PWD/mpris-ctl.sh"
bash "$ctl" >/dev/null 2>&1
check "ctl: missing mode → 4" "4" "$?"
bash "$ctl" pos "spotify" >/dev/null 2>&1
check "ctl: bare name dest → 4" "4" "$?"
bash "$ctl" seek "org.mpris.MediaPlayer2.spotify" "abc" >/dev/null 2>&1
check "ctl: non-numeric target → 4" "4" "$?"
bash "$ctl" frobnicate "org.mpris.MediaPlayer2.x" >/dev/null 2>&1
check "ctl: bad mode → 4" "4" "$?"
bash "$ctl" pos "org.mpris.MediaPlayer2.no-such-player-xyz" >/dev/null 2>&1
check "ctl: absent player → 1" "1" "$?"

# ---- raise-player: arg validation + no-match path (safe: the omarchy
# helper simply finds nothing for a bogus name, focus is untouched)
bash "$PWD/raise-player.sh" >/dev/null 2>&1
check "raise: empty id → 4" "4" "$?"
bash "$PWD/raise-player.sh" definitely-not-a-player-xyz >/dev/null 2>&1
check "raise: unknown player → 1" "1" "$?"

# ---- MEDIA_GLYPHS: raw UTF-8 verified by codepoint, never by eye.
# fa-backward / fa-forward (BMP) and md-play / md-pause / md-music
# (astral plane) — all must exist in the Nerd Font planes we render.
python3 - <<'EOF'
import re, sys
src = open("Controls.js", encoding="utf-8").read()
want = {"prev": 0xF04A, "play": 0xF040A, "pause": 0xF03E4,
        "next": 0xF04E, "music": 0xF075A}
m = re.search(r"MEDIA_GLYPHS\s*=\s*\{([^}]*)\}", src)
if not m:
    print("glyphs: MEDIA_GLYPHS block not found")
    sys.exit(1)
found = dict(re.findall(r'(\w+):\s*"([^"]*)"', m.group(1)))
bad = [k for k, cp in want.items()
       if k not in found or len(found[k]) != 1 or ord(found[k]) != cp]
if bad:
    print("glyphs: missing/wrong codepoints:", bad)
    sys.exit(1)
print("glyphs: all five codepoints verified")
EOF
check "glyphs: MEDIA_GLYPHS codepoints" "0" "$?"

rm -rf "$XDG_STATE_HOME"
echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
