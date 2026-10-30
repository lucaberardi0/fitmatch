import urllib.parse
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer


class MaxiSportScraper(BaseScraper):
    store_id = "maxisport"
    store_name = "Maxi Sport"
    base_url = "https://www.maxisport.com"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        search_url = f"{self.base_url}/catalogsearch/result/"
        params = {"q": query}
        html = self._fetch_html(search_url, params=params)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        items = soup.select(".item.product.product-item")
        offers: List[Offer] = []

        for item in items[:limit]:
            try:
                # Title and Link
                link_el = item.select_one("a.product-item-link")
                if not link_el or not link_el.get("href"):
                    continue
                title = link_el.get_text(strip=True)
                product_url = link_el["href"]

                # Product ID
                pid_el = item.select_one("[data-product-id]")
                product_id = pid_el["data-product-id"] if pid_el and pid_el.get("data-product-id") else None

                # Current Price
                price = None
                price_wrapper = item.select_one("[data-price-type='finalPrice']")
                if price_wrapper and price_wrapper.has_attr("data-price-amount"):
                    price = self.parse_price(price_wrapper["data-price-amount"])
                if not price:
                    price_text = item.select_one("[data-price-type='finalPrice'] .price, .price-box .price")
                    if price_text:
                        price = self.parse_price(price_text.get_text())

                if not price:
                    continue

                # Original Price
                orig_price = None
                old_wrapper = item.select_one("[data-price-type='oldPrice']")
                if old_wrapper and old_wrapper.has_attr("data-price-amount"):
                    orig_price = self.parse_price(old_wrapper["data-price-amount"])
                if not orig_price:
                    old_text = item.select_one("[data-price-type='oldPrice'] .price, .old-price .price")
                    if old_text:
                        orig_price = self.parse_price(old_text.get_text())

                # Image
                img_el = item.select_one("img.product-image-photo, img")
                img_url = None
                if img_el:
                    img_url = img_el.get("src") or img_el.get("data-src")

                # Brand (often derived from URL or leading word)
                brand = None
                brand_el = item.select_one(".brand, .product-item-brand")
                if brand_el:
                    brand = brand_el.get_text(strip=True)
                elif "/" in product_url:
                    slug = product_url.rstrip("/").split("/")[-1]
                    slug_parts = slug.split("-")
                    if slug_parts:
                        brand = slug_parts[0].capitalize()

                offers.append(
                    Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=product_id,
                        title=title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=product_url,
                        image_url=img_url,
                        in_stock=True
                    )
                )
            except Exception:
                continue

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Extract available sizes from Maxi Sport jsonConfig."""
        html = self._fetch_html(product_url)
        if not html:
            return []
        import json, re
        soup = BeautifulSoup(html, "html.parser")
        for s in soup.find_all("script"):
            if s.string and "data-role=swatch-options" in s.string:
                m = re.search(r"\"jsonConfig\":\s*(\{.*?\})\s*,\s*\"jsonSwatchConfig\"", s.string)
                if m:
                    try:
                        cfg = json.loads(m.group(1))
                        for attr_id, attr_data in cfg.get("attributes", {}).items():
                            label = attr_data.get("label", "").lower()
                            if "taglia" in label or "size" in label:
                                return [
                                    opt["label"].strip().replace(",", ".")
                                    for opt in attr_data.get("options", [])
                                    if len(opt.get("products", [])) > 0
                                ]
                    except Exception:
                        pass
        return []
