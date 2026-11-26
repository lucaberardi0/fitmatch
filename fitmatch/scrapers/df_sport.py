import re
import urllib.parse
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes, is_female_context

logger = logging.getLogger("fitmatch.scraper.df_sport")


class DFSportScraper(BaseScraper):
    """
    Scraper for DF Sport Specialist (df-sportspecialist.it).
    Major Italian retail sports chain specializing in outdoor, mountain, running, cycling and padel.
    """

    store_id = "df_sportspecialist"
    store_name = "DF Sport Specialist"
    base_url = "https://www.df-sportspecialist.it"
    rating = 4.6
    review_count = 38000
    formatted_review_count = "38K"
    card_theme = "grid"
    accent_color = "#E30613"
    free_shipping_threshold = 100.0
    standard_shipping_cost = 8.00
    courier = "Corriere Espresso"

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
        candidates: List[Dict[str, Any]] = []

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

            candidates.append({
                "p_id": str(p.get("id") or ""),
                "full_title": full_title,
                "brand": brand,
                "price": price,
                "orig_price": orig_price,
                "clean_url": clean_url,
                "img_url": img_url,
                "in_stock": bool(p.get("available", True)),
            })
            if len(candidates) >= limit:
                break

        if not candidates:
            return []

        with ThreadPoolExecutor(max_workers=min(len(candidates), 6)) as executor:
            details_list = list(executor.map(lambda c: self.fetch_pdp_details(c["clean_url"], title=c["full_title"]), candidates))

        offers: List[Offer] = []
        for c, det in zip(candidates, details_list):
            gallery = det.get("gallery_images") or ([c["img_url"]] if c["img_url"] else [])
            if c["img_url"] and c["img_url"] not in gallery:
                gallery.insert(0, c["img_url"])
            in_stock = det["in_stock"] if det.get("in_stock") is not None else c["in_stock"]
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=c["p_id"] if c["p_id"] else None,
                    title=c["full_title"],
                    brand=c["brand"],
                    price=c["price"],
                    original_price=c["orig_price"],
                    url=c["clean_url"],
                    image_url=c["img_url"] or (gallery[0] if gallery else None),
                    gallery_images=gallery[:8],
                    available_sizes=det.get("sizes") or [],
                    in_stock=in_stock,
                )
            )

        return offers

    def _extract_variant_size(self, variant: Dict[str, Any], size_idx: Optional[int]) -> Optional[str]:
        if size_idx is not None:
            opts = variant.get("options")
            if isinstance(opts, list) and len(opts) > size_idx and opts[size_idx]:
                return str(opts[size_idx]).strip()
            opt_val = variant.get(f"option{size_idx + 1}")
            if opt_val:
                return str(opt_val).strip()
        v_title = variant.get("title")
        if v_title and str(v_title).strip().lower() != "default title":
            return str(v_title).strip()
        return None

    def fetch_pdp_details(self, product_url: str, title: Optional[str] = None) -> Dict[str, Any]:
        """Fetch real-time in-stock sizes and multi-angle gallery via Shopify .js endpoint."""
        try:
            clean_url = product_url.split("?")[0]
            js_url = f"{clean_url}.js"
            data = self._fetch_json(js_url)
            if not data or not isinstance(data, dict):
                return {"sizes": [], "gallery_images": [], "in_stock": None}

            raw_imgs: List[str] = []
            feat = data.get("featured_image")
            if isinstance(feat, str):
                raw_imgs.append(feat)
            for im in (data.get("images") or []):
                if isinstance(im, str):
                    raw_imgs.append(im)
                elif isinstance(im, dict) and (im.get("src") or im.get("url")):
                    raw_imgs.append(str(im.get("src") or im.get("url")))
            gallery = self.normalize_gallery_urls(raw_imgs, base_url=self.base_url, limit=8)

            variants = data.get("variants") or []
            if not isinstance(variants, list):
                return {"sizes": [], "gallery_images": gallery, "in_stock": None}

            options_meta = data.get("options") or []
            size_idx: Optional[int] = None
            for idx, opt in enumerate(options_meta):
                opt_name = (opt.get("name") if isinstance(opt, dict) else str(opt)).lower()
                if any(k in opt_name for k in ("tagli", "size", "misur", "numer")):
                    size_idx = idx
                    break

            sizes: List[str] = []
            any_avail = False
            for v in variants:
                if not isinstance(v, dict) or v.get("available") is not True:
                    continue
                any_avail = True
                sz = self._extract_variant_size(v, size_idx)
                if sz and sz not in sizes:
                    sizes.append(sz)

            pdp_title = title or data.get("title") or ""
            gender = "women" if is_female_context(title=pdp_title) else None
            ptype = str(data.get("type") or "").lower()
            category = "apparel" if any(k in ptype for k in ("abbigliamento", "apparel", "t-shirt", "magli", "pantalon", "giacc")) else None
            norm_sizes = normalize_sizes(sizes, gender=gender, category=category)
            return {
                "sizes": norm_sizes,
                "gallery_images": gallery,
                "in_stock": any_avail if variants else None,
            }
        except Exception as e:
            logger.debug(f"[DFSport] fetch_pdp_details error on {product_url}: {e}")
            return {"sizes": [], "gallery_images": [], "in_stock": None}

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Fetch real-time in-stock sizes via Shopify .js endpoint (which includes per-variant availability)."""
        return self.fetch_pdp_details(product_url, title=title).get("sizes", [])
