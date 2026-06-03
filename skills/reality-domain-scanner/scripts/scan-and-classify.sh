#!/usr/bin/env bash
# Scan an IP with RealiTLScanner, verifying and classifying each domain as it is
# discovered. Stops the scanner and exits as soon as 3 domains suitable for VLESS
# Reality (gaming/entertainment/news/shop) are found. Usage:
#   ./scan-and-classify.sh <IP> [output_csv]
# Requires: RealiTLScanner (env REALITLSCANNER or in PATH), curl
#
# Note: RealiTLScanner runs in infinite-expansion mode for a single -addr, so it
# never terminates on its own. We run it in the background, follow its CSV output
# live, and kill it once REQUIRED matches are collected.

set -e
REQUIRED=3
IP="${1:?Usage: $0 <IP> [output_csv]}"
OUT_CSV="${2:-reality_scan.csv}"
SCANNER="${REALITLSCANNER:-RealiTLScanner}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Keyword patterns (order: gaming → entertainment → news → shop). Word-boundary
# anchored to avoid generic substring hits (e.g. "origin" inside "crossorigin").
GAMING='\b(game|games|gaming|steam|epic games|xbox|playstation|nintendo|esport|esports|twitch|mmorpg|multiplayer|gameplay)\b'
ENTERTAINMENT='\b(streaming|movie|movies|film|music|podcast|netflix|spotify|youtube|disney|hulu|entertainment|radio|audiobook|cinema)\b'
NEWS='\b(news|breaking news|headline|headlines|reuters|bbc|cnn|editorial|journalism|reporter|gazette|nachrichten)\b'
SHOP='\b(shop|store|shopping|retail|buy|purchase|cart|checkout|marketplace|etsy|sale|deals|discount|catalog|webshop)\b'

classify() {
  local body="$1"
  if echo "$body" | grep -qiE "$GAMING"; then echo "gaming"
  elif echo "$body" | grep -qiE "$ENTERTAINMENT"; then echo "entertainment"
  elif echo "$body" | grep -qiE "$NEWS"; then echo "news"
  elif echo "$body" | grep -qiE "$SHOP"; then echo "shop"
  else echo ""
  fi
}

if ! command -v "$SCANNER" &>/dev/null; then
  echo "Error: RealiTLScanner not found. Set REALITLSCANNER or add it to PATH." >&2
  exit 1
fi

# Start fresh so we never read stale rows from a previous run.
: > "$OUT_CSV"

# 1. Launch the scanner in the background.
"$SCANNER" -addr "$IP" -port 443 -out "$OUT_CSV" -thread 4 -timeout 10 &
SCANNER_PID=$!
trap 'kill "$SCANNER_PID" 2>/dev/null' EXIT

# Wait for the CSV to materialize (or the scanner to die early).
while [ ! -s "$OUT_CSV" ]; do
  kill -0 "$SCANNER_PID" 2>/dev/null || break
  sleep 0.3
done

# 2/3. Follow the CSV live; verify + classify each new domain until we have REQUIRED.
found=0
declare -A seen
echo "## Reality-capable domains (working + classified)"
echo ""
echo "| # | Domain | Category | Status |"
echo "|---|--------|----------|--------|"

# tail --pid makes tail exit if the scanner ever stops; process substitution keeps
# the loop in this shell so `found` persists and `break` ends the run.
while IFS= read -r line; do
  case "$line" in IP,ORIGIN*|'') continue;; esac

  domain=$(echo "$line" | awk -F',' '{gsub(/^"|"$/,"",$3); print $3}' | sed 's/^\*\.//')
  [[ "$domain" =~ ^[a-zA-Z0-9] ]] || continue
  [[ "$domain" == *.* ]] || continue
  [[ "$domain" == *" "* ]] && continue
  [[ -n "${seen[$domain]:-}" ]] && continue
  seen[$domain]=1

  code=$(curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${domain}/" 2>/dev/null || echo "000")
  case "$code" in 200|301|302) ;; *) continue;; esac

  body=$(curl -sL --max-time 8 "https://${domain}/" 2>/dev/null | head -c 51200)
  category=$(classify "$body")
  [ -z "$category" ] && continue

  found=$((found + 1))
  echo "| $found | $domain | $category | working |"
  [ "$found" -ge "$REQUIRED" ] && break
done < <(tail -n +1 -f --pid="$SCANNER_PID" "$OUT_CSV" 2>/dev/null)

# 4. Stop the scanner (also covered by the EXIT trap) and report.
kill "$SCANNER_PID" 2>/dev/null || true

if [ "$found" -eq 0 ]; then
  echo "| — | (none) | — | — |"
elif [ "$found" -lt "$REQUIRED" ]; then
  echo ""
  echo "_Scanner ended before $REQUIRED matches; found $found._"
fi
echo ""
echo "These domains are suitable as SNI/targets for VLESS Reality from IP $IP."
