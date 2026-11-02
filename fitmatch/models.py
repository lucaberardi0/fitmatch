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
US_TO_EU_MEN = {v: k for k, v in EU_TO_US_MEN.items()}

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
}


class Offer(BaseModel):
    """Represents a specific product offer found on a retailer store."""
    store_id: str
    store_name: str
    product_id: Optional[str] = None
    title: str
    brand: Optional[str] = None
    price: float
    original_price: Optional[float] = None
    currency: str = "EUR"
    url: str
    image_url: Optional[str] = None
    available_sizes: List[str] = Field(default_factory=list)
    in_stock: bool = True
    scraped_at: datetime = Field(default_factory=datetime.now)

    @field_validator("image_url", mode="before")
    @classmethod
    def validate_image_url(cls, v: Any) -> Optional[str]:
        return clean_image_url(v)

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
    offers: List[Offer] = Field(default_factory=list)

    @field_validator("image_url", mode="before")
    @classmethod
    def validate_image_url(cls, v: Any) -> Optional[str]:
        return clean_image_url(v)

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
