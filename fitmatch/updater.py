import time
import logging
import threading
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
    def get_instance(cls) -> "PriceUpdater":
        if cls._instance is None:
            cls._instance = PriceUpdater()
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
            "timestamp": None
        }
        self._scheduler_thread: Optional[threading.Thread] = None
        self._stop_scheduler = threading.Event()

    def run_update_sync(self, limit: int = 30) -> Dict[str, Any]:
        """Check prices of currently indexed products and update price history."""
        if self.is_running:
            return {"status": "busy", "message": "Aggiornamento prezzi già in corso."}

        self.is_running = True
        start_time = time.time()
        checked = 0
        updated = 0
        drops = 0
        total_savings = 0.0

        try:
            with self.db.get_connection() as conn:
                # Select distinct active products that have store offers
                rows = conn.execute("""
                    SELECT DISTINCT p.id, p.canonical_name, p.brand
                    FROM products p
                    JOIN store_offers o ON p.id = o.product_id
                    ORDER BY p.updated_at ASC
                    LIMIT ?
                """, (limit,)).fetchall()

            for row in rows:
                query = row["canonical_name"]
                checked += 1
                try:
                    # Query registry across all stores for this product
                    res = self.registry.search_all(query=query, limit_per_store=2)
                    offers = res.get("offers", [])

                    for offer in offers:
                        try:
                            cluster_key = self.normalizer.extract_cluster_key(offer)
                            offer_id = f"{offer.store_id}:{offer.product_id or abs(hash(offer.url))}"

                            # Check existing price to detect drop
                            with self.db.get_connection() as conn:
                                prev = conn.execute(
                                    "SELECT current_price FROM store_offers WHERE id = ?",
                                    (offer_id,)
                                ).fetchone()

                            if prev:
                                old_price = float(prev["current_price"])
                                if abs(old_price - offer.price) > 0.01:
                                    updated += 1
                                    if offer.price < old_price:
                                        drops += 1
                                        total_savings += (old_price - offer.price)

                            # Upsert offer & record price_history point
                            self.db.upsert_product_and_offer(
                                cluster_key=cluster_key,
                                canonical_name=query,
                                brand=row["brand"],
                                category=None,
                                gender=None,
                                offer=offer
                            )
                        except Exception as e:
                            logger.debug(f"[PriceUpdater] Upsert error for offer: {e}")
                except Exception as e:
                    logger.error(f"[PriceUpdater] Search error on query '{query}': {e}")

            elapsed = round(time.time() - start_time, 2)
            now_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            self.last_run = now_iso
            self.last_stats = {
                "offers_checked": checked,
                "prices_updated": updated,
                "price_drops": drops,
                "total_savings": round(total_savings, 2),
                "duration_seconds": elapsed,
                "timestamp": now_iso
            }

            return {
                "status": "success",
                "message": f"Aggiornamento completato: {checked} prodotti verificati, {drops} cali di prezzo rilevati.",
                **self.last_stats
            }
        finally:
            self.is_running = False

    def get_status(self) -> Dict[str, Any]:
        """Return real-time status of the price monitor."""
        return {
            "is_running": self.is_running,
            "last_run": self.last_run,
            "last_stats": self.last_stats,
            "scheduler_active": self._scheduler_thread is not None and self._scheduler_thread.is_alive()
        }

    def start_scheduler(self, interval_seconds: int = 14400):
        """Start recurring background sync daemon."""
        if self._scheduler_thread and self._scheduler_thread.is_alive():
            return

        self._stop_scheduler.clear()

        def _loop():
            logger.info(f"[PriceUpdater] Periodic scheduler started (interval: {interval_seconds}s).")
            while not self._stop_scheduler.is_set():
                # Wait interval with quick exit check
                for _ in range(int(interval_seconds)):
                    if self._stop_scheduler.is_set():
                        break
                    time.sleep(1)

                if not self._stop_scheduler.is_set():
                    logger.info("[PriceUpdater] Running scheduled periodic price refresh...")
                    self.run_update_sync(limit=25)

        self._scheduler_thread = threading.Thread(target=_loop, daemon=True)
        self._scheduler_thread.start()

    def stop_scheduler(self):
        """Stop recurring background sync daemon."""
        self._stop_scheduler.set()
