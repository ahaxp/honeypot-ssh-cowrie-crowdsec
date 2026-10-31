#!/bin/bash
set -uo pipefail

IPLIST="${1:-collected/top_ips.json}"
API_KEY="${ABUSEIPDB_API_KEY:-}"

if [ -z "$API_KEY" ]; then
    echo "[!] Błąd: Zmienna ABUSEIPDB_API_KEY jest pusta. Uruchom: source .env"
    exit 1
fi

if jq -e . "$IPLIST" >/dev/null 2>&1; then
    IP_DATA=$(jq -r '.[].ip' "$IPLIST")
else
    IP_DATA=$(cat "$IPLIST")
fi

while read -r ip || [ -n "$ip" ]; do
    [ -z "$ip" ] && continue

    curl -s -m 10 -G https://api.abuseipdb.com/api/v2/check \
        --data-urlencode "ipAddress=$ip" \
        -d maxAgeInDays=90 \
        -H "Key: $API_KEY" \
        -H "Accept: application/json" \
    | jq -c --arg ip "$ip" '{ip: $ip, country: (.data.countryCode // "?"), score: .data.abuseConfidenceScore}'

    sleep 1
done <<< "$IP_DATA"