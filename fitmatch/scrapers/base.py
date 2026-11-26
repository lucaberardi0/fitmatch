import re
import json
import urllib.parse
import logging
from abc import ABC, abstractmethod
from typing import List, Optional, Any, Dict
from curl_cffi import requests
from fitmatch.models import Offer, clean_image_url, normalize_sizes, is_female_context
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.scraper")


class BaseScraper(ABC):
    """Abstract base class for store scrapers."""

    store_id: str
    store_name: str
    base_url: str
    rating: float = 4.8
    review_count: int = 1200
    formatted_review_count: Optional[str] = None
    card_theme: str = "white"  # "white", "olive", "grid", "dark"
    accent_color: Optional[str] = None
    free_shipping_threshold: Optional[float] = None
    standard_shipping_cost: Optional[float] = None
    courier: Optional[str] = None

    def __init__(self, timeout: int = 12):
        self.timeout = timeout
        self.session = requests.Session()
        self.headers = {
            "Accept-Language": "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7",
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            )
        }

    @abstractmethod
    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search the store catalog for a given query and return a list of Offers."""
        pass

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Fetch available in-stock sizes from the product detail page."""
        return []

    def fetch_pdp_details(self, product_url: str, title: Optional[str] = None) -> Dict[str, Any]:
        """Fetch sizes, gallery_images, and optional in_stock status from a PDP in a single HTTP request."""
        return {
            "sizes": self.fetch_sizes(product_url, title=title),
            "gallery_images": [],
            "in_stock": None,
        }

    @staticmethod
    def normalize_gallery_urls(urls: List[Any], base_url: Optional[str] = None, limit: int = 8) -> List[str]:
        """Resolve relative/protocol-relative image URLs, sanitize placeholders, and deduplicate preserving order."""
        out: List[str] = []
        seen = set()
        for raw in urls:
            if not raw or not isinstance(raw, str):
                continue
            u = raw.strip()
            if not u or u.startswith("data:"):
                continue
            if u.startswith("//"):
                u = f"https:{u}"
            elif u.startswith("/") and base_url:
                u = urllib.parse.urljoin(base_url, u)
            cleaned = clean_image_url(u)
            if not cleaned:
                continue
            low = cleaned.lower()
            if any(bad in low for bad in ("pixel.png", "svg", "rating.", "icon", "logo", "sprite")):
                continue
            if cleaned not in seen:
                seen.add(cleaned)
                out.append(cleaned)
                if len(out) >= limit:
                    break
        return out

    @classmethod
    def extract_jsonld_images(cls, soup: Any, base_url: Optional[str] = None, limit: int = 8) -> List[str]:
        """Extract product gallery image URLs from schema.org Product JSON-LD blocks."""
        if soup is None:
            return []
        collected: List[str] = []
        for sc in soup.find_all("script", type="application/ld+json"):
            raw = sc.string or sc.get_text() or ""
            if not raw.strip():
                continue
            try:
                parsed = json.loads(raw)
            except Exception:
                continue
            stack = parsed if isinstance(parsed, list) else [parsed]
            while stack:
                node = stack.pop(0)
                if not isinstance(node, dict):
                    continue
                if isinstance(node.get("@graph"), list):
                    stack.extend(node["@graph"])
                ntype = node.get("@type")
                types = ntype if isinstance(ntype, list) else [ntype]
                if any(str(t).lower() == "product" for t in types if t):
                    imgs = node.get("image")
                    if isinstance(imgs, str):
                        collected.append(imgs)
                    elif isinstance(imgs, dict) and imgs.get("url"):
                        collected.append(str(imgs["url"]))
                    elif isinstance(imgs, list):
                        for item in imgs:
                            if isinstance(item, str):
                                collected.append(item)
                            elif isinstance(item, dict) and item.get("url"):
                                collected.append(str(item["url"]))
        return cls.normalize_gallery_urls(collected, base_url=base_url, limit=limit)

    def _fetch_html(self, url: str, params: Optional[Dict[str, Any]] = None) -> Optional[str]:
        """Fetch HTML content with Chrome impersonation."""
        try:
            resp = self.session.get(
                url,
                params=params,
                headers=self.headers,
                impersonate="chrome",
                timeout=self.timeout
            )
            if resp.status_code == 200:
                return resp.text
            logger.warning(f"[{self.store_name}] HTTP {resp.status_code} for URL: {resp.url}")
            return None
        except Exception as e:
            logger.error(f"[{self.store_name}] Request error on {url}: {e}")
            return None

    def _fetch_json(self, url: str, params: Optional[Dict[str, Any]] = None) -> Optional[Any]:
        """Fetch JSON payload with Chrome impersonation."""
        try:
            resp = self.session.get(
                url,
                params=params,
                headers=self.headers,
                impersonate="chrome",
                timeout=self.timeout
            )
            if resp.status_code == 200:
                return resp.json()
            logger.warning(f"[{self.store_name}] HTTP {resp.status_code} on JSON API: {resp.url}")
            return None
        except Exception as e:
            logger.error(f"[{self.store_name}] JSON Request error on {url}: {e}")
            return None

    @staticmethod
    def parse_price(val: Any) -> Optional[float]:
        """Extract a clean float from diverse string/number price formats."""
        if val is None:
            return None
        if isinstance(val, (int, float)):
            return round(float(val), 2)
        
        # Remove currency symbols and non-digits/dots/commas
        cleaned = re.sub(r"[^\d,\.]", "", str(val))
        if not cleaned:
            return None
        
        # Handle European decimal formats: 1.199,50 -> 1199.50
        if "." in cleaned and "," in cleaned:
            cleaned = cleaned.replace(".", "").replace(",", ".")
        elif "," in cleaned:
            cleaned = cleaned.replace(",", ".")
            
        try:
            return round(float(cleaned), 2)
        except ValueError:
            return None

    def normalize_sizes_for_product(
        self,
        raw_sizes: Any,
        title: Optional[str] = None,
        url: Optional[str] = None,
        gender: Optional[str] = None,
        category: Optional[str] = None,
        soup: Any = None,
    ) -> List[str]:
        """Normalize sizes using resolved gender and product category context."""
        resolved_title = title
        if not resolved_title and soup is not None:
            h1 = soup.find("h1")
            if h1:
                resolved_title = h1.get_text(" ", strip=True)
        normalizer = getattr(self, "normalizer", None) or ProductNormalizer()
        resolved_gender = gender
        if not resolved_gender:
            if is_female_context(title=resolved_title) or is_female_context(title=url):
                resolved_gender = "women"
            else:
                resolved_gender = normalizer.extract_gender(resolved_title or "", url)
        resolved_category = category or (normalizer.detect_article_type(resolved_title) if resolved_title else None)
        return normalize_sizes(raw_sizes, gender=resolved_gender, category=resolved_category)
