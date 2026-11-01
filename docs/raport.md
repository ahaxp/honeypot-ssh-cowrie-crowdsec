# Raport końcowy projektu
## Honeypot SSH: Cowrie + CrowdSec
---

## 1. Streszczenie

Celem projektu było zbudowanie i przetestowanie zamkniętej pętli bezpieczeństwa:

**atak → detekcja → decyzja → blokada → analiza**

W środowisku Docker uruchomiono honeypot SSH Cowrie, system detekcji CrowdSec z własnym parserem logów JSON oraz firewall bouncer, który egzekwuje decyzje podejmowane przez CrowdSec. Dodatkowo przygotowano zestaw skryptów Bash wykorzystujących `jq` do analizy zebranych logów oraz statyczny dashboard prezentujący wyniki.

Projekt pozwolił sprawdzić, czy kontrolowany atak brute-force na port 2222 zostanie automatycznie wykryty przez CrowdSec za pomocą scenariusza `crowdsecurity/ssh-bf`, a następnie zablokowany przez bouncer w łańcuchu `DOCKER-USER`.

Ważnym elementem implementacji było opracowanie własnego parsera `local/cowrie-json-logs`, ponieważ standardowa kolekcja `crowdsecurity/sshd` jest przeznaczona do analizy logów SSH w formacie syslog, a Cowrie zapisuje zdarzenia w formacie JSON.

**Słowa kluczowe:** honeypot, Cowrie, CrowdSec, bouncer, SSH, Docker, jq, brute-force, IOC, TTP.

---

## 2. Wprowadzenie

### 2.1. Cel projektu

Głównym celem było zbudowanie izolowanego środowiska laboratoryjnego, które:

1. rejestruje kontrolowane próby ataku na usługę SSH;
2. automatycznie wykrywa wzorce charakterystyczne dla ataków brute-force;
3. podejmuje decyzję o zablokowaniu adresu IP;
4. egzekwuje blokadę na poziomie firewalla;
5. analizuje zebrane dane i prezentuje je w czytelnej formie.

### 2.2. Zakres projektu

Projekt obejmuje następujące elementy:

- **Honeypot SSH:** Cowrie – honeypot średniej interakcji.
- **System detekcji:** CrowdSec – agent oraz Local API (LAPI).
- **Własny parser:** `local/cowrie-json-logs` – obsługa logów JSON generowanych przez Cowrie.
- **Scenariusz detekcji:** `crowdsecurity/ssh-bf`.
- **Egzekutor decyzji:** `crowdsec-firewall-bouncer` – blokowanie ruchu za pomocą iptables.
- **Narzędzie testowe:** Hydra uruchamiana w osobnym kontenerze `attacker`.
- **Analiza danych:** Bash oraz `jq`.
- **Prezentacja wyników:** statyczny dashboard HTML serwowany przez Nginx.
- **Automatyzacja:** skrypty wdrożeniowe i weryfikujące.

### 2.3. Poza zakresem projektu

Projekt ma charakter laboratoryjny. Nie obejmuje:

- wdrożenia produkcyjnego;
- ochrony rzeczywistego serwera produkcyjnego;
- analizy zaawansowanych, ukierunkowanych ataków typu APT;
- długoterminowego monitorowania infrastruktury;
- automatycznego reagowania na wszystkie możliwe rodzaje ataków.

---

## 3. Podstawy teoretyczne – honeypoty

### 3.1. Definicja

**Honeypot** to system-przynęta zaprojektowany w taki sposób, aby przyciągać aktywność potencjalnych atakujących i rejestrować ich działania.

W odróżnieniu od zwykłego serwera honeypot nie powinien obsługiwać legalnych użytkowników. Dzięki temu połączenia i działania wykonywane w jego obrębie mogą być traktowane jako podejrzane.

Honeypoty umożliwiają obserwację technik atakujących, zbieranie wskaźników naruszenia bezpieczeństwa oraz analizę prób uzyskania nieautoryzowanego dostępu.

### 3.2. Typy honeypotów według poziomu interakcji

| Poziom | Charakterystyka | Ryzyko | Ilość zbieranych danych |
|---|---|---|---|
| Niska interakcja | Emulacja wybranych usług, ograniczona możliwość interakcji | Niskie | Mała |
| **Średnia interakcja** | Użytkownik może się zalogować i wykonywać komendy w symulowanym środowisku | Niskie, ale niezerowe | Duża |
| Wysoka interakcja | Wykorzystanie rzeczywistego systemu i usług | Wysokie | Bardzo duża |

W projekcie wykorzystano **Cowrie**, czyli honeypot średniej interakcji. Pozwala on rejestrować próby logowania, wprowadzane komendy oraz inne działania użytkownika w symulowanej powłoce.

Wybór Cowrie stanowi kompromis między ilością zbieranych danych a bezpieczeństwem środowiska. Dodatkową zaletą jest możliwość zapisywania zdarzeń w formacie JSON, który można analizować za pomocą `jq` i przekazywać do CrowdSec.

### 3.3. Zastosowanie honeypotów

Do najważniejszych zastosowań honeypotów należą:

1. **Zbieranie IOC (Indicators of Compromise)** – adresów IP, nazw użytkowników, prób użycia haseł, komend, adresów URL i informacji o pobieranych plikach.
2. **Obserwacja zachowania atakujących** – analiza wykonywanych poleceń i sposobów uzyskiwania dostępu.
3. **Analiza TTP** – porządkowanie technik, taktyk i procedur z wykorzystaniem m.in. katalogu MITRE ATT&CK.
4. **Wczesne wykrywanie aktywności** – identyfikacja podejrzanych połączeń i powtarzających się prób logowania.

### 3.4. Honeypot a system CrowdSec

| Aspekt | Honeypot | Zwykły system chroniony przez CrowdSec |
|---|---|---|
| Główny cel | Obserwacja atakujących | Ochrona świadczonej usługi |
| Użytkownicy | Brak oczekiwanych legalnych użytkowników | Mogą występować legalni użytkownicy |
| Rola | Źródło danych o zagrożeniach | Detekcja i reagowanie |
| Fałszywe alarmy | Zwykle mniejsze ryzyko | Możliwe zablokowanie legalnego użytkownika |

Oba rozwiązania się uzupełniają. Honeypot dostarcza danych o aktywności atakujących, a CrowdSec analizuje zdarzenia i podejmuje decyzje o blokowaniu adresów IP.

### 3.5. Aspekty prawne i etyczne

Projekt działa w kontrolowanym środowisku laboratoryjnym:

- honeypot znajduje się w wydzielonej sieci Docker;
- testy ataków są generowane samodzielnie z kontenera `attacker`;
- projekt nie wykonuje działań odwetowych wobec zewnętrznych systemów;
- hasła zapisane w logach mogą przypominać rzeczywiste dane uwierzytelniające i nie powinny być publikowane bez potrzeby;
- adresy IP mogą stanowić dane osobowe, dlatego ich przetwarzanie i publikowanie wymaga ostrożności.

---

## 4. Architektura systemu

### 4.1. Główna pętla działania

```text
Kontener attacker
       |
       | SSH / brute-force
       v
     Cowrie
       |
       | logi JSON
       v
  Własny parser
       |
       v
    CrowdSec
       |
       | decyzja BAN
       v
    Bouncer
       |
       | reguła DROP
       v
  DOCKER-USER

Cowrie logs
     |
     +------> collect_logs.sh
                    |
                    v
                jq / analiza
                    |
                    v
                collected/
                    |
                    v
          generate_dashboard.sh
                    |
                    v
             site/index.html
                    |
                    v
                  Nginx
```

### 4.2. Komponenty systemu

| Komponent | Rola | Odpowiedzialność |
|---|---|---|
| Cowrie | Honeypot | Przyjmuje połączenia SSH i rejestruje działania użytkowników |
| Własny parser CrowdSec | Parser | Przekształca logi JSON Cowrie na pola rozpoznawane przez CrowdSec |
| CrowdSec | System detekcji | Analizuje zdarzenia i podejmuje decyzje |
| Firewall bouncer | Egzekutor | Pobiera decyzje z LAPI i blokuje adresy IP |
| `collect_logs.sh` | Analiza danych | Przetwarza logi za pomocą `jq` |
| `generate_dashboard.sh` | Wizualizacja | Generuje statyczny dashboard HTML |
| Nginx | Publikacja | Udostępnia dashboard przez HTTP |
| `attacker` | Generator testów | Wykonuje kontrolowane próby logowania |
| `deploy.sh` | Automatyzacja | Uruchamia środowisko i sprawdza gotowość usług |
| `verify_ban.sh` | Weryfikacja | Sprawdza decyzję CrowdSec i rzeczywistą blokadę |
| `enrich_ip.sh` | Wzbogacanie danych | Opcjonalnie pobiera informacje o reputacji adresu IP |

### 4.3. Przepływ danych

1. Kontener `attacker` wykonuje próby logowania SSH na porcie 2222.
2. Cowrie rejestruje zdarzenia i zapisuje je do pliku JSON w katalogu `./cowrie/log`.
3. CrowdSec odczytuje logi przez konfigurację `acquis.yaml`.
4. Własny parser `local/cowrie-json-logs` przetwarza zdarzenia Cowrie i mapuje potrzebne pola.
5. Scenariusz `crowdsecurity/ssh-bf` analizuje nieudane próby logowania.
6. CrowdSec tworzy decyzję o blokadzie adresu IP.
7. Firewall bouncer pobiera decyzję z LAPI i egzekwuje ją w łańcuchu `DOCKER-USER`.
8. `collect_logs.sh` analizuje logi za pomocą `jq`.
9. `generate_dashboard.sh` generuje plik `site/index.html`.
10. Nginx udostępnia dashboard na porcie 8080.

### 4.4. Najważniejsze decyzje projektowe

**Rozdzielenie detekcji od egzekucji**

CrowdSec analizuje zdarzenia i podejmuje decyzję o blokadzie. Bouncer odpowiada za jej wykonanie. Dzięki temu logika detekcji jest oddzielona od mechanizmu egzekwowania decyzji.

**Port 2222 zamiast 22**

Port 22 może być wykorzystywany przez rzeczywistą usługę SSH hosta. W projekcie wykorzystano port 2222, aby uniknąć konfliktu.

**Bind mount zamiast named volume dla logów Cowrie**

Logi Cowrie są udostępniane przez katalog `./cowrie/log`. Dzięki temu można je analizować bezpośrednio z hosta za pomocą `jq`, a CrowdSec może odczytywać ten sam katalog w trybie tylko do odczytu.

**Własny parser logów**

Standardowa kolekcja `crowdsecurity/sshd` jest przeznaczona dla logów SSH w formacie syslog. Cowrie zapisuje zdarzenia jako JSON, dlatego konieczne było przygotowanie własnego parsera `local/cowrie-json-logs`.

**Statyczny dashboard**

Dashboard jest generowany przez Bash i `jq` jako plik HTML. Nie wymaga osobnego backendu ani bazy danych projektu.

---

## 5. Konfiguracja środowiska

### 5.1. Wymagania

Do uruchomienia środowiska potrzebne są:

- system Linux (testowany na Arch Linux);
- Docker;
- Docker Compose v2;
- Git;
- `jq`;
- wolne porty 2222, 8080 i 8081.

### 5.2. Wykorzystane obrazy

| Obraz | Tag | Zastosowanie |
|---|---|---|
| `cowrie/cowrie` | `latest` | Honeypot SSH |
| `crowdsecurity/crowdsec` | `latest` | System detekcji |
| `ghcr.io/shgew/cs-firewall-bouncer-docker` | `stable` | Firewall bouncer |
| `nginx` | `alpine` | Serwer dashboardu |
| `kalilinux/kali-rolling` | `latest` | Kontener testowy |

W projekcie nie przypięto jeszcze digestów SHA256 wszystkich obrazów. Oznacza to, że ponowne pobranie tagu `latest` lub `stable` nie musi zapewnić identycznej wersji obrazu.

### 5.3. Najważniejsze pliki konfiguracyjne

#### Cowrie – `cowrie/cowrie.cfg`

Przykładowe ustawienia tożsamości honeypota:

```ini
[honeypot]
hostname = db-prod-03

[shell]
kernel_version = 5.15.0-91-generic
kernel_build_string = #101-Ubuntu SMP Tue Nov 14 13:30:08 UTC 2023
hardware_platform = x86_64
operating_system = GNU/Linux

[ssh]
version = SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.6

[output_jsonlog]
enabled = true
logfile = var/log/cowrie/cowrie.json
```

#### Cowrie – `cowrie/userdb.txt`

```text
root:x:!*
```

Wpis ten blokuje uwierzytelnienie użytkownika `root` w skonfigurowany sposób i pozwala rejestrować nieudane próby logowania jako `login.failed`.

#### CrowdSec – `crowdsec/acquis.yaml`

```yaml
filenames:
  - /var/log/cowrie/cowrie.json
labels:
  type: cowrie
```

Konfiguracja wskazuje plik logów Cowrie i oznacza zdarzenia etykietą `type: cowrie`.

#### Własny parser – `crowdsec/parsers/s01-parse/cowrie-json-logs.yaml`

Parser `local/cowrie-json-logs` odpowiada za odczyt danych JSON Cowrie i przygotowanie pól wymaganych przez scenariusz CrowdSec.

Jego zadania obejmują:

- filtrowanie zdarzeń oznaczonych jako `cowrie`;
- odczyt danych JSON;
- pobranie adresu źródłowego z pola `src_ip`;
- mapowanie adresu do pola `source_ip`;
- ustawienie `log_type`, w tym `ssh_failed-auth` dla zdarzenia nieudanego logowania;
- przekazanie danych do kolejnych etapów przetwarzania.

W implementacji wykorzystywane jest `UnmarshalJSON(evt.Line.Raw, ...)` do odczytu surowej linii logu.

#### Docker Compose

Poniższy fragment przedstawia najważniejsze elementy konfiguracji. Pełna konfiguracja znajduje się w `docker-compose.yml`.

```yaml
services:
  cowrie:
    image: cowrie/cowrie:latest
    container_name: cowrie
    ports:
      - "2222:2222"
    volumes:
      - ./cowrie/log:/cowrie/cowrie-git/var/log/cowrie
      - ./cowrie/cowrie.cfg:/cowrie/cowrie-git/etc/cowrie.cfg
      - ./cowrie/userdb.txt:/cowrie/cowrie-git/etc/userdb.txt
    networks:
      - honeytrapnet

  crowdsec:
    image: crowdsecurity/crowdsec:latest
    volumes:
      - ./cowrie/log:/var/log/cowrie:ro
      - ./crowdsec/acquis.yaml:/etc/crowdsec/acquis.yaml
      - ./crowdsec/parsers:/etc/crowdsec/parsers
      - crowdsec-db:/var/lib/crowdsec/data
    ports:
      - "127.0.0.1:8081:8080"
    networks:
      - honeytrapnet

  bouncer:
    image: ghcr.io/shgew/cs-firewall-bouncer-docker:stable
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      API_URL: http://127.0.0.1:8081/
      API_KEY: ${CROWDSEC_BOUNCER_API_KEY}
    volumes:
      - ./crowdsec/crowdsec-firewall-bouncer.yaml:/config/crowdsec-firewall-bouncer.yaml:ro

  nginx:
    image: nginx:alpine
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - ./site:/usr/share/nginx/html:ro

  attacker:
    build: ./attacker
    networks:
      - honeytrapnet

networks:
  honeytrapnet:
    driver: bridge

volumes:
  crowdsec-db:
```

**Uwaga:** jest to fragment dokumentacyjny. W przypadku zmian w rzeczywistym `docker-compose.yml` należy zachować zgodność nazw usług, ścieżek, zmiennych środowiskowych i konfiguracji bouncera z plikami repozytorium.

#### Firewall bouncer – `crowdsec/crowdsec-firewall-bouncer.yaml`

Przykładowe ustawienia:

```yaml
mode: iptables
api_url: http://127.0.0.1:8081/
api_key: ${API_KEY}
deny_action: DROP
iptables_chains:
  - INPUT
  - FORWARD
  - DOCKER-USER
```

Klucz API jest przekazywany przez zmienną środowiskową. Nie powinien być umieszczany bezpośrednio w repozytorium.

---

## 6. Implementacja – przebieg prac

### 6.1. Tydzień 1 – przygotowanie projektu

Utworzono repozytorium i podstawowy podział na katalogi odpowiedzialne za konfigurację Cowrie, CrowdSec, kontenery testowe, skrypty, dokumentację i wyniki analizy.

Przygotowano również `.gitignore`, który chroni repozytorium przed przypadkowym dodaniem logów, danych generowanych, plików sekretów i konfiguracji lokalnej.

### 6.2. Tydzień 2 – uruchomienie Cowrie

Uruchomiono kontener Cowrie i udostępniono usługę SSH na porcie 2222.

Logi zostały skonfigurowane jako pliki JSON i udostępnione hostowi przez bind mount `./cowrie/log`.

Skonfigurowano również tożsamość emulowanego systemu, m.in. nazwę hosta, wersję SSH i parametry systemu operacyjnego.

Podczas pierwszych testów ręcznego logowania zaobserwowano zdarzenia takie jak `command.input`, `login.failed` i `login.success`.

**Zaobserwowany adres źródłowy:** `172.19.0.1` – adres bramy sieci Docker w wykonanym teście.

### 6.3. Tydzień 3 – integracja CrowdSec

Uruchomiono CrowdSec i rozpoczęto integrację z logami Cowrie.

Ponieważ standardowa kolekcja `crowdsecurity/sshd` nie obsługiwała bezpośrednio formatu JSON generowanego przez Cowrie, przygotowano własny parser `local/cowrie-json-logs`.

Parser mapuje dane z logów Cowrie do pól wymaganych przez CrowdSec, w szczególności `source_ip` oraz `log_type`.

Dodano również konfigurację `userdb.txt`, aby wymusić rejestrowanie nieudanych prób logowania.

Poprawność przetwarzania sprawdzano za pomocą `cscli metrics` i `cscli explain`.

W testach uzyskano decyzję z następującymi parametrami:

- źródło: `crowdsec`;
- scenariusz: `crowdsecurity/ssh-bf`;
- liczba zdarzeń: 6.

### 6.4. Tydzień 4 – bouncer i rzeczywista blokada

Dodano kontener `attacker`, wykorzystujący Kali Linux i narzędzie Hydra, oraz firewall bouncer.

Początkowo decyzja o banie pojawiała się w CrowdSec, ale ruch do honeypota nadal był możliwy. Również ręczne dodanie reguły `DROP` do `DOCKER-USER` nie rozwiązywało problemu.

Przyczyną było przetwarzanie ruchu w sieci bridge Dockera. Aby reguły iptables mogły filtrować ruch przechodzący przez mostek, konieczne było włączenie `br_netfilter` oraz ustawienie:

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
```

Po wprowadzeniu tej konfiguracji bouncer mógł skutecznie egzekwować decyzje CrowdSec.

### 6.5. Tydzień 5 – analiza logów za pomocą jq

Przygotowano skrypt `collect_logs.sh`, który analizuje logi Cowrie za pomocą `jq` i generuje pliki wynikowe w katalogu `collected/`.

Analiza obejmuje m.in.:

- najczęściej występujące adresy IP;
- podsumowanie zdarzeń;
- najczęściej używane nazwy użytkowników;
- najczęściej używane hasła;
- wykonywane komendy;
- pobierane pliki;
- zestawienie połączeń.

Przykładowa logika zliczania nieudanych logowań według adresu IP:

```bash
jq -s '
  [.[] | select(.eventid=="cowrie.login.failed")]
  | group_by(.src_ip)
  | map({ip: .[0].src_ip, attempts: length})
  | sort_by(-.attempts)
' cowrie.json
```

W jednym z testów wykonano dwa ataki Hydrą po sześć prób. W rezultacie zarejestrowano łącznie 12 zdarzeń `login.failed`.

### 6.6. Tydzień 6 – dashboard i automatyzacja wdrożenia

Przygotowano `generate_dashboard.sh`, który tworzy statyczny dashboard w pliku `site/index.html`.

Dashboard prezentuje m.in. liczbę prób logowania, liczbę unikalnych adresów IP, tabelę najaktywniejszych adresów oraz wykres SVG.

Do publikacji wykorzystano Nginx. Katalog `./site` jest montowany w kontenerze jako `/usr/share/nginx/html` w trybie tylko do odczytu.

Dashboard jest dostępny pod adresem:

`http://localhost:8080`

Przygotowano także `deploy.sh`, który uruchamia środowisko przez Docker Compose, oczekuje na gotowość usług i sprawdza:

- banner SSH Cowrie na porcie 2222;
- dostępność endpointu zdrowia CrowdSec LAPI na porcie 8081.

### 6.7. Tydzień 7 – wzbogacanie danych i weryfikacja bana

Przygotowano opcjonalny skrypt `enrich_ip.sh`, który może wzbogacać informacje o adresach IP za pomocą API AbuseIPDB.

Klucz API jest przechowywany w lokalnym pliku `.env`, a w repozytorium udostępniono szablon `.env.example` bez rzeczywistych sekretów.

Przygotowano również `verify_ban.sh`, który weryfikuje dwa niezależne aspekty:

1. Czy CrowdSec posiada decyzję blokady dla wskazanego adresu IP.
2. Czy połączenie TCP z kontenera `attacker` do Cowrie na porcie 2222 faktycznie nie może zostać nawiązane.

Dzięki temu test nie ogranicza się do sprawdzenia obecności decyzji w CrowdSec, ale obejmuje również rzeczywiste działanie firewalla.

---

## 7. Testy i wyniki

### 7.1. Test 1 – ręczne logowanie do Cowrie

**Cel:** sprawdzenie dostępności honeypota i poprawności rejestrowania zdarzeń.

**Przebieg:** wykonano ręczne połączenie SSH z portem 2222.

**Zaobserwowany wynik:**

- zarejestrowano zdarzenia `command.input`;
- pojawiło się zdarzenie `login.failed`;
- w teście odnotowano również `login.success`.

**Wniosek:** Cowrie przyjmuje połączenia i zapisuje aktywność użytkownika w logach JSON.

*Uwaga: jeżeli test był wykonywany po dodaniu `root:x:!*`, warto potwierdzić, którego konta dotyczyło zdarzenie `login.success`, aby opis był zgodny z konfiguracją `userdb.txt`.*

### 7.2. Test 2 – detekcja brute-force

**Cel:** sprawdzenie, czy CrowdSec wykrywa powtarzające się nieudane próby logowania.

**Przebieg:** wykonano sześć nieudanych prób logowania z jednego adresu IP.

**Wynik:**

- utworzono decyzję typu `ban`;
- źródło decyzji: `crowdsec`;
- scenariusz: `crowdsecurity/ssh-bf`;
- liczba zdarzeń: 6.

**Wniosek:** własny parser poprawnie przekazuje dane do CrowdSec, a scenariusz `crowdsecurity/ssh-bf` wykrywa testowany wzorzec brute-force.

### 7.3. Test 3 – rzeczywista blokada ruchu

**Cel:** sprawdzenie, czy decyzja CrowdSec jest egzekwowana przez firewall.

**Przebieg:**

1. Sprawdzono, czy CrowdSec utworzył decyzję bana.
2. Zweryfikowano działanie połączenia z kontenera `attacker`.
3. Przetestowano ręczną regułę `DROP` w `DOCKER-USER`.
4. Włączono `br_netfilter` i `net.bridge.bridge-nf-call-iptables=1`.
5. Ponowiono test połączenia.

**Wynik:** po włączeniu obsługi filtrowania ruchu bridge przez iptables blokada zaczęła działać.

**Wniosek:** samo utworzenie decyzji w CrowdSec nie gwarantuje jeszcze blokady ruchu. Konieczna jest prawidłowa konfiguracja bouncera i ścieżki filtrowania pakietów Dockera.

### 7.4. Test 4 – analiza logów

**Cel:** sprawdzenie poprawności skryptu `collect_logs.sh`.

**Przebieg:** wykonano dwa ataki Hydrą, każdy obejmujący sześć prób logowania.

**Wynik:**

- łącznie 12 zdarzeń `login.failed`;
- wynik w `top_ips.json` wskazywał 12 prób dla testowanego adresu IP.

Przykładowa struktura wyniku:

```json
{
  "ip": "172.19.0.4",
  "attempts": 12
}
```

**Wniosek:** zastosowane filtry `jq` poprawnie zliczają nieudane próby logowania według adresu IP.

### 7.5. Test 5 – generowanie dashboardu

**Cel:** sprawdzenie poprawności generowania i publikowania dashboardu.

**Przebieg:**

1. Uruchomiono środowisko.
2. Wykonano testowy atak.
3. Uruchomiono `collect_logs.sh`.
4. Uruchomiono `generate_dashboard.sh`.
5. Otworzono dashboard w przeglądarce.

**Wynik:** dashboard wyświetlał liczbę prób logowania, liczbę unikalnych adresów IP, tabelę oraz wykres.

**Wniosek:** dane wygenerowane przez skrypty analityczne mogą być prezentowane w statycznym dashboardzie serwowanym przez Nginx.

### 7.6. Test 6 – weryfikacja bana

**Cel:** potwierdzenie decyzji CrowdSec oraz rzeczywistego zablokowania ruchu.

**Przebieg:** uruchomiono:

```bash
./scripts/verify_ban.sh <IP>
```

Skrypt sprawdza obecność decyzji w CrowdSec, a następnie wykonuje test połączenia TCP z kontenera `attacker` do Cowrie.

**Wynik:** decyzja bana została potwierdzona, a połączenie z zablokowanego adresu nie mogło zostać nawiązane.

W przypadku reguły `DROP` oczekiwanym zachowaniem jest zwykle timeout połączenia, a nie natychmiastowe odrzucenie go przez usługę.

**Wniosek:** test potwierdził zarówno obecność decyzji w CrowdSec, jak i jej egzekwowanie przez firewall bouncer.

### 7.7. Zestawienie trzech przebiegów testowych

W poniższej tabeli należy wpisać wyniki z pomiarów wykonanych podczas testów końcowych.

| Przebieg | Czas wdrożenia | Liczba prób Hydrą | Czas do bana | Wyniki zgodne | Ręczne poprawki |
|---|---:|---:|---:|---|---|
| 1 | [DO UZUPEŁNIENIA] s | 6 | [DO UZUPEŁNIENIA] s | [tak/nie] | [tak/nie] |
| 2 | [DO UZUPEŁNIENIA] s | 6 | [DO UZUPEŁNIENIA] s | [tak/nie] | [tak/nie] |
| 3 | [DO UZUPEŁNIENIA] s | 6 | [DO UZUPEŁNIENIA] s | [tak/nie] | [tak/nie] |

### 7.8. Metryki zbiorcze

| Metryka | Wartość |
|---|---|
| Czas reakcji od pierwszej próby do decyzji | [DO UZUPEŁNIENIA] s |
| Czas od decyzji do egzekucji przez bouncer | Około 10–12 s – wartość zaobserwowana w testach |
| Skuteczność blokady po włączeniu `br_netfilter` | 100% w wykonanych testach |
| Liczba prób do uzyskania bana | 6 w opisanym teście |
| Czas trwania bana | 4 h – zgodnie z konfiguracją profilu |

Wartości czasowe należy traktować jako wyniki środowiska laboratoryjnego, a nie gwarantowane parametry działania systemu.

### 7.9. Przykładowe logi i wyniki

Przykładowe zdarzenie `login.failed` z logu Cowrie:

```json
{
  "eventid": "cowrie.login.failed",
  "username": "root",
  "password": "123456",
  "src_ip": "172.19.0.4",
  "session": "a1b2c3",
  "timestamp": "2026-10-06T09:14:02.113Z"
}
```

Przykładowy wynik `cscli decisions list`:

```text
┌────┬──────────┬──────────────────────┬──────────┬──────────┬────────┐
│ ID │ Source   │ Scope:Value          │ Action   │ Duration │ Events │
├────┼──────────┼──────────────────────┼──────────┼──────────┼────────┤
│ 1  │ crowdsec │ Ip:172.19.0.4        │ ban      │ 3h59m    │ 6      │
└────┴──────────┴──────────────────────┴──────────┴──────────┴────────┘
```

Przykładowy wynik weryfikacji:

```text
[OK] IP 172.19.0.4 jest zbanowane
[+] Test TCP z kontenera attacker do cowrie:2222
[OK] Polaczenie nie zostalo nawiazane (timeout)
```

Powyższe fragmenty mają charakter przykładowy. Przed oddaniem raportu należy upewnić się, że adresy IP, czasy i identyfikatory odpowiadają rzeczywistym zrzutom z testów.

---

## 8. Napotkane problemy i sposoby ich rozwiązania

| Lp. | Problem | Przyczyna | Rozwiązanie |
|---:|---|---|---|
| 1 | `volumes must be a mapping` | Błąd składni w YAML, m.in. literówka w nazwie sterownika sieci | Poprawienie konfiguracji i weryfikacja przez `docker compose config` |
| 2 | `Failed to load output engine: json` | Nieprawidłowa nazwa silnika wyjściowego w konfiguracji Cowrie | Zastosowanie sekcji `[output_jsonlog]` |
| 3 | `PermissionError` przy zapisie `cowrie.json` | Katalog logów miał nieprawidłowego właściciela; Cowrie działa z UID 999 | Dostosowanie uprawnień, np. `chown -R 999:999 cowrie/log` |
| 4 | Brak oczekiwanych zdarzeń `login.failed` | Konfiguracja użytkownika pozwalała na uwierzytelnienie | Dodanie `userdb.txt` z wpisem `root:x:!*` |
| 5 | Błędne pole `soruce_ip` zamiast `source_ip` | Literówka w parserze | Poprawienie mapowania i sprawdzenie przez `cscli explain` |
| 6 | Whitelist ignorował adresy z zakresu 172.x | Działanie parsera whitelist w środowisku laboratoryjnym | Dostosowanie konfiguracji parserów na potrzeby testów |
| 7 | Ban pojawiał się w CrowdSec, ale ruch nadal przechodził | Bouncer nie filtrował właściwej ścieżki ruchu Dockera | Dodanie `DOCKER-USER` do obsługiwanych łańcuchów |
| 8 | Reguła `DROP` nie blokowała ruchu kontener–kontener | Brak filtrowania ruchu bridge przez iptables | Włączenie `br_netfilter` i `bridge-nf-call-iptables=1` |
| 9 | `br_netfilter` przestawał działać po restarcie | Zmiany wykonane przez `modprobe` i `sysctl -w` nie były trwałe | Przygotowanie trwałej konfiguracji modułu i sysctl |
| 10 | Błąd `No such file` w skrypcie | Nieprawidłowy tekst pozostał w pliku skryptu | Usunięcie zbędnego tekstu i ponowna weryfikacja |
| 11 | Nginx zwracał 403 | Brak pliku `index.html` w katalogu `site/` | Uruchomienie `generate_dashboard.sh` |
| 12 | `Permission denied` przy generowaniu dashboardu | Katalog `site/` należał do roota | Poprawienie właściciela katalogu |
| 13 | `decisions delete --all` usunęło wiele decyzji | Polecenie objęło również decyzje pochodzące z list społecznościowych | Rozróżnianie decyzji własnych od pozostałych przed ich usuwaniem |
| 14 | Klucz API znalazł się w `docker-compose.yml` | Nieprawidłowe przechowywanie sekretów | Przeniesienie klucza do `.env`, dodanie `.env.example` i reguł `.gitignore` |
| 15 | Skrypt nie widział zmiennej po `source .env` | Zmienna nie była eksportowana do środowiska procesu | Użycie `set -a`, `source .env`, `set +a` |

---

## 9. Ograniczenia projektu

1. **Ograniczenia Cowrie.** Cowrie jest honeypotem średniej interakcji, a nie rzeczywistym systemem operacyjnym. Doświadczony atakujący może rozpoznać emulację na podstawie niespójności środowiska, dostępnych poleceń lub zawartości plików systemowych.

2. **Zakres detekcji.** CrowdSec wykrywa wzorce opisane w zainstalowanych scenariuszach. Aktywność, która nie pasuje do żadnego z nich, może zostać zapisana w logach bez wygenerowania decyzji o blokadzie.

3. **Ograniczona reprezentatywność danych.** Wyniki pochodzą z kontrolowanych testów i ograniczonego okresu obserwacji. Nie stanowią statystycznego obrazu wszystkich ataków SSH.

4. **Statyczny dashboard.** Dashboard nie aktualizuje się automatycznie w czasie rzeczywistym. Wymaga ponownego uruchomienia skryptów generujących dane i stronę.

5. **Wzbogacanie reputacji IP.** Dane z AbuseIPDB są dodatkową wskazówką, a nie dowodem złośliwej aktywności. Prywatne adresy IP używane w sieci laboratoryjnej nie dostarczają wiarygodnego wyniku reputacyjnego.

6. **Trwałość konfiguracji firewalla.** Ustawienia `br_netfilter` i `net.bridge.bridge-nf-call-iptables` wymagają trwałego zapisania w konfiguracji systemu, aby były dostępne również po restarcie hosta.

7. **Powtarzalność obrazów.** W projekcie nie przypięto wszystkich obrazów do digestów SHA256. Tagi takie jak `latest` mogą wskazywać różne wersje w kolejnych wdrożeniach.

---

## 10. Wnioski

1. **Zamknięta pętla bezpieczeństwa działa.** Kontrolowany atak brute-force prowadzi do wygenerowania decyzji CrowdSec, a następnie do rzeczywistego zablokowania ruchu przez firewall bouncer.

2. **Rozdzielenie detekcji i egzekucji jest istotne.** CrowdSec odpowiada za analizę i podejmowanie decyzji, natomiast bouncer za ich wykonanie. Taki podział ułatwia zmianę mechanizmu blokowania bez przebudowy logiki detekcji.

3. **Własny parser był konieczny do integracji.** Standardowa kolekcja `crowdsecurity/sshd` nie obsługiwała bezpośrednio formatu JSON Cowrie. Przygotowanie parsera `local/cowrie-json-logs` umożliwiło przekazanie danych do scenariusza `crowdsecurity/ssh-bf`.

4. **Integracja Dockera z firewallem wymaga uwzględnienia ruchu bridge.** Samo utworzenie decyzji bana nie gwarantuje blokady. Konieczne było włączenie `br_netfilter` oraz prawidłowe skonfigurowanie łańcucha `DOCKER-USER`.

5. **Analiza logów może być realizowana prostymi narzędziami.** Bash i `jq` wystarczyły do przygotowania zestawień adresów IP, użytkowników, haseł, komend i połączeń.

6. **Statyczny dashboard jest wystarczający do prezentacji wyników projektu.** Generowanie HTML i SVG pozwoliło przedstawić najważniejsze dane bez konieczności budowania osobnego backendu.

7. **Weryfikacja powinna obejmować rzeczywisty ruch.** Sprawdzenie decyzji w CrowdSec nie wystarcza. Dopiero test połączenia z kontenera `attacker` pozwala potwierdzić, że blokada działa również na poziomie sieci.

### 10.1. Możliwe kierunki rozwoju

- Dodanie scenariuszy wykrywających podejrzane polecenia, np. użycie `wget` lub `curl` do pobierania plików.
- Automatyczne odświeżanie dashboardu, np. za pomocą harmonogramu `cron`.
- Trwałe zapisanie konfiguracji `br_netfilter`.
- Przypięcie obrazów Docker do digestów SHA256.
- Dodanie powiadomień o nowych decyzjach bana, np. przez webhook.
- Prowadzenie obserwacji przez dłuższy okres i porównanie wyników z kolejnych dni.

---

## 11. Załączniki

### A. Repozytorium

[adres GitHub]

### B. Zrzuty ekranu

Do raportu należy dołączyć:

1. [DO UZUPEŁNIENIA: zrzut dashboardu z tabelą top IP]
2. [DO UZUPEŁNIENIA: wynik `cscli decisions list` z decyzją bana]
3. [DO UZUPEŁNIENIA: wynik `iptables` pokazujący regułę blokującą]
4. [DO UZUPEŁNIENIA: wynik działania `verify_ban.sh`]

### C. Wideo demonstracyjne

[DO UZUPEŁNIENIA: link do pliku lub lokalizacja nagrania]

### D. Słownik pojęć

| Pojęcie | Znaczenie |
|---|---|
| Honeypot | System-przynęta służący do obserwacji aktywności atakujących |
| IOC | Wskaźnik naruszenia bezpieczeństwa, np. adres IP, hash lub URL |
| TTP | Taktyki, techniki i procedury wykorzystywane przez atakujących |
| MITRE ATT&CK | Baza wiedzy o taktykach i technikach ataków |
| Parser | Komponent przekształcający surowe logi w ustrukturyzowane pola |
| Scenariusz | Reguła wykrywająca określony wzorzec aktywności |
| Leaky bucket | Model ograniczania zdarzeń w określonym przedziale czasu |
| LAPI | Local API CrowdSec, udostępniające m.in. decyzje systemu |
| Bouncer | Komponent egzekwujący decyzje CrowdSec |
| DOCKER-USER | Łańcuch iptables przeznaczony na własne reguły filtrowania ruchu Dockera |
| br_netfilter | Moduł jądra umożliwiający filtrowanie ruchu mostków przez mechanizmy netfilter |
| Bind mount | Udostępnienie katalogu hosta wewnątrz kontenera |
| `@html` | Filtr `jq` kodujący znaki specjalne w tekście przeznaczonym do HTML |
| JSON Lines | Format, w którym każdy wiersz zawiera osobny obiekt JSON |
| `jq -s` | Tryb jq wczytujący całe wejście jako jedną tablicę |
| Digest | Skrót SHA256 identyfikujący konkretny obraz kontenera |

---

## 12. Bibliografia

1. Dokumentacja Cowrie: https://github.com/cowrie/cowrie
2. Dokumentacja CrowdSec: https://docs.crowdsec.net/
3. CrowdSec Hub: https://hub.crowdsec.net/
4. MITRE ATT&CK: https://attack.mitre.org/
5. Dokumentacja AbuseIPDB API: https://docs.abuseipdb.com/
6. Dokumentacja Docker: https://docs.docker.com/
7. Podręcznik jq: https://jqlang.org/manual/

---