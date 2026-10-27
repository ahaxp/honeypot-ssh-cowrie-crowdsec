#!/bin/bash
set -uo pipefail

LOGFILE="${1:-cowrie/log/cowrie.json}"
OUTDIR="${2:-collected}"

mkdir -p "$OUTDIR"

echo "Wyciąganie listy IP z największą liczbą nieudanych prób logowania:"
jq -s '[.[] | select(.eventid=="cowrie.login.failed")]
  | group_by(.src_ip)
  | map({ip: .[0].src_ip, attempts: length})
  | sort_by(-.attempts)' "$LOGFILE" > "$OUTDIR/top_ips.json"

echo "Wyciągnięcie wszystkich wpisanych komend:"
jq -c 'select(.eventid=="cowrie.command.input") | {ip: .src_ip, command: .input}' \
  "$LOGFILE" > "$OUTDIR/commands.jsonl"

echo "Wyciągnięcie wszystkich prób pobrania plików:"
jq -c 'select(.eventid=="cowrie.session.file_download")' \
  "$LOGFILE" > "$OUTDIR/downloads.jsonl" 2>/dev/null || true

echo "Generowanie ogólnego podsumowania statystyk:"
jq -s '{
  total_failed: [.[] | select(.eventid=="cowrie.login.failed")] | length,
  total_success: [.[] | select(.eventid=="cowrie.login.success")] | length,
  unique_ips: [.[] | select(.eventid=="cowrie.login.failed") | .src_ip] | unique | length
}' "$LOGFILE" > "$OUTDIR/summary.json"

echo "Ranking najczęściej używanych loginów:"
jq -s '[.[] | select(.eventid=="cowrie.login.failed") | .username] 
  | group_by(.) 
  | map({user: .[0], count: length}) 
  | sort_by(-.count)' "$LOGFILE" > "$OUTDIR/top_users.json"

echo "Ranking najczęściej używanych haseł:"
jq -s '[.[] | select(.eventid=="cowrie.login.failed") | .password] 
  | group_by(.) 
  | map({password: .[0], count: length}) 
  | sort_by(-.count)' "$LOGFILE" > "$OUTDIR/top_passwords.json"

echo "Wyciągnięcie wszystkich prób połączeń SSH:"
jq -c 'select(.eventid=="cowrie.session.connect") | {ip: .src_ip, time: .timestamp}' \
  "$LOGFILE" > "$OUTDIR/connections.jsonl" 2>/dev/null || true

echo "Gotowe! Wszystkie pliki zapisane w folderze: $OUTDIR"