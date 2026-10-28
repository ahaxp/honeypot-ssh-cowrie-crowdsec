#!/bin/bash

set -uo pipefail

INDIR="${1:-collected}"
OUTDIR="${2:-site}"
IPS="$INDIR/top_ips.json"
OUT="$OUTDIR/index.html"
mkdir -p "$OUTDIR"

//AI
[ -s "$IPS" ] || { echo "Brak danych do wygenerowania dashboardu. Upewnij się, że skrypt collect_logs.sh został uruchomiony i wygenerował plik top_ips.json."; exit 1; }

MAX=$(jq '[.[].attempts] | max // 1' "$IPS")
TOTAL=$(jq '[.[].attempts] | add // 0' "$IPS")
UNIQ=$(jq 'length' "$IPS")
NOW=$(date -u '+%Y-%m-%d %H:%M UTC')

ROWS=$(jq -r '.[:10][] | "<tr><td>\(.ip | @html)</td><td>\(.attempts)</td></tr>"' "$IPS")
BARS=$(jq -r --argjson max "$MAX" '.[:10] | to_entries[] |
  "<text x=\"5\" y=\"\(.key * 30 + 15)\" font-size=\"12\" fill=\"#ccc\">\(.value.ip | @html) (\(.value.attempts))</text>" +
  "<rect x=\"170\" y=\"\(.key * 30)\" width=\"\(.value.attempts * 200 / $max | floor | if . < 2 then 2 else . end)\" height=\"20\" fill=\"#c23b3b\"/>"' "$IPS")
//AI