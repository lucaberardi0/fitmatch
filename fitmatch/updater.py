import time
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, Any, List, Optional
from datetime import datetime
from fitmatch.db import Database
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.matcher.normalizer import ProductNormalizer

logger = logging.getLogger("fitmatch.updater")


class PriceUpdater:
    """Automated price monitor and background sync engine for store offers."""

    _instance: Optional["PriceUpdater"] = None

    @classmethod
    def get_instance(cls, db: Optional[Database] = None) -> "PriceUpdater":
        if cls._instance is None:
            cls._instance = PriceUpdater(db=db)
        return cls._instance

    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()
        self.registry = ScraperRegistry()
        self.normalizer = ProductNormalizer()
        self.is_running = False
        self.last_run: Optional[str] = None
        self.last_stats: Dict[str, Any] = {
            "offers_checked": 0,
            "prices_updated": 0,
            "price_drops": 0,
            "total_savings": 0.0,
            "duration_seconds": 0.0,
            "timestamp": None,
            "priority_tiers": {},
        }
        self._scheduler_thread: Optional[threading.Thread] = None
        self._stop_scheduler = threading.Event()

    def _refresh_single_product(self, row: Dict[str, Any], search_timeout: float = 14.0) -> Dict[str, Any]:
        """Refresh prices for one product across partner stores with bounded wall-clock timeout."""
        query = (row.get("canonical_name") or "").strip()
        prod_id = row.get("id")
        tier = row.get("priority_tier") or "catalog_oldest"
        if not query:
            return {"checked": 0, "updated": 0, "drops": 0, "savings": 0.0, "tier": tier}

        updated = 0
        drops = 0
        savings = 0.0
        try:
            res = self.registry.search_all(
                query=query,
                limit_per_store=2,
                max_workers=12,
                timeout=search_timeout,
            )
            offers = res.get("offers", [])

            for offer in offers:
                try:
                    off_cat = self.normalizer.detect_article_type(offer.title, url=offer.url)
                    if off_cat == "non_sport":
                        continue
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    off_brand = self.normalizer.extract_brand(offer.title, offer.brand, url=offer.url)
                    off_gender = self.normalizer.extract_gender(offer.title, offer.url)
                    off_canonical = self.normalizer.build_canonical_display_name(offer.title, off_brand)

                    offer_id = f"{offer.store_id}:{offer.product_id or offer.url}"
                    old_price = self.db.get_offer_price(offer_id)

                    if old_price is not None and abs(old_price - offer.price) > 0.01:
                        updated += 1
                        if offer.price < old_price:
                            drops += 1
                            savings += (old_price - offer.price)

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=off_canonical or query,
                        brand=off_brand,
                        category=off_cat,
                        gender=off_gender,
                        offer=offer,
                    )
                except Exception as e:
                    logger.debug(f"[PriceUpdater] Upsert error for offer: {e}")
        except Exception as e:
            logger.error(f"[PriceUpdater] Search error on query '{query}': {e}")
        finally:
            if prod_id:
                try:
                    self.db.touch_product_updated(prod_id)
                except Exception:
                    pass

        return {
            "checked": 1,
            "updated": updated,
            "drops": drops,
            "savings": savings,
            "tier": tier,
        }

    def run_update_sync(
        self,
        limit: int = 30,
        priority_deals: bool = True,
        stale_hours: int = 24,
        max_workers: int = 3,
    ) -> Dict[str, Any]:
        """Check prices of prioritized indexed products (wishlist -> visible deals -> oldest) and update price history."""
        if self.is_running:
            return {"status": "busy", "message": "Aggiornamento prezzi già in corso."}

        self.is_running = True
        start_time = time.time()
        checked = 0
        updated = 0
        drops = 0
        total_savings = 0.0
        tier_counts: Dict[str, int] = {}

        try:
            rows = self.db.get_products_for_update(
                limit=limit,
                priority_deals=priority_deals,
                stale_hours=stale_hours,
            )
            logger.info(
                f"[PriceUpdater] Loaded {len(rows)} products to refresh "
                f"(priority_deals={priority_deals}, stale_hours={stale_hours})."
            )

            worker_count = max(1, min(max_workers, len(rows) or 1))
            if worker_count == 1:
                for row in rows:
                    stat = self._refresh_single_product(row)
                    checked += stat["checked"]
                    updated += stat["updated"]
                    drops += stat["drops"]
                    total_savings += stat["savings"]
                    t = stat["tier"]
                    tier_counts[t] = tier_counts.get(t, 0) + stat["checked"]
            else:
                with ThreadPoolExecutor(max_workers=worker_count) as pool:
                    futures = [pool.submit(self._refresh_single_product, row) for row in rows]
                    for fut in as_completed(futures):
                        try:
                            stat = fut.result()
                            checked += stat["checked"]
                            updated += stat["updated"]
                            drops += stat["drops"]
                            total_savings += stat["savings"]
                            t = stat["tier"]
                            tier_counts[t] = tier_counts.get(t, 0) + stat["checked"]
                        except Exception as e:
                            logger.debug(f"[PriceUpdater] Worker error: {e}")

            elapsed = round(time.time() - start_time, 2)
            now_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            self.last_run = now_iso
            self.last_stats = {
                "offers_checked": checked,
                "prices_updated": updated,
                "price_drops": drops,
                "total_savings": round(total_savings, 2),
                "duration_seconds": elapsed,
                "timestamp": now_iso,
                "priority_tiers": tier_counts,
            }

            return {
                "status": "success",
                "message": f"Aggiornamento completato: {checked} prodotti verificati, {drops} cali di prezzo rilevati.",
                **self.last_stats,
            }
        finally:
            self.is_running = False

    def get_status(self) -> Dict[str, Any]:
        """Return real-time status of the price monitor."""
        return {
            "is_running": self.is_running,
            "last_run": self.last_run,
            "last_stats": self.last_stats,
            "scheduler_active": self._scheduler_thread is not None and self._scheduler_thread.is_alive(),
        }

    def start_scheduler(self, interval_seconds: int = 14400):
        """Start recurring background sync daemon."""
        if self._scheduler_thread and self._scheduler_thread.is_alive():
            return

        self._stop_scheduler.clear()

        def _loop():
            logger.info(f"[PriceUpdater] Periodic scheduler started (interval: {interval_seconds}s).")
            while not self._stop_scheduler.is_set():
                for _ in range(int(interval_seconds)):
                    if self._stop_scheduler.is_set():
                        break
                    time.sleep(1)

                if not self._stop_scheduler.is_set():
                    logger.info("[PriceUpdater] Running scheduled periodic priority price refresh...")
                    self.run_update_sync(limit=35, priority_deals=True)

        self._scheduler_thread = threading.Thread(target=_loop, daemon=True)
        self._scheduler_thread.start()

    def stop_scheduler(self):
        """Stop recurring background sync daemon."""
        self._stop_scheduler.set()
