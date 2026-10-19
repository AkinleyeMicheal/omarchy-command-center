#!/usr/bin/env bash
# dict-lookup.sh <word> — dictionary provider (Phase 7): definitions from
# the free dictionaryapi.dev (no key, no account).
#   stdout: up to three definitions joined by " · " (one line)
# Exit: 0 definition found · 2 no entry · 4 rejected args · 1 network/parse.
#
# The word is validated to letters/apostrophe/space/hyphen before it touches
# the URL, so the request path is built from a proven-safe string only.
set -u

# Delivery: argv, or one line on stdin (the palette writes it there so
# the word — potentially pasted text — never sits in /proc cmdline).
if [ -n "${1:-}" ]; then word="$1"; else IFS= read -r word || true; fi
word="$(printf '%s' "$word" | tr -d '\n\r' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
case "$word" in
  "") echo "dict-lookup: empty word" >&2; exit 4 ;;
esac
# Strip the specials a word may carry (' - and spaces), then the remainder
# must be pure letters. (A literal apostrophe inside a case bracket pattern
# wrecks the shell's own quoting — this avoids that trap entirely.)
core="$(printf '%s' "$word" | tr -d "' -")"
case "$core" in
  *[!A-Za-z]*) echo "dict-lookup: letters only" >&2; exit 4 ;;
esac
[ "${#word}" -le 64 ] || { echo "dict-lookup: word too long" >&2; exit 4; }

enc="${word// /%20}"
# The URL carries the query word, so it rides a one-line config on
# stdin — curl's argv is world-readable (/proc/<pid>/cmdline) and the
# word is potentially pasted text (8.14 review; the word already rides
# stdin into this script). The charset validation above (letters,
# apostrophe, hyphen, %20) guarantees no quote/backslash can break out
# of the quoted config value.
url="https://api.dictionaryapi.dev/api/v2/entries/en/$enc"

json="$(printf 'url = "%s"\n' "$url" \
  | curl -sf --max-time 8 --max-filesize 2097152 --proto '=https' -K -)"
rc=$?
if [ "$rc" -eq 22 ]; then exit 2 ; fi   # HTTP error → no entry
[ "$rc" -eq 0 ] || exit 1               # DNS/timeout/…

def="$(printf '%s' "$json" \
  | jq -r '[.[0].meanings[]?.definitions[]?.definition][0:3] | join(" · ")' \
      2>/dev/null)" || def=""
# Empty or unparseable body ("don't" answers 200 with []) reads as "no
# entry" — only transport failures above (rc≠0, ≠22) are exit 1.
case "$def" in
  ""|"null") exit 2 ;;
esac
printf '%s\n' "$def"
