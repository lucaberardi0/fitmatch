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
                if self.current_task == "idle" and not self.updater.is_running:
                    self._run_discovery_task()
                    last_discovery_time = time.time()
                    self.next_discovery_run = (datetime.now() + timedelta(seconds=self.discovery_interval)).strftime("%Y-%m-%d %H:%M:%S")
                else:
                    logger.info(f"[SyncScheduler] Discovery cycle deferred: current_task={self.current_task}, updater_busy={self.updater.is_running}")

            # 2. Check if Price & Stock Refresh is due
            elif current_time - last_refresh_time >= self.refresh_interval:
                if self.current_task == "idle" and not self.updater.is_running:
                    self._run_refresh_task()
                    last_refresh_time = time.time()
                    self.next_refresh_run = (datetime.now() + timedelta(seconds=self.refresh_interval)).strftime("%Y-%m-%d %H:%M:%S")
                else:
                    logger.info(f"[SyncScheduler] Scheduled refresh deferred: current_task={self.current_task}, updater_busy={self.updater.is_running}")

            # Heartbeat sleep (1 second interval allows rapid stop response)
            for _ in range(5):
                if self._stop_event.is_set():
                    break
                time.sleep(1)

        logger.info("[SyncScheduler] Worker loop terminated.")

    def _run_discovery_task(self, limit_per_store: int = 300, trigger_source: str = "scheduler") -> Dict[str, Any]:
        """Execute full multi-store catalog crawl and index new products with persistent session tracking."""
        if self.updater.is_running:
            logger.warning("[SyncScheduler] Price updater is running. Deferring discovery cycle.")
            return {"status": "busy", "message": "Price updater already running."}

        self.current_task = "discovery"
        logger.info("[SyncScheduler] Initiating automatic catalog discovery cycle...")
        start_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        start_time = time.time()

        # 1. Create persistent sync session in database
        session_id = self.db.create_sync_session(
            session_type="discovery",
            trigger_source=trigger_source,
            metadata={"limit_per_store": limit_per_store}
        )
        logger.info(f"[SyncScheduler] Created discovery session {session_id}")

        try:
            # 2. Run crawler with session_id link
            res = self.crawler.run_full_sync(limit_per_store=limit_per_store, session_id=session_id)
            total_crawled = res.get("total_crawled", 0)
            duration_crawling = res.get("duration_seconds", 0)
            by_store = res.get("crawled_by_store", {})

            # 3. Automated post-discovery reconciliation & entity re-clustering
            recluster_res = None
            try:
                recluster_res = self.run_reclustering_task()
            except Exception as rc_err:
                logger.warning(f"[SyncScheduler] Post-discovery recluster warning: {rc_err}")

            # 4. Automated size enrichment for newly indexed products
            enrichment_stats = None
            try:
                enrichment_stats = self.run_size_enrichment_task(limit_per_store=50, standalone=False)
            except Exception as en_err:
                logger.warning(f"[SyncScheduler] Post-discovery size enrichment warning: {en_err}")

            # 5. Automated vector embedding for newly discovered products
            embedding_stats = None
            try:
                embedding_stats = self.run_embedding_task(batch_size=50, limit=None, standalone=False)
            except Exception as emb_err:
                logger.warning(f"[SyncScheduler] Post-discovery vector embedding warning: {emb_err}")

            total_duration = round(time.time() - start_time, 2)

            # 5. Complete persistent session
            self.db.update_sync_session(
                session_id=session_id,
                status="completed",
                duration_seconds=total_duration,
                total_items_processed=total_crawled,
                total_items_updated=total_crawled,
                store_stats=by_store,
                metadata={
                    "recluster": recluster_res,
                    "enrichment": enrichment_stats,
                    "limit_per_store": limit_per_store
                }
            )

            self.last_discovery_run = start_iso
            self.last_discovery_stats = {
                "session_id": session_id,
                "timestamp": start_iso,
                "status": "success",
                "total_crawled": total_crawled,
                "duration_seconds": total_duration,
                "by_store": by_store
            }
            self.total_cycles_completed += 1
            logger.info(
                f"[SyncScheduler] Catalog discovery completed (Session {session_id}): {total_crawled} items "
                f"in {total_duration}s."
            )
            return self.last_discovery_stats

        except Exception as e:
            elapsed = round(time.time() - start_time, 2)
            logger.error(f"[SyncScheduler] Error during catalog discovery session {session_id}: {e}")
            self.db.update_sync_session(
                session_id=session_id,
                status="failed",
                duration_seconds=elapsed,
                error_message=str(e)
            )
            self.last_discovery_stats = {
                "session_id": session_id,
                "timestamp": start_iso,
                "status": "error",
                "error": str(e)
            }
            return self.last_discovery_stats
        finally:
            if self.current_task == "discovery":
                self.current_task = "idle"

    def _run_refresh_task(self, limit: int = 50, trigger_source: str = "scheduler") -> Dict[str, Any]:
        """Execute continuous price and stock refresh for indexed products with persistent session tracking."""
        if self.updater.is_running:
            logger.warning("[SyncScheduler] Price updater is already active. Skipping duplicate refresh task to prevent collision.")
            return {"status": "busy", "message": "Aggiornamento prezzi già in corso."}

        self.current_task = "refresh"
        logger.info(f"[SyncScheduler] Initiating price refresh cycle for {limit} products...")
        start_iso = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        start_time = time.time()

        # 1. Create persistent sync session in database
        session_id = self.db.create_sync_session(
            session_type="price_refresh",
            trigger_source=trigger_source,
            metadata={"limit": limit}
        )
        logger.info(f"[SyncScheduler] Created price_refresh session {session_id}")

        try:
            res = self.updater.run_update_sync(limit=limit)
            res_status = res.get("status", "success")

            if res_status == "busy":
                logger.warning(f"[SyncScheduler] Updater busy reported; deleting duplicate phantom session {session_id}")
                self.db.delete_sync_session(session_id)
                return {"status": "busy", "message": "Aggiornamento prezzi già in corso."}

            offers_checked = res.get("offers_checked", 0)
            prices_updated = res.get("prices_updated", 0)
            price_drops = res.get("price_drops", 0)
            total_savings = res.get("total_savings", 0.0)

            # Trigger server-side PriceDropWatcher to push APNs alerts to devices
            watcher_stats = None
            try:
                import asyncio
                from fitmatch.price_drop_watcher import PriceDropWatcher
                watcher = PriceDropWatcher()
                loop = asyncio.new_event_loop()
                watcher_stats = loop.run_until_complete(watcher.run_check())
                loop.close()
                logger.info(f"[SyncScheduler] PriceDropWatcher completed: {watcher_stats}")
            except Exception as w_err:
                logger.warning(f"[SyncScheduler] PriceDropWatcher warning: {w_err}")

            total_duration = round(time.time() - start_time, 2)

            # Complete persistent session
            self.db.update_sync_session(
                session_id=session_id,
                status="completed" if res_status == "success" else "failed",
                duration_seconds=total_duration,
                total_items_processed=offers_checked,
                total_items_updated=prices_updated,
                total_price_drops=price_drops,
                store_stats={"total_savings": total_savings},
                error_message=None if res_status == "success" else res.get("message", "Aggiornamento prezzi fallito"),
                metadata={"watcher": watcher_stats, "limit": limit}
            )

            self.last_refresh_run = start_iso
            self.last_refresh_stats = {
                "session_id": session_id,
                "timestamp": start_iso,
                "status": res_status,
                "offers_checked": offers_checked,
                "prices_updated": prices_updated,
                "price_drops": price_drops,
                "total_savings": total_savings,
                "duration_seconds": total_duration,
                "watcher": watcher_stats
            }
            self.total_cycles_completed += 1
            logger.info(
                f"[SyncScheduler] Price refresh completed (Session {session_id}): {offers_checked} offers checked, "
                f"{price_drops} drops detected."
            )
            return self.last_refresh_stats

        except Exception as e:
            elapsed = round(time.time() - start_time, 2)
            logger.error(f"[SyncScheduler] Error during price refresh session {session_id}: {e}")
            self.db.update_sync_session(
                session_id=session_id,
                status="failed",
                duration_seconds=elapsed,
                error_message=str(e)
            )
            self.last_refresh_stats = {
                "session_id": session_id,
                "timestamp": start_iso,
                "status": "error",
                "error": str(e)
            }
            return self.last_refresh_stats
        finally:
            if self.current_task == "refresh":
                self.current_task = "idle"

    def run_size_enrichment_task(
        self,
        limit_per_store: int = 50,
        standalone: bool = True,
        trigger_source: str = "scheduler"
    ) -> Dict[str, Any]:
        """Runs size enrichment on store offers missing sizes."""
        session_id = None
        if standalone:
            session_id = self.db.create_sync_session(
                session_type="size_enrichment",
                trigger_source=trigger_source,
                metadata={"limit_per_store": limit_per_store}
            )
            logger.info(f"[SyncScheduler] Created size_enrichment session {session_id}")

        start_time = time.time()
        try:
            from scripts.enrich_database_sizes import run_enrichment_batch
            counts = run_enrichment_batch(limit_per_store=limit_per_store, max_workers=5)
            total_enriched = sum(counts.values())
            elapsed = round(time.time() - start_time, 2)

            if standalone and session_id:
                self.db.update_sync_session(
                    session_id=session_id,
                    status="completed",
                    duration_seconds=elapsed,
                    total_items_processed=total_enriched,
                    total_items_updated=total_enriched,
                    store_stats=counts
                )

            return {
                "status": "success",
                "total_enriched": total_enriched,
                "by_store": counts,
                "duration_seconds": elapsed
            }
        except Exception as e:
            elapsed = round(time.time() - start_time, 2)
            logger.error(f"[SyncScheduler] Size enrichment task error: {e}")
            if standalone and session_id:
                self.db.update_sync_session(
                    session_id=session_id,
                    status="failed",
                    duration_seconds=elapsed,
                    error_message=str(e)
                )
            return {"status": "error", "error": str(e)}

    def run_embedding_task(
        self,
        batch_size: int = 25,
        limit: Optional[int] = None,
        standalone: bool = True,
        trigger_source: str = "scheduler",
        category: Optional[str] = None,
        stop_event: Any = None,
        progress_callback: Any = None,
    ) -> Dict[str, Any]:
        """Automatically generates vector embeddings for products with active offers missing embeddings."""
        session_id = None
        if standalone:
            session_id = self.db.create_sync_session(
                session_type="embedding_sync",
                trigger_source=trigger_source,
                metadata={"batch_size": batch_size, "limit": limit, "category": category or "all"}
            )
            logger.info(f"[SyncScheduler] Created embedding_sync session {session_id}")

        start_time = time.time()
        try:
            from scripts.generate_embeddings import EmbeddingGenerator
            generator = EmbeddingGenerator()
            result = generator.run(
                batch_size=batch_size,
                limit=limit,
                active_only=True,
                category=category,
                stop_event=stop_event,
                progress_callback=progress_callback,
            )
            elapsed = round(time.time() - start_time, 2)
            processed = int(result.get("processed", 0)) if isinstance(result, dict) else 0
            err_msg = result.get("error") if isinstance(result, dict) else None
            stopped = bool(result.get("stopped")) if isinstance(result, dict) else False
            if standalone and session_id:
                self.db.update_sync_session(
                    session_id=session_id,
                    status="completed" if not err_msg else "failed",
                    duration_seconds=elapsed,
                    total_items_processed=processed,
                    total_items_updated=processed,
                    error_message=err_msg,
                )
            return {
                "status": "error" if err_msg else ("stopped" if stopped else "success"),
                "processed": processed,
                "duration_seconds": elapsed,
                "error": err_msg,
            }
        except Exception as e:
            elapsed = round(time.time() - start_time, 2)
            logger.error(f"[SyncScheduler] Embedding task error: {e}")
            if standalone and session_id:
                self.db.update_sync_session(
                    session_id=session_id,
                    status="failed",
                    duration_seconds=elapsed,
                    error_message=str(e)
                )
            return {"status": "error", "error": str(e)}

    def trigger_discovery_now(self, limit_per_store: int = 200, trigger_source: str = "manual_api") -> Dict[str, Any]:
        """Trigger an immediate catalog discovery run in background."""
        if self.current_task != "idle" or self.updater.is_running:
            return {"status": "busy", "message": f"Task already running: {self.current_task} (updater_running={self.updater.is_running})"}

        self.current_task = "discovery"
        thread = threading.Thread(
            target=self._run_discovery_task,
            args=(limit_per_store, trigger_source),
            daemon=True
        )
        thread.start()
        return {
            "status": "started",
            "message": f"Avvio scraping e scoperta catalogo in background (target: {limit_per_store} per negozio)."
        }

    def trigger_refresh_now(self, limit: int = 50, trigger_source: str = "manual_api") -> Dict[str, Any]:
        """Trigger an immediate price refresh run in background."""
        if self.current_task != "idle" or self.updater.is_running:
            return {"status": "busy", "message": f"Task already running: {self.current_task} (updater_running={self.updater.is_running})"}

        self.current_task = "refresh"
        thread = threading.Thread(
            target=self._run_refresh_task,
            args=(limit, trigger_source),
            daemon=True
        )
        thread.start()
        return {
            "status": "started",
            "message": f"Avvio verifica prezzi in background per {limit} prodotti."
        }

    def trigger_enrichment_now(self, limit_per_store: int = 50, trigger_source: str = "manual_api") -> Dict[str, Any]:
        """Trigger an immediate size enrichment run in background."""
        if self.current_task != "idle" or self.updater.is_running:
            return {"status": "busy", "message": f"Task already running: {self.current_task} (updater_running={self.updater.is_running})"}

        self.current_task = "size_enrichment"
        thread = threading.Thread(
            target=self.run_size_enrichment_task,
            args=(limit_per_store, True, trigger_source),
            daemon=True
        )
        thread.start()
        return {
            "status": "started",
            "message": f"Avvio arricchimento taglie in background (target: {limit_per_store} per negozio)."
        }

    def run_reclustering_task(self) -> Dict[str, Any]:
        """Runs the ProductNormalizer entity resolution and re-clustering engine across all offers."""
        logger.info("[SyncScheduler] Starting automated catalog re-clustering...")
        try:
            from scripts.recluster_database import analyze_and_recluster
            analyze_and_recluster(execute=True)
            logger.info("[SyncScheduler] Catalog re-clustering finished successfully.")
            return {"status": "success", "message": "Catalog re-clustering completed successfully."}
        except Exception as e:
            logger.error(f"[SyncScheduler] Re-clustering error: {e}")
            return {"status": "error", "error": str(e)}

    def get_status(self) -> Dict[str, Any]:
        """Return full telemetry and status of the automated sync engine with persistent DB history."""
        # Fallback to database for last runs if freshly booted
        discovery_last_run = self.last_discovery_run
        discovery_stats = self.last_discovery_stats
        if not discovery_last_run:
            latest_disc = self.db.get_latest_sync_session("discovery")
            if latest_disc:
                discovery_last_run = latest_disc.get("completed_at") or latest_disc.get("started_at")
                discovery_stats = {
                    "session_id": latest_disc.get("id"),
                    "timestamp": discovery_last_run,
                    "status": latest_disc.get("status"),
                    "total_crawled": latest_disc.get("total_items_processed", 0),
                    "duration_seconds": float(latest_disc.get("duration_seconds", 0)),
                    "by_store": latest_disc.get("store_stats", {})
                }

        refresh_last_run = self.last_refresh_run
        refresh_stats = self.last_refresh_stats
        if not refresh_last_run:
            latest_ref = self.db.get_latest_sync_session("price_refresh")
            if latest_ref:
                refresh_last_run = latest_ref.get("completed_at") or latest_ref.get("started_at")
                refresh_stats = {
                    "session_id": latest_ref.get("id"),
                    "timestamp": refresh_last_run,
                    "status": latest_ref.get("status"),
                    "offers_checked": latest_ref.get("total_items_processed", 0),
                    "prices_updated": latest_ref.get("total_items_updated", 0),
                    "price_drops": latest_ref.get("total_price_drops", 0),
                    "duration_seconds": float(latest_ref.get("duration_seconds", 0))
                }

        recent_sessions = []
        try:
            recent_sessions = self.db.get_sync_sessions(limit=5)
        except Exception as e:
            logger.warning(f"[SyncScheduler] Could not load recent sessions: {e}")

        return {
            "is_running": self.is_running,
            "current_task": self.current_task,
            "total_cycles_completed": self.total_cycles_completed,
            "discovery": {
                "interval_seconds": self.discovery_interval,
                "interval_hours": round(self.discovery_interval / 3600, 1),
                "last_run": discovery_last_run,
                "next_run": self.next_discovery_run,
                "last_stats": discovery_stats
            },
            "refresh": {
                "interval_seconds": self.refresh_interval,
                "interval_hours": round(self.refresh_interval / 3600, 1),
                "last_run": refresh_last_run,
                "next_run": self.next_refresh_run,
                "last_stats": refresh_stats
            },
            "recent_sessions": recent_sessions
        }
