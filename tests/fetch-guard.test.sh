#!/usr/bin/env bash
# fetch-guard.test.sh — destination policy for feed-supplied URLs (8.10,
# the marketplace SSRF review point): scheme rejection, address policy
# (v4 + v6 + mapped/NAT64 embeddings + obfuscated literals), userinfo,
# redirect joining, and end-to-end rejection in the image fetcher.
# Offline by default: only the single marked "live" case needs network
# and is skipped (not counted) when none is available.
# Run: bash tests/fetch-guard.test.sh
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

expect_contains() { # name haystack needle
  case "$2" in
    *"$3"*) passed=$((passed + 1)) ;;
    *) failed=$((failed + 1)); echo "FAIL $1: [$2] lacks [$3]" >&2 ;;
  esac
}

guard=./fetch-guard.sh
block() { bash "$guard" check "$1" >/dev/null 2>&1; echo $?; }
allow() { bash "$guard" check "$1" >/dev/null 2>&1; echo $?; }

# --- usage guards ---------------------------------------------------------
expect_exit "no args" 2 "$(bash "$guard" >/dev/null 2>&1; echo $?)"
expect_exit "empty url" 2 "$(bash "$guard" check "" >/dev/null 2>&1; echo $?)"
expect_exit "unknown verb" 2 "$(bash "$guard" frobnicate >/dev/null 2>&1; echo $?)"

# --- scheme / syntax rejections -------------------------------------------
for u in "file:///etc/passwd" "ftp://example.com/x" "gopher://127.0.0.1/" \
         "data:text/html,hi" "javascript:alert(1)" "httpx://example.com/" \
         "example.com/x" "http:///" "httpx"; do
  expect_exit "scheme reject $u" 1 "$(block "$u")"
done
expect_contains "scheme reason" \
  "$(bash "$guard" check "file:///etc/passwd" 2>&1)" "not an http(s) url"

# --- private / reserved destination rejections (IPv4) ---------------------
for u in "http://127.0.0.1/" "http://127.0.0.1:631/" "http://10.1.2.3/" \
         "http://172.16.0.1/" "http://172.31.255.255/" "http://192.168.88.1/" \
         "http://169.254.169.254/latest/meta-data/" "http://100.64.0.1/" \
         "http://0.0.0.0/" "http://255.255.255.255/" "http://224.0.0.1/" \
         "http://198.18.0.1/" "http://192.0.2.1/" "http://198.51.100.7/" \
         "http://203.0.113.9/" "http://0177.0.0.1/"; do
  expect_exit "v4 reject $u" 1 "$(block "$u")"
done

# --- hostname rejections (resolve to private, or unresolvable) ------------
for u in "http://localhost/" "http://localhost:8080/x.png" \
         "http://localhost.localdomain/"; do
  expect_exit "host reject $u" 1 "$(block "$u")"
done

# --- userinfo rejections (credentials never allowed in content URLs) ------
for u in "http://user@10.0.0.1/" "http://user:pass@93.184.216.34/" \
         "http://news.ycombinator.com@192.168.1.1/"; do
  expect_exit "userinfo reject $u" 1 "$(block "$u")"
done
expect_contains "userinfo reason" \
  "$(bash "$guard" check "http://user@10.0.0.1/" 2>&1)" "userinfo rejected"

# --- obfuscated literal forms (normalise to loopback or fail closed) ------
for u in "http://2130706433/" "http://127.1/" "http://0x7f000001/"; do
  expect_exit "obfuscated reject $u" 1 "$(block "$u")"
done

# --- bad ports ------------------------------------------------------------
expect_exit "port >65535" 1 "$(block "http://93.184.216.34:99999/")"
expect_exit "non-numeric port" 1 "$(block "http://a.b:notaport/")"
expect_exit "unbracketed v6" 1 "$(block "http://::1/")"

# --- IPv6 destination rejections ------------------------------------------
for u in "http://[::1]/" "http://[::]/" "http://[fc00::1]/" \
         "http://[fd12:3456::1]/" "http://[fe80::1]/" "http://[ff02::1]/" \
         "http://[::ffff:127.0.0.1]/" "http://[::ffff:169.254.169.254]/" \
         "http://[64:ff9b::7f00:1]/" "http://[2001:db8::1]/" \
         "http://[0:0:0:0:0:0:0:1]/"; do
  expect_exit "v6 reject $u" 1 "$(block "$u")"
done

# --- public destinations allowed ------------------------------------------
expect_exit "public literal v4" 0 "$(allow "https://93.184.216.34/")"
expect_exit "public literal v4 odd port" 0 "$(allow "http://93.184.216.34:8080/")"
expect_exit "public literal v6 hetzner" 0 \
  "$(allow "http://[2606:2800:220:1:248:1893:25c8:1946]/")"
expect_exit "public literal v6 google" 0 \
  "$(allow "https://[2001:4860:4860::8888]/")"
if getent ahosts example.com >/dev/null 2>&1; then
  expect_exit "public hostname resolves+allowed" 0 "$(allow "https://example.com/")"
  expect_exit "public hostname (HN)" 0 "$(allow "https://news.ycombinator.com/img/y18.svg")"
else
  echo "SKIP: hostname cases (no DNS)"
fi

# --- redirect joining -----------------------------------------------------
j() { bash "$guard" join "$1" "$2" 2>/dev/null; }
expect_eq "join absolute" "https://x.y/z" "$(j "https://a.b/c/d" "https://x.y/z")"
expect_eq "join protocol-relative" "https://x.y/z" "$(j "https://a.b/c/d" "//x.y/z")"
expect_eq "join http base" "http://x.y/z" "$(j "http://a.b/c/d" "http://x.y/z")"
expect_eq "join root-relative" "https://a.b/z" "$(j "https://a.b/c/d" "/z")"
expect_eq "join path-relative" "https://a.b/c/img/p.png" "$(j "https://a.b/c/d" "img/p.png")"
expect_eq "join no-dir base" "https://a.b/p.png" "$(j "https://a.b/img" "p.png")"
expect_eq "join trims spaces" "https://x.y/z" "$(j "https://a.b/c" " https://x.y/z ")"
expect_exit "join missing location" 2 "$(bash "$guard" join "https://a.b/c" "" >/dev/null 2>&1; echo $?)"

# --- e2e: the image fetcher silently drops blocked urls -------------------
sb=$(mktemp -d)
trap 'rm -rf "$sb"' EXIT
rc=$(XDG_STATE_HOME="$sb" bash ./fetch-feeds.sh --fetch-images \
      "item0=http://127.0.0.1:9/evil" "item1=file:///etc/passwd" \
      "item2=http://169.254.169.254/x" "item3=http://[::1]/x" >/dev/null 2>&1; echo $?)
expect_eq "fetch-images blocked exit" "0" "$rc"
expect_eq "fetch-images wrote nothing" "0" \
  "$(find "$sb/omarchy-cmdcenter/news-img" -name '*.img' 2>/dev/null | wc -l | tr -d ' ')"

# --- fetch-art destination contract ---------------------------------------
expect_exit "art private dest ->4" 4 "$(bash ./fetch-art.sh "http://192.168.88.1/x" >/dev/null 2>&1; echo $?)"
expect_exit "art loopback ->4" 4 "$(bash ./fetch-art.sh "http://127.0.0.1:80/art" >/dev/null 2>&1; echo $?)"
expect_exit "art file scheme ->4" 4 "$(bash ./fetch-art.sh "file:///tmp/a.png" >/dev/null 2>&1; echo $?)"

# --- add-feed: scheme gate (user-entered URLs must be web URLs) -----------
for u in "file:///etc/passwd" "ftp://example.com/rss" "gopher://x/1" \
         "dict://localhost:2628/d:test" "data:text/xml,<x/>"; do
  expect_exit "add-feed scheme reject $u" 4 "$(bash ./add-feed.sh "$u" >/dev/null 2>&1; echo $?)"
done

# --- player-icon: identity must not walk out of the .desktop dirs ---------
expect_exit "player-icon slash reject" 4 \
  "$(bash ./player-icon.sh "../../evil.desktop" >/dev/null 2>&1; echo $?)"
expect_exit "player-icon traversal reject" 4 \
  "$(bash ./player-icon.sh "../evil" >/dev/null 2>&1; echo $?)"

# --- wiring canaries (the security plumbing must stay connected) ----------
expect_eq "add-feed pins curl protocols" "2" \
  "$(grep -c -- "--proto '=http,https'" add-feed.sh)"
expect_eq "fetch-feeds pins feed curl protocols" "1" \
  "$(grep -c -- "--proto '=http,https'" fetch-feeds.sh)"
expect_eq "fetch-feeds routes images via guard" "2" \
  "$(grep -c "netguard_fetch" fetch-feeds.sh)"
expect_eq "fetch-art routes downloads via guard" "1" \
  "$(grep -c "netguard_fetch" fetch-art.sh)"
expect_eq "add-feed guards declared hrefs" "1" \
  "$(grep -c "netguard_check_url" add-feed.sh)"
expect_eq "Palette gates openUrlExternally" "2" \
  "$(grep -c "Controls.isWebUrl" Palette.qml)"
expect_eq "Controls exports isWebUrl" "1" \
  "$(grep -c "function isWebUrl" Controls.js)"
expect_eq "win-ctl eval arg stays address-shaped" "1" \
  "$(grep -c '0x\[0-9a-fA-F\]' win-ctl.sh)"

# --- add-feed: content-declared href gets the destination guard -----------
if command -v python3 >/dev/null 2>&1; then
  sbwww="$sb/www"; mkdir -p "$sbwww"
  cat > "$sbwww/index.html" <<'HTML'
<html><head><link rel="alternate" type="application/rss+xml" href="http://169.254.169.254/steal"></head><body>page</body></html>
HTML
  port=$((18000 + RANDOM % 7000))
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$sbwww" \
    >/dev/null 2>&1 &
  srv=$!
  up=0
  for _ in $(seq 1 30); do
    curl -fs --max-time 1 "http://127.0.0.1:$port/index.html" >/dev/null 2>&1 \
      && { up=1; break; }
    sleep 0.2
  done
  if [ "$up" = 1 ]; then
    rc=$(XDG_STATE_HOME="$sb/af1" bash ./add-feed.sh "http://127.0.0.1:$port/index.html" >/dev/null 2>&1; echo $?)
    expect_eq "add-feed declared private href rejected" "4" "$rc"
    expect_eq "add-feed wrote no entry for rejected href" "0" \
      "$(jq '.feeds | length' "$sb/af1/omarchy-cmdcenter/feeds.json" 2>/dev/null || echo 0)"
    # A relative declared href stays on the host the USER chose → allowed.
    cat > "$sbwww/index.html" <<'HTML'
<html><head><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head><body>page</body></html>
HTML
    cat > "$sbwww/feed.xml" <<'XML'
<?xml version="1.0"?><rss version="2.0"><channel><title>Local Zine</title></channel></rss>
XML
    out=$(XDG_STATE_HOME="$sb/af2" bash ./add-feed.sh "http://127.0.0.1:$port/index.html" 2>/dev/null)
    expect_eq "add-feed relative href added" "Local Zine" "$out"
    expect_eq "add-feed feeds count" "1" \
      "$(jq '.feeds | length' "$sb/af2/omarchy-cmdcenter/feeds.json" 2>/dev/null || echo 0)"
  else
    echo "SKIP: add-feed discovery cases (server did not start)"
  fi
  kill "$srv" 2>/dev/null || true
  wait "$srv" 2>/dev/null || true
else
  echo "SKIP: add-feed discovery cases (no python3)"
fi

# --- live: netguard_fetch follows a real redirect chain (skippable) -------
if getent ahosts example.com >/dev/null 2>&1 \
   && curl -fsI --max-time 6 http://example.com >/dev/null 2>&1; then
  livetmp=$(mktemp -u /tmp/guard-live.XXXXXX)
  rc=$(bash -c ". ./fetch-guard.sh; netguard_fetch 'http://example.com' '$livetmp' 4194304 >/dev/null 2>&1; echo \$?")
  expect_eq "live fetch exit" "0" "$rc"
  if [ -s "$livetmp" ]; then passed=$((passed + 1)); else
    failed=$((failed + 1)); echo "FAIL live fetch wrote no body" >&2
  fi
  rm -f "$livetmp"
else
  echo "SKIP: live fetch case (no network)"
fi

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
