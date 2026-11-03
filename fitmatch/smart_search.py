import os
import json
import logging
import re
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from fitmatch.cache_manager import SearchCacheManager

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

logger = logging.getLogger("fitmatch.smart_search")

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "meta-llama/llama-3.3-70b-instruct")
OPENROUTER_BACKUP_MODEL = "meta-llama/llama-3.1-8b-instruct"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


class SmartSearchChip(BaseModel):
    id: str
    label: str
    param_key: str
    value: str


class CuratedSectionDef(BaseModel):
    id: str
    title: str
    subtitle: str
    keywords: List[str] = Field(default_factory=list)


class SpotlightDef(BaseModel):
    target_keyword: str
    badge_text: str = "Miglior Scelta"
    highlights: List[str] = Field(default_factory=list)


class SmartSearchIntent(BaseModel):
    raw_query: str
    search_mode: str = "deep_dive"  # "deep_dive" | "classic"
    is_deep_dive: bool = True
    conversational_header: str = "Ho cercato prodotti"
    conversational_summary: str = ""
    target_keywords: List[str] = Field(default_factory=list)
    brand: Optional[str] = None
    category: Optional[str] = None
    gender: Optional[str] = None
    max_price: Optional[float] = None
    min_price: Optional[float] = None
    size: Optional[str] = None
    features: List[str] = Field(default_factory=list)
    explanation: str = ""
    chips: List[SmartSearchChip] = Field(default_factory=list)
    curated_sections: List[CuratedSectionDef] = Field(default_factory=list)
    spotlight: Optional[SpotlightDef] = None
    follow_up_suggestions: List[str] = Field(default_factory=list)
    source: str = "local_heuristic"


# Sports domain knowledge base for athletic gear and running
SPORTS_KNOWLEDGE = {
    "max_cushion": {
        "models": ["asics nimbus", "hoka bondi", "brooks glycerin", "hoka clifton", "new balance 1080", "saucony triumph"],
        "label": "Massimo Ammortizzamento & Protezione",
        "category": "running_shoes",
        "description": "Scarpe con massima protezione d'impatto per correre su asfalto, ideali per proteggere ginocchia, articolazioni e per pesi medi/elevati.",
        "sections": [
            {
                "id": "sec_max_cushion",
                "title": "Massimo Ammortizzamento",
                "subtitle": "Le scarpe con la suola più protettiva per correre su asfalto e proteggere le articolazioni.",
                "keywords": ["nimbus", "bondi"]
            },
            {
                "id": "sec_daily_cushion",
                "title": "Daily Trainer Confortevoli",
                "subtitle": "Morbide e versatili per tutti gli allenamenti quotidiani e lunghe distanze.",
                "keywords": ["glycerin", "clifton", "1080"]
            }
        ],
        "spotlight": {
            "target_keyword": "nimbus",
            "badge_text": "Miglior Scelta",
            "highlights": [
                "Tecnologia PureGEL per massimo assorbimento degli urti",
                "Intersuola protettiva per ginocchia e schiena",
                "Miglior prezzo confrontato tra più negozi partner"
            ]
        },
        "follow_ups": [
            "Mostrami modelli sotto 140 euro",
            "Confronta Asics Nimbus e Hoka Bondi",
            "Mostrami scarpe disponibili in taglia 43"
        ]
    },
    "daily_trainer": {
        "models": ["nike pegasus", "brooks ghost", "asics cumulus", "saucony ride", "mizuno wave rider"],
        "label": "Daily Trainer Polivalente",
        "category": "running_shoes",
        "description": "Scarpe versatili e resistenti per tutti gli allenamenti quotidiani su asfalto a ritmo medio.",
        "sections": [
            {
                "id": "sec_iconic_trainers",
                "title": "Modelli Più Venduti & Polivalenti",
                "subtitle": "Il punto di riferimento per chilometraggi quotidiani e durata eccezionale.",
                "keywords": ["pegasus", "ghost"]
            },
            {
                "id": "sec_comfort_trainers",
                "title": "Comfort & Flessibilità Quotidiana",
                "subtitle": "Calzata morbida per corse facili, camminate e ritmi medi.",
                "keywords": ["cumulus", "wave rider", "ride"]
            }
        ],
        "spotlight": {
            "target_keyword": "pegasus",
            "badge_text": "Icona Daily",
            "highlights": [
                "Unità Air Zoom per ammortizzazione reattiva",
                "Tomaia in engineered mesh traspirante",
                "Prezzo competitivo disponibile in più store"
            ]
        },
        "follow_ups": [
            "Confronta Nike Pegasus e Brooks Ghost",
            "Mostrami Daily Trainer sotto 100 euro",
            "Filtra per taglia 42.5"
        ]
    },
    "speed_race": {
        "models": ["nike alphafly", "nike vaporfly", "nike zoom fly", "nike streakfly", "adidas adizero", "asics metaspeed", "asics magic speed", "saucony endorphin", "brooks hyperion", "hoka cielo"],
        "label": "Velocità & Gara",
        "category": "running_shoes",
        "description": "Modelli leggeri e reattivi con schiuma performante e/o piastra in carbonio per ritmo veloce e gare.",
        "sections": [
            {
                "id": "sec_carbon_race",
                "title": "Super Scarpe con Piastra in Carbonio",
                "subtitle": "Massimo ritorno energetico e propulsione per maratona e record personali.",
                "keywords": ["alphafly", "vaporfly", "metaspeed", "adizero"]
            },
            {
                "id": "sec_fast_tempo",
                "title": "Scarpe Veloci & Allenamento a Ritmo",
                "subtitle": "Reattività e leggerezza per ripetute, medi veloci e gare fino alla mezza.",
                "keywords": ["zoom fly", "streakfly", "magic speed", "hyperion"]
            }
        ],
        "spotlight": {
            "target_keyword": "alphafly",
            "badge_text": "Scelta Record",
            "highlights": [
                "Piastra in fibra di carbonio a tutta lunghezza",
                "Doppia capsula Zoom Air per spinta esplosiva",
                "Miglior offerta multi-store tracciata"
            ]
        },
        "follow_ups": [
            "Confronta Nike Alphafly e Vaporfly",
            "Mostrami scarpe con piastra sotto 180 euro",
            "Filtra per taglia 43"
        ]
    },
    "trail_running": {
        "models": ["hoka speedgoat", "salomon xa pro", "brooks cascadia", "asics trabuco", "la sportiva", "salomon pulsar"],
        "label": "Trail Running & Sterrato",
        "category": "running_shoes",
        "description": "Scarpe con tasselli e suola artigliata per sentieri, fango, sassi e montagna.",
        "sections": [
            {
                "id": "sec_grip_trail",
                "title": "Aderenza Tecnica & Fango",
                "subtitle": "Suole Vibram e tassellatura aggressiva per percorsi sconnessi.",
                "keywords": ["speedgoat", "salomon", "trabuco"]
            },
            {
                "id": "sec_mountain_protect",
                "title": "Protezione Alpina & Stabilità",
                "subtitle": "Tomaia rinforzata anti-roccia e stabilità per sentieri di montagna.",
                "keywords": ["cascadia", "la sportiva", "xa pro"]
            }
        ],
        "spotlight": {
            "target_keyword": "speedgoat",
            "badge_text": "Top Trail",
            "highlights": [
                "Battistrada Vibram Megagrip ad altissima aderenza",
                "Protezione rinforzata su avampiede e tallone",
                "Prezzo confrontato tra 12 store partner"
            ]
        },
        "follow_ups": [
            "Mostrami modelli da trail in Gore-Tex",
            "Confronta Hoka Speedgoat e Brooks Cascadia",
            "Mostrami scarpe da trail sotto 120 euro"
        ]
    },
    "gps_watch": {
        "models": ["garmin forerunner 165", "garmin forerunner 265", "garmin forerunner 965", "garmin forerunner", "garmin fenix", "garmin edge", "garmin instinct", "polar vantage", "polar grit", "suunto"],
        "label": "GPS & Smartwatch",
        "category": "gps_watch",
        "description": "Dispositivi GPS, cardiofrequenzimetri e ciclocomputer per il monitoraggio della performance atletica.",
        "sections": [
            {
                "id": "sec_running_gps",
                "title": "Orologi Specifici per Corsa & Fitness",
                "subtitle": "Leggeri con display AMOLED, metriche di passo, frequenza e VO2 max.",
                "keywords": ["forerunner 165", "forerunner 265", "forerunner"]
            },
            {
                "id": "sec_outdoor_gps",
                "title": "Outdoor, Triathlon & Mappe Topografiche",
                "subtitle": "Costruzione ultra-robusta, ricarica solare e cartografia offline.",
                "keywords": ["fenix", "instinct", "vantage", "edge"]
            }
        ],
        "spotlight": {
            "target_keyword": "forerunner 165",
            "badge_text": "Best Buy GPS",
            "highlights": [
                "Display AMOLED ultra nitido e sensore cardio al polso",
                "Fino a 11 giorni di autonomia in modalità smartwatch",
                "Miglior prezzo garantito tra i rivenditori ufficiali"
            ]
        },
        "follow_ups": [
            "Confronta Garmin Forerunner 165 e 265",
            "Mostrami orologi con mappe cartografiche",
            "Filtra smartwatch sotto 250 euro"
        ]
    },
    "eyewear": {
        "models": ["oakley radar", "oakley sutro", "oakley jawbreaker", "bliz", "rudy project", "smith"],
        "label": "Occhiali Tecnici",
        "category": "eyewear",
        "description": "Occhiali sportivi con lenti Prizm o fotocromatiche per running, ciclismo e outdoor.",
        "sections": [
            {
                "id": "sec_cycling_eyewear",
                "title": "Ampio Campo Visivo & Protezione Vento",
                "subtitle": "Maschere aerodinamiche per ciclismo e running ad alta velocità.",
                "keywords": ["sutro", "jawbreaker"]
            },
            {
                "id": "sec_performance_eyewear",
                "title": "Leggerezza & Lenti Prizm Contrasto",
                "subtitle": "Montature ultraleggere che non scivolano nemmeno col sudore intenso.",
                "keywords": ["radar", "bliz", "rudy"]
            }
        ],
        "spotlight": {
            "target_keyword": "sutro",
            "badge_text": "Icona Stile & Bici",
            "highlights": [
                "Lenti Prizm per ottimizzare dettagli e contrasti",
                "Copertura avvolgente contro vento e raggi UV",
                "Prezzo competitivo confrontato in tempo reale"
            ]
        },
        "follow_ups": [
            "Mostrami occhiali con lenti fotocromatiche",
            "Confronta Oakley Sutro e Radar EV",
            "Filtra occhiali tecnici sotto 120 euro"
        ]
    },
    "hydration": {
        "models": ["salomon active skin", "salomon adv skin", "camelbak", "borraccia soft flask"],
        "label": "Zaini & Idratazione",
        "category": "hydration",
        "description": "Gilet ergonomici traspiranti e borracce morbide per autosufficienza in corsa.",
        "sections": [
            {
                "id": "sec_trail_vests",
                "title": "Gilet Ergonomici da Trail",
                "subtitle": "Tasche frontali per flask e vestibilità a maglia traspirante senza rimbalzi.",
                "keywords": ["active skin", "adv skin"]
            },
            {
                "id": "sec_bottles_gear",
                "title": "Borracce Morbide & Sacche Idriche",
                "subtitle": "Soluzioni ultraleggere per idratazione rapida in movimento.",
                "keywords": ["flask", "camelbak", "borraccia"]
            }
        ],
        "spotlight": {
            "target_keyword": "active skin",
            "badge_text": "Miglior Comfort",
            "highlights": [
                "Vestibilità Sensifit che si adatta al busto senza rimbalzi",
                "Include 2 borracce morbide da 500ml",
                "Miglior prezzo tra i negozi specializzati outdoor"
            ]
        },
        "follow_ups": [
            "Confronta Salomon Active Skin 4 e 8",
            "Mostrami borracce morbide 500ml",
            "Filtra gilet idratazione sotto 80 euro"
        ]
    },
    "fitness": {
        "models": ["theragun", "therabody", "pistola massaggiante", "compex"],
        "label": "Fitness & Recupero",
        "category": "fitness",
        "description": "Dispositivi per massaggio percussivo e recupero muscolare post-allenamento.",
        "sections": [
            {
                "id": "sec_percussive",
                "title": "Dispositivi per Massaggio Percussivo",
                "subtitle": "Allentamento rapido di tensioni e contratture muscolari post-corsa.",
                "keywords": ["theragun", "pistola", "therabody"]
            }
        ],
        "spotlight": {
            "target_keyword": "theragun",
            "badge_text": "Top Recupero",
            "highlights": [
                "Trattamento percussivo profondo per allentare i muscoli",
                "Design ergonomico e portatile da borsa sportiva",
                "Confronto offerte su store specializzati"
            ]
        },
        "follow_ups": [
            "Confronta Theragun Mini e Prime",
            "Mostrami accessori di recupero sotto 150 euro"
        ]
    },
    "nutrition": {
        "models": ["enervit gel", "enervit", "sis go", "maurten", "isocarb", "226ers"],
        "label": "Nutrizione Sportiva",
        "category": "nutrition",
        "description": "Gel isotonici, maltodestrine ed elettroliti per energia immediata e prevenzione crampi.",
        "sections": [
            {
                "id": "sec_gels",
                "title": "Gel Energetici & Isotonici",
                "subtitle": "Carboidrati a rapido assorbimento per allenamenti e maratone.",
                "keywords": ["enervit", "gel", "sis", "maurten"]
            }
        ],
        "spotlight": {
            "target_keyword": "enervit",
            "badge_text": "Energia Corsa",
            "highlights": [
                "Formula isotonica delicata sullo stomaco",
                "Apporto energetico immediato per distanze lunghe",
                "Miglior prezzo per box multipack"
            ]
        },
        "follow_ups": [
            "Mostrami integratori senza caffeina",
            "Filtra gel e maltodestrine sotto 30 euro"
        ]
    },
    "padel": {
        "models": ["bullpadel hack", "bullpadel vertex", "nox at10", "babolat technical viper", "head speed pro", "siux diablo", "kuikma"],
        "label": "Padel & Racchette",
        "category": "padel",
        "description": "Racchette da padel, scarpe con suola a spiga, borse e accessori per il campo.",
        "sections": [
            {
                "id": "sec_power_padel",
                "title": "Racchette Potenza & Attacco",
                "subtitle": "Forma a diamante e bilanciamento alto per smash e colpi vincenti.",
                "keywords": ["hack", "vertex", "viper"]
            },
            {
                "id": "sec_control_padel",
                "title": "Controllo & Maneggevolezza",
                "subtitle": "Forma a goccia o rotonda per tocco morbido e precisione.",
                "keywords": ["at10", "head", "siux"]
            }
        ],
        "spotlight": {
            "target_keyword": "hack",
            "badge_text": "Scelta Pro",
            "highlights": [
                "Carbonio Tricarbon per massima rigidità ed esplosività",
                "Sistema antivibrazione per prevenire epicondilite",
                "Miglior prezzo confrontato tra store padel"
            ]
        },
        "follow_ups": [
            "Confronta Bullpadel Hack e Vertex",
            "Mostrami racchette da padel sotto 150 euro",
            "Filtra per racchette di controllo"
        ]
    },
    "cycling": {
        "models": ["garmin edge", "wahoo kickr", "tacx flux", "tacx neo", "favero assioma", "kask protone", "kask wasabi", "poc ventral", "castelli espresso"],
        "label": "Ciclismo & Rulli Smart",
        "category": "cycling",
        "description": "Rulli interattivi per allenamento indoor, ciclocomputer GPS, caschi e abbigliamento per bici da corsa e gravel.",
        "sections": [
            {
                "id": "sec_smart_trainers",
                "title": "Rulli Smart & Indoor Cycling",
                "subtitle": "Allenamento interattivo su Zwift con simulazione pendenze e misurazione watt.",
                "keywords": ["kickr", "flux", "tacx", "wahoo"]
            },
            {
                "id": "sec_helmets_computers",
                "title": "Ciclocomputer & Caschi Aerodinamici",
                "subtitle": "Navigazione satellitare e sicurezza per uscite su strada e gravel.",
                "keywords": ["edge", "kask", "poc", "assioma"]
            }
        ],
        "spotlight": {
            "target_keyword": "kickr",
            "badge_text": "Top Rullo Smart",
            "highlights": [
                "Resistenza elettromagnetica ultra silenziosa",
                "Precisione di potenza +/- 1% e compatibilità Zwift",
                "Miglior prezzo confrontato tra negozi bici"
            ]
        },
        "follow_ups": [
            "Confronta Wahoo Kickr e Tacx Flux",
            "Mostrami rulli smart interattivi sotto 500 euro",
            "Filtra caschi da ciclismo taglia M"
        ]
    },
    "gear": {
        "models": ["poc", "kask", "abus", "casco", "abbigliamento termico"],
        "label": "Ciclismo & Attrezzatura",
        "category": "gear",
        "description": "Caschi tecnici, abbigliamento protettivo e accessori sportivi.",
        "sections": [
            {
                "id": "sec_protection_gear",
                "title": "Caschi & Protezione",
                "subtitle": "Tecnologia MIPS e ventilazione ottimale per uscite sicure.",
                "keywords": ["kask", "poc", "abus"]
            }
        ],
        "spotlight": {
            "target_keyword": "kask",
            "badge_text": "Top Sicurezza",
            "highlights": [
                "Design aerodinamico e ventilazione pluripremiata",
                "Regolazione micrometrica posteriore",
                "Miglior prezzo garantito"
            ]
        },
        "follow_ups": [
            "Confronta caschi Kask e POC",
            "Mostrami caschi sotto 100 euro"
        ]
    }
}

KNOWN_BRANDS = [
    "nike", "adidas", "asics", "hoka", "brooks", "garmin", "polar", "suunto",
    "salomon", "oakley", "theragun", "therabody", "enervit", "saucony",
    "mizuno", "new balance", "new-balance", "la sportiva", "poc", "kask", "abus",
    "bullpadel", "nox", "babolat", "starvie", "siux", "wahoo", "tacx", "favero", "castelli",
    "maison margiela", "margiela"
]


class LocalHeuristicParser:
    """High-precision local NLP rule engine specialized for athletic gear and fashion e-commerce.

    Implements Shopify Shop-style dual mode detection (AI Deep Dive vs Classic).
    """

    @staticmethod
    def normalize_typos(text: str) -> str:
        """Corrects common athletic gear phonetic typos and slang."""
        substitutions = [
            (r"\b(?:alpha\s*fly|alphafly)\b", "alphafly"),
            (r"\b(?:vapor\s*fly|vaporfly)\b", "vaporfly"),
            (r"\b(?:tempo\s*next)\b", "tempo next"),
            (r"\b(?:zom\s*fli|zoomfly|zomfly|zoom\s*fli)\b", "zoom fly"),
            (r"\b(?:peg|pegas)\b", "pegasus"),
            (r"\b(?:invincibl|invincibile)\b", "invincible"),
            (r"\b(?:vomer|vomer18)\b", "vomero"),
            (r"\b(?:speedgot|speed\s*got)\b", "speedgoat"),
            (r"\b(?:forunner|fore\s*runner)\b", "forerunner"),
            (r"\b(?:okley|oakly)\b", "oakley"),
            (r"\b(?:adizero\s*pro|adios\s*pro)\b", "adizero"),
            (r"\b(?:nimb|nimbus\s*26)\b", "nimbus"),
        ]
        res = text
        for pat, repl in substitutions:
            res = re.sub(pat, repl, res, flags=re.IGNORECASE)
        return res

    @staticmethod
    def parse(user_query: str, force_mode: Optional[str] = None) -> SmartSearchIntent:
        text = LocalHeuristicParser.normalize_typos(user_query.strip().lower())
        words = text.split()

        # 1. Price Bounds
        max_price = None
        min_price = None

        max_match = re.search(r"(?:sotto\s*i?|meno\s*di|max|massimo|budget\s*di?|fino\s*a)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?", text)
        if max_match:
            max_price = float(max_match.group(1).replace(",", "."))

        min_match = re.search(r"(?:sopra\s*i?|più\s*di|minimo|almeno)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?", text)
        if min_match:
            min_price = float(min_match.group(1).replace(",", "."))

        # 2. Shoe / Clothing Size
        size = None
        size_match = re.search(r"(?:taglia|numero|misura|porto\s*(?:il|la)?)\s*([0-9]{2}(?:[\.,][0-9])?|[xXsSmMlL]{1,3})", text)
        if size_match:
            size = size_match.group(1).replace(",", ".").upper()

        # 3. Gender
        gender = None
        if re.search(r"\b(donna|ragazza|femmin[eia]|wmns?|women)\b", text):
            gender = "Donna"
        elif re.search(r"\b(uomo|ragazzo|maschil[eia]|mens?|men)\b", text):
            gender = "Uomo"

        # 4. Brand extraction
        detected_brand = None
        for b in KNOWN_BRANDS:
            if re.search(rf"\b{re.escape(b)}\b", text):
                if "maison margiela" in b or "margiela" in b:
                    detected_brand = "Maison Margiela"
                elif "new balance" in b or "new-balance" in b:
                    detected_brand = "New-balance"
                else:
                    detected_brand = b.capitalize()
                break

        # 5. Domain Category & Archetype Detection
        archetype_key = "daily_trainer"
        features = []
        is_waterproof = bool(re.search(r"\b(impermeabil[ei]|gtx|gore[\s-]tex|pioggia|fango)\b", text))
        if is_waterproof:
            features.append("waterproof")

        if re.search(r"\b(orolog[io]|smartwatch|gps|cardio|garmin|polar|suunto|forerunner|fenix|instinct|epix|venu|vivoactive|ciclocomputer)\b", text):
            archetype_key = "gps_watch"
            if not detected_brand and re.search(r"\b(forerunner|fenix|instinct|epix|venu|vivoactive)\b", text):
                detected_brand = "Garmin"
        elif re.search(r"\b(occhial[ie]|lenti|oakley|prizm|sole)\b", text):
            archetype_key = "eyewear"
        elif re.search(r"\b(zain[oi]|gilet|flask|borracci[ae]|idratazione|camelbak)\b", text):
            archetype_key = "hydration"
        elif re.search(r"\b(theragun|pistola|massaggi[ao]|recupero|therabody)\b", text):
            archetype_key = "fitness"
        elif re.search(r"\b(gel|barrett[ae]|integrator[ei]|enervit|sali|maltodestrin[ae]|nutrizione)\b", text):
            archetype_key = "nutrition"
        elif re.search(r"\b(padel|racchett[ae]|pala|bullpadel|nox|starvie|siux|overgrip)\b", text):
            archetype_key = "padel"
        elif re.search(r"\b(ciclismo|bici|bicicletta|rull[oi]|smart trainer|kickr|flux|tacx|wahoo|assioma|favero|castelli)\b", text):
            archetype_key = "cycling"
        elif re.search(r"\b(casco|caschi|kask|poc|abus)\b", text):
            archetype_key = "gear"
        elif re.search(r"\b(trail|sterrato|fango|montagna|sentier[oi]|bosco)\b", text):
            archetype_key = "trail_running"
            features.append("trail")
        elif re.search(r"\b(alphafly|vaporfly|streakfly|metaspeed|adizero|endorphin|veloc[ei]|reattiv[ae]|gara|maratona|mezza|ripetute|piastra|carbonio)\b", text):
            archetype_key = "speed_race"
            features.append("racing")
            if not detected_brand and re.search(r"\b(alphafly|vaporfly|streakfly)\b", text):
                detected_brand = "Nike"
        elif re.search(r"\b(ammortizzat[ae]|morbida?|comod[ae]|protettiv[ae]|ginocchi[ao]|schiena|pesant[ei]|peso|\d{2,3}\s*kg)\b", text):
            archetype_key = "max_cushion"
            features.append("cushioning")

        arch = SPORTS_KNOWLEDGE[archetype_key]
        category = arch["category"]

        # 6. Generate Target Keywords
        exact_model_match = re.search(
            r"\b(alphafly(?:\s*\d+)?|vaporfly(?:\s*\d+)?|zoom\s*fly(?:\s*\d+)?|vomero(?:\s*\d+)?|pegasus(?:\s*\w+)?|nimbus(?:\s*\d+)?|clifton(?:\s*\d+)?|bondi(?:\s*\d+)?|ghost(?:\s*\d+)?|streakfly(?:\s*\d+)?|invincible(?:\s*\d+)?|adizero(?:\s*\w+)?|speedgoat(?:\s*\d+)?|forerunner(?:\s*\d+)?|fenix(?:\s*\d+)?|novablast(?:\s*\d+)?|superblast(?:\s*\d+)?|endorphin(?:\s*\w+)?|deviate(?:\s*\w+)?|radar\s*ev|sutro|hack(?:\s*\d+)?|vertex(?:\s*\d+)?|at10|kickr|flux(?:\s*\w+)?|replica(?:\s*\w+)?|tabi)\b",
            text
        )

        is_exact_sku_only = False
        if exact_model_match and len(words) <= 3 and not any(kw in text for kw in ["per", "come", "quale", "miglior", "comod", "ammortizz", "sotto", "econom"]):
            is_exact_sku_only = True

        if exact_model_match:
            exact_val = exact_model_match.group(1).strip()
            if detected_brand and detected_brand.lower() not in exact_val.lower():
                target_keywords = [f"{detected_brand.lower()} {exact_val}", exact_val]
            else:
                target_keywords = [exact_val]
        else:
            stopwords = {"per", "la", "il", "lo", "i", "gli", "le", "un", "una", "uno", "di", "a", "da", "in", "con", "su", "scarpe", "scarpa", "modello", "sotto", "fino", "euro", "max", "taglia", "misura", "porto", "cerco", "voglio", "trova", "della", "running", "corsa", "ammortizzate", "comode", "veloci", "nere", "bianche"}
            tokens = [w for w in re.findall(r"\b[a-zA-Z0-9]+\b", text) if w not in stopwords and len(w) > 1]
            if tokens and len(tokens) >= 2 and archetype_key == "daily_trainer" and not detected_brand:
                target_keywords = [" ".join(tokens)]
            else:
                candidate_models = arch["models"]
                if detected_brand:
                    brand_lower = detected_brand.lower()
                    filtered = [m for m in candidate_models if brand_lower in m]
                    candidate_models = filtered if filtered else [f"{detected_brand.lower()}"]
                if is_waterproof and category == "running_shoes":
                    target_keywords = [f"{m} gtx" for m in candidate_models[:3]] + candidate_models[:2]
                else:
                    target_keywords = candidate_models[:4]

        # 7. Chips & Filter Representation
        chips = []
        if max_price:
            chips.append(SmartSearchChip(id="price", label=f"Max €{max_price:.0f}", param_key="max_price", value=str(max_price)))
        if size:
            chips.append(SmartSearchChip(id="size", label=f"Taglia {size}", param_key="size", value=size))
        if gender:
            chips.append(SmartSearchChip(id="gender", label=gender, param_key="gender", value=gender))
        if detected_brand:
            chips.append(SmartSearchChip(id="brand", label=detected_brand, param_key="brand", value=detected_brand))
        if is_waterproof:
            chips.append(SmartSearchChip(id="feature_gtx", label="Impermeabile / GTX", param_key="feature", value="waterproof"))
        if "cushioning" in features:
            chips.append(SmartSearchChip(id="feature_cushion", label="Massimo Ammortizzamento", param_key="feature", value="cushioning"))
        elif "racing" in features:
            chips.append(SmartSearchChip(id="feature_racing", label="Gara & Reattività", param_key="feature", value="racing"))
        elif "trail" in features:
            chips.append(SmartSearchChip(id="feature_trail", label="Trail / Sterrato", param_key="feature", value="trail"))

        # 8. Mode Decision: AI Deep Dive vs Classic Mode
        if force_mode == "classic":
            search_mode = "classic"
            is_deep_dive = False
        elif force_mode == "deep_dive":
            search_mode = "deep_dive"
            is_deep_dive = True
        else:
            # Automatic heuristic: exact SKU searches (e.g. 'pegasus 41') go to classic directly,
            # exploratory, multi-attribute or fashion/lifestyle queries go to deep_dive!
            if is_exact_sku_only:
                search_mode = "classic"
                is_deep_dive = False
            else:
                search_mode = "deep_dive"
                is_deep_dive = True

        # 9. Conversational Header & Summary (Exact Shopify Shop style)
        clean_subject = detected_brand or arch["label"]
        if detected_brand and "scarpe" in text:
            clean_subject = f"scarpe {detected_brand}"

        conversational_header = "Ho cercato prodotti"
        conversational_summary = f"Ho trovato diverse **{clean_subject}**: dai modelli più versatili a quelli più performanti e ricercati, con prezzi e stili molto diversi."

        # 10. Thematic Curated Sections & Spotlight
        curated_sections_raw = arch.get("sections", [])
        curated_sections = [
            CuratedSectionDef(
                id=s["id"],
                title=s["title"],
                subtitle=s["subtitle"],
                keywords=s.get("keywords", target_keywords[:2])
            )
            for s in curated_sections_raw
        ]

        # Fashion / Custom query fallback sections if not standard sports archetype
        if detected_brand and detected_brand == "Maison Margiela":
            conversational_summary = "Ho trovato diverse **scarpe nere Maison Margiela**: dalle Replica più versatili alle Tabi e ai modelli Future, con prezzi e stili molto diversi."
            curated_sections = [
                CuratedSectionDef(
                    id="sec_replica",
                    title="Sneakers nere Replica",
                    subtitle="Le più facili da portare ogni giorno, tra pelle, suede e versioni iconiche.",
                    keywords=["replica", "margiela replica"]
                ),
                CuratedSectionDef(
                    id="sec_popular",
                    title="Modelli più ricercati",
                    subtitle="Tabi, Future e silhouette distintive per un look d'avanguardia.",
                    keywords=["tabi", "future", "mm6"]
                ),
                CuratedSectionDef(
                    id="sec_tabi_elegant",
                    title="Tabi e scarpe eleganti nere",
                    subtitle="Derby, mocassini e stivaletti con la caratteristica punta divisa.",
                    keywords=["tabi derby", "mocassini", "stringate"]
                )
            ]
            spotlight_def = SpotlightDef(
                target_keyword="replica",
                badge_text="15% di sconto",
                highlights=[
                    "Replica nera classica in pelle e suede",
                    "Design iconico d'ispirazione German Army Trainer",
                    "Prezzo tra i più bassi nel nostro confronto"
                ]
            )
            follow_ups = [
                "Mostrami Maison Margiela nere taglia 42",
                "Confronta Replica, Tabi e Future nere",
                "Mostrami solo Maison Margiela sotto 700 euro"
            ]
        else:
            spotlight_raw = arch.get("spotlight", {})
            spotlight_def = SpotlightDef(
                target_keyword=spotlight_raw.get("target_keyword", target_keywords[0] if target_keywords else "modello"),
                badge_text=spotlight_raw.get("badge_text", "Miglior Scelta"),
                highlights=spotlight_raw.get("highlights", [
                    "Modello di riferimento per comfort e affidabilità",
                    "Ottimo rapporto qualità/prezzo e materiali tecnici",
                    "Prezzo confrontato in tempo reale tra negozi verificati"
                ])
            )
            follow_ups = arch.get("follow_ups", [
                f"Mostrami solo opzioni sotto {max_price or 150} euro",
                f"Confronta i modelli più apprezzati",
                "Filtra per disponibilità immediata"
            ])

        explanation = conversational_summary

        return SmartSearchIntent(
            raw_query=user_query,
            search_mode=search_mode,
            is_deep_dive=is_deep_dive,
            conversational_header=conversational_header,
            conversational_summary=conversational_summary,
            target_keywords=target_keywords,
            brand=detected_brand,
            category=category,
            gender=gender,
            max_price=max_price,
            min_price=min_price,
            size=size,
            features=features,
            explanation=explanation,
            chips=chips,
            curated_sections=curated_sections,
            spotlight=spotlight_def,
            follow_up_suggestions=follow_ups,
            source="local_heuristic"
        )


class OpenRouterParser:
    """Uses OpenRouter AI (Llama 3.3 70B / Llama 3.1 8B) to generate Shopify Shop-style

    intelligent, conversational e-commerce search responses.
    """

    SYSTEM_PROMPT = """Sei l'assistente IA di ricerca intelligente per l'app e-commerce 'FitMatch' (ispirata alla ricerca dell'app Shop di Shopify).
FitMatch è un comparatore di prezzi e cataloghi specializzato in scarpe (running, sneakers, lifestyle), abbigliamento sportivo e tecnologia (GPS, cardio, ciclismo).

Il tuo obiettivo è analizzare la ricerca dell'utente e decidere:
1. DECISIONE SULLA MODALITÀ DI RICERCA:
   - "classic": se l'utente cerca un singolo modello o SKU esatto e privo di aggettivi/domande (es. "Pegasus 41", "Forerunner 165", "Vomero 18"). L'utente vuole vedere subito l'elenco dei risultati classici.
   - "deep_dive": se la richiesta è esplorativa, colloquiale, multi-attributo, comprende stile/brand o un bisogno (es. "Maison margiela scarpe nere", "scarpe running ammortizzate per proteggere le ginocchia", "migliori scarpe per maratona", "outfit corsa invernale", "orologio gps triathlon sotto 300 euro"). In questo caso l'utente trae grande valore da una risposta in stile ChatGPT/Shop con sezioni tematiche e caroselli curati!

2. IN CASO DI "deep_dive":
   - conversational_header: Breve intestazione di contesto (es. "Ho cercato prodotti" o "Ho cercato scarpe da running").
   - conversational_summary: 1 o 2 frasi amichevoli ed eleganti in italiano che riassumono cosa hai trovato, mettendo in grassetto con **i punti chiave** (es. "Ho trovato diverse **scarpe nere Maison Margiela**: dalle Replica più versatili alle Tabi e ai modelli Future, con prezzi e stili molto diversi.").
   - curated_sections: 2 o 3 categorie o temi tematici logici in cui dividere i prodotti (es. "Sneakers nere Replica", "Modelli più ricercati", "Tabi e scarpe eleganti nere"), ciascuno con:
     * id: stringa univoca
     * title: titolo accattivante
     * subtitle: 1 riga descrittiva del perché questa categoria è speciale
     * keywords: array di 2 o 3 termini di ricerca per pescare i prodotti corretti
   - spotlight: Un prodotto di punta consigliato con badge ("15% di sconto" o "Miglior Scelta") e 3 bullet point descrittivi di valore.
   - follow_up_suggestions: 3 pulsanti pillola con domande di approfondimento coerenti (es. ["Mostrami Maison Margiela nere taglia 42", "Confronta Replica, Tabi e Future nere", "Mostrami solo opzioni sotto 700 euro"]).
   - chips: Filtri rapidi estratti (es. brand, prezzo, taglia, caratteristiche).

Rispondi ESCLUSIVAMENTE con un JSON valido con questa esatta struttura:
{
  "search_mode": "deep_dive | classic",
  "is_deep_dive": true,
  "conversational_header": "Ho cercato prodotti",
  "conversational_summary": "Testo con **parole chiave in grassetto**",
  "target_keywords": ["termine 1", "termine 2"],
  "brand": "Nome Brand o null",
  "category": "running_shoes | gps_watch | eyewear | hydration | fitness | nutrition | gear",
  "gender": "Uomo | Donna | null",
  "max_price": float o null,
  "min_price": float o null,
  "size": "taglia o null",
  "features": ["cushioning", "waterproof", "racing", "trail"],
  "curated_sections": [
    {
      "id": "sec_1",
      "title": "Titolo Sezione 1",
      "subtitle": "Descrizione 1 riga",
      "keywords": ["kw1", "kw2"]
    }
  ],
  "spotlight": {
    "target_keyword": "kw_modello_top",
    "badge_text": "15% di sconto",
    "highlights": [
      "Punto di forza 1",
      "Punto di forza 2",
      "Punto di forza 3"
    ]
  },
  "follow_up_suggestions": [
    "Domanda di follow up 1",
    "Domanda di follow up 2",
    "Domanda di follow up 3"
  ],
  "chips": [
    {"id": "brand", "label": "Nike", "param_key": "brand", "value": "Nike"}
  ]
}
"""

    @classmethod
    def parse(cls, user_query: str, api_key: str, model: str = OPENROUTER_MODEL, force_mode: Optional[str] = None) -> Optional[SmartSearchIntent]:
        if not api_key:
            return None

        import urllib.request
        import ssl

        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

        mode_instruction = ""
        if force_mode == "classic":
            mode_instruction = "\nNOTA IMPORTANTE: L'utente richiede esplicitamente la modalità 'classic'."
        elif force_mode == "deep_dive":
            mode_instruction = "\nNOTA IMPORTANTE: L'utente richiede esplicitamente la modalità 'deep_dive'."

        models_to_try = [model]
        if OPENROUTER_BACKUP_MODEL and OPENROUTER_BACKUP_MODEL != model:
            models_to_try.append(OPENROUTER_BACKUP_MODEL)

        for current_model in models_to_try:
            payload = {
                "model": current_model,
                "messages": [
                    {"role": "system", "content": cls.SYSTEM_PROMPT + mode_instruction},
                    {"role": "user", "content": user_query}
                ],
                "temperature": 0.1,
                "max_tokens": 800
            }

            headers = {
                "Authorization": f"Bearer {api_key.strip()}",
                "HTTP-Referer": "https://fitmatch.it",
                "X-Title": "FitMatch Price Comparator",
                "Content-Type": "application/json"
            }

            try:
                req = urllib.request.Request(
                    OPENROUTER_URL,
                    data=json.dumps(payload).encode("utf-8"),
                    headers=headers,
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=8.5, context=ctx) as resp:
                    if resp.status != 200:
                        logger.warning("OpenRouter API status %s for %s", resp.status, current_model)
                        continue
                    data = json.loads(resp.read().decode("utf-8"))
                    content = data["choices"][0]["message"]["content"]

                    json_match = re.search(r"(\{.*\})", content, flags=re.DOTALL)
                    clean_json = json_match.group(1).strip() if json_match else content.strip()
                    if clean_json.startswith("```json"):
                        clean_json = clean_json[7:]
                    if clean_json.startswith("```"):
                        clean_json = clean_json[3:]
                    if clean_json.endswith("```"):
                        clean_json = clean_json[:-3]
                    clean_json = clean_json.strip()

                    parsed = json.loads(clean_json)

                    chips = [
                        SmartSearchChip(
                            id=c.get("id", f"chip_{i}"),
                            label=c.get("label", ""),
                            param_key=c.get("param_key", "keyword"),
                            value=str(c.get("value", ""))
                        )
                        for i, c in enumerate(parsed.get("chips", []))
                        if c.get("label")
                    ]

                    curated_sections = [
                        CuratedSectionDef(
                            id=s.get("id", f"sec_{i}"),
                            title=s.get("title", ""),
                            subtitle=s.get("subtitle", ""),
                            keywords=s.get("keywords", [])
                        )
                        for i, s in enumerate(parsed.get("curated_sections", []))
                        if s.get("title")
                    ]

                    spotlight_data = parsed.get("spotlight")
                    spotlight_obj = None
                    if spotlight_data and isinstance(spotlight_data, dict):
                        spotlight_obj = SpotlightDef(
                            target_keyword=spotlight_data.get("target_keyword", ""),
                            badge_text=spotlight_data.get("badge_text", "Miglior Scelta"),
                            highlights=spotlight_data.get("highlights", [])
                        )

                    search_mode = parsed.get("search_mode", "deep_dive")
                    is_deep_dive = parsed.get("is_deep_dive", search_mode == "deep_dive")

                    if force_mode:
                        search_mode = force_mode
                        is_deep_dive = (force_mode == "deep_dive")

                    return SmartSearchIntent(
                        raw_query=user_query,
                        search_mode=search_mode,
                        is_deep_dive=is_deep_dive,
                        conversational_header=parsed.get("conversational_header", "Ho cercato prodotti"),
                        conversational_summary=parsed.get("conversational_summary", ""),
                        target_keywords=parsed.get("target_keywords") or [user_query],
                        brand=parsed.get("brand"),
                        category=parsed.get("category"),
                        gender=parsed.get("gender"),
                        max_price=float(parsed["max_price"]) if parsed.get("max_price") is not None else None,
                        min_price=float(parsed["min_price"]) if parsed.get("min_price") is not None else None,
                        size=str(parsed["size"]) if parsed.get("size") else None,
                        features=parsed.get("features", []),
                        explanation=parsed.get("conversational_summary", "Risultati selezionati con intelligenza artificiale"),
                        chips=chips,
                        curated_sections=curated_sections,
                        spotlight=spotlight_obj,
                        follow_up_suggestions=parsed.get("follow_up_suggestions", []),
                        source="openrouter"
                    )
            except Exception as e:
                logger.warning("OpenRouter call failed for model %s: %s", current_model, e)
                continue

        return None


class SmartSearchEngine:
    """Unified coordinator with dual-engine AI parser, enterprise multi-tier LRU/TTL cache, and SQL aggregator."""

    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None, cache_manager: Optional[SearchCacheManager] = None):
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY", "")
        self.model = model or os.environ.get("OPENROUTER_MODEL", OPENROUTER_MODEL)
        self.cache_manager = cache_manager or SearchCacheManager.get_instance()

    def parse_query(self, user_query: str, force_mode: Optional[str] = None) -> SmartSearchIntent:
        # 1. Check Multi-Tier Cache (L1 Memory LRU / L2 Disk Persistence)
        cached_data = self.cache_manager.get_intent(user_query, force_mode=force_mode)
        if cached_data:
            try:
                return SmartSearchIntent.model_validate(cached_data)
            except Exception as e:
                logger.debug("Failed to re-validate cached intent: %s", e)

        intent = None
        if self.api_key:
            intent = OpenRouterParser.parse(user_query=user_query, api_key=self.api_key, model=self.model, force_mode=force_mode)

        if not intent:
            intent = LocalHeuristicParser.parse(user_query=user_query, force_mode=force_mode)

        # 2. Store in Multi-Tier Cache with 7-day TTL
        if intent:
            self.cache_manager.set_intent(user_query, force_mode=force_mode, intent_data=intent)

        return intent
