# COMMANDS.md

## Honeypot SSH: Cowrie + CrowdSec — kompletna ściąga komend

Dokument zbiera komendy wykorzystywane podczas realizacji projektu w tygodniach 1–7. Polecenia pogrupowano według obszaru, aby ułatwić uruchamianie, testowanie i diagnozowanie środowiska.

Adresy IP kontenerów Docker są w przykładach zamaskowane jako `172.19.0.X` lub `172.18.0.X`. W rzeczywistych poleceniach należy zastąpić je aktualnym adresem z laboratorium.

**Konwencja:** komentarz `# →` opisuje oczekiwany wynik lub cel polecenia.

---

## Spis treści

1. [Narzędzia i weryfikacja wersji](#1-narzędzia-i-weryfikacja-wersji)
2. [Inicjalizacja repozytorium](#2-inicjalizacja-repozytorium)
3. [Docker Compose — cykl życia środowiska](#3-docker-compose--cykl-życia-środowiska)
4. [Cowrie — logowanie i logi](#4-cowrie--logowanie-i-logi)
5. [CrowdSec — kolekcje, parsery i metryki](#5-crowdsec--kolekcje-parsery-i-metryki)
6. [CrowdSec — decyzje i bany](#6-crowdsec--decyzje-i-bany)
7. [Bouncer — rejestracja i diagnostyka](#7-bouncer--rejestracja-i-diagnostyka)
8. [Attacker — Hydra](#8-attacker--hydra)
9. [Analiza logów — jq](#9-analiza-logów--jq)
10. [Skrypty projektu](#10-skrypty-projektu)
11. [Dashboard i Nginx](#11-dashboard-i-nginx)
12. [System — br_netfilter, iptables i sysctl](#12-system--br_netfilter-iptables-i-sysctl)
13. [Uprawnienia i pliki](#13-uprawnienia-i-pliki)
14. [Git — typowe operacje](#14-git--typowe-operacje)
15. [Pełny test środowiska](#15-pełny-test-środowiska)

---

## 1. Narzędzia i weryfikacja wersji

Sprawdzenie dostępności podstawowych narzędzi:

```bash
docker --version
docker compose version
git --version
jq --version
```

Sprawdzenie Hydry wewnątrz kontenera `attacker`:

```bash
docker compose exec attacker hydra -h
```

Sprawdzenie, czy port 2222 jest wolny:

```bash
ss -ltn | grep ':2222 ' || echo "port 2222 wolny"
```

Sprawdzenie portów LAPI i Nginx:

```bash
ss -ltn | grep -E ':(8080|8081) '
```

---

## 2. Inicjalizacja repozytorium

Utworzenie katalogu projektu:

```bash
mkdir honeypot-cowrie-crowdsec
cd honeypot-cowrie-crowdsec

mkdir cowrie crowdsec nginx attacker scripts docs
touch README.md .gitignore

git init
git add .
git commit -m "init: struktura projektu"
```

Dodanie plików `.gitkeep`, aby Git śledził puste katalogi:

```bash
for d in cowrie crowdsec nginx attacker scripts docs; do
    touch "$d/.gitkeep"
done

git add .
git commit -m "dodaj .gitkeep"
```

---

## 3. Docker Compose — cykl życia środowiska

### Walidacja konfiguracji

Sprawdzenie poprawności pliku Compose przed uruchomieniem:

```bash
docker compose config >/dev/null && echo OK
```

### Uruchamianie

Uruchomienie wszystkich usług w tle:

```bash
docker compose up -d
```

Przebudowanie obrazów i uruchomienie usług:

```bash
docker compose up -d --build
```

Odtworzenie samego bouncera:

```bash
docker compose up -d --force-recreate bouncer
```

Uruchomienie usług i oczekiwanie na healthchecki:

```bash
docker compose up -d --wait
```

### Stan kontenerów i logi

```bash
docker compose ps
docker compose ps -q attacker
```

Ostatnie 40 linii logów Cowrie:

```bash
docker compose logs --tail=40 cowrie
```

Logi wszystkich usług na żywo:

```bash
docker compose logs -f
```

Logi Nginx:

```bash
docker compose logs -f nginx
```

Logi bouncera:

```bash
docker compose logs bouncer
```

### Zatrzymywanie

Zatrzymanie i usunięcie kontenerów oraz sieci Compose:

```bash
docker compose down
```

**Uwaga:** poniższe polecenie usuwa również wolumeny zarządzane przez Compose, w tym `crowdsec-db`. Nie usuwa automatycznie plików logów znajdujących się w bind mouncie `./cowrie/log`.

```bash
docker compose down -v
```

### Sprawdzanie adresu IP kontenera

Pobranie adresu IP kontenera `attacker`:

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  "$(docker compose ps -q attacker)"
```

Alternatywnie:

```bash
docker compose exec attacker hostname -I
```

Przykładowy wynik:

```text
172.19.0.X
```

Adres może się zmienić po odtworzeniu kontenera lub sieci.

---

## 4. Cowrie — logowanie i logi

### Ręczne logowanie do honeypota

```bash
ssh -p 2222 root@localhost
```

Zachowanie logowania zależy od konfiguracji `userdb.txt`. Przy wpisie `root:x:!*` logowanie na konto `root` powinno kończyć się niepowodzeniem.

Jeżeli kontener został odtworzony i zmienił się klucz hosta SSH:

```bash
ssh-keygen -R "[localhost]:2222"
```

### Oglądanie logów

Z hosta — dzięki bind mountowi `./cowrie/log`:

```bash
tail -f cowrie/log/cowrie.json
```

Z wnętrza kontenera:

```bash
docker compose exec cowrie tail -f var/log/cowrie/cowrie.json
```

Wyświetlenie zawartości katalogu logów:

```bash
docker compose exec cowrie ls /cowrie/cowrie-git/var/log/cowrie/
```

Wyświetlenie pliku JSON:

```bash
docker compose exec cowrie cat /cowrie/cowrie-git/var/log/cowrie/cowrie.json
```

### Filtrowanie typów zdarzeń

Zliczenie wystąpień poszczególnych typów zdarzeń:

```bash
jq -r '.eventid' cowrie/log/cowrie.json |
  sort | uniq -c | sort -rn
```

Wyświetlenie nieudanych logowań z kontenera:

```bash
docker compose exec -T cowrie cat var/log/cowrie/cowrie.json |
  jq -c 'select(.eventid=="cowrie.login.failed")'
```

Opcja `-T` wyłącza przydzielanie pseudo-terminala. Jest przydatna przy przekazywaniu wyniku polecenia do `jq`.

### Czyszczenie logu

**Uwaga:** tylko w środowisku laboratoryjnym. Polecenie usuwa dotychczasową zawartość pliku.

```bash
: > cowrie/log/cowrie.json
```

---

## 5. CrowdSec — kolekcje, parsery i metryki

### Aktualizacja Hub i instalacja kolekcji

```bash
docker compose exec crowdsec cscli hub update
```

Instalacja kolekcji SSH:

```bash
docker compose exec crowdsec cscli collections install crowdsecurity/sshd
```

Sprawdzenie dostępnych kolekcji związanych z Cowrie:

```bash
docker compose exec crowdsec cscli collections list -a |
  grep -i cowrie
```

Sprawdzenie parserów:

```bash
docker compose exec crowdsec cscli parsers list -a |
  grep -i cowrie
```

Lista scenariuszy:

```bash
docker compose exec crowdsec cscli scenarios list
```

**Ważne:** standardowa kolekcja `crowdsecurity/sshd` oczekuje logów SSH w formacie syslog. Logi Cowrie są zapisane jako JSON, dlatego projekt wykorzystuje własny parser `local/cowrie-json-logs`.

### Weryfikacja parsowania

Przykładowe uruchomienie `cscli explain` dla pojedynczego zdarzenia:

```bash
docker compose exec crowdsec cscli explain \
  --log '{"eventid":"cowrie.login.failed","src_ip":"172.19.0.X","username":"root"}' \
  --type cowrie
```

W przykładzie użyto uproszczonego zdarzenia. W razie problemów z parsowaniem najlepiej przekazać rzeczywistą linię z `cowrie.json`.

### Metryki

Ogólne metryki CrowdSec:

```bash
docker compose exec crowdsec cscli metrics
```

Metryki akwizycji:

```bash
docker compose exec crowdsec cscli metrics show acquisition
```

Metryki parserów:

```bash
docker compose exec crowdsec cscli metrics show parsers
```

Metryki scenariuszy:

```bash
docker compose exec crowdsec cscli metrics show scenarios
```

### Restart po zmianie konfiguracji

```bash
docker compose restart crowdsec
```

### Parser whitelist — diagnostyka laboratoryjna

Parser whitelist może pomijać prywatne adresy IP, np. adresy kontenerów `172.x.x.x`. W laboratorium może to utrudniać testowanie scenariuszy.

Wyłączenie parsera na potrzeby testów:

```bash
docker compose exec crowdsec cscli parsers remove crowdsecurity/whitelists --force
```

Przywrócenie parsera:

```bash
docker compose exec crowdsec cscli parsers install crowdsecurity/whitelists
```

**Uwaga:** wyłączanie whitelist nie jest zalecanym ustawieniem produkcyjnym. W laboratorium należy świadomie kontrolować, które adresy są dopuszczane do analizy.

### Dodatkowa diagnostyka

```bash
docker compose exec crowdsec cscli simulation status
docker compose exec crowdsec cscli allowlists list
docker compose exec crowdsec cscli metrics
```

---

## 6. CrowdSec — decyzje i bany

### Ręczne dodanie bana testowego

Do testu można użyć dokumentacyjnego adresu IP:

```bash
docker compose exec crowdsec cscli decisions add \
  --ip 1.2.3.4 \
  --duration 10m \
  --reason "test manualny"
```

### Lista decyzji

```bash
docker compose exec crowdsec cscli decisions list
```

Decyzje dla konkretnego adresu:

```bash
docker compose exec crowdsec cscli decisions list --ip 172.19.0.X
```

Wynik w formacie JSON:

```bash
docker compose exec crowdsec cscli decisions list \
  --ip 172.19.0.X -o json | jq .
```

### Usuwanie decyzji

Usunięcie decyzji dla wskazanego adresu:

```bash
docker compose exec crowdsec cscli decisions delete --ip 1.2.3.4
```

Usunięcie decyzji o konkretnym identyfikatorze:

```bash
docker compose exec crowdsec cscli decisions delete --id 1
```

Usunięcie wszystkich decyzji:

```bash
docker compose exec crowdsec cscli decisions delete --all
```

**Ostrzeżenie:** `--all` usuwa wszystkie decyzje widoczne dla CrowdSec, a nie tylko bany wygenerowane przez test Cowrie. Nie używaj tej komendy jako rutynowego sposobu czyszczenia laboratorium. Przed usunięciem sprawdź listę decyzji i ich źródła.

### Alerty

Lista alertów:

```bash
docker compose exec crowdsec cscli alerts list
```

Alerty dla konkretnego adresu:

```bash
docker compose exec crowdsec cscli alerts list \
  --ip 172.19.0.X -o json | jq '.[0]'
```

### Podgląd decyzji podczas ataku

```bash
watch -n 2 'docker compose exec -T crowdsec cscli decisions list'
```

---

## 7. Bouncer — rejestracja i diagnostyka

### Rejestracja bouncera

Dodanie bouncera do CrowdSec:

```bash
docker compose exec crowdsec cscli bouncers add cowrie-bouncer
```

Klucz API należy zapisać w lokalnym pliku `.env` jako:

```text
CROWDSEC_BOUNCER_API_KEY=...
```

Klucza nie należy umieszczać bezpośrednio w repozytorium.

### Lista i usuwanie bouncerów

```bash
docker compose exec crowdsec cscli bouncers list
```

Usunięcie bouncera:

```bash
docker compose exec crowdsec cscli bouncers delete cowrie-bouncer
```

### Diagnostyka

```bash
docker compose logs bouncer
docker compose ps bouncer
```

Bouncer powinien mieć stan `Up`, a nie `Restarting`. W `cscli bouncers list` należy sprawdzić, czy aktualizuje się pole `Last API pull`.

### Sprawdzenie łańcuchów iptables

Polecenia wykonuje się na hoście:

```bash
sudo iptables -L CROWDSEC_CHAIN -n -v
sudo iptables -L DOCKER-USER -n -v
sudo iptables -t filter -L -n --line-numbers
```

W projekcie istotny jest łańcuch `DOCKER-USER`, ponieważ obsługuje filtrowanie ruchu przekazywanego przez Docker.

---

## 8. Attacker — Hydra

### Atak brute-force

Uruchomienie Hydry z jednym loginem i listą haseł:

```bash
docker compose exec attacker hydra \
  -l root -P /pass.txt -t 4 -V ssh://cowrie -s 2222
```

Parametry:

- `-l root` — nazwa testowanego użytkownika,
- `-P /pass.txt` — plik z hasłami,
- `-t 4` — liczba równoległych zadań,
- `-V` — szczegółowy wynik,
- `ssh://cowrie` — usługa SSH i nazwa hosta w sieci Compose,
- `-s 2222` — port honeypota.

### Wariant bez szczegółowego wyjścia

```bash
docker compose exec attacker hydra \
  -l root -P /pass.txt -t 4 ssh://cowrie -s 2222
```

### Kilka loginów z pliku

```bash
docker compose exec attacker hydra \
  -L /logins.txt -P /pass.txt -t 4 ssh://cowrie -s 2222
```

### Interaktywna powłoka w kontenerze

```bash
docker compose exec attacker bash
```

### Test TCP z kontenera attacker

Polecenie pozwala sprawdzić, czy po nałożeniu bana połączenie do Cowrie jest blokowane:

```bash
docker compose exec -T attacker \
  timeout 3 bash -c 'echo > /dev/tcp/cowrie/2222'
```

Przy regule `DROP` połączenie powinno zakończyć się timeoutem. Sam timeout nie jest jednak wystarczającym dowodem — należy go zestawić z decyzją CrowdSec i regułami firewalla.

---

## 9. Analiza logów — jq

Poniższe przykłady zakładają, że log Cowrie znajduje się na hoście w pliku `cowrie/log/cowrie.json`.

### Typy zdarzeń

```bash
jq -r '.eventid' cowrie/log/cowrie.json |
  sort | uniq -c | sort -rn
```

### Nieudane logowania

Pełne zdarzenia:

```bash
jq -c 'select(.eventid=="cowrie.login.failed")' \
  cowrie/log/cowrie.json
```

Nieudane logowania jako rekordy zawierające IP, użytkownika i czas:

```bash
jq -c '
  select(.eventid=="cowrie.login.failed")
  | {
      ip: .src_ip,
      user: .username,
      time: .timestamp
    }
' cowrie/log/cowrie.json
```

### Top IP — liczba nieudanych prób

```bash
jq -s '
  [.[] | select(.eventid=="cowrie.login.failed")]
  | group_by(.src_ip)
  | map({
      ip: .[0].src_ip,
      attempts: length
    })
  | sort_by(-.attempts)
' cowrie/log/cowrie.json
```

### Komendy wpisane przez atakującego

```bash
jq -c '
  select(.eventid=="cowrie.command.input")
  | {
      ip: .src_ip,
      command: .input,
      time: .timestamp
    }
' cowrie/log/cowrie.json
```

### Próby pobrania plików

```bash
jq -c 'select(.eventid=="cowrie.session.file_download")' \
  cowrie/log/cowrie.json
```

### Komendy wget/curl

Wyszukanie poleceń, które mogą wskazywać na próbę pobrania narzędzi lub plików:

```bash
jq -c '
  select(
    .eventid=="cowrie.command.input"
    and (.input | test("wget|curl"; "i"))
  )
  | {
      src_ip,
      input
    }
' cowrie/log/cowrie.json
```

### Najczęściej wpisywane komendy

```bash
jq -s '
  [.[] | select(.eventid=="cowrie.command.input")]
  | group_by(.input)
  | map({
      command: .[0].input,
      count: length
    })
  | sort_by(-.count)
' cowrie/log/cowrie.json
```

### Unikalne adresy IP

Lista:

```bash
jq -s '[.[].src_ip] | unique' cowrie/log/cowrie.json
```

Liczba unikalnych adresów:

```bash
jq -s '[.[].src_ip] | unique | length' cowrie/log/cowrie.json
```

### Loginy i hasła

**Uwaga:** dane uwierzytelniające mogą być wrażliwe. Nie publikuj surowych haseł ani pełnych logów zawierających dane atakujących.

```bash
jq -r '
  select(.eventid | startswith("cowrie.login"))
  | [.timestamp, .src_ip, .username, .password]
  | @tsv
' cowrie/log/cowrie.json
```

### Zliczanie zdarzeń

Liczba wszystkich zdarzeń:

```bash
jq -s 'length' cowrie/log/cowrie.json
```

Liczba nieudanych logowań:

```bash
jq -r 'select(.eventid=="cowrie.login.failed") | .src_ip' \
  cowrie/log/cowrie.json | wc -l
```

### Walidacja pliku JSON

```bash
jq -c . cowrie/log/cowrie.json > /dev/null
```

Jeśli plik zawiera niepoprawną linię JSON, `jq` zgłosi błąd i wskaże miejsce problemu.

---

## 10. Skrypty projektu

### Nadanie uprawnień wykonywania

```bash
chmod +x deploy.sh scripts/*.sh
```

### deploy.sh

Uruchomienie środowiska:

```bash
./deploy.sh
```

Pomiar czasu uruchamiania:

```bash
time ./deploy.sh
```

Skrypt uruchamia usługi, czeka na gotowość SSH Cowrie i sprawdza dostępność LAPI CrowdSec.

### collect_logs.sh

Analiza logów Cowrie i wygenerowanie plików wynikowych:

```bash
./scripts/collect_logs.sh cowrie/log/cowrie.json collected
```

Sprawdzenie wygenerowanych plików:

```bash
ls -la collected/
```

Podgląd podsumowania:

```bash
cat collected/summary.json
```

### generate_dashboard.sh

Wygenerowanie strony dashboardu:

```bash
./scripts/generate_dashboard.sh collected site
```

Sprawdzenie plików:

```bash
ls -la site/
```

### verify_ban.sh

Weryfikacja decyzji CrowdSec i rzeczywistej blokady ruchu:

```bash
./scripts/verify_ban.sh 172.19.0.X
```

Skrypt przyjmuje adres IP badanego kontenera. Należy podać aktualny adres, a nie przykładową wartość `172.19.0.X`.

### enrich_ip.sh

Opcjonalne wzbogacanie danych o informacje z AbuseIPDB. Wymaga klucza API w pliku `.env`.

Załadowanie zmiennych środowiskowych:

```bash
set -a
source .env
set +a
```

Uruchomienie wzbogacania:

```bash
./scripts/enrich_ip.sh collected/top_ips.json |
  jq -s . > collected/enriched.json
```

### Suma kontrolna po analizie logów

```bash
jq '[.[].attempts] | add' collected/top_ips.json
```

Wynik powinien odpowiadać liczbie zdarzeń `cowrie.login.failed` uwzględnionych w analizie.

---

## 11. Dashboard i Nginx

### Sprawdzenie dostępności dashboardu

```bash
curl -I http://localhost:8080
```

Oczekiwany wynik:

```text
HTTP/1.1 200 OK
```

Pobranie początku strony:

```bash
curl -s http://localhost:8080 | head -20
```

### Sprawdzenie plików widocznych dla Nginx

```bash
docker compose exec nginx ls /usr/share/nginx/html
```

Podgląd pliku HTML:

```bash
docker compose exec nginx \
  cat /usr/share/nginx/html/index.html | head
```

### Restart Nginx

Po zmianach w plikach udostępnianych przez bind mount restart zwykle nie jest potrzebny. Można go jednak wykonać:

```bash
docker compose restart nginx
```

### Sprawdzenie zdrowia CrowdSec LAPI

```bash
curl -sf http://localhost:8081/health && echo OK
```

---

## 12. System — br_netfilter, iptables i sysctl

Ruch przekazywany przez most sieciowy Dockera może nie przechodzić przez reguły iptables w oczekiwany sposób, jeśli nie jest aktywny `br_netfilter`.

### Włączenie br_netfilter

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
```

Polecenia te aktywują moduł i ustawiają parametr do czasu restartu systemu.

### Utrwalenie konfiguracji

Załadowanie modułu przy starcie systemu:

```bash
echo "br_netfilter" |
  sudo tee /etc/modules-load.d/br_netfilter.conf
```

Utrwalenie parametru sysctl:

```bash
echo "net.bridge.bridge-nf-call-iptables=1" |
  sudo tee /etc/sysctl.d/99-br-netfilter.conf
```

Zastosowanie konfiguracji:

```bash
sudo sysctl --system
```

### Weryfikacja

```bash
lsmod | grep br_netfilter
```

```bash
sysctl net.bridge.bridge-nf-call-iptables
```

Oczekiwany parametr:

```text
net.bridge.bridge-nf-call-iptables = 1
```

### Ręczna reguła DROP — test

**Uwaga:** jest to testowa reguła firewalla. Może odciąć ruch z wybranego adresu. Po teście należy ją usunąć.

Dodanie reguły:

```bash
sudo iptables -I DOCKER-USER -s 172.19.0.X -j DROP
```

Podgląd łańcucha:

```bash
sudo iptables -L DOCKER-USER -n -v
```

Usunięcie reguły:

```bash
sudo iptables -D DOCKER-USER -s 172.19.0.X -j DROP
```

### Podgląd łańcucha CrowdSec

```bash
sudo iptables -L CROWDSEC_CHAIN -n -v
```

Licznik pakietów (`pkts`) może pomóc potwierdzić, czy reguła jest używana.

### ipset

```bash
sudo ipset list | head
```

Brak narzędzia `ipset` na hoście nie musi oznaczać błędu. Sposób zarządzania zestawami zależy od konfiguracji bouncera i środowiska.

---

## 13. Uprawnienia i pliki

### Uprawnienia do logów Cowrie

W projekcie kontener Cowrie korzysta z UID 999. W razie problemów z zapisem do bind mountu:

```bash
sudo chown -R 999:999 cowrie/log
```

### Uprawnienia do katalogu site

Jeśli katalog został utworzony przez roota:

```bash
sudo chown -R "$USER:$USER" site
chmod -R 755 site
```

### Uprawnienia do skryptów

```bash
chmod +x deploy.sh scripts/*.sh
```

### Plik .env.example

Przykładowy plik bez rzeczywistych kluczy:

```bash
cat > .env.example <<'EOF'
CROWDSEC_BOUNCER_API_KEY=
ABUSEIPDB_API_KEY=
EOF
```

### Lokalny plik .env

Przykład — wartości należy uzupełnić własnymi kluczami:

```bash
cat > .env <<'EOF'
CROWDSEC_BOUNCER_API_KEY=...
ABUSEIPDB_API_KEY=...
EOF
```

Plik `.env` powinien być wykluczony z repozytorium przez `.gitignore`. Nie należy commitować rzeczywistych kluczy API.

### Sprawdzenie statusu plików

```bash
git status
git status --ignored | head -30
```

Sprawdzenie, czy wskazane pliki są ignorowane:

```bash
git check-ignore -v .env site/ collected/ cowrie/log/cowrie.json
```

---

## 14. Git — typowe operacje

Sprawdzenie statusu:

```bash
git status
```

Ostatnie commity:

```bash
git log --oneline -10
```

Podgląd zmian:

```bash
git diff
```

Dodanie zmian:

```bash
git add .
```

Utworzenie commita:

```bash
git commit -m "opis zmiany"
```

Wysłanie zmian do zdalnego repozytorium:

```bash
git push origin main
```

Sprawdzenie, czy sekrety i dane runtime są ignorowane:

```bash
git check-ignore -v .env collected/ site/ cowrie/log/cowrie.json
```

---

## 15. Pełny test środowiska

Poniższa sekwencja przedstawia przykładowy przebieg testu od uruchomienia laboratorium do sprawdzenia bana i wygenerowania dashboardu.

**Uwaga:** `docker compose down -v` usuwa wolumeny zarządzane przez Compose. Nie wykonuj tego polecenia, jeśli chcesz zachować dane CrowdSec.

### 1. Zatrzymanie poprzedniego środowiska

```bash
docker compose down -v
```

### 2. Przygotowanie filtrowania ruchu i uruchomienie usług

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

./deploy.sh
```

### 3. Pobranie aktualnego adresu IP attackera

```bash
ATT=$(docker compose exec -T attacker hostname -I | awk '{print $1}')
echo "attacker = $ATT"
```

Adres może zmienić się po odtworzeniu kontenera.

### 4. Wykonanie kontrolowanego ataku

```bash
docker compose exec attacker \
  hydra -l root -P /pass.txt -t 4 ssh://cowrie -s 2222
```

Atak należy wykonywać wyłącznie na własnym, odizolowanym laboratorium.

### 5. Oczekiwanie na aktualizację decyzji przez bouncera

```bash
sleep 12
```

Czas oczekiwania jest orientacyjny i zależy od konfiguracji oraz interwału pobierania decyzji przez bouncer.

### 6. Weryfikacja bana

```bash
./scripts/verify_ban.sh "$ATT"
```

### 7. Analiza logów i wygenerowanie dashboardu

```bash
./scripts/collect_logs.sh cowrie/log/cowrie.json collected

./scripts/generate_dashboard.sh collected site

curl -I http://localhost:8080
```

Dashboard powinien być dostępny pod adresem:

```text
http://localhost:8080
```

### 8. Opcjonalne sprzątanie decyzji testowych

Najpierw sprawdź aktualną listę:

```bash
docker compose exec crowdsec cscli decisions list
```

Następnie usuń wyłącznie decyzje, które mają zostać usunięte. Nie używaj `decisions delete --all`, jeśli w bazie znajdują się inne decyzje, które chcesz zachować.

---

## Zamaskowane adresy IP używane w projekcie

| Kontekst | Adres lub zapis | Uwagi |
|---|---|---|
| Kontener attacker | `172.19.0.X` | Adres może zmienić się po odtworzeniu kontenera |
| Brama sieci Docker | `172.19.0.1` | Adres bramy; nie należy go banować podczas testu |
| Ręczne połączenie z hosta | `172.19.0.1` | W logach może pojawić się adres bramy Dockera zamiast `127.0.0.1` |
| Starsza sieć laboratoryjna | `172.18.0.X` | Adresy z wcześniejszej konfiguracji |
| Loopback hosta | `127.0.0.1` | Lokalny adres hosta |
| Adres testowy | `1.2.3.4` | Adres używany w przykładzie ręcznego dodawania decyzji |

---

## Czego świadomie nie umieszczono w tej ściądze

- Rzeczywistych kluczy API — w przykładach występują wyłącznie wartości zastępcze.
- Rzeczywistych haseł z `pass.txt` — nie należy publikować haseł używanych w testach.
- Konkretnych publicznych adresów IP pochodzących z danych runtime lub AbuseIPDB.
- Absolutnych ścieżek zależnych od konkretnego komputera — używane są ścieżki względne projektu.
- Surowych danych uwierzytelniających z logów Cowrie.

---

## Uwagi końcowe

- Komendy zakładają uruchamianie ich z katalogu głównego repozytorium, w którym znajduje się `compose.yaml` lub `docker-compose.yml`.
- W poleceniach zawierających `172.19.0.X` należy podstawić aktualny adres IP kontenera.
- Logi Cowrie są dostępne na hoście przez bind mount `./cowrie/log`.
- CrowdSec analizuje logi JSON Cowrie za pomocą własnego parsera `local/cowrie-json-logs`.
- Bouncer egzekwuje decyzje zapory sieciowej, a ruch kontenerów Docker jest filtrowany przez łańcuch `DOCKER-USER`.
- Po restarcie hosta należy sprawdzić, czy `br_netfilter` i parametr `net.bridge.bridge-nf-call-iptables` są aktywne.
- Komendy usuwające decyzje, wolumeny lub reguły firewalla należy wykonywać świadomie, po sprawdzeniu ich skutków.

