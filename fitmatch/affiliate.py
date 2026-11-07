"""
FitMatch Affiliate Marketing & Outbound Redirect Engine.
Supports Sovrn //Commerce (VigLink) programmatic link wrapping, CUID tracking,
click logging, and fallback routing for e-commerce partner stores.
"""

import hashlib
import logging
import os
import re
import urllib.parse
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("fitmatch.affiliate")


class AffiliateManager:
    """Manages outbound link monetization, UTM injection, and click attribution."""

    def __init__(self, sovrn_api_key: Optional[str] = None):
        if sovrn_api_key is not None:
            self._sovrn_api_key = sovrn_api_key.strip()
        else:
            self._sovrn_api_key = os.getenv("SOVRN_API_KEY", "").strip()
        self.sovrn_base_url = "https://redirect.viglink.com"

    @property
    def sovrn_api_key(self) -> str:
        if self._sovrn_api_key is not None:
            return self._sovrn_api_key
        return os.getenv("SOVRN_API_KEY", "").strip()

    @sovrn_api_key.setter
    def sovrn_api_key(self, value: str):
        self._sovrn_api_key = value.strip() if value is not None else ""

    def reload_key(self):
        """Reload key from environment if updated at runtime."""
        self._sovrn_api_key = os.getenv("SOVRN_API_KEY", "").strip()

    def generate_cuid(
        self,
        store_id: Optional[str] = None,
        offer_id: Optional[str] = None,
        device_id: Optional[str] = None,
    ) -> str:
        """
        Generate a compact CUID (Custom User/Click ID) for Sovrn reporting.
        Max 32 alphanumeric characters.
        Format: fm_<clean_store>_<8char_hash>
        """
        store_part = (store_id or "gen").lower()
        store_part = re.sub(r"[^a-z0-9]", "", store_part)[:10]

        seed = f"{store_id}:{offer_id}:{device_id}:{uuid.uuid4().hex}"
        unique_hash = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:12]

        cuid = f"fm_{store_part}_{unique_hash}"
        # Ensure max 32 characters
        return cuid[:32]

    def build_monetized_url(
        self,
        target_url: str,
        store_id: Optional[str] = None,
        offer_id: Optional[str] = None,
        device_id: Optional[str] = None,
        cuid: Optional[str] = None,
    ) -> str:
        """
        Wrap a raw store URL with Sovrn Commerce affiliate redirect parameters.
        If no Sovrn key is configured, safely returns the clean target URL.
        """
        if not target_url:
            return ""

        clean_url = target_url.strip()
        key = self.sovrn_api_key

        # If no affiliate key is present, fallback directly to merchant URL
        if not key:
            return clean_url

        # Generate CUID for tracking attribution if not provided
        tracking_cuid = cuid or self.generate_cuid(store_id=store_id, offer_id=offer_id, device_id=device_id)

        # Build Sovrn VigLink redirect URL
        params = {
            "key": key,
            "u": clean_url,
            "cuid": tracking_cuid,
        }

        # Encode parameters
        return f"{self.sovrn_base_url}?{urllib.parse.urlencode(params)}"


# Global singleton instance
affiliate_manager = AffiliateManager()
