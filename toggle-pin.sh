#!/bin/bash
# toggle-pin.sh <route> — add/remove a route in the command center's pinned
# favorites (a JSON array, most recently pinned first). Atomic under flock
# so concurrent toggles never clobber each other. Prints the resulting
# state: "pinned" or "unpinned".
set -euo pipefail

route="${1:?toggle-pin: missing route}"
# Outside the plugin dir: inotifywait -r on the plugin tree means writes
# here would hot-reload the plugin mid-toggle. See build-catalog.sh.
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
file="$dir/pins.json"

mkdir -p "$dir"
chmod 700 "$dir" 2>/dev/null || true   # holds the pin list
exec 9>"$file.lock"
flock 9
if [[ ! -s $file ]]; then
  old_umask=$(umask); umask 077
  echo '[]' > "$file"
  umask "$old_umask"
fi

tmp=$(mktemp "$dir/.pins.XXXXXX")
state=$(jq --arg r "$route" 'if index($r) then map(select(. != $r)) else [$r] + . end' "$file" > "$tmp" \
  && jq -r --arg r "$route" 'if index($r) then "pinned" else "unpinned" end' "$tmp")
mv "$tmp" "$file"
echo "$state"
