import urllib.parse
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional, Tuple
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes, is_female_context
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.shopify")

_SIZE_OPTION_KEYS = ("taglia", "size", "misura", "grip", "impugnatura", "manico", "numero", "shoe size")
_COLOR_OPTION_KEYS = ("color", "colore", "colour", "variante", "variant", "fantasia", "modello")


class ShopifyBaseScraper(BaseScraper):
    """Shared base scraper for Shopify storefronts exposing /search/suggest.json, /collections/*/products.json, and /products/*.js."""

    @staticmethod
    def _clean_product_url(base_url: str, raw_url: str) -> Optional[str]:
        if not raw_url:
            return None
        path_only = raw_url.split("?")[0].strip()
        if "/products/" not in path_only:
            return None
        return urllib.parse.urljoin(base_url.rstrip("/") + "/", path_only.lstrip("/"))

    @staticmethod
    def _extract_js_url(product_url: str) -> str:
        clean = product_url.split("?")[0].rstrip("/")
        return clean if clean.endswith(".js") else f"{clean}.js"

    @staticmethod
    def _find_size_option_index(options: List[Dict[str, Any]]) -> Optional[int]:
        if not options:
            return None
        for idx, opt in enumerate(options):
            name = str(opt.get("name") or "").strip().lower()
            if any(k in name for k in _SIZE_OPTION_KEYS):
                return idx
        # Single non-color variant option (Shopify default 'Title' omitted)
        if len(options) == 1:
            name = str(options[0].get("name") or "").strip().lower()
            if name and name != "title" and not any(k in name for k in _COLOR_OPTION_KEYS):
                return 0
        return None

    @staticmethod
    def _detect_js_gender_and_category(
        pj: Dict[str, Any],
        title: Optional[str],
        product_url: str,
        size_opt_name: str = "",
    ) -> Tuple[Optional[str], str]:
        tags = pj.get("tags") or []
        tags_str = " ".join(str(t) for t in tags) if isinstance(tags, list) else str(tags)
        ptype_raw = str(pj.get("type") or "").strip()
        full_title = title or str(pj.get("title") or "")
        combined = f"{full_title} {ptype_raw} {tags_str} {product_url}".strip()

        gender = ProductNormalizer.extract_gender(full_title or combined, f"{tags_str} {product_url}")
        if is_female_context(gender=gender, title=combined):
            gender_norm: Optional[str] = "women"
        elif gender in ("Uomo", "Male"):
            gender_norm = "men"
        else:
            gender_norm = None

        category = ProductNormalizer.detect_article_type(combined)
        if "grip" in size_opt_name.lower() and category in ("gear", "tennis", "racket"):
            category = "tennis"
        return gender_norm, category

    def _extract_sizes_from_js(
        self,
        pj: Dict[str, Any],
        product_url: str,
        title: Optional[str] = None,
    ) -> List[str]:
        options = pj.get("options") or []
        size_idx = self._find_size_option_index(options)
        if size_idx is None:
            return []

        size_opt_name = str((options[size_idx] or {}).get("name") or "")
        variants = pj.get("variants") or []
        raw_sizes: List[str] = []

        # Respect ?variant=<id> if URL targets a single colorway variant group
        target_variant_id = None
        if "?" in product_url:
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(product_url).query)
            if qs.get("variant"):
                target_variant_id = str(qs["variant"][0])

        selected_color = None
        if target_variant_id and size_idx > 0:
            for v in variants:
                if str(v.get("id")) == target_variant_id:
                    v_opts = v.get("options") or []
                    if v_opts:
                        selected_color = v_opts[0]
                    break

        for v in variants:
            if not isinstance(v, dict) or v.get("available") is not True:
                continue
            v_opts = v.get("options") or []
            if selected_color is not None and len(v_opts) > 0 and v_opts[0] != selected_color:
                continue
            val = v_opts[size_idx] if size_idx < len(v_opts) else v.get(f"option{size_idx + 1}")
            if val is not None:
                raw_sizes.append(str(val).strip())

        if not raw_sizes:
            return []

        gender_norm, category = self._detect_js_gender_and_category(
            pj, title=title, product_url=product_url, size_opt_name=size_opt_name
        )
        return normalize_sizes(raw_sizes, gender=gender_norm, category=category)

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract verified in-stock variant sizes from Shopify /products/<handle>.js."""
        js_url = self._extract_js_url(product_url)
        pj = self._fetch_json(js_url)
        if not pj or not isinstance(pj, dict):
            return []
        return self._extract_sizes_from_js(pj, product_url=product_url, title=title or pj.get("title"))

    def _hydrate_candidate_from_js(self, cand: Dict[str, Any]) -> Optional[Offer]:
        url = cand["url"]
        pj = self._fetch_json(self._extract_js_url(url))
        if not pj or not isinstance(pj, dict):
            return None

        title = cand.get("title") or str(pj.get("title") or "").strip()
        if not title:
            return None

        raw_price_cents = pj.get("price")
        price = round(float(raw_price_cents) / 100.0, 2) if raw_price_cents else cand.get("fallback_price")
        if not price or price <= 0:
            return None

        raw_compare_cents = pj.get("compare_at_price")
        orig_price = (
            round(float(raw_compare_cents) / 100.0, 2)
            if raw_compare_cents and float(raw_compare_cents) / 100.0 > price
            else cand.get("fallback_orig_price")
        )

        img_url = cand.get("image_url") or pj.get("featured_image")
        if not img_url and isinstance(pj.get("images"), list) and pj["images"]:
            img_url = pj["images"][0]
        if isinstance(img_url, str) and img_url.startswith("//"):
            img_url = f"https:{img_url}"

        sizes = self._extract_sizes_from_js(pj, product_url=url, title=title)
        any_available = any(isinstance(v, dict) and v.get("available") is True for v in (pj.get("variants") or []))
        brand = cand.get("brand") or pj.get("vendor") or ProductNormalizer.extract_brand(title)

        return Offer(
            store_id=self.store_id,
            store_name=self.store_name,
            product_id=str(pj.get("id") or cand.get("product_id") or ""),
            title=title,
            brand=brand,
            price=price,
            original_price=orig_price,
            url=url,
            image_url=img_url,
            available_sizes=sizes,
            in_stock=bool(any_available),
        )

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        clean_query = (query or "").strip()
        if not clean_query:
            return []

        suggest_url = f"{self.base_url.rstrip('/')}/search/suggest.json"
        params = {
            "q": clean_query,
            "resources[type]": "product",
            "resources[limit]": min(max(limit * 2, 10), 25),
        }
        data = self._fetch_json(suggest_url, params=params)
        if not data or not isinstance(data, dict):
            return []

        products = data.get("resources", {}).get("results", {}).get("products", [])
        candidates: List[Dict[str, Any]] = []
        seen_urls = set()

        for p in products:
            url = self._clean_product_url(self.base_url, str(p.get("url") or ""))
            if not url or url in seen_urls:
                continue
            seen_urls.add(url)

            fallback_price = self.parse_price(p.get("price"))
            fallback_orig = self.parse_price(p.get("compare_at_price_max") or p.get("compare_at_price_min"))
            if fallback_orig and fallback_price and fallback_orig <= fallback_price:
                fallback_orig = None

            img = p.get("image") or (p.get("featured_image") or {}).get("url")
            if isinstance(img, str) and img.startswith("//"):
                img = f"https:{img}"

            candidates.append({
                "product_id": p.get("id"),
                "title": (p.get("title") or "").strip(),
                "brand": (p.get("vendor") or "").strip() or None,
                "url": url,
                "image_url": img,
                "fallback_price": fallback_price,
                "fallback_orig_price": fallback_orig,
            })
            if len(candidates) >= limit:
                break

        if not candidates:
            return []

        with ThreadPoolExecutor(max_workers=min(len(candidates), 8)) as ex:
            results = list(ex.map(self._hydrate_candidate_from_js, candidates))

        return [o for o in results if o is not None and o.in_stock]

    def fetch_collection_offers(self, collection_handle: str, limit: int = 100) -> List[Offer]:
        """Crawl a Shopify collection and verify live variant stock via /products/<handle>.js."""
        clean_handle = collection_handle.strip().strip("/")
        if not clean_handle:
            return []

        candidates: List[Dict[str, Any]] = []
        seen_urls = set()
        page = 1
        while len(candidates) < limit:
            col_url = f"{self.base_url.rstrip('/')}/collections/{clean_handle}/products.json"
            data = self._fetch_json(col_url, params={"limit": min(250, limit - len(candidates) + 20), "page": page})
            products = (data or {}).get("products") if isinstance(data, dict) else None
            if not products:
                break

            for p in products:
                handle = p.get("handle")
                if not handle:
                    continue
                url = f"{self.base_url.rstrip('/')}/products/{handle}"
                if url in seen_urls:
                    continue
                seen_urls.add(url)

                variants = p.get("variants") or []
                first_v = variants[0] if variants else {}
                fallback_price = self.parse_price(first_v.get("price"))
                img = (p.get("images") or [{}])[0].get("src") if p.get("images") else None

                candidates.append({
                    "product_id": p.get("id"),
                    "title": (p.get("title") or "").strip(),
                    "brand": (p.get("vendor") or "").strip() or None,
                    "url": url,
                    "image_url": img,
                    "fallback_price": fallback_price,
                    "fallback_orig_price": self.parse_price(first_v.get("compare_at_price")),
                })
                if len(candidates) >= limit:
                    break

            if len(products) < 50:
                break
            page += 1

        if not candidates:
            return []

        with ThreadPoolExecutor(max_workers=8) as ex:
            results = list(ex.map(self._hydrate_candidate_from_js, candidates))

        return [o for o in results if o is not None and o.in_stock]
