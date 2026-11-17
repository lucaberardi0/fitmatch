import re
import urllib.parse
import logging
from typing import List, Optional, Dict
import json
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.decathlon")

_RSC_URL_RE = re.compile(r'\\?"url\\?":\\?"(/p/[^\\"]+)\\?"')
_RSC_SIZES_RE = re.compile(r'\\?"availableSizes\\?":(\[[^\]]*\])')


class DecathlonScraper(BaseScraper):
    """Scraper for Decathlon Italy (decathlon.it) — European sporting goods leader."""

    store_id = "decathlon"
    store_name = "Decathlon"
    base_url = "https://www.decathlon.it"
    rating = 1.5
    review_count = 2690
    formatted_review_count = "2,7K"
    card_theme = "colored"
    accent_color = "#0082C8"
    free_shipping_threshold = 60.0
    standard_shipping_cost = 4.99
    courier = "Corriere Espresso"

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

        # Parse pre-rendered sizes from Next.js RSC state without crossing product boundaries
        raw_url_to_sizes = self.extract_rsc_raw_sizes(soup)

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
            raw_href = link_el["href"]
            product_url = urllib.parse.urljoin(self.base_url, raw_href)
            clean_rel = raw_href.split("?")[0]

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

            raw_sizes = raw_url_to_sizes.get(clean_rel) or raw_url_to_sizes.get(raw_href) or []
            gender = self.normalizer.extract_gender(title, product_url)
            category = self.normalizer.detect_article_type(title)
            sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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
                    available_sizes=sizes,
                    in_stock=True
                )
            )

            if len(offers) >= limit:
                break

        return offers

    @staticmethod
    def extract_rsc_raw_sizes(soup: BeautifulSoup) -> Dict[str, List[str]]:
        """Extract raw availableSizes per product path strictly within each product's RSC slice."""
        url_to_raw: Dict[str, List[str]] = {}
        for sc in soup.find_all("script"):
            text = sc.string
            if not text or "availableSizes" not in text:
                continue
            url_matches = list(_RSC_URL_RE.finditer(text))
            for idx, m in enumerate(url_matches):
                u = m.group(1).split("?")[0]
                next_start = url_matches[idx + 1].start() if idx + 1 < len(url_matches) else len(text)
                chunk = text[m.end():min(next_start, m.end() + 2500)]
                sm = _RSC_SIZES_RE.search(chunk)
                if not sm:
                    continue
                raw_json = sm.group(1).replace('\\"', '"')
                try:
                    parsed = json.loads(raw_json)
                    if isinstance(parsed, list):
                        url_to_raw[u] = parsed
                except Exception:
                    continue
        return url_to_raw

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Fetch available in-stock sizes for Decathlon product."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []
            soup = BeautifulSoup(html, "html.parser")
            path = urllib.parse.urlparse(product_url).path.split("?")[0]
            raw_map = self.extract_rsc_raw_sizes(soup)
            raw_sizes: Optional[List[str]] = raw_map.get(path)
            if raw_sizes is None:
                for sc in soup.find_all("script"):
                    if sc.string and "availableSizes" in sc.string:
                        m = _RSC_SIZES_RE.search(sc.string)
                        if m:
                            raw_sizes = json.loads(m.group(1).replace('\\"', '"'))
                            break
            if not raw_sizes:
                return []
            gender = self.normalizer.extract_gender(title or "", product_url)
            category = self.normalizer.detect_article_type(title or "") if title else None
            return normalize_sizes(raw_sizes, gender=gender, category=category)
        except Exception as e:
            logger.debug(f"[Decathlon] fetch_sizes error on {product_url}: {e}")
            return []
