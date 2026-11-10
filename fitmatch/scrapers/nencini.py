import re
import json
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


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
        candidates: List[Dict[str, Any]] = []

        for card in cards:
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

                candidates.append({
                    "pid": str(pid) if pid else None,
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

        def _get_sizes(cand: Dict[str, Any]) -> List[str]:
            try:
                return self.fetch_sizes(cand["product_url"])
            except Exception:
                return []

        with ThreadPoolExecutor(max_workers=min(len(candidates), 6)) as ex:
            sizes_results = list(ex.map(_get_sizes, candidates))

        offers: List[Offer] = []
        for cand, sizes in zip(candidates, sizes_results):
            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=cand["pid"],
                    title=cand["title"],
                    brand=cand["brand"],
                    price=cand["price"],
                    original_price=cand["orig_price"],
                    url=cand["product_url"],
                    image_url=cand["img_url"],
                    available_sizes=sizes,
                    in_stock=True
                )
            )

        return offers

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Extract verified in-stock sizes from Nencini product detail page."""
        self._ensure_session()
        html = self._fetch_html(product_url)
        if not html:
            return []
        soup = BeautifulSoup(html, "html.parser")

        # 1. Parse window.tipiTaglia mapping if present
        m = re.search(r"window\.tipiTaglia\s*=\s*(\{.*?\});\s*(?:window|\n|<)", html, re.DOTALL)
        eu_map = {}
        if m:
            try:
                data = json.loads(m.group(1))
                if "EU" in data:
                    for entry in data["EU"]:
                        attr_id = entry.get("attributi_dettaglio_ID")
                        eu_val = entry.get("descr")
                        if attr_id and eu_val:
                            eu_map[str(attr_id)] = eu_val
            except Exception:
                pass

        active_switch = soup.select_one(".detail_switch_size_type_label.active")
        active_system = active_switch.get("data-size-key", "").upper() if active_switch else ""

        in_stock_sizes = []
        for a in soup.select(".gescat_detail_info_size a"):
            disp_str = a.get("data-disponibilita", "0")
            try:
                disp = int(disp_str)
            except ValueError:
                disp = 0
            if disp <= 0:
                continue

            classes = a.get("class", [])
            if any(c in classes for c in ["disabled", "non_disponibile", "esaurito"]):
                continue

            matched_eu = None
            for c in classes:
                if c.startswith("dettaglio-id-"):
                    attr_id = c.replace("dettaglio-id-", "")
                    if attr_id in eu_map:
                        matched_eu = eu_map[attr_id]
                        break

            if matched_eu:
                in_stock_sizes.append(matched_eu)
            else:
                desc_el = a.select_one(".desc_size")
                if desc_el:
                    txt = desc_el.get_text(strip=True)
                    if active_system == "US" and not txt.upper().startswith("US"):
                        txt = f"US {txt}"
                    in_stock_sizes.append(txt)

        return normalize_sizes(in_stock_sizes)
