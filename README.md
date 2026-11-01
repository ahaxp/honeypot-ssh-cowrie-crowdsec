# Honeypot SSH: Cowrie + CrowdSec

Projekt studencki przedstawiający działanie honeypota SSH z automatycznym wykrywaniem i blokowaniem adresów IP wykonujących podejrzane działania.

Głównym założeniem projektu jest stworzenie zamkniętej pętli bezpieczeństwa:

**atak → detekcja → decyzja → blokada**

Projekt działa w środowisku Docker i wykorzystuje Cowrie jako honeypot, CrowdSec jako system detekcji oraz Bouncer jako mechanizm egzekwowania decyzji.

Dodatkowo logi są analizowane za pomocą Bash + `jq`, a wyniki prezentowane na statycznym dashboardzie HTML serwowanym przez Nginx.

---

## Cel projektu

Celem projektu jest zbudowanie i przetestowanie środowiska, które pozwala obserwować kontrolowane ataki na usługę SSH oraz automatycznie reagować na wykryte zagrożenia.

Projekt realizuje następujący przepływ:

```text
Atak
  │
  ▼
Cowrie
  │
  ▼
Logi JSON
  │
  ▼
CrowdSec
  │
  ▼
Decyzja o banie
  │
  ▼
Bouncer
  │
  ▼
Blokada IP
```

Równolegle dane z logów są analizowane przez:

```text
cowrie.json
     │
     ▼
collect_logs.sh
     │
     ▼
     jq
     │
     ▼
collected/
     │
     ▼
generate_dashboard.sh
     │
     ▼
site/index.html
     │
     ▼
Nginx :8080
```

---

## Architektura

```text
                       ┌──────────────────┐
                       │    Atakujący     │
                       │                  │
                       │ attacker/        │
                       │ Hydra / test     │
                       └────────┬─────────┘
                                │
                                │ SSH :2222
                                ▼
                       ┌──────────────────┐
                       │      Cowrie      │
                       │                  │
                       │  SSH honeypot    │
                       └────────┬─────────┘
                                │
                                │ zapis JSON
                                ▼
                       ┌──────────────────┐
                       │  ./cowrie/log    │
                       │   bind mount     │
                       └────────┬─────────┘
                                │
                     ┌──────────┴────────────┐
                     │                       │
                     ▼                       ▼
              ┌──────────────┐      ┌─────────────────┐
              │   CrowdSec   │      │ collect_logs.sh │
              │              │      │                 │
              │ własny parser│      │ Bash + jq       │
              │ scenarios    │      └────────┬────────┘
              │ decisions    │               │
              └──────┬───────┘               ▼
                     │               ┌─────────────────┐
                     │               │   collected/    │
                     │               └────────┬────────┘
                     │                        │
                     │                        ▼
                     │               ┌─────────────────┐
                     │               │ generate_       │
                     │               │ dashboard.sh    │
                     │               └────────┬────────┘
                     │                        │
                     ▼                        ▼
              ┌──────────────┐      ┌─────────────────┐
              │   Bouncer    │      │ site/index.html │
              │              │      └────────┬────────┘
              │ DOCKER-USER  │               │
              │ firewall     │               ▼
              └──────────────┘      ┌─────────────────┐
                                    │      Nginx      │
                                    │     :8080       │
                                    └─────────────────┘

                       CrowdSec LAPI :8081
```

Szczegółowy opis architektury znajduje się w:

`docs/architecture.md`

---

## Stack technologiczny

Projekt wykorzystuje:

- **Cowrie** — honeypot SSH średniej interakcji.
- **CrowdSec** — system wykrywania zagrożeń i podejmowania decyzji.
- **Własny parser CrowdSec** — interpretacja logów JSON Cowrie.
- **Bouncer** — mechanizm wykonywania decyzji CrowdSec.
- **Docker** — konteneryzacja komponentów.
- **Docker Compose** — orkiestracja środowiska.
- **iptables / nftables** — egzekwowanie blokad.
- **jq** — parsowanie danych JSON.
- **Bash** — automatyzacja i przetwarzanie danych.
- **Nginx** — serwowanie dashboardu.
- **Hydra** — kontrolowane generowanie prób logowania.
- **Git** — kontrola wersji.

---

## Wymagania

Do uruchomienia projektu potrzebne są:

- Linux,
- Docker,
- Docker Compose,
- Git,
- `jq`,
- uprawnienia umożliwiające konfigurację modułów i parametrów sieciowych systemu.

Projekt był przygotowywany i testowany w środowisku Linux.

Sprawdzenie instalacji:

```bash
docker --version
docker compose version
git --version
jq --version
```

---

## Struktura projektu

```text
honeypot-ssh-cowrie-crowdsec/
│
├── README.md
├── .gitignore
├── .env.example
├── docker-compose.yml
│
├── cowrie/
│   ├── cowrie.cfg
│   ├── userdb.txt
│   └── log/                         # logi generowane podczas działania
│
├── crowdsec/
│   ├── acquis.yaml
│   ├── parsers/
│   │   └── s01-parse/
│   │       └── cowrie-json-logs.yaml
│   ├── scenarios/
│   │   └── crowdsec-firewall-bouncer.yaml
│   └── config/                      # konfiguracja generowana przez cscli
│
├── attacker/
│   ├── Dockerfile
│   └── pass.txt
│
├── scripts/
│   ├── collect_logs.sh
│   ├── generate_dashboard.sh
│   ├── deploy.sh
│   ├── verify_ban.sh
│   └── enrich_ip.sh
│
├── site/                            # generowany dashboard
│   └── index.html
│
├── docs/
│   ├── architecture.md
│   └── structure.md
│
└── collected/                       # generowane dane analityczne
    ├── top_ips.json
    ├── commands.jsonl
    └── downloads.jsonl
```

Nie wszystkie katalogi i pliki muszą istnieć od razu po sklonowaniu repozytorium. Część z nich jest tworzona podczas uruchamiania projektu lub generowania wyników.

Katalog `nginx/` z własnym `default.conf` nie jest wymagany. Wykorzystywana jest domyślna konfiguracja obrazu `nginx:alpine`, która serwuje pliki z `/usr/share/nginx/html`. Dashboard jest udostępniany przez zamontowany katalog `site/`.

Szczegółowy opis struktury znajduje się w:

`docs/structure.md`

---

## Opis katalogów i skryptów

### `cowrie/`

Konfiguracja honeypota Cowrie.

- `cowrie.cfg` — konfiguracja działania honeypota.
- `userdb.txt` — baza użytkowników wykorzystywana przez Cowrie.
- `log/` — katalog z logami JSON, współdzielony przez bind mount.

Wpis `root:x:!*` w `userdb.txt` wymusza nieudane logowanie jako `root`, dzięki czemu Cowrie generuje zdarzenia `login.failed` wykorzystywane przez CrowdSec.

### `crowdsec/`

Konfiguracja CrowdSec.

- `acquis.yaml` — wskazuje źródło logów Cowrie i filtr zdarzeń.
- `parsers/s01-parse/cowrie-json-logs.yaml` — własny parser logów JSON Cowrie.
- `scenarios/` — konfiguracja scenariuszy i integracji wykorzystywanych przez projekt.
- `config/` — konfiguracja generowana przez `cscli`.

Własny parser jest potrzebny, ponieważ standardowa kolekcja `crowdsecurity/sshd` jest przeznaczona do logów SSH w formacie syslog, a Cowrie zapisuje zdarzenia JSON.

### `attacker/`

Kontener wykorzystywany do kontrolowanych testów.

Zawiera narzędzia takie jak Hydra, które generują próby logowania do honeypota.

Plik `pass.txt` zawiera dane testowe i nie powinien zawierać prawdziwych haseł.

### `scripts/`

Skrypty Bash automatyzujące działanie projektu.

| Skrypt | Odpowiedzialność |
|---|---|
| `collect_logs.sh` | Analizuje logi Cowrie za pomocą `jq` |
| `generate_dashboard.sh` | Generuje statyczny dashboard HTML |
| `deploy.sh` | Przygotowuje i uruchamia środowisko |
| `verify_ban.sh` | Weryfikuje działanie blokady adresu IP |
| `enrich_ip.sh` | Opcjonalnie wzbogaca informacje o adresach IP |

### `site/`

Katalog zawierający dashboard HTML generowany przez `generate_dashboard.sh`.

Główny plik:

```text
site/index.html
```

Katalog jest generowany podczas działania projektu i ignorowany przez Git.

### `docs/`

Dokumentacja projektu:

- `architecture.md` — architektura, przepływ danych i decyzje projektowe.
- `structure.md` — struktura katalogów i przeznaczenie plików.

### `collected/`

Katalog zawierający dane wygenerowane podczas analizy logów.

Przykładowe pliki:

```text
collected/
├── top_ips.json
├── commands.jsonl
└── downloads.jsonl
```

Katalog jest ignorowany przez Git. Nie powinien zawierać danych, które muszą być przechowywane w repozytorium.

---

## Jak działa projekt?

### 1. Atakujący

Kontrolowany kontener `attacker` wykonuje próby logowania SSH.

Ruch jest kierowany do:

```text
Cowrie :2222
```

Port `22` hosta pozostaje niezależny od honeypota.

### 2. Cowrie

Cowrie przyjmuje połączenie i rejestruje aktywność użytkownika.

Rejestrowane mogą być między innymi:

- adres IP,
- nazwa użytkownika,
- próby logowania,
- komendy,
- informacje o sesji,
- próby pobierania plików,
- czas zdarzenia.

Dane są zapisywane w formacie JSON w katalogu `./cowrie/log`, udostępnionym przez bind mount.

### 3. CrowdSec

CrowdSec analizuje logi Cowrie.

Własny parser `local/cowrie-json-logs` interpretuje zdarzenia JSON i mapuje pole `src_ip` na `source_ip`.

Nieudane logowanie jest oznaczane jako:

```text
log_type: ssh_failed-auth
```

Następnie scenariusz `crowdsecurity/ssh-bf` wykrywa podejrzane wzorce, grupując zdarzenia według `source_ip`.

Po spełnieniu warunków scenariusza CrowdSec tworzy decyzję:

```text
IP → BAN
```

### 4. Bouncer

Bouncer pobiera decyzje CrowdSec i wykonuje blokadę na poziomie firewalla.

W projekcie wykorzystuje łańcuch:

```text
DOCKER-USER
```

Jest to istotne, ponieważ ruch przekazywany pomiędzy kontenerami Docker nie musi przechodzić przez łańcuch `INPUT`.

Do poprawnego filtrowania ruchu w sieci bridge wymagane jest również włączenie `br_netfilter` i odpowiedniego parametru sysctl.

### 5. Analiza logów

Skrypt:

```text
scripts/collect_logs.sh
```

odczytuje logi Cowrie i wykorzystuje `jq` do wyciągania interesujących informacji.

Przykładowe informacje:

- najczęściej atakujące IP,
- liczba prób logowania,
- użytkownicy,
- komendy,
- pobierane pliki.

Wyniki są zapisywane w:

```text
collected/
```

### 6. Dashboard

Skrypt:

```text
scripts/generate_dashboard.sh
```

wykorzystuje dane zebrane przez `collect_logs.sh` i tworzy statyczny plik:

```text
site/index.html
```

Następnie Nginx udostępnia dashboard przez port `8080`.

---

## Uruchomienie

### 1. Sklonowanie repozytorium

```bash
git clone <adres-repozytorium>
cd honeypot-ssh-cowrie-crowdsec
```

### 2. Przygotowanie skryptów

```bash
chmod +x scripts/*.sh
```

### 3. Konfiguracja sieci Linux

Przed uruchomieniem bouncera wymagane jest włączenie `br_netfilter` i filtrowania ruchu bridge przez iptables.

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
```

**Ważne:** powyższe polecenia należy wykonać ponownie po restarcie komputera, jeśli konfiguracja nie została utrwalona na stałe. Sposób trwałego ustawienia opisano w dokumentacji projektu.

### 4. Uruchomienie środowiska

```bash
./scripts/deploy.sh
```

Skrypt przygotowuje i uruchamia środowisko, a następnie sprawdza dostępność najważniejszych usług.

Oczekiwany komunikat końcowy:

```text
[+] Tworzenie sieci i uruchamianie kontenerow...
[+] Czekam na: Cowrie (banner SSH na porcie 2222)
    gotowe po X s
[+] Czekam na: CrowdSec LAPI (/health na porcie 8081)
    gotowe po X s
[OK] Srodowisko gotowe. Dashboard: http://localhost:8080
```

Czas oczekiwania zależy od środowiska i uruchamianych kontenerów.

### 5. Sprawdzenie kontenerów

```bash
docker compose ps
```

### 6. Podgląd logów

```bash
docker compose logs -f
```

### 7. Zatrzymanie środowiska

```bash
docker compose down
```

### Porty usług

| Usługa | Adres / port | Przeznaczenie |
|---|---|---|
| Cowrie | `2222` | Honeypot SSH |
| CrowdSec LAPI | `127.0.0.1:8081` | API CrowdSec |
| Nginx | `localhost:8080` | Dashboard |

CrowdSec LAPI jest udostępnione lokalnie na porcie `8081`, natomiast Nginx publikuje dashboard na porcie `8080`. Rozdzielenie portów zapobiega kolizji usług.

---

## Dashboard

Po uruchomieniu kompletnego środowiska dashboard jest dostępny pod adresem:

```text
http://localhost:8080
```

Plik dashboardu:

```text
site/index.html
```

Dashboard prezentuje informacje zebrane z logów Cowrie.

Przykładowe informacje:

- top atakujących adresów IP,
- liczba prób logowania,
- używane nazwy użytkowników,
- wykonywane komendy,
- próby pobrania plików,
- podstawowe informacje o wykrytych zdarzeniach.

CrowdSec LAPI działa niezależnie na `127.0.0.1:8081` i nie jest serwerem dashboardu.

---

## Przykładowy przepływ testowy

Kontrolowany test może wyglądać następująco:

```text
1. Uruchomienie środowiska
          │
          ▼
2. Uruchomienie kontenera attacker
          │
          ▼
3. Próby logowania do Cowrie
          │
          ▼
4. Cowrie zapisuje zdarzenia
          │
          ▼
5. CrowdSec analizuje logi
          │
          ▼
6. Wykrycie brute-force
          │
          ▼
7. Utworzenie decyzji BAN
          │
          ▼
8. Bouncer pobiera decyzję i wykonuje blokadę
          │
          ▼
9. Odczekanie około 12 sekund
          │
          ▼
10. Weryfikacja blokady przez verify_ban.sh
          │
          ▼
11. collect_logs.sh analizuje dane
          │
          ▼
12. generate_dashboard.sh tworzy dashboard
          │
          ▼
13. Nginx udostępnia wyniki
```

**Uwaga dotycząca testu:** po utworzeniu decyzji BAN należy odczekać około 12 sekund, aby bouncer zdążył pobrać decyzję z CrowdSec. Dopiero potem należy wykonać weryfikację blokady. Zbyt szybkie sprawdzenie może sprawiać wrażenie, że blokada nie działa.

---

## Status projektu

### Tydzień 1 — fundamenty

- [x] Utworzenie repozytorium
- [x] Przygotowanie struktury katalogów
- [x] Przygotowanie `.gitignore`
- [x] Przygotowanie dokumentacji
- [x] Przygotowanie podstawowej architektury

### Tydzień 2 — Cowrie

- [x] Przygotowanie kontenera Cowrie
- [x] Konfiguracja honeypota
- [x] Uruchomienie SSH honeypota
- [x] Weryfikacja generowania logów JSON

### Tydzień 3 — CrowdSec

- [x] Uruchomienie CrowdSec
- [x] Konfiguracja źródła logów
- [x] Przygotowanie własnego parsera Cowrie JSON
- [x] Przygotowanie scenariusza detekcji
- [x] Weryfikacja wykrywania prób brute-force

### Tydzień 4 — atak i autoban

- [x] Przygotowanie kontenera `attacker`
- [x] Konfiguracja Hydra
- [x] Przeprowadzenie kontrolowanego ataku
- [x] Integracja Bouncera
- [x] Weryfikacja automatycznego bana

### Tydzień 5 — analiza logów

- [x] Implementacja `collect_logs.sh`
- [x] Parsowanie logów przez `jq`
- [x] Generowanie `top_ips.json`
- [x] Generowanie `commands.jsonl`
- [x] Generowanie `downloads.jsonl`

### Tydzień 6 — dashboard

- [x] Implementacja `generate_dashboard.sh`
- [x] Przygotowanie HTML
- [x] Konfiguracja publikacji przez Nginx
- [x] Publikacja dashboardu na porcie `8080`
- [x] Implementacja `deploy.sh`

### Tydzień 7 — wzbogacanie danych i testy

- [x] Przygotowanie `verify_ban.sh`
- [x] Przygotowanie `enrich_ip.sh`
- [x] Strojenie progów detekcji
- [x] Testy działania automatycznej blokady
- [x] Weryfikacja bana z kontenera `attacker`

**Świadomie pozostawione poza zakresem lub do ewentualnego rozwinięcia:**

- [ ] Dodatkowe kolumny kraju i reputacji IP w dashboardzie.
- [ ] Przypięcie digestów obrazów Docker.
- [ ] Przygotowanie zapasowego nagrania wideo z demonstracji.

### Tydzień 8 — dokumentacja

- [x] Przygotowanie raportu końcowego
- [x] Przygotowanie diagramów
- [x] Dokumentacja wyników testów
- [ ] Przygotowanie prezentacji — w toku

---

## Bezpieczeństwo

Projekt ma charakter edukacyjny i powinien być uruchamiany wyłącznie w kontrolowanym środowisku.

### Izolacja honeypota

Cowrie powinien działać w odpowiednio odizolowanej sieci Docker.

Nie należy wystawiać honeypota bezpośrednio do Internetu bez właściwej konfiguracji bezpieczeństwa.

### Port SSH

Honeypot wykorzystuje:

```text
2222
```

a nie:

```text
22
```

Dzięki temu projekt nie zastępuje prawdziwej usługi SSH hosta.

### Firewall Docker: DOCKER-USER i br_netfilter

Poprawne blokowanie ruchu w środowisku Docker wymaga uwzględnienia sposobu obsługi pakietów w sieci bridge.

Ruch kontener → kontener może omijać standardowe reguły `iptables`, jeśli nie jest aktywne `br_netfilter`.

W projekcie wymagane jest:

- włączenie modułu `br_netfilter`,
- ustawienie `net.bridge.bridge-nf-call-iptables=1`,
- wykorzystanie łańcucha `DOCKER-USER` przez bouncer.

Bouncer musi blokować ruch przekazywany przez Docker w odpowiednim łańcuchu, a nie polegać wyłącznie na `INPUT`.

Konfiguracja `br_netfilter` musi być utrwalona, aby po restarcie systemu filtrowanie nadal działało.

### Sekrety

Do repozytorium nie wolno dodawać:

```text
.env
*.key
crowdsec_api_key.txt
```

Nie należy również commitować:

- haseł,
- tokenów API,
- prywatnych kluczy,
- prawdziwych danych uwierzytelniających,
- innych danych wrażliwych.

Plik `.env.example` może zawierać nazwy wymaganych zmiennych i przykładowe wartości, ale nie może zawierać prawdziwych sekretów.

Sekrety powinny być przechowywane lokalnie i przekazywane do aplikacji w bezpieczny sposób.

---

## `.gitignore`

Repozytorium ignoruje dane runtime, wygenerowane pliki i sekrety.

Przykładowa zawartość:

```gitignore
# Dane runtime i logi
collected/
cowrie/log/
*.log
cowrie.json*

# Generowany dashboard
site/

# Konfiguracja generowana przez CrowdSec
crowdsec/config/
crowdsec/parsers/s00-raw/
crowdsec/parsers/s02-enrich/
crowdsec/parsers/s01-parse/sshd-*
crowdsec/scenarios/ssh-*

# Sekrety
.env
*.key
crowdsec_api_key.txt

# Edytory i system
.DS_Store
*.swp
*~
```

Plik `.env.example` powinien pozostać w repozytorium, ponieważ jest wzorem konfiguracji bez prawdziwych danych uwierzytelniających.

---

## Ograniczenia projektu

Projekt posiada kilka ograniczeń.

### Cowrie jest honeypotem średniej interakcji

Doświadczony atakujący może rozpoznać, że komunikuje się z honeypotem, a nie z prawdziwym systemem.

### Ograniczona detekcja

CrowdSec wykrywa tylko zachowania objęte skonfigurowanymi parserami i scenariuszami.

### Środowisko laboratoryjne

Projekt jest przeznaczony przede wszystkim do celów edukacyjnych i testowych.

### Brak własnej bazy danych

Projekt nie dodaje osobnej bazy danych do przechowywania wyników analizy. Dane analityczne są przechowywane i przetwarzane jako pliki JSON.

CrowdSec korzysta jednak z własnej, wbudowanej bazy danych przechowywanej w wolumenie `crowdsec-db`.

### Prosty dashboard

Dashboard jest statycznym HTML-em generowanym przez Bash + `jq`. Nie jest to pełnoprawny system monitoringu produkcyjnego.

### Wzbogacanie informacji o IP

Dodatkowe informacje o kraju i reputacji adresów IP nie są obecnie wymagane do działania głównej pętli bezpieczeństwa. Mogą zostać dodane jako rozszerzenie projektu.

---

## Dokumentacja

Szczegółowa dokumentacja znajduje się w katalogu `docs/`.

### Architektura

```text
docs/architecture.md
```

Opisuje:

- przepływ danych,
- komponenty,
- Cowrie,
- CrowdSec i własny parser,
- Bouncer,
- blokowanie ruchu Docker,
- dashboard,
- bezpieczeństwo,
- decyzje projektowe.

### Struktura projektu

```text
docs/structure.md
```

Opisuje:

- strukturę katalogów,
- przeznaczenie plików,
- przepływ danych,
- konwencje projektu.

Raport końcowy powinien zostać dodany do `docs/`, gdy jego finalna wersja będzie gotowa.

---

## Główna idea projektu

Najważniejszym elementem projektu jest zamknięta pętla:

```text
                     ┌───────────────┐
                     │     ATAK      │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │    COWRIE     │
                     │  honeypot SSH │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │     LOGI      │
                     │     JSON      │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │   CROWDSEC    │
                     │    analiza    │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │    DECYZJA    │
                     │      BAN      │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │    BOUNCER    │
                     │   DOCKER-USER│
                     └───────────────┘

                             │
                             │ równolegle
                             ▼

                     ┌───────────────┐
                     │   Bash + jq  │
                     │    analiza    │
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │   DASHBOARD   │
                     │ site/index.html│
                     └───────┬───────┘
                             │
                             ▼
                     ┌───────────────┐
                     │     NGINX     │
                     │     :8080     │
                     └───────────────┘
```

**Cowrie zbiera dane → CrowdSec wykrywa zagrożenie → Bouncer wykonuje blokadę → Bash + jq analizują dane → Nginx prezentuje wyniki.**

---

## Autor

Projekt studencki — Honeypot SSH z wykorzystaniem Cowrie i CrowdSec.

Projekt służy do celów edukacyjnych, laboratoryjnych i demonstracyjnych.