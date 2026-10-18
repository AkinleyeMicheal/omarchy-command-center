#!/usr/bin/env bash
# idle-settings.test.sh — arg validation, value allowlist (injection
# attempts), JSON preservation and defaults for idle-settings.sh (7.3).
# Fully offline: OMARCHY_SHELL_JSON points at a sandbox copy.
# Run: bash tests/idle-settings.test.sh
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
export OMARCHY_SHELL_JSON="$sandbox/shell.json"
idle=./idle-settings.sh

# --- arg guards -----------------------------------------------------------
expect_exit "no args" 2 "$(bash "$idle" >/dev/null 2>&1; echo $?)"
expect_exit "set too few" 2 "$(bash "$idle" set screensaver >/dev/null 2>&1; echo $?)"
expect_exit "unknown cmd" 2 "$(bash "$idle" frobnicate >/dev/null 2>&1; echo $?)"
expect_exit "get missing file" 3 "$(bash "$idle" get >/dev/null 2>&1; echo $?)"

# Seed: a realistic shell.json (version + bar + idle).
printf '{"version":1,"bar":{"layout":"full"},"idle":{"screensaver":150,"lock":300}}' \
  >"$OMARCHY_SHELL_JSON"

expect_eq "get defaults" "$(bash "$idle" get)" "150 300"

# --- allowlist (injection attempts never touch the file) -------------------
before=$(cat "$OMARCHY_SHELL_JSON")
expect_exit "reject zero" 2 "$(bash "$idle" set lock 0 >/dev/null 2>&1; echo $?)"
expect_exit "reject garbage" 2 "$(bash "$idle" set lock '5; rm -rf /' >/dev/null 2>&1; echo $?)"
expect_exit "reject unknown key" 2 "$(bash "$idle" set evil 300 >/dev/null 2>&1; echo $?)"
expect_exit "reject float" 2 "$(bash "$idle" set lock 299.9 >/dev/null 2>&1; echo $?)"
expect_exit "reject empty value" 2 "$(bash "$idle" set lock '' >/dev/null 2>&1; echo $?)"
expect_eq "file untouched by rejects" "$(cat "$OMARCHY_SHELL_JSON")" "$before"

# --- set roundtrip ---------------------------------------------------------
expect_exit "set ok" 0 "$(bash "$idle" set screensaver 600 >/dev/null 2>&1; echo $?)"
expect_eq "set reads back" "$(bash "$idle" get)" "600 300"
expect_exit "set lock ok" 0 "$(bash "$idle" set lock 3600 >/dev/null 2>&1; echo $?)"
expect_eq "both set" "$(bash "$idle" get)" "600 3600"

# --- preservation + hygiene ------------------------------------------------
expect_eq "version preserved" \
  "$(jq -r '.version' "$OMARCHY_SHELL_JSON")" "1"
expect_eq "bar preserved" \
  "$(jq -r '.bar.layout' "$OMARCHY_SHELL_JSON")" "full"
expect_eq "valid json" \
  "$(jq -e . "$OMARCHY_SHELL_JSON" >/dev/null 2>&1; echo $?)" "0"
expect_eq "no tmp leftovers" \
  "$(find "$sandbox" -name 'shell.json.*' | wc -l)" "0"

# --- missing idle block gets created, siblings kept ------------------------
printf '{"version":1,"other":7}' >"$OMARCHY_SHELL_JSON"
bash "$idle" set lock 60 >/dev/null 2>&1
expect_eq "idle block created" \
  "$(jq -r '.idle.lock' "$OMARCHY_SHELL_JSON")" "60"
expect_eq "siblings kept" \
  "$(jq -r '.other' "$OMARCHY_SHELL_JSON")" "7"
expect_eq "get fills missing screensaver default" \
  "$(bash "$idle" get)" "150 60"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
