import re
import json
from pydantic import BaseModel, Field, computed_field, field_validator
from typing import Optional, List, Any
from datetime import datetime


def clean_image_url(url: Optional[str]) -> Optional[str]:
    """Validate and sanitize product/offer image URLs, eliminating placeholders and invalid paths."""
    if not url or not isinstance(url, str):
        return None
    cleaned = url.strip()
    if not (cleaned.startswith("http://") or cleaned.startswith("https://")):
        return None
    lower = cleaned.lower()
    if any(p in lower for p in ("blank.gif", "pixel.gif", "spacer.gif", "placeholder")):
        return None
    return cleaned


EU_TO_US_MEN = {
    "36": "4.5", "36.5": "5", "37": "5", "37.5": "5.5", "38": "6", "38.5": "6",
    "39": "6.5", "39.5": "7", "40": "7", "40.5": "7.5", "41": "8", "41.5": "8.5", "42": "8.5",
    "42.5": "9", "43": "9.5", "43.5": "10", "44": "10", "44.5": "10.5", "45": "11",
    "45.5": "11.5", "46": "12", "46.5": "12", "47": "12.5", "47.5": "13", "48": "13.5",
    "48.5": "14", "49": "14.5"
}

US_TO_EU_MEN = {
    "4": "36", "4.0": "36", "4.5": "36.5",
    "5": "37.5", "5.0": "37.5", "5.5": "38",
    "6": "38.5", "6.0": "38.5", "6.5": "39",
    "7": "40", "7.0": "40", "7.5": "40.5",
    "8": "41", "8.0": "41", "8.5": "42",
    "9": "42.5", "9.0": "42.5", "9.5": "43",
    "10": "44", "10.0": "44", "10.5": "44.5",
    "11": "45", "11.0": "45", "11.5": "45.5",
    "12": "46", "12.0": "46", "12.5": "46.5",
    "13": "47.5", "13.0": "47.5", "13.5": "48",
    "14": "48.5", "14.0": "48.5", "14.5": "49",
    "15": "49.5", "15.0": "49.5", "16": "50.5", "16.0": "50.5"
}

US_TO_EU_WOMEN = {
    "5": "35.5", "5.0": "35.5", "5.5": "36",
    "6": "36.5", "6.0": "36.5", "6.5": "37.5",
    "7": "38", "7.0": "38", "7.5": "38.5",
    "8": "39", "8.0": "39", "8.5": "40",
    "9": "40.5", "9.0": "40.5", "9.5": "41",
    "10": "42", "10.0": "42", "10.5": "42.5",
    "11": "43", "11.0": "43", "11.5": "44",
    "12": "44.5", "12.0": "44.5", "12.5": "45",
    "13": "45.5", "13.0": "45.5"
}

EU_TO_US_WOMEN = {
    "35.5": "5", "36": "5.5", "36.5": "6", "37": "6", "37.5": "6.5",
    "38": "7", "38.5": "7.5", "39": "8", "39.5": "8", "40": "8.5",
    "40.5": "9", "41": "9.5", "41.5": "9.5", "42": "10", "42.5": "10.5",
    "43": "11", "43.5": "11", "44": "11.5", "44.5": "12", "45": "12.5",
    "45.5": "13"
}

UK_TO_EU = {
    "3.5": "36", "4": "36.5", "4.0": "36.5", "4.5": "37.5",
    "5": "38", "5.0": "38", "5.5": "38.5",
    "6": "39.5", "6.0": "39.5", "6.5": "40",
    "7": "40.5", "7.0": "40.5", "7.5": "41.5",
    "8": "42", "8.0": "42", "8.5": "42.5",
    "9": "43", "9.0": "43", "9.5": "44",
    "10": "44.5", "10.0": "44.5", "10.5": "45",
    "11": "45.5", "11.0": "45.5", "11.5": "46",
    "12": "47", "12.0": "47", "12.5": "47.5",
    "13": "48.5", "13.0": "48.5", "13.5": "49",
    "14": "49.5", "14.0": "49.5"
}

CLOTHING_ORDER = {
    "4XS": 1, "3XS": 2, "2XS": 3, "XXS": 4, "XS": 5,
    "S": 6, "M": 7, "L": 8, "XL": 9, "XXL": 10, "2XL": 10,
    "3XL": 11, "4XL": 12, "5XL": 13,
    "L0": 40, "L1": 41, "L2": 42, "L3": 43, "L4": 44, "L5": 45,
    "UNICA": 90, "ONE SIZE": 90, "TU": 90
}

NON_FOOTWEAR_CATEGORIES = {
    "top", "jacket", "pants", "apparel", "swim", "cycling",
    "gps_watch", "eyewear", "racket", "nutrition", "hydration",
    "case", "mount", "sensor", "pack", "trainer", "winter_sports", "sci"
}

RE_INVALID_SIZE = re.compile(
    r"(?i)(?:"
    r"\b(?:"
    r"selezion|scegli|tagli[ae]|misur[ae]|guida|vedere|esaurit[oa]|"
    r"out of stock|non disponibil[ei]|terminat[oa]|disponibil[ei]|"
    r"roulement|pi[eè]ces|options?|cat[1-4]|prizm|lens|trous|"
    r"teeth|denti|pollici|inch|ann[io]|years?|mois|mesi|default|nd_"
    r")\b"
    r"|(?:\b|\d)(?:mm|cm)\b"
    r")"
)


def is_female_context(gender: Optional[str] = None, title: Optional[str] = None) -> bool:
    """Return True when gender or title indicates women's sizing."""
    g = (gender or "").strip().lower()
    if g in {"women", "woman", "donna", "female", "femme", "wmns", "w", "f", "lady", "ladies"}:
        return True
    if title:
        if re.search(r"(?i)\b(?:donna|woman|women|wmns|femme|lady|ladies|w's)\b", title):
            return True
    return False


def _snap_eu_shoe_value(val: float) -> float:
    """Snap third-fraction shoe decimals (.3, .33, .67, .7) to .5 for EU consistency."""
    frac = round(val - int(val), 2)
    if frac in (0.3, 0.33, 0.34, 0.66, 0.67, 0.7):
        return int(val) + 0.5
    return val


def normalize_sizes(
    raw_sizes: Any,
    gender: Optional[str] = None,
    category: Optional[str] = None,
) -> List[str]:
    """Standardize shoe and apparel sizes, using gender/category context to avoid unit misconversion."""
    if not raw_sizes:
        return []
    if isinstance(raw_sizes, str):
        try:
            raw_sizes = json.loads(raw_sizes)
        except Exception:
            raw_sizes = [s.strip() for s in raw_sizes.split(",") if s.strip()]

    if not isinstance(raw_sizes, (list, set, tuple)):
        return []

    is_female = is_female_context(gender)
    us_map = US_TO_EU_WOMEN if is_female else US_TO_EU_MEN
    cat_norm = (category or "").strip().lower()
    is_non_footwear = cat_norm in NON_FOOTWEAR_CATEGORIES
    is_racket_cat = cat_norm in {"racket", "tennis", "padel"}
    is_winter_cat = cat_norm in {"winter_sports", "sci"}

    # Detect pure grip-size lists (e.g. ["0", "1", "2", "3"] on tennis/padel rackets, or ["L1", "2", "L3"])
    has_shoe_like_numbers = any(
        re.search(r"\b(?:3[2-9]|4\d|5[0-2])\b", str(it))
        for it in raw_sizes
        if it is not None
    )
    has_explicit_grip_tokens = any(
        re.match(r"(?i)^(?:grip\s*)?L[0-5]$", str(it).strip())
        for it in raw_sizes
        if it is not None
    )

    eu_sizes = set()
    clothing_sizes = []

    for item in raw_sizes:
        if not item:
            continue
        s_str = str(item).strip()
        if not s_str or len(s_str) > 40:
            continue

        # Check One Size
        if re.match(r"(?i)^(?:taglia\s+unica|one\s+size|unica|uni|tu|t\.u)$", s_str):
            clothing_sizes.append("Unica")
            continue

        # Racket grip sizes (e.g. L1..L5, Grip 2, or 0..5 when not mixed with EU shoe numbers)
        grip_m = re.match(r"(?i)^(?:grip\s*)?L?([0-5])$", s_str)
        if grip_m and (
            is_racket_cat
            or has_explicit_grip_tokens
        ) and (s_str.upper().startswith(("L", "GRIP")) or not has_shoe_like_numbers):
            clothing_sizes.append(f"L{grip_m.group(1)}")
            continue

        # Ski boot Mondopoint sizes (e.g. 'CM 26,5', '27.5') when in winter_sports or prefixed with CM <40
        mondo_m = re.match(r"(?i)^(?:CM|MP)\s*(\d{2}(?:[.,]\d+)?)$", s_str)
        if mondo_m:
            mval = float(mondo_m.group(1).replace(",", "."))
            if 18.0 <= mval <= 34.5:
                eu_sizes.add(f"{mval:.1f}" if mval % 1 != 0 else f"{int(mval)}")
            continue
        if is_winter_cat and re.match(r"^\d{2}(?:[.,]\d+)?$", s_str):
            mval = float(s_str.replace(",", "."))
            if 22.0 <= mval <= 33.5:
                eu_sizes.add(f"{mval:.1f}" if mval % 1 != 0 else f"{int(mval)}")
                continue

        # Check invalid keywords / placeholders / dimension parts
        if RE_INVALID_SIZE.search(s_str):
            continue

        # Check dual UK/US/CM-EU format like '10 UK - 44.5' or '7.5 UK - 41.5' (avoid matching EU ranges like '47-50')
        if re.search(r"(?i)\b(?:UK|US|CM|JP)\b", s_str):
            uk_eu_m = re.search(r"-\s*(\d+(?:[.,]\d+)?)\s*(?:EU)?$", s_str, re.IGNORECASE)
            if uk_eu_m:
                s_str = uk_eu_m.group(1)

        # Preserve explicit EU ranges like '39-42' or '47-50' without corrupting them to a single endpoint
        range_m = re.match(r"^(?:EU\s*)?(\d{2})\s*[-/]\s*(\d{2})$", s_str, re.IGNORECASE)
        if range_m:
            clothing_sizes.append(f"{range_m.group(1)}-{range_m.group(2)}")
            continue

        # Decathlon format '46 (UK 11)' or '40.5 (UK 7)'
        uk_m = re.search(r"^(\d+(?:[.,]\d+)?)\s*\([^\)]*\)", s_str)
        if uk_m:
            s_str = uk_m.group(1)

        # Apparel with size label e.g. 'M (IT 44-46)', 'L (56-62 cm)'
        cloth_m = re.match(r"^([XSLM]+|[234]XL)\b", s_str, re.IGNORECASE)
        if cloth_m and cloth_m.group(1).upper() in CLOTHING_ORDER:
            clothing_sizes.append(cloth_m.group(1).upper())
            continue

        # Standalone clothing
        if s_str.upper() in CLOTHING_ORDER:
            clothing_sizes.append(s_str.upper())
            continue

        # Normalize Unicode fractions (Top4Running/EU stores use ½, ⅓, ⅔) and ASCII fractions (42 2/3, 41 1/3, 42.1/2)
        s_str = s_str.replace("½", ".5").replace("⅓", ".5").replace("⅔", ".5")
        s_str = re.sub(r"\s+\.5\b", ".5", s_str)
        s_str = re.sub(r"\bEU\b", "", s_str, flags=re.IGNORECASE).strip()
        s_str = re.sub(r"(\d+)[.\s]+(?:1/2|1/3|2/3)", r"\1.5", s_str)

        # Explicit UK prefix/suffix e.g. 'UK 9.5', '9.5 UK'
        uk_explicit_m = re.search(r"(?:\bUK\s*(\d+(?:[.,]\d+)?)\b)|(?:(\d+(?:[.,]\d+)?)\s*UK\b)", s_str, re.IGNORECASE)
        if uk_explicit_m:
            if is_non_footwear:
                continue
            val_str = (uk_explicit_m.group(1) or uk_explicit_m.group(2)).replace(",", ".")
            if val_str in UK_TO_EU:
                eu_sizes.add(UK_TO_EU[val_str])
            continue

        # Explicit US prefix/suffix e.g. 'US 9.5', '9.5 US'
        us_m = re.search(r"(?:\bUS\s*(\d+(?:[.,]\d+)?)\b)|(?:(\d+(?:[.,]\d+)?)\s*US\b)", s_str, re.IGNORECASE)
        if us_m:
            if is_non_footwear:
                continue
            val_str = (us_m.group(1) or us_m.group(2)).replace(",", ".")
            if val_str in us_map:
                eu_sizes.add(us_map[val_str])
            continue

        if is_non_footwear:
            continue

        s_clean = s_str.replace(",", ".").rstrip(".").strip()
        try:
            val = float(s_clean)
            if 32.0 <= val <= 52.0:
                val = _snap_eu_shoe_value(val)
                fmt = f"{val:.1f}" if val % 1 != 0 else f"{int(val)}"
                eu_sizes.add(fmt)
            elif 4.0 <= val <= 16.0:
                s_key = f"{val:.1f}" if val % 1 != 0 else f"{int(val)}"
                if s_key in us_map:
                    eu_sizes.add(us_map[s_key])
                elif s_clean in us_map:
                    eu_sizes.add(us_map[s_clean])
        except ValueError:
            pass

    if eu_sizes:
        return sorted(list(eu_sizes), key=lambda s: (0, float(s)))

    if clothing_sizes:
        return sorted(list(set(clothing_sizes)), key=lambda x: (CLOTHING_ORDER.get(x, 99), x))

    return []


def extract_variant_title(raw_title: str) -> Optional[str]:
    """Extract clean colorway or variant description from retailer offer title."""
    if not raw_title:
        return None
    parts = re.split(r"\s+[-–—|]\s+", raw_title, maxsplit=1)
    if len(parts) > 1:
        v = re.sub(r"\(.*?\)", "", parts[1]).strip()
        if len(v) >= 3:
            return v.title()

    m = re.search(r"\((.*?)\)", raw_title)
    if m:
        inside = m.group(1).strip()
        if inside and len(inside) <= 35:
            return inside.capitalize()

    # Look for color keywords at end of title (e.g. "Glam Blu/Verde Uomo")
    color_m = re.search(r"\b(Nero|Bianco|Blu|Rosso|Verde|Giallo|Rosa|Grigio|Viola|Arancione|Glam)[^,;]*", raw_title, re.IGNORECASE)
    if color_m:
        clean_color = re.sub(r"\b(Uomo|Donna|Unisex|Scarpe|Running)\b", "", color_m.group(0), flags=re.IGNORECASE).strip()
        if len(clean_color) >= 3:
            return clean_color.title()

    return None

# Verified real shipping policies for partner stores in Italy
STORE_SHIPPING_RULES = {
    "cisalfa": {"standard": 9.90, "free_threshold": 99.0, "courier": "BRT / GLS"},
    "maxisport": {"standard": 7.90, "free_threshold": 99.0, "courier": "GLS / DHL"},
    "misterrunning": {"standard": 4.90, "free_threshold": 49.0, "courier": "DHL / UPS"},
    "nencini": {"standard": 5.90, "free_threshold": 100.0, "courier": "BRT / UPS / DHL"},
    "top4running": {"standard": 4.90, "free_threshold": 75.0, "courier": "DPD / BRT"},
    "runningwarehouse": {"standard": 10.00, "free_threshold": 59.0, "courier": "UPS / FedEx / DHL"},
    "deporvillage": {"standard": 4.99, "free_threshold": 80.0, "courier": "GLS / DPD"},
    "alltricks": {"standard": 4.99, "free_threshold": 69.0, "courier": "Bartolini (BRT)"},
    "decathlon": {"standard": 4.99, "free_threshold": 60.0, "courier": "Corriere Espresso"},
    "sportler": {"standard": 4.95, "free_threshold": 100.0, "courier": "SDA / Corriere Espresso"},
    "nike": {"standard": 5.00, "free_threshold": 99.0, "courier": "UPS / DPD"},
    "adidas": {"standard": 4.99, "free_threshold": 50.0, "courier": "Poste / BRT"},
    "tradeinn": {"standard": 4.99, "free_threshold": None, "courier": "DHL / UPS / GLS / Poste"},
    "df_sportspecialist": {"standard": 8.00, "free_threshold": 100.0, "courier": "Corriere Espresso"},
    "df_sport": {"standard": 8.00, "free_threshold": 100.0, "courier": "Corriere Espresso"},
    "sportit": {"standard": 5.99, "free_threshold": 59.90, "courier": "GLS / DHL / InPost"},
    "tennis_point": {"standard": 5.99, "free_threshold": 59.0, "courier": "DHL / UPS"},
    "basketballstore": {"standard": 6.90, "free_threshold": 50.0, "courier": "BRT / UPS / Poste"},
    "nonsolosport": {"standard": 5.00, "free_threshold": 89.99, "courier": "BRT"},
    "intersport": {"standard": 5.90, "free_threshold": 59.0, "courier": "GLS / BRT"},
    "bshopzone": {"standard": 10.00, "free_threshold": 100.0, "courier": "BRT / SDA / GLS"},
}


def calculate_shipping_cost(price: float, rule: Optional[dict]) -> float:
    """Compute shipping cost from offer price and store shipping rule, handling None thresholds."""
    if not rule:
        rule = {"standard": 4.90, "free_threshold": 50.0}
    threshold = rule.get("free_threshold")
    if threshold is not None and price >= threshold:
        return 0.0
    standard = rule.get("standard")
    return float(standard) if standard is not None else 4.90


class Offer(BaseModel):
    """Represents a specific product offer found on a retailer store."""
    store_id: str
    store_name: str
    product_id: Optional[str] = None
    barcode: Optional[str] = None
    title: str
    brand: Optional[str] = None
    price: float
    original_price: Optional[float] = None
    currency: str = "EUR"
    url: str
    image_url: Optional[str] = None
    gallery_images: List[str] = Field(default_factory=list)
    available_sizes: List[str] = Field(default_factory=list)
    in_stock: bool = True
    scraped_at: datetime = Field(default_factory=datetime.now)

    @field_validator("image_url", mode="before")
    @classmethod
    def validate_image_url(cls, v: Any) -> Optional[str]:
        return clean_image_url(v)

    @field_validator("gallery_images", mode="before")
    @classmethod
    def validate_gallery_images(cls, v: Any) -> List[str]:
        if not v:
            return []
        if isinstance(v, str):
            v = [v]
        cleaned = []
        for img in v:
            c = clean_image_url(img)
            if c and c not in cleaned:
                cleaned.append(c)
        return cleaned

    def matches_size(self, target_size: Optional[str], allow_unverified: bool = False) -> bool:
        """Check if requested size is available, handling EU <-> US conversions."""
        if not target_size:
            return True
        if not self.available_sizes:
            return bool(allow_unverified)
        req = target_size.strip().replace(",", ".").upper()
        candidates = {req}
        is_female = is_female_context(title=self.title) or is_female_context(title=self.url)
        eu_to_us = EU_TO_US_WOMEN if is_female else EU_TO_US_MEN
        us_to_eu = US_TO_EU_WOMEN if is_female else US_TO_EU_MEN
        if req in eu_to_us:
            candidates.add(eu_to_us[req])
        if req in us_to_eu:
            candidates.add(us_to_eu[req])

        norm_avail = {s.strip().replace(",", ".").upper() for s in self.available_sizes}
        return bool(candidates.intersection(norm_avail))

    @computed_field
    @property
    def discount_pct(self) -> Optional[float]:
        if self.original_price and self.original_price > self.price:
            pct = ((self.original_price - self.price) / self.original_price) * 100
            return round(pct, 1)
        return None

    @computed_field
    @property
    def savings(self) -> Optional[float]:
        if self.original_price and self.original_price > self.price:
            return round(self.original_price - self.price, 2)
        return None

    @computed_field
    @property
    def shipping_cost(self) -> float:
        rule = STORE_SHIPPING_RULES.get(self.store_id.lower().strip(), {"standard": 4.90, "free_threshold": 50.0})
        return calculate_shipping_cost(self.price, rule)

    @computed_field
    @property
    def is_free_shipping(self) -> bool:
        return self.shipping_cost == 0.0

    @computed_field
    @property
    def total_price(self) -> float:
        return round(self.price + self.shipping_cost, 2)

    @computed_field
    @property
    def shipping_label(self) -> str:
        if self.is_free_shipping:
            return "Spedizione Gratuita"
        return f"+{self.shipping_cost:.2f} € sped."

    @computed_field
    @property
    def free_shipping_threshold(self) -> Optional[float]:
        rule = STORE_SHIPPING_RULES.get(self.store_id.lower().strip(), {"free_threshold": 50.0})
        return rule.get("free_threshold")

    @computed_field
    @property
    def courier(self) -> str:
        rule = STORE_SHIPPING_RULES.get(self.store_id.lower().strip(), {"courier": "Corriere Espresso"})
        return rule.get("courier", "Corriere Espresso")


class MatchedProductGroup(BaseModel):
    """Groups matching offers of the same or very similar product across different stores."""
    canonical_name: str
    brand: Optional[str] = None
    image_url: Optional[str] = None
    gallery_images: List[str] = Field(default_factory=list)
    offers: List[Offer] = Field(default_factory=list)

    @field_validator("image_url", mode="before")
    @classmethod
    def validate_image_url(cls, v: Any) -> Optional[str]:
        return clean_image_url(v)

    @field_validator("gallery_images", mode="before")
    @classmethod
    def validate_gallery_images(cls, v: Any) -> List[str]:
        if not v:
            return []
        if isinstance(v, str):
            v = [v]
        cleaned = []
        for img in v:
            c = clean_image_url(img)
            if c and c not in cleaned:
                cleaned.append(c)
        return cleaned

    @computed_field
    @property
    def best_offer(self) -> Optional[Offer]:
        if not self.offers:
            return None
        return min(self.offers, key=lambda o: o.price)

    @computed_field
    @property
    def highest_price(self) -> Optional[float]:
        if not self.offers:
            return None
        return max(o.price for o in self.offers)

    @computed_field
    @property
    def best_price(self) -> Optional[float]:
        best = self.best_offer
        return best.price if best else None

    @computed_field
    @property
    def cross_store_savings(self) -> Optional[float]:
        """Difference between highest and lowest store price for this product."""
        if len(self.offers) > 1 and self.best_price and self.highest_price:
            return round(self.highest_price - self.best_price, 2)
        return None


class SearchResult(BaseModel):
    """Consolidated result returned by the comparison engine."""
    query: str
    execution_time_seconds: float
    stores_queried: List[str]
    total_offers_found: int
    matched_products: List[MatchedProductGroup]
    raw_offers: List[Offer]
