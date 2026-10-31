import urllib.parse
import logging
from typing import List, Optional
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer

logger = logging.getLogger("fitmatch.scraper.alltricks")


class AlltricksScraper(BaseScraper):
    """Scraper for Alltricks (alltricks.it), European leader in cycling, outdoor, GPS & fitness equipment (Decathlon Group)."""

    store_id = "alltricks"
    store_name = "Alltricks"
    base_url = "https://www.alltricks.it"
    api_key = "key_PQ0WloSnsVtffWIN"
    api_base = "https://ac.cnstrc.com/search"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        quoted_query = urllib.parse.quote(query.strip())
        url = f"{self.api_base}/{quoted_query}?key={self.api_key}&num_results_per_page={min(max(limit * 2, 10), 30)}"

        data = self._fetch_json(url)
        if not data or not isinstance(data, dict):
            return []

        results = data.get("response", {}).get("results", [])
        offers: List[Offer] = []

        for item in results:
            title = item.get("value")
            d = item.get("data") or {}
            raw_url = d.get("url")

            raw_price = d.get("sale_price") or d.get("price")
            price = self.parse_price(raw_price)

            if not title or not price or not raw_url:
                continue

            brand = d.get("brand")
            if not brand or not isinstance(brand, str):
                brand = None

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            # Check original vs discounted price
            list_price = self.parse_price(d.get("price"))
            orig_price = list_price if (list_price and list_price > price) else None

            img_url = d.get("image_url")
            pid = str(d.get("id") or item.get("variation_id") or "")

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=pid if pid else None,
                    title=full_title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=raw_url,
                    image_url=img_url,
                    available_sizes=[],
                    in_stock=True
                )
            )

            if len(offers) >= limit:
                break

        return offers
