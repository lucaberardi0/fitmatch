import urllib.parse
import logging
import time
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes

logger = logging.getLogger("fitmatch.scraper.alltricks")


class AlltricksScraper(BaseScraper):
    """Scraper for Alltricks (alltricks.it), European leader in cycling, outdoor, GPS & fitness equipment (Decathlon Group)."""

    store_id = "alltricks"
    store_name = "Alltricks"
    base_url = "https://www.alltricks.it"
    rating = 4.2
    review_count = 1323
    formatted_review_count = "1,3K"
    card_theme = "colored"
    accent_color = "#007AB8"
    free_shipping_threshold = 69.0
    standard_shipping_cost = 4.99
    courier = "Bartolini (BRT)"
    api_key = "key_PQ0WloSnsVtffWIN"
    api_base = "https://ac.cnstrc.com/search"

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        self.headers.update({
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Referer": "https://www.alltricks.it/",
        })

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        quoted_query = urllib.parse.quote(query.strip())
        url = f"{self.api_base}/{quoted_query}?key={self.api_key}&num_results_per_page={min(max(limit * 2, 10), 30)}"

        data = self._fetch_json(url)
        if not data or not isinstance(data, dict):
            return []

        results = data.get("response", {}).get("results", [])
        candidates: List[Dict[str, Any]] = []

        for item in results:
            title = item.get("value")
            d = item.get("data") or {}
            raw_url = d.get("url")

            raw_price = d.get("sale_price") or d.get("price")
            price = self.parse_price(raw_price)

            if not title or not price or not raw_url:
                continue

            brand = d.get("brand")
            if not brand or not isinstance(brand, str):
                brand = None

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            # Check original vs discounted price
            list_price = self.parse_price(d.get("price"))
            orig_price = list_price if (list_price and list_price > price) else None

            img_url = d.get("image_url")
            pid = str(d.get("id") or item.get("variation_id") or "")

            candidates.append({
                "pid": pid,
                "title": full_title,
                "brand": brand,
                "price": price,
                "orig_price": orig_price,
                "url": raw_url,
                "img_url": img_url
            })

            if len(candidates) >= limit:
                break

        if not candidates:
            return []

        details_results: List[Dict[str, Any]] = []
        for idx, cand in enumerate(candidates):
            if idx > 0:
                time.sleep(0.12)
            try:
                details_results.append(self.fetch_pdp_details(cand["url"], title=cand["title"]))
            except Exception:
                details_results.append({"sizes": [], "gallery_images": [], "in_stock": None})

        offers: List[Offer] = []
        for cand, det in zip(candidates, details_results):
            gallery = det.get("gallery_images") or ([cand["img_url"]] if cand["img_url"] else [])
            if cand["img_url"] and cand["img_url"] not in gallery:
                gallery.insert(0, cand["img_url"])
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=cand["pid"] if cand["pid"] else None,
                    title=cand["title"],
                    brand=cand["brand"],
                    price=cand["price"],
                    original_price=cand["orig_price"],
                    url=cand["url"],
                    image_url=cand["img_url"] or (gallery[0] if gallery else None),
                    gallery_images=gallery[:8],
                    available_sizes=det.get("sizes") or [],
                    in_stock=True if det.get("in_stock") is None else bool(det["in_stock"]),
                )
            )

        return offers

    def fetch_pdp_details(self, product_url: str, title: Optional[str] = None) -> Dict[str, Any]:
        """Fetch verified in-stock sizes, large Swiper gallery photos, and stock status from Alltricks PDP."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return {"sizes": [], "gallery_images": [], "in_stock": None}
            soup = BeautifulSoup(html, "html.parser")

            # Primary product gallery lives cleanly inside .swiper .swiper-zoom-container
            raw_gallery: List[str] = []
            for img in soup.select(".swiper .swiper-zoom-container img, .swiper-slide img"):
                src = (img.get("data-src") or img.get("src") or "").strip()
                if src and "product-cdn.alltricks.com/large/" in src:
                    raw_gallery.append(src)
            if not raw_gallery:
                raw_gallery = self.extract_jsonld_images(soup, base_url=self.base_url, limit=8)
            gallery = self.normalize_gallery_urls(raw_gallery, base_url=self.base_url, limit=8)

            sel = soup.select_one('select[name="product_id"]')
            if not sel:
                return {"sizes": [], "gallery_images": gallery, "in_stock": None}

            sizes: List[str] = []
            total_real_opts = 0
            for opt in sel.select("option"):
                val = opt.get("value", "").strip()
                if not val:
                    continue
                total_real_opts += 1
                if opt.has_attr("disabled") or "disabled" in (opt.get("class") or []):
                    continue
                stock_label = (opt.get("data-stock-label") or "").lower()
                if any(w in stock_label for w in ["esaurito", "epuis", "out of stock", "non disponib"]):
                    continue
                txt = opt.get("data-label") or opt.get_text(strip=True)
                if txt and not any(w in txt.lower() for w in ["taglia", "select", "seleziona"]):
                    sizes.append(txt)

            norm_sizes = self.normalize_sizes_for_product(sizes, title=title, url=product_url, soup=soup)
            in_stock = (len(sizes) > 0) if total_real_opts >= 2 else None
            return {"sizes": norm_sizes, "gallery_images": gallery, "in_stock": in_stock}
        except Exception as e:
            logger.debug(f"[Alltricks] fetch_pdp_details error on {product_url}: {e}")
            return {"sizes": [], "gallery_images": [], "in_stock": None}

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Fetch verified in-stock sizes from Alltricks product detail page."""
        return self.fetch_pdp_details(product_url, title=title).get("sizes", [])
