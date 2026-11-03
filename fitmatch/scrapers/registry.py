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
from fitmatch.scrapers.deporvillage import DeporvillageScraper
from fitmatch.scrapers.alltricks import AlltricksScraper
from fitmatch.scrapers.decathlon import DecathlonScraper
from fitmatch.scrapers.sportler import SportlerScraper
from fitmatch.scrapers.nike import NikeScraper
from fitmatch.scrapers.adidas import AdidasScraper
from fitmatch.scrapers.tradeinn import TradeinnScraper
from fitmatch.scrapers.df_sport import DFSportScraper
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
        DeporvillageScraper,
        AlltricksScraper,
        DecathlonScraper,
        SportlerScraper,
        NikeScraper,
        AdidasScraper,
        TradeinnScraper,
        DFSportScraper,
    ]

    def __init__(self, scrapers: List[BaseScraper] = None):
        if scrapers:
            self.scrapers = scrapers
        else:
            self.scrapers = [cls() for cls in self.DEFAULT_SCRAPERS]

    def search_all(self, query: str, limit_per_store: int = 10, max_workers: int = 11) -> Dict[str, Any]:
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

    def sync_stores_to_database(self, db) -> int:
        """Automatically registers/updates all scraper metadata in the database."""
        count = 0
        for scraper in self.scrapers:
            s_id = getattr(scraper, "store_id", "").lower().strip()
            if not s_id:
                continue
            name = getattr(scraper, "store_name", s_id.title())
            rating = getattr(scraper, "rating", 4.8)
            review_count = getattr(scraper, "review_count", 1200)

            # Auto-format review count (e.g. 4200 -> '4,2K')
            if getattr(scraper, "formatted_review_count", None):
                fmt_rev = scraper.formatted_review_count
            elif review_count >= 1000:
                fmt_rev = f"{review_count/1000:.1f}K".replace(".", ",")
            else:
                fmt_rev = str(review_count)

            store_data = {
                "id": s_id,
                "name": name,
                "rating": rating,
                "review_count": review_count,
                "formatted_review_count": fmt_rev,
                "card_theme": getattr(scraper, "card_theme", "white"),
                "accent_color": getattr(scraper, "accent_color", None),
                "base_url": getattr(scraper, "base_url", None),
                "free_shipping_threshold": getattr(scraper, "free_shipping_threshold", None),
                "standard_shipping_cost": getattr(scraper, "standard_shipping_cost", None),
                "courier": getattr(scraper, "courier", None),
            }
            if db.upsert_store(store_data):
                count += 1
        return count
