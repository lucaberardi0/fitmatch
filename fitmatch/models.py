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

CLOTHING_ORDER = {
    "4XS": 1, "3XS": 2, "2XS": 3, "XXS": 4, "XS": 5,
    "S": 6, "M": 7, "L": 8, "XL": 9, "XXL": 10, "2XL": 10,
    "3XL": 11, "4XL": 12, "5XL": 13,
    "UNICA": 90, "ONE SIZE": 90, "TU": 90
}

RE_INVALID_SIZE = re.compile(
    r"(?i)\b("
    r"selezion|scegli|tagli[ae]|misur[ae]|guida|vedere|esaurit[oa]|"
    r"out of stock|non disponibil[ei]|terminat[oa]|disponibil[ei]|"
    r"roulement|pi[eè]ces|options?|cat[1-4]|prizm|lens|mm|cm|trous|"
    r"teeth|denti|pollici|inch|ann[io]|years?|mois|mesi|default|nd_"
    r")\b"
)


def normalize_sizes(raw_sizes: Any) -> List[str]:
    """Standardizes shoe and apparel sizes, strictly verifying validity, converting US to EU and sorting numerically."""
    if not raw_sizes:
        return []
    if isinstance(raw_sizes, str):
        try:
            raw_sizes = json.loads(raw_sizes)
        except Exception:
            raw_sizes = [s.strip() for s in raw_sizes.split(",") if s.strip()]

    if not isinstance(raw_sizes, (list, set, tuple)):
        return []

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

        # Check invalid keywords / placeholders / dimension parts
        if RE_INVALID_SIZE.search(s_str):
            continue

        # Check dual UK-EU format like '10 UK - 44.5' or '7.5 UK - 41.5'
        uk_eu_m = re.search(r"-\s*(\d+(?:[.,]\d+)?)\s*(?:EU)?$", s_str, re.IGNORECASE)
        if uk_eu_m:
            s_str = uk_eu_m.group(1)

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

        # Fractions e.g. 42 2/3, 41 1/3, 42.1/2, 42 1/2
        s_str = re.sub(r"\bEU\b", "", s_str, flags=re.IGNORECASE).strip()
        s_str = re.sub(r"(\d+)[.\s]+(?:1/2|1/3|2/3)", r"\1.5", s_str)

        # Explicit US prefix/suffix e.g. 'US 9.5', '9.5 US'
        us_m = re.search(r"(?:\bUS\s*(\d+(?:[.,]\d+)?)\b)|(?:(\d+(?:[.,]\d+)?)\s*US\b)", s_str, re.IGNORECASE)
        if us_m:
            val_str = (us_m.group(1) or us_m.group(2)).replace(",", ".")
            if val_str in US_TO_EU_MEN:
                eu_sizes.add(US_TO_EU_MEN[val_str])
                continue

        s_clean = s_str.replace(",", ".").rstrip(".").strip()
        try:
            val = float(s_clean)
            if 32.0 <= val <= 52.0:
                fmt = f"{val:.1f}" if val % 1 != 0 else f"{int(val)}"
                eu_sizes.add(fmt)
            elif 4.0 <= val <= 16.0:
                s_key = f"{val:.1f}" if val % 1 != 0 else f"{int(val)}"
                if s_key in US_TO_EU_MEN:
                    eu_sizes.add(US_TO_EU_MEN[s_key])
                elif s_clean in US_TO_EU_MEN:
                    eu_sizes.add(US_TO_EU_MEN[s_clean])
        except ValueError:
            pass

    if eu_sizes:
        return sorted(list(eu_sizes), key=lambda s: (0, float(s)))

    if clothing_sizes:
        return sorted(list(set(clothing_sizes)), key=lambda x: CLOTHING_ORDER.get(x, 99))

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
    "nencini": {"standard": 5.90, "free_threshold": 100.0, "courier": "BRT Espresso"},
    "top4running": {"standard": 4.90, "free_threshold": 75.0, "courier": "DPD / BRT"},
    "runningwarehouse": {"standard": 10.00, "free_threshold": 59.0, "courier": "UPS Standard"},
    "deporvillage": {"standard": 4.99, "free_threshold": 80.0, "courier": "GLS / DPD"},
    "alltricks": {"standard": 4.99, "free_threshold": 69.0, "courier": "Bartolini (BRT)"},
    "decathlon": {"standard": 3.99, "free_threshold": 50.0, "courier": "Corriere Espresso"},
    "sportler": {"standard": 5.00, "free_threshold": 50.0, "courier": "GLS / DPD"},
    "nike": {"standard": 5.00, "free_threshold": 99.0, "courier": "UPS / DPD"},
    "adidas": {"standard": 4.99, "free_threshold": 50.0, "courier": "DHL / GLS"},
    "tradeinn": {"standard": 4.99, "free_threshold": 150.0, "courier": "Poste / GLS / DPD"},
    "df_sportspecialist": {"standard": 5.90, "free_threshold": 60.0, "courier": "GLS / BRT"},
    "df_sport": {"standard": 5.90, "free_threshold": 60.0, "courier": "GLS / BRT"},
}


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

    def matches_size(self, target_size: Optional[str]) -> bool:
        """Check if requested size is available, handling EU <-> US conversions."""
        if not target_size or not self.available_sizes:
            return True  # If no size filter or sizes not fetched yet, keep
        req = target_size.strip().replace(",", ".").upper()
        candidates = {req}
        if req in EU_TO_US_MEN:
            candidates.add(EU_TO_US_MEN[req])
        if req in US_TO_EU_MEN:
            candidates.add(US_TO_EU_MEN[req])

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
        if self.price >= rule["free_threshold"]:
            return 0.0
        return rule["standard"]

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
    def free_shipping_threshold(self) -> float:
        rule = STORE_SHIPPING_RULES.get(self.store_id.lower().strip(), {"free_threshold": 50.0})
        return rule["free_threshold"]

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
