# 🏃 FitMatch — Sports Gear Price Comparator & Scraping Engine

Motore di scraping multi-store e comparazione prezzi in tempo reale specializzato nell'abbigliamento e calzature sportive per il mercato italiano ed europeo.

---

## 🎯 Negozi Integrati nel Prototipo (8 Partner Stores)

1. **Cisalfa Sport** (`cisalfasport.it`): Leader retail in Italia (architettura Salesforce Commerce Cloud).
2. **Maxi Sport** (`maxisport.com`): Grande specialista sneaker, running e sportswear (architettura Magento).
3. **Mister Running** (`misterrunning.com`): E-commerce specializzato #1 in Italia nella corsa (API REST Clerk ultra-rapida).
4. **Nencini Sport** (`nencinisport.it`): Storica catena sportiva multi-marca (session warmup con CSRF e attributi GTM).
5. **Top4Running** (`top4running.it`): Gigante europeo specializzato nella corsa (API Luigi's Box ad alte prestazioni).
6. **Running Warehouse Europe** (`runningwarehouse.eu`): Store globale leader nel running (prezzi EUR con IVA italiana e catalogo GTM).
7. **Deporvillage** (`deporvillage.it`): Leader Sud Europa in outdoor, ciclismo, elettronica Garmin/Polar, occhiali tecnici Oakley e nutrizione (API Algolia ad alta velocità).
8. **Alltricks** (`alltricks.it` — Gruppo Decathlon): Gigante europeo per ciclismo, trail, GPS, caschi, recupero e fitness gear (API Constructor.io).

---

## 🎒 Categorie di Prodotti & Accessori Coperte

* 👟 **Scarpe & Sneakers**: Running su asfalto, trail running, gara/piastra in carbonio, daily trainer, camminata.
* ⌚ **Smartwatch & GPS**: Garmin (Forerunner, Fenix, Edge), Polar, Suunto, ciclocomputer, fasce cardio HRM.
* 🎒 **Zaini & Idratazione**: Gilet trail running Salomon (Active Skin, ADV Skin), CamelBak, borracce soft flask.
* 🕶️ **Ottica & Occhiali Tecnici**: Oakley (Radar EV, Sutro, Jawbreaker), Bliz, Rudy Project, lenti fotocromatiche/Prizm.
* 🏋️ **Fitness & Recupero Muscolare**: Pistole massaggianti a percussione Theragun/Therabody, rulli, elastici, loop bands.
* ⚡ **Nutrizione Sportiva**: Gel energetici, barrette proteiche, sali minerali e carboidrati (Enervit, SiS, Maurten).
* 🚴 **Ciclismo & Attrezzatura**: Caschi (POC, Abus, Kask), borse bici, accessori padel e tennis.

---

## 🏗️ Architettura del Sistema

```
fitmatch/
├── fitmatch/
│   ├── models.py              # Schemi Pydantic (Offer, MatchedProductGroup, SearchResult)
│   ├── service.py             # Servizio centrale di comparazione e cache
│   ├── scrapers/
│   │   ├── base.py            # Classe astratta BaseScraper con browser impersonation e parser prezzi
│   │   ├── cisalfa.py         # Scraper Cisalfa Sport
│   │   ├── maxisport.py       # Scraper Maxi Sport
│   │   ├── misterrunning.py   # Scraper Mister Running (Clerk API)
│   │   ├── nencini.py         # Scraper Nencini Sport (con session warmup)
│   │   ├── top4running.py     # Scraper Top4Running (Luigi's Box API)
│   │   ├── runningwarehouse.py# Scraper Running Warehouse Europe (VAT IT + GTM)
│   │   └── registry.py        # Esecuzione parallela multi-thread (ThreadPoolExecutor)
│   └── matcher/
│       └── normalizer.py      # Entity resolution, estrazione brand, rimozione rumore e raggruppamento
├── cli.py                     # Interfaccia a riga di comando a colori
├── api.py                     # API REST FastAPI pronta per il frontend
├── requirements.txt
└── data/cache/                # Cache locale dei risultati di ricerca
```

---

## 🚀 Utilizzo Rapido

### 1. Test Demo Immediato
Esegue una ricerca istantanea su tutti i 4 negozi contemporaneamente:
```bash
python3 cli.py demo
```

### 2. Ricerca di Qualsiasi Prodotto o Accessorio
```bash
# Scarpe da running
python3 cli.py search "nike pegasus"
python3 cli.py search "asics nimbus"

# Smartwatch, GPS & Ciclocomputer
python3 cli.py search "garmin edge"
python3 cli.py search "polar vantage"

# Occhiali sportivi & Zaini idratazione
python3 cli.py search "oakley radar"
python3 cli.py search "salomon active skin"

# Attrezzatura fitness, recupero e nutrizione
python3 cli.py search "theragun"
python3 cli.py search "enervit gel"

# Limita il numero di risultati per negozio o output in JSON strutturato
python3 cli.py search "garmin" --limit 3 --json
```

### 3. Avvio Server API REST (per collegare Frontend o Mobile App)
```bash
python3 api.py
```
La documentazione interattiva Swagger è disponibile all'indirizzo:
`http://localhost:8000/docs`

All'avvio dell'API, il demone di background (`SyncScheduler`) si attiva automaticamente per monitorare i prezzi ogni 2 ore e sincronizzare il catalogo.

### 4. Demone Autonomo 24/7 (Worker Indipendente)
Puoi avviare il demone orchestratore dedicato (ideale per systemd o Docker):
```bash
# Avvio continuo con monitor prezzi ogni 2h e scoperta catalogo ogni 24h
python3 cli.py worker

# Avvio con esecuzione immediata del primo ciclo
python3 cli.py worker --immediate --refresh-hours 1.5

# Controllo dello stato dello scheduler da riga di comando
python3 cli.py scheduler --status
```

### 5. Scansione Approfondita & Indicizzazione Massiva
```bash
# Scansione di un singolo store con limite personalizzato
python3 cli.py crawl --store deporvillage --limit 500
python3 cli.py crawl --store cisalfa --limit 300

# Scansione massiva di tutti i 9 negozi contemporaneamente
python3 cli.py crawl --limit 500
```

---

## 🧠 Caratteristiche Chiave

- **Bypass WAF & Anti-bot**: Utilizzo di `curl_cffi` per impersonare l'impronta crittografica TLS/JA3 di Chrome, garantendo il 100% di successo senza blocchi.
- **Scraping Parallelo**: Scansione concorrente di tutti i 4 store in meno di 2–4 secondi complessivi.
- **Normalizzazione & Raggruppamento Intelligente**:
  - Rilevamento automatico del genere (`Uomo`, `Donna`, `Junior`).
  - Separazione di colorway e codici articolo secondari.
  - Riconoscimento del brand e allineamento dei modelli (es. `Nike Air Zoom Pegasus 42` vs `Pegasus 42`).
  - Calcolo istantaneo del negozio più economico e del risparmio potenziale (fino al 30-50%).
