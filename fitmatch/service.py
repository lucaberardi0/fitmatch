import json
import os
import hashlib
from typing import Optional, List
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import SearchResult, Offer, MatchedProductGroup


class ComparisonService:
    """Core business service for searching and comparing athletic products."""

    def __init__(self, cache_dir: Optional[str] = "data/cache", enable_cache: bool = True):
        self.registry = ScraperRegistry()
        self.normalizer = ProductNormalizer()
        self.cache_dir = cache_dir
        self.enable_cache = enable_cache

        if self.enable_cache and self.cache_dir:
            os.makedirs(self.cache_dir, exist_ok=True)

    def _get_cache_path(self, query: str) -> str:
        q_hash = hashlib.md5(query.strip().lower().encode("utf-8")).hexdigest()
        return os.path.join(self.cache_dir, f"{q_hash}.json")

    def search_and_compare(
        self,
        query: str,
        limit_per_store: int = 10,
        use_cache: bool = False
    ) -> SearchResult:
        """Search all stores, match products, and rank prices."""
        cache_path = self._get_cache_path(query) if self.enable_cache else None

        if use_cache and cache_path and os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    cached_data = json.load(f)
                    return SearchResult.model_validate(cached_data)
            except Exception:
                pass

        # Perform live scraping
        scrape_res = self.registry.search_all(query, limit_per_store=limit_per_store)
        offers: List[Offer] = scrape_res["offers"]

        # Deduplicate & group identical products across stores
        matched_groups = self.normalizer.group_offers(offers)

        result = SearchResult(
            query=query,
            execution_time_seconds=scrape_res["execution_time_seconds"],
            stores_queried=self.registry.DEFAULT_SCRAPERS and [s.store_name for s in self.registry.scrapers],
            total_offers_found=len(offers),
            matched_products=matched_groups,
            raw_offers=offers
        )

        # Save to cache if enabled
        if self.enable_cache and cache_path:
            try:
                with open(cache_path, "w", encoding="utf-8") as f:
                    f.write(result.model_dump_json(indent=2))
            except Exception:
                pass

        return result
