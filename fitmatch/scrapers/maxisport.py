import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes


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
        candidates: List[Dict[str, Any]] = []

        for item in items:
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

                candidates.append({
                    "product_id": product_id,
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
                return self.fetch_sizes(cand["product_url"], title=cand["title"])
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
                    product_id=cand["product_id"],
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

    @staticmethod
    def _resolve_color_product_ids(cfg: Dict[str, Any], product_url: str) -> Optional[set]:
        """Scope simple product IDs to the active colorway when a Magento jsonConfig exposes a color attribute."""
        color_attr = None
        color_attr_id = None
        for attr_id, attr_data in (cfg.get("attributes") or {}).items():
            label = str(attr_data.get("label", "")).lower()
            code = str(attr_data.get("code", "")).lower()
            if "colore" in label or "color" in label or "color" in code or "colore" in code:
                color_attr = attr_data
                color_attr_id = str(attr_id)
                break

        if not color_attr or len(color_attr.get("options") or []) <= 1:
            return None

        default_vals = cfg.get("defaultValues") or {}
        selected_opt_id = str(default_vals.get(color_attr_id) or "")
        if selected_opt_id:
            for opt in color_attr.get("options", []):
                if str(opt.get("id") or "") == selected_opt_id and opt.get("products"):
                    return {str(pid) for pid in opt["products"]}

        slug = urllib.parse.urlparse(product_url).path.rstrip("/").split("/")[-1].lower()
        parts = slug.split("-")
        if len(parts) >= 2:
            # MaxiSport URLs typically end with -<style>-<colorCode>, reflected in cfg["sku"] as <style>_<colorCode>_<size>
            tail_underscore = f"{parts[-2]}_{parts[-1]}"
            tail_dash = f"{parts[-2]}-{parts[-1]}"
            matched_ids = {
                str(pid)
                for pid, sku in (cfg.get("sku") or {}).items()
                if tail_underscore in str(sku).lower() or tail_dash in str(sku).lower()
            }
            if matched_ids:
                return matched_ids

        return None

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract available sizes from Maxi Sport jsonConfig using gender/category context."""
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
                        allowed_pids = self._resolve_color_product_ids(cfg, product_url)
                        for attr_id, attr_data in cfg.get("attributes", {}).items():
                            label = attr_data.get("label", "").lower()
                            if "taglia" in label or "size" in label:
                                raw_sizes = []
                                for opt in attr_data.get("options", []):
                                    opt_pids = {str(pid) for pid in (opt.get("products") or [])}
                                    if not opt_pids:
                                        continue
                                    if allowed_pids is not None and not (opt_pids & allowed_pids):
                                        continue
                                    raw_sizes.append(opt["label"].strip().replace(",", "."))
                                return self.normalize_sizes_for_product(raw_sizes, title=title, url=product_url, soup=soup)
                    except Exception:
                        pass
        return []
