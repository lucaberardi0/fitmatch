import urllib.parse
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer


class CisalfaScraper(BaseScraper):
    store_id = "cisalfa"
    store_name = "Cisalfa Sport"
    base_url = "https://www.cisalfasport.it"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        search_url = f"{self.base_url}/it-it/search"
        params = {"q": query}
        html = self._fetch_html(search_url, params=params)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        tiles = soup.select(".product-tile")
        offers: List[Offer] = []

        for tile in tiles[:limit]:
            try:
                # Title
                title_el = tile.select_one(".cc-tile__title, .product-tile-title, [itemprop='name']")
                if not title_el:
                    continue
                title = title_el.get_text(strip=True)

                # Link
                link_el = tile.select_one("a.cc-tile__url-absolute, a.link")
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
        """Extract available sizes from Cisalfa product detail page."""
        html = self._fetch_html(product_url)
        if not html:
            return []
        soup = BeautifulSoup(html, "html.parser")
        sizes = []
        for el in soup.select(".size-attribute.cc-available"):
            val = el.get("data-display-value")
            if val:
                sizes.append(val.strip().replace(",", "."))
        return sizes
