import json
import os
import hashlib
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, List, Dict
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.scrapers.base import BaseScraper
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import SearchResult, Offer, MatchedProductGroup


class ComparisonService:
    """Core business service for searching and comparing athletic products with size awareness."""

    def __init__(self, cache_dir: Optional[str] = "data/cache", enable_cache: bool = True):
        self.registry = ScraperRegistry()
        self.normalizer = ProductNormalizer()
        self.cache_dir = cache_dir
        self.enable_cache = enable_cache
        self.scrapers_by_id: Dict[str, BaseScraper] = {s.store_id: s for s in self.registry.scrapers}

        if self.enable_cache and self.cache_dir:
            os.makedirs(self.cache_dir, exist_ok=True)

    def _get_cache_path(self, query: str, size: Optional[str] = None) -> str:
        key = f"{query.strip().lower()}_size_{size}" if size else query.strip().lower()
        q_hash = hashlib.md5(key.encode("utf-8")).hexdigest()
        return os.path.join(self.cache_dir, f"{q_hash}.json")

    def _enrich_sizes_for_offers(self, offers: List[Offer], max_workers: int = 8) -> None:
        """Concurrently fetch in-stock sizes for offers that don't have them yet."""
        offers_to_fetch = [o for o in offers if not o.available_sizes and o.store_id in self.scrapers_by_id]
        if not offers_to_fetch:
            return

        def fetch_for_offer(offer: Offer):
            scraper = self.scrapers_by_id.get(offer.store_id)
            if scraper:
                try:
                    sizes = scraper.fetch_sizes(offer.url)
                    if sizes:
                        offer.available_sizes = sizes
                except Exception:
                    pass

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            list(executor.map(fetch_for_offer, offers_to_fetch))

    def search_and_compare(
        self,
        query: str,
        size: Optional[str] = None,
        limit_per_store: int = 10,
        use_cache: bool = False
    ) -> SearchResult:
        """Search all stores, verify size stock, match products, and rank prices."""
        cache_path = self._get_cache_path(query, size) if self.enable_cache else None

        if use_cache and cache_path and os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    cached_data = json.load(f)
                    return SearchResult.model_validate(cached_data)
            except Exception:
                pass

        # 1. Scrape live stores
        scrape_res = self.registry.search_all(query, limit_per_store=limit_per_store)
        offers: List[Offer] = scrape_res["offers"]

        # 2. If a specific size was requested, enrich with sizes and filter
        if size:
            self._enrich_sizes_for_offers(offers)
            # Filter strictly by size
            offers = [o for o in offers if o.matches_size(size)]

        # 3. Deduplicate & group identical products across stores
        matched_groups = self.normalizer.group_offers(offers)

        result = SearchResult(
            query=f"{query} (Taglia {size})" if size else query,
            execution_time_seconds=scrape_res["execution_time_seconds"],
            stores_queried=[s.store_name for s in self.registry.scrapers],
            total_offers_found=len(offers),
            matched_products=matched_groups,
            raw_offers=offers
        )

        # 4. Save to cache
        if self.enable_cache and cache_path:
            try:
                with open(cache_path, "w", encoding="utf-8") as f:
                    f.write(result.model_dump_json(indent=2))
            except Exception:
                pass

        return result
