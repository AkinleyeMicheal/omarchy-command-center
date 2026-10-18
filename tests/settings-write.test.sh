#!/usr/bin/env bash
# settings-write.test.sh — allowlist + atomicity tests for
# settings-write.sh (Phase 8.5a). Runs against a throwaway state dir
# (CMD_STATE_DIR), never the real settings.json.
# Run: bash tests/settings-write.test.sh
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../settings-write.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0
check() {
  local name="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $name (want [$want], got [$got])"
  fi
}

run() { CMD_STATE_DIR="$tmp" bash "$script" "$@" 2>/dev/null; }
code() { CMD_STATE_DIR="$tmp" bash "$script" "$@" >/dev/null 2>&1; echo $?; }

# ---- defaults --------------------------------------------------------
check "fresh get is default JSON" '{"cards":{"weather":true,"system":true},"density":70}' \
  "$(run get | jq -c .)"

# ---- valid sets + merge ---------------------------------------------
check "set weather false → 0" "0" "$(code set cards.weather false)"
check "weather now false" "false" "$(run get | jq -r .cards.weather)"
check "set density 84 → 0" "0" "$(code set density 84)"
check "density now 84" "84" "$(run get | jq -r .density)"
check "merge preserved: weather still false" "false" "$(run get | jq -r .cards.weather)"
check "set system false → 0" "0" "$(code set cards.system false)"
check "both cards off" "false false" \
  "$(run get | jq -r '[.cards.weather, .cards.system] | @tsv' | tr '\t' ' ')"
check "density 96 allowed" "0" "$(code set density 96)"
check "density 70 allowed" "0" "$(code set density 70)"

# ---- invalid values (must not touch the file) ------------------------
before="$(run get | jq -c .)"
check "density 60 rejected" "4" "$(code set density 60)"
check "density 0 rejected" "4" "$(code set density 0)"
check "density 150 rejected" "4" "$(code set density 150)"
check "weather yes rejected" "4" "$(code set cards.weather yes)"
check "weather 1 rejected" "4" "$(code set cards.weather 1)"
check "weather OFF rejected" "4" "$(code set cards.weather OFF)"
check "file untouched after rejections" "$before" "$(run get | jq -c .)"

# ---- unknown keys ----------------------------------------------------
check "unknown key rejected" "3" "$(code set cards.media false)"
check "bare key rejected" "3" "$(code set weather false)"
check "nested-injection key rejected" "3" "$(code set 'cards.weather.x' true)"

# ---- shell-injection attempts ---------------------------------------
check "value injection rejected" "4" "$(code set density '$(touch pwned)')"
check "no injection file created" "0" "$(find "$tmp" -name pwned | wc -l)"
check "key injection rejected" "3" "$(code set 'cards.weather;reboot' true)"
check "file still valid after attacks" "0" \
  "$(CMD_STATE_DIR="$tmp" bash "$script" get | jq -e . >/dev/null 2>&1; echo $?)"

# ---- usage -----------------------------------------------------------
check "no args → 2" "2" "$(code)"
check "set without value → 2" "2" "$(code set cards.weather)"
check "bad subcommand → 2" "2" "$(code update)"

echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
