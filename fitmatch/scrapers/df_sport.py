import re
import urllib.parse
import logging
from typing import List, Optional
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes

logger = logging.getLogger("fitmatch.scraper.df_sport")


class DFSportScraper(BaseScraper):
    """
    Scraper for DF Sport Specialist (df-sportspecialist.it).
    Major Italian retail sports chain specializing in outdoor, mountain, running, cycling and padel.
    """

    store_id = "df_sportspecialist"
    store_name = "DF Sport Specialist"
    base_url = "https://www.df-sportspecialist.it"
    rating = 4.8
    review_count = 5400
    formatted_review_count = "5,4K"
    card_theme = "grid"
    accent_color = "#E30613"
    free_shipping_threshold = 60.0
    standard_shipping_cost = 5.90
    courier = "GLS / BRT"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        clean_query = query.strip()
        if not clean_query:
            return []

        search_url = f"{self.base_url}/search/suggest.json"
        params = {
            "q": clean_query,
            "resources[type]": "product",
            "resources[limit]": min(max(limit * 2, 10), 30)
        }

        data = self._fetch_json(search_url, params=params)
        if not data or not isinstance(data, dict):
            return []

        products = data.get("resources", {}).get("results", {}).get("products", [])
        offers: List[Offer] = []

        for p in products:
            title = p.get("title")
            raw_price = p.get("price")
            price = self.parse_price(raw_price)

            if not title or not price:
                continue

            brand = p.get("vendor")
            if not brand or not isinstance(brand, str):
                brand = None

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            # Compare at price (MSRP original price)
            raw_compare = p.get("compare_at_price_max") or p.get("compare_at_price_min")
            orig_price = self.parse_price(raw_compare)
            if orig_price and orig_price <= price:
                orig_price = None

            # Product URL
            rel_url = p.get("url") or ""
            clean_url = urllib.parse.urljoin(self.base_url, rel_url.split("?")[0])

            # Image
            img_url = p.get("image")
            if not img_url:
                feat = p.get("featured_image")
                if isinstance(feat, dict):
                    img_url = feat.get("url")

            if img_url and img_url.startswith("//"):
                img_url = "https:" + img_url

            p_id = str(p.get("id") or "")
            in_stock = bool(p.get("available", True))
            sizes = self.fetch_sizes(clean_url)

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=p_id if p_id else None,
                    title=full_title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=clean_url,
                    image_url=img_url,
                    gallery_images=[img_url] if img_url else [],
                    available_sizes=sizes,
                    in_stock=in_stock
                )
            )

            if len(offers) >= limit:
                break

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Fetch available in-stock sizes via Shopify product JSON endpoint."""
        try:
            clean_url = product_url.split("?")[0]
            json_url = f"{clean_url}.json"
            data = self._fetch_json(json_url)
            if not data or not isinstance(data, dict):
                return []

            prod = data.get("product", {})
            sizes: List[str] = []
            for v in prod.get("variants", []):
                # Only include available sizes
                if v.get("available") is False:
                    continue
                v_title = v.get("title")
                if v_title and v_title.lower() != "default title" and v_title not in sizes:
                    sizes.append(v_title)
            return normalize_sizes(sizes)
        except Exception as e:
            logger.debug(f"[DFSport] fetch_sizes error on {product_url}: {e}")
            return []
