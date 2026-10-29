#!/bin/bash
set -uo pipefail
TIMEOUT="${TIMEOUT:-90}"

wait_for_file() {
    local name="$1"; shift
    local start=$SECONDS
    echo "Oczekiwanie na plik: $name"
    until "$@" >/dev/null 2>&1; do
        if (( SECONDS - start > TIMEOUT )); then
            echo "Timeout: plik $name nie został znaleziony w ciągu $TIMEOUT sekund."
            return 1
        fi
        sleep 1
    done
    echo "Plik $name został znaleziony."
}

cowrie_ready() {
    timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222 && head -c 3 <&3' 2>/dev/null | grep -q '^SSH'
}

lapi_ready() {
    curl -sf http://localhost:8081/health;
}

echo "Uruchamianie kontenerów Docker"
docker compose up -d --build || { echo "Błąd podczas uruchamiania kontenerów Docker"; exit 1; }

wait_for_file "Cowrie SSH" cowrie_ready || { echo "Cowrie SSH nie jest gotowy"; exit 1; }
wait_for_file "LAPI" lapi_ready || { echo "LAPI nie jest gotowy"; exit 1; }

echo "Środowisko gotowe. Dashboard: http://localhost:8081"
