import re
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes

logger = logging.getLogger("fitmatch.scraper.tradeinn")


class TradeinnScraper(BaseScraper):
    """
    Scraper for Tradeinn (tradeinn.com / runnerinn, bikeinn, smashinn, trekkinn).
    European sports retail giant covering running, cycling, padel, outdoor & multisport gear.
    """

    store_id = "tradeinn"
    store_name = "Tradeinn"
    base_url = "https://www.tradeinn.com"
    rating = 4.7
    review_count = 18500
    formatted_review_count = "18,5K"
    card_theme = "white"
    accent_color = "#F25A24"
    free_shipping_threshold = 150.0
    standard_shipping_cost = 4.99
    courier = "Poste / GLS / DPD"

    SEARCH_ENDPOINT = "https://www.tradeinn.com/listado.php"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        clean_query = query.strip()
        if not clean_query:
            return []

        ql = clean_query.lower()

        # Select the most relevant initial Tradeinn shop ID
        # 10: Runnerinn, 11: Bikeinn, 14: Smashinn (Padel/Tennis), 17: Trekkinn, 18: Sports All
        if any(w in ql for w in ["padel", "racchetta", "pala", "bullpadel", "nox", "starvie", "siux"]):
            preferred_shops = ["14", "18", "10"]
        elif any(w in ql for w in ["bici", "ciclismo", "ciclocomputer", "tacx", "wahoo", "kickr", "kask", "castelli"]):
            preferred_shops = ["11", "18", "10"]
        elif any(w in ql for w in ["trekking", "alpinismo", "arrampicata", "scarponi", "tenda"]):
            preferred_shops = ["17", "18", "10"]
        else:
            preferred_shops = ["10", "18", "11"]

        headers = {
            "Referer": "https://www.tradeinn.com",
            "Origin": "https://www.tradeinn.com",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": self.headers["User-Agent"]
        }

        results = []
        for shop_id in preferred_shops:
            payload = {
                "action": "buscador_google",
                "palabras": clean_query,
                "id_tienda": shop_id,
                "idioma": "ita",
                "visitorid": str(uuid.uuid4()),
                "nextToken": ""
            }

            try:
                resp = self.session.post(
                    self.SEARCH_ENDPOINT,
                    data=payload,
                    headers=headers,
                    impersonate="chrome",
                    timeout=self.timeout
                )
                if resp.status_code == 200 and resp.text:
                    data = resp.json()
                    items = data.get("results", [])
                    if items:
                        results = items
                        break
            except Exception as e:
                logger.debug(f"[Tradeinn] Shop {shop_id} attempt error: {e}")
                continue

        if not results:
            return []

        offers: List[Offer] = []
        candidates = []
        for item in results:
            product = item.get("product") or {}
            title = product.get("title")
            p_id = str(item.get("id") or "")
            if not title or not p_id:
                continue

            brands = product.get("brands") or []
            brand = brands[0] if brands else None

            # Price extraction: Country 98 is Italy in Tradeinn
            price: Optional[float] = None
            attributes = product.get("attributes") or {}

            # First priority: check price_all_91_to_100 for '98:...'
            p_text = attributes.get("price_all_91_to_100", {}).get("text", [])
            for entry in p_text:
                if entry.startswith("98:"):
                    raw_val = entry.split(":", 1)[1]
                    price = self.parse_price(raw_val)
                    break

            # Fallback: scan all price_all_ keys if 98 not found
            if not price:
                for k, v in attributes.items():
                    if k.startswith("price_all_") and isinstance(v, dict):
                        for entry in v.get("text", []):
                            if ":" in entry:
                                val_candidate = self.parse_price(entry.split(":", 1)[1])
                                if val_candidate and val_candidate > 5.0:
                                    price = val_candidate
                                    break
                    if price:
                        break

            if not price:
                continue

            # Clean product URL
            raw_uri = product.get("uri") or f"https://www.tradeinn.com/runnerinn/it/p/{p_id}/p"
            clean_url = raw_uri.split("?")[0]

            # Construct clean webp product image
            try:
                div_folder = int(p_id) // 10000
                slug_match = re.search(r"/([^/]+)/" + re.escape(p_id) + r"/p", clean_url)
                slug = slug_match.group(1) if slug_match else "product"
                img_url = f"https://www.tradeinn.com/h/{div_folder}/{p_id}/{slug}.webp"
                gallery = [img_url, f"https://www.tradeinn.com/h/{div_folder}/{p_id}_1/{slug}.webp"]
            except Exception:
                img_url = None
                gallery = []

            # Check stock
            in_stock = product.get("availability") == "IN_STOCK"

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            candidate = {
                "p_id": p_id,
                "full_title": full_title,
                "brand": brand,
                "price": price,
                "clean_url": clean_url,
                "img_url": img_url,
                "gallery": gallery,
                "in_stock": in_stock,
            }
            candidates.append(candidate)
            if len(candidates) >= limit:
                break

        if not candidates:
            return []

        # Concurrently fetch available sizes for all candidates
        with ThreadPoolExecutor(max_workers=min(len(candidates), 8)) as executor:
            sizes_list = list(executor.map(lambda c: self.fetch_sizes(c["clean_url"]), candidates))

        for c, sizes in zip(candidates, sizes_list):
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=c["p_id"],
                    title=c["full_title"],
                    brand=c["brand"],
                    price=c["price"],
                    original_price=None,
                    url=c["clean_url"],
                    image_url=c["img_url"],
                    gallery_images=c["gallery"],
                    available_sizes=sizes,
                    in_stock=c["in_stock"]
                )
            )

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Extract available sizes from Tradeinn product detail page."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []
            matches = re.findall(r"\"size\"\s*:\s*\"([^\"]+)\"[^}]+?\"availability\"\s*:\s*\"https://schema\.org/InStock\"", html, re.DOTALL)
            if not matches:
                matches = re.findall(r"\"size\"\s*:\s*\"([^\"]+)\"", html)
            return normalize_sizes(matches)
        except Exception as e:
            logger.debug(f"[Tradeinn] fetch_sizes error on {product_url}: {e}")
            return []
