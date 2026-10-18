#!/bin/bash
# status.sh — READ-ONLY system status probe for the Command Center's
# Controls view (Phase 5). One KEY=value per line; every source is guarded
# so a missing tool or degraded box degrades to skipped lines, never errors.
# Never writes anything, never toggles anything.
set -u

# Battery (laptops): omarchy's own CLI, tab-separated fields.
if out=$(omarchy-battery-status --shell 2>/dev/null) && [[ -n $out ]]; then
  pct=$(awk -F'\t' '$1 == "percentage" { print $2 }' <<<"$out")
  st=$(awk -F'\t' '$1 == "state" { print $2 }' <<<"$out")
  [[ -n $pct ]] && echo "BATTERY=$pct${st:+ ($st)}"
fi

# Output volume + mute (PipeWire via wpctl). The display string keeps its
# Phase-5 shape; VOLUME_PCT / OUTPUTMUTED / INPUT_PCT are the structured
# keys the footer rail's audio popover binds its sliders to.
if out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null); then
  frac=$(grep -oE '[0-9]+\.[0-9]+' <<<"$out" | head -1)
  if [[ -n $frac ]]; then
    pct=$(awk "BEGIN { printf \"%d\", $frac * 100 + 0.5 }")
    echo "VOLUME_PCT=$pct"
    if grep -q MUTED <<<"$out"; then
      echo "OUTPUTMUTED=true"
      echo "VOLUME=muted (${pct}%)"
    else
      echo "OUTPUTMUTED=false"
      echo "VOLUME=${pct}%"
    fi
  fi
fi

# Microphone mute state + level (level feeds the popover's input slider)
if out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null); then
  if grep -q MUTED <<<"$out"; then echo "MICMUTED=true"
  else echo "MICMUTED=false"; fi
  frac=$(grep -oE '[0-9]+\.[0-9]+' <<<"$out" | head -1)
  [[ -n $frac ]] && echo "INPUT_PCT=$(awk "BEGIN { printf \"%d\", $frac * 100 + 0.5 }")"
fi

# CPU / memory from omarchy's stats CLI
if out=$(omarchy-system-stats 2>/dev/null) && [[ -n $out ]]; then
  cpu=$(awk -F'\t' '$1 == "cpu" { print $2 }' <<<"$out")
  mem=$(awk -F'\t' '$1 == "memory" { print $2 }' <<<"$out")
  [[ -n $cpu ]] && echo "CPU=$cpu"
  [[ -n $mem ]] && echo "MEM=$mem"
fi

# Do not disturb: the notifications service's persisted `dnd` key
# (same file its "cross-restart backstop" comment describes); absent = off.
dndfile="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/notifications.json"
dnd=off
if [[ -f $dndfile ]] && [[ "$(jq -r '.dnd // false' "$dndfile" 2>/dev/null)" == "true" ]]; then
  dnd=on
fi
echo "DND=$dnd"

# Night light: omarchy's toggle script --status is a pure read
if out=$(omarchy-toggle-nightlight --status 2>/dev/null) && [[ -n $out ]]; then
  nl=$(jq -r 'if .enabled == true then "on" else "off" end' <<<"$out" 2>/dev/null)
  [[ -n $nl && $nl != null ]] && echo "NIGHTLIGHT=$nl"
fi

# Stay Awake: --status is a pure read (enabled = stay-awake armed)
if out=$(omarchy-toggle-idle --status 2>/dev/null) && [[ -n $out ]]; then
  sa=$(jq -r 'if .enabled == true then "on" else "off" end' <<<"$out" 2>/dev/null)
  [[ -n $sa && $sa != null ]] && echo "STAYAWAKE=$sa"
fi

# Screensaver availability — inverted gate exactly like the menu's
# `when:` conditions (screensaver-off enabled = screensaver disabled)
if omarchy-toggle-enabled screensaver-off >/dev/null 2>&1; then
  echo "SCREENSAVER=off"
else
  echo "SCREENSAVER=on"
fi

# Wi-Fi radio + currently connected SSID — ONLY when the box actually has
# a Wi-Fi device (nmcli reports the rfkill switch as "enabled" even on a
# wired-only desktop; a fake toggle row would be worse than none). SSID
# may truncate on names containing ":" — cosmetic only. SIGNAL is the
# "network settings" strength number (0-100).
if nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | grep -q ':wifi$'; then
  if [[ "$(nmcli radio wifi 2>/dev/null)" == enabled ]]; then echo "WIFI=on"
  else echo "WIFI=off"; fi
  ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')
  [[ -n $ssid ]] && echo "WIFI_SSID=$ssid"
  sig=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')
  [[ -n $sig ]] && echo "WIFI_SIGNAL=$sig"
fi

# Primary wired/wireless connection name for the status readout
con=$(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null \
  | awk -F: '$2 ~ /^(802-3-ethernet|802-11-wireless|gsm|cdma)$/ { print $1; exit }')
[[ -n $con ]] && echo "CONNECTION=$con"

# Primary IPv4 + gateway — the address on whatever physical link is
# actually up (Wi-Fi or wired). `con show` rejects detail fields here,
# so take the first connected non-loopback device and read its details;
# tun/VPN devices are skipped exactly like the CONNECTION filter above.
# Link health (ping + loss) runs before the rate window so a short-
# lived run still reports it; the traffic rates need the ~1s window
# (two /proc/net/dev reads) and are the first thing sacrificed if the
# run is cut short.
dev=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null \
  | awk -F: '$3 == "connected" && $2 ~ /^(ethernet|wifi|gsm|cdma)$/ { print $1; exit }')
if [[ -n $dev ]]; then
  ip=$(nmcli -g IP4.ADDRESS dev show "$dev" 2>/dev/null | head -1 | cut -d/ -f1)
  gw=$(nmcli -g IP4.GATEWAY dev show "$dev" 2>/dev/null | head -1)
  [[ -n $ip ]] && echo "NET_IP=$ip"
  [[ -n $gw ]] && echo "NET_GW=$gw"
fi
# Parsed unconditionally: ping prints its stats even on heavy loss, and
# "100%" is data. Only an empty output (no network stack at all) is
# skipped.
out=$(ping -c 3 -i 0.3 -W 1 1.1.1.1 2>/dev/null || true)
if [[ -n $out ]]; then
  loss=$(grep -oE '[0-9]+% packet loss' <<<"$out" | head -1 | grep -oE '^[0-9]+')
  avg=$(sed -nE 's|.*= [0-9.]+/([0-9.]+)/[0-9.]+.*|\1|p' <<<"$out" | head -1)
  [[ -n $loss ]] && echo "NET_LOSS=$loss"
  [[ -n $avg ]] && echo "NET_PING=$avg"
fi
if [[ -n $dev ]]; then
  rx1=$(awk -v d="$dev" '$1 == d ":" { print $2 }' /proc/net/dev 2>/dev/null)
  tx1=$(awk -v d="$dev" '$1 == d ":" { print $10 }' /proc/net/dev 2>/dev/null)
  sleep 1
  rx2=$(awk -v d="$dev" '$1 == d ":" { print $2 }' /proc/net/dev 2>/dev/null)
  tx2=$(awk -v d="$dev" '$1 == d ":" { print $10 }' /proc/net/dev 2>/dev/null)
  if [[ -n $rx2 && -n $tx2 ]]; then
    echo "NET_RXB=$rx2"
    echo "NET_TXB=$tx2"
    if [[ -n $rx1 && -n $tx1 ]]; then
      echo "NET_RX_RATE=$((rx2 - rx1))"
      echo "NET_TX_RATE=$((tx2 - tx1))"
    fi
  fi
fi

# Bluetooth power
if out=$(bluetoothctl show 2>/dev/null) && [[ -n $out ]]; then
  if grep -q "Powered: yes" <<<"$out"; then echo "BT=on"; else echo "BT=off"; fi
fi

# Session-action availability, gated exactly like omarchy-menu.jsonc
# (suspend hidden when the user disabled it; hibernate only when it works).
if omarchy-toggle-enabled suspend-off >/dev/null 2>&1; then
  echo "SUSPEND_OK=false"
else
  echo "SUSPEND_OK=true"
fi
if omarchy-hibernation-available >/dev/null 2>&1; then
  echo "HIBERNATE_OK=true"
else
  echo "HIBERNATE_OK=false"
fi
