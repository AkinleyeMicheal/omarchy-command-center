#!/bin/bash
# settings-write.sh — the only writer for the palette's settings.json
# (Phase 8.5). Closed key/value allowlist in the idle-settings.sh
# shape: unknown keys and out-of-set values exit non-zero WITHOUT
# touching the file. Atomic tmp+mv; the palette's FileView watches the
# file (watchChanges) and applies every change live.
#
#   settings-write.sh set <key> <value>
#   settings-write.sh get             # current settings as JSON
#
# Keys (settings.json):
#   cards.weather  true|false   weather·today tile shown in the home row
#   cards.system   true|false   System & Network tile shown
#   density        70|84|96     home-row tile height in style units
#
# CMD_STATE_DIR — test-only override of the state dir (mirrors
# OMARCHY_SHELL_JSON in idle-settings.sh).
# Exit: 0 ok · 2 usage · 3 unknown key · 4 invalid value · 5 write failed
set -euo pipefail

state="${CMD_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter}"
file="$state/settings.json"
mkdir -p "$state"
[[ -f $file ]] || printf '{"cards":{"weather":true,"system":true},"density":70}\n' >"$file"

cmd="${1:-}"
case "$cmd" in
get)
  cat "$file"
  ;;
set)
  key="${2:-}"
  value="${3:-}"
  if [[ -z $key || -z $value ]]; then
    echo "usage: settings-write.sh set <key> <value>" >&2
    exit 2
  fi
  case "$key" in
  cards.weather | cards.system)
    if [[ $value != true && $value != false ]]; then
      echo "invalid value for $key: $value (want true|false)" >&2
      exit 4
    fi
    sub="${key#cards.}"
    if ! out=$(jq --argjson v "$value" ".cards.\"$sub\" = \$v" "$file" 2>/dev/null); then
      echo "settings.json is malformed" >&2
      exit 5
    fi
    ;;
  density)
    case "$value" in
    70 | 84 | 96) ;;
    *)
      echo "invalid value for density: $value (want 70|84|96)" >&2
      exit 4
      ;;
    esac
    if ! out=$(jq --argjson v "$value" ".density = \$v" "$file" 2>/dev/null); then
      echo "settings.json is malformed" >&2
      exit 5
    fi
    ;;
  *)
    echo "unknown setting: $key" >&2
    exit 3
    ;;
  esac
  printf '%s\n' "$out" >"$file.tmp" && mv "$file.tmp" "$file"
  ;;
*)
  echo "usage: settings-write.sh {get|set <key> <value>}" >&2
  exit 2
  ;;
esac
