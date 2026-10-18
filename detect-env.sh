#!/bin/bash
# detect-env.sh — one-shot, READ-ONLY environment probe for the Command
# Center, run once at palette startup via `bash -lc` (login shell so the
# omarchy helpers and XDG vars are present). Writes nothing, ever: the shell's
# plugin watcher reloads the plugin on any write inside this directory.
#
# stdout, one KEY=value per line (split on the FIRST "=" only):
#   DEFAULT_AGENT=<id or empty>        from omarchy-default-agent
#   AGENT=<id>                         one line per installed agent CLI
#   WEB_NAME=<engine name>             for the "Open in <name>" label
#   WEB_URL=<url template with %s>     engine search URL, %s = the query
#
# Web-engine precedence (the configured browser's default engine):
#   1. override file  $XDG_CONFIG_HOME/omarchy/defaults/websearch
#      either "Name|https://host/path?q=%s" or a bare url template
#   2. the browser profile's custom default provider (chromium-family
#      Preferences), when it defines a usable search_url
#   3. the browser's stock address-bar engine (Google for chromium/chrome/
#      edge/firefox/zen, Brave Search for brave)
#   4. DuckDuckGo, if the browser can't even be identified

set -u

echo "DEFAULT_AGENT=$(omarchy-default-agent 2>/dev/null | head -1)"

# Keep in sync with AGENT_IDS in Agents.js.
for id in pi omp opencode claude codex grok gemini openclaw hermes copilot \
  crush cursor-agent muse; do
  command -v "$id" >/dev/null 2>&1 && echo "AGENT=$id"
done

# ---- 1. explicit override ------------------------------------------------
override="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/defaults/websearch"
if [[ -f $override ]]; then
  line=$(grep -v '^[[:space:]]*#' "$override" | grep -v '^[[:space:]]*$' | head -1)
  if [[ $line == *%s* ]]; then
    if [[ $line == *"|"* ]]; then
      web_name="${line%%|*}"
      web_url="${line#*|}"
    else
      web_name="Custom"
      web_url="$line"
    fi
    # The template prefixes every palette web search — web scheme only.
    # The override file is user-owned, but this branch also guards the
    # principle for anything that ever writes it.
    case "$web_url" in
      http://*%s* | https://*%s*)
        echo "WEB_NAME=$web_name"
        echo "WEB_URL=$web_url"
        exit 0
        ;;
    esac
  fi
fi

# ---- 2/3. the default browser's profile, then its stock engine -----------
browser=$(xdg-settings get default-web-browser 2>/dev/null | sed 's/\.desktop$//')
python3 - "$browser" <<'PY'
import json, os, sys

browser = (sys.argv[1] or "").lower()
home = os.path.expanduser("~")

profiles = {
    "chromium": f"{home}/.config/chromium/Default/Preferences",
    "google-chrome": f"{home}/.config/google-chrome/Default/Preferences",
    "brave": f"{home}/.config/BraveSoftware/Brave-Browser/Default/Preferences",
    "microsoft-edge": f"{home}/.config/microsoft-edge/Default/Preferences",
}
stock = {
    "brave": ("Brave Search", "https://search.brave.com/search?q=%s"),
}
default_stock = ("Google", "https://www.google.com/search?q=%s")

def emit(name, url):
    print(f"WEB_NAME={name}")
    print(f"WEB_URL={url}")

# 2) a custom default provider stored in the profile (chromium-family)
path = profiles.get(browser)
if path and os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            prefs = json.load(f)
        candidates = [prefs.get("default_search_provider") or {}]
        search = prefs.get("search") or {}
        candidates.append(search.get("default_search_provider_data") or {})
        for cand in candidates:
            su = cand.get("search_url")
            u = su.get("url") if isinstance(su, dict) else None
            if isinstance(u, str) and "{searchTerm}" in u and u.startswith("http"):
                emit(str(cand.get("name") or browser), u.replace("{searchTerm}", "%s"))
                raise SystemExit
    except SystemExit:
        raise
    except Exception:
        pass  # unreadable/foreign profile → fall through to the stock engine

# 3) stock address-bar engine for a recognized browser
if browser.startswith(("firefox", "zen")) or browser in profiles:
    emit(*stock.get(browser, default_stock))
    raise SystemExit

# 4) unknown browser → privacy-friendly fallback
emit("DuckDuckGo", "https://duckduckgo.com/?q=%s")
PY
