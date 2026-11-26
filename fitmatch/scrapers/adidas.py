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
    rating = 1.5
    review_count = 603
    formatted_review_count = "603"
    card_theme = "colored"
    accent_color = "#111111"
    free_shipping_threshold = 50.0
    standard_shipping_cost = 4.99
    courier = "Poste / BRT"
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

    _COMPETITOR_BRANDS = (
        "nike", "hoka", "asics", "salomon", "brooks", "saucony",
        "mizuno", "puma", "garmin", "polar", "suunto", "coros",
        "babolat", "wilson", "head", "yonex", "new balance", "on running",
    )

    @classmethod
    def extract_gallery_from_item(cls, item: Dict[str, Any], limit: int = 8) -> List[str]:
        """Extract ordered hi-res (800x800) product angle URLs from Adidas taxonomy API item."""
        def _upgrade(u: Optional[str]) -> Optional[str]:
            if not u or not isinstance(u, str):
                return None
            return u.replace("/w_280,h_280,", "/w_800,h_800,").replace("/w_383,h_383,", "/w_800,h_800,")

        ordered_imgs: List[str] = []
        raw_list = item.get("images")
        if isinstance(raw_list, list) and raw_list:
            def _sort_key(entry: Any) -> int:
                if isinstance(entry, dict):
                    meta = entry.get("metadata") or {}
                    try:
                        return int(meta.get("sortOrder", 999))
                    except Exception:
                        return 999
                return 999

            for entry in sorted(raw_list, key=_sort_key):
                if isinstance(entry, dict):
                    meta = entry.get("metadata") or {}
                    style = str(meta.get("imageStyle") or "").lower()
                    # Prefer clean Standard studio product angles first
                    if style == "marketing":
                        continue
                    u = _upgrade(entry.get("src"))
                    if u:
                        ordered_imgs.append(u)
                elif isinstance(entry, str):
                    u = _upgrade(entry)
                    if u:
                        ordered_imgs.append(u)

        for key in ("image", "secondImage"):
            obj = item.get(key)
            src = obj.get("src") if isinstance(obj, dict) else (obj if isinstance(obj, str) else None)
            u = _upgrade(src)
            if u:
                ordered_imgs.append(u)

        return cls.normalize_gallery_urls(ordered_imgs, base_url=cls.base_url, limit=limit)

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Adidas Italy catalog via official taxonomy/search API."""
        clean_query = query.strip()
        if not clean_query:
            return []

        ql = clean_query.lower()
        if "adidas" not in ql and any(b in ql for b in self._COMPETITOR_BRANDS):
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

                gallery = self.extract_gallery_from_item(p, limit=8)
                img_url = gallery[0] if gallery else None

                pid = str(p.get("productId") or p.get("modelId") or "")
                raw_sizes = p.get("availableSizes", [])
                sizes = self.normalize_sizes_for_product(raw_sizes, title=name, url=url)
                in_stock = p.get("orderable", True)

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
                        gallery_images=gallery,
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

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract available sizes for Adidas products. Returns empty list when unverified to prevent false stock."""
        return []
