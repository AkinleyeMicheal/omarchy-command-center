#!/usr/bin/env bash
# file-search.sh <query> — file provider (Phase 7): home-wide file-name
# search via fd, case-insensitive substring on the basename.
#   stdout: matching paths, one per line, capped at 40
# Exit: 0 ok (may match nothing) · 4 rejected args · 1 fd/cd failure.
#
# The query never reaches a shell or a regex/glob parser — it is compared
# with awk's index() as a literal, so ".", "*", "[", spaces are all safe.
# No fd-side result cap either: with a match-everything pattern a cap would
# truncate to a RANDOM subset of the home (parallel walk — verified: result
# counts varied 0/1/2 run to run), and the basename filter runs after. The
# full walk is cheap; awk's early exit at 40 matches SIGPIPEs fd.
set -u

# Delivery: argv, or one line on stdin — the palette writes the query
# there so it (potentially pasted text) never sits in world-readable
# /proc cmdline during the seconds-long home walk.
if [ -n "${1:-}" ]; then q="$1"; else IFS= read -r q || true; fi
q="$(printf '%s' "$q" | tr -d '\n\r\0')"
[ -n "$q" ] || { echo "file-search: empty query" >&2; exit 4; }
[ "${#q}" -le 128 ] || { echo "file-search: query too long" >&2; exit 4; }

cd "$HOME" || exit 1

fd --hidden --type f --absolute-path \
   --exclude '.git' \
   --exclude 'node_modules' \
   --exclude '.cache' \
   --exclude 'Trash' \
   --exclude '.npm' \
   --exclude 'target' \
   --exclude '.steam' \
   . 2>/dev/null \
  | Q="$(printf '%s' "$q" | tr '[:upper:]' '[:lower:]')" awk '
      # ENVIRON, not -v: awk -v backslash-expands its input, and the
      # query is data.
      BEGIN { q = ENVIRON["Q"] }
      {
        n = split($0, parts, "/")
        if (index(tolower(parts[n]), q) > 0) {
          print $0
          c++
        }
        if (c >= 40) exit
      }'
