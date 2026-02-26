#!/usr/bin/env bash
# Scan an IP with RealiTLScanner, then verify and classify domains until we have 3
# suitable for VLESS Reality (gaming/entertainment/news/shop). Usage:
#   ./scan-and-classify.sh <IP> [output_csv]
# Requires: RealiTLScanner (env REALITLSCANNER or in PATH), curl

set -e
REQUIRED=3
IP="${1:?Usage: $0 <IP> [output_csv]}"
OUT_CSV="${2:-reality_scan.csv}"
SCANNER="${REALITLSCANNER:-RealiTLScanner}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Keyword patterns (order: gaming → entertainment → news → shop)
GAMING='game|gaming|steam|epic\s*games|gog|origin|xbox|playstation|nintendo|esport|twitch|mmorpg|fps|rpg|multiplayer|gameplay|player'
ENTERTAINMENT='streaming|stream|movie|film|tv|television|music|podcast|netflix|spotify|youtube|disney|hulu|entertainment|series|show|radio|audiobook'
NEWS='news|breaking|headline|reuters|associated\s+press|ap\s+news|bbc|cnn|editorial|journalism|reporter|gazette'
SHOP='shop|store|shopping|retail|buy|purchase|cart|checkout|order|amazon|ebay|marketplace|etsy|sale|deals|discount|price|product|catalog'

classify() {
  local body="$1"
  if echo "$body" | grep -qiE "$GAMING"; then echo "gaming"
  elif echo "$body" | grep -qiE "$ENTERTAINMENT"; then echo "entertainment"
  elif echo "$body" | grep -qiE "$NEWS"; then echo "news"
  elif echo "$body" | grep -qiE "$SHOP"; then echo "shop"
  else echo ""
  fi
}

# 1. Run RealiTLScanner
if ! command -v "$SCANNER" &>/dev/null; then
  echo "Error: RealiTLScanner not found. Set REALITLSCANNER or add it to PATH." >&2
  exit 1
fi
"$SCANNER" -addr "$IP" -port 443 -out "$OUT_CSV" -thread 4 -timeout 10

# 2. Parse unique CERT_DOMAIN (column 3), normalize wildcard
domains=()
while IFS= read -r domain; do
  [ -z "$domain" ] && continue
  domain=$(echo "$domain" | sed 's/^\*\.//')
  [[ "$domain" =~ ^[a-zA-Z0-9] ]] && domains+=("$domain")
done < <(tail -n +2 "$OUT_CSV" 2>/dev/null | awk -F',' '{gsub(/^"|"$/,"",$3); print $3}' | sort -u)

if [ ${#domains[@]} -eq 0 ]; then
  echo "No domains found in $OUT_CSV"
  exit 0
fi

# 3. Verify + classify until we have REQUIRED
found=0
echo "## Reality-capable domains (working + classified)"
echo ""
echo "| # | Domain | Category | Status |"
echo "|---|--------|----------|--------|"

for domain in "${domains[@]}"; do
  [ "$found" -ge "$REQUIRED" ] && break
  code=$(curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${domain}/" 2>/dev/null || echo "000")
  if [[ "$code" != "200" && "$code" != "301" && "$code" != "302" ]]; then
    continue
  fi
  body=$(curl -sL --max-time 8 --max-filesize 51200 "https://${domain}/" 2>/dev/null | head -c 51200)
  category=$(classify "$body")
  [ -z "$category" ] && continue
  found=$((found + 1))
  echo "| $found | $domain | $category | working |"
done

if [ "$found" -eq 0 ]; then
  echo "| — | (none) | — | — |"
fi
echo ""
echo "These domains are suitable as SNI/targets for VLESS Reality from IP $IP."
