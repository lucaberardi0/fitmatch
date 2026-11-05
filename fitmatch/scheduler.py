import time
import logging
import threading
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.updater import PriceUpdater

logger = logging.getLogger("fitmatch.scheduler")


class SyncScheduler:
    """
    Autonomous orchestration engine that runs periodic catalog discovery
    and continuous price/stock monitoring in the background.
    """

    _instance: Optional["SyncScheduler"] = None

    @classmethod
    def get_instance(cls, db: Optional[Database] = None) -> "SyncScheduler":
        if cls._instance is None:
            cls._instance = SyncScheduler(db=db)
        return cls._instance

    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()
        self.crawler = CategoryCrawler(db=self.db)
        self.updater = PriceUpdater(db=self.db)

        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

        # Configuration (in seconds)
        # Default: Price refresh every 2 hours (7200s), full catalog discovery every 24 hours (86400s)
        self.refresh_interval: int = 7200
        self.discovery_interval: int = 86400

        # State tracking
        self.is_running: bool = False
        self.current_task: str = "idle"  # "idle", "discovery", "refresh"
        self.total_cycles_completed: int = 0

        self.last_discovery_run: Optional[str] = None
        self.last_discovery_stats: Dict[str, Any] = {}
        self.next_discovery_run: Optional[str] = None

        self.last_refresh_run: Optional[str] = None
        self.last_refresh_stats: Dict[str, Any] = {}
        self.next_refresh_run: Optional[str] = None

        self._lock = threading.Lock()

    def start(
        self,
        refresh_interval_seconds: int = 7200,
        discovery_interval_seconds: int = 86400,
        run_immediately: bool = False
    ):
        """Start the autonomous background scheduler thread."""
        with self._lock:
            if self._thread and self._thread.is_alive():
                logger.info("[SyncScheduler] Already running.")
                return

            self.refresh_interval = refresh_interval_seconds
            self.discovery_interval = discovery_interval_seconds
            self._stop_event.clear()
            self.is_running = True

            self._thread = threading.Thread(
                target=self._worker_loop,
                args=(run_immediately,),
                daemon=True,
                name="FitMatch-Scheduler"
            )
            self._thread.start()
            logger.info(
                f"[SyncScheduler] Started. Refresh every {self.refresh_interval}s, "
                f"Discovery every {self.discovery_interval}s."
            )

    def stop(self):
        """Signal the scheduler thread to stop gracefully."""
        with self._lock:
            if not self.is_running:
                return
            logger.info("[SyncScheduler] Stopping background worker...")
            self._stop_event.set()
            self.is_running = False
            self.current_task = "idle"

    def _worker_loop(self, run_immediately: bool):
        """Main recurring worker loop."""
        now = time.time()
        last_refresh_time = now if not run_immediately else 0
        last_discovery_time = now if not run_immediately else 0

        # Schedule initial next run timestamps
        self.next_refresh_run = (datetime.now() + timedelta(seconds=self.refresh_interval if not run_immediately else 0)).strftime("%Y-%m-%d %H:%M:%S")
        self.next_discovery_run = (datetime.now() + timedelta(seconds=self.discovery_interval if not run_immediately else 0)).strftime("%Y-%m-%d %H:%M:%S")

        while not self._stop_event.is_set():
            current_time = time.time()

            # 1. Check if Full Catalog Discovery is due
            if current_time - last_discovery_time >= self.discovery_interval:
                self._run_discovery_task()
                last_discovery_time = time.time()
                self.next_discovery_run = (datetime.now() + timedelta(seconds=self.discovery_interval)).strftime("%Y-%m-%d %H:%M:%S")

            # 2. Check if Price & Stock Refresh is due
            elif current_time - last_refresh_time >= self.refresh_interval:
                self._run_refresh_task()
                last_refresh_time = time.time()
                self.next_refresh_run = (datetime.now() + timedelta(seconds=self.refresh_interval)).strftime("%Y-%m-%d %H:%M:%S")

            # Heartbeat sleep (1 second interval allows rapid stop response)
            for _ in range(5):
                if self._stop_event.is_set():
                    break
                time.sleep(1)

        logger.info("[SyncScheduler] Worker loop terminated.")

    def _run_discovery_task(self, limit_per_store: int = 300) -> Dict[str, Any]:
        """Execute full multi-store catalog crawl and index new products."""
        self.current_task = "discovery"
        logger.info("[SyncScheduler] Initiating automatic catalog discovery cycle...")
        start_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        try:
            res = self.crawler.run_full_sync(limit_per_store=limit_per_store)
            self.last_discovery_run = start_iso
            self.last_discovery_stats = {
                "timestamp": start_iso,
                "status": "success",
                "total_crawled": res.get("total_crawled", 0),
                "duration_seconds": res.get("duration_seconds", 0),
                "by_store": res.get("crawled_by_store", {})
            }
            self.total_cycles_completed += 1
            logger.info(
                f"[SyncScheduler] Catalog discovery completed: {res.get('total_crawled')} items "
                f"in {res.get('duration_seconds')}s."
            )
            return self.last_discovery_stats
        except Exception as e:
            logger.error(f"[SyncScheduler] Error during catalog discovery: {e}")
            self.last_discovery_stats = {
                "timestamp": start_iso,
                "status": "error",
                "error": str(e)
            }
            return self.last_discovery_stats
        finally:
            self.current_task = "idle"

    def _run_refresh_task(self, limit: int = 50) -> Dict[str, Any]:
        """Execute continuous price and stock refresh for indexed products."""
        self.current_task = "refresh"
        logger.info(f"[SyncScheduler] Initiating price refresh cycle for {limit} products...")
        start_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        try:
            res = self.updater.run_update_sync(limit=limit)
            self.last_refresh_run = start_iso
            self.last_refresh_stats = {
                "timestamp": start_iso,
                "status": res.get("status", "success"),
                "offers_checked": res.get("offers_checked", 0),
                "prices_updated": res.get("prices_updated", 0),
                "price_drops": res.get("price_drops", 0),
                "total_savings": res.get("total_savings", 0.0),
                "duration_seconds": res.get("duration_seconds", 0.0)
            }
            self.total_cycles_completed += 1
            logger.info(
                f"[SyncScheduler] Price refresh completed: {res.get('offers_checked')} offers checked, "
                f"{res.get('price_drops')} drops detected."
            )

            # Trigger server-side PriceDropWatcher to push APNs alerts to devices
            try:
                import asyncio
                from fitmatch.price_drop_watcher import PriceDropWatcher
                watcher = PriceDropWatcher()
                loop = asyncio.new_event_loop()
                watcher_stats = loop.run_until_complete(watcher.run_check())
                loop.close()
                self.last_refresh_stats["watcher"] = watcher_stats
                logger.info(f"[SyncScheduler] PriceDropWatcher completed: {watcher_stats}")
            except Exception as w_err:
                logger.warning(f"[SyncScheduler] PriceDropWatcher warning: {w_err}")

            return self.last_refresh_stats
        except Exception as e:
            logger.error(f"[SyncScheduler] Error during price refresh: {e}")
            self.last_refresh_stats = {
                "timestamp": start_iso,
                "status": "error",
                "error": str(e)
            }
            return self.last_refresh_stats
        finally:
            self.current_task = "idle"

    def trigger_discovery_now(self, limit_per_store: int = 200) -> Dict[str, Any]:
        """Trigger an immediate catalog discovery run in background or synchronously."""
        if self.current_task != "idle":
            return {"status": "busy", "message": f"Task already running: {self.current_task}"}

        self.current_task = "discovery"
        thread = threading.Thread(
            target=self._run_discovery_task,
            args=(limit_per_store,),
            daemon=True
        )
        thread.start()
        return {
            "status": "started",
            "message": f"Avvio scraping e scoperta catalogo in background (target: {limit_per_store} per negozio)."
        }

    def trigger_refresh_now(self, limit: int = 50) -> Dict[str, Any]:
        """Trigger an immediate price refresh run in background."""
        if self.current_task != "idle":
            return {"status": "busy", "message": f"Task already running: {self.current_task}"}

        self.current_task = "refresh"
        thread = threading.Thread(
            target=self._run_refresh_task,
            args=(limit,),
            daemon=True
        )
        thread.start()
        return {
            "status": "started",
            "message": f"Avvio verifica prezzi in background per {limit} prodotti."
        }

    def get_status(self) -> Dict[str, Any]:
        """Return full telemetry and status of the automated sync engine."""
        return {
            "is_running": self.is_running,
            "current_task": self.current_task,
            "total_cycles_completed": self.total_cycles_completed,
            "discovery": {
                "interval_seconds": self.discovery_interval,
                "interval_hours": round(self.discovery_interval / 3600, 1),
                "last_run": self.last_discovery_run,
                "next_run": self.next_discovery_run,
                "last_stats": self.last_discovery_stats
            },
            "refresh": {
                "interval_seconds": self.refresh_interval,
                "interval_hours": round(self.refresh_interval / 3600, 1),
                "last_run": self.last_refresh_run,
                "next_run": self.next_refresh_run,
                "last_stats": self.last_refresh_stats
            }
        }
