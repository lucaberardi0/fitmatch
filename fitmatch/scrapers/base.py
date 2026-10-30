import re
import logging
from abc import ABC, abstractmethod
from typing import List, Optional, Any, Dict
from curl_cffi import requests
from fitmatch.models import Offer

logger = logging.getLogger("fitmatch.scraper")


class BaseScraper(ABC):
    """Abstract base class for store scrapers."""

    store_id: str
    store_name: str
    base_url: str

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

    def fetch_sizes(self, product_url: str) -> List[str]:
        """Fetch available in-stock sizes from the product detail page."""
        return []

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
