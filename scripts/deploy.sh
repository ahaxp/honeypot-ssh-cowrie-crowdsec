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