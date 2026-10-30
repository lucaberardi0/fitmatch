import urllib.parse
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer


class NenciniSportScraper(BaseScraper):
    store_id = "nencini"
    store_name = "Nencini Sport"
    base_url = "https://www.nencinisport.it"

    def _ensure_session(self):
        """Warm up session on homepage to receive the required CSRF / security cookies."""
        if not self.session.cookies.get("__csrfuid"):
            try:
                self.session.get(f"{self.base_url}/it/", headers=self.headers, impersonate="chrome", timeout=self.timeout)
            except Exception:
                pass

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        self._ensure_session()
        search_url = f"{self.base_url}/it/search.html"
        params = {"searchkey": query}
        html = self._fetch_html(search_url, params=params)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        cards = soup.select(".product-card")
        offers: List[Offer] = []

        for card in cards[:limit]:
            try:
                link_el = card.select_one("a.card-img-link") or card.select_one(".product-title a")
                if not link_el or not link_el.get("href"):
                    continue

                raw_href = link_el["href"]
                product_url = urllib.parse.urljoin(self.base_url, raw_href)

                # Title & Brand from GTM attributes or DOM
                title = None
                brand = None
                price = None
                orig_price = None

                if link_el.has_attr("data-gtmname"):
                    title = link_el["data-gtmname"].strip()
                if not title:
                    title_el = card.select_one(".product-title a, .product-title")
                    if title_el:
                        title = title_el.get_text(strip=True)

                if link_el.has_attr("data-gtmbrand"):
                    brand = link_el["data-gtmbrand"].strip().capitalize()

                if link_el.has_attr("data-gtmprice"):
                    price = self.parse_price(link_el["data-gtmprice"])
                if not price:
                    price_el = card.select_one(".price, .current-price, .special-price")
                    if price_el:
                        price = self.parse_price(price_el.get_text())

                if not title or not price:
                    continue

                # Original Price
                old_price_el = card.select_one(".old-price, .regular-price, del")
                if old_price_el:
                    orig_price = self.parse_price(old_price_el.get_text())

                # Image
                img_el = card.select_one("img")
                img_url = None
                if img_el:
                    img_url = img_el.get("src") or img_el.get("data-src")
                    if img_url:
                        img_url = urllib.parse.urljoin(self.base_url, img_url)

                # Product ID
                pid = card.get("data-clerk-product-id") or link_el.get("data-gtmid")

                offers.append(
                    Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=str(pid) if pid else None,
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
