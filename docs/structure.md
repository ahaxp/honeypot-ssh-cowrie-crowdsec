# Struktura projektu

## 1. Cel dokumentu

Ten dokument opisuje strukturę repozytorium projektu:

**Honeypot SSH: Cowrie + CrowdSec**

Projekt jest podzielony na katalogi odpowiedzialne za:

- honeypota Cowrie,
- system detekcji CrowdSec,
- własny parser logów Cowrie,
- kontrolowanego atakującego,
- dashboard,
- skrypty automatyzujące,
- dokumentację,
- dane generowane podczas działania systemu.

Główną zasadą organizacji projektu jest rozdzielenie:

```text
kod
konfiguracja
skrypty
dokumentacja
dane runtime
sekrety
```

Dzięki temu repozytorium pozostaje uporządkowane, a dane generowane podczas działania honeypota nie są przechowywane razem z kodem źródłowym.

---

## 2. Drzewo katalogów

Poniższe drzewo przedstawia strukturę projektu po zakończeniu głównych prac implementacyjnych.

```text
honeypot-ssh-cowrie-crowdsec/
│
├── README.md
├── .gitignore
├── .env.example
├── docker-compose.yml
│
├── cowrie/
│   ├── .gitkeep
│   ├── cowrie.cfg
│   ├── userdb.txt
│   └── log/                         # bind mount, dane runtime
│
├── crowdsec/
│   ├── .gitkeep
│   ├── acquis.yaml
│   ├── crowdsec-firewall-bouncer.yaml
│   ├── parsers/
│   │   └── s01-parse/
│   │       └── cowrie-json-logs.yaml
│   ├── scenarios/
│   │   └── .gitkeep
│   └── config/                      # generowane, ignorowane przez Git
│
├── attacker/
│   ├── .gitkeep
│   ├── Dockerfile
│   └── pass.txt
│
├── scripts/
│   ├── .gitkeep
│   ├── collect_logs.sh
│   ├── generate_dashboard.sh
│   ├── deploy.sh
│   ├── verify_ban.sh
│   └── enrich_ip.sh
│
├── site/                            # generowane, ignorowane przez Git
│   └── index.html
│
├── docs/
│   ├── .gitkeep
│   ├── architecture.md
│   ├── structure.md
│   └── raport.md
│
└── collected/                       # dane runtime, ignorowane przez Git
    ├── top_ips.json
    ├── summary.json
    ├── top_users.json
    ├── top_passwords.json
    ├── commands.jsonl
    ├── downloads.jsonl
    ├── connections.jsonl
    └── enriched.json
```

Nie wszystkie katalogi z drzewa muszą zawierać pliki śledzone przez Git. Część z nich jest tworzona podczas uruchamiania projektu, a jej zawartość jest ignorowana przez `.gitignore`.

---

## 3. Pliki główne

### `README.md`

Główny opis projektu.

Zawiera:

- cel projektu,
- opis architektury,
- używane technologie,
- wymagania,
- strukturę katalogów,
- instrukcję uruchomienia,
- status projektu,
- informacje dotyczące bezpieczeństwa,
- ograniczenia projektu.

Jest to pierwszy plik, który powinien zostać przeczytany po pobraniu repozytorium.

### `.gitignore`

Definiuje pliki i katalogi, które nie powinny być śledzone przez Git.

Najważniejsze wpisy:

```gitignore
# Dane i wyniki runtime
collected/
site/
*.log
cowrie.json*

# Wygenerowana konfiguracja CrowdSec
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

Celem jest ochrona repozytorium przed przypadkowym dodaniem:

- logów i danych runtime,
- wygenerowanych plików,
- sekretów i kluczy API,
- plików tymczasowych.

### `.env.example`

Przykładowy plik zmiennych środowiskowych.

Zawiera nazwy wymaganych zmiennych, ale nie powinien zawierać prawdziwych kluczy ani sekretów.

Właściwy plik `.env` jest lokalny i ignorowany przez Git.

### `docker-compose.yml`

Główny plik odpowiedzialny za uruchomienie środowiska Docker.

Definiuje usługi projektu:

```text
Cowrie
CrowdSec
Firewall Bouncer
Nginx
attacker
```

Określa również:

- sieć Docker `honeytrapnet`,
- porty usług,
- zmienne środowiskowe,
- zależności pomiędzy kontenerami,
- bind mounty i named volumes,
- sposób udostępniania logów.

CrowdSec korzysta z własnej wbudowanej bazy danych przechowywanej w wolumenie `crowdsec-db`. Projekt nie dodaje osobnej usługi bazodanowej.

---

## 4. Katalog `cowrie/`

```text
cowrie/
├── .gitkeep
├── cowrie.cfg
├── userdb.txt
└── log/
```

Katalog zawiera konfigurację honeypota Cowrie oraz logi generowane podczas jego działania.

### `cowrie/cowrie.cfg`

Plik konfiguracyjny Cowrie.

Określa między innymi:

- sposób działania honeypota,
- jego tożsamość,
- konfigurację SSH,
- system plików honeypota,
- logowanie zdarzeń,
- zachowanie sesji.

Cowrie działa jako honeypot SSH średniej interakcji.

### `cowrie/userdb.txt`

Plik definiujący użytkowników i sposób uwierzytelniania w Cowrie.

W projekcie wykorzystywany jest wpis:

```text
root:x:!*
```

Wymusza on nieudane logowanie dla użytkownika `root`. Dzięki temu próby logowania generują zdarzenia `login.failed`, które mogą być następnie analizowane przez CrowdSec.

Plik jest istotnym elementem konfiguracji testów brute-force.

### `cowrie/log/`

Katalog zawierający logi Cowrie.

Jest to **bind mount** z hosta, a nie Docker named volume.

Cowrie zapisuje logi w kontenerze w lokalizacji:

```text
/cowrie/cowrie-git/var/log/cowrie
```

Katalog hosta `./cowrie/log` jest montowany w odpowiednim miejscu kontenera. Ten sam katalog jest udostępniany CrowdSec jako:

```text
/var/log/cowrie:ro
```

Dzięki temu:

- logi można odczytywać bezpośrednio z hosta, np. za pomocą `jq`,
- CrowdSec może analizować te same pliki,
- nie trzeba kopiować logów pomiędzy kontenerami.

Katalog zawiera dane runtime i nie powinien być commitowany.

### `.gitkeep`

Pozwala zachować katalog w repozytorium Git, nawet jeśli nie zawiera jeszcze właściwych plików.

---

## 5. Katalog `crowdsec/`

```text
crowdsec/
├── .gitkeep
├── acquis.yaml
├── crowdsec-firewall-bouncer.yaml
├── parsers/
│   └── s01-parse/
│       └── cowrie-json-logs.yaml
├── scenarios/
│   └── .gitkeep
└── config/
```

Katalog zawiera konfigurację CrowdSec, własny parser logów Cowrie oraz konfigurację bouncera.

### `crowdsec/acquis.yaml`

Plik określający źródła logów analizowanych przez CrowdSec.

W projekcie wskazuje logi Cowrie i filtruje je według typu źródła:

```yaml
filter: "evt.Line.Labels.type == 'cowrie'"
```

Logi są odczytywane z katalogu zamontowanego jako `/var/log/cowrie`.

### `crowdsec/parsers/s01-parse/cowrie-json-logs.yaml`

Własny parser CrowdSec o nazwie:

```text
local/cowrie-json-logs
```

Jest to jeden z najważniejszych elementów integracji Cowrie z CrowdSec.

Standardowa kolekcja `crowdsecurity/sshd` oczekuje logów w formacie syslog. Cowrie zapisuje natomiast zdarzenia w JSON, dlatego konieczne było przygotowanie własnego parsera.

Parser:

1. Odczytuje surową linię JSON z `evt.Line.Raw`.
2. Dekoduje ją przy użyciu `UnmarshalJSON`.
3. Pobiera adres źródłowy z pola `src_ip`.
4. Mapuje `src_ip` na `source_ip`.
5. Ustawia typ zdarzenia `log_type: ssh_failed-auth` dla nieudanego logowania.

Dzięki temu zdarzenia Cowrie otrzymują pola wymagane przez scenariusz detekcji.

### `crowdsec/scenarios/`

Katalog przeznaczony na scenariusze CrowdSec.

W projekcie wykorzystywany jest scenariusz:

```text
crowdsecurity/ssh-bf
```

Scenariusz wykrywa próby brute-force SSH. Zdarzenia są grupowane według `source_ip`, dzięki czemu kolejne nieudane logowania z tego samego adresu IP mogą prowadzić do decyzji o blokadzie.

Próg detekcji jest określany przez parametry `capacity` i `leakspeed` w konfiguracji scenariusza.

### `crowdsec/crowdsec-firewall-bouncer.yaml`

Konfiguracja Firewall Bouncera.

Bouncer pobiera decyzje CrowdSec i egzekwuje blokady na poziomie reguł firewalla.

W środowisku Docker istotne jest użycie łańcucha `DOCKER-USER`, a nie wyłącznie `INPUT`. Ruch kierowany do kontenerów może przechodzić przez reguły Dockera inną ścieżką niż ruch do usług hosta.

### `crowdsec/config/`

Katalog z konfiguracją generowaną przez CrowdSec, między innymi przez `cscli`.

Nie jest traktowany jako kod źródłowy i jest ignorowany przez Git.

### Baza danych CrowdSec

CrowdSec korzysta z własnej wbudowanej bazy danych. Jej dane są przechowywane w wolumenie Docker:

```text
crowdsec-db
```

Projekt nie dodaje osobnego serwera MySQL, PostgreSQL ani MongoDB.

---

## 6. Dashboard i Nginx

Dashboard jest generowany jako statyczny plik HTML.

```text
site/
└── index.html
```

### `site/index.html`

Plik dashboardu generowany przez `scripts/generate_dashboard.sh`.

Zawiera wizualizację danych zebranych i przetworzonych przez skrypty projektu.

Dashboard wykorzystuje HTML, CSS, JavaScript oraz elementy SVG. W projekcie nie jest uruchamiany osobny backend dashboardu.

Katalog `site/` jest generowany i ignorowany przez Git.

### Nginx

Projekt wykorzystuje obraz `nginx:alpine`.

Nie jest używany własny plik `nginx/default.conf`. Domyślna konfiguracja Nginx wystarcza do serwowania statycznych plików z katalogu:

```text
/usr/share/nginx/html
```

Katalog hosta jest montowany jako:

```text
./site:/usr/share/nginx/html:ro
```

Nginx udostępnia dashboard pod adresem:

```text
http://localhost:8080
```

Nginx odpowiada wyłącznie za publikację dashboardu. Nie analizuje logów, nie wykrywa ataków i nie blokuje adresów IP.

---

## 7. Katalog `attacker/`

```text
attacker/
├── .gitkeep
├── Dockerfile
└── pass.txt
```

Katalog zawiera środowisko wykorzystywane do kontrolowanego generowania ataków testowych.

### `attacker/Dockerfile`

Definiuje obraz kontenera testowego atakującego.

Zawiera narzędzia wykorzystywane do wykonywania kontrolowanych prób logowania SSH.

Schemat:

```text
Dockerfile
    │
    ▼
obraz attacker
    │
    ▼
kontener attacker
    │
    ▼
próby SSH
    │
    ▼
Cowrie :2222
```

### `attacker/pass.txt`

Lista haseł używana podczas kontrolowanych testów.

Plik powinien zawierać wyłącznie dane testowe. Nie należy umieszczać w nim prawdziwych haseł.

Przykładowe wartości:

```text
password
admin
123456
qwerty
test
```

---

## 8. Katalog `scripts/`

```text
scripts/
├── .gitkeep
├── collect_logs.sh
├── generate_dashboard.sh
├── deploy.sh
├── verify_ban.sh
└── enrich_ip.sh
```

Katalog zawiera skrypty Bash automatyzujące działanie projektu.

### `scripts/collect_logs.sh`

Skrypt odpowiedzialny za analizowanie logów Cowrie.

Wykorzystuje Bash oraz `jq`.

Jego zadania obejmują:

- odczyt logów JSON,
- filtrowanie zdarzeń,
- grupowanie adresów IP,
- analizę prób logowania,
- wyciąganie wykonywanych komend,
- wyciąganie informacji o pobieranych plikach,
- przygotowanie danych dla dashboardu.

Wyniki trafiają do katalogu `collected/`.

### `scripts/generate_dashboard.sh`

Skrypt generujący dashboard na podstawie danych z katalogu `collected/`.

Pobiera przygotowane pliki JSON i JSONL, a następnie generuje:

```text
site/index.html
```

Dashboard jest statycznym plikiem HTML serwowanym przez Nginx.

### `scripts/deploy.sh`

Skrypt automatyzujący uruchamianie środowiska.

Wykonuje między innymi:

1. uruchomienie usług przez `docker compose up -d --build`,
2. oczekiwanie na gotowość Cowrie,
3. sprawdzenie bannera SSH na porcie `2222`,
4. oczekiwanie na gotowość CrowdSec LAPI,
5. sprawdzenie endpointu `/health` na porcie `8081`.

Skrypt wykorzystuje funkcję oczekiwania `wait_for` z limitem 90 sekund.

### `scripts/verify_ban.sh`

Skrypt weryfikujący, czy blokada adresu IP działa zarówno po stronie CrowdSec, jak i na poziomie ruchu sieciowego.

Sprawdza dwa elementy.

**1. Obecność decyzji w CrowdSec**

Wykorzystuje polecenie:

```bash
cscli decisions list --ip <IP> -o json
```

oraz sprawdza, czy wynik zawiera co najmniej jedną decyzję:

```bash
jq -e 'length > 0'
```

**2. Rzeczywiste zablokowanie połączenia**

Wykonuje próbę połączenia z portem Cowrie `2222` z kontenera `attacker`, wykorzystując `/dev/tcp` i limit czasu 3 sekund.

Jeżeli reguła firewalla odrzuca pakiety przez `DROP`, próba może zakończyć się timeoutem, a nie komunikatem `Connection refused`.

Dzięki temu test nie ogranicza się do sprawdzenia, czy decyzja BAN istnieje w bazie CrowdSec — weryfikuje również rzeczywiste działanie blokady.

### `scripts/enrich_ip.sh`

Skrypt służący do wzbogacania informacji o adresach IP.

Może wykorzystywać zewnętrzne API, takie jak AbuseIPDB.

Wyniki wzbogacania są zapisywane w:

```text
collected/enriched.json
```

Korzystanie z zewnętrznego API wymaga bezpiecznego przechowywania klucza w pliku `.env`. Klucz nie może znajdować się bezpośrednio w repozytorium.

---

## 9. Katalog `docs/`

```text
docs/
├── .gitkeep
├── architecture.md
├── structure.md
└── raport.md
```

Katalog zawiera dokumentację projektu.

### `docs/architecture.md`

Opisuje architekturę systemu, w tym:

- diagram systemu,
- przepływ danych,
- działanie Cowrie,
- integrację CrowdSec,
- własny parser,
- działanie Bouncera,
- dashboard i Nginx,
- decyzje projektowe,
- zagadnienia bezpieczeństwa.

### `docs/structure.md`

Ten dokument.

Opisuje strukturę repozytorium oraz rolę poszczególnych katalogów i plików.

### `docs/raport.md`

Dokument przeznaczony na raport końcowy projektu.

Powinien zawierać:

- opis wykonania projektu,
- konfigurację środowiska,
- przeprowadzone testy,
- wyniki testów,
- przykładowe logi,
- wyniki detekcji,
- wyniki banowania,
- zrzuty ekranu dashboardu,
- problemy napotkane podczas realizacji,
- rozwiązania problemów,
- wnioski końcowe.

---

## 10. Katalog `collected/`

```text
collected/
├── top_ips.json
├── summary.json
├── top_users.json
├── top_passwords.json
├── commands.jsonl
├── downloads.jsonl
├── connections.jsonl
└── enriched.json
```

Katalog zawiera dane generowane podczas działania projektu.

Nie jest częścią kodu źródłowego i jest ignorowany przez Git.

### Pliki JSON

| Plik | Zawartość |
|---|---|
| `top_ips.json` | Najczęściej występujące adresy IP |
| `summary.json` | Zbiorcze statystyki zdarzeń |
| `top_users.json` | Najczęściej używane nazwy użytkowników |
| `top_passwords.json` | Najczęściej używane hasła testowane przez atakujących |
| `enriched.json` | Dodatkowe informacje o adresach IP |

### Pliki JSONL

Pliki JSONL zawierają jedno zdarzenie JSON w każdej linii.

| Plik | Zawartość |
|---|---|
| `commands.jsonl` | Komendy wykonywane podczas sesji honeypota |
| `downloads.jsonl` | Informacje o próbach pobierania plików |
| `connections.jsonl` | Informacje o połączeniach |

Przykładowy wpis w `commands.jsonl`:

```json
{"ip":"192.168.1.100","command":"whoami"}
{"ip":"192.168.1.100","command":"uname -a"}
```

Dokładna struktura danych zależy od implementacji skryptu `collect_logs.sh`.

---

## 11. Pliki `.gitkeep`

W projekcie wykorzystywane są pliki `.gitkeep`, aby zachować wybrane puste katalogi w repozytorium Git.

Przykładowo:

```text
cowrie/.gitkeep
crowdsec/.gitkeep
crowdsec/scenarios/.gitkeep
attacker/.gitkeep
scripts/.gitkeep
docs/.gitkeep
```

`.gitkeep` jest konwencją, a nie specjalną funkcją Gita.

Git nie śledzi pustych katalogów, dlatego umieszczenie w nich pliku `.gitkeep` pozwala zachować ich strukturę w repozytorium.

---

## 12. Przepływ plików w runtime

Główny przepływ danych wygląda następująco:

```text
                         docker-compose.yml
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
           Cowrie            CrowdSec           Nginx
              │                 ▲                 ▲
              │                 │                 │
              ▼                 │                 │
       /cowrie/cowrie-git/      │                 │
          var/log/cowrie        │                 │
              │                 │                 │
              ▼                 │                 │
       ./cowrie/log ────────────┘                 │
              │                                   │
              ▼                                   │
       collect_logs.sh                            │
              │                                   │
              ▼                                   │
           collected/                             │
              │                                   │
              ▼                                   │
     generate_dashboard.sh                        │
              │                                   │
              ▼                                   │
        site/index.html ──────────────────────────┘
```

Katalog `./cowrie/log` jest współdzielony przez Cowrie i CrowdSec za pomocą bind mountów.

Skrypt `collect_logs.sh` odczytuje te same logi z hosta i przygotowuje dane do dashboardu.

Nginx serwuje wygenerowany plik `site/index.html`.

---

## 13. Przepływ danych pomiędzy komponentami

### Cowrie → CrowdSec

```text
Cowrie
  │
  ▼
logi JSON
  │
  ▼
./cowrie/log
  │
  ▼
CrowdSec acquis.yaml
  │
  ▼
parser local/cowrie-json-logs
  │
  ▼
scenariusz crowdsecurity/ssh-bf
  │
  ▼
decyzja BAN
```

Własny parser przekształca zdarzenia JSON Cowrie do formatu, z którego może korzystać scenariusz detekcji.

### Cowrie → collect_logs.sh

```text
Cowrie
  │
  ▼
./cowrie/log
  │
  ▼
collect_logs.sh
  │
  ▼
jq
  │
  ▼
collected/
```

Skrypt analizuje logi niezależnie od mechanizmu detekcji CrowdSec.

### CrowdSec → Bouncer

```text
CrowdSec
  │
  ▼
decyzja BAN
  │
  ▼
Firewall Bouncer
  │
  ▼
reguły firewalla
  │
  ▼
blokada adresu IP
```

Bouncer egzekwuje decyzje CrowdSec na poziomie firewalla.

### `collected/` → dashboard

```text
collected/
  │
  ▼
generate_dashboard.sh
  │
  ▼
site/index.html
  │
  ▼
Nginx
  │
  ▼
http://localhost:8080
```

---

## 14. Przechowywanie logów i Docker volumes

Projekt wykorzystuje **bind mount `./cowrie/log`**, a nie Docker named volume do przechowywania logów Cowrie.

Cowrie zapisuje logi w kontenerze w lokalizacji:

```text
/cowrie/cowrie-git/var/log/cowrie
```

Katalog ten jest powiązany z katalogiem hosta:

```text
./cowrie/log
```

CrowdSec montuje ten sam katalog w trybie tylko do odczytu:

```text
/var/log/cowrie:ro
```

Schemat:

```text
┌─────────────────────────────┐
│            Cowrie           │
│                             │
│ zapis logów JSON            │
│ /cowrie/cowrie-git/var/log/ │
│ cowrie                      │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│       Host: ./cowrie/log    │
│                             │
│ wspólny bind mount          │
└──────────────┬──────────────┘
               │
               ├──────────────► CrowdSec (tylko odczyt)
               │
               └──────────────► collect_logs.sh + jq
```

Takie rozwiązanie umożliwia:

- odczyt logów bezpośrednio na hoście,
- analizę danych za pomocą `jq`,
- udostępnienie tych samych logów CrowdSec,
- uniknięcie kopiowania danych pomiędzy kontenerami.

Niezależnie od bind mountu logów, CrowdSec korzysta z własnego wolumenu `crowdsec-db` do przechowywania danych swojej wbudowanej bazy.

---

## 15. Sieć Docker i porty

Kontenery projektu komunikują się za pomocą prywatnej sieci Docker:

```text
honeytrapnet
```

Schemat logiczny:

```text
                    Docker network
                          │
         ┌────────────────┼────────────────┐
         │                │                │
         ▼                ▼                ▼
      Cowrie           CrowdSec          Nginx
         ▲                │
         │                ▼
      attacker          Bouncer
```

Komunikacja pomiędzy kontenerami odbywa się przez sieć wewnętrzną.

Na hosta wystawiane są wymagane porty:

| Port hosta | Usługa | Przeznaczenie |
|---|---|---|
| `127.0.0.1:2222` | Cowrie | Testowe połączenia SSH |
| `127.0.0.1:8080` | Nginx | Dashboard |
| `127.0.0.1:8081` | CrowdSec LAPI | API CrowdSec i kontrola stanu |

Porty `8080` i `8081` są powiązane z adresem `127.0.0.1`, aby nie udostępniać dashboardu i LAPI na wszystkich interfejsach hosta.

### Filtrowanie ruchu kontenerów

W środowisku Docker samo dodanie reguł do łańcucha `INPUT` nie wystarcza do blokowania całego ruchu kierowanego do kontenerów.

Dlatego Firewall Bouncer wykorzystuje łańcuch:

```text
DOCKER-USER
```

Do prawidłowego filtrowania ruchu przekazywanego przez most Docker wymagane jest również włączenie `br_netfilter` i odpowiedniego parametru sysctl:

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
```

Po restarcie systemu ustawienie powinno być ponownie aktywowane lub zapisane w konfiguracji systemowej, aby nie trzeba było wykonywać tych poleceń ręcznie.

---

## 16. Zasady organizacji projektu

### Kod

Skrypty automatyzujące znajdują się w:

```text
scripts/
```

Konfiguracje komponentów są przechowywane w katalogach odpowiadających tym komponentom.

### Konfiguracja

Konfiguracja jest przechowywana razem z komponentem, którego dotyczy.

Przykłady:

```text
cowrie/cowrie.cfg
cowrie/userdb.txt
crowdsec/acquis.yaml
crowdsec/parsers/s01-parse/cowrie-json-logs.yaml
crowdsec/crowdsec-firewall-bouncer.yaml
.env.example
```

### Dokumentacja

Dokumentacja znajduje się w:

```text
docs/
```

### Dane runtime

Dane wygenerowane podczas działania projektu znajdują się w:

```text
cowrie/log/
collected/
site/
```

Nie są przeznaczone do commitowania.

### Sekrety

Sekrety są przechowywane poza repozytorium, w lokalnym pliku `.env` lub w odpowiednim mechanizmie zarządzania sekretami.

Przykładowe pliki ignorowane przez Git:

```text
.env
*.key
crowdsec_api_key.txt
```

---

## 17. Czego nie przechowujemy w repozytorium

Repozytorium nie powinno zawierać:

```text
prawdziwych haseł
kluczy API
tokenów
prywatnych kluczy SSH
lokalnego pliku .env
logów runtime
danych osobowych
wygenerowanych plików dashboardu
```

Nie należy również commitować dużych plików generowanych podczas działania honeypota.

---

## 18. Czego świadomie nie ma w projekcie

### Brak własnej bazy danych projektu

Projekt nie dodaje osobnego serwera bazodanowego, takiego jak:

```text
MySQL
PostgreSQL
MongoDB
Redis
```

Dane analityczne projektu są przygotowywane i przechowywane w plikach JSON oraz JSONL.

CrowdSec korzysta jednak z własnej, wbudowanej bazy danych przechowywanej w wolumenie `crowdsec-db`.

Oznacza to, że projekt nie wymaga dodatkowej usługi bazodanowej, ale nie oznacza całkowitego braku bazy danych w środowisku.

### Brak osobnego backendu dashboardu

Dashboard nie wykorzystuje osobnego frameworka backendowego, takiego jak:

```text
Flask
Django
Node.js
Express
```

Jest generowany jako statyczny HTML przez skrypt Bash.

### Brak prawdziwego SSH na porcie 22

Cowrie wykorzystuje port:

```text
2222
```

Port:

```text
22
```

pozostaje przeznaczony dla prawdziwej usługi SSH hosta.

---

## 19. Zależności pomiędzy elementami

Główne zależności projektu:

```text
docker-compose.yml
        │
        ├──────────► Cowrie
        │               │
        │               ▼
        │          logi JSON
        │               │
        │               ▼
        │         ./cowrie/log
        │               │
        │       ┌───────┴────────┐
        │       │                │
        │       ▼                ▼
        │   CrowdSec       collect_logs.sh
        │       │                │
        │       ▼                ▼
        │   parser          collected/
        │       │                │
        │       ▼                ▼
        │   scenariusz    generate_dashboard.sh
        │       │                │
        │       ▼                ▼
        │   decyzja BAN    site/index.html
        │       │                │
        │       ▼                ▼
        │   Bouncer              Nginx
        │       │                │
        │       ▼                ▼
        │   blokada IP       :8080
        │
        └──────────► attacker
```

---

## 20. Odpowiedzialność komponentów

| Komponent | Odpowiedzialność |
|---|---|
| `docker-compose.yml` | Uruchomienie i połączenie usług |
| `Cowrie` | Honeypot SSH i zbieranie zdarzeń |
| `cowrie/log/` | Współdzielone logi runtime |
| `userdb.txt` | Wymuszenie nieudanego logowania testowego |
| `acquis.yaml` | Wskazanie źródła logów CrowdSec |
| `cowrie-json-logs.yaml` | Parsowanie zdarzeń JSON Cowrie |
| `ssh-bf` | Wykrywanie prób brute-force |
| `CrowdSec` | Analiza logów i podejmowanie decyzji |
| `Firewall Bouncer` | Egzekwowanie decyzji o blokadzie |
| `collect_logs.sh` | Analiza danych za pomocą `jq` |
| `collected/` | Przechowywanie danych runtime |
| `generate_dashboard.sh` | Generowanie dashboardu |
| `site/index.html` | Statyczna prezentacja danych |
| `Nginx` | Udostępnienie dashboardu |
| `attacker` | Kontrolowane generowanie ataków |
| `deploy.sh` | Automatyzacja uruchamiania |
| `verify_ban.sh` | Weryfikacja decyzji i rzeczywistej blokady |
| `enrich_ip.sh` | Wzbogacanie informacji o IP |
| `docs/` | Dokumentacja projektu |

---

## 21. Zasada rozdzielenia odpowiedzialności

Projekt został podzielony na komponenty zgodnie z zasadą jednej odpowiedzialności.

Najważniejsza pętla detekcji i blokowania wygląda następująco:

```text
Cowrie
  │
  ▼
log JSON
  │
  ▼
własny parser
local/cowrie-json-logs
  │
  ▼
scenariusz
crowdsecurity/ssh-bf
  │
  ▼
decyzja BAN
  │
  ▼
Firewall Bouncer
  │
  ▼
reguły firewalla
  │
  ▼
blokada adresu IP
```

Równolegle działa ścieżka analityczna i prezentacyjna:

```text
logi Cowrie
  │
  ▼
collect_logs.sh
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
Nginx
  │
  ▼
dashboard w przeglądarce
```

Dzięki temu parser, scenariusz, CrowdSec i Bouncer odpowiadają za kolejne etapy detekcji i egzekwowania blokady, a skrypty analityczne i dashboard realizują niezależną ścieżkę prezentacji danych.

---

## 22. Podsumowanie struktury

Projekt został podzielony na główne obszary:

```text
┌──────────────────────────────────────────┐
│                 PROJEKT                  │
├──────────────────────────────────────────┤
│                                          │
│  cowrie/        → honeypot SSH           │
│                                          │
│  crowdsec/      → parser i detekcja      │
│                                          │
│  attacker/      → kontrolowane testy     │
│                                          │
│  scripts/       → automatyzacja          │
│                                          │
│  site/          → dashboard              │
│                                          │
│  docs/          → dokumentacja           │
│                                          │
│  collected/     → dane runtime           │
│                                          │
└──────────────────────────────────────────┘
```

Najważniejszy przepływ projektu:

```text
ATakujący
    │
    ▼
Cowrie
    │
    ▼
logi JSON
    │
    ├────────────────────────┐
    ▼                        ▼
CrowdSec               collect_logs.sh
    │                        │
    ▼                        ▼
własny parser            collected/
    │                        │
    ▼                        ▼
scenariusz            generate_dashboard.sh
    │                        │
    ▼                        ▼
decyzja BAN           site/index.html
    │                        │
    ▼                        ▼
Bouncer                   Nginx
    │                        │
    ▼                        ▼
blokada IP              :8080
```

Struktura repozytorium została zaprojektowana tak, aby oddzielić **zbieranie danych, parsowanie, detekcję, egzekwowanie decyzji, analizę, prezentację oraz dokumentację**.

Dzięki temu projekt pozostaje modularny, a poszczególne komponenty mają jasno określone zadania.