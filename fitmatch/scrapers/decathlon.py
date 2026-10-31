import re
import urllib.parse
import logging
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.decathlon")


class DecathlonScraper(BaseScraper):
    """Scraper for Decathlon Italy (decathlon.it) — European sporting goods leader."""

    store_id = "decathlon"
    store_name = "Decathlon"
    base_url = "https://www.decathlon.it"

    def __init__(self, timeout: int = 14):
        super().__init__(timeout=timeout)
        self.normalizer = ProductNormalizer()
        self.headers = {
            "Accept-Language": "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Decathlon Italy catalog for sports apparel, shoes and gear."""
        quoted_query = urllib.parse.quote(query.strip())
        search_url = f"{self.base_url}/it/search?Ntt={quoted_query}"

        html = self._fetch_html(search_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        articles = soup.find_all("article")
        if not articles:
            return []

        offers: List[Offer] = []

        for art in articles:
            # 1. Product Title
            title = None
            h2 = art.find("h2")
            if h2:
                title = h2.get_text(strip=True)
            if not title:
                a_label = art.find("a", attrs={"aria-label": True})
                if a_label and a_label.get("aria-label"):
                    title = a_label["aria-label"].strip()
            if not title:
                img_el = art.find("img", alt=True)
                if img_el and img_el.get("alt"):
                    title = img_el["alt"].strip()
            if not title:
                continue

            # 2. Product URL
            link_el = art.find("a", href=lambda h: h and "/p/" in h)
            if not link_el or not link_el.get("href"):
                continue
            product_url = urllib.parse.urljoin(self.base_url, link_el["href"])

            # 3. Prices & Discounts
            price_blocks = art.select(".vp-price-amount, [class*=\"price-amount\"]")
            price = None
            orig_price = None

            for pb in price_blocks:
                t = pb.get_text(strip=True)
                val = self.parse_price(t)
                if val:
                    if "precedente" in t.lower() or "prima" in t.lower():
                        orig_price = val
                    else:
                        price = val

            if not price:
                text_match = re.search(r"Prezzo attuale\s*([\d\.,]+)", art.get_text())
                if text_match:
                    price = self.parse_price(text_match.group(1))

            if not price:
                continue

            # 4. Brand extraction
            brand = self.normalizer.extract_brand(title)

            # 5. Image URL
            img_el = art.find("img")
            img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

            # 6. Product ID
            pid = None
            if "/p/" in product_url:
                parts = [p for p in product_url.split("/") if p]
                if len(parts) >= 2:
                    pid = parts[-1].split("?")[0]

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=pid,
                    title=title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=product_url,
                    image_url=img_url,
                    available_sizes=[],
                    in_stock=True
                )
            )

            if len(offers) >= limit:
                break

        return offers
