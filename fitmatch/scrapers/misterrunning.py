import json
import logging
from typing import Any, Dict, List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes, is_female_context
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.misterrunning")


class MisterRunningScraper(BaseScraper):
    store_id = "misterrunning"
    store_name = "Mister Running"
    base_url = "https://www.misterrunning.com"
    rating = 4.9
    review_count = 37250
    formatted_review_count = "37,2K"
    card_theme = "colored"
    accent_color = "#005EB8"
    free_shipping_threshold = 49.0
    standard_shipping_cost = 4.90
    courier = "DHL / UPS"
    clerk_key = "lZ8DVtTLdHkHHx3YPe8lEvCOalU8FPiN"
    api_url = "https://api.clerk.io/v2/search/search"

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        self.normalizer = ProductNormalizer()

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
                gender = "women" if is_female_context(title=name) or is_female_context(title=url) else self.normalizer.extract_gender(name, url)
                category = self.normalizer.detect_article_type(name)
                sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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

    def fetch_pdp_details(self, product_url: str, title: Optional[str] = None) -> Dict[str, Any]:
        """Extract verified in-stock EU sizes and active-colorway gallery angles from MisterRunning PDP."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return {"sizes": [], "gallery_images": [], "in_stock": None}
            soup = BeautifulSoup(html, "html.parser")

            # Active colorway gallery only (div.gallery excludes sibling color swatches in ul.varianti)
            raw_gallery: List[str] = []
            for a_el in soup.select("div.gallery a"):
                href = (a_el.get("href") or "").strip()
                if href and ("/images/" in href or "/media/products/" in href):
                    raw_gallery.append(href)
                img_el = a_el.find("img")
                if img_el:
                    src = (img_el.get("data-src") or img_el.get("src") or "").strip()
                    if src and not (href and ("/images/" in href or "/media/products/" in href)):
                        raw_gallery.append(src)
            if not raw_gallery:
                for img_el in soup.select("div.gallery img"):
                    src = (img_el.get("data-src") or img_el.get("src") or "").strip()
                    if src:
                        raw_gallery.append(src)
            gallery = self.normalize_gallery_urls(raw_gallery, base_url=self.base_url, limit=8)

            all_size_els = soup.select(".opt")
            raw_sizes: List[str] = []
            for el in soup.select(".opt.opt_on"):
                eu_val = el.get("data-eu")
                if eu_val and eu_val.strip():
                    raw_sizes.append(eu_val.strip())
                    continue
                col1 = el.select_one(".col1")
                txt = col1.get_text(strip=True) if col1 else (el.get("data-usa") or "")
                if txt:
                    raw_sizes.append(txt.strip())

            pdp_title = title or (soup.find("h1").get_text(strip=True) if soup.find("h1") else "")
            gender = "women" if is_female_context(title=pdp_title) or is_female_context(title=product_url) else self.normalizer.extract_gender(pdp_title, product_url)
            category = self.normalizer.detect_article_type(pdp_title) if pdp_title else None
            sizes = normalize_sizes(raw_sizes, gender=gender, category=category)
            in_stock = (len(raw_sizes) > 0) if len(all_size_els) >= 2 else None
            return {"sizes": sizes, "gallery_images": gallery, "in_stock": in_stock}
        except Exception as e:
            logger.debug(f"[MisterRunning] fetch_pdp_details error on {product_url}: {e}")
            return {"sizes": [], "gallery_images": [], "in_stock": None}

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract verified in-stock EU sizes from MisterRunning PDP (.opt.opt_on)."""
        return self.fetch_pdp_details(product_url, title=title).get("sizes", [])
