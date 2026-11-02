import re
import json
import logging
import urllib.parse
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer

logger = logging.getLogger("fitmatch.scraper.nike")


class NikeScraper(BaseScraper):
    """Scraper for Nike Italy (nike.com/it) — Official brand store and innovation benchmark."""

    store_id = "nike"
    store_name = "Nike"
    base_url = "https://www.nike.com/it"
    search_base_url = "https://www.nike.com/it/w"

    def __init__(self, timeout: int = 15):
        super().__init__(timeout=timeout)
        self.headers.update({
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Referer": "https://www.nike.com/it",
        })

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Nike Italy catalog via Next.js rendered payload and structured product data."""
        clean_query = query.strip()
        if not clean_query:
            return []

        search_url = f"{self.search_base_url}?q={urllib.parse.quote_plus(clean_query)}"
        html = self._fetch_html(search_url)
        if not html:
            logger.warning(f"[Nike] Failed to fetch search HTML for '{query}'")
            return []

        offers = self._parse_wall_products(html, limit=limit)
        return offers

    def _parse_wall_products(self, html: str, limit: int = 10) -> List[Offer]:
        """Extract product cards from Next.js __NEXT_DATA__ wall state."""
        try:
            soup = BeautifulSoup(html, "html.parser")
            tag = soup.find("script", id="__NEXT_DATA__")
            if not tag or not tag.string:
                logger.debug("[Nike] No __NEXT_DATA__ tag found in page")
                return []

            data = json.loads(tag.string)
            wall = data.get("props", {}).get("pageProps", {}).get("initialState", {}).get("Wall", {})
            groupings = wall.get("productGroupings") or []

            offers: List[Offer] = []
            seen_codes = set()

            for group in groupings:
                products = group.get("products") or []
                for p in products:
                    if not isinstance(p, dict):
                        continue

                    code = p.get("productCode") or p.get("internalPid") or p.get("globalProductId")
                    if not code or code in seen_codes:
                        continue
                    seen_codes.add(code)

                    copy_data = p.get("copy") or {}
                    title = (copy_data.get("title") or "").strip()
                    subtitle = (copy_data.get("subTitle") or "").strip()
                    if not title:
                        continue

                    full_title = f"{title} ({subtitle})" if subtitle else title

                    prices = p.get("prices") or {}
                    curr_price = prices.get("currentPrice")
                    if curr_price is None:
                        continue

                    init_price = prices.get("initialPrice")
                    disc_pct = prices.get("discountPercentage")

                    pdp = p.get("pdpUrl") or {}
                    purl = pdp.get("url") or ""
                    if purl.startswith("/"):
                        purl = f"https://www.nike.com{purl}"

                    imgs = p.get("colorwayImages") or {}
                    img_url = imgs.get("squarishURL") or imgs.get("portraitURL")
                    gallery_urls = []
                    for k in ["squarishURL", "portraitURL"]:
                        u = imgs.get(k)
                        if u and u not in gallery_urls:
                            gallery_urls.append(u)

                    offer = Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=str(code),
                        title=full_title,
                        brand="Nike",
                        price=float(curr_price),
                        original_price=float(init_price) if init_price and init_price > curr_price else None,
                        discount_pct=float(disc_pct) if disc_pct and disc_pct > 0 else None,
                        url=purl,
                        image_url=img_url,
                        gallery_images=gallery_urls,
                        in_stock=True
                    )
                    offers.append(offer)

                    if len(offers) >= limit:
                        return offers

            return offers
        except Exception as e:
            logger.error(f"[Nike] Error parsing search wall: {e}")
            return []

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Fetch available in-stock sizes directly from the Nike PDP structured state."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []

            soup = BeautifulSoup(html, "html.parser")
            tag = soup.find("script", id="__NEXT_DATA__")
            if not tag or not tag.string:
                return []

            data = json.loads(tag.string)
            sp = data.get("props", {}).get("pageProps", {}).get("selectedProduct") or {}
            sizes_raw = sp.get("sizes") or []

            active_sizes = []
            for s in sizes_raw:
                if isinstance(s, dict) and s.get("status") == "ACTIVE":
                    label = s.get("localizedLabel") or s.get("label")
                    if label:
                        active_sizes.append(str(label))

            return active_sizes
        except Exception as e:
            logger.warning(f"[Nike] Error fetching sizes for {product_url}: {e}")
            return []
