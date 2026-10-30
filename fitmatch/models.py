from pydantic import BaseModel, Field, computed_field
from typing import Optional, List
from datetime import datetime


EU_TO_US_MEN = {
    "39": "6.5", "40": "7", "40.5": "7.5", "41": "8", "42": "8.5",
    "42.5": "9", "43": "9.5", "44": "10", "44.5": "10.5", "45": "11",
    "45.5": "11.5", "46": "12", "47": "12.5", "47.5": "13", "48": "13.5"
}
US_TO_EU_MEN = {v: k for k, v in EU_TO_US_MEN.items()}


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


class MatchedProductGroup(BaseModel):
    """Groups matching offers of the same or very similar product across different stores."""
    canonical_name: str
    brand: Optional[str] = None
    image_url: Optional[str] = None
    offers: List[Offer] = Field(default_factory=list)

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
