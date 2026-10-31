import time
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Type, Any
from fitmatch.scrapers.base import BaseScraper
from fitmatch.scrapers.cisalfa import CisalfaScraper
from fitmatch.scrapers.maxisport import MaxiSportScraper
from fitmatch.scrapers.misterrunning import MisterRunningScraper
from fitmatch.scrapers.nencini import NenciniSportScraper
from fitmatch.scrapers.top4running import Top4RunningScraper
from fitmatch.scrapers.runningwarehouse import RunningWarehouseScraper
from fitmatch.models import Offer

logger = logging.getLogger("fitmatch.registry")


class ScraperRegistry:
    """Manages available store scrapers and coordinates parallel catalog search."""

    DEFAULT_SCRAPERS: List[Type[BaseScraper]] = [
        CisalfaScraper,
        MaxiSportScraper,
        MisterRunningScraper,
        NenciniSportScraper,
        Top4RunningScraper,
        RunningWarehouseScraper,
    ]

    def __init__(self, scrapers: List[BaseScraper] = None):
        if scrapers:
            self.scrapers = scrapers
        else:
            self.scrapers = [cls() for cls in self.DEFAULT_SCRAPERS]

    def search_all(self, query: str, limit_per_store: int = 10, max_workers: int = 6) -> Dict[str, Any]:
        """Query all registered stores concurrently."""
        start_time = time.time()
        all_offers: List[Offer] = []
        store_results: Dict[str, int] = {}
        successful_stores: List[str] = []
        failed_stores: List[str] = []

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_scraper = {
                executor.submit(scraper.search, query, limit_per_store): scraper
                for scraper in self.scrapers
            }

            for future in as_completed(future_to_scraper):
                scraper = future_to_scraper[future]
                try:
                    offers = future.result()
                    all_offers.extend(offers)
                    store_results[scraper.store_name] = len(offers)
                    successful_stores.append(scraper.store_name)
                    logger.info(f"[{scraper.store_name}] Found {len(offers)} offers for '{query}'")
                except Exception as e:
                    logger.error(f"[{scraper.store_name}] Failed while searching for '{query}': {e}")
                    failed_stores.append(scraper.store_name)
                    store_results[scraper.store_name] = 0

        elapsed = round(time.time() - start_time, 2)

        return {
            "query": query,
            "offers": all_offers,
            "store_counts": store_results,
            "successful_stores": successful_stores,
            "failed_stores": failed_stores,
            "execution_time_seconds": elapsed,
        }
