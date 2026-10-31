import re
import urllib.parse
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer


class RunningWarehouseScraper(BaseScraper):
    """Scraper for Running Warehouse Europe (runningwarehouse.eu), premier running gear specialist."""

    store_id = "runningwarehouse"
    store_name = "Running Warehouse Europe"
    base_url = "https://www.runningwarehouse.eu"

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        # Setting SMID cookie ensures all displayed prices are in EUR with 22% Italian VAT included
        self.session.cookies.set("SMID", "smc_new:lang=IT:vat=IT", domain="runningwarehouse.eu")
        self.headers["Accept-Language"] = "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        search_url = f"{self.base_url}/search-eu.html"
        params = {"searchtext": query}
        html = self._fetch_html(search_url, params=params)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        cells = soup.select(".cattable-wrap-cell")
        offers: List[Offer] = []

        for cell in cells[:limit]:
            try:
                title = cell.get("data-gtm_impression_name")
                link_el = cell.select_one("a.cattable-wrap-cell-imgwrap-inner, a")
                if not link_el or not link_el.get("href"):
                    continue
                href = link_el["href"]
                product_url = urllib.parse.urljoin(self.base_url, href)

                if not title:
                    title = link_el.get_text(strip=True)
                if not title:
                    continue

                # Brand cleaning (remove category suffixes like " RUNNING Footwear")
                raw_brand = cell.get("data-gtm_impression_brand") or ""
                brand = re.sub(r"(?i)\s*(running|footwear|padel|tennis|-.*)$", "", raw_brand).strip()
                if not brand:
                    brand = None

                # Current Price from GTM attribute or fallback to text
                price = self.parse_price(cell.get("data-gtm_impression_price"))
                if not price:
                    m_p = re.search(r"(\d+[\.,]\d{2})\s*€", cell.text)
                    if m_p:
                        price = self.parse_price(m_p.group(1))

                if not price:
                    continue

                # Original / List Price (SRP)
                orig_price = None
                m_srp = re.search(r"SRP\s*(\d+[\.,]\d{2})", cell.text)
                if m_srp:
                    orig_price = self.parse_price(m_srp.group(1))

                # Image URL (upgrade to higher resolution 500px if available)
                img_el = cell.select_one("img")
                img_url = img_el.get("src") if img_el else None
                if img_url and "nw=210" in img_url:
                    img_url = img_url.replace("nw=210", "nw=500")

                # In-stock sizes from search preview card
                sizes = []
                m_sizes = re.search(r"Solo taglia\s*([0-9.,\s]+)", cell.text)
                if m_sizes:
                    raw_s = m_sizes.group(1).split(",")
                    for s in raw_s:
                        cleaned = re.sub(r"[^0-9.]", "", s.strip().replace(",", "."))
                        if cleaned:
                            cleaned = re.sub(r"\.0$", "", cleaned)
                            sizes.append(cleaned)

                pid = cell.get("data-code")

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
            except Exception:
                continue

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Fetch real-time in-stock sizes directly from the product detail page."""
        html = self._fetch_html(product_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        rows = soup.select("table.styled_subproduct_list tr.subproduct")
        sizes: List[str] = []

        for row in rows:
            txt = row.text
            # Extract US shoe sizes from subproduct table
            m = re.search(r"US\s*([0-9]+(?:\.[0-9]+)?)", txt)
            if m:
                val = re.sub(r"\.0$", "", m.group(1))
                sizes.append(val)

        return sizes
