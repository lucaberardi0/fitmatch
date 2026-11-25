import re
import json
import uuid
import logging
import threading
import statistics
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Any, Dict
from bs4 import BeautifulSoup
from curl_cffi import requests as cffi_requests
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
    DC_ENDPOINT = "https://dc.tradeinn.com"
    ITALY_COUNTRY_ID = 98
    NO_RRP_SENTINEL = 99900.0

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        self._thread_local = threading.local()

    def _get_thread_session(self):
        sess = getattr(self._thread_local, "session", None)
        if sess is None:
            sess = cffi_requests.Session()
            self._thread_local.session = sess
        return sess

    @staticmethod
    def _safe_int(val: Any, default: int = 0) -> int:
        try:
            if val is None or val == "":
                return default
            return int(float(val))
        except Exception:
            return default

    @staticmethod
    def _safe_float(val: Any) -> Optional[float]:
        try:
            if val is None or val == "":
                return None
            num = float(str(val).replace(",", ".").strip())
            return num if num > 0 else None
        except Exception:
            return None

    @classmethod
    def _is_variant_in_stock(cls, variant: Dict[str, Any]) -> bool:
        """Return True if a Tradeinn dc.tradeinn.com productes variant is purchasable."""
        if cls._safe_int(variant.get("baja"), 0) != 0:
            return False
        if cls._safe_int(variant.get("stock_disponible"), 0) > 0:
            return True
        exist = cls._safe_int(variant.get("exist"), 0)
        reservat = cls._safe_int(variant.get("stock_reservat"), 0)
        if exist - reservat > 0:
            return True
        if cls._safe_int(variant.get("exist_de"), 0) > 0:
            return True
        if cls._safe_int(variant.get("stock_volcado"), 0) > 0:
            return True
        for seller in (variant.get("sellers") or []):
            if not isinstance(seller, dict):
                continue
            if cls._safe_int(seller.get("stock"), 0) > 0 or cls._safe_int(seller.get("stock_de"), 0) > 0:
                return True
        return False

    @classmethod
    def _extract_italy_seller_price(cls, variant: Dict[str, Any]) -> Optional[float]:
        """Extract lowest Italy (id_pais=98) price across active sellers for a variant."""
        prices: List[float] = []
        for seller in (variant.get("sellers") or []):
            if not isinstance(seller, dict):
                continue
            if cls._safe_int(seller.get("stock"), 0) <= 0 and cls._safe_int(seller.get("stock_de"), 0) <= 0:
                continue
            for p_entry in (seller.get("precios_paises") or []):
                if isinstance(p_entry, dict) and cls._safe_int(p_entry.get("id_pais"), -1) == cls.ITALY_COUNTRY_ID:
                    val = cls._safe_float(p_entry.get("precio"))
                    if val and val > 1.0:
                        prices.append(val)
        return min(prices) if prices else None

    @classmethod
    def _resolve_valid_original_price(cls, current_price: float, rec_candidates: List[float]) -> Optional[float]:
        """
        Validate Tradeinn official PVC/RRP (`rec`) candidates using Tradeinn's own guardrails:
        - Exclude sentinel values (>= 99900; Tradeinn uses 99968/99999 for missing RRP)
        - Require at least 5% genuine discount (`rec >= current_price / 0.95`)
        - Exclude unrealistic outlier RRPs (> 85% implied discount)
        - Prefer the lower/median valid RRP so inflated third-party variants cannot skew discounts
        """
        if not current_price or current_price <= 0:
            return None
        valid: List[float] = []
        for rec in rec_candidates:
            if not rec or rec >= cls.NO_RRP_SENTINEL or rec <= current_price:
                continue
            disc_pct = ((rec - current_price) / rec) * 100.0
            if 5.0 <= disc_pct <= 85.0:
                valid.append(round(rec, 2))
        if not valid:
            return None
        # Median suppresses single-variant outliers while preserving the official RRP
        return round(float(statistics.median_low(valid)), 2)

    def parse_dc_payload(
        self,
        payload: Dict[str, Any],
        fallback_price: Optional[float] = None,
        fallback_in_stock: bool = True,
        title: Optional[str] = None,
        product_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Parse a `https://dc.tradeinn.com/{id}` JSON payload into price, original_price, sizes, and stock."""
        src = payload.get("_source") if isinstance(payload, dict) and isinstance(payload.get("_source"), dict) else payload
        if not isinstance(src, dict):
            return {
                "price": fallback_price,
                "original_price": None,
                "sizes": [],
                "in_stock": fallback_in_stock,
                "dc_ok": False,
            }

        win_price = self._safe_float(src.get(f"precio_win_{self.ITALY_COUNTRY_ID}"))
        productes = src.get("productes") or []

        raw_sizes: List[str] = []
        in_stock_recs: List[float] = []
        active_recs: List[float] = []
        in_stock_it_prices: List[float] = []
        has_in_stock_variant = False

        for variant in productes:
            if not isinstance(variant, dict):
                continue
            rec_val = self._safe_float(variant.get("rec"))
            is_baja = self._safe_int(variant.get("baja"), 0) != 0
            if rec_val and rec_val < self.NO_RRP_SENTINEL and not is_baja:
                active_recs.append(rec_val)

            if self._is_variant_in_stock(variant):
                has_in_stock_variant = True
                talla = str(variant.get("talla") or "").strip()
                if talla:
                    raw_sizes.append(talla)
                if rec_val and rec_val < self.NO_RRP_SENTINEL:
                    in_stock_recs.append(rec_val)
                it_p = self._extract_italy_seller_price(variant)
                if it_p:
                    in_stock_it_prices.append(it_p)

        resolved_price = win_price or (min(in_stock_it_prices) if in_stock_it_prices else None) or fallback_price
        rec_pool = in_stock_recs if in_stock_recs else active_recs
        original_price = self._resolve_valid_original_price(resolved_price, rec_pool) if resolved_price else None

        in_stock = has_in_stock_variant if productes else fallback_in_stock
        sizes = self.normalize_sizes_for_product(raw_sizes, title=title, url=product_url) if raw_sizes else []

        return {
            "price": round(resolved_price, 2) if resolved_price else fallback_price,
            "original_price": original_price,
            "sizes": sizes,
            "in_stock": in_stock,
            "dc_ok": True,
        }

    def fetch_product_details(
        self,
        product_id: str,
        fallback_price: Optional[float] = None,
        fallback_in_stock: bool = True,
        title: Optional[str] = None,
        product_url: Optional[str] = None,
        allow_html_fallback: bool = True,
    ) -> Dict[str, Any]:
        """Fetch accurate Italy price, official PVC/RRP (`original_price`), stock, and sizes from Tradeinn DC API."""
        clean_id = str(product_id or "").strip()
        if clean_id.isdigit():
            try:
                sess = self._get_thread_session()
                resp = sess.get(
                    f"{self.DC_ENDPOINT}/{clean_id}",
                    headers={
                        "Referer": "https://www.tradeinn.com/",
                        "Origin": "https://www.tradeinn.com",
                        "User-Agent": self.headers["User-Agent"],
                    },
                    impersonate="chrome",
                    timeout=min(self.timeout, 8),
                )
                if resp.status_code == 200 and resp.text:
                    parsed = self.parse_dc_payload(
                        resp.json(),
                        fallback_price=fallback_price,
                        fallback_in_stock=fallback_in_stock,
                        title=title,
                        product_url=product_url,
                    )
                    if parsed.get("dc_ok"):
                        return parsed
                elif resp.status_code in (403, 429):
                    logger.debug(f"[Tradeinn] DC rate-limited ({resp.status_code}) for {clean_id}; using fallback.")
                    sizes = self.fetch_sizes(product_url, title=title, use_dc=False) if (allow_html_fallback and product_url) else []
                    return {
                        "price": fallback_price,
                        "original_price": None,
                        "sizes": sizes,
                        "in_stock": fallback_in_stock,
                        "dc_ok": False,
                        "rate_limited": True,
                    }
            except Exception as e:
                logger.debug(f"[Tradeinn] DC details fetch error for {clean_id}: {e}")

        # Fallback to HTML JSON-LD size extraction if DC endpoint unavailable
        sizes = self.fetch_sizes(product_url, title=title, use_dc=False) if (allow_html_fallback and product_url) else []
        return {
            "price": fallback_price,
            "original_price": None,
            "sizes": sizes,
            "in_stock": fallback_in_stock,
            "dc_ok": False,
        }

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

        # Concurrently fetch real original_price (PVC/RRP), Italy price, stock & sizes via dc.tradeinn.com
        # Keep concurrency polite (<= 2) to stay well within Tradeinn's CDN rate limits
        with ThreadPoolExecutor(max_workers=min(len(candidates), 2)) as executor:
            details_list = list(
                executor.map(
                    lambda c: self.fetch_product_details(
                        c["p_id"],
                        fallback_price=c["price"],
                        fallback_in_stock=c["in_stock"],
                        title=c["full_title"],
                        product_url=c["clean_url"],
                    ),
                    candidates,
                )
            )

        for c, details in zip(candidates, details_list):
            final_price = details.get("price") or c["price"]
            orig_price = details.get("original_price")
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=c["p_id"],
                    title=c["full_title"],
                    brand=c["brand"],
                    price=final_price,
                    original_price=orig_price,
                    url=c["clean_url"],
                    image_url=c["img_url"],
                    gallery_images=c["gallery"],
                    available_sizes=details.get("sizes") or [],
                    in_stock=bool(details.get("in_stock", c["in_stock"])),
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

    def fetch_sizes(self, product_url: str, title: Optional[str] = None, use_dc: bool = True) -> List[str]:
        """Extract verified in-stock sizes from Tradeinn DC API (fast path) or HTML JSON-LD fallback."""
        try:
            # Fast path: extract product_id from URL (/138838888/p) and query dc.tradeinn.com (~30KB vs 500KB HTML)
            if use_dc:
                id_match = re.search(r"/(\d{6,12})/p(?:$|[/?#])", product_url or "")
                if id_match:
                    dc_res = self.fetch_product_details(
                        id_match.group(1),
                        title=title,
                        product_url=product_url,
                        allow_html_fallback=False,
                    )
                    if dc_res.get("dc_ok"):
                        return dc_res.get("sizes") or []

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
