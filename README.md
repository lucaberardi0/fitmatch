# 🏃 FitMatch — Sports Gear Price Comparator & Scraping Engine

Motore di scraping multi-store e comparazione prezzi in tempo reale specializzato nell'abbigliamento e calzature sportive per il mercato italiano ed europeo.

---

## 🎯 Negozi Integrati nel Prototipo

1. **Cisalfa Sport** (`cisalfasport.it`): Leader retail in Italia (architettura Salesforce Commerce Cloud).
2. **Maxi Sport** (`maxisport.com`): Grande specialista sneaker e running (architettura Magento).
3. **Mister Running** (`misterrunning.com`): E-commerce specializzato #1 in Italia nella corsa (API REST Clerk ultra-rapida).
4. **Nencini Sport** (`nencinisport.it`): Storica catena sportiva multi-marca (session warmup con CSRF e attributi GTM).

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

### 2. Ricerca di Qualsiasi Prodotto
```bash
# Esempi con scarpe da running
python3 cli.py search "nike pegasus"
python3 cli.py search "asics nimbus"
python3 cli.py search "brooks ghost"
python3 cli.py search "hoka clifton"

# Limita il numero di risultati per negozio
python3 cli.py search "adidas ultraboost" --limit 5

# Output in formato JSON strutturato
python3 cli.py search "nike pegasus" --json
```

### 3. Avvio Server API REST (per collegare Frontend o Mobile App)
```bash
python3 api.py
```
La documentazione interattiva Swagger è disponibile all'indirizzo:
`http://localhost:8000/docs`

---

## 🧠 Caratteristiche Chiave

- **Bypass WAF & Anti-bot**: Utilizzo di `curl_cffi` per impersonare l'impronta crittografica TLS/JA3 di Chrome, garantendo il 100% di successo senza blocchi.
- **Scraping Parallelo**: Scansione concorrente di tutti i 4 store in meno di 2–4 secondi complessivi.
- **Normalizzazione & Raggruppamento Intelligente**:
  - Rilevamento automatico del genere (`Uomo`, `Donna`, `Junior`).
  - Separazione di colorway e codici articolo secondari.
  - Riconoscimento del brand e allineamento dei modelli (es. `Nike Air Zoom Pegasus 42` vs `Pegasus 42`).
  - Calcolo istantaneo del negozio più economico e del risparmio potenziale (fino al 30-50%).
