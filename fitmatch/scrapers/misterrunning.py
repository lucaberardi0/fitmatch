import json
from typing import List
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


class MisterRunningScraper(BaseScraper):
    store_id = "misterrunning"
    store_name = "Mister Running"
    base_url = "https://www.misterrunning.com"
    clerk_key = "lZ8DVtTLdHkHHx3YPe8lEvCOalU8FPiN"
    api_url = "https://api.clerk.io/v2/search/search"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        params = {
            "key": self.clerk_key,
            "query": query,
            "limit": limit,
            "attributes": json.dumps(["name", "price", "list_price", "image", "url", "brand", "id", "sizes"])
        }
        data = self._fetch_json(self.api_url, params=params)
        if not data or not isinstance(data, dict):
            return []

        products = data.get("product_data", [])
        offers: List[Offer] = []

        for p in products:
            try:
                name = p.get("name")
                price = self.parse_price(p.get("price"))
                url = p.get("url")
                if not name or not price or not url:
                    continue

                orig_price = self.parse_price(p.get("list_price"))
                brand = p.get("brand")
                image = p.get("image")
                pid = str(p.get("id")) if p.get("id") else None
                raw_sizes = p.get("sizes", [])
                sizes = normalize_sizes(raw_sizes)

                offers.append(
                    Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=pid,
                        title=name,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=url,
                        image_url=image,
                        available_sizes=sizes,
                        in_stock=True
                    )
                )
            except Exception:
                continue

        return offers
