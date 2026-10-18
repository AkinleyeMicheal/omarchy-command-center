#!/bin/bash
# Tests for update-usage.sh (record / forget / 90-day sweep) against a
# throwaway XDG_STATE_HOME — never touches the live state dir.
# Run: bash tests/usage.test.sh
set -u
cd "$(dirname "$0")/.."
export XDG_STATE_HOME
XDG_STATE_HOME=$(mktemp -d)
script="$PWD/update-usage.sh"
file="$XDG_STATE_HOME/omarchy-cmdcenter/usage.json"
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
jqv() { jq -r "$1" "$file" 2>/dev/null; }

# ---- record
bash "$script" "omarchy theme set"
check "record: count starts at 1" "1" "$(jqv '.["omarchy theme set"].count')"
check "record: last is ~now" "ok" \
  "$([[ $(jqv '.["omarchy theme set"].last') -gt $(( ($(date +%s) - 60) * 1000 )) ]] && echo ok)"

bash "$script" "omarchy theme set"
check "record: second launch -> count 2" "2" "$(jqv '.["omarchy theme set"].count')"

bash "$script" "app:chromium"
check "record: app route works" "1" "$(jqv '.["app:chromium"].count')"

# ---- seed aged entries -----------------------------------------------
# 40 days old: beyond the strip's 30-day expiry but INSIDE the 90-day disk
# sweep — must survive a write.
old=$(( ($(date +%s) - 40 * 86400) * 1000 ))
jq --argjson t "$old" '.["old:40d"] = {count: 3, last: $t}' "$file" > "$file.tmp" \
  && mv "$file.tmp" "$file"
# 100 days old: must be swept on the next write.
older=$(( ($(date +%s) - 100 * 86400) * 1000 ))
jq --argjson t "$older" '.["ancient:100d"] = {count: 9, last: $t}' "$file" > "$file.tmp" \
  && mv "$file.tmp" "$file"

bash "$script" "some new route"
check "sweep: 100-day entry dropped" "null" "$(jqv '.["ancient:100d"] // "null"')"
check "sweep: 40-day entry survives" "3" "$(jqv '.["old:40d"].count')"
check "sweep: new record present" "1" "$(jqv '.["some new route"].count')"
check "sweep: recent entries untouched" "2" "$(jqv '.["omarchy theme set"].count')"

# ---- forget ----------------------------------------------------------
bash "$script" forget "omarchy theme set"
check "forget: route removed" "null" "$(jqv '.["omarchy theme set"] // "null"')"
check "forget: other routes kept" "1" "$(jqv '.["app:chromium"].count')"
check "forget: sweep data still intact" "3" "$(jqv '.["old:40d"].count')"

bash "$script" forget "never-existed"
check "forget: missing route is a no-op exit 0" "0" "$?"
check "forget: file still valid JSON" "object" "$(jq -r 'type' "$file")"

# ---- concurrency sanity: serialized writes never clobber -------------
for i in 1 2 3 4 5; do bash "$script" "parallel:test" & done
wait
check "flock: 5 concurrent records -> count 5" "5" "$(jqv '.["parallel:test"].count')"

echo "$pass passed, $fail failed"
rm -rf "$XDG_STATE_HOME"
exit $((fail ? 1 : 0))
