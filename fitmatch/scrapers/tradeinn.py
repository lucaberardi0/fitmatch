import re
import json
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Any
from bs4 import BeautifulSoup
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
    rating = 3.3
    review_count = 52300
    formatted_review_count = "52,3K"
    card_theme = "white"
    accent_color = "#F25A24"
    free_shipping_threshold = None
    standard_shipping_cost = 4.99
    courier = "DHL / UPS / GLS / Poste"

    SEARCH_ENDPOINT = "https://www.tradeinn.com/listado.php"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        clean_query = query.strip()
        if not clean_query:
            return []

        ql = clean_query.lower()

        # Select the most relevant initial Tradeinn shop ID
        # 1: Goalinn (Calcio), 7: Snowinn (Sci/Snow), 10: Runnerinn, 11: Bikeinn,
        # 14: Smashinn (Padel/Tennis), 16: Swiminn (Nuoto), 17: Trekkinn, 18: Sports All
        if any(w in ql for w in ["padel", "tennis", "racchetta", "pala", "bullpadel", "nox", "starvie", "siux", "babolat", "wilson", "head", "yonex"]):
            preferred_shops = ["14", "18", "10"]
        elif any(w in ql for w in ["calcio", "scarpini", "mercurial", "predator", "copa", "phantom", "calcetto", "guanti portiere"]):
            preferred_shops = ["1", "18", "10"]
        elif any(w in ql for w in ["sci", "snow", "scarponi sci", "maschera sci", "atomic", "rossignol", "nordica", "fischer", "burton", "tavola snowboard", "attacchi sci"]):
            preferred_shops = ["7", "18", "17"]
        elif any(w in ql for w in ["nuoto", "costume", "occhialini", "arena", "speedo", "muta", "swim", "triathlon"]):
            preferred_shops = ["16", "18", "10"]
        elif any(w in ql for w in ["bici", "ciclismo", "ciclocomputer", "tacx", "wahoo", "kickr", "kask", "castelli"]):
            preferred_shops = ["11", "18", "10"]
        elif any(w in ql for w in ["trekking", "alpinismo", "arrampicata", "scarponi", "tenda"]):
            preferred_shops = ["17", "18", "10"]
        elif any(w in ql for w in ["basket", "jordan", "pallacanestro", "curry", "lebron", "spalding"]):
            preferred_shops = ["18", "10", "1"]
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
            sizes_list = list(executor.map(lambda c: self.fetch_sizes(c["clean_url"], title=c["full_title"]), candidates))

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

    def _collect_variants(self, node: Any, raw_sizes: List[str]) -> Optional[str]:
        """Extract in-stock variant sizes from JSON-LD node and return optional product name."""
        found_name: Optional[str] = None
        if isinstance(node, list):
            for item in node:
                n = self._collect_variants(item, raw_sizes)
                if n and not found_name:
                    found_name = n
            return found_name
        if not isinstance(node, dict):
            return None
        if isinstance(node.get("name"), str):
            found_name = node["name"].strip()
        if isinstance(node.get("@graph"), list):
            n = self._collect_variants(node["@graph"], raw_sizes)
            if n and not found_name:
                found_name = n
        for v in (node.get("hasVariant") or []):
            if not isinstance(v, dict):
                continue
            offers = v.get("offers")
            offer_list = offers if isinstance(offers, list) else ([offers] if isinstance(offers, dict) else [])
            in_stock = any("InStock" in str(o.get("availability") or "") for o in offer_list if isinstance(o, dict))
            if in_stock and v.get("size"):
                raw_sizes.append(str(v["size"]).strip())
        return found_name

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract verified in-stock sizes from Tradeinn product detail page JSON-LD."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []

            raw_sizes: List[str] = []
            resolved_title = title
            soup = BeautifulSoup(html, "html.parser") if "<" in html else None
            if soup is not None:
                for sc in soup.find_all("script", type="application/ld+json"):
                    if sc.string and "hasVariant" in sc.string:
                        try:
                            n = self._collect_variants(json.loads(sc.string), raw_sizes)
                            if n and not resolved_title:
                                resolved_title = n
                        except Exception:
                            pass

            if not raw_sizes and html.lstrip().startswith("{"):
                try:
                    n = self._collect_variants(json.loads(html), raw_sizes)
                    if n and not resolved_title:
                        resolved_title = n
                except Exception:
                    pass

            if not raw_sizes and '"OutOfStock"' not in html and '"hasVariant"' not in html:
                p1 = r'\"size\"\s*:\s*\"([^\"]+)\"[^}]+?\"availability\"\s*:\s*\"https://schema\.org/InStock\"'
                p2 = r'\"availability\"\s*:\s*\"https://schema\.org/InStock\"[^}]+?\"size\"\s*:\s*\"([^\"]+)\"'
                raw_sizes = re.findall(p1, html, re.DOTALL) + re.findall(p2, html, re.DOTALL)
            elif not raw_sizes and '"hasVariant"' in html:
                p1 = r'\"size\"\s*:\s*\"([^\"]+)\"[^}]+?\"availability\"\s*:\s*\"https://schema\.org/InStock\"'
                p2 = r'\"availability\"\s*:\s*\"https://schema\.org/InStock\"[^}]+?\"size\"\s*:\s*\"([^\"]+)\"'
                raw_sizes = re.findall(p1, html, re.DOTALL) + re.findall(p2, html, re.DOTALL)

            return self.normalize_sizes_for_product(raw_sizes, title=resolved_title, url=product_url, soup=soup)
        except Exception as e:
            logger.debug(f"[Tradeinn] fetch_sizes error on {product_url}: {e}")
            return []
