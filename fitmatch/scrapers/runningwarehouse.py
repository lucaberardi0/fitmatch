import re
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


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
        candidates = []

        for cell in cells:
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

                pid = cell.get("data-code")

                # Image URL (upgrade to higher resolution 500px if available)
                img_el = cell.select_one("img")
                raw_img = None
                if img_el:
                    raw_img = img_el.get("src")
                    if not raw_img or "blank.gif" in raw_img:
                        raw_img = img_el.get("data-src") or (img_el.get("data-srcset", "").split(" ")[0] if img_el.get("data-srcset") else None)
                if (not raw_img or not raw_img.startswith("http")) and pid:
                    raw_img = f"https://img.runningwarehouse.eu/watermark/rs.php?path={pid}-1.jpg&nw=500"

                img_url = raw_img if raw_img and raw_img.startswith("http") else None
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

                gallery_urls = []
                if img_url:
                    gallery_urls.append(img_url)
                if pid:
                    for i in range(1, 5):
                        angle_url = f"https://img.runningwarehouse.eu/watermark/rs.php?path={pid}-{i}.jpg&nw=500"
                        if angle_url not in gallery_urls:
                            gallery_urls.append(angle_url)

                candidates.append({
                    "pid": pid,
                    "title": title,
                    "brand": brand,
                    "price": price,
                    "orig_price": orig_price,
                    "url": product_url,
                    "img_url": img_url,
                    "gallery_urls": gallery_urls,
                    "sizes": normalize_sizes(sizes)
                })
                if len(candidates) >= limit:
                    break
            except Exception:
                continue

        if not candidates:
            return []

        # Find candidates missing sizes and fetch them concurrently
        missing_indices = [i for i, c in enumerate(candidates) if not c["sizes"]]
        if missing_indices:
            with ThreadPoolExecutor(max_workers=min(len(missing_indices), 8)) as executor:
                fetched_sizes = list(executor.map(lambda idx: self.fetch_sizes(candidates[idx]["url"]), missing_indices))
            for idx, s in zip(missing_indices, fetched_sizes):
                candidates[idx]["sizes"] = s

        for c in candidates:
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=c["pid"],
                    title=c["title"],
                    brand=c["brand"],
                    price=c["price"],
                    original_price=c["orig_price"],
                    url=c["url"],
                    image_url=c["img_url"],
                    gallery_images=c["gallery_urls"],
                    available_sizes=c["sizes"],
                    in_stock=True
                )
            )

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Fetch real-time in-stock sizes directly from the product detail page."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []

            soup = BeautifulSoup(html, "html.parser")
            rows = soup.select("table.styled_subproduct_list tr.subproduct")
            sizes: List[str] = []

            for row in rows:
                stock_el = row.select_one(".stock .available")
                if stock_el and stock_el.text.strip() == "0":
                    continue

                # 1. Primary: Extract directly from data-eu on styleitem (standard for RunningWarehouse EU)
                eu_items = row.select("span.styleitem[data-eu]")
                found_eu = False
                for item in eu_items:
                    eu_val = item.get("data-eu")
                    if eu_val and eu_val.strip():
                        sizes.append(eu_val.strip())
                        found_eu = True

                if not found_eu:
                    # 2. Apparel or non-EU shoes: check Taglia styleitem
                    for item in row.select("ul.stylelist li"):
                        lbl = item.select_one("span.style")
                        if lbl and any(w in lbl.text.lower() for w in ["tagli", "misur", "size"]):
                            val_el = item.select_one("span.styleitem")
                            if val_el:
                                s_text = val_el.get("data-eu") or val_el.get("data-us") or val_el.text.strip()
                                if s_text:
                                    sizes.append(s_text)
                                    found_eu = True

                if not found_eu:
                    # 3. Fallback regex on row text
                    txt = row.text
                    m = re.search(r"(?:US|EU)\s*([0-9]+(?:\.[0-9]+)?)", txt)
                    if m:
                        val = re.sub(r"\.0$", "", m.group(1))
                        sizes.append(val)

            return normalize_sizes(sizes)
        except Exception:
            return []
