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


class SpecComparisonDef(BaseModel):
    model_name: str
    ideal_for: str
    strengths: str
    target_keyword: Optional[str] = None


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
    spec_comparisons: List[SpecComparisonDef] = Field(default_factory=list)
    follow_up_suggestions: List[str] = Field(default_factory=list)
    source: str = "local_heuristic"


# Sports domain knowledge base for athletic gear and running
SPORTS_KNOWLEDGE = {
    "max_cushion": {
        "models": ["asics nimbus", "hoka bondi", "brooks glycerin", "hoka clifton", "new balance 1080", "saucony triumph"],
        "label": "Massimo Ammortizzamento & Protezione",
        "category": "running_shoes",
        "description": "Scarpe con massima protezione d'impatto per correre su asfalto, ideali per proteggere ginocchia, articolazioni e per pesi medi/elevati.",
        "conversational_summary": "Per proteggere ginocchia e articolazioni su asfalto sceglierei modelli con **massimo ammortizzamento e protezione d'impatto**. Ecco le opzioni più confortevoli trovate a confronto:",
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
                "keywords": ["glycerin", "clifton", "1080", "triumph"]
            }
        ],
        "spec_comparisons": [
            {
                "model_name": "Asics Gel-Nimbus 26",
                "ideal_for": "Massima protezione e ginocchia sensibili",
                "strengths": "PureGEL e schiuma FF BLAST+ ECO",
                "target_keyword": "nimbus"
            },
            {
                "model_name": "Hoka Bondi 8",
                "ideal_for": "Corse rigeneranti e impatti morbidi",
                "strengths": "Maxi intersuola in schiuma EVA e tallone esteso",
                "target_keyword": "bondi"
            },
            {
                "model_name": "Brooks Glycerin 21",
                "ideal_for": "Alti chilometraggi con calzata premium",
                "strengths": "DNA LOFT v3 a infusione di azoto",
                "target_keyword": "glycerin"
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
        "models": ["nike pegasus", "brooks ghost", "asics cumulus", "asics novablast", "saucony ride", "mizuno wave rider"],
        "label": "Daily Trainer Polivalente",
        "category": "running_shoes",
        "description": "Scarpe versatili e resistenti per tutti gli allenamenti quotidiani su asfalto a ritmo medio.",
        "conversational_summary": "Per gli allenamenti quotidiani e chilometraggi versatili punterei su una **daily trainer solida e reattiva**. Ecco i modelli di riferimento con i migliori prezzi:",
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
                "keywords": ["novablast", "cumulus", "wave rider", "ride"]
            }
        ],
        "spec_comparisons": [
            {
                "model_name": "Nike Pegasus 41",
                "ideal_for": "Allenamenti quotidiani versatili",
                "strengths": "Nuova schiuma ReactX e doppie unità Air Zoom",
                "target_keyword": "pegasus"
            },
            {
                "model_name": "Brooks Ghost 16",
                "ideal_for": "Affidabilità, transizioni fluide e durata",
                "strengths": "Intersuola DNA LOFT v3 e tomaia air mesh",
                "target_keyword": "ghost"
            },
            {
                "model_name": "Asics Novablast 4",
                "ideal_for": "Ritmo allegro e corse divertenti",
                "strengths": "Geometria a trampolino e FF BLAST+ ECO",
                "target_keyword": "novablast"
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
        "models": ["adidas adizero", "nike vaporfly", "nike alphafly", "asics metaspeed", "saucony endorphin", "altra vanish carbon", "new balance fuelcell", "hoka cielo", "nike zoom fly", "brooks hyperion"],
        "label": "Velocità & Maratona",
        "category": "running_shoes",
        "description": "Modelli leggeri e reattivi con schiuma performante e/o piastra in carbonio per ritmo veloce e maratona.",
        "conversational_summary": "Per la maratona sceglierei tra una **super scarpa da gara in carbonio** e una **trainer più versatile per lunghi e preparazione**. Queste sono le opzioni più interessanti trovate disponibili per l’Italia:",
        "sections": [
            {
                "id": "sec_carbon_race",
                "title": "Super scarpe da gara",
                "subtitle": "Massima propulsione e ritorno di energia per il giorno della gara.",
                "keywords": ["adizero", "adios", "vaporfly", "alphafly", "metaspeed", "vanish", "fuelcell", "cielo"]
            },
            {
                "id": "sec_adizero_marathon",
                "title": "Adidas Adizero per la maratona",
                "subtitle": "Modelli da gara e allenamento veloce della linea Adizero.",
                "keywords": ["adizero", "adios", "takumi", "boston"]
            },
            {
                "id": "sec_long_preparation",
                "title": "Per lunghi e preparazione",
                "subtitle": "Più ammortizzazione e versatilità per accumulare chilometri.",
                "keywords": ["nimbus", "endorphin", "superblast", "novablast", "clifton", "1080"]
            }
        ],
        "spec_comparisons": [
            {
                "model_name": "Adidas Adizero Adios Pro 4",
                "ideal_for": "Gara e ritmi sostenuti",
                "strengths": "Lightstrike Pro, Energyrods, rocker",
                "target_keyword": "adizero"
            },
            {
                "model_name": "Nike Vaporfly 4 / 3",
                "ideal_for": "Runner leggeri ed elastici",
                "strengths": "ZoomX e piastra Flyplate",
                "target_keyword": "vaporfly"
            },
            {
                "model_name": "Asics Metaspeed Sky Paris",
                "ideal_for": "Runner ad ampia falcata",
                "strengths": "Schiuma FF Turbo+ e piastra carbonio",
                "target_keyword": "metaspeed"
            },
            {
                "model_name": "Saucony Endorphin Pro 4",
                "ideal_for": "Maratone e lunghi veloci costanti",
                "strengths": "PWRRUN PB con piastra in fibra di carbonio",
                "target_keyword": "endorphin"
            }
        ],
        "spotlight": {
            "target_keyword": "adizero",
            "badge_text": "Scelta Pro Maratona",
            "highlights": [
                "Energyrods per spinta esplosiva ad ogni falcata",
                "Schiuma Lightstrike Pro ultra reattiva e leggera",
                "Miglior prezzo confrontato tra più negozi partner"
            ]
        },
        "follow_ups": [
            "Confronta Adidas Adios Pro 4 e Nike Vaporfly 4",
            "Trovami scarpe da maratona Adidas sotto 180 euro",
            "Consigliami una scarpa per lunghi e maratona"
        ]
    },
    "trail_running": {
        "models": ["hoka speedgoat", "salomon xa pro", "brooks cascadia", "asics trabuco", "la sportiva", "salomon pulsar"],
        "label": "Trail Running & Sterrato",
        "category": "running_shoes",
        "description": "Scarpe con tasselli e suola artigliata per sentieri, fango, sassi e montagna.",
        "conversational_summary": "Per sentieri e montagna sceglierei tra una scarpa da **trail tecnico con suola aggressiva** e un modello polivalente **door-to-trail**. Ecco le opzioni più convenienti:",
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
        "spec_comparisons": [
            {
                "model_name": "Hoka Speedgoat 5 / 6",
                "ideal_for": "Trail tecnici, fango e lunghe distanze",
                "strengths": "Battistrada Vibram Megagrip e tasselli 5mm",
                "target_keyword": "speedgoat"
            },
            {
                "model_name": "Brooks Cascadia 17",
                "ideal_for": "Sentieri montani sconnessi e rocce",
                "strengths": "Trail Adapt System e piastra anti-roccia",
                "target_keyword": "cascadia"
            },
            {
                "model_name": "Salomon Pulsar Trail",
                "ideal_for": "Ritmi veloci e sterrato scorrevole",
                "strengths": "Energy Blade e battistrada All Terrain Contagrip",
                "target_keyword": "salomon"
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
        "conversational_summary": "Per monitorare passo, frequenza cardiaca e carico di allenamento ecco i **migliori smartwatch e cardiofrequenzimetri GPS**:",
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
        "spec_comparisons": [
            {
                "model_name": "Garmin Forerunner 165",
                "ideal_for": "Runner e principianti evoluti",
                "strengths": "Display AMOLED touch, piani Garmin Coach, 39g",
                "target_keyword": "forerunner 165"
            },
            {
                "model_name": "Garmin Forerunner 265",
                "ideal_for": "Mezza maratona, maratona e triathlon",
                "strengths": "GPS multi-banda, Training Readiness, musica",
                "target_keyword": "forerunner 265"
            },
            {
                "model_name": "Garmin Fenix 7 / Epix Pro",
                "ideal_for": "Trail, ultramaratona e outdoor estremo",
                "strengths": "Cassa in titanio, mappe offline, autonomia eccezionale",
                "target_keyword": "fenix"
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
    "gym_training": {
        "models": ["adidas dropset", "adizero dropset", "dropset 4", "dropset pro", "nike metcon", "reebok nano", "under armour tribase", "puma fuse"],
        "label": "Palestra, Cross-Training & Hyrox",
        "category": "fitness",
        "description": "Scarpe stabili e piatte per sollevamento pesi, cross-training, circuiti funzionali e competizioni Hyrox.",
        "conversational_summary": "Per allenamento funzionale, palestra e gare **Hyrox**, la stabilità a terra e il supporto laterale sono cruciali. Ecco i migliori modelli **Adidas Dropset** e training a confronto:",
        "sections": [
            {
                "id": "sec_dropset_models",
                "title": "Modelli Adidas Dropset",
                "subtitle": "Piattaforma ribassata a doppia densità per massima stabilità sotto carico.",
                "keywords": ["dropset", "adizero dropset"]
            },
            {
                "id": "sec_training_alternatives",
                "title": "Scarpe da Allenamento Ibrido",
                "subtitle": "Ideali per alternare sollevamento pesi, sled push e tratti di corsa.",
                "keywords": ["metcon", "nano", "tribase", "fuse"]
            }
        ],
        "spec_comparisons": [
            {
                "model_name": "Adidas Adizero Dropset Pro Trainer",
                "ideal_for": "Allenamento ibrido e Hyrox",
                "strengths": "Doppia densità, suola Traxion grip e gabbia di supporto",
                "target_keyword": "dropset"
            },
            {
                "model_name": "Adidas Dropset 4 Power",
                "ideal_for": "Sollevamento pesi e forza in palestra",
                "strengths": "Base ampia e drop ridotto per massimo radicamento",
                "target_keyword": "dropset"
            }
        ],
        "spotlight": {
            "target_keyword": "dropset",
            "badge_text": "Miglior Scelta Training",
            "highlights": [
                "Stabilità ottimale con intersuola a doppia densità",
                "Grip superiore per slitte, affondi e stacchi da terra",
                "Prezzo più basso confrontato tra i migliori negozi"
            ]
        },
        "follow_ups": [
            "Confrontale con le adidas Dropset 4",
            "Quali sono migliori per Hyrox?",
            "Cercale nella mia taglia"
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
        elif re.search(r"\b(dropset|metcon|nano|tribase|fuse|powerlifting|crossfit|hyrox|palestra|pesi|sollevamento|allenamento funzionale)\b", text):
            archetype_key = "gym_training"
            features.append("training")
            if not detected_brand:
                if "dropset" in text:
                    detected_brand = "Adidas"
                elif "metcon" in text:
                    detected_brand = "Nike"
                elif "nano" in text:
                    detected_brand = "Reebok"
                elif "tribase" in text:
                    detected_brand = "Under Armour"
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
            r"\b(adizero\s+dropset(?:\s*\w+)?|dropset(?:\s*\w+)?|metcon(?:\s*\d+)?|nano(?:\s*\w+)?|alphafly(?:\s*\d+)?|vaporfly(?:\s*\d+)?|zoom\s*fly(?:\s*\d+)?|vomero(?:\s*\d+)?|pegasus(?:\s*\w+)?|nimbus(?:\s*\d+)?|clifton(?:\s*\d+)?|bondi(?:\s*\d+)?|ghost(?:\s*\d+)?|streakfly(?:\s*\d+)?|invincible(?:\s*\d+)?|adizero(?:\s*\w+)?|speedgoat(?:\s*\d+)?|forerunner(?:\s*\d+)?|fenix(?:\s*\d+)?|novablast(?:\s*\d+)?|superblast(?:\s*\d+)?|endorphin(?:\s*\w+)?|deviate(?:\s*\w+)?|radar\s*ev|sutro|hack(?:\s*\d+)?|vertex(?:\s*\d+)?|at10|kickr|flux(?:\s*\w+)?|replica(?:\s*\w+)?|tabi)\b",
            text
        )

        is_exact_sku_only = False
        if exact_model_match and len(words) <= 3 and not any(kw in text for kw in ["per", "come", "quale", "miglior", "comod", "ammortizz", "sotto", "econom"]):
            is_exact_sku_only = True

        if exact_model_match:
            exact_val = exact_model_match.group(1).strip()
            if "dropset" in exact_val:
                target_keywords = ["adidas dropset", "adizero dropset", exact_val]
            elif "forerunner" in exact_val and "165" in text:
                target_keywords = ["garmin forerunner 165", "forerunner 165"]
            elif detected_brand and detected_brand.lower() not in exact_val.lower():
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
                    target_keywords = candidate_models[:8]

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
        elif "training" in features:
            chips.append(SmartSearchChip(id="feature_training", label="Palestra & Hyrox", param_key="feature", value="training"))

        # 8. Mode Decision: Default to AI Deep Dive like Shopify Shop
        if force_mode == "classic":
            search_mode = "classic"
            is_deep_dive = False
        else:
            search_mode = "deep_dive"
            is_deep_dive = True

        # 9. Conversational Header & Summary (Exact Shopify Shop style)
        if exact_model_match:
            exact_val = exact_model_match.group(1).strip()
            brand_prefix = f"{detected_brand} " if detected_brand and detected_brand.lower() not in exact_val.lower() else ""
            clean_subject = f"{brand_prefix}{exact_val.title()}"
            conversational_header = f"Ho cercato {clean_subject}"
            conversational_summary = arch.get("conversational_summary") or f"Ecco i migliori prezzi e offerte per **{clean_subject}**, confrontati in tempo reale tra tutti i negozi partner ufficiali."
        else:
            clean_subject = detected_brand or arch["label"]
            if detected_brand and "scarpe" in text:
                clean_subject = f"scarpe {detected_brand}"
            conversational_header = "Ho cercato prodotti"
            conversational_summary = arch.get("conversational_summary") or f"Ho trovato diverse **{clean_subject}**: dai modelli più versatili a quelli più performanti e ricercati, con prezzi e stili molto diversi."

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

        # 11. Structured Comparative Spec Cards ("Come orientarsi" - Exact Shopify Shop style)
        spec_comparisons_raw = arch.get("spec_comparisons", [])
        spec_comparisons = [
            SpecComparisonDef(
                model_name=s["model_name"],
                ideal_for=s["ideal_for"],
                strengths=s["strengths"],
                target_keyword=s.get("target_keyword")
            )
            for s in spec_comparisons_raw
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
            spec_comparisons = [
                SpecComparisonDef(
                    model_name="Maison Margiela Replica",
                    ideal_for="Stile quotidiano e silhouette senza tempo",
                    strengths="Pelle d'agnello e suede con suola in gomma naturale",
                    target_keyword="replica"
                ),
                SpecComparisonDef(
                    model_name="Maison Margiela Tabi",
                    ideal_for="Look iconico e avanguardia concettuale",
                    strengths="Punta divisa a zoccolo giapponese in nappa morbida",
                    target_keyword="tabi"
                )
            ]
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
            spec_comparisons=spec_comparisons,
            follow_up_suggestions=follow_ups,
            source="local_heuristic"
        )


class OpenRouterParser:
    """Uses OpenRouter AI (Llama 3.3 70B / Llama 3.1 8B) to generate Shopify Shop-style

    intelligent, conversational e-commerce search responses.
    """

    SYSTEM_PROMPT = """Sei l'assistente IA di ricerca intelligente per l'app e-commerce 'FitMatch' (ispirata alla ricerca dell'app Shop di Shopify).
FitMatch è un comparatore di prezzi e cataloghi specializzato in scarpe (running, fitness, sneakers, lifestyle), abbigliamento sportivo e tecnologia (GPS, cardio, ciclismo).

Il tuo obiettivo è analizzare la ricerca dell'utente e restituire una risposta d'eccellenza in stile Shop di Shopify:
1. MODALITÀ DI RICERCA:
   - Imposta SEMPRE "search_mode": "deep_dive" e "is_deep_dive": true (anche per ricerche di singoli modelli come "Forerunner 165" o "Adizero Dropset"), così che l'utente riceva sempre il riassunto conversazionale, lo spotlight con la migliore offerta, il confronto rapido tra edizioni e i pulsanti di follow-up utili! Usa "classic" SOLO se l'utente richiede espressamente una lista piatta senza AI (es. "mostra solo lista").

2. CONOSCENZA DEL DOMINIO ATLETICO & REGOLE CRITICHE SULLE CATEGORIE:
   - "Adidas Dropset" (Dropset Trainer, Dropset Pro, Dropset 3, Dropset 4) è una scarpa specifica per PALESTRA, PESISTICA, FUNCTIONAL TRAINING e HYROX (suola piatta a doppia densità, drop ridotto, supporto laterale per squat e slitte). NON descriverla MAI come scarpa da corsa o con ammortizzazione da running! Imposta 'category': 'fitness'.
   - "Garmin Forerunner" (es. Forerunner 165, 265, 965) è uno SMARTWATCH GPS DA CORSA. "Garmin Edge" (es. Edge 840) è un CICLOCOMPUTER DA MANUBRIO BICI: non confonderli MAI! Imposta 'category': 'gps_watch'.
   - Scarpe da corsa (running_shoes): Pegasus, Vomero, Nimbus, Clifton, Bondi, Ghost, Speedgoat, Novablast, Endorphin, Adizero Adios / Boston.
   - Scarpe da training/palestra (fitness): Dropset, Metcon, Nano, Tribase, Fuse.

3. STRUTTURA DELLE SEZIONI & SPEC COMPARISONS ("Confronto Rapido"):
   - conversational_header: Intestazione pulita e specifica (es. "Ho cercato Garmin Forerunner 165" o "Ho cercato Adidas Adizero Dropset").
   - conversational_summary: 1 o 2 frasi concise ed esperte in italiano, con **i concetti chiave in grassetto** (es. "Ho trovato le **Adidas Adizero Dropset**: scarpe a base piatta e supporto laterale rinforzato per **allenamento ibrido, pesi e gare Hyrox**.").
   - curated_sections: 2 o 3 caroselli tematici coerenti (es. "Modelli Dropset Disponibili", "Alternative per Allenamento Ibrido"), con keyword pertinenti al modello cercato.
   - spotlight: Il miglior prodotto/modello cercato con badge ("Miglior Scelta" o "Prezzo Top") e 3 bullet point tecnici accurati.
   - spec_comparisons: 2 o 3 modelli a confronto per la card 'Confronto rapido' (come nello screenshot di Shop), con:
     * model_name: nome commerciale (es. "Adidas Adizero Dropset Pro Trainer", "Adidas Dropset 4 Power")
     * ideal_for: uso primario (es. "Allenamento ibrido e Hyrox", "Sollevamento pesi e forza")
     * strengths: punto forte tecnico (es. "Doppia densità e stabilità sotto carico", "Base ribassata per massimo radicamento")
     * target_keyword: termine mirato per agganciare il prodotto a database (es. "dropset", "forerunner 165")
   - follow_up_suggestions: 3 pulsanti pillola con domande realistiche da appassionato (es. ["Confrontale con le adidas Dropset 4", "Quali sono migliori per Hyrox?", "Cercale nella mia taglia"]).
   - chips: Filtri rapidi estratti (brand, prezzo, taglia).

REGOLE CRITICHE SUI FILTRI:
- NON INVENTARE FILTRI: se l'utente NON ha specificato esplicitamente un prezzo massimo o minimo (es. 'sotto 150 euro'), imposta SEMPRE 'max_price': null e 'min_price': null!
- GENERE: imposta 'gender' a 'Uomo' o 'Donna' SOLO se esplicitamente dichiarato nella query. Altrimenti 'gender': null.
- TARGET KEYWORDS: includi 2-4 parole chiave mirate sul MODELLO e sul PRODOTTO (es. ['Garmin Forerunner 165', 'Forerunner 165']). Metti il modello specifico per primo!
- STRINGHE DI TESTO: 'conversational_header' deve essere una stringa breve (es. 'Ho cercato Nike Vomero Plus') e 'conversational_summary' una breve frase descrittiva; non impostarli MAI a null anche se search_mode è classic.

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
  "spec_comparisons": [
    {
      "model_name": "Adidas Adizero Adios Pro 4",
      "ideal_for": "Gara e ritmi sostenuti",
      "strengths": "Lightstrike Pro, Energyrods, rocker",
      "target_keyword": "adizero"
    }
  ],
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
    def parse(cls, user_query: str, api_key: str, model: str = OPENROUTER_MODEL, force_mode: Optional[str] = None, context_query: Optional[str] = None) -> Optional[SmartSearchIntent]:
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

        messages = [
            {"role": "system", "content": cls.SYSTEM_PROMPT + mode_instruction}
        ]
        if context_query and context_query.strip():
            messages.append({"role": "user", "content": f"Ricerca precedente nel catalogo: {context_query.strip()}"})
            messages.append({"role": "assistant", "content": f"Ho compreso e mostrato i migliori modelli per {context_query.strip()}."})
            messages.append({"role": "user", "content": f"Domanda di follow-up o approfondimento: {user_query.strip()}"})
        else:
            messages.append({"role": "user", "content": user_query.strip()})

        for current_model in models_to_try:
            payload = {
                "model": current_model,
                "messages": messages,
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

                    chips_list = parsed.get("chips") or []
                    chips = [
                        SmartSearchChip(
                            id=c.get("id", f"chip_{i}"),
                            label=c.get("label", ""),
                            param_key=c.get("param_key", "keyword"),
                            value=str(c.get("value", ""))
                        )
                        for i, c in enumerate(chips_list)
                        if isinstance(c, dict) and c.get("label")
                    ]

                    curated_list = parsed.get("curated_sections") or []
                    curated_sections = [
                        CuratedSectionDef(
                            id=s.get("id", f"sec_{i}"),
                            title=s.get("title", ""),
                            subtitle=s.get("subtitle", ""),
                            keywords=s.get("keywords") or []
                        )
                        for i, s in enumerate(curated_list)
                        if isinstance(s, dict) and s.get("title")
                    ]

                    spotlight_data = parsed.get("spotlight")
                    spotlight_obj = None
                    if spotlight_data and isinstance(spotlight_data, dict) and spotlight_data.get("target_keyword"):
                        spotlight_obj = SpotlightDef(
                            target_keyword=str(spotlight_data.get("target_keyword")),
                            badge_text=str(spotlight_data.get("badge_text") or "Miglior Scelta"),
                            highlights=spotlight_data.get("highlights") or []
                        )

                    search_mode = parsed.get("search_mode", "deep_dive")
                    is_deep_dive = parsed.get("is_deep_dive", search_mode == "deep_dive")

                    if force_mode:
                        search_mode = force_mode
                        is_deep_dive = (force_mode == "deep_dive")

                    header_text = parsed.get("conversational_header") or f"Ho cercato {user_query}"
                    summary_text = parsed.get("conversational_summary") or f"Risultati per {user_query}"
                    explanation_text = parsed.get("explanation") or summary_text

                    target_kws = parsed.get("target_keywords") or [user_query]
                    if not isinstance(target_kws, list):
                        target_kws = [user_query]

                    features_list = parsed.get("features") or []
                    if not isinstance(features_list, list):
                        features_list = []

                    followups_list = parsed.get("follow_up_suggestions") or []
                    if not isinstance(followups_list, list):
                        followups_list = []

                    spec_list = parsed.get("spec_comparisons") or []
                    spec_comparisons = [
                        SpecComparisonDef(
                            model_name=str(sc.get("model_name", "")),
                            ideal_for=str(sc.get("ideal_for", "")),
                            strengths=str(sc.get("strengths", "")),
                            target_keyword=str(sc.get("target_keyword", "")) if sc.get("target_keyword") else None
                        )
                        for sc in spec_list
                        if isinstance(sc, dict) and sc.get("model_name")
                    ]

                    return SmartSearchIntent(
                        raw_query=user_query,
                        search_mode=search_mode,
                        is_deep_dive=is_deep_dive,
                        conversational_header=header_text,
                        conversational_summary=summary_text,
                        target_keywords=target_kws,
                        brand=parsed.get("brand"),
                        category=parsed.get("category"),
                        gender=parsed.get("gender"),
                        max_price=float(parsed["max_price"]) if parsed.get("max_price") is not None else None,
                        min_price=float(parsed["min_price"]) if parsed.get("min_price") is not None else None,
                        size=str(parsed["size"]) if parsed.get("size") else None,
                        features=features_list,
                        explanation=explanation_text,
                        chips=chips,
                        curated_sections=curated_sections,
                        spotlight=spotlight_obj,
                        spec_comparisons=spec_comparisons,
                        follow_up_suggestions=followups_list,
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

    def parse_query(self, user_query: str, force_mode: Optional[str] = None, context_query: Optional[str] = None) -> SmartSearchIntent:
        # 1. Check Multi-Tier Cache (L1 Memory LRU / L2 Disk Persistence)
        cache_lookup_query = f"{context_query.strip()} >> {user_query.strip()}" if context_query and context_query.strip() else user_query
        cached_data = self.cache_manager.get_intent(cache_lookup_query, force_mode=force_mode)
        if cached_data:
            try:
                return SmartSearchIntent.model_validate(cached_data)
            except Exception as e:
                logger.debug("Failed to re-validate cached intent: %s", e)

        intent = None
        if self.api_key:
            intent = OpenRouterParser.parse(user_query=user_query, api_key=self.api_key, model=self.model, force_mode=force_mode, context_query=context_query)

        if not intent:
            intent = LocalHeuristicParser.parse(user_query=user_query, force_mode=force_mode)

        # 2. Store in Multi-Tier Cache with 7-day TTL
        if intent:
            self.cache_manager.set_intent(cache_lookup_query, force_mode=force_mode, intent_data=intent)

        return intent
