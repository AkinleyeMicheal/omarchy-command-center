#!/usr/bin/env bash
# search-scripts.test.sh — arg validation and output shape for the Phase-7
# provider scripts (win-ctl, dict-lookup, file-search). Only deterministic,
# offline paths are asserted; the live dictionary API is never called.
# Run: bash tests/search-scripts.test.sh
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

# ---------------------------------------------------------------- win-ctl
bash win-ctl.sh >/dev/null 2>&1; expect_exit "win-ctl no args" 4 $?
bash win-ctl.sh frobnicate >/dev/null 2>&1; expect_exit "win-ctl bad mode" 4 $?
bash win-ctl.sh list extra >/dev/null 2>&1; expect_exit "win-ctl list extra arg" 4 $?
bash win-ctl.sh focus >/dev/null 2>&1; expect_exit "focus no addr" 4 $?
bash win-ctl.sh focus "1234" >/dev/null 2>&1; expect_exit "focus bad prefix" 4 $?
bash win-ctl.sh focus "0xzz" >/dev/null 2>&1; expect_exit "focus non-hex" 4 $?
bash win-ctl.sh focus "0xdeadbeef; print(1)" >/dev/null 2>&1; expect_exit "focus injection" 4 $?
bash win-ctl.sh focus "0x$(printf 'f%.0s' {1..30})" >/dev/null 2>&1; expect_exit "focus too long" 4 $?

out="$(bash win-ctl.sh list 2>/dev/null)"; rc=$?
expect_exit "win-ctl list rc" 0 $rc
case "$out" in
  \[*\]) passed=$((passed + 1)) ;;
  *) failed=$((failed + 1)); echo "FAIL win-ctl list shape: [$out]" >&2 ;;
esac
if [ -n "$out" ] && [ "$out" != "[]" ]; then
  bad="$(printf '%s' "$out" | jq '[.[] | select(
    (.addr | type) != "string" or (.class | type) != "string"
    or (.title | type) != "string" or (.ws | type) != "string")] | length' 2>/dev/null)"
  expect_eq "win-ctl row keys" "$bad" "0"
  # Addresses stay bare hex — the focus path's injection contract.
  badaddr="$(printf '%s' "$out" | jq '[.[] | select(.addr | test("^0x[0-9a-fA-F]+$") | not)] | length')"
  expect_eq "win-ctl addr format" "$badaddr" "0"
fi

# ------------------------------------------------------------------ dict
bash dict-lookup.sh "" >/dev/null 2>&1; expect_exit "dict empty" 4 $?
bash dict-lookup.sh "a;rm -rf /" >/dev/null 2>&1; expect_exit "dict injection" 4 $?
bash dict-lookup.sh "abc <script>" >/dev/null 2>&1; expect_exit "dict angle brackets" 4 $?
bash dict-lookup.sh "word\$HOME" >/dev/null 2>&1; expect_exit "dict dollar" 4 $?
long="$(printf 'a%.0s' {1..80})"
bash dict-lookup.sh "$long" >/dev/null 2>&1; expect_exit "dict too long" 4 $?

# ---------------------------------------------------------- file-search
bash file-search.sh "" >/dev/null 2>&1; expect_exit "file empty" 4 $?
big="$(printf 'x%.0s' {1..200})"
bash file-search.sh "$big" >/dev/null 2>&1; expect_exit "file too long" 4 $?

out="$(bash file-search.sh Palette 2>/dev/null)"; rc=$?
expect_exit "file search rc" 0 $rc
# Order-independent: fd's parallel walk may emit matches in any order.
if printf '%s\n' "$out" | grep -q '/Palette\.qml$'; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
  echo "FAIL file search hit: no Palette.qml among results" >&2
fi
n="$(printf '%s\n' "$out" | grep -c .)"
if [ "$n" -le 40 ]; then passed=$((passed + 1)); else
  failed=$((failed + 1)); echo "FAIL file search cap: $n rows" >&2
fi

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
