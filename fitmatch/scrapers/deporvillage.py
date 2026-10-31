import logging
from typing import List, Optional
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer

logger = logging.getLogger("fitmatch.scraper.deporvillage")


class DeporvillageScraper(BaseScraper):
    """Scraper for Deporvillage (deporvillage.it), premier Southern Europe cycling, outdoor, electronics & sports retailer."""

    store_id = "deporvillage"
    store_name = "Deporvillage"
    base_url = "https://www.deporvillage.it"
    app_id = "GFLCWVLLQY"
    api_key = "77b624f582d4304da3a6159f116575b0"
    index_name = "prod_product_IT_default"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        url = f"https://{self.app_id}-dsn.algolia.net/1/indexes/{self.index_name}/query"
        headers = {
            "x-algolia-application-id": self.app_id,
            "x-algolia-api-key": self.api_key,
            "Content-Type": "application/json"
        }
        payload = {
            "query": query,
            "hitsPerPage": min(max(limit * 2, 10), 40)
        }

        try:
            resp = self.session.post(
                url,
                headers=headers,
                json=payload,
                impersonate="chrome",
                timeout=self.timeout
            )
            if resp.status_code != 200:
                logger.warning(f"[{self.store_name}] Algolia returned HTTP {resp.status_code}")
                return []
            data = resp.json()
        except Exception as e:
            logger.error(f"[{self.store_name}] Search error on query '{query}': {e}")
            return []

        hits = data.get("hits", [])
        offers: List[Offer] = []

        for h in hits:
            title = h.get("title") or h.get("name")
            url_str = h.get("url")
            price_info = h.get("price")

            if isinstance(price_info, dict):
                raw_price = price_info.get("price")
                pvp = self.parse_price(price_info.get("pvp"))
            else:
                raw_price = price_info
                pvp = None

            price = self.parse_price(raw_price)

            if not title or not price or not url_str:
                continue

            brand_info = h.get("brand") or {}
            brand = brand_info.get("name") if isinstance(brand_info, dict) else str(brand_info or "")
            if not brand:
                brand = None

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            orig_price = pvp if (pvp and pvp > price) else None

            # Build high-resolution image URL
            gallery = h.get("gallery") or {}
            images = gallery.get("images", []) if isinstance(gallery, dict) else []
            img_url = None
            if images and isinstance(images, list) and images[0]:
                img_name = images[0]
                img_url = f"https://cdn.deporvillage.com/cdn-cgi/image/h=500,w=400,f=auto,q=75,fit=contain,background=white/product-vertical/{img_name}"

            # Extract available sizes in stock
            raw_sizes = h.get("sizes") or []
            sizes = [str(s).strip().replace(",", ".") for s in raw_sizes if s]

            pid = str(h.get("objectID") or h.get("id") or "")

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=pid if pid else None,
                    title=full_title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=url_str,
                    image_url=img_url,
                    available_sizes=sizes,
                    in_stock=True
                )
            )
            if len(offers) >= limit:
                break

        return offers
