import os
import json
import logging
import ssl
import certifi
import urllib.request
from typing import List, Dict, Any, Optional

logger = logging.getLogger("fitmatch.supabase")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://goopfdvnqhdmsoutkldp.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdvb3BmZHZucWhkbXNvdXRrbGRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MzA3MzIsImV4cCI6MjEwOTEwNjczMn0.iXpBGsAORT0-1oFtQh-PAmgfwkGRVTyekalZoS2_Zyo")


class SupabaseClient:
    """Production client for synchronizing FitMatch data to Supabase PostgreSQL."""

    def __init__(self, base_url: str = SUPABASE_URL, api_key: str = SUPABASE_KEY):
        self.base_url = f"{base_url.rstrip('/')}/rest/v1"
        self.api_key = api_key
        try:
            self.ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            self.ctx = ssl.create_default_context()

    def _get_headers(self, upsert: bool = False) -> Dict[str, str]:
        headers = {
            "apikey": self.api_key,
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        if upsert:
            headers["Prefer"] = "resolution=merge-duplicates"
        return headers

    def upsert_products(self, products: List[Dict[str, Any]]) -> bool:
        """Upsert a batch of canonical products."""
        if not products:
            return True
        url = f"{self.base_url}/products"
        data = json.dumps(products).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=self._get_headers(upsert=True), method="POST")
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=15) as resp:
                return resp.status in (200, 201)
        except Exception as e:
            logger.error(f"Error upserting products to Supabase: {e}")
            return False

    def upsert_offers(self, offers: List[Dict[str, Any]]) -> bool:
        """Upsert a batch of store offers."""
        if not offers:
            return True
        url = f"{self.base_url}/store_offers"
        data = json.dumps(offers).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=self._get_headers(upsert=True), method="POST")
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=15) as resp:
                return resp.status in (200, 201)
        except Exception as e:
            logger.error(f"Error upserting offers to Supabase: {e}")
            return False

    def get_wishlists(self, collection_name: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieve wishlist items from Supabase."""
        url = f"{self.base_url}/wishlists"
        if collection_name and collection_name.lower() != "tutti":
            url += f"?collection_name=eq.{urllib.parse.quote(collection_name)}"
        req = urllib.request.Request(url, headers=self._get_headers())
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            logger.error(f"Error fetching wishlists from Supabase: {e}")
            return []
