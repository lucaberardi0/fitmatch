import re
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
from fitmatch.models import Offer, MatchedProductGroup

KNOWN_BRANDS = [
    # Top Running & Athletic Brands
    "nike", "adidas", "asics", "brooks", "hoka", "on running", "on", "saucony",
    "puma", "new balance", "mizuno", "under armour", "salomon", "altra", "la sportiva",
    "scarpa", "dynafit", "inov-8", "topo athletic", "joma", "newton", "craft", "diadora",
    "nnormal", "reebok", "veja", "scott", "merrell", "361", "karhu", "ronhill",

    # Technical Running & Outdoor Apparel Brands
    "odlo", "saysky", "maloja", "alé", "x-bionic", "xbionic", "uyn", "2xu",
    "gorewear", "cmp", "karpos", "montura", "ciele", "42k running", "42k", "otso",
    "oxsitis", "raidlight", "bv sport", "sidas", "soar", "satisfy", "tracksmith",
    "regatta", "helly hansen", "haglöfs", "haglofs", "rab", "salewa", "mammut",
    "millet", "the north face", "north face", "patagonia", "columbia", "arc'teryx", "arcteryx",
    "black diamond", "petzl", "leki", "camelbak", "osprey", "deuter", "buff", "compressport",

    # Electronics & Optics
    "garmin", "polar", "suunto", "coros", "amazfit", "wahoo", "bryton", "igpsport", "oakley", "bliz",
    "rudy project", "100%", "shokz", "aftershokz", "apple", "huawei",

    # Cycling & Helmets
    "shimano", "poc", "kask", "abus", "castelli", "sportful", "santini", "giro",
    "sidi", "sram", "campagnolo", "met", "tacx", "favero", "assioma", "elite", "chris king",

    # Padel & Tennis
    "bullpadel", "babolat", "head", "wilson", "nox", "starvie", "siux", "dunlop", "kuikma",

    # Recovery, Fitness & Nutrition
    "therabody", "theragun", "hyperice", "compex", "enervit", "sis", "maurten",
    "named sport", "powerbar", "ethic sport", "226ers", "leone 1947",

    # Decathlon Brands
    "decathlon", "kiprun", "evadict", "kalenji", "quechua", "forclaz", "btwin",
    "van rysel", "rockrider", "triban", "domyos", "artengo"
]

STORE_NAMES_LOWER = {
    "mister running", "misterrunning", "alltricks", "top4running", "maxi sport",
    "maxisport", "cisalfa", "cisalfa sport", "running warehouse", "runningwarehouse",
    "deporvillage", "sportler", "nencini", "nencini sport", "df sport specialist",
    "tradeinn", "decathlon", "generic", "none"
}

BRAND_ALIASES = {
    "on running": "On",
    "theragun": "Therabody",
    "north face": "The North Face",
    "arcteryx": "Arc'teryx",
    "kiprun": "Kiprun",
    "kalenji": "Kalenji",
    "xbionic": "X-Bionic",
    "x-bionic": "X-Bionic",
    "42k running": "42K Running",
    "42k": "42K Running",
    "2xu": "2XU",
    "uyn": "UYN",
    "cmp": "CMP",
    "alé": "Alé",
    "igpsport": "iGPSPORT"
}

ICONIC_MODEL_BRANDS = {
    # Adidas
    "supernova": "Adidas", "adizero": "Adidas", "adios": "Adidas", "boston": "Adidas",
    "takumi": "Adidas", "terrex": "Adidas", "ultraboost": "Adidas", "sl20": "Adidas", "dropset": "Adidas",
    # Nike
    "pegasus": "Nike", "vomero": "Nike", "alphafly": "Nike", "vaporfly": "Nike",
    "invincible": "Nike", "streakfly": "Nike", "infinity": "Nike", "wildhorse": "Nike",
    "zegama": "Nike", "metcon": "Nike",
    # Reebok
    "nano": "Reebok", "nanoflex": "Reebok",
    # Under Armour
    "tribase": "Under Armour",
    # Puma
    "deviate nitro": "Puma", "velocity nitro": "Puma", "magnify nitro": "Puma", "foreverrun": "Puma", "fast-r": "Puma",
    # Asics
    "nimbus": "Asics", "cumulus": "Asics", "kayano": "Asics", "novablast": "Asics",
    "superblast": "Asics", "metaspeed": "Asics", "magic speed": "Asics", "trabuco": "Asics",
    "gt-2000": "Asics", "gt-1000": "Asics", "fujitrail": "Asics",
    # Brooks
    "ghost": "Brooks", "glycerin": "Brooks", "adrenaline": "Brooks", "hyperion": "Brooks",
    "cascadia": "Brooks", "launch": "Brooks", "catamount": "Brooks", "caldera": "Brooks",
    # Hoka
    "clifton": "Hoka", "bondi": "Hoka", "speedgoat": "Hoka", "mach": "Hoka",
    "arahi": "Hoka", "challenger": "Hoka", "cielo": "Hoka", "rocket x": "Hoka",
    # Saucony
    "endorphin": "Saucony", "triumph": "Saucony", "ride": "Saucony", "guide": "Saucony",
    "kinvara": "Saucony", "peregrine": "Saucony", "tempus": "Saucony",
    # Mizuno
    "wave rider": "Mizuno", "wave inspire": "Mizuno", "wave rebellion": "Mizuno", "wave sky": "Mizuno",
    # On
    "cloudmonster": "On", "cloudsurfer": "On", "cloudrunner": "On", "cloudflow": "On",
    "cloudboom": "On", "cloudstratus": "On", "cloudtilt": "On", "cloudeclipse": "On",
    # New Balance
    "fuelcell": "New Balance", "fresh foam": "New Balance", "hierro": "New Balance",
    "sc elite": "New Balance", "supercomp": "New Balance",
    # Garmin
    "forerunner": "Garmin", "fenix": "Garmin", "epix": "Garmin", "instinct": "Garmin",
    "venu": "Garmin", "vivoactive": "Garmin", "edge": "Garmin",
    # Polar
    "vantage": "Polar", "grit x": "Polar", "pacer": "Polar", "ignite": "Polar",
    # Coros & Suunto
    "pace 3": "Coros", "pace 4": "Coros", "pace pro": "Coros", "apex 2": "Coros", "apex 4": "Coros", "vertix": "Coros",
    "suunto race": "Suunto", "suunto vertical": "Suunto", "suunto run": "Suunto",
    # Salomon
    "speedcross": "Salomon", "sense ride": "Salomon", "pulsar": "Salomon", "xa pro": "Salomon",
    "active skin": "Salomon", "adv skin": "Salomon",
    # Oakley
    "sutro": "Oakley", "radar": "Oakley", "jawbreaker": "Oakley", "encoder": "Oakley",
    # Bullpadel
    "hack": "Bullpadel", "vertex": "Bullpadel", "flow": "Bullpadel", "indiga": "Bullpadel",
    # Wahoo / Tacx
    "kickr": "Wahoo", "elemnt": "Wahoo", "flux": "Tacx", "neo": "Tacx"
}

ARTICLE_PATTERNS: List[Tuple[str, List[str]]] = [
    ("case", [
        r"\bcustodi[ae]\b", r"\bcases?\b", r"\bcovers?\b", r"\bhousse\b",
        r"\bpellicol[ae]\b", r"\bvetro temp[ea]rato\b", r"\bsalvaschermo\b",
        r"\bpanzerglass\b", r"\bprotezion[ei]\s+(?:lo\s+)?schermo\b",
        r"\bidrogel\b", r"\bhydrogel\b", r"\bsportenzia\b"
    ]),
    ("mount", [
        r"\bsupport[oi]\b", r"\bstaff[ae]\b", r"\bmounts?\b", r"\bstaffetta\b", r"\bportaborracc(?:ia|e|ie)\b",
        r"\bflush\s+out\s+front\b", r"\bextended\s+out\b"
    ]),
    ("strap", [
        r"\bcinturin[oi]\b", r"\bstraps?\b", r"\bwristband\b", r"\bbraccialetto\b", r"\bbracelet\b"
    ]),
    ("pack", [
        r"\bpacks?\b", r"\bbundles?\b", r"\bset\b", r"\bkit\b", r"\bcoppia\b", r"\bduo\b"
    ]),
    ("sensor", [
        r"\bfascia cardio\b", r"\bhrm\b", r"\bsensore\b", r"\bspeed sensor\b", r"\bcadence\b"
    ]),
    ("cycling", [
        r"\bciclocomputer\b", r"\bbike\s+computer\b", r"\bcontachilometri\b", r"\bcontatore\b",
        r"\bgarmin\s+edge\b", r"\bedge\s+(?:130|530|540|550|830|840|1030|1040|1050|explore|mtb)\b",
        r"\bwahoo\s+elemnt\b", r"\bbryton\b", r"\bigpsport\b"
    ]),
    ("gps_watch", [
        r"\bsmartwatch\b", r"\borologi[o]?\b", r"\bforerunner\b", r"\bfenix\b",
        r"\bepix\b", r"\binstinct\b", r"\bvenu\b", r"\bvivoactive\b",
        r"\bcardiofrequenzimetr[oi]\b", r"\bapple\s+watch\b",
        r"\bt[\s-]?rex\s*\d\b", r"\bamazfit\b", r"\bcoros\s+(?:pace|apex|vertix|nomad)\b",
        r"\bpolar\s+(?:vantage|pacer|grit|ignite)\b", r"\bsuunto\s+(?:race|vertical|9|peak|run)\b"
    ]),
    ("nutrition", [
        r"\bgel\s+energetic[oi]\b", r"\benervit\b", r"\bisocarb\b", r"\bbarrett[ae]\b",
        r"\bmaltodestrin[ae]\b", r"\bsali\s+minerali\b", r"\bmaurten\b", r"\b226ers\b",
        r"\bintegrator[ei]\b", r"\bwhey\b", r"\bcreatina\b"
    ]),
    ("hydration", [
        r"\bzain[oi]\b", r"\bactive\s+skin\b", r"\badv\s+skin\b", r"\bsoft\s*flask\b",
        r"\bflask\b", r"\bborracc(?:ia|e|ie)\b", r"\bsacca\s+idrica\b", r"\bcamelbak\b",
        r"\bgilet\s+(?:da\s+)?(?:trail|idratazione|running|corsa)\b"
    ]),
    ("eyewear", [
        r"\bocchial[ie]\b", r"\bsunglasses\b", r"\blent[ie]\b", r"\bmascher[ae]\b",
        r"\bsutro\b", r"\bjawbreaker\b", r"\bradar\s+ev\b"
    ]),
    ("racket", [
        r"\bracchett[ae]\b", r"\bpala\b", r"\bpalas\b", r"\bracks?\b", r"\bpadel\b"
    ]),
    ("trainer", [
        r"\brull[oi]\b", r"\bsmart trainer\b", r"\bkickr\b", r"\bflux\b", r"\bsuito\b", r"\bdireto\b"
    ]),
    ("jacket", [
        r"\bgiacc(?:a|he)\b", r"\bgiubbin[oi]\b", r"\bgiubbott[oi]\b", r"\bjackets?\b",
        r"\bantivento\b", r"\bwindbreaker\b", r"\bwindstopper\b", r"\bgilet\b", r"\bvest\b",
        r"\banorak\b", r"\bshell\b", r"\bpiumin[oi]\b", r"\bcappott[oi]\b", r"\bparka\b"
    ]),
    ("pants", [
        r"\bpantalon[ie]\b", r"\bpantaloncin[oi]\b", r"\bshorts?\b", r"\btights?\b",
        r"\bleggings?\b", r"\bcapri\b", r"\bcalzamagli[ae]\b", r"\bbermuda\b", r"\bsprinter\b"
    ]),
    ("top", [
        r"\bmagli[ae]\b", r"\bmagliett[ae]\b", r"\bt-?shirts?\b", r"\bcanott[ae]\b",
        r"\bsinglets?\b", r"\btops?\b", r"\bfelp[ae]\b", r"\bhoodie\b", r"\blong\s+sleeve\b",
        r"\bshort\s+sleeve\b", r"\bsleeveless\b", r"\bmanic(?:a|he)\s+lung(?:a|he)\b",
        r"\bmanic(?:a|he)\s+cort(?:a|e)\b", r"\bjersey\b", r"\bpolo\b", r"\breggisen[oi]\b", r"\bbra\b"
    ]),
    ("socks", [
        r"\bcalz[ae]\b", r"\bcalzin[oi]\b", r"\bsocks?\b"
    ]),
    ("shoes", [
        r"\bscarp[ae]\b", r"\bshoes?\b", r"\bsneakers?\b", r"\bcalzatur[ae]\b",
        r"\bstival[ie]\b", r"\bstivalett[oi]\b", r"\bciabatt[ae]\b", r"\bchiodat[ae]\b",
        r"\bscarpon[ie]\b", r"\bscarpett[ae]\b"
    ]),
    ("gear", [
        r"\btheragun\b", r"\bpistola\s+(?:per\s+)?massaggi\b", r"\bstimolatore\s+muscolare\b",
        r"\bcasc(?:o|hi)\b", r"\bhelmet\b", r"\bcappellin[oi]\b", r"\bcappell[oi]\b", r"\bcap\b",
        r"\bberrett[oi]\b", r"\bbeanie\b", r"\bvisier[ae]\b", r"\bfasci[ae]\b",
        r"\bguant[oi]\b", r"\bscaldacollo\b", r"\bscaldamani\b", r"\bpolsin[oi]\b",
        r"\btelo\b", r"\basciugaman[oi]\b", r"\bmanubri[o]?\b", r"\bkettlebell\b",
        r"\bcintur[ae]\b", r"\bbastoncini\b", r"\bshampoo\b", r"\bsterzo\b",
        r"\bpignoni\b", r"\bguarnitura\b", r"\bpedal[ei]\b", r"\bcoperton[ei]\b"
    ])
]

TECH_FABRICS = [
    "dri-fit adv", "dri-fit", "dri fit", "drifit", "aeroready", "heatgear", "coldgear",
    "iso-chill", "climalite", "therma-fit", "tech fleece", "climacool", "air zoom",
    "air", "gel", "fuelcell", "fresh foam x", "fresh foam", "super comp", "supercomp"
]

STOPWORDS = {
    "scarpe", "scarpa", "shoes", "shoe", "sneakers", "calzature", "running", "corsa", "asfalto",
    "uomo", "donna", "unisex", "bambino", "bambina", "junior", "ragazzo", "ragazza",
    "m", "w", "men", "women", "mens", "womens", "wmns",
    "smartwatch", "orologio", "gps", "multisport", "cardiofrequenzimetro", "ciclocomputer",
    "pistola", "massaggi", "stimolatore", "muscolare",
    "custodia", "silicone", "housse", "cover", "pack", "bundle", "kit", "cinturino", "strap",
    "allenamento", "palestra", "training", "workout", "fitness",
    "performance", "sportswear", "originals", "athletics", "athletic", "road",
    "per", "di", "con", "e", "the", "in", "de", "ed", "da", "a", "la", "il", "le", "un", "una",
    "nero", "nera", "neri", "nere", "grigio", "grigia", "grigi", "grigie", "bianco", "bianca", "bianchi", "bianche",
    "rosso", "rossa", "rossi", "rosse", "blu", "giallo", "gialla", "gialle", "fluor", "verde", "verdi", "rosa", "viola",
    "beige", "arancione", "azzurro", "azzurra", "argento", "oro", "bordeaux", "turchese", "corallo",
    "militare", "lilla", "acqua", "oliva", "chiaro", "scuro", "multicolore", "multicolor",
    "naval", "cobalt", "whitestone", "mist", "lime", "menta",
    "silver", "white", "black", "grey", "anthracite", "smoke", "core"
}


class ProductNormalizer:
    """
    Advanced Anti-Mismatch Engine:
    Categorizes article types, extracts exact model versions, eliminates accessories
    from device clusters, and dynamically rejects price outliers.
    """

    @staticmethod
    def extract_gender(title: str, url: str = "") -> str:
        """Detect gender category from text or URL."""
        combined = f"{title} {url}".lower()
        if re.search(r"\b(bambin[oi]|junior|jr|kids?|boy|girl)\b", combined):
            return "Junior"
        if re.search(r"\b(donna|women|womens|wmns|\bw\b)\b", combined):
            return "Donna"
        if re.search(r"\b(uomo|men|mens|\bm\b)\b", combined):
            return "Uomo"
        return "Unisex"

    @classmethod
    def extract_brand(cls, title: str, existing_brand: Optional[str] = None) -> Optional[str]:
        """Detect standard canonical brand name from title or existing hint, avoiding false-positive collisions."""
        lower_title = (title or "").lower()
        ambiguous_brands = {"scarpa", "elite", "on", "head", "polar"}

        # 1. Check non-ambiguous known brands in the title first (longest match first)
        primary_brands = [b for b in KNOWN_BRANDS if b not in ambiguous_brands]
        for b in sorted(primary_brands, key=len, reverse=True):
            if re.search(rf"\b{re.escape(b)}\b", lower_title):
                return BRAND_ALIASES.get(b, b.title())

        # 2. Check existing_brand if valid and not a store name or ambiguous false positive
        if existing_brand:
            eb_lower = existing_brand.strip().lower()
            if eb_lower not in STORE_NAMES_LOWER and eb_lower not in ambiguous_brands:
                if eb_lower in BRAND_ALIASES:
                    return BRAND_ALIASES[eb_lower]
                for b in primary_brands:
                    if b == eb_lower:
                        return BRAND_ALIASES.get(b, b.title())

        # 3. Check iconic model mapping (before ambiguous words like 'elite' or 'scarpa')
        is_bike_headset = any(w in lower_title for w in ("sterzo", "chris king", "headset", "nothreadset", "griplock", "is42"))
        for model_sub, brand_name in ICONIC_MODEL_BRANDS.items():
            if model_sub == "dropset" and is_bike_headset:
                continue
            if re.search(rf"\b{re.escape(model_sub)}\b", lower_title):
                return brand_name
        if "adizero" in lower_title:
            return "Adidas"

        # 4. Disambiguate ambiguous brand names ('scarpa', 'elite', 'on', 'head')
        if re.search(r"\bscarpa\b", lower_title):
            scarpa_models = {
                "ribelle", "mojito", "spin", "golden gate", "mescalito", "atom", "chimera",
                "drago", "phantom", "zen", "boostic", "instinct", "marmolada", "rapid", "rush",
                "kinesis", "maestrale", "alien"
            }
            if any(m in lower_title for m in scarpa_models) or any(
                w in lower_title for w in ("arrampicata", "alpinismo", "climbing", "scarpette", "scarponi")
            ):
                return "Scarpa"

        if re.search(r"\belite\b", lower_title):
            elite_cycling_terms = {
                "rullo", "rulli", "trainer", "suito", "direto", "tuo", "qubo", "novo",
                "arion", "portaborraccia", "borraccia", "fly tex", "custom race", "sterzo"
            }
            if any(w in lower_title for w in elite_cycling_terms):
                return "Elite"

        if re.search(r"\bon\b", lower_title):
            if lower_title.startswith("on ") or any(w in lower_title for w in ("cloud", "roger", "on running")):
                return "On"

        if re.search(r"\bhead\b", lower_title):
            if any(w in lower_title for w in ("padel", "racchetta", "pala", "speed", "extreme", "delta", "gravity", "radical", "tennis", "sci")):
                return "Head"

        if re.search(r"\bpolar\b", lower_title):
            if not any(w in lower_title for w in ("felpa", "pile", "giacca", "fleece", "lacoste", "columbia", "cardigan", "scaldacollo")):
                return "Polar"

        if existing_brand and existing_brand.strip().lower() not in STORE_NAMES_LOWER and existing_brand.strip().lower() != "elite":
            return existing_brand.strip().capitalize()
        return None

    @classmethod
    def detect_article_type(cls, title: str) -> str:
        """Categorize item into article type (e.g. case, strap, pack, jacket, pants, top, shoes, gps_watch, gear)."""
        tl = (title or "").lower()
        for atype, patterns in ARTICLE_PATTERNS:
            for pattern in patterns:
                if re.search(pattern, tl):
                    return atype
        # Check if it matches any iconic shoe/watch model before defaulting
        for model_sub, brand_name in ICONIC_MODEL_BRANDS.items():
            if re.search(rf"\b{re.escape(model_sub)}\b", tl):
                if brand_name in ("Garmin", "Polar", "Coros", "Suunto"):
                    return "cycling" if model_sub == "edge" else "gps_watch"
                if brand_name == "Oakley":
                    return "eyewear"
                if brand_name == "Bullpadel":
                    return "racket"
                if brand_name in ("Wahoo", "Tacx"):
                    return "trainer"
                return "shoes"
        return "shoes"

    @classmethod
    def clean_title(cls, title: str, brand: Optional[str] = None) -> Tuple[str, Optional[str]]:
        """Splits off colorway/descriptions and strips noise words while preserving model version and garment type."""
        # Normalize fractions like 1/2 zip before splitting on slashes/punctuation
        norm_title = re.sub(r"\b1\s*/\s*2\s*zip\b", "half zip", title or "", flags=re.IGNORECASE)
        norm_title = re.sub(r"\ba\s+maniche\s+lunghe\b|\bmaniche\s+lunghe\b", "manica lunga", norm_title, flags=re.IGNORECASE)
        norm_title = re.sub(r"\ba\s+maniche\s+corte\b|\bmaniche\s+corte\b", "manica corta", norm_title, flags=re.IGNORECASE)

        # Split on dash or pipe that separates model from color description or category breadcrumb
        parts = re.split(r"\s+[-–—|]\s+", norm_title)
        base = parts[0]
        colorway = parts[-1].strip() if len(parts) > 1 else None

        # Check if parts[0] is an internal SKU/MPN code (e.g. Decathlon "NIKE FQ0912-400 — Scarpe da running uomo Nike Pegasus 41"),
        # a store name, or a generic category breadcrumb
        if len(parts) > 1:
            is_sku_code = bool(re.search(r"\b[A-Za-z0-9]{4,10}[-_][A-Za-z0-9]{2,6}\b", parts[0]))
            is_store_name = any(s in parts[0].lower() for s in ("decathlon", "cisalfa", "maxisport", "nencini", "top4running", "misterrunning"))
            generic_words = STOPWORDS.union({"running", "corsa", "trail", "asics", "nike", "adidas", "mizuno", "brooks", "hoka", "altra", "new", "balance", "saucony", "on"})
            tokens_0 = set(re.findall(r"\b[a-zA-Z0-9]+\b", parts[0].lower()))
            if is_sku_code or is_store_name or tokens_0.issubset(generic_words):
                best_part = None
                for p in parts[1:]:
                    p_toks = set(re.findall(r"\b[a-zA-Z0-9]+\b", p.lower()))
                    non_stop = p_toks - STOPWORDS
                    if non_stop:
                        if re.search(r"\d", p) or any(k in p.lower() for k in ICONIC_MODEL_BRANDS):
                            best_part = p
                            break
                        elif best_part is None:
                            best_part = p
                if best_part:
                    base = best_part
                    colorway = parts[0].strip()

        text = base.lower()
        text = re.sub(r"\(.*?\)", "", text)
        # Preserve x-bionic and gt-2000 compounds before stripping punctuation
        text = re.sub(r"\bx[\s-]bionic\b", "xbionic", text)
        text = re.sub(r"\bt[\s-]rex\b", "trex", text)
        text = re.sub(r"\bt[\s-]shirt\b", "tshirt", text)
        text = re.sub(r"[^\w\s]", " ", text)

        # Remove all occurrences of the brand
        if brand:
            b_low = brand.lower()
            text = re.sub(rf"\b{re.escape(b_low)}\b", " ", text)
            if b_low == "x-bionic":
                text = re.sub(r"\bxbionic\b", " ", text)
            for p in b_low.split():
                if len(p) > 2:
                    text = re.sub(rf"\b{re.escape(p)}\b", " ", text)

        # Standardize known compounds
        text = re.sub(r"\bsuper\s+comp\b", "supercomp", text)
        for tf in sorted(TECH_FABRICS, key=len, reverse=True):
            if tf not in ("super comp", "supercomp"):
                text = re.sub(rf"\b{re.escape(tf)}\b", " ", text)

        tokens = text.split()
        cleaned_tokens = []
        for idx, t in enumerate(tokens):
            if t in STOPWORDS or re.match(r"^\d{6,}$", t) or t == "s":
                continue
            # Drop connector 'x' in "Puma x Hyrox"
            if t == "x" and idx + 1 < len(tokens) and tokens[idx + 1] == "hyrox":
                continue
            cleaned_tokens.append(t)

        # Deduplicate consecutive identical tokens
        dedup_tokens = []
        for t in cleaned_tokens:
            if not dedup_tokens or dedup_tokens[-1] != t:
                dedup_tokens.append(t)

        return " ".join(dedup_tokens).strip(), colorway

    @classmethod
    def build_canonical_display_name(cls, title: str, brand: Optional[str] = None) -> str:
        """Build a clean, complete, human-readable canonical product title from an offer title."""
        eff_brand = cls.extract_brand(title, brand)
        cleaned_base, _ = cls.clean_title(title, eff_brand)
        if not cleaned_base:
            cleaned_base = re.sub(r"\s+", " ", (title or "").strip())
        canonical = f"{eff_brand} {cleaned_base.title()}" if eff_brand and eff_brand.lower() not in cleaned_base.lower() else cleaned_base.title()
        if eff_brand:
            canonical = re.sub(r"^(" + re.escape(eff_brand) + r"\s+)+", f"{eff_brand} ", canonical, flags=re.IGNORECASE).strip()
        return canonical

    @classmethod
    def extract_cluster_key(cls, offer: Offer) -> str:
        """
        Generates a strictly partitioned cluster key:
        Prevents cases/straps/packs from sharing keys with core devices or shoes,
        and retains exact model generation numbers (e.g. 965, 55, 41, Pro 5, v14, Hyrox).
        If a clean barcode/GTIN is present, ensures 100% deterministic grouping.
        """
        if offer.barcode and len(offer.barcode.strip()) >= 8:
            return f"barcode:{offer.barcode.strip()}"

        brand = cls.extract_brand(offer.title, offer.brand) or "Generic"
        gender = cls.extract_gender(offer.title, offer.url)
        art_type = cls.detect_article_type(offer.title)
        cleaned_base, _ = cls.clean_title(offer.title, brand)

        tokens = cleaned_base.split()
        model_parts: List[str] = []
        i = 0

        important_qualifiers = {
            "pro", "music", "elite", "plus", "s", "x", "max", "tr", "gtx", "trail",
            "hyrox", "solar", "amp", "se", "power", "pwr", "warm", "winter"
        }

        while i < len(tokens):
            t = tokens[i]
            if t == "hyrox":
                i += 1
                continue
            model_parts.append(t)
            # Only treat digits, v+digits, or multi-char Roman numerals (ii, iii, iv, vi...) as version numbers
            # NEVER treat single 'x', 'i', 'v' as Roman numerals (fixes 'Puma x Hyrox', 'X-Bionic', etc.)
            is_num = bool(re.search(r"\d", t) or re.match(r"^(v\d+|ii|iii|iv|vi|vii|viii|ix|xi|xii|xiii|xiv|xv)$", t))
            if is_num:
                # Retain model qualifiers following a number (e.g. 'deviate nitro 4 hyrox', '1080 v15', 'adios pro 4')
                while i + 1 < len(tokens) and tokens[i + 1] in important_qualifiers:
                    if tokens[i + 1] != "hyrox":
                        model_parts.append(tokens[i + 1])
                    i += 1
                break
            elif t in ("pro", "elite", "prime", "relief") and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if re.search(r"\d", nxt) or nxt in ("plus", "max", "ultra", "v6", "v5", "v4", "trail", "hyrox"):
                    if nxt != "hyrox":
                        model_parts.append(nxt)
                    i += 1
                    break
            elif len(model_parts) >= 4:
                for rem_t in tokens[i + 1:]:
                    if (rem_t in ("gtx", "lunga", "sleeve", "warm", "merino", "zip") or bool(re.search(r"\d", rem_t))) and rem_t not in model_parts:
                        model_parts.append(rem_t)
                break
            i += 1

        if "hyrox" in tokens and "hyrox" not in model_parts:
            model_parts.append("hyrox")

        model_key = " ".join(model_parts).strip() if model_parts else "general"

        # Devices, electronics, eyewear, cycling trainers, rackets & gear are genderless
        if art_type in ("gps_watch", "cycling", "gear", "eyewear", "racket", "trainer", "sensor", "mount", "case", "strap", "pack", "nutrition", "hydration"):
            return f"{brand.lower()} {model_key} [{art_type}]"

        # Racing super-shoes (e.g. adios pro, alphafly, vaporfly, metaspeed, cielo, vanish, endorphin elite, sc elite)
        # are inherently unisex models with identical specs across genders
        is_racing_super_shoe = any(
            rw in model_key.lower() for rw in ("adios pro", "alphafly", "vaporfly", "metaspeed", "cielo", "vanish", "endorphin elite", "sc elite")
        )
        if is_racing_super_shoe:
            return f"{brand.lower()} {model_key} [{art_type}]"

        # Standard adult shoes: bridge 'Unisex' and 'Uomo' into standard adult cluster
        # (while preserving distinct 'Donna' and 'Junior' if women/kids specific)
        cluster_gender = gender
        if cluster_gender in ("Unisex", "Uomo"):
            cluster_gender = "Adult"

        return f"{brand.lower()} {model_key} [{art_type}] [{cluster_gender}]"

    @classmethod
    def partition_by_price_sanity(cls, cluster_offers: List[Offer]) -> List[List[Offer]]:
        """
        Detects extreme pricing anomalies (e.g. an €18 case mixed with €230 GPS)
        and isolates outliers into their own separate comparison cards.
        """
        if len(cluster_offers) <= 1:
            return [cluster_offers]

        sorted_offers = sorted(cluster_offers, key=lambda o: o.price)
        prices = [o.price for o in sorted_offers if o.price and o.price > 0]
        if not prices:
            return [sorted_offers]

        median_price = prices[len(prices) // 2]
        if median_price <= 0:
            return [sorted_offers]

        main_group: List[Offer] = []
        outliers: List[Offer] = []

        for o in sorted_offers:
            if not o.price:
                continue
            ratio = o.price / median_price
            # If an offer is less than 38% or more than 260% of the median, treat as outlier
            if ratio < 0.38 or ratio > 2.60:
                outliers.append(o)
            else:
                main_group.append(o)

        partitions: List[List[Offer]] = []
        if main_group:
            partitions.append(main_group)
        for out in outliers:
            partitions.append([out])

        return partitions

    @classmethod
    def group_offers(cls, offers: List[Offer]) -> List[MatchedProductGroup]:
        """Group offers from different stores into consolidated, verified matched product cards."""
        clusters: Dict[str, List[Offer]] = defaultdict(list)

        for offer in offers:
            key = cls.extract_cluster_key(offer)
            clusters[key].append(offer)

        groups: List[MatchedProductGroup] = []

        for key, raw_cluster_offers in clusters.items():
            # Apply price sanity guardrail to partition any accidental outliers
            partitions = cls.partition_by_price_sanity(raw_cluster_offers)

            for cluster_offers in partitions:
                if not cluster_offers:
                    continue

                sample_offer = max(cluster_offers, key=lambda o: len(o.title))
                brand = cls.extract_brand(sample_offer.title, sample_offer.brand)
                gender = cls.extract_gender(sample_offer.title, sample_offer.url)
                art_type = cls.detect_article_type(sample_offer.title)

                # Canonical Name Generation
                cleaned_base, _ = cls.clean_title(sample_offer.title, brand)
                canonical = f"{brand} {cleaned_base.title()}" if brand and brand.lower() not in cleaned_base.lower() else cleaned_base.title()
                if brand:
                    canonical = re.sub(r"^(" + re.escape(brand) + r"\s+)+", f"{brand} ", canonical, flags=re.IGNORECASE).strip()

                if art_type == "case" and "custodia" not in canonical.lower() and "case" not in canonical.lower():
                    canonical += " (Custodia)"
                elif art_type == "strap" and "cinturino" not in canonical.lower():
                    canonical += " (Cinturino)"
                elif art_type == "pack" and "pack" not in canonical.lower():
                    canonical += " (Bundle/Pack)"
                elif art_type == "jacket" and not any(w in canonical.lower() for w in ("giacca", "jacket", "gilet")):
                    canonical += " (Giacca)"
                elif art_type == "pants" and not any(w in canonical.lower() for w in ("pantaloni", "pantaloncini", "shorts", "tights", "leggings")):
                    canonical += " (Pantaloni/Shorts)"
                elif art_type == "top" and not any(w in canonical.lower() for w in ("maglia", "maglietta", "t-shirt", "canotta", "top")):
                    canonical += " (Maglia)"
                elif art_type == "racket" and not any(w in canonical.lower() for w in ("racchetta", "pala", "racket")):
                    canonical += " (Racchetta Padel)"
                elif art_type == "trainer" and not any(w in canonical.lower() for w in ("rullo", "trainer")):
                    canonical += " (Rullo Smart)"

                if gender in ("Donna", "Junior") and gender.lower() not in canonical.lower():
                    canonical += f" ({gender})"

                sorted_offers = sorted(cluster_offers, key=lambda o: o.price)
                image = next((o.image_url for o in cluster_offers if o.image_url), None)

                # Collect and deduplicate all distinct images across matching offers
                gallery = []
                if image:
                    gallery.append(image)
                for o in sorted_offers:
                    if o.image_url and o.image_url not in gallery:
                        gallery.append(o.image_url)
                    for g_img in o.gallery_images:
                        if g_img and g_img not in gallery:
                            gallery.append(g_img)

                groups.append(
                    MatchedProductGroup(
                        canonical_name=canonical,
                        brand=brand,
                        image_url=image,
                        gallery_images=gallery,
                        offers=sorted_offers
                    )
                )

        # Prioritize true multi-store matches, then top savings
        groups.sort(
            key=lambda g: (
                len({o.store_id for o in g.offers}) > 1,
                g.cross_store_savings or 0,
                len(g.offers)
            ),
            reverse=True
        )
        return groups
