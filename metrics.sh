#!/usr/bin/env bash
# metrics.sh — the live feed for the System & Network tile while the
# palette is open (Phase 8.4, user-directed amendment to open-cycle).
#
# Deliberately separate from status.sh's full open-cycle probe:
#   - identity fields (IP, gateway) only change on link events and ride
#     status.sh at open — nmcli detail lookups are not worth a tick;
#   - everything here samples inside one short ~0.5s window, with a
#     2-packet ping overlapping that window, so a run lands under ~1.5s
#     (QML ticks every 2s and skips while one is in flight).
# One bounded run per tick, no state, argv-only like every script here.
set -u

# Device resolved exactly like status.sh (connected physical link;
# loopback/tun/VPN skipped).
dev=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null \
  | awk -F: '$3 == "connected" && $2 ~ /^(ethernet|wifi|gsm|cdma)$/ { print $1; exit }')

# Sample window start: kick a 2-packet ping now so it overlaps the CPU
# and traffic sampling instead of serializing behind them.
d=$(mktemp -d) || d=""
trap '[ -n "$d" ] && rm -rf "$d"' EXIT
if [[ -n $d ]]; then
  ( ping -c 2 -i 0.3 -W 1 1.1.1.1 2>/dev/null || true ) >"$d/ping" &
  ping_pid=$!
fi

rx1=""
tx1=""
if [[ -n $dev ]]; then
  rx1=$(awk -v d="$dev" '$1 == d ":" { print $2 }' /proc/net/dev 2>/dev/null)
  tx1=$(awk -v d="$dev" '$1 == d ":" { print $10 }' /proc/net/dev 2>/dev/null)
fi

# CPU from omarchy's stats CLI — the exact source status.sh uses, so a
# tick and an open-cycle probe report identical units.
if out=$(omarchy-system-stats 2>/dev/null) && [[ -n $out ]]; then
  cpu=$(awk -F'\t' '$1 == "cpu" { print $2 }' <<<"$out")
  [[ -n $cpu ]] && echo "CPU=$cpu"
fi

sleep 0.5

if [[ -n $dev ]]; then
  rx2=$(awk -v d="$dev" '$1 == d ":" { print $2 }' /proc/net/dev 2>/dev/null)
  tx2=$(awk -v d="$dev" '$1 == d ":" { print $10 }' /proc/net/dev 2>/dev/null)
  if [[ -n $rx2 && -n $tx2 ]]; then
    echo "NET_RXB=$rx2"
    echo "NET_TXB=$tx2"
    if [[ -n $rx1 && -n $tx1 ]]; then
      # 0.5s window → bytes per second.
      echo "NET_RX_RATE=$(((rx2 - rx1) * 2))"
      echo "NET_TX_RATE=$(((tx2 - tx1) * 2))"
    fi
  fi
fi

# Ping + loss parsed unconditionally (a single dropped probe is data),
# same extraction as status.sh.
if [[ -n $d && -n ${ping_pid:-} ]]; then
  wait "$ping_pid" 2>/dev/null
  out=$(cat "$d/ping" 2>/dev/null)
  if [[ -n $out ]]; then
    loss=$(grep -oE '[0-9]+% packet loss' <<<"$out" | head -1 | grep -oE '^[0-9]+')
    avg=$(sed -nE 's|.*= [0-9.]+/([0-9.]+)/[0-9.]+.*|\1|p' <<<"$out" | head -1)
    [[ -n $loss ]] && echo "NET_LOSS=$loss"
    [[ -n $avg ]] && echo "NET_PING=$avg"
  fi
fi
