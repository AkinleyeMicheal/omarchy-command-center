#!/usr/bin/env bash
# fetch-guard.sh — destination policy for content-supplied URLs (8.10
# the marketplace's SSRF review point; 8.11 hardened it further after a
# follow-up review caught hex-form IPv4 embeddings). Content arriving
# FROM the network (a page's declared feed link, MPRIS album art, a
# feed server's redirect hops) may only cause requests to publicly
# routable addresses: every URL is scheme-checked, resolved, and
# validated against the address policy below; redirects are followed
# manually with the same validation repeated at each hop, and the
# validated addresses are pinned into curl with --resolve so a DNS
# rebind between the check and the connect cannot win.
#
# NOTE: the News group itself never fetches feed-supplied images at all
# (rows/cards show feed initials) — the remaining callers are album art
# (netguard_fetch, strict), a page's declared feed href
# (netguard_check_url), and the user's own feed URLs and their redirect
# hops (netguard_fetch_user: seed honored, hops public or same-host).
#
# Trust boundary: URLs the USER enters (feed URLs in feeds.json) are the
# user's own intent and are honored as-is by the feed fetcher; only URLs
# supplied by feed CONTENT pass through this guard.
#
# Standalone use (tests / debugging):
#   bash fetch-guard.sh check <url>   exit 0 allowed · 1 blocked · 2 usage
#   bash fetch-guard.sh fetch|fetch-user <url> <out> [maxbytes]
#   bash fetch-guard.sh join <base> <location>   print redirect resolution
set -u

NETGUARD_REASON=""
NETGUARD_SCHEME=""
NETGUARD_HOST=""
NETGUARD_PORT=""
NETGUARD_V6=""
NETGUARD_PARTS_OK=""
NETGUARD_ADDRS=()

# --- address policy ------------------------------------------------------
# Publicly routable IPv4? 0 = allowed, 1 = blocked.
netguard_v4_ok() {
  local ip=$1 a b c d g
  [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  # Strict decimal octets: a leading zero is octal to some parsers and
  # decimal to others (0177.0.0.1) — never accept an ambiguous address.
  local o1=${BASH_REMATCH[1]} o2=${BASH_REMATCH[2]}
  local o3=${BASH_REMATCH[3]} o4=${BASH_REMATCH[4]}
  for g in "$o1" "$o2" "$o3" "$o4"; do
    [[ $g =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
  done
  a=$((10#$o1)); b=$((10#$o2)); c=$((10#$o3)); d=$((10#$o4))
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
  (( a == 0 || a == 10 || a == 127 )) && return 1          # 0/8, 10/8, 127/8
  (( a == 169 && b == 254 )) && return 1                   # link-local / metadata
  (( a == 172 && b >= 16 && b <= 31 )) && return 1         # 172.16/12
  (( a == 192 && b == 168 )) && return 1                   # 192.168/16
  (( a == 192 && b == 0 && c == 0 )) && return 1           # IETF protocol assignments
  (( a == 192 && b == 0 && c == 2 )) && return 1           # TEST-NET-1
  (( a == 198 && b == 51 && c == 100 )) && return 1        # TEST-NET-2
  (( a == 203 && b == 0 && c == 113 )) && return 1         # TEST-NET-3
  (( a == 198 && (b == 18 || b == 19) )) && return 1       # benchmark 198.18/15
  (( a == 100 && b >= 64 && b <= 127 )) && return 1        # CGNAT 100.64/10
  (( a >= 224 )) && return 1                               # multicast / reserved / broadcast
  return 0
}

# Publicly routable IPv6? 0 = allowed, 1 = blocked. Handles :: expansion
# and rejects EVERY IPv4-embedding form — dotted (::ffff:127.0.0.1),
# hex v4-mapped (::ffff:7f00:1), v4-compatible (::7f00:1), NAT64
# (64:ff9b::/96 and 64:ff9b:1::/48), 6to4 (2002::/16) and Teredo
# (2001:0::/32). An embedded v4 makes the connection land on (or get
# relayed to) that v4 address, so an embedding is never a public v6
# destination — public or private, rejected outright rather than
# evaluated (the marketplace review caught hex-form embeddings slipping
# through per-value evaluation). Plus ULA/link-local/site-local/
# multicast/documentation prefixes.
netguard_v6_ok() {
  local ip=${1,,} l r x
  ip=${ip%%\%*}                                            # strip %zone
  [[ $ip == *:* ]] || return 1
  # Any dotted-quad inside a v6 literal is an embedded IPv4 (mapped or
  # compatible spelling) — reject outright, whatever the embedded value.
  [[ $ip != *.* ]] || return 1
  [[ $ip != *::*::* ]] || return 1                         # at most one '::'
  local -a h=() L=() R=()
  if [[ $ip == *::* ]]; then
    l=${ip%%::*}; r=${ip#*::}
    [[ -z $l ]] || IFS=: read -ra L <<< "$l"
    [[ -z $r ]] || IFS=: read -ra R <<< "$r"
    local pad=$(( 8 - ${#L[@]} - ${#R[@]} ))
    (( pad >= 0 )) || return 1
    h=("${L[@]+"${L[@]}"}")
    local k
    for ((k = 0; k < pad; k++)); do h+=(0); done
    h+=("${R[@]+"${R[@]}"}")
  else
    IFS=: read -ra h <<< "$ip"
    (( ${#h[@]} == 8 )) || return 1
  fi
  local -a n=()
  for x in "${h[@]}"; do
    [[ $x =~ ^[0-9a-f]{1,4}$ ]] || return 1
    n+=( $((16#$x)) )
  done
  local allzero=1 i
  for ((i = 0; i < 8; i++)); do (( n[i] == 0 )) || allzero=0; done
  (( allzero )) && return 1                                # ::
  local loop=1
  for ((i = 0; i < 7; i++)); do (( n[i] == 0 )) || loop=0; done
  (( loop && n[7] == 1 )) && return 1                      # ::1
  # --- IPv4-embedding forms (checked on the EXPANDED hextets, so hex,
  # compressed and full spellings all land here): never public.
  (( (n[0] | n[1] | n[2] | n[3] | n[4]) == 0 && n[5] == 16#ffff )) \
    && return 1                                            # ::ffff:0:0/96 mapped
  (( (n[0] | n[1] | n[2] | n[3] | n[4] | n[5]) == 0 )) \
    && return 1                                            # ::/96 v4-compatible
  (( n[0] == 16#64 && n[1] == 16#ff9b )) && return 1       # NAT64 64:ff9b::/96,
  #                                                     64:ff9b:1::/48 (RFC 8215)
  (( n[0] == 16#2002 )) && return 1                        # 6to4 2002::/16
  (( n[0] == 16#2001 && n[1] == 0 )) && return 1           # Teredo 2001:0::/32
  # --- non-embeddable blocked prefixes -----------------------------------
  (( (n[0] & 16#fe00) == 16#fc00 )) && return 1            # fc00::/7 ULA
  (( (n[0] & 16#ffc0) == 16#fe80 )) && return 1            # fe80::/10 link-local
  (( (n[0] & 16#ffe0) == 16#fec0 )) && return 1            # fec0::/10 site-local
  (( (n[0] & 16#ff00) == 16#ff00 )) && return 1            # ff00::/8 multicast
  (( n[0] == 16#2001 && n[1] == 16#0db8 )) && return 1      # 2001:db8::/32 documentation
  return 0
}

netguard_addr_ok() {
  case "$1" in
    *:*) netguard_v6_ok "$1" ;;
    *)   netguard_v4_ok "$1" ;;
  esac
}

# --- URL parsing ---------------------------------------------------------
# Scheme http/https only; authority without userinfo; bracketed v6 or
# host:port with a sane port. Sets NETGUARD_SCHEME/HOST/PORT/V6.
netguard_url_parts() {
  local url=$1 rest
  NETGUARD_SCHEME=""; NETGUARD_HOST=""; NETGUARD_PORT=""; NETGUARD_V6=""
  NETGUARD_PARTS_OK=""
  NETGUARD_REASON="url rejected"
  # Raw control characters (CR/LF/TAB and friends) never belong in a
  # URL — they are header- and parser-smuggling material.
  [[ ! $url =~ [^[:print:]] ]] \
    || { NETGUARD_REASON="control characters in url"; return 1; }
  # Raw double quotes and backslashes are invalid in a URL (RFC 3986)
  # and, since 8.14, the only characters that could break out of the
  # quoted curl-config line the URL now rides on stdin and inject curl
  # options (output=… and friends). Percent-encoded forms (%22, %5C)
  # stay accepted. Both fetch modes funnel through this function, so
  # seed, redirect hop and art URLs all get the check.
  [[ ! $url =~ [\"\\] ]] \
    || { NETGUARD_REASON="quote or backslash in url"; return 1; }
  [[ $url =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]] || { NETGUARD_REASON="not an http(s) url"; return 1; }
  NETGUARD_SCHEME=${BASH_REMATCH[0]%://}
  NETGUARD_SCHEME=${NETGUARD_SCHEME,,}
  rest=${url#*://}
  rest=${rest%%[\?#]*}
  rest=${rest%%/*}
  [[ -n $rest ]] || { NETGUARD_REASON="empty host"; return 1; }
  [[ $rest != *@* ]] || { NETGUARD_REASON="userinfo rejected"; return 1; }
  if [[ $rest == \[* ]]; then
    [[ $rest == *\]* ]] || { NETGUARD_REASON="bad ipv6 authority"; return 1; }
    NETGUARD_V6=1
    NETGUARD_HOST=${rest#\[}; NETGUARD_HOST=${NETGUARD_HOST%%\]*}
    # Brackets mean IPv6 literal — a v4 address or a name inside
    # brackets is parser-differential bait; reject it here.
    [[ $NETGUARD_HOST == *:* ]] || { NETGUARD_REASON="bad ipv6 authority"; return 1; }
    local tail=${rest#*\]}
    if [[ -n $tail ]]; then
      [[ $tail == :* && ${tail#:} =~ ^[0-9]{1,5}$ ]] || { NETGUARD_REASON="bad port"; return 1; }
      NETGUARD_PORT=${tail#:}
    fi
  else
    local colons=${rest//[^:]/}
    (( ${#colons} <= 1 )) || { NETGUARD_REASON="unbracketed ipv6"; return 1; }
    if [[ $rest == *:* ]]; then
      NETGUARD_HOST=${rest%%:*}
      NETGUARD_PORT=${rest##*:}
      [[ $NETGUARD_PORT =~ ^[0-9]{1,5}$ ]] || { NETGUARD_REASON="bad port"; return 1; }
    else
      NETGUARD_HOST=$rest
    fi
  fi
  [[ -n $NETGUARD_HOST ]] || { NETGUARD_REASON="empty host"; return 1; }
  if [[ -n $NETGUARD_PORT ]]; then
    # Decimal, not octal: (( 0080 )) parses base-8 and errors out with
    # a stray stderr line (the URL still fails closed, but confusingly).
    NETGUARD_PORT=$((10#$NETGUARD_PORT))
    (( NETGUARD_PORT >= 1 && NETGUARD_PORT <= 65535 )) || { NETGUARD_REASON="bad port"; return 1; }
  else
    NETGUARD_PORT=80; [[ $NETGUARD_SCHEME == https ]] && NETGUARD_PORT=443
  fi
  NETGUARD_PARTS_OK=1
  return 0
}

# Full policy check: parts → resolve → every address public. On success
# NETGUARD_ADDRS holds the validated addresses (for --resolve pinning).
netguard_check_url() {
  local url=$1 addr
  NETGUARD_ADDRS=()
  netguard_url_parts "$url" || return 1
  if [[ -n $NETGUARD_V6 || $NETGUARD_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Literal address in the URL: policy applies directly (no DNS).
    netguard_addr_ok "$NETGUARD_HOST" || { NETGUARD_REASON="address not public: $NETGUARD_HOST"; return 1; }
    NETGUARD_ADDRS=("$NETGUARD_HOST")
    return 0
  fi
  # Hostname: resolve here, pin into curl later. Fail closed on anything
  # unresolvable or non-standard (IDN without punycode, shorthand IPv4
  # obfuscations like 2130706433 / 127.1 never reach curl).
  local addrs
  addrs=$(getent ahosts "$NETGUARD_HOST" 2>/dev/null | awk '{print $1}' | sort -u)
  if [[ -z $addrs ]]; then
    NETGUARD_REASON="unresolvable host"
    return 1
  fi
  while IFS= read -r addr; do
    [[ -n $addr ]] || continue
    if ! netguard_addr_ok "$addr"; then
      NETGUARD_REASON="address not public: $addr"
      return 1
    fi
    NETGUARD_ADDRS+=("$addr")
  done <<< "$addrs"
  (( ${#NETGUARD_ADDRS[@]} > 0 )) || { NETGUARD_REASON="unresolvable host"; return 1; }
  return 0
}

# Redirect target resolution (RFC 3986 subset): absolute, protocol-
# relative, root-relative, path-relative. Policy is re-applied by the
# caller's per-hop netguard_check_url — this only joins text.
netguard_join_url() {
  local base=$1 loc=$2 scheme authority path
  loc=$(printf '%s' "$loc" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [[ -n $loc ]] || return 1
  [[ $loc != *$'\n'* ]] || return 1
  case "$loc" in
    [Hh][Tt][Tt][Pp][Ss]://* | [Hh][Tt][Tt][Pp]://*) printf '%s\n' "$loc"; return 0 ;;
    //* ) scheme=${base%%://*}; printf '%s:%s\n' "$scheme" "$loc"; return 0 ;;
  esac
  scheme=${base%%://*}
  authority=${base#*://}; authority=${authority%%/*}
  case "$loc" in
    /*) printf '%s://%s%s\n' "$scheme" "$authority" "$loc" ;;
    *)
      path=${base#*://}; path=${path#*/}
      path=${path%%[\?#]*}
      if [[ $path == */* ]]; then
        printf '%s://%s/%s/%s\n' "$scheme" "$authority" "${path%/*}" "$loc"
      else
        printf '%s://%s/%s\n' "$scheme" "$authority" "$loc"
      fi ;;
  esac
  return 0
}

# --- validated fetch -----------------------------------------------------
# netguard_fetch <url> <outfile> <maxbytes> [ua]
# Strict mode: EVERY hop (the seed included) must pass the full public
# policy. For URLs that come FROM content (album art, declared feed
# links). Writes the body to outfile on success; removes outfile and
# returns 1 on any failure (including blocked destinations).
netguard_fetch() {
  netguard_fetch_impl public "$@"
}

# netguard_fetch_user <url> <outfile> <maxbytes> [ua]
# User-seed mode: the seed URL is the user's own choice (LAN/homelab
# feeds included) — validated for scheme/userinfo/port only, never for
# its address. Every redirect BEYOND it is server-chosen, i.e. content:
# it must pass the full public policy, or return to the very host the
# user pasted (same-host port/path redirects a local feed service makes
# are still the user's own intent).
netguard_fetch_user() {
  netguard_fetch_impl user "$@"
}

netguard_fetch_impl() {
  local mode=$1 url=$2 out=$3 maxbytes=${4:-4194304} ua=${5:-"omarchy-cmdcenter/1.0 (RSS reader)"}
  [[ -n $url && -n $out ]] || return 1
  local maxhops=5 hop cur=$url code rc hdr loc ip seedhost=""
  local -a resolve=()
  hdr=$(mktemp) || return 1
  for ((hop = 0; hop <= maxhops; hop++)); do
    if [[ $mode == user && $hop == 0 ]]; then
      netguard_url_parts "$cur" || { rm -f "$hdr" "$out"; return 1; }
      seedhost=${NETGUARD_HOST,,}
      NETGUARD_ADDRS=()
    elif ! netguard_check_url "$cur"; then
      if [[ $mode == user && -n $seedhost && ${NETGUARD_PARTS_OK:-} == 1
            && ${NETGUARD_HOST,,} == "$seedhost" ]]; then
        NETGUARD_ADDRS=()          # the user's own host: curl resolves it
      else
        rm -f "$hdr" "$out"; return 1
      fi
    fi
    resolve=()
    if [[ -z ${NETGUARD_V6:-} && ! $NETGUARD_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      # Pin only what we will dial: curl prefers a pinned IPv6 address
      # (happy-eyeballs) and gives up entirely when it is unroutable
      # from this host (no default v6 route → immediate failure, no v4
      # fallback), so v4 pins win whenever any validated v4 exists;
      # v6-only hosts pin v6. --resolve replaces DNS outright, so the
      # dialed address is always one this function validated.
      local -a v4s=() v6s=() use=()
      for ip in "${NETGUARD_ADDRS[@]}"; do
        if [[ $ip == *:* ]]; then v6s+=( "$ip" ); else v4s+=( "$ip" ); fi
      done
      if ((${#v4s[@]})); then use=("${v4s[@]}"); else use=("${v6s[@]}"); fi
      for ip in "${use[@]}"; do
        if [[ $ip == *:* ]]; then resolve+=( --resolve "$NETGUARD_HOST:$NETGUARD_PORT:[$ip]" )
        else resolve+=( --resolve "$NETGUARD_HOST:$NETGUARD_PORT:$ip" ); fi
      done
    fi
    : > "$hdr"
    rc=0
    # The URL — feed tokens included — rides a one-line config on stdin,
    # never argv: /proc/<pid>/cmdline is world-readable (8.14 review).
    # netguard_url_parts guarantees $cur holds no quote/backslash, so
    # the quoted config value cannot be broken out of; only non-sensitive
    # dial data (--resolve host:port:ip of already-validated public
    # addresses) stays in argv.
    code=$(printf 'url = "%s"\n' "$cur" \
      | curl --proto '=http,https' --proto-redir '=http,https' \
        --max-time 8 --max-filesize "$maxbytes" \
        -A "$ua" "${resolve[@]+"${resolve[@]}"}" \
        -D "$hdr" -o "$out" -w '%{http_code}' -K - 2>/dev/null) || rc=$?
    if (( rc != 0 )); then rm -f "$hdr" "$out"; return 1; fi
    case "$code" in
      200)
        rm -f "$hdr"
        [[ -s $out ]] || { rm -f "$out"; return 1; }
        return 0 ;;
      301 | 302 | 303 | 307 | 308)
        loc=$(tr -d '\r' < "$hdr" | sed -nE 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[ \t]*(.*)$/\1/p' | tail -1)
        if [[ -z $loc ]] || ! cur=$(netguard_join_url "$cur" "$loc"); then
          rm -f "$hdr" "$out"; return 1
        fi ;;
      *)
        rm -f "$hdr" "$out"; return 1 ;;
    esac
  done
  rm -f "$hdr" "$out"                             # too many redirects
  return 1
}

# --- CLI (tests / debugging) --------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    check)
      if [[ -z ${2:-} ]]; then echo "usage: fetch-guard.sh check <url>" >&2; exit 2; fi
      if netguard_check_url "$2"; then echo "allowed: $2"; exit 0; fi
      echo "blocked: $2 (${NETGUARD_REASON})" >&2
      exit 1 ;;
    fetch | fetch-user)
      if [[ -z ${2:-} || -z ${3:-} ]]; then
        echo "usage: fetch-guard.sh $1 <url> <outfile> [maxbytes]" >&2; exit 2; fi
      if [[ $1 == fetch ]]; then
        netguard_fetch "$2" "$3" "${4:-4194304}"
      else
        netguard_fetch_user "$2" "$3" "${4:-4194304}"
      fi
      exit $? ;;
    join)
      [[ -n ${2:-} && -n ${3:-} ]] || { echo "usage: fetch-guard.sh join <base> <location>" >&2; exit 2; }
      netguard_join_url "$2" "$3" || exit 1 ;;
    *)
      echo "usage: fetch-guard.sh check <url> | fetch|fetch-user <url> <out> [max] | join <base> <location>" >&2
      exit 2 ;;
  esac
fi
