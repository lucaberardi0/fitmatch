import json
import logging
from typing import List, Optional, Any
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes, is_female_context
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper.deporvillage")


class DeporvillageScraper(BaseScraper):
    """Scraper for Deporvillage (deporvillage.it), premier Southern Europe cycling, outdoor, electronics & sports retailer."""

    store_id = "deporvillage"
    store_name = "Deporvillage"
    base_url = "https://www.deporvillage.it"
    rating = 4.5
    review_count = 486000
    formatted_review_count = "486K"
    card_theme = "colored"
    accent_color = "#D63B0E"
    free_shipping_threshold = 80.0
    standard_shipping_cost = 4.99
    courier = "GLS / DPD"
    app_id = "GFLCWVLLQY"
    api_key = "77b624f582d4304da3a6159f116575b0"
    index_name = "prod_product_IT_default"

    def __init__(self, timeout: int = 12):
        super().__init__(timeout=timeout)
        self.normalizer = ProductNormalizer()

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        url = f"https://{self.app_id}-dsn.algolia.net/1/indexes/{self.index_name}/query"
        headers = {
            "x-algolia-application-id": self.app_id,
            "x-algolia-api-key": self.api_key,
            "Content-Type": "application/json"
        }
        payload = {
            "query": query,
            "hitsPerPage": min(max(limit * 2, 10), 40)
        }

        try:
            resp = self.session.post(
                url,
                headers=headers,
                json=payload,
                impersonate="chrome",
                timeout=self.timeout
            )
            if resp.status_code != 200:
                logger.warning(f"[{self.store_name}] Algolia returned HTTP {resp.status_code}")
                return []
            data = resp.json()
        except Exception as e:
            logger.error(f"[{self.store_name}] Search error on query '{query}': {e}")
            return []

        hits = data.get("hits", [])
        offers: List[Offer] = []

        for h in hits:
            title = h.get("title") or h.get("name")
            url_str = h.get("url")
            price_info = h.get("price")

            if isinstance(price_info, dict):
                raw_price = price_info.get("price")
                pvp = self.parse_price(price_info.get("pvp"))
            else:
                raw_price = price_info
                pvp = None

            price = self.parse_price(raw_price)

            if not title or not price or not url_str:
                continue

            brand_info = h.get("brand") or {}
            brand = brand_info.get("name") if isinstance(brand_info, dict) else str(brand_info or "")
            if not brand:
                brand = None

            full_title = (
                f"{brand} {title}"
                if brand and not title.lower().startswith(brand.lower())
                else title
            )

            orig_price = pvp if (pvp and pvp > price) else None

            # Build high-resolution image URL & full gallery
            gallery_data = h.get("gallery") or {}
            images = gallery_data.get("images", []) if isinstance(gallery_data, dict) else (h.get("images") or [])
            if not isinstance(images, list):
                images = []

            gallery_urls = [
                f"https://cdn.deporvillage.com/cdn-cgi/image/h=500,w=400,f=auto,q=75,fit=contain,background=white/product-vertical/{img}"
                for img in images if img
            ]
            img_url = gallery_urls[0] if gallery_urls else None

            # Extract available sizes in stock
            raw_sizes: List[str] = []
            for s in (h.get("sizes") or []):
                if isinstance(s, dict) and s.get("name"):
                    raw_sizes.append(str(s["name"]).strip())
                elif isinstance(s, str) and s.strip():
                    raw_sizes.append(s.strip())
            gender = "women" if is_female_context(title=full_title) or is_female_context(title=url_str) else self.normalizer.extract_gender(full_title, url_str)
            category = self.normalizer.detect_article_type(full_title)
            sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

            pid = str(h.get("objectID") or h.get("id") or "")

            offers.append(
                Offer(
                    store_id=self.store_id,
                    store_name=self.store_name,
                    product_id=pid if pid else None,
                    title=full_title,
                    brand=brand,
                    price=price,
                    original_price=orig_price,
                    url=url_str,
                    image_url=img_url,
                    gallery_images=gallery_urls,
                    available_sizes=sizes,
                    in_stock=True
                )
            )
            if len(offers) >= limit:
                break

        return offers

    def _collect_variants_from_ld(self, obj: Any) -> List[str]:
        raw_sizes: List[str] = []
        if isinstance(obj, list):
            for item in obj:
                raw_sizes.extend(self._collect_variants_from_ld(item))
            return raw_sizes
        if not isinstance(obj, dict):
            return raw_sizes
        if "@graph" in obj and isinstance(obj["@graph"], list):
            raw_sizes.extend(self._collect_variants_from_ld(obj["@graph"]))
        for v in (obj.get("hasVariant") or []):
            if not isinstance(v, dict):
                continue
            offers = v.get("offers")
            offer_list = offers if isinstance(offers, list) else ([offers] if isinstance(offers, dict) else [])
            in_stock = any("InStock" in str(o.get("availability") or "") for o in offer_list if isinstance(o, dict))
            if in_stock and v.get("size"):
                raw_sizes.append(str(v["size"]).strip())
        return raw_sizes

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Extract live in-stock sizes from Deporvillage PDP JSON-LD ProductGroup variants."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []
            soup = BeautifulSoup(html, "html.parser")
            raw_sizes: List[str] = []
            for sc in soup.find_all("script", type="application/ld+json"):
                if not sc.string or "hasVariant" not in sc.string:
                    continue
                try:
                    data = json.loads(sc.string)
                    raw_sizes.extend(self._collect_variants_from_ld(data))
                except Exception:
                    continue
            pdp_title = title or (soup.find("h1").get_text(strip=True) if soup.find("h1") else "")
            gender = "women" if is_female_context(title=pdp_title) or is_female_context(title=product_url) else self.normalizer.extract_gender(pdp_title, product_url)
            category = self.normalizer.detect_article_type(pdp_title) if pdp_title else None
            return normalize_sizes(raw_sizes, gender=gender, category=category)
        except Exception as e:
            logger.debug(f"[Deporvillage] fetch_sizes error on {product_url}: {e}")
            return []
