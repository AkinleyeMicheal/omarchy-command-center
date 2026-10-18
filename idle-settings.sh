#!/usr/bin/env bash
# idle-settings.sh — read/write Omarchy's idle timeouts for the power
# popover's Idle section (7.3): the screensaver and lock delays live in
# ~/.config/omarchy/shell.json (idle.screensaver / idle.lock, seconds);
# omarchy-shell watches that file (FileView watchChanges), so an atomic
# write applies live — the idle service binds to shellConfig.idle.
#
#   idle-settings.sh get
#   idle-settings.sh set <screensaver|lock> <seconds>
#
# set accepts ONLY the closed value set the popover chips offer — any
# other key or value exits 2 before the file is touched. Zero is
# deliberately absent: the idle service treats 0 as "trigger immediately"
# (Service.qml startIdleCycle — delay 0 fires now), not "never"; the
# chips' "Off" is encoded as 86400 (24 h) and the Stay Awake switch is
# the real off for both timers. jq edits atomically (tmp + mv) and
# preserves every other key — notably "version": 1, without which the
# shell falls back to defaults.
#
# Exit codes: save-side 0 ok · 2 usage/rejected value · 1 write failure;
# get also uses 3 for a missing config. OMARCHY_SHELL_JSON overrides the
# config path for tests.
set -u

json="${OMARCHY_SHELL_JSON:-$HOME/.config/omarchy/shell.json}"

cmd="${1:-}"

case "$cmd" in
  get)
    [ "$#" -eq 1 ] || exit 2
    [ -f "$json" ] || exit 3
    jq -r '[(.idle.screensaver // 150 | tostring),
            (.idle.lock // 300 | tostring)] | join(" ")' "$json"
    ;;
  set)
    [ "$#" -eq 3 ] || exit 2
    key="$2"
    case "$key" in
      screensaver | lock) ;;
      *) exit 2 ;;
    esac
    value="$3"
    case "$value" in
      60 | 120 | 300 | 600 | 900 | 1800 | 3600 | 86400) ;;
      *) exit 2 ;;
    esac
    [ -f "$json" ] || exit 1
    tmp=$(mktemp "${json}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"' EXIT
    jq --arg k "$key" --argjson v "$value" \
      '.idle = ((.idle // {}) + {($k): $v})' "$json" >"$tmp" || exit 1
    mv -f "$tmp" "$json" || exit 1
    trap - EXIT
    ;;
  *)
    exit 2
    ;;
esac
