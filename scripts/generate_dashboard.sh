#!/bin/bash

set -uo pipefail

INDIR="${1:-collected}"
OUTDIR="${2:-site}"
IPS="$INDIR/top_ips.json"
OUT="$OUTDIR/index.html"
mkdir -p "$OUTDIR"

# //AI
[ -s "$IPS" ] || { echo "Brak danych do wygenerowania dashboardu. Upewnij się, że skrypt collect_logs.sh został uruchomiony i wygenerował plik top_ips.json."; exit 1; }

MAX=$(jq '[.[].attempts] | max // 1' "$IPS")
TOTAL=$(jq '[.[].attempts] | add // 0' "$IPS")
UNIQ=$(jq 'length' "$IPS")
NOW=$(date -u '+%Y-%m-%d %H:%M UTC')

ROWS=$(jq -r '.[:10][] | "<tr><td>\(.ip | @html)</td><td>\(.attempts)</td></tr>"' "$IPS")
BARS=$(jq -r --argjson max "$MAX" '.[:10] | to_entries[] |
  "<text x=\"5\" y=\"\(.key * 30 + 15)\" font-size=\"12\" fill=\"#ccc\">\(.value.ip | @html) (\(.value.attempts))</text>" +
  "<rect x=\"170\" y=\"\(.key * 30)\" width=\"\(.value.attempts * 200 / $max | floor | if . < 2 then 2 else . end)\" height=\"20\" fill=\"#c23b3b\"/>"' "$IPS")
# //AI

cat > "$OUT" <<HTML
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Honeypot Dashboard</title>
<style>
  body { background: #0a0a0a; color: #ededed; font-family: monospace; padding: 20px; }
  table { border-collapse: collapse; width: 100%; max-width: 600px; margin-bottom: 30px; }
  th, td { border: 1px solid #333; padding: 8px; text-align: left; }
  th { background: #111; color: #ff3b30; }
  svg { background: #111; border: 1px solid #333; }
</style>
</head>
<body>
<h1>Top atakujące IP</h1>
<p>Prób: $TOTAL, unikalnych IP: $UNIQ, wygenerowano: $NOW</p>
<table>
  <tr><th>IP</th><th>Próby</th></tr>
  $ROWS
</table>
<h2>Wykres</h2>
<svg viewBox="0 0 400 300" width="100%" style="max-width: 600px;">
  $BARS
</svg>
</body>
</html>
HTML
echo "[OK] Zapisano $OUT"