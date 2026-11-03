import os
import json
import logging
import re
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field

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


class SmartSearchIntent(BaseModel):
    raw_query: str
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
    source: str = "local_heuristic"


# Sports domain knowledge base for athletic gear and running
SPORTS_KNOWLEDGE = {
    "max_cushion": {
        "models": ["asics nimbus", "hoka bondi", "brooks glycerin", "hoka clifton", "new balance 1080", "saucony triumph"],
        "label": "Massimo Ammortizzamento",
        "category": "running_shoes",
        "description": "Scarpe con massima protezione d'impatto per correre su asfalto, ideali per proteggere ginocchia, articolazioni e per pesi medi/elevati."
    },
    "daily_trainer": {
        "models": ["nike pegasus", "brooks ghost", "asics cumulus", "saucony ride", "mizuno wave rider"],
        "label": "Daily Trainer Polivalente",
        "category": "running_shoes",
        "description": "Scarpe versatili e resistenti per tutti gli allenamenti quotidiani su asfalto a ritmo medio."
    },
    "speed_race": {
        "models": ["nike alphafly", "nike vaporfly", "nike zoom fly", "nike streakfly", "adidas adizero", "asics metaspeed", "asics magic speed", "saucony endorphin", "brooks hyperion", "hoka cielo"],
        "label": "Velocità & Gara",
        "category": "running_shoes",
        "description": "Modelli leggeri e reattivi con schiuma performante e/o piastra in carbonio per ritmo veloce e gare."
    },
    "trail_running": {
        "models": ["hoka speedgoat", "salomon xa pro", "brooks cascadia", "asics trabuco", "la sportiva", "salomon pulsar"],
        "label": "Trail Running & Sterrato",
        "category": "running_shoes",
        "description": "Scarpe con tasselli e suola artigliata per sentieri, fango, sassi e montagna."
    },
    "gps_watch": {
        "models": ["garmin forerunner 165", "garmin forerunner 265", "garmin forerunner 965", "garmin forerunner", "garmin fenix", "garmin edge", "garmin instinct", "polar vantage", "polar grit", "suunto"],
        "label": "GPS & Smartwatch",
        "category": "gps_watch",
        "description": "Dispositivi GPS, cardiofrequenzimetri e ciclocomputer per il monitoraggio della performance atletica."
    },
    "eyewear": {
        "models": ["oakley radar", "oakley sutro", "oakley jawbreaker", "bliz", "rudy project", "smith"],
        "label": "Occhiali Tecnici",
        "category": "eyewear",
        "description": "Occhiali sportivi con lenti Prizm o fotocromatiche per running, ciclismo e outdoor."
    },
    "hydration": {
        "models": ["salomon active skin", "salomon adv skin", "camelbak", "borraccia soft flask"],
        "label": "Zaini & Idratazione",
        "category": "hydration",
        "description": "Gilet ergonomici traspiranti e borracce morbide per autosufficienza in corsa."
    },
    "fitness": {
        "models": ["theragun", "therabody", "pistola massaggiante", "compex"],
        "label": "Fitness & Recupero",
        "category": "fitness",
        "description": "Dispositivi per massaggio percussivo e recupero muscolare post-allenamento."
    },
    "nutrition": {
        "models": ["enervit gel", "enervit", "sis go", "maurten", "isocarb", "226ers"],
        "label": "Nutrizione Sportiva",
        "category": "nutrition",
        "description": "Gel isotonici, maltodestrine ed elettroliti per energia immediata e prevenzione crampi."
    },
    "padel": {
        "models": ["bullpadel hack", "bullpadel vertex", "nox at10", "babolat technical viper", "head speed pro", "siux diablo", "kuikma"],
        "label": "Padel & Racchette",
        "category": "padel",
        "description": "Racchette da padel, scarpe con suola a spiga, borse e accessori per il campo."
    },
    "cycling": {
        "models": ["garmin edge", "wahoo kickr", "tacx flux", "tacx neo", "favero assioma", "kask protone", "kask wasabi", "poc ventral", "castelli espresso"],
        "label": "Ciclismo & Rulli Smart",
        "category": "cycling",
        "description": "Rulli interattivi per allenamento indoor, ciclocomputer GPS, caschi e abbigliamento per bici da corsa e gravel."
    },
    "gear": {
        "models": ["poc", "kask", "abus", "casco", "abbigliamento termico"],
        "label": "Ciclismo & Attrezzatura",
        "category": "gear",
        "description": "Caschi tecnici, abbigliamento protettivo e accessori sportivi."
    }
}

KNOWN_BRANDS = [
    "nike", "adidas", "asics", "hoka", "brooks", "garmin", "polar", "suunto",
    "salomon", "oakley", "theragun", "therabody", "enervit", "saucony",
    "mizuno", "new balance", "new-balance", "la sportiva", "poc", "kask", "abus",
    "bullpadel", "nox", "babolat", "starvie", "siux", "wahoo", "tacx", "favero", "castelli"
]


class LocalHeuristicParser:
    """High-precision local NLP rule engine specialized for athletic gear e-commerce."""

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
    def parse(user_query: str) -> SmartSearchIntent:
        text = LocalHeuristicParser.normalize_typos(user_query.strip().lower())

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
                detected_brand = b.capitalize()
                if "new balance" in b or "new-balance" in b:
                    detected_brand = "New-balance"
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
            r"\b(alphafly(?:\s*\d+)?|vaporfly(?:\s*\d+)?|zoom\s*fly(?:\s*\d+)?|vomero(?:\s*\d+)?|pegasus(?:\s*\w+)?|nimbus(?:\s*\d+)?|clifton(?:\s*\d+)?|bondi(?:\s*\d+)?|ghost(?:\s*\d+)?|streakfly(?:\s*\d+)?|invincible(?:\s*\d+)?|adizero(?:\s*\w+)?|speedgoat(?:\s*\d+)?|forerunner(?:\s*\d+)?|fenix(?:\s*\d+)?|novablast(?:\s*\d+)?|superblast(?:\s*\d+)?|endorphin(?:\s*\w+)?|deviate(?:\s*\w+)?|radar\s*ev|sutro|hack(?:\s*\d+)?|vertex(?:\s*\d+)?|at10|kickr|flux(?:\s*\w+)?)\b",
            text
        )

        if exact_model_match:
            exact_val = exact_model_match.group(1).strip()
            if detected_brand and detected_brand.lower() not in exact_val.lower():
                target_keywords = [f"{detected_brand.lower()} {exact_val}", exact_val]
            else:
                target_keywords = [exact_val]
        else:
            # Clean substantive words from query (excluding stopwords and filler)
            stopwords = {"per", "la", "il", "lo", "i", "gli", "le", "un", "una", "uno", "di", "a", "da", "in", "con", "su", "scarpe", "scarpa", "modello", "sotto", "fino", "euro", "max", "taglia", "misura", "porto", "cerco", "voglio", "trova", "della"}
            tokens = [w for w in re.findall(r"\b[a-zA-Z0-9]+\b", text) if w not in stopwords and len(w) > 1]
            if tokens and len(tokens) >= 2:
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

        # 7. Chips & Human-friendly Explanation
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

        # Explanation sentence
        explanation_parts = [f"Trovati modelli per **{arch['label']}**"]
        if detected_brand:
            explanation_parts.append(f"di marca **{detected_brand}**")
        if max_price:
            explanation_parts.append(f"con budget massimo **€{max_price:.0f}**")
        if size:
            explanation_parts.append(f"disponibili in taglia **{size}**")
        explanation = " ".join(explanation_parts) + ". Confronto prezzi e spedizioni tra tutti i negozi partner."

        return SmartSearchIntent(
            raw_query=user_query,
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
            source="local_heuristic"
        )


class OpenRouterParser:
    """Uses OpenRouter AI (Llama 3.3 70B / Llama 3.1 8B) to understand conversational search intents."""

    SYSTEM_PROMPT = """Sei l'assistente IA di ricerca intelligente per l'app 'FitMatch', un comparatore di prezzi specializzato in scarpe da running, abbigliamento e tecnologia sportiva.

Il tuo obiettivo è analizzare la richiesta in linguaggio naturale dell'utente (anche colloquiale o con refusi) e tradurla in un oggetto JSON strutturato e accurato.

REGOLE ASSOLUTE PER TARGET_KEYWORDS:
1. SE L'UTENTE CERCA UN MODELLO SPECIFICO (es. "Nike alpha fly per la corsa", "Forerunner 165", "Novablast 4", "Hoka Clifton 9", "Asics Nimbus"):
   - target_keywords DEVE contenere il nome del modello esatto ricercato dall'utente (es. ["nike alphafly", "alphafly"] oppure ["garmin forerunner 165", "forerunner 165"]).
   - NON SOSTITUIRE MAI un modello specifico con un altro modello (es. NON sostituire Alphafly con Pegasus, NON sostituire Forerunner con scarpe da corsa)!
   - Imposta la marca corretta (es. brand: "Nike", brand: "Garmin", brand: "Asics").
   - Imposta la categoria corretta:
     * Orologi/Smartwatch/GPS (Forerunner, Fenix, Vantage, Grit, Polar, Garmin, Suunto) -> category: "gps_watch"
     * Scarpe da corsa/Gara/Allenamento (Alphafly, Pegasus, Nimbus, Clifton, Bondi, Vaporfly) -> category: "running_shoes"
     * Occhiali (Oakley, Sutro, Radar) -> category: "eyewear"

2. SE L'UTENTE FA UNA RICHIESTA GENERICA (es. "scarpe comode per iniziare a correre", "scarpe veloci con piastra in carbonio", "smartwatch per triathlon"):
   - Solo in questo caso proponi i modelli di riferimento ideali nel catalogo:
     * Ammortizzamento/Protezione: ["asics nimbus", "hoka bondi", "brooks glycerin", "hoka clifton"]
     * Gara/Carbonio/Velocità: ["nike alphafly", "nike vaporfly", "asics metaspeed", "adidas adizero pro", "saucony endorphin pro"]
     * Allenamento quotidiano: ["nike pegasus", "brooks ghost", "asics cumulus", "saucony ride"]
     * Trail: ["hoka speedgoat", "salomon xa pro", "brooks cascadia"]
     * GPS/Smartwatch: ["garmin forerunner", "garmin fenix", "polar vantage"]

Rispondi ESCLUSIVAMENTE con un JSON valido con questa esatta struttura:
{
  "target_keywords": ["modello 1", "modello 2"],
  "brand": "Nome Brand o null",
  "category": "running_shoes | gps_watch | eyewear | hydration | fitness | nutrition | gear",
  "gender": "Uomo | Donna | null",
  "max_price": float o null,
  "min_price": float o null,
  "size": "es. 43 o M o null",
  "features": ["waterproof", "cushioning", "racing", "trail", "carbon_plate"],
  "explanation": "1 frase amichevole in italiano",
  "chips": [
    {"id": "brand", "label": "Nike", "param_key": "brand", "value": "Nike"}
  ]
}
"""

    @classmethod
    def parse(cls, user_query: str, api_key: str, model: str = OPENROUTER_MODEL) -> Optional[SmartSearchIntent]:
        if not api_key:
            return None

        import urllib.request
        import ssl

        # Robust SSL Context for macOS / Linux Python
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

        models_to_try = [model]
        if OPENROUTER_BACKUP_MODEL and OPENROUTER_BACKUP_MODEL != model:
            models_to_try.append(OPENROUTER_BACKUP_MODEL)

        for current_model in models_to_try:
            payload = {
                "model": current_model,
                "messages": [
                    {"role": "system", "content": cls.SYSTEM_PROMPT},
                    {"role": "user", "content": user_query}
                ],
                "temperature": 0.1,
                "max_tokens": 500
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
                with urllib.request.urlopen(req, timeout=7.5, context=ctx) as resp:
                    if resp.status != 200:
                        logger.warning("OpenRouter API returned status %s for model %s", resp.status, current_model)
                        continue
                    data = json.loads(resp.read().decode("utf-8"))
                    content = data["choices"][0]["message"]["content"]

                    # Extract JSON block robustly
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

                    return SmartSearchIntent(
                        raw_query=user_query,
                        target_keywords=parsed.get("target_keywords") or [user_query],
                        brand=parsed.get("brand"),
                        category=parsed.get("category"),
                        gender=parsed.get("gender"),
                        max_price=float(parsed["max_price"]) if parsed.get("max_price") is not None else None,
                        min_price=float(parsed["min_price"]) if parsed.get("min_price") is not None else None,
                        size=str(parsed["size"]) if parsed.get("size") else None,
                        features=parsed.get("features", []),
                        explanation=parsed.get("explanation", "Risultati selezionati con intelligenza artificiale"),
                        chips=chips,
                        source="openrouter"
                    )
            except Exception as e:
                logger.warning("OpenRouter call failed for model %s: %s", current_model, e)
                continue

        return None


class SmartSearchEngine:
    """Unified coordinator with dual-engine AI parser, in-memory LRU cache, and SQL aggregator."""

    _CACHE: Dict[str, SmartSearchIntent] = {}

    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None):
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY", "")
        self.model = model or os.environ.get("OPENROUTER_MODEL", OPENROUTER_MODEL)

    def parse_query(self, user_query: str) -> SmartSearchIntent:
        key = user_query.strip().lower()
        if key in self._CACHE:
            return self._CACHE[key]

        intent = None
        if self.api_key:
            intent = OpenRouterParser.parse(user_query=user_query, api_key=self.api_key, model=self.model)

        if not intent:
            intent = LocalHeuristicParser.parse(user_query=user_query)

        # Cache up to 200 recent queries
        if len(self._CACHE) > 200:
            self._CACHE.clear()
        self._CACHE[key] = intent
        return intent
