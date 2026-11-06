import re
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
from fitmatch.models import Offer, MatchedProductGroup

KNOWN_BRANDS = [
    # Top Running & Athletic Brands
    "nike", "adidas", "asics", "brooks", "hoka", "on running", "on", "saucony",
    "puma", "new balance", "mizuno", "under armour", "salomon", "altra", "la sportiva",
    "scarpa", "dynafit", "inov-8", "topo athletic", "joma", "newton", "craft", "diadora",

    # Electronics & Optics
    "garmin", "polar", "suunto", "coros", "wahoo", "bryton", "oakley", "bliz",
    "rudy project", "100%", "shokz", "aftershokz",

    # Cycling & Helmets
    "shimano", "poc", "kask", "abus", "castelli", "sportful", "santini", "giro",
    "sidi", "sram", "campagnolo", "met", "tacx", "favero", "assioma", "elite",

    # Padel & Tennis
    "bullpadel", "babolat", "head", "wilson", "nox", "starvie", "siux", "dunlop", "kuikma",

    # Outdoor, Packs & Hydration
    "the north face", "north face", "patagonia", "columbia", "arc'teryx", "arcteryx",
    "mammut", "millet", "salewa", "black diamond", "petzl", "leki", "camelbak",
    "osprey", "deuter", "buff", "compressport",

    # Recovery, Fitness & Nutrition
    "therabody", "theragun", "hyperice", "compex", "enervit", "sis", "maurten",
    "named sport", "powerbar", "ethic sport",

    # Decathlon Brands
    "decathlon", "kiprun", "evadict", "kalenji", "quechua", "forclaz", "btwin",
    "van rysel", "rockrider", "triban", "domyos", "kuikma", "artengo"
]

BRAND_ALIASES = {
    "on running": "On",
    "theragun": "Therabody",
    "north face": "The North Face",
    "arcteryx": "Arc'teryx",
    "kiprun": "Kiprun",
    "kalenji": "Kalenji"
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
    # Asics
    "nimbus": "Asics", "cumulus": "Asics", "kayano": "Asics", "novablast": "Asics",
    "superblast": "Asics", "metaspeed": "Asics", "magic speed": "Asics", "trabuco": "Asics",
    "gt-2000": "Asics", "gt-1000": "Asics",
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
    "cloudboom": "On", "cloudstratus": "On",
    # New Balance
    "fuelcell": "New Balance", "fresh foam": "New Balance", "hierro": "New Balance",
    "sc elite": "New Balance", "supercomp": "New Balance",
    # Garmin
    "forerunner": "Garmin", "fenix": "Garmin", "epix": "Garmin", "instinct": "Garmin",
    "venu": "Garmin", "vivoactive": "Garmin", "edge": "Garmin",
    # Polar
    "vantage": "Polar", "grit x": "Polar", "pacer": "Polar", "ignite": "Polar",
    # Salomon
    "speedcross": "Salomon", "sense ride": "Salomon", "pulsar": "Salomon", "xa pro": "Salomon",
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
        r"\bpellicol[ae]\b", r"\bvetro temprato\b", r"\bsleeve\b", r"\bsalvaschermo\b"
    ]),
    ("strap", [
        r"\bcinturin[oi]\b", r"\bstraps?\b", r"\bwristband\b", r"\bbraccialetto\b"
    ]),
    ("sensor", [
        r"\bfascia cardio\b", r"\bhrm\b", r"\bsensore\b", r"\bspeed sensor\b", r"\bcadence\b"
    ]),
    ("mount", [
        r"\bsupport[oi]\b", r"\bstaff[ae]\b", r"\bmounts?\b", r"\bstaffetta\b"
    ]),
    ("pack", [
        r"\bpacks?\b", r"\bbundles?\b", r"\bset\b", r"\bkit\b", r"\bcoppia\b", r"\bduo\b"
    ]),
    ("jacket", [
        r"\bgiacc[ae]\b", r"\bjackets?\b", r"\bantivento\b", r"\bwindbreaker\b",
        r"\bgilet\b", r"\bvest\b", r"\banorak\b", r"\bshell\b"
    ]),
    ("pants", [
        r"\bpantalon[ii]\b", r"\bpantaloncin[ii]\b", r"\bshorts?\b", r"\btights?\b",
        r"\bleggings?\b", r"\bcapri\b", r"\bcalzamagli[ae]\b"
    ]),
    ("top", [
        r"\bmagli[ae]\b", r"\bmagliett[ae]\b", r"\bt-?shirts?\b", r"\bcanott[ae]\b",
        r"\bsinglets?\b", r"\btops?\b", r"\bfelp[ae]\b", r"\bhoodie\b"
    ]),
    ("socks", [
        r"\bcalz[ae]\b", r"\bcalzin[ii]\b", r"\bsocks?\b"
    ]),
    ("eyewear", [
        r"\bocchial[ii]\b", r"\bsunglasses\b", r"\blent[ie]\b", r"\bmascher[ae]\b"
    ]),
    ("racket", [
        r"\bracchett[ae]\b", r"\bpala\b", r"\bpalas\b", r"\bracks?\b", r"\bpadel\b"
    ]),
    ("trainer", [
        r"\brull[oi]\b", r"\bsmart trainer\b", r"\btrainer\b", r"\bkickr\b", r"\bflux\b", r"\bneo\b", r"\bsuito\b"
    ]),
    ("gear", [
        r"\bsmartwatch\b", r"\borolog[io]\b", r"\bgps\b", r"\bciclocomputer\b",
        r"\bcardiofrequenzimetr[oi]\b", r"\btheragun\b", r"\bpistola per massaggi\b",
        r"\bpistola massaggi\b", r"\bstimolatore muscolare\b", r"\bracchett[ae]\b",
        r"\bcasc[oi]\b", r"\bcomputer\b", r"\bedge\b"
    ]),
    ("shoes", [
        r"\bscarp[ae]\b", r"\bshoes?\b", r"\bsneakers?\b", r"\bcalzatur[ae]\b",
        r"\bstival[ii]\b", r"\bciabatt[ae]\b", r"\bchiodat[ae]\b"
    ])
]

TECH_FABRICS = [
    "dri-fit adv", "dri-fit", "dri fit", "drifit", "aeroready", "heatgear", "coldgear",
    "iso-chill", "climalite", "therma-fit", "tech fleece", "climacool", "air zoom",
    "air", "gel", "fuelcell", "fresh foam x", "fresh foam", "super comp", "supercomp"
]

STOPWORDS = {
    "scarpe", "scarpa", "shoes", "shoe", "sneakers", "calzature", "running", "corsa", "trail", "asfalto",
    "uomo", "donna", "unisex", "bambino", "bambina", "junior", "ragazzo", "ragazza",
    "m", "w", "men", "women", "mens", "womens", "wmns",
    "smartwatch", "orologio", "gps", "multisport", "cardiofrequenzimetro", "ciclocomputer",
    "pistola", "massaggi", "stimolatore", "muscolare",
    "maglietta", "maglia", "pantaloni", "pantaloncini", "shorts", "tights", "giacca", "canotta",
    "custodia", "silicone", "housse", "cover", "pack", "bundle", "kit", "cinturino", "strap",
    "allenamento", "palestra", "training", "workout", "fitness",
    "performance", "sportswear", "originals", "athletics", "athletic", "road",
    "per", "di", "con", "e", "the", "in", "de", "ed", "da", "a", "la", "il", "le", "un", "una",
    "senza", "maniche", "nero", "grigio", "bianco", "rosso", "blu", "giallo", "fluor", "verde",
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
        """Detect standard canonical brand name from title or existing hint."""
        if existing_brand:
            eb_lower = existing_brand.strip().lower()
            if eb_lower in BRAND_ALIASES:
                return BRAND_ALIASES[eb_lower]
            for b in KNOWN_BRANDS:
                if b == eb_lower:
                    return b.title()

        lower_title = title.lower()
        for b in sorted(KNOWN_BRANDS, key=len, reverse=True):
            if re.search(rf"\b{re.escape(b)}\b", lower_title):
                if b == "scarpa":
                    # Disambiguate Italian noun 'scarpa' (shoe) from Italian mountaineering brand SCARPA S.p.A.
                    scarpa_models = {
                        "ribelle", "mojito", "spin", "golden gate", "mescalito", "atom", "chimera",
                        "drago", "phantom", "zen", "boostic", "instinct", "marmolada", "rapid", "rush",
                        "kinesis", "maestrale", "alien"
                    }
                    is_real_scarpa = any(m in lower_title for m in scarpa_models) or any(
                        w in lower_title for w in ("arrampicata", "alpinismo", "climbing", "scarpette", "scarponi")
                    )
                    if not is_real_scarpa:
                        continue
                return BRAND_ALIASES.get(b, b.title())

        # Fallback to iconic model mapping if brand was omitted from title
        for model_sub, brand_name in ICONIC_MODEL_BRANDS.items():
            if re.search(rf"\b{re.escape(model_sub)}\b", lower_title):
                return brand_name

        return existing_brand.capitalize() if existing_brand else None

    @classmethod
    def detect_article_type(cls, title: str) -> str:
        """Categorize item into article type (e.g. case, strap, pack, jacket, pants, shoes, gear)."""
        tl = title.lower()
        for atype, patterns in ARTICLE_PATTERNS:
            for pattern in patterns:
                if re.search(pattern, tl):
                    return atype
        return "shoes"

    @classmethod
    def clean_title(cls, title: str, brand: Optional[str] = None) -> Tuple[str, Optional[str]]:
        """Splits off colorway/descriptions and strips noise words while preserving model version."""
        # Split on dash, pipe or slash that separates model from color description or category breadcrumb
        parts = re.split(r"\s+[-–—|]\s+", title)
        base = parts[0]
        colorway = parts[-1].strip() if len(parts) > 1 else None

        # Check if parts[0] is just a generic category breadcrumb (e.g. Decathlon: "ASICS Scarpe da Running – Novablast 5")
        if len(parts) > 1:
            generic_words = STOPWORDS.union({"running", "corsa", "trail", "asics", "nike", "adidas", "mizuno", "brooks", "hoka", "altra", "new", "balance", "saucony", "on"})
            tokens_0 = set(re.findall(r"\b[a-zA-Z0-9]+\b", parts[0].lower()))
            if tokens_0.issubset(generic_words):
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
        text = re.sub(r"[^\w\s]", " ", text)

        # Remove all occurrences of the brand
        if brand:
            text = re.sub(rf"\b{re.escape(brand.lower())}\b", " ", text)
            for p in brand.lower().split():
                if len(p) > 2:
                    text = re.sub(rf"\b{re.escape(p)}\b", " ", text)

        # Standardize known compounds
        text = re.sub(r"\bsuper\s+comp\b", "supercomp", text)
        for tf in sorted(TECH_FABRICS, key=len, reverse=True):
            if tf not in ("super comp", "supercomp"):
                text = re.sub(rf"\b{re.escape(tf)}\b", " ", text)

        tokens = text.split()
        cleaned_tokens = [
            t for t in tokens
            if t not in STOPWORDS and not re.match(r"^\d{6,}$", t) and t != "s"
        ]
        return " ".join(cleaned_tokens).strip(), colorway

    @classmethod
    def extract_cluster_key(cls, offer: Offer) -> str:
        """
        Generates a strictly partitioned cluster key:
        Prevents cases/straps/packs from sharing keys with core devices or shoes,
        and retains exact model generation numbers (e.g. 965, 55, 41, Pro 5, v14).
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

        while i < len(tokens):
            t = tokens[i]
            model_parts.append(t)
            is_num = bool(re.search(r"\d", t) or re.match(r"^(v\d+|[ivx]+)$", t))
            if is_num:
                # Retain model qualifiers immediately following a number (e.g. '1080 v15', 'adios pro 5')
                if i + 1 < len(tokens) and tokens[i + 1] in (
                    "pro", "music", "elite", "plus", "s", "x", "max", "tr", "gtx", "trail"
                ):
                    model_parts.append(tokens[i + 1])
                    i += 1
                break
            elif t in ("pro", "elite", "prime", "relief") and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if re.search(r"\d", nxt) or nxt in ("plus", "max", "ultra", "v6", "v5", "v4", "trail"):
                    model_parts.append(nxt)
                    i += 1
                    break
            elif len(model_parts) >= 4:
                break
            i += 1

        model_key = " ".join(model_parts).strip() if model_parts else "general"

        # Devices, electronics, eyewear, cycling trainers, rackets & gear are genderless
        if art_type in ("gear", "eyewear", "racket", "trainer", "sensor", "mount", "case", "strap", "pack"):
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
