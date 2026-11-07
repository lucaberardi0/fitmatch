import urllib.parse
from typing import List, Optional
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


class Top4RunningScraper(BaseScraper):
    """Scraper for Top4Running (top4running.it), top European running specialist retailer."""

    store_id = "top4running"
    store_name = "Top4Running"
    base_url = "https://top4running.it"
    rating = 4.8
    review_count = 950
    formatted_review_count = "950"
    card_theme = "grid"
    accent_color = "#00B9F1"
    free_shipping_threshold = 75.00
    standard_shipping_cost = 4.90
    courier = "DPD / BRT"
    tracker_id = "214346-281297"  # Luigi's Box Italian catalog tracker ID
    api_url = "https://live.luigisbox.com/search"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        params = {
            "tracker_id": self.tracker_id,
            "q": query,
            "size": min(max(limit * 3, 20), 50)
        }
        data = self._fetch_json(self.api_url, params=params)
        if not data or not isinstance(data, dict):
            return []

        hits = data.get("results", {}).get("hits", [])
        offers: List[Offer] = []

        for h in hits:
            # Skip query suggestions and facets
            if h.get("type") != "item":
                continue

            attrs = h.get("attributes", {})
            title = attrs.get("title")
            price = self.parse_price(attrs.get("price_amount"))
            raw_url = h.get("url")
            if not title or not price or not raw_url:
                continue

            brand_raw = attrs.get("brand")
            brand = (
                brand_raw[0]
                if isinstance(brand_raw, list) and brand_raw
                else (brand_raw if isinstance(brand_raw, str) else None)
            )

            # Ensure canonical brand is part of title if not already present
            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            orig_price = self.parse_price(attrs.get("price_old_amount"))
            img_url = attrs.get("image_link")
            product_url = urllib.parse.urljoin(self.base_url, raw_url)
            pid = str(attrs.get("id") or attrs.get("producer_id") or h.get("identity_hash") or "")

            raw_sizes = attrs.get("sizes_eu") or attrs.get("sizes_default") or attrs.get("Size") or []
            sizes = normalize_sizes(raw_sizes)

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=pid if pid else None,
                    title=full_title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=product_url,
                    image_url=img_url,
                    available_sizes=sizes,
                    in_stock=True
                )
            )

            if len(offers) >= limit:
                break

        return offers
