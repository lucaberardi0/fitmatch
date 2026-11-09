import logging
import urllib.parse
from typing import List, Optional, Dict, Any
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes

logger = logging.getLogger("fitmatch.scraper.adidas")


class AdidasScraper(BaseScraper):
    """Scraper for Adidas Italy (adidas.it) — Official brand flagship store."""

    store_id = "adidas"
    store_name = "Adidas"
    base_url = "https://www.adidas.it"
    taxonomy_api_url = "https://www.adidas.it/api/search/taxonomy"

    def __init__(self, timeout: int = 15):
        super().__init__(timeout=timeout)
        self.headers.update({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Accept": "application/json",
            "Accept-Language": "it-IT,it;q=0.9",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "Referer": "https://www.adidas.it/"
        })

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Adidas Italy catalog via official taxonomy/search API."""
        clean_query = query.strip()
        if not clean_query:
            return []

        params = {
            "sitePath": "it",
            "query": clean_query,
            "start": 0
        }
        data = self._fetch_json(self.taxonomy_api_url, params=params)
        if not data or not isinstance(data, dict):
            return []

        items = data.get("itemList", {}).get("items", [])
        offers: List[Offer] = []

        for p in items:
            try:
                name = p.get("displayName")
                if not name:
                    continue

                raw_price = p.get("salePrice") or p.get("price")
                price = float(raw_price) if raw_price is not None else None
                if not price or price <= 0:
                    continue

                list_price = p.get("price")
                orig_price = float(list_price) if list_price and float(list_price) > price else None

                link = p.get("link")
                if not link:
                    continue
                url = urllib.parse.urljoin(self.base_url, link)

                img_obj = p.get("image")
                img_url = img_obj.get("src") if isinstance(img_obj, dict) else (img_obj if isinstance(img_obj, str) else None)
                if not img_url:
                    sec_img = p.get("secondImage")
                    img_url = sec_img.get("src") if isinstance(sec_img, dict) else sec_img

                pid = str(p.get("productId") or p.get("modelId") or "")
                raw_sizes = p.get("availableSizes", [])
                sizes = normalize_sizes(raw_sizes)
                in_stock = p.get("orderable", True)

                # If Adidas taxonomy API omits size breakdown for in-stock item, infer standard curve
                if not sizes and in_stock:
                    sizes = self.infer_standard_sizes(name, link, p.get("category"), p.get("subTitle"))

                offers.append(
                    Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=pid,
                        title=name,
                        brand="Adidas",
                        price=price,
                        original_price=orig_price,
                        url=url,
                        image_url=img_url,
                        available_sizes=sizes,
                        in_stock=in_stock
                    )
                )

                if len(offers) >= limit:
                    break
            except Exception as e:
                logger.debug(f"[Adidas] Parsing error for item: {e}")
                continue

        return offers

    def infer_standard_sizes(
        self,
        title: str,
        url_or_link: str = "",
        category: Optional[str] = None,
        subtitle: Optional[str] = None
    ) -> List[str]:
        """Infer typical Adidas EU size curves based on product category and gender."""
        context = f"{title} {url_or_link} {category or ''} {subtitle or ''}".lower()
        is_women = any(w in context for w in ["donna", "women", "wmns", "femme"])
        is_apparel = any(w in context for w in [
            "apparel", "abbigliamento", "t-shirt", "maglia", "pantalon", "short",
            "giacca", "felpa", "tight", "top", "bra", "calzamaglia"
        ])
        is_shoe = any(w in context for w in [
            "shoes", "scarpe", "scarpa", "shoe", "adizero", "adios", "running",
            "supernova", "boston", "prime", "takumi", "sl20", "ultraboost"
        ]) and not is_apparel

        if is_shoe:
            if is_women:
                return ["36", "36.5", "37.5", "38", "38.5", "39.5", "40", "40.5", "41.5", "42"]
            else:
                return ["40", "40.5", "41.5", "42", "42.5", "43.5", "44", "44.5", "45.5", "46", "46.5", "47.5"]
        elif is_apparel:
            return ["XS", "S", "M", "L", "XL"]
        else:
            return ["40", "40.5", "41.5", "42", "42.5", "43.5", "44", "44.5", "45.5", "46"]

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract or estimate available sizes for Adidas products."""
        return self.infer_standard_sizes(title or "", product_url)
