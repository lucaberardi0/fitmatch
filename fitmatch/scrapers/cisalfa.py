import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


class CisalfaScraper(BaseScraper):
    store_id = "cisalfa"
    store_name = "Cisalfa Sport"
    base_url = "https://www.cisalfasport.it"
    rating = 2.6
    review_count = 1850
    formatted_review_count = "1,8K"
    card_theme = "colored"
    accent_color = "#C8102E"
    free_shipping_threshold = 99.0
    standard_shipping_cost = 9.90
    courier = "BRT / GLS"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        search_url = f"{self.base_url}/it-it/search"
        params = {"q": query}
        html = self._fetch_html(search_url, params=params)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        tiles = soup.select(".product-tile, .cc-product-tile")
        candidates: List[Dict[str, Any]] = []

        for tile in tiles:
            try:
                # Title
                title_el = tile.select_one(".cc-tile__title, .product-tile-title, [itemprop='name']")
                if not title_el:
                    continue
                title = title_el.get_text(strip=True)

                # Link
                link_el = tile.select_one("a.cc-tile__url-absolute, a.link, a")
                if not link_el or not link_el.get("href"):
                    continue
                raw_href = link_el["href"]
                product_url = urllib.parse.urljoin(self.base_url, raw_href)

                # Brand (often present in URL or brand element)
                brand = None
                brand_el = tile.select_one(".cc-tile__brand, .brand")
                if brand_el:
                    brand = brand_el.get_text(strip=True)
                elif "/it-it/" in raw_href:
                    parts = raw_href.split("/")
                    if len(parts) >= 3 and parts[2] not in ("search", "donna", "uomo", "bambino"):
                        brand = parts[2].capitalize()

                # Current Price
                price = None
                sales_val = tile.select_one(".sales .value[content], .sales [content]")
                if sales_val and sales_val.get("content"):
                    price = self.parse_price(sales_val["content"])
                if not price:
                    sales_text = tile.select_one(".sales, .cc-product__prices--sales, .price")
                    if sales_text:
                        price = self.parse_price(sales_text.get_text())

                if not price:
                    continue

                # Original / Strikethrough Price
                orig_price = None
                strike_val = tile.select_one("s.value[content], .strike .value[content]")
                if strike_val and strike_val.get("content"):
                    orig_price = self.parse_price(strike_val["content"])
                if not orig_price:
                    strike_text = tile.select_one("s.value, .strike, .cc-tile__price--old")
                    if strike_text:
                        orig_price = self.parse_price(strike_text.get_text())

                # Image
                img_el = tile.select_one("img")
                img_url = None
                if img_el:
                    img_url = img_el.get("src") or img_el.get("data-src")

                # Product ID
                pid_el = tile.select_one("[data-itemid]")
                product_id = pid_el["data-itemid"] if pid_el and pid_el.get("data-itemid") else None

                candidates.append({
                    "product_id": product_id,
                    "title": title,
                    "brand": brand,
                    "price": price,
                    "orig_price": orig_price,
                    "product_url": product_url,
                    "img_url": img_url
                })

                if len(candidates) >= limit:
                    break
            except Exception:
                continue

        if not candidates:
            return []

        def _get_details(cand: Dict[str, Any]) -> Dict[str, Any]:
            try:
                return self.fetch_pdp_details(cand["product_url"], title=cand["title"])
            except Exception:
                return {"sizes": [], "gallery_images": [], "in_stock": None}

        with ThreadPoolExecutor(max_workers=min(len(candidates), 6)) as ex:
            details_results = list(ex.map(_get_details, candidates))

        offers: List[Offer] = []
        for cand, det in zip(candidates, details_results):
            gallery = det.get("gallery_images") or ([cand["img_url"]] if cand["img_url"] else [])
            if cand["img_url"] and cand["img_url"] not in gallery:
                gallery.insert(0, cand["img_url"])
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=cand["product_id"],
                    title=cand["title"],
                    brand=cand["brand"],
                    price=cand["price"],
                    original_price=cand["orig_price"],
                    url=cand["product_url"],
                    image_url=cand["img_url"] or (gallery[0] if gallery else None),
                    gallery_images=gallery[:8],
                    available_sizes=det.get("sizes") or [],
                    in_stock=True if det.get("in_stock") is None else bool(det["in_stock"]),
                )
            )

        return offers

    def fetch_pdp_details(self, product_url: str, title: Optional[str] = None) -> Dict[str, Any]:
        """Extract available sizes, PDP slider gallery angles, and stock state from Cisalfa PDP."""
        html = self._fetch_html(product_url)
        if not html:
            return {"sizes": [], "gallery_images": [], "in_stock": None}
        soup = BeautifulSoup(html, "html.parser")

        raw_gallery: List[str] = []
        for img in soup.select(".js-pdp-slider-img .cc-product-image img, .cc-pdp__image-wrp img"):
            src = (img.get("data-src") or img.get("src") or "").strip()
            if src and "sw=180" not in src:
                raw_gallery.append(src)
        gallery = self.normalize_gallery_urls(raw_gallery, base_url=self.base_url, limit=8)

        all_size_els = soup.select(".size-attribute")
        sizes = []
        for el in soup.select(".size-attribute.cc-available"):
            val = el.get("data-display-value")
            if val:
                sizes.append(val.strip().replace(",", "."))
        norm_sizes = self.normalize_sizes_for_product(sizes, title=title, url=product_url, soup=soup)
        in_stock = (len(sizes) > 0) if len(all_size_els) >= 2 else None
        return {"sizes": norm_sizes, "gallery_images": gallery, "in_stock": in_stock}

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract available sizes from Cisalfa product detail page."""
        return self.fetch_pdp_details(product_url, title=title).get("sizes", [])
