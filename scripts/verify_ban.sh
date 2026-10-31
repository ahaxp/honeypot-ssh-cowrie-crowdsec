#!/bin/bash
set -uo pipefail

IP="${1:?Podaj adres IP do sprawdzenia}"

echo "Sprawdzam decyzje w CrowdSec dla IP: $IP"

if docker compose exec -T crowdsec cscli decisions list --ip "$IP" -o json | jq -e 'length > 0' >/dev/null 2>&1; 
then
    echo IP $IP jest zablokowane na liście decyzji CrowdSec.
else
    echo IP $IP nie jest zablokowane na liście decyzji CrowdSec.
    exit 1
fi

echo "Test polaczenia TCP z kontenera attacker do cowrie"
if docker compose exec -T attacker timeout 3 bash -c 'echo > /dev/tcp/cowrie/2222' 2>/dev/null; 
then
    echo "Polaczenie TCP przeszlo - blokada nie dziala bouncer nie odrzuca pakietow"
    exit 1
else
    echo "Polaczenie TCP nie przeszlo - blokada dziala bouncer odrzuca pakiety"
fi