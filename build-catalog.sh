#!/bin/bash
# build-catalog.sh — build the command-center cache for fonsgaudii.cmdcenter.
#
# Output: one JSON object on stdout:
#   { "commands": [...], "groups": {...}, "apps": [...] }
#
# Commands come from `omarchy commands --json` (authoritative). Apps are
# enumerated from .desktop entries using the SAME primitives Omarchy's own
# AppLibrary uses — hidden-entries.sh (Hidden/NoDisplay/OnlyShowIn/NotShowIn)
# and default/omarchy/launcher.hides — plus the same icon-index scan, so the
# list matches what the built-in menu shows. This bypasses the shell's
# shell.appLibrary facade, which is currently null for third-party menu
# plugins (upstream: omacom/omarchy#10973, #11068, #10876).

set -euo pipefail

# State lives OUTSIDE the plugin dir on purpose: the shell hot-reload
# watcher runs `inotifywait -m -r` over the whole plugin tree, so any write
# under it (cache, locks, temp files) would reload the plugin mid-operation
# and recreate the palette. XDG state dir it is.
cache_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-cmdcenter"
omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
mkdir -p "$cache_dir"

# --- staleness gate (--if-stale) -------------------------------------------
# The shell triggers this once per session. If nothing that feeds the cache
# is newer than the cache itself, exit WITHOUT rebuilding or writing — zero
# churn for the plugin's file watcher and no needless `omarchy commands`
# run. Any newer source (omarchy update, app install, script edit) falls
# through to the full rebuild below.
if [[ "${1:-}" == "--if-stale" && -f "$cache_dir/commands.json" ]]; then
  cache="$cache_dir/commands.json"
  newer=$(find "$omarchy_path" \
    "$HOME/.local/share/applications" \
    "$HOME/.nix-profile/share/applications" \
    "$HOME/.config/omarchy/launcher.hides" \
    "$(command -v omarchy)" "$0" \
    -newer "$cache" -print -quit 2>/dev/null || true)
  if [[ -z $newer ]]; then
    IFS=':' read -ra _ddirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for _d in "${_ddirs[@]}"; do
      [[ -d "$_d/applications" ]] || continue
      if find "$_d/applications" -newer "$cache" -print -quit 2>/dev/null | grep -q .; then
        newer=1; break
      fi
    done
  fi
  [[ -z $newer ]] && exit 0
fi

# Bulk JSON/text travels as temp files: Linux caps a single argv entry at
# 128KB (MAX_ARG_STRLEN), which the icon index and apps list both exceed.
groups_file=$(mktemp)
tsv_file=$(mktemp)
icon_file=$(mktemp)
apps_file=$(mktemp)
trap 'rm -f "$groups_file" "$tsv_file" "$icon_file" "$apps_file"' EXIT

# --- group descriptions, scraped from the omarchy dispatcher itself -------
groups_json=$(sed -n 's/^GROUP_DESCRIPTIONS\[\([^]]*\)\]="\([^"]*\)"$/\1\t\2/p' "$(command -v omarchy)" \
  | jq -Rn '[inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries')

# --- hidden desktop-entry ids (Omarchy's own filter, same desktop context) -
desktop=""
for v in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}"; do
  [[ -n $v ]] && desktop+="${desktop:+:}$v"
done
hidden_ids=$("$omarchy_path/shell/services/hidden-entries.sh" "$desktop" 2>/dev/null || true)
hides=$(cat "$omarchy_path/default/omarchy/launcher.hides" "$HOME/.config/omarchy/launcher.hides" 2>/dev/null || true)

# --- candidate .desktop files: user dir first, first-id-wins (same order
#     and dedupe semantics as hidden-entries.sh) --------------------------
declare -A seen_ids
files=()
scan_apps_dir() {
  local dir=$1 f rel id
  [[ -d $dir ]] || return 0
  while IFS= read -r -d '' f; do
    rel=${f#"$dir"/}; rel=${rel%.desktop}; id=${rel//\//-}
    [[ -n ${seen_ids[$id]+x} ]] && continue
    seen_ids[$id]=1
    files+=("$f")
  done < <(find "$dir" -type f -name '*.desktop' -print0 2>/dev/null | sort -z)
}

scan_apps_dir "$HOME/.local/share/applications"
IFS=':' read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  scan_apps_dir "$data_dir/applications"
done
scan_apps_dir "$HOME/.nix-profile/share/applications"

# --- parse [Desktop Entry] fields into TSV lines ---------------------------
tsv=""
if (( ${#files[@]} > 0 )); then
  tsv=$(printf '%s\0' "${files[@]}" | xargs -0 awk '
    function file_id( r) {
      r = FILENAME
      sub(/^.*\/applications\//, "", r)
      sub(/\.desktop$/, "", r)
      gsub(/\//, "-", r)
      return r
    }
    function clean(s) { gsub(/[\t\r\n]/, " ", s); return s }
    FNR == 1 { id = file_id(); type = ""; name = ""; comment = ""; keywords = ""; icon = ""; inde = 0 }
    /^\[/ { inde = ($0 == "[Desktop Entry]"); next }
    inde == 1 {
      if (type == "" && /^Type=/) type = clean(substr($0, 6))
      else if (name == "" && /^Name=/) name = clean(substr($0, 6))
      else if (comment == "" && /^Comment=/) comment = clean(substr($0, 9))
      else if (keywords == "" && /^Keywords=/) keywords = clean(substr($0, 10))
      else if (icon == "" && /^Icon=/) icon = clean(substr($0, 6))
    }
    ENDFILE {
      if (type == "Application" && name != "")
        printf "%s\t%s\t%s\t%s\t%s\n", id, name, comment, keywords, icon
    }
  ')
fi

# --- icon index: same scan as the shell's AppLibrary (svg before png, so
#     scalable icons win; first hit per name kept) --------------------------
icon_index=$(
  dirs="$HOME/.icons $HOME/.local/share/icons"
  IFS=":"
  for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done
  unset IFS
  for ext in svg png; do
    for base in $dirs; do
      [[ -d $base ]] && find "$base" \( -path "*/apps/*" -o -path "*/devices/*" \) -name "*.$ext" 2>/dev/null || true
    done
    find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null || true
  done
)

# --- assemble apps JSON: visible = Application entries not hidden ----------
printf '%s\n' "$tsv" > "$tsv_file"
printf '%s\n' "$icon_index" > "$icon_file"

apps_json=$(jq -n \
  --rawfile tsv "$tsv_file" --rawfile ii "$icon_file" \
  --arg hs "$hidden_ids" --arg ls "$hides" '
  ($tsv | split("\n")) as $lines
  | (($hs + "\n" + $ls) | split("\n") | map(select(length > 0)) | unique) as $hide
  | ($ii | split("\n") | map(select(length > 0))) as $iconLines
  | (reduce $iconLines[] as $line ({};
      ($line | capture("(?<n>[^/]+)\\.(svg|png)$")?) as $cap
      | if $cap == null then . elif has($cap.n) then . else . + {($cap.n): $line} end)) as $icons
  | [ $lines[]
      | select(length > 0)
      | split("\t")
      | { id: .[0], name: .[1], comment: .[2],
          keywords: (.[3] | split(";") | map(select(length > 0))), icon: .[4] }
      | select(.id as $i | ($hide | index($i)) == null)
      | . + { iconPath: ($icons[.icon] // "") } ]
  | sort_by(.name)
')

# --- commands + final atomic cache write -----------------------------------
printf '%s\n' "$groups_json" > "$groups_file"
printf '%s\n' "$apps_json" > "$apps_file"
omarchy commands --json \
  | jq -c --rawfile g "$groups_file" --rawfile a "$apps_file" \
    '{commands: .commands, groups: ($g | fromjson), apps: ($a | fromjson)}' \
    > "$cache_dir/commands.json.tmp"
mv "$cache_dir/commands.json.tmp" "$cache_dir/commands.json"
cat "$cache_dir/commands.json"
