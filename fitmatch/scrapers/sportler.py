import re
import json
import logging
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.sportler")


class SportlerScraper(BaseScraper):
    """Scraper for Sportler (sportler.com) — Top Italian sporting goods retailer in Northern Italy & Alps."""

    store_id = "sportler"
    store_name = "Sportler"
    base_url = "https://www.sportler.com"
    suggest_url = "https://www.sportler.com/it/FactFinderSuggestRequestProxy"

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        self.normalizer = ProductNormalizer()
        self.headers.update({
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://www.sportler.com/it",
        })

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Sportler catalog via FactFinder API and concurrent detail parsing."""
        params = {
            "searchTerm": query.strip(),
            "channel": "it",
            "format": "json"
        }

        data = self._fetch_json(self.suggest_url, params=params)
        if not data or not isinstance(data, dict):
            logger.debug(f"[Sportler] No suggest response for query: {query}")
            return []

        suggestions = data.get("suggestions", [])
        candidates = []
        for s in suggestions:
            attrs = s.get("attributes", {})
            deeplink = attrs.get("deeplink")
            if deeplink and "/it/p/" in deeplink:
                candidates.append({
                    "url": deeplink.split("?")[0],
                    "raw_name": s.get("name", "").strip(),
                    "image": s.get("image"),
                    "id": attrs.get("id") or attrs.get("articleNr") or attrs.get("masterId")
                })

        if not candidates:
            return []

        target_candidates = candidates[:max(limit, 4)]
        offers: List[Offer] = []

        # Concurrent fetch of candidate product pages to extract precise pricing and sizes
        with ThreadPoolExecutor(max_workers=min(len(target_candidates), 5)) as executor:
            futures = [
                executor.submit(self._fetch_product_details, cand)
                for cand in target_candidates
            ]
            for fut in futures:
                try:
                    offer = fut.result()
                    if offer:
                        offers.append(offer)
                except Exception as e:
                    logger.warning(f"[Sportler] Failed to parse product candidate: {e}")

        return offers[:limit]

    def _fetch_product_details(self, candidate: Dict[str, Any]) -> Optional[Offer]:
        """Fetch product detail page to parse exact price, discount, and in-stock sizes."""
        url = candidate["url"]
        html = self._fetch_html(url)
        if not html:
            return None

        # 1. Parse GTM dataLayer for price and discount
        price = None
        orig_price = None
        brand = None
        title = candidate.get("raw_name")
        image_url = candidate.get("image")

        matches = re.findall(r"dataLayer\.push\((.*?)\);", html, re.DOTALL)
        for m in matches:
            if "item_name" in m:
                try:
                    d = json.loads(m.strip())
                    items = d.get("ecommerce", {}).get("items", [])
                    if items:
                        it = items[0]
                        p_val = self.parse_price(it.get("price"))
                        if p_val and p_val > 0:
                            price = p_val
                            disc = self.parse_price(it.get("discount"))
                            if disc and disc > 0:
                                orig_price = round(price + disc, 2)
                        if it.get("item_brand"):
                            brand = it["item_brand"].strip()
                        if it.get("item_name") and not title:
                            title = it["item_name"].strip()
                        break
                except Exception:
                    pass

        # Fallback price regex in HTML if dataLayer missed
        if not price:
            p_match = re.search(r"class=[\"']price[\"'][^>]*>[\s\n]*€?\s*([\d\.,]+)", html, re.I)
            if p_match:
                price = self.parse_price(p_match.group(1))

        if not price:
            return None

        # Clean title
        if title:
            # Sportler titles often end with ' - scarpe running neutre - uomo' or similar
            title = re.sub(r"\s*-\s*scarpe.*$", "", title, flags=re.I).strip()
            title = re.sub(r"\s*-\s*sneakers.*$", "", title, flags=re.I).strip()
            title = re.sub(r"\s*-\s*gilet.*$", "", title, flags=re.I).strip()
            title = re.sub(r"\s*-\s*pantaloni.*$", "", title, flags=re.I).strip()
        else:
            title = candidate.get("raw_name") or "Articolo Sportler"

        if not brand:
            brand = self.normalizer.extract_brand(title)
        if brand and not title.lower().startswith(brand.lower()):
            title = f"{brand} {title}"

        # 2. Extract in-stock sizes
        soup = BeautifulSoup(html, "html.parser")
        sizes: List[str] = []
        size_select = soup.find("select", id=re.compile(r"filterorig_size", re.I))
        if size_select:
            for opt in size_select.find_all("option"):
                raw_s = opt.get_text(strip=True)
                clean_s = re.sub(r"(?i)\s*(?:us|eu|uk)\b", "", raw_s).strip().replace(",", ".")
                if clean_s:
                    sizes.append(clean_s)
        else:
            size_inp = soup.find("input", id=re.compile(r"filterorig_size", re.I))
            if size_inp and size_inp.get("value"):
                clean_s = re.sub(r"(?i)\s*(?:us|eu|uk)\b", "", size_inp["value"]).strip().replace(",", ".")
                if clean_s and clean_s.lower() != "no size":
                    sizes.append(clean_s)

        # 3. High quality image if available
        og_img = soup.find("meta", property="og:image")
        if og_img and og_img.get("content"):
            image_url = og_img["content"]
        elif image_url and "_micro_" in image_url:
            image_url = image_url.replace("_micro_", "_c600_")

        return Offer(
            store_id=self.store_id,
            store_name=self.store_name,
            product_id=str(candidate.get("id")) if candidate.get("id") else None,
            title=title,
            brand=brand,
            price=price,
            original_price=orig_price,
            url=url,
            image_url=image_url,
            available_sizes=normalize_sizes(sizes),
            in_stock=True
        )
