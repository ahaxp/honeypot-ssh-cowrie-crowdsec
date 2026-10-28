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