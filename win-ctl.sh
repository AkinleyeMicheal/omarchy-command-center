#!/usr/bin/env bash
# win-ctl.sh list|focus — window-switching provider (Phase 7).
#   list          → JSON array of switchable windows, current one excluded
#   focus <0xADDR> → bring that window (and its workspace) to the front
# Exit: 0 ok · 4 rejected arguments · 1 hyprctl/eval failure.
#
# Focus uses the Lua form `hl.dsp.focus({ window = "address:0x…" })` via
# `hyprctl eval`: raw `hyprctl dispatch` args are Lua-evaluated in Hyprland
# 0.56.2 (upstream #16224), and this is the exact form the shipping
# li.window-controls plugin uses. The address is regex-validated to bare hex
# before it can reach the eval string, so no runtime value is ever code.
set -u

mode="${1:-}"

case "$mode" in
  list)
    [ $# -eq 1 ] || { echo "win-ctl: list takes no arguments" >&2; exit 4; }
    aw="$(hyprctl activewindow -j 2>/dev/null)"
    [ -n "$aw" ] || aw='{}'
    cl="$(hyprctl clients -j 2>/dev/null)"
    [ -n "$cl" ] || cl='[]'
    printf '%s\n%s\n' "$aw" "$cl" | jq -s -c '
      ((.[0] // {}).address // "") as $me
      | [ .[1][]
        | select(.mapped == true and .hidden == false)
        | select(.address != $me)
        | select((.workspace.name // "") | startswith("special:") | not)
        | select(((.class // "") as $c
            | ($c | startswith("org.omarchy.")) or ($c == "quickshell")
            or ($c | startswith("org.quickshell"))) | not)
        | { addr: (.address // "")
          , class: (.class // "")
          , title: (.title // "")
          , ws: (.workspace.name // "") } ]
    ' 2>/dev/null || exit 1
    ;;

  focus)
    addr="${2:-}"
    case "$addr" in
      0x[0-9a-fA-F][0-9a-fA-F]*) ;;
      *) echo "win-ctl: bad address" >&2; exit 4 ;;
    esac
    case "$addr" in
      *[!0-9a-fA-F]*) echo "win-ctl: bad address" >&2; exit 4 ;;
    esac
    [ "${#addr}" -le 20 ] || { echo "win-ctl: bad address" >&2; exit 4; }
    out="$(hyprctl eval "hl.dsp.focus({ window = \"address:$addr\" })" 2>&1)" || exit 1
    case "$out" in
      ok*) exit 0 ;;
      *) printf 'win-ctl: %s\n' "$out" >&2; exit 1 ;;
    esac
    ;;

  *)
    echo "win-ctl: mode must be list or focus" >&2; exit 4 ;;
esac
