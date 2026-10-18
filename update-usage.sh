#!/bin/bash
# update-usage.sh — manage the command center's usage history (frecency +
# persistent recents data source).
#
#   update-usage.sh <route>            record one launch
#   update-usage.sh forget <route>     remove one route entirely (hover ✕ on
#                                      a recent tile — the manual half of the
#                                      hybrid recents-removal design)
#
# The JSON map (route -> {count, last}) is what Palette.qml reads for frecency
# ranking and the recents strip. Atomic under flock so concurrent launches,
# forgets, and sweeps never clobber each other. The sweep is the automatic
# half: entries untouched for SWEEP_DAYS are dropped on every write, keeping
# the file tidy without ever silently changing recent rankings (the strip
# applies its own softer 30-day expiry in QML).
set -euo pipefail

# Outside the plugin dir: inotifywait -r on the plugin tree means writes
# here would hot-reload the plugin mid-launch. See build-catalog.sh.
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
file="$dir/usage.json"

SWEEP_DAYS=90
cutoff=$(( ($(date +%s) - SWEEP_DAYS * 86400) * 1000 ))

mode="record"
if [[ ${1:-} == "forget" ]]; then
  mode="forget"
  shift
fi
route="${1:?update-usage: missing route}"

mkdir -p "$dir"
exec 9>"$file.lock"
flock 9
[[ -s $file ]] || echo '{}' > "$file"

tmp=$(mktemp "$dir/.usage.XXXXXX")
if [[ $mode == "forget" ]]; then
  jq --arg r "$route" 'del(.[$r])' "$file" > "$tmp"
else
  jq --arg r "$route" --argjson t "$(date +%s%3N)" --argjson cutoff "$cutoff" \
    '.[$r] = ((.[$r] // {}) | {count: ((.count // 0) + 1), last: $t})
     | with_entries(select((.value.last // 0) >= $cutoff))' \
    "$file" > "$tmp"
fi
mv "$tmp" "$file"
