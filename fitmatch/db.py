import sqlite3
import os
import uuid
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Any
from fitmatch.models import Offer, MatchedProductGroup, clean_image_url
from fitmatch.supabase_client import SupabaseClient, SUPABASE_URL, SUPABASE_KEY

logger = logging.getLogger("fitmatch.db")

DB_DIR = "data"
DB_PATH = os.path.join(DB_DIR, "fitmatch.db")


class Database:
    """Unified Database manager delegating directly to Supabase Cloud PostgreSQL in production."""

    def __init__(self, db_path: Optional[str] = None, use_supabase: bool = True):
        self.use_supabase = use_supabase and bool(SUPABASE_URL and SUPABASE_KEY)
        self.supabase = SupabaseClient() if self.use_supabase else None
        self.db_path = db_path or DB_PATH
        dirname = os.path.dirname(self.db_path)
        if dirname:
            os.makedirs(dirname, exist_ok=True)
        self.init_schema()

    def get_connection(self) -> sqlite3.Connection:
        try:
            conn = sqlite3.connect(self.db_path, timeout=30.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA foreign_keys = ON")
            if self.db_path != ":memory:":
                conn.execute("PRAGMA journal_mode = WAL")
            conn.execute("PRAGMA synchronous = NORMAL")
            conn.execute("PRAGMA busy_timeout = 30000")
            return conn
        except sqlite3.DatabaseError:
            # If local sqlite file was corrupt, fallback to clean in-memory sqlite
            conn = sqlite3.connect(":memory:", timeout=30.0)
            conn.row_factory = sqlite3.Row
            return conn

    def init_schema(self):
        """Creates tables, foreign keys and indexes if they do not exist."""
        with self.get_connection() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS products (
                    id TEXT PRIMARY KEY,
                    canonical_name TEXT NOT NULL,
                    brand TEXT,
                    category TEXT,
                    gender TEXT DEFAULT 'Unisex',
                    image_url TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS store_offers (
                    id TEXT PRIMARY KEY,
                    product_id TEXT NOT NULL,
                    store_id TEXT NOT NULL,
                    store_name TEXT NOT NULL,
                    raw_title TEXT NOT NULL,
                    current_price REAL NOT NULL,
                    original_price REAL,
                    discount_pct REAL,
                    product_url TEXT NOT NULL,
                    image_url TEXT,
                    in_stock INTEGER DEFAULT 1,
                    last_checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS price_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    offer_id TEXT NOT NULL,
                    price REAL NOT NULL,
                    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (offer_id) REFERENCES store_offers(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS crawl_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    store_id TEXT NOT NULL,
                    category TEXT NOT NULL,
                    items_found INTEGER NOT NULL,
                    duration_seconds REAL NOT NULL,
                    session_id TEXT,
                    crawled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS sync_sessions (
                    id TEXT PRIMARY KEY,
                    session_type TEXT NOT NULL,
                    trigger_source TEXT DEFAULT 'scheduler',
                    status TEXT NOT NULL DEFAULT 'running',
                    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    completed_at TIMESTAMP,
                    duration_seconds REAL DEFAULT 0,
                    total_items_processed INTEGER DEFAULT 0,
                    total_items_updated INTEGER DEFAULT 0,
                    total_price_drops INTEGER DEFAULT 0,
                    store_stats TEXT DEFAULT '{}',
                    error_message TEXT,
                    metadata TEXT DEFAULT '{}'
                );

                CREATE TABLE IF NOT EXISTS collections (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS wishlist (
                    id TEXT PRIMARY KEY,
                    product_id TEXT,
                    canonical_name TEXT NOT NULL UNIQUE,
                    brand TEXT,
                    store_name TEXT,
                    current_price REAL NOT NULL,
                    original_price REAL,
                    discount_pct REAL,
                    image_url TEXT,
                    product_url TEXT,
                    selected_size TEXT,
                    collection_name TEXT DEFAULT 'Tutti',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS followed_stores (
                    id TEXT PRIMARY KEY,
                    store_id TEXT NOT NULL UNIQUE,
                    store_name TEXT NOT NULL,
                    store_logo TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS recent_activity (
                    id TEXT PRIMARY KEY,
                    activity_type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    subtitle TEXT,
                    image_url TEXT,
                    price REAL,
                    original_price REAL,
                    store_id TEXT,
                    store_name TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS stores (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    rating REAL DEFAULT 4.8,
                    review_count INTEGER DEFAULT 1200,
                    formatted_review_count TEXT,
                    card_theme TEXT DEFAULT 'white',
                    accent_color TEXT,
                    logo_url TEXT,
                    is_verified INTEGER DEFAULT 1,
                    base_url TEXT,
                    free_shipping_threshold REAL,
                    standard_shipping_cost REAL,
                    courier TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS hidden_stores (
                    id TEXT PRIMARY KEY,
                    store_id TEXT NOT NULL UNIQUE,
                    store_name TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS store_reports (
                    id TEXT PRIMARY KEY,
                    store_id TEXT NOT NULL,
                    store_name TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    details TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS store_reviews (
                    id TEXT PRIMARY KEY,
                    store_id TEXT NOT NULL,
                    author_name TEXT NOT NULL,
                    rating INTEGER NOT NULL,
                    review_text TEXT NOT NULL,
                    device_id TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS affiliate_clicks (
                    id TEXT PRIMARY KEY,
                    store_id TEXT,
                    offer_id TEXT,
                    target_url TEXT NOT NULL,
                    monetized_url TEXT,
                    cuid TEXT,
                    source TEXT,
                    device_id TEXT,
                    user_agent TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_affiliate_clicks_store ON affiliate_clicks(store_id);
                CREATE INDEX IF NOT EXISTS idx_affiliate_clicks_created ON affiliate_clicks(created_at);

                CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand);
                CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
                CREATE INDEX IF NOT EXISTS idx_offers_product_id ON store_offers(product_id);
                CREATE INDEX IF NOT EXISTS idx_offers_store_id ON store_offers(store_id);
                CREATE INDEX IF NOT EXISTS idx_offers_price ON store_offers(current_price);
                CREATE INDEX IF NOT EXISTS idx_wishlist_canonical ON wishlist(canonical_name);
                CREATE INDEX IF NOT EXISTS idx_wishlist_collection ON wishlist(collection_name);
            """)

            # Ensure gallery_images columns exist in local SQLite
            for tbl in ["products", "store_offers"]:
                try:
                    conn.execute(f"ALTER TABLE {tbl} ADD COLUMN gallery_images TEXT DEFAULT '[]'")
                except Exception:
                    pass

            try:
                conn.execute("ALTER TABLE crawl_logs ADD COLUMN session_id TEXT")
            except Exception:
                pass

    def upsert_product_and_offer(
        self,
        cluster_key: str,
        canonical_name: str,
        brand: Optional[str],
        category: str,
        gender: str,
        offer: Offer
    ) -> str:
        """Upsert canonical product and record current store offer + price history."""
        clean_off_img = clean_image_url(offer.image_url)
        gallery_json = json.dumps(offer.gallery_images or [])
        if self.use_supabase and self.supabase:
            try:
                self.supabase.upsert_product_and_offer(
                    cluster_key=cluster_key,
                    canonical_name=canonical_name,
                    brand=brand,
                    category=category,
                    gender=gender,
                    image_url=clean_off_img,
                    offer=offer
                )
                return cluster_key
            except Exception as e:
                logger.error(f"[Database] Error upserting to Supabase: {e}")

        with self.get_connection() as conn:
            # 1. Upsert product
            conn.execute("""
                INSERT INTO products (id, canonical_name, brand, category, gender, image_url, gallery_images, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    canonical_name = excluded.canonical_name,
                    brand = COALESCE(excluded.brand, products.brand),
                    image_url = CASE 
                        WHEN products.image_url IS NOT NULL AND products.image_url LIKE 'http%' AND products.image_url NOT LIKE '%blank.gif%' THEN products.image_url
                        ELSE excluded.image_url
                    END,
                    gallery_images = COALESCE(excluded.gallery_images, products.gallery_images),
                    updated_at = CURRENT_TIMESTAMP
            """, (cluster_key, canonical_name, brand, category, gender, clean_off_img, gallery_json))

            # 2. Offer ID is based on store_id + URL hash or store's product ID
            offer_id = f"{offer.store_id}:{offer.product_id or abs(hash(offer.url))}"

            # Check previous price to log price history if changed
            cur = conn.execute("SELECT current_price FROM store_offers WHERE id = ?", (offer_id,))
            prev_row = cur.fetchone()
            price_changed = (prev_row is None or abs(prev_row["current_price"] - offer.price) > 0.01)

            conn.execute("""
                INSERT INTO store_offers (
                    id, product_id, store_id, store_name, raw_title,
                    current_price, original_price, discount_pct,
                    product_url, image_url, gallery_images, in_stock, last_checked_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    product_id = excluded.product_id,
                    raw_title = excluded.raw_title,
                    current_price = excluded.current_price,
                    original_price = excluded.original_price,
                    discount_pct = excluded.discount_pct,
                    product_url = excluded.product_url,
                    image_url = COALESCE(excluded.image_url, store_offers.image_url),
                    gallery_images = COALESCE(excluded.gallery_images, store_offers.gallery_images),
                    in_stock = excluded.in_stock,
                    last_checked_at = CURRENT_TIMESTAMP
            """, (
                offer_id,
                cluster_key,
                offer.store_id,
                offer.store_name,
                offer.title,
                offer.price,
                offer.original_price,
                offer.discount_pct,
                offer.url,
                clean_off_img,
                gallery_json,
                1 if offer.in_stock else 0
            ))

            # Record price history point if new or changed
            if price_changed:
                conn.execute("""
                    INSERT INTO price_history (offer_id, price)
                    VALUES (?, ?)
                """, (offer_id, offer.price))

            conn.commit()
            return cluster_key

    def get_products_for_update(self, limit: int = 30) -> List[Dict[str, Any]]:
        """Fetch indexed products that need periodic price & stock re-verification."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_products_for_update(limit=limit)
            except Exception as e:
                logger.error(f"[Database] Error get_products_for_update from Supabase: {e}")

        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT DISTINCT p.id, p.canonical_name, p.brand, p.category, p.gender
                FROM products p
                JOIN store_offers o ON p.id = o.product_id
                ORDER BY p.updated_at ASC
                LIMIT ?
            """, (limit,)).fetchall()
            return [dict(r) for r in rows]

    def get_offer_price(self, offer_id: str) -> Optional[float]:
        """Get the current recorded price for a specific offer."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_offer_price(offer_id)
            except Exception as e:
                logger.error(f"[Database] Error get_offer_price from Supabase: {e}")

        with self.get_connection() as conn:
            row = conn.execute("SELECT current_price FROM store_offers WHERE id = ?", (offer_id,)).fetchone()
            return float(row["current_price"]) if row else None

    def record_price_history(self, offer_id: str, price: float) -> bool:
        """Record a historical price data point."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.record_price_history(offer_id, price)
            except Exception as e:
                logger.error(f"[Database] Error record_price_history in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("INSERT INTO price_history (offer_id, price) VALUES (?, ?)", (offer_id, price))
            conn.commit()
            return True

    def get_price_history(
        self,
        product_id: Optional[str] = None,
        canonical_name: Optional[str] = None,
        days: int = 90
    ) -> Dict[str, Any]:
        """Retrieve aggregated price history and trend metrics."""
        if self.use_supabase and self.supabase:
            try:
                res = self.supabase.get_price_history(product_id=product_id, canonical_name=canonical_name, days=days)
                if res and res.get("history_points"):
                    return res
            except Exception as e:
                logger.error(f"[Database] Error get_price_history from Supabase: {e}")

        # Local SQLite fallback
        now = datetime.now(timezone.utc)
        start_date = now - timedelta(days=days)
        start_str = start_date.strftime("%Y-%m-%d %H:%M:%S")

        with self.get_connection() as conn:
            p_row = None
            if product_id:
                p_row = conn.execute("SELECT id, canonical_name FROM products WHERE id = ?", (product_id,)).fetchone()
            if not p_row and canonical_name:
                p_row = conn.execute("SELECT id, canonical_name FROM products WHERE canonical_name LIKE ? OR id LIKE ? LIMIT 1", (f"%{canonical_name}%", f"%{canonical_name}%")).fetchone()

            eff_id = p_row["id"] if p_row else (product_id or canonical_name or "")
            eff_canon = p_row["canonical_name"] if p_row else (canonical_name or eff_id)

            offers_rows = conn.execute(
                "SELECT id, store_id, store_name, current_price, original_price FROM store_offers WHERE product_id = ?",
                (eff_id,)
            ).fetchall()
            offers = [dict(r) for r in offers_rows]

            raw_points: List[Dict[str, Any]] = []
            offer_store_map = {o["id"]: o["store_name"] for o in offers}
            offer_current_map = {o["id"]: float(o["current_price"]) for o in offers if o.get("current_price") is not None}
            offer_orig_map = {o["id"]: float(o["original_price"]) for o in offers if o.get("original_price") is not None}

            if offers:
                oids = [o["id"] for o in offers]
                placeholders = ",".join(["?"] * len(oids))
                hist_rows = conn.execute(f"""
                    SELECT offer_id, price, recorded_at
                    FROM price_history
                    WHERE offer_id IN ({placeholders}) AND recorded_at >= ?
                    ORDER BY recorded_at ASC
                """, (*oids, start_str)).fetchall()

                for hr in hist_rows:
                    oid = hr["offer_id"]
                    raw_points.append({
                        "date": str(hr["recorded_at"]),
                        "price": float(hr["price"]),
                        "store_name": offer_store_map.get(oid, "Store"),
                        "offer_id": oid
                    })

            now_str = now.isoformat()
            for oid, cur_p in offer_current_map.items():
                raw_points.append({
                    "date": now_str,
                    "price": cur_p,
                    "store_name": offer_store_map.get(oid, "Store"),
                    "offer_id": oid
                })

            if len(raw_points) == len(offer_current_map) and offer_current_map:
                max_orig = max(offer_orig_map.values()) if offer_orig_map else None
                min_cur = min(offer_current_map.values())
                if max_orig and max_orig > min_cur:
                    past_30d = (now - timedelta(days=30)).isoformat()
                    raw_points.insert(0, {
                        "date": past_30d,
                        "price": round(max_orig, 2),
                        "store_name": "Listino Ufficiale",
                        "offer_id": None
                    })

            raw_points.sort(key=lambda x: str(x["date"]))

            # Group by calendar date (YYYY-MM-DD), picking the minimum market price per day to guarantee clean time-series
            daily_points_map: Dict[str, Dict[str, Any]] = {}
            for pt in raw_points:
                d_short = str(pt["date"])[:10]
                p_val = round(float(pt["price"]), 2)
                if d_short not in daily_points_map or p_val < daily_points_map[d_short]["price"]:
                    daily_points_map[d_short] = {
                        "date": pt["date"],
                        "price": p_val,
                        "store_name": pt["store_name"],
                        "offer_id": pt.get("offer_id")
                    }

            filtered_points = sorted(daily_points_map.values(), key=lambda x: str(x["date"]))

            all_prices = [p["price"] for p in filtered_points if p.get("price") and p["price"] > 0]
            if not all_prices and offer_current_map:
                all_prices = list(offer_current_map.values())

            current_price = min(offer_current_map.values()) if offer_current_map else (all_prices[-1] if all_prices else 0.0)
            lowest_price = min(all_prices) if all_prices else current_price
            highest_price = max(all_prices) if all_prices else current_price
            average_price = round(sum(all_prices) / len(all_prices), 2) if all_prices else current_price

            is_all_time_low = bool(current_price > 0 and current_price <= (lowest_price + 0.50))
            price_drop_pct = round(((average_price - current_price) / average_price) * 100, 1) if average_price > current_price else 0.0
            price_drop_amount = round(average_price - current_price, 2) if average_price > current_price else 0.0

            return {
                "canonical_name": eff_canon,
                "product_id": eff_id,
                "current_price": round(current_price, 2),
                "lowest_price": round(lowest_price, 2),
                "highest_price": round(highest_price, 2),
                "average_price": round(average_price, 2),
                "is_all_time_low": is_all_time_low,
                "price_drop_percentage": price_drop_pct,
                "price_drop_amount": price_drop_amount,
                "history_points": filtered_points,
                "total_data_points": len(filtered_points),
                "first_recorded_date": filtered_points[0]["date"] if filtered_points else None,
                "last_recorded_date": filtered_points[-1]["date"] if filtered_points else None
            }

    def touch_product_updated(self, product_id: str) -> bool:
        """Advance product timestamp to ensure fair round-robin scheduling."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.touch_product_updated(product_id)
            except Exception as e:
                logger.error(f"[Database] Error touch_product_updated in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("UPDATE products SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", (product_id,))
            conn.commit()
            return True

    def upsert_offers_batch(self, items: List[Dict[str, Any]]) -> int:
        """Upsert a list of offers and products in a single database transaction."""
        if not items:
            return 0

        if self.use_supabase and self.supabase:
            try:
                return self.supabase.upsert_offers_batch(items)
            except Exception as e:
                logger.error(f"[Database] Error batch upserting to Supabase: {e}")

        with self.get_connection() as conn:
            for item in items:
                offer: Offer = item["offer"]
                cluster_key = item["cluster_key"]
                canonical_name = item["canonical_name"]
                brand = item.get("brand")
                category = item.get("category")
                gender = item.get("gender", "Unisex")

                # 1. Upsert canonical product
                conn.execute("""
                    INSERT INTO products (id, canonical_name, brand, category, gender, image_url, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(id) DO UPDATE SET
                        canonical_name = excluded.canonical_name,
                        brand = COALESCE(excluded.brand, products.brand),
                        category = COALESCE(excluded.category, products.category),
                        gender = COALESCE(excluded.gender, products.gender),
                        image_url = COALESCE(products.image_url, excluded.image_url),
                        updated_at = CURRENT_TIMESTAMP
                """, (cluster_key, canonical_name, brand, category, gender, offer.image_url))

                # 2. Offer ID
                offer_id = f"{offer.store_id}:{offer.product_id or abs(hash(offer.url))}"
                cur = conn.execute("SELECT current_price FROM store_offers WHERE id = ?", (offer_id,))
                prev_row = cur.fetchone()
                price_changed = (prev_row is None or abs(prev_row["current_price"] - offer.price) > 0.01)

                conn.execute("""
                    INSERT INTO store_offers (
                        id, product_id, store_id, store_name, raw_title,
                        current_price, original_price, discount_pct,
                        product_url, image_url, in_stock, last_checked_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(id) DO UPDATE SET
                        product_id = excluded.product_id,
                        raw_title = excluded.raw_title,
                        current_price = excluded.current_price,
                        original_price = excluded.original_price,
                        discount_pct = excluded.discount_pct,
                        product_url = excluded.product_url,
                        image_url = COALESCE(excluded.image_url, store_offers.image_url),
                        in_stock = excluded.in_stock,
                        last_checked_at = CURRENT_TIMESTAMP
                """, (
                    offer_id,
                    cluster_key,
                    offer.store_id,
                    offer.store_name,
                    offer.title,
                    offer.price,
                    offer.original_price,
                    offer.discount_pct,
                    offer.url,
                    offer.image_url,
                    1 if offer.in_stock else 0
                ))

                if price_changed:
                    conn.execute("""
                        INSERT INTO price_history (offer_id, price)
                        VALUES (?, ?)
                    """, (offer_id, offer.price))

            conn.commit()
            return len(items)

    def record_crawl_log(
        self,
        store_id: str,
        category: str,
        items_found: int,
        duration_seconds: float,
        session_id: Optional[str] = None
    ):
        """Record log of crawler job in database."""
        if self.use_supabase and self.supabase:
            self.supabase.record_crawl_log(store_id, category, items_found, duration_seconds, session_id=session_id)
            return

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO crawl_logs (store_id, category, items_found, duration_seconds, session_id)
                VALUES (?, ?, ?, ?, ?)
            """, (store_id, category, items_found, round(duration_seconds, 2), session_id))
            conn.commit()

    # MARK: - Sync Sessions (Database / Supabase)

    def create_sync_session(
        self,
        session_type: str,
        trigger_source: str = "scheduler",
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """Create a new sync session record with status 'running'."""
        if self.use_supabase and self.supabase:
            sid = self.supabase.create_sync_session(session_type, trigger_source=trigger_source, metadata=metadata)
            if sid:
                return sid

        session_id = str(uuid.uuid4())
        meta_json = json.dumps(metadata or {})
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO sync_sessions (id, session_type, trigger_source, status, metadata)
                VALUES (?, ?, ?, 'running', ?)
            """, (session_id, session_type, trigger_source, meta_json))
            conn.commit()
        return session_id

    def update_sync_session(
        self,
        session_id: str,
        status: str,
        duration_seconds: float = 0.0,
        total_items_processed: int = 0,
        total_items_updated: int = 0,
        total_price_drops: int = 0,
        store_stats: Optional[Dict[str, Any]] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Update a sync session record with outcome and metrics."""
        if self.use_supabase and self.supabase:
            return self.supabase.update_sync_session(
                session_id=session_id,
                status=status,
                duration_seconds=duration_seconds,
                total_items_processed=total_items_processed,
                total_items_updated=total_items_updated,
                total_price_drops=total_price_drops,
                store_stats=store_stats,
                error_message=error_message,
                metadata=metadata
            )

        store_stats_json = json.dumps(store_stats or {})
        meta_json = json.dumps(metadata) if metadata is not None else None
        with self.get_connection() as conn:
            if meta_json is not None:
                conn.execute("""
                    UPDATE sync_sessions
                    SET status = ?, completed_at = CURRENT_TIMESTAMP, duration_seconds = ?,
                        total_items_processed = ?, total_items_updated = ?, total_price_drops = ?,
                        store_stats = ?, error_message = ?, metadata = ?
                    WHERE id = ?
                """, (status, round(duration_seconds, 2), total_items_processed, total_items_updated, total_price_drops, store_stats_json, error_message, meta_json, session_id))
            else:
                conn.execute("""
                    UPDATE sync_sessions
                    SET status = ?, completed_at = CURRENT_TIMESTAMP, duration_seconds = ?,
                        total_items_processed = ?, total_items_updated = ?, total_price_drops = ?,
                        store_stats = ?, error_message = ?
                    WHERE id = ?
                """, (status, round(duration_seconds, 2), total_items_processed, total_items_updated, total_price_drops, store_stats_json, error_message, session_id))
            conn.commit()
        return True

    def get_sync_sessions(
        self,
        limit: int = 20,
        session_type: Optional[str] = None,
        status: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Retrieve recent sync sessions."""
        if self.use_supabase and self.supabase:
            return self.supabase.get_sync_sessions(limit=limit, session_type=session_type, status=status)

        query = "SELECT * FROM sync_sessions WHERE 1=1"
        params: List[Any] = []
        if session_type:
            query += " AND session_type = ?"
            params.append(session_type)
        if status:
            query += " AND status = ?"
            params.append(status)
        query += " ORDER BY started_at DESC LIMIT ?"
        params.append(limit)

        with self.get_connection() as conn:
            cur = conn.execute(query, tuple(params))
            rows = [dict(r) for r in cur.fetchall()]
            for r in rows:
                if isinstance(r.get("store_stats"), str):
                    try:
                        r["store_stats"] = json.loads(r["store_stats"])
                    except Exception:
                        pass
                if isinstance(r.get("metadata"), str):
                    try:
                        r["metadata"] = json.loads(r["metadata"])
                    except Exception:
                        pass
            return rows

    def get_sync_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve a specific session with attached crawl logs."""
        if self.use_supabase and self.supabase:
            return self.supabase.get_sync_session(session_id)

        with self.get_connection() as conn:
            cur = conn.execute("SELECT * FROM sync_sessions WHERE id = ?", (session_id,))
            row = cur.fetchone()
            if not row:
                return None
            session = dict(row)
            if isinstance(session.get("store_stats"), str):
                try:
                    session["store_stats"] = json.loads(session["store_stats"])
                except Exception:
                    pass
            if isinstance(session.get("metadata"), str):
                try:
                    session["metadata"] = json.loads(session["metadata"])
                except Exception:
                    pass

            cur_logs = conn.execute("SELECT * FROM crawl_logs WHERE session_id = ? ORDER BY crawled_at ASC", (session_id,))
            session["crawl_logs"] = [dict(lr) for lr in cur_logs.fetchall()]
            return session

    def delete_sync_session(self, session_id: str) -> bool:
        """Delete a sync session and its linked crawl logs."""
        if self.use_supabase and self.supabase:
            return self.supabase.delete_sync_session(session_id)

        with self.get_connection() as conn:
            conn.execute("DELETE FROM crawl_logs WHERE session_id = ?", (session_id,))
            conn.execute("DELETE FROM sync_sessions WHERE id = ?", (session_id,))
            conn.commit()
            return True

    def delete_sync_sessions(self, status: Optional[str] = None) -> int:
        """Delete multiple sync sessions filtered by status."""
        if self.use_supabase and self.supabase:
            return self.supabase.delete_sync_sessions(status=status)

        with self.get_connection() as conn:
            if status:
                sessions = conn.execute("SELECT id FROM sync_sessions WHERE status = ?", (status,)).fetchall()
            else:
                sessions = conn.execute("SELECT id FROM sync_sessions").fetchall()

            deleted = 0
            for s in sessions:
                sid = s["id"]
                conn.execute("DELETE FROM crawl_logs WHERE session_id = ?", (sid,))
                conn.execute("DELETE FROM sync_sessions WHERE id = ?", (sid,))
                deleted += 1
            conn.commit()
            return deleted

    def get_latest_sync_session(self, session_type: str) -> Optional[Dict[str, Any]]:
        """Retrieve the most recent completed session of a specific type."""
        if self.use_supabase and self.supabase:
            return self.supabase.get_latest_sync_session(session_type)

        with self.get_connection() as conn:
            cur = conn.execute("""
                SELECT * FROM sync_sessions
                WHERE session_type = ? AND status = 'completed'
                ORDER BY started_at DESC LIMIT 1
            """, (session_type,))
            row = cur.fetchone()
            if not row:
                return None
            session = dict(row)
            if isinstance(session.get("store_stats"), str):
                try:
                    session["store_stats"] = json.loads(session["store_stats"])
                except Exception:
                    pass
            return session

    def get_store_health_metrics(self) -> List[Dict[str, Any]]:
        """Retrieve aggregate store coverage and sizes health."""
        if self.use_supabase and self.supabase:
            return self.supabase.get_store_health_metrics()

        with self.get_connection() as conn:
            cur = conn.execute("""
                SELECT store_id,
                       COUNT(*) as total_offers,
                       SUM(CASE WHEN available_sizes IS NOT NULL AND available_sizes != '[]' AND available_sizes != '' THEN 1 ELSE 0 END) as with_sizes,
                       ROUND(AVG(current_price), 2) as avg_price,
                       ROUND(AVG(discount_pct), 1) as avg_discount,
                       MAX(last_checked_at) as last_checked_at
                FROM store_offers
                GROUP BY store_id
                ORDER BY total_offers DESC
            """)
            rows = [dict(r) for r in cur.fetchall()]
            for r in rows:
                tot = r.get("total_offers") or 0
                ws = r.get("with_sizes") or 0
                r["size_coverage_pct"] = round((ws / tot) * 100, 1) if tot > 0 else 0.0
            return rows

    def get_stats(self) -> Dict[str, Any]:
        """Return catalog overview statistics."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_stats()
            except Exception as e:
                logger.error(f"[Database] Error fetching stats from Supabase: {e}")

        with self.get_connection() as conn:
            total_products = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
            total_offers = conn.execute("SELECT COUNT(*) FROM store_offers").fetchone()[0]
            multi_store_products = conn.execute("""
                SELECT COUNT(*) FROM (
                    SELECT product_id FROM store_offers GROUP BY product_id HAVING COUNT(DISTINCT store_id) > 1
                )
            """).fetchone()[0]
            brands_count = conn.execute("SELECT COUNT(DISTINCT brand) FROM products WHERE brand IS NOT NULL").fetchone()[0]

            store_breakdown = conn.execute("""
                SELECT store_name, COUNT(*) as count, AVG(current_price) as avg_price, AVG(discount_pct) as avg_discount
                FROM store_offers
                GROUP BY store_name
            """).fetchall()

            top_savings = conn.execute("""
                SELECT p.canonical_name, p.brand,
                       MIN(o.current_price) as min_price,
                       MAX(o.current_price) as max_price,
                       (MAX(o.current_price) - MIN(o.current_price)) as savings,
                       COUNT(DISTINCT o.store_id) as store_count
                FROM products p
                JOIN store_offers o ON p.id = o.product_id
                GROUP BY p.id
                HAVING store_count > 1
                ORDER BY savings DESC
                LIMIT 5
            """).fetchall()

            return {
                "total_products": total_products,
                "total_offers": total_offers,
                "multi_store_products": multi_store_products,
                "brands_count": brands_count,
                "store_breakdown": [dict(r) for r in store_breakdown],
                "top_savings": [dict(r) for r in top_savings]
            }

    def search_indexed(self, query: str, category: Optional[str] = None, limit: int = 20) -> List[Dict[str, Any]]:
        """Fast SQL query on pre-indexed products and their store offers with optional category filter."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.search_indexed(query=query, category=category, limit=limit)
            except Exception as e:
                logger.error(f"[Database] Error search_indexed from Supabase: {e}")

        with self.get_connection() as conn:
            words = query.strip().lower().split()
            where_clauses = ["(LOWER(p.canonical_name) LIKE ? OR LOWER(COALESCE(p.brand, '')) LIKE ?)" for _ in words]
            params = []
            for w in words:
                params.extend([f"%{w}%", f"%{w}%"])

            if category and category.lower() != "all" and category.lower() != "tutti":
                where_clauses.append("p.category = ?")
                params.append(category.lower())

            where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

            sql = f"""
                SELECT p.id, p.canonical_name, p.brand, p.category, p.gender, p.image_url,
                       COUNT(o.id) as offer_count,
                       MIN(o.current_price) as best_price,
                       MAX(o.current_price) as max_price
                FROM products p
                JOIN store_offers o ON p.id = o.product_id
                WHERE {where_sql}
                GROUP BY p.id
                ORDER BY (MAX(o.current_price) - MIN(o.current_price)) DESC, best_price ASC
                LIMIT ?
            """
            params.append(limit)
            cur = conn.execute(sql, params)
            products = [dict(r) for r in cur.fetchall()]

            from fitmatch.models import STORE_SHIPPING_RULES

            for prod in products:
                offer_cur = conn.execute("""
                    SELECT store_id, store_name, current_price, original_price, discount_pct, product_url, image_url, raw_title
                    FROM store_offers
                    WHERE product_id = ?
                    ORDER BY current_price ASC
                """, (prod["id"],))
                offers = []
                for row in offer_cur.fetchall():
                    o = dict(row)
                    sid = o["store_id"].lower().strip()
                    rule = STORE_SHIPPING_RULES.get(sid, {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})
                    price = float(o["current_price"])
                    cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
                    is_free = (cost == 0.0)
                    o["price"] = price
                    o["url"] = o["product_url"]
                    o["title"] = o.get("raw_title") or prod["canonical_name"]
                    o["brand"] = prod.get("brand")
                    o["in_stock"] = True
                    o["shipping_cost"] = cost
                    o["total_price"] = round(price + cost, 2)
                    o["is_free_shipping"] = is_free
                    o["shipping_label"] = "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped."
                    o["free_shipping_threshold"] = rule["free_threshold"]
                    o["courier"] = rule["courier"]
                    offers.append(o)

                prod["offers"] = offers
                prod["highest_price"] = prod.get("max_price")
                if prod.get("max_price") and prod.get("best_price"):
                    prod["cross_store_savings"] = round(prod["max_price"] - prod["best_price"], 2)
                else:
                    prod["cross_store_savings"] = 0.0

            return products

    def search_smart(
        self,
        target_keywords: List[str],
        category: Optional[str] = None,
        brand: Optional[str] = None,
        gender: Optional[str] = None,
        max_price: Optional[float] = None,
        min_price: Optional[float] = None,
        size: Optional[str] = None,
        store_id: Optional[str] = None,
        limit: int = 30,
        raw_query: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Smart AI-powered SQL retrieval matching multiple candidate models, price bounds and filters."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.search_smart(
                    target_keywords=target_keywords,
                    category=category,
                    brand=brand,
                    gender=gender,
                    max_price=max_price,
                    min_price=min_price,
                    size=size,
                    store_id=store_id,
                    limit=limit,
                    raw_query=raw_query
                )
            except Exception as e:
                import traceback
                logger.error(f"[Database] Error search_smart from Supabase: {e}\n{traceback.format_exc()}")

        from fitmatch.models import STORE_SHIPPING_RULES

        with self.get_connection() as conn:
            where_clauses = []
            params: List[Any] = []

            # 1. Target Keywords matching (OR across candidate model archetypes)
            if target_keywords:
                kw_conditions = []
                for kw in target_keywords:
                    words = kw.strip().lower().split()
                    if not words:
                        continue
                    word_conds = []
                    for w in words:
                        word_conds.append("(LOWER(p.canonical_name || ' ' || COALESCE(p.brand, '')) LIKE ?)")
                        params.append(f"%{w}%")
                    kw_conditions.append("(" + " AND ".join(word_conds) + ")")
                if kw_conditions:
                    where_clauses.append("(" + " OR ".join(kw_conditions) + ")")

            # 2. Brand Filter
            if brand:
                where_clauses.append("(LOWER(COALESCE(p.brand, '')) LIKE ? OR LOWER(p.canonical_name) LIKE ?)")
                params.append(f"%{brand.lower()}%")
                params.append(f"%{brand.lower()}%")

            # 3. Category Filter
            if category and category.lower() not in ("all", "tutti"):
                where_clauses.append("p.category = ?")
                params.append(category.lower())

            # 4. Gender Filter
            if gender and gender.lower() in ("donna", "uomo"):
                where_clauses.append("(LOWER(p.gender) LIKE ? OR LOWER(p.gender) = 'unisex' OR p.gender IS NULL)")
                params.append(f"%{gender.lower()}%")

            # 5. Price bounds on the product's lowest offer
            if max_price is not None:
                try:
                    where_clauses.append("o.current_price <= ?")
                    params.append(float(max_price))
                except (ValueError, TypeError):
                    pass

            if min_price is not None:
                try:
                    where_clauses.append("o.current_price >= ?")
                    params.append(float(min_price))
                except (ValueError, TypeError):
                    pass

            # 6. Specific store
            if store_id and store_id.lower() not in ("all", "tutti"):
                where_clauses.append("LOWER(o.store_id) = ?")
                params.append(store_id.lower())

            where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

            sql = f"""
                SELECT p.id, p.canonical_name, p.brand, p.category, p.gender, p.image_url,
                       COUNT(DISTINCT o.id) as offer_count,
                       MIN(o.current_price) as best_price,
                       MAX(o.current_price) as max_price
                FROM products p
                JOIN store_offers o ON p.id = o.product_id
                WHERE {where_sql}
                GROUP BY p.id
                ORDER BY (MAX(o.current_price) - MIN(o.current_price)) DESC, best_price ASC
                LIMIT ?
            """
            params.append(limit)
            cur = conn.execute(sql, params)
            products = [dict(r) for r in cur.fetchall()]

            # Only fallback to category/brand browsing if the user did NOT specify target keywords
            if not products and not target_keywords and (category or brand):
                fb_clauses = []
                fb_params: List[Any] = []
                if category and category.lower() not in ("all", "tutti"):
                    fb_clauses.append("p.category = ?")
                    fb_params.append(category.lower())
                if brand:
                    fb_clauses.append("LOWER(COALESCE(p.brand, '')) LIKE ?")
                    fb_params.append(f"%{brand.lower()}%")
                if max_price:
                    fb_clauses.append("o.current_price <= ?")
                    fb_params.append(float(max_price))
                if fb_clauses:
                    fb_sql = f"""
                        SELECT p.id, p.canonical_name, p.brand, p.category, p.gender, p.image_url,
                               COUNT(DISTINCT o.id) as offer_count,
                               MIN(o.current_price) as best_price,
                               MAX(o.current_price) as max_price
                        FROM products p
                        JOIN store_offers o ON p.id = o.product_id
                        WHERE {" AND ".join(fb_clauses)}
                        GROUP BY p.id
                        ORDER BY best_price ASC
                        LIMIT ?
                    """
                    fb_params.append(limit)
                    cur = conn.execute(fb_sql, fb_params)
                    products = [dict(r) for r in cur.fetchall()]

            for prod in products:
                offer_cur = conn.execute("""
                    SELECT store_id, store_name, current_price, original_price, discount_pct, product_url, image_url, raw_title
                    FROM store_offers
                    WHERE product_id = ?
                    ORDER BY current_price ASC
                """, (prod["id"],))
                offers = []
                for row in offer_cur.fetchall():
                    o = dict(row)
                    sid = o["store_id"].lower().strip()
                    rule = STORE_SHIPPING_RULES.get(sid, {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})
                    price = float(o["current_price"])
                    cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
                    is_free = (cost == 0.0)
                    o["price"] = price
                    o["url"] = o["product_url"]
                    o["title"] = o.get("raw_title") or prod["canonical_name"]
                    o["brand"] = prod.get("brand")
                    o["in_stock"] = True
                    o["shipping_cost"] = cost
                    o["total_price"] = round(price + cost, 2)
                    o["is_free_shipping"] = is_free
                    o["shipping_label"] = "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped."
                    o["free_shipping_threshold"] = rule["free_threshold"]
                    o["courier"] = rule["courier"]
                    offers.append(o)

                prod["offers"] = offers
                prod["highest_price"] = prod.get("max_price")
                if prod.get("max_price") and prod.get("best_price"):
                    prod["cross_store_savings"] = round(prod["max_price"] - prod["best_price"], 2)
                else:
                    prod["cross_store_savings"] = 0.0

            return products

    def get_store_showcases(self, limit_per_store: int = 6) -> List[Dict[str, Any]]:
        """Return curated product highlights for each store (Shop-style merchant showcase)."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_store_showcases(limit_per_store=limit_per_store)
            except Exception as e:
                logger.error(f"[Database] Error get_store_showcases from Supabase: {e}")

        ratings = {
            "cisalfa": "4.8",
            "maxisport": "4.9",
            "misterrunning": "4.9",
            "nencini": "4.7",
            "top4running": "4.8",
            "runningwarehouse": "4.9",
            "deporvillage": "4.3",
            "alltricks": "4.4",
            "decathlon": "4.8",
            "sportler": "4.8",
            "nike": "4.9",
            "adidas": "4.8",
            "tradeinn": "4.7",
            "df_sportspecialist": "4.8"
        }
        with self.get_connection() as conn:
            stores = conn.execute("""
                SELECT store_id, store_name, COUNT(*) as total_offers, AVG(discount_pct) as avg_discount
                FROM store_offers
                GROUP BY store_id, store_name
                ORDER BY total_offers DESC, store_name ASC
            """).fetchall()

            result = []
            for s in stores:
                sid, sname = s["store_id"], s["store_name"]
                prods_cur = conn.execute("""
                    SELECT o.id, o.raw_title as title, p.brand, COALESCE(o.image_url, p.image_url) as image_url,
                           o.current_price, o.original_price, o.discount_pct, o.product_url, p.canonical_name,
                           p.id as product_id
                    FROM store_offers o
                    JOIN products p ON o.product_id = p.id
                    WHERE o.store_id = ? AND o.image_url IS NOT NULL AND o.image_url != ''
                    ORDER BY o.discount_pct DESC, o.current_price ASC
                    LIMIT ?
                """, (sid, limit_per_store))

                products = [dict(r) for r in prods_cur.fetchall()]
                from fitmatch.models import STORE_SHIPPING_RULES
                rule = STORE_SHIPPING_RULES.get(sid, {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})
                for p in products:
                    price = float(p["current_price"])
                    cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
                    is_free = (cost == 0.0)
                    p["shipping_cost"] = cost
                    p["total_price"] = round(price + cost, 2)
                    p["is_free_shipping"] = is_free
                    p["shipping_label"] = "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped."
                    p["free_shipping_threshold"] = rule["free_threshold"]
                    p["courier"] = rule["courier"]

                discounts = [p.get("discount_pct") or 0 for p in products]
                max_d = int(round(max(discounts))) if discounts else int(round(s["avg_discount"] or 0))
                free_th = int(round(rule["free_threshold"])) if rule.get("free_threshold") else None

                if max_d >= 70:
                    promo_text = f"Risparmia fino al {max_d}% • Spedizione gratis da {free_th} €" if free_th else f"Risparmia fino al {max_d}% sui saldi di stagione"
                elif max_d >= 40:
                    promo_text = f"Sconti fino al {max_d}% e spedizione gratis da {free_th} €" if free_th else f"Sconti fino al {max_d}% su modelli selezionati"
                elif max_d > 0:
                    promo_text = f"Prezzi ribassati fino al -{max_d}%"
                elif free_th:
                    promo_text = f"Spedizione gratuita da {free_th} €"
                else:
                    promo_text = "Rivenditore autorizzato con offerte esclusive."

                result.append({
                    "store_id": sid,
                    "store_name": sname,
                    "promo_text": promo_text,
                    "total_offers": s["total_offers"],
                    "avg_discount": round(s["avg_discount"] or 0, 1),
                    "rating": ratings.get(sid, "4.8"),
                    "products": products
                })

            return result

    def get_store_details(self, store_id: str, query: str = "", sort: str = "discount", limit: int = 100) -> Optional[Dict[str, Any]]:
        """Return full merchant details, trust badges, stats, and indexed catalog for a store."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_store_details(store_id=store_id, query=query, sort=sort, limit=limit)
            except Exception as e:
                logger.error(f"[Database] Error get_store_details from Supabase: {e}")

        metadata = {
            "cisalfa": {
                "name": "Cisalfa Sport",
                "base_url": "https://www.cisalfasport.it",
                "rating": "4.8",
                "review_count": "18.2k recensioni",
                "description": "Leader italiano nella vendita di abbigliamento, calzature e attrezzature sportive dei migliori marchi mondiali.",
                "full_description": "Fondata nel 1977, Cisalfa Sport è la catena di articoli sportivi numero uno in Italia con oltre 160 megastore fisici. Offre la massima sicurezza per gli acquisti con garanzia ufficiale, prodotti 100% autentici dei top brand (Nike, adidas, Asics, Hoka) e la possibilità di effettuare resi e cambi sia online che comodamente in qualsiasi punto vendita sul territorio nazionale.",
                "badges": ["Rivenditore Ufficiale", "160+ Negozi in Italia", "Reso 30 Giorni", "Garanzia Italia"],
                "highlights": ["160+ Punti Vendita Fisici", "Reso Facile in Negozio", "Top Brand Certificati"],
                "location": "Sede & Magazzino Centrale: Curno (BG), Italia",
                "shipping_info": "Spedizione standard 9,90 € • Gratuita da 99,00 € (o gratis con ritiro in negozio)",
                "shipping_rule": {"standard": 9.90, "free_threshold": 99.0, "label": "Gratis da 99 €", "courier": "BRT / GLS"},
                "return_policy": "30 giorni per reso online o in qualsiasi negozio",
                "rating_breakdown": {
                    "score": 4.8,
                    "positive_pct": "96%",
                    "review_count": "18.200+",
                    "platform": "Trustpilot / Feedaty"
                }
            },
            "maxisport": {
                "name": "Maxi Sport",
                "base_url": "https://www.maxisport.com",
                "rating": "4.9",
                "review_count": "24.5k recensioni",
                "description": "Oltre 30 anni di passione sport & street style con le ultime novità running, trail e moda sportswear.",
                "full_description": "Maxi Sport è una delle eccellenze italiane nel retail specializzato sport e lifestyle con megastore moderni in Lombardia e un e-commerce pluripremiato. Uno staff di oltre 200 tecnici ed esperti seleziona con cura ogni modello per assicurare al cliente la miglior scarpa per il proprio appoggio e stile di corsa, garantendo trasparenza e resi rapidi.",
                "badges": ["Spedizione Rapida", "Reso Gratuito", "Rivenditore Autorizzato", "Assistenza Dedicata"],
                "highlights": ["Consulenza Tecnica Running", "Reso Rapido & Gratuito", "Oltre 30 Anni di Esperienza"],
                "location": "Sede & Hub Logistico: Merate (LC), Italia",
                "shipping_info": "Spedizione standard 7,90 € • Gratuita in tutta Italia per ordini superiori a 99,00 €",
                "shipping_rule": {"standard": 7.90, "free_threshold": 99.0, "label": "Gratis da 99 €", "courier": "GLS / DHL"},
                "return_policy": "Reso facile entro 30 giorni",
                "rating_breakdown": {
                    "score": 4.9,
                    "positive_pct": "98%",
                    "review_count": "24.500+",
                    "platform": "Feedaty / Recensioni Certificate"
                }
            },
            "misterrunning": {
                "name": "Mister Running",
                "base_url": "https://www.misterrunning.com",
                "rating": "4.9",
                "review_count": "15.1k recensioni",
                "description": "Lo specialista online del running con la più vasta gamma di scarpe tecniche, abbigliamento e accessori.",
                "full_description": "Mister Running è il portale specializzato leader in Europa per atleti, podisti e maratoneti. Gestito da runner professionisti ed entusiasti della disciplina, il catalogo comprende le ultime novità di scarpe da gara in carbonio, modelli daily training e trail con disponibilità reale in magazzino, miglior prezzo garantito e spedizioni veloci con tracciamento in tempo reale.",
                "badges": ["Spedizione 24/48h", "Prezzo Minimo Garantito", "Reso 14 Giorni", "100% Originale"],
                "highlights": ["Specialista Tecnico Running", "Stock 100% Reale", "Spedizione Espressa 24h"],
                "location": "Sede & Magazzino Centrale: Cosenza, Italia",
                "shipping_info": "Spedizione standard 4,90 € • Gratuita in tutta Italia per ordini da 49,00 €",
                "shipping_rule": {"standard": 4.90, "free_threshold": 49.0, "label": "Gratis da 49 €", "courier": "DHL / UPS"},
                "return_policy": "Reso garantito e rimborso immediato",
                "rating_breakdown": {
                    "score": 4.9,
                    "positive_pct": "98%",
                    "review_count": "15.100+",
                    "platform": "Trustpilot / Trusted Shops"
                }
            },
            "nencini": {
                "name": "Nencini Sport",
                "base_url": "https://www.nencinisport.it",
                "rating": "4.7",
                "review_count": "9.8k recensioni",
                "description": "Punto di riferimento toscano e online per lo sport con offerte esclusive outlet e migliori marche.",
                "full_description": "Nato nel 1954 in Toscana, Nencini Sport unisce una lunga tradizione familiare a una moderna piattaforma online. Punto di forza è l'ampiezza dell'assortimento con offerte outlet esclusive e sconti continuativi sui modelli di fine serie e nuovi arrivi, con la sicurezza di prodotti rigorosamente originali e un servizio clienti sempre attivo.",
                "badges": ["Outlet & Novità", "Consegna Espressa", "Pagamenti Sicuri", "Garanzia Ufficiale"],
                "highlights": ["Tradizione dal 1954", "Grandi Sconti Outlet", "Assistenza Clienti Telefonica"],
                "location": "Sede & Magazzino: Calenzano (FI), Italia",
                "shipping_info": "Spedizione standard 5,90 € • Gratuita per ordini superiori a 100,00 €",
                "shipping_rule": {"standard": 5.90, "free_threshold": 100.0, "label": "Gratis da 100 €", "courier": "BRT Espresso"},
                "return_policy": "30 giorni per reso e cambio taglia",
                "rating_breakdown": {
                    "score": 4.7,
                    "positive_pct": "94%",
                    "review_count": "9.800+",
                    "platform": "Trustpilot / E-Commerce Sicuro"
                }
            },
            "top4running": {
                "name": "Top4Running",
                "base_url": "https://top4running.it",
                "rating": "4.8",
                "review_count": "11.3k recensioni",
                "description": "La destinazione europea per runner, atleti da pista e maratoneti con scarpe racing d'élite.",
                "full_description": "Top4Running fa parte di Top4Sport, uno dei network sportivi più all'avanguardia in Europa. Dedicato a chi vive la corsa come una passione seria, dalle gare su pista alle ultra-maratone, collabora direttamente con i dipartimenti racing di Nike, Asics e adidas per portare in anteprima le scarpe da record, unendo tecnologia all'esperienza del Top4Running Club.",
                "badges": ["Top Club Sconti", "Scarpe da Gara", "Reso 30 Giorni", "Spedizione Veloce"],
                "highlights": ["Anteprime Super-Shoes", "Top4Running Club Vantaggi", "Community Atleti Internazionali"],
                "location": "Hub Logistico Centrale: Praga, Unione Europea",
                "shipping_info": "Spedizione standard 4,90 € • Gratuita per ordini a partire da 75,00 €",
                "shipping_rule": {"standard": 4.90, "free_threshold": 75.0, "label": "Gratis da 75 €", "courier": "DPD / BRT"},
                "return_policy": "30 giorni di reso semplice e sicuro",
                "rating_breakdown": {
                    "score": 4.8,
                    "positive_pct": "96%",
                    "review_count": "11.300+",
                    "platform": "Trustpilot / Heureka Certified"
                }
            },
            "runningwarehouse": {
                "name": "Running Warehouse Europe",
                "base_url": "https://www.runningwarehouse.eu",
                "rating": "4.9",
                "review_count": "32.0k recensioni",
                "description": "Il colosso globale del running con la selezione tecnica più approfondita per maratona, trail e ultra.",
                "full_description": "Nato in California e affermatosi in tutto il mondo, Running Warehouse Europe è considerato dalla community podistica il punto di riferimento assoluto per ampiezza di taglie, schede tecniche dettagliate (drop, peso al grammo, altezza suola) e un servizio post-vendita leggendario, che include una politica di reso fino a 60 giorni.",
                "badges": ["Catalogo Globale", "Consulenza Tecnica", "Reso 60 Giorni", "Stock Certificato"],
                "highlights": ["Schede Tecniche al Millimetro", "Reso Record 60 Giorni", "Assortimento Taglie Unico"],
                "location": "Hub Europeo: Schutterwald, Germania (UE)",
                "shipping_info": "Spedizione standard 10,00 € • Gratuita per l'Italia per ordini superiori a 59,00 €",
                "shipping_rule": {"standard": 10.00, "free_threshold": 59.0, "label": "Gratis da 59 €", "courier": "UPS Standard"},
                "return_policy": "Fino a 60 giorni per il reso gratuito o cambio",
                "rating_breakdown": {
                    "score": 4.9,
                    "positive_pct": "99%",
                    "review_count": "32.000+",
                    "platform": "Trustpilot / Trusted Shops Global"
                }
            },
            "deporvillage": {
                "name": "Deporvillage",
                "base_url": "https://www.deporvillage.it",
                "rating": "4.3",
                "review_count": "92.5k recensioni",
                "description": "Leader nel Sud Europa per ciclismo, outdoor, elettronica sportiva, occhiali tecnici e nutrizione.",
                "full_description": "Deporvillage è il punto di riferimento per gli appassionati di sport outdoor in Italia, Spagna e Francia. Con oltre 100.000 articoli a catalogo, si distingue per la straordinaria profondità di gamma negli accessori per ciclismo, smartwatch e cardiofrequenzimetri Garmin e Polar, occhiali sportivi Oakley e integratori dei migliori brand mondiali.",
                "badges": ["Specialista Ciclismo & Outdoor", "90k+ Recensioni Verificate", "Reso 365 Giorni", "Garmin & Oakley Partner"],
                "highlights": ["Catalogo Accessori N.1", "Reso Esteso 365 Giorni", "Spedizione Tracciata 24/48h"],
                "location": "Hub Logistico: Barcellona (Spagna) con spedizione rapida in Italia",
                "shipping_info": "Spedizione standard 4,99 € • Gratuita in tutta Italia per ordini superiori a 80,00 €",
                "shipping_rule": {"standard": 4.99, "free_threshold": 80.0, "label": "Gratis da 80 €", "courier": "GLS / DPD"},
                "return_policy": "Fino a 365 giorni per reso o sostituzione",
                "rating_breakdown": {
                    "score": 4.3,
                    "positive_pct": "91%",
                    "review_count": "92.500+",
                    "platform": "Trustpilot Verified Reviews"
                }
            },
            "alltricks": {
                "name": "Alltricks",
                "base_url": "https://www.alltricks.it",
                "rating": "4.4",
                "review_count": "45.8k recensioni",
                "description": "Gigante europeo di ciclismo, trail, elettronica Garmin e attrezzatura fitness (Gruppo Decathlon).",
                "full_description": "Fondata da ciclisti ed entrata a far parte della galassia Decathlon, Alltricks è la mecca europea per chi cerca componenti, ciclocomputer, caschi ad alta protezione, accessori per il recupero muscolare come pistole massaggianti Theragun e abbigliamento trail d'alta quota, garantendo spedizioni rapide con corriere espresso.",
                "badges": ["Gruppo Decathlon", "Spedizione Bartolini 24/48h", "Prezzo Minimo Garantito", "Reso Facile 60 Giorni"],
                "highlights": ["Garanzia Gruppo Decathlon", "Spedizione Rapida Bartolini", "Esperti Ciclismo & Fitness"],
                "location": "Piattaforma Logistica Europea: Châteaudun (Francia) con consegna diretta Italia",
                "shipping_info": "Spedizione standard 4,99 € • Gratuita con Bartolini per ordini a partire da 69,00 €",
                "shipping_rule": {"standard": 4.99, "free_threshold": 69.0, "label": "Gratis da 69 €", "courier": "Bartolini (BRT)"},
                "return_policy": "Fino a 60 giorni per il reso (100 giorni con Alltricks+)",
                "rating_breakdown": {
                    "score": 4.4,
                    "positive_pct": "92%",
                    "review_count": "45.800+",
                    "platform": "Trustpilot / Avis Vérifiés"
                }
            },
            "tradeinn": {
                "name": "Tradeinn",
                "base_url": "https://www.tradeinn.com",
                "rating": "4.7",
                "review_count": "18.5k recensioni",
                "description": "Gigante europeo dell'e-commerce sportivo con megastore verticali: Runnerinn, Bikeinn, Smashinn e Trekkinn.",
                "full_description": "Tradeinn è uno dei più grandi network europei di negozi sportivi specializzati con oltre 3 milioni di prodotti in catalogo. Comprende canali dedicati come Runnerinn per la corsa, Bikeinn per il ciclismo, Smashinn per il padel e Trekkinn per l'outdoor, offrendo prezzi altamente competitivi e spedizioni tracciate verso l'Italia.",
                "badges": ["Catalogo Globale 3M+", "Prezzi Outlet Garantiti", "Reso 30 Giorni", "Pagamenti Sicuri"],
                "highlights": ["3M+ Prodotti a Stock", "Specialista Multi-Sport", "Prezzi Ultra Competitivi"],
                "location": "Hub Logistico Europeo: Celrà (Girona), Spagna con consegna espressa in Italia",
                "shipping_info": "Spedizione standard 4,99 € • Gratuita da 150,00 € con corriere Poste Italiane / GLS",
                "shipping_rule": {"standard": 4.99, "free_threshold": 150.0, "label": "Gratis da 150 €", "courier": "Poste / GLS / DPD"},
                "return_policy": "30 giorni per il reso semplice",
                "rating_breakdown": {
                    "score": 4.7,
                    "positive_pct": "95%",
                    "review_count": "18.500+",
                    "platform": "Trustpilot / eKomi"
                }
            },
            "df_sportspecialist": {
                "name": "DF Sport Specialist",
                "base_url": "https://www.df-sportspecialist.it",
                "rating": "4.8",
                "review_count": "5.4k recensioni",
                "description": "Storica catena italiana punto di riferimento per corsa, montagna, outdoor, ciclismo e padel.",
                "full_description": "Fondata da Sergio Longoni, DF Sport Specialist è la catena di negozi sportivi di riferimento nel Nord Italia con oltre 15 megastore e un portale e-commerce moderno su Shopify. Conosciuta per l'eccellenza dello staff tecnico e la qualità dei brand trattati, offre assistenza specializzata per la scelta delle scarpe da corsa, attrezzatura da alpinismo e racchette da padel.",
                "badges": ["15+ Megastore in Italia", "Spedizione Veloce 24/48h", "Staff Tecnico Esperto", "Reso Facile 30 Giorni"],
                "highlights": ["15 Megastore Fisici", "Consulenza Tecnica Specializzata", "Spedizione Gratuita da 60€"],
                "location": "Sede Centrale: Barzanò (LC), Italia",
                "shipping_info": "Spedizione standard 5,90 € • Gratuita in tutta Italia da 60,00 € con GLS / BRT",
                "shipping_rule": {"standard": 5.90, "free_threshold": 60.0, "label": "Gratis da 60 €", "courier": "GLS / BRT"},
                "return_policy": "30 giorni per reso in negozio o con corriere",
                "rating_breakdown": {
                    "score": 4.8,
                    "positive_pct": "96%",
                    "review_count": "5.400+",
                    "platform": "Feedaty / Trustpilot"
                }
            }
        }

        sid = store_id.lower().strip()
        info = metadata.get(sid)
        if not info:
            # Fallback for unrecognized store id
            info = {
                "name": store_id.capitalize(),
                "base_url": "",
                "rating": "4.8",
                "review_count": "10k+ recensioni",
                "description": "Rivenditore partner verificato con offerte esclusive e catalogo sportivo.",
                "badges": ["Rivenditore Verificato", "Spedizione Rapida", "Pagamenti Sicuri"]
            }

        with self.get_connection() as conn:
            stat_row = conn.execute("""
                SELECT COUNT(*), AVG(discount_pct), MIN(current_price)
                FROM store_offers
                WHERE store_id = ?
            """, (sid,)).fetchone()

            total_offers = stat_row[0] if stat_row else 0
            avg_discount = round(stat_row[1] or 0, 1) if stat_row else 0.0
            min_price = round(stat_row[2] or 0, 2) if stat_row else 0.0

            # Order by mapping
            order_by = "o.discount_pct DESC, o.current_price ASC"
            if sort == "price_asc":
                order_by = "o.current_price ASC"
            elif sort == "price_desc":
                order_by = "o.current_price DESC"
            elif sort == "name":
                order_by = "p.canonical_name ASC"

            from fitmatch.smart_search import LocalHeuristicParser
            clean_q = LocalHeuristicParser.normalize_typos(query.strip().lower()) if query.strip() else ""
            words = clean_q.split() if clean_q else []
            where_clauses = ["o.store_id = ?"]
            params = [sid]

            for w in words:
                where_clauses.append("(LOWER(o.raw_title) LIKE ? OR LOWER(COALESCE(p.brand, '')) LIKE ? OR LOWER(p.canonical_name) LIKE ?)")
                params.extend([f"%{w}%", f"%{w}%", f"%{w}%"])

            where_sql = " AND ".join(where_clauses)
            sql = f"""
                SELECT o.id, o.raw_title as title, p.brand, COALESCE(o.image_url, p.image_url) as image_url,
                       o.current_price, o.original_price, o.discount_pct, o.product_url, p.canonical_name,
                       p.id as product_id
                FROM store_offers o
                JOIN products p ON o.product_id = p.id
                WHERE {where_sql} AND o.image_url IS NOT NULL AND o.image_url != ''
                ORDER BY {order_by}
                LIMIT ?
            """
            params.append(limit)
            prods = [dict(r) for r in conn.execute(sql, params).fetchall()]
            rule = info.get("shipping_rule", {"standard": 4.90, "free_threshold": 50.0, "label": "Gratis da 50 €", "courier": "Corriere Espresso"})
            for p in prods:
                price = float(p["current_price"])
                cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
                is_free = (cost == 0.0)
                p["shipping_cost"] = cost
                p["total_price"] = round(price + cost, 2)
                p["is_free_shipping"] = is_free
                p["shipping_label"] = "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped."
                p["free_shipping_threshold"] = rule["free_threshold"]
                p["courier"] = rule["courier"]

            return {
                "store_id": sid,
                "store_name": info["name"],
                "base_url": info["base_url"],
                "rating": info["rating"],
                "review_count": info["review_count"],
                "description": info["description"],
                "full_description": info.get("full_description"),
                "badges": info["badges"],
                "highlights": info.get("highlights", []),
                "location": info.get("location"),
                "shipping_info": info.get("shipping_info"),
                "shipping_rule": info.get("shipping_rule"),
                "return_policy": info.get("return_policy"),
                "rating_breakdown": info.get("rating_breakdown"),
                "contact_email": f"supporto@{sid}.com",
                "contact_phone": "+39 02 8295 1860",
                "social_instagram": f"@{sid}",
                "privacy_policy_url": info["base_url"],
                "terms_url": info["base_url"],
                "refund_policy": info.get("return_policy"),
                "shipping_policy": info.get("shipping_info"),
                "city_or_location": info.get("location"),
                "customer_reviews": [
                    {"author": "Cliente Verificato", "rating": 5.0, "text": "Esperienza d'acquisto eccellente, prodotti originali e spedizione rapida.", "date": "2 settimane fa"},
                    {"author": "Runner Appassionato", "rating": 4.9, "text": "Ottimo rapporto qualità/prezzo e servizio clienti sempre disponibile.", "date": "3 settimane fa"}
                ],
                "customer_photos": [p["image_url"] for p in prods if p.get("image_url")][:8],
                "total_offers": total_offers,
                "avg_discount": avg_discount,
                "min_price": min_price,
                "products": prods
            }

    # MARK: - Wishlist & Collections Methods

    def _seed_initial_wishlist_if_empty(self, conn: sqlite3.Connection):
        """Populate initial wishlist if empty to showcase saved products."""
        row = conn.execute("SELECT COUNT(*) FROM wishlist").fetchone()
        if row and row[0] > 0:
            return

        initial_collections = ["Tutti", "Sneakers", "Running", "Abbigliamento"]
        for c in initial_collections:
            conn.execute("INSERT OR IGNORE INTO collections (id, name) VALUES (?, ?)", (str(uuid.uuid4()), c))

        seed_items = [
            {
                "id": str(uuid.uuid4()),
                "product_id": "mihara-hank-og-sole",
                "canonical_name": "Maison Mihara Yasuhiro Hank",
                "brand": "Maison Mihara Yasuhiro",
                "store_name": "SneakerAsk",
                "current_price": 188.00,
                "original_price": 243.75,
                "discount_pct": 23.0,
                "image_url": "https://img.miharayasuhiro.jp/v2/product/A05FW702/cc_1.jpg",
                "product_url": "https://sneakerask.com",
                "selected_size": "36 EU",
                "collection_name": "Sneakers"
            },
            {
                "id": str(uuid.uuid4()),
                "product_id": "nb-740-marsh",
                "canonical_name": "Nuovo Balance 740 - Sale marine",
                "brand": "New Balance",
                "store_name": "Kith",
                "current_price": 145.00,
                "original_price": 165.00,
                "discount_pct": 12.0,
                "image_url": "https://www.sneakinpeace.com/cdn/shop/files/new-balance-740-white-marsh-green-sea-salt-low-top-sneakers-trainers-1_440x570.jpg",
                "product_url": "https://kith.com",
                "selected_size": "7.5",
                "collection_name": "Sneakers"
            },
            {
                "id": str(uuid.uuid4()),
                "product_id": "generic deviate nitro 4 [shoes] [Uomo]",
                "canonical_name": "Puma Deviate Nitro 4 Hyrox",
                "brand": "Puma",
                "store_name": "Maxi Sport",
                "current_price": 119.99,
                "original_price": 169.99,
                "discount_pct": 29.4,
                "image_url": "https://maxi.gumlet.io/media/catalog/product/cache/49229e27a07aec1fba01f3faa4d67bfd/p/u/puma-314155-deviate-nitro-4-hyrox-scarpe-running-uomo-052754101-01_1.jpg",
                "product_url": "https://maxisport.com",
                "selected_size": "42 EU",
                "collection_name": "Running"
            },
            {
                "id": str(uuid.uuid4()),
                "product_id": "generic clifton 11 [shoes] [Uomo]",
                "canonical_name": "Hoka Clifton 11 Wide",
                "brand": "Hoka",
                "store_name": "Cisalfa Sport",
                "current_price": 128.00,
                "original_price": 160.00,
                "discount_pct": 20.0,
                "image_url": "https://maxi.gumlet.io/media/catalog/product/cache/49229e27a07aec1fba01f3faa4d67bfd/h/o/hoka-1176572-clifton-11-scarpe-running-uomo-052835001-bblc_1.jpg",
                "product_url": "https://cisalfasport.it",
                "selected_size": "43 EU",
                "collection_name": "Running"
            },
            {
                "id": str(uuid.uuid4()),
                "product_id": "joma elite viii [top] [Uomo]",
                "canonical_name": "Joma Elite VIII Maglia Gara",
                "brand": "Joma",
                "store_name": "Mister Running",
                "current_price": 10.71,
                "original_price": 32.00,
                "discount_pct": 66.5,
                "image_url": "https://www.misterrunning.com/media/products/2021-media/joma-elite-viii-maglietta-da-running-uomo-navy-yellow-fluor-101929321_A-600x600.jpg",
                "product_url": "https://misterrunning.com",
                "selected_size": "L",
                "collection_name": "Abbigliamento"
            },
            {
                "id": str(uuid.uuid4()),
                "product_id": "mizuno printed [pants] [Donna]",
                "canonical_name": "Mizuno Printed Running Tights",
                "brand": "Mizuno",
                "store_name": "Mister Running",
                "current_price": 19.71,
                "original_price": 60.00,
                "discount_pct": 67.2,
                "image_url": "https://www.misterrunning.com/media/products/2023-media-06/mizuno-printed-tights-da-running-donna-nightshadow-blue-j2gba702-03_A-600x600.jpg",
                "product_url": "https://misterrunning.com",
                "selected_size": "M",
                "collection_name": "Abbigliamento"
            }
        ]

        for it in seed_items:
            conn.execute("""
                INSERT OR IGNORE INTO wishlist (id, product_id, canonical_name, brand, store_name, current_price, original_price, discount_pct, image_url, product_url, selected_size, collection_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                it["id"], it["product_id"], it["canonical_name"], it["brand"], it["store_name"],
                it["current_price"], it["original_price"], it["discount_pct"], it["image_url"],
                it["product_url"], it["selected_size"], it["collection_name"]
            ))

    def get_wishlist(self, collection_name: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieve all wishlist products from the database, optionally filtered by collection."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_wishlist(collection_name=collection_name)
            except Exception as e:
                logger.error(f"[Database] Error get_wishlist from Supabase: {e}")

        with self.get_connection() as conn:
            if collection_name and collection_name.lower() != "tutti":
                sql = "SELECT * FROM wishlist WHERE LOWER(collection_name) = LOWER(?) ORDER BY created_at DESC"
                rows = conn.execute(sql, (collection_name,)).fetchall()
            else:
                sql = "SELECT * FROM wishlist ORDER BY created_at DESC"
                rows = conn.execute(sql).fetchall()

            results = []
            for r in rows:
                d = dict(r)
                # Compute formatted fields
                d["currentBestPrice"] = d["current_price"]
                d["originalPrice"] = d["original_price"]
                d["discountPct"] = d["discount_pct"]
                d["bestStore"] = d["store_name"]
                d["bestStoreUrl"] = d["product_url"]
                d["selectedSize"] = d["selected_size"]
                d["collectionName"] = d["collection_name"]
                results.append(d)
            return results

    def add_to_wishlist(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """Save a product to the wishlist table in the database."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.add_to_wishlist(item)
            except Exception as e:
                logger.error(f"[Database] Error add_to_wishlist to Supabase: {e}")

        with self.get_connection() as conn:
            item_id = item.get("id") or str(uuid.uuid4())
            canonical_name = item.get("canonical_name") or item.get("title") or "Articolo"
            brand = item.get("brand")
            store_name = item.get("store_name") or item.get("bestStore") or item.get("store") or "Store Partner"
            current_price = float(item.get("current_price", item.get("currentBestPrice", 0.0)) or 0.0)
            original_price = item.get("original_price") or item.get("originalPrice") or item.get("initialPrice")
            if original_price is not None:
                original_price = float(original_price)
            discount_pct = item.get("discount_pct") or item.get("discountPct")
            if discount_pct is not None:
                discount_pct = float(discount_pct)
            elif original_price and original_price > current_price and original_price > 0:
                discount_pct = round(((original_price - current_price) / original_price) * 100.0, 1)

            image_url = item.get("image_url")
            product_url = item.get("product_url") or item.get("bestStoreUrl")
            selected_size = item.get("selected_size") or item.get("selectedSize") or "Standard"
            collection_name = item.get("collection_name") or item.get("collectionName") or "Tutti"

            conn.execute("""
                INSERT INTO wishlist (id, product_id, canonical_name, brand, store_name, current_price, original_price, discount_pct, image_url, product_url, selected_size, collection_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(canonical_name) DO UPDATE SET
                    store_name = excluded.store_name,
                    current_price = excluded.current_price,
                    original_price = COALESCE(excluded.original_price, wishlist.original_price),
                    discount_pct = COALESCE(excluded.discount_pct, wishlist.discount_pct),
                    image_url = COALESCE(excluded.image_url, wishlist.image_url),
                    selected_size = COALESCE(excluded.selected_size, wishlist.selected_size),
                    collection_name = COALESCE(excluded.collection_name, wishlist.collection_name)
            """, (
                item_id, item.get("product_id"), canonical_name, brand, store_name,
                current_price, original_price, discount_pct, image_url, product_url,
                selected_size, collection_name
            ))
            return item

    def remove_from_wishlist(self, identifier: str) -> bool:
        """Remove a product from the wishlist by id or canonical_name."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.remove_from_wishlist(identifier)
            except Exception as e:
                logger.error(f"[Database] Error remove_from_wishlist from Supabase: {e}")

        with self.get_connection() as conn:
            res = conn.execute("DELETE FROM wishlist WHERE id = ? OR LOWER(canonical_name) = LOWER(?)", (identifier, identifier))
            return res.rowcount > 0

    def get_collections(self) -> List[Dict[str, Any]]:
        """Return all collections with product counts."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_collections()
            except Exception as e:
                logger.error(f"[Database] Error get_collections from Supabase: {e}")

        with self.get_connection() as conn:
            rows = conn.execute("""
                SELECT c.name, COUNT(w.id) as item_count 
                FROM collections c 
                LEFT JOIN wishlist w ON LOWER(c.name) = LOWER(w.collection_name) 
                GROUP BY c.name
                ORDER BY c.created_at ASC
            """).fetchall()
            return [dict(r) for r in rows]

    def create_collection(self, name: str) -> Dict[str, Any]:
        """Create a new collection category."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.create_collection(name)
            except Exception as e:
                logger.error(f"[Database] Error create_collection in Supabase: {e}")

        with self.get_connection() as conn:
            col_id = str(uuid.uuid4())
            conn.execute("INSERT OR IGNORE INTO collections (id, name) VALUES (?, ?)", (col_id, name))
            return {"id": col_id, "name": name}

    def delete_collection(self, name: str) -> bool:
        """Delete a collection and reassign items to 'Tutti'."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.delete_collection(name)
            except Exception as e:
                logger.error(f"[Database] Error delete_collection in Supabase: {e}")

        try:
            with self.get_connection() as conn:
                conn.execute("DELETE FROM collections WHERE LOWER(name) = LOWER(?)", (name,))
                conn.execute("UPDATE wishlist SET collection_name = 'Tutti' WHERE LOWER(collection_name) = LOWER(?)", (name,))
        except Exception as e:
            logger.warning(f"[Database] Local SQLite delete_collection note: {e}")
        return True

    def update_wishlist_item_collection(self, canonical_name: str, collection_name: str) -> bool:
        """Move an item to a new collection."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.update_wishlist_item_collection(canonical_name, collection_name)
            except Exception as e:
                logger.error(f"[Database] Error update_wishlist_item_collection in Supabase: {e}")

        try:
            with self.get_connection() as conn:
                conn.execute("UPDATE wishlist SET collection_name = ? WHERE LOWER(canonical_name) = LOWER(?)", (collection_name, canonical_name))
        except Exception as e:
            logger.warning(f"[Database] Local SQLite update_wishlist note: {e}")
        return True

    def get_followed_stores(self) -> List[Dict[str, Any]]:
        """Retrieve all followed stores."""
        if self.use_supabase and self.supabase:
            try:
                res = self.supabase.client.table("followed_stores").select("*").order("created_at", desc=True).execute()
                if res.data:
                    return res.data
            except Exception as e:
                logger.error(f"[Database] Error get_followed_stores in Supabase: {e}")

        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM followed_stores ORDER BY created_at DESC").fetchall()
            return [dict(r) for r in rows]

    def follow_store(self, store_id: str, store_name: str, store_logo: Optional[str] = None) -> bool:
        """Follow a store."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.client.table("followed_stores").upsert({
                    "store_id": store_id,
                    "store_name": store_name,
                    "store_logo": store_logo,
                    "device_id": "default_device"
                }, on_conflict="device_id,store_id").execute()
            except Exception as e:
                logger.error(f"[Database] Error follow_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO followed_stores (id, store_id, store_name, store_logo)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(store_id) DO UPDATE SET store_name=excluded.store_name, store_logo=excluded.store_logo
            """, (str(uuid.uuid4()), store_id, store_name, store_logo))
        return True

    def unfollow_store(self, store_id: str) -> bool:
        """Unfollow a store."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.client.table("followed_stores").delete().eq("store_id", store_id).execute()
            except Exception as e:
                logger.error(f"[Database] Error unfollow_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("DELETE FROM followed_stores WHERE LOWER(store_id) = LOWER(?)", (store_id,))
        return True

    def get_recent_activity(self, limit: int = 30) -> List[Dict[str, Any]]:
        """Retrieve recent activity items."""
        if self.use_supabase and self.supabase:
            try:
                res = self.supabase.client.table("recent_activity").select("*").order("created_at", desc=True).limit(limit).execute()
                if res.data:
                    return res.data
            except Exception as e:
                logger.error(f"[Database] Error get_recent_activity in Supabase: {e}")

        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM recent_activity ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
            return [dict(r) for r in rows]

    def record_recent_activity(self, item: Dict[str, Any]) -> bool:
        """Record a product view or search activity."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.client.table("recent_activity").insert({
                    "activity_type": item.get("activity_type", "product"),
                    "title": item.get("title", ""),
                    "subtitle": item.get("subtitle"),
                    "image_url": item.get("image_url"),
                    "price": item.get("price"),
                    "original_price": item.get("original_price"),
                    "store_id": item.get("store_id"),
                    "store_name": item.get("store_name"),
                    "device_id": "default_device"
                }).execute()
            except Exception as e:
                logger.error(f"[Database] Error record_recent_activity in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO recent_activity (id, activity_type, title, subtitle, image_url, price, original_price, store_id, store_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                str(uuid.uuid4()),
                item.get("activity_type", "product"),
                item.get("title", ""),
                item.get("subtitle"),
                item.get("image_url"),
                item.get("price"),
                item.get("original_price"),
                item.get("store_id"),
                item.get("store_name")
            ))
        return True

    # MARK: - Stores, Hidden Stores & Store Reports

    def upsert_store(self, store_data: Dict[str, Any]) -> bool:
        """Upsert store metadata to Supabase and SQLite."""
        s_id = store_data.get("id", "").lower().strip()
        if not s_id:
            return False

        if self.use_supabase and self.supabase:
            try:
                self.supabase.upsert_store(store_data)
            except Exception as e:
                logger.error(f"[Database] Error upsert_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO stores (id, name, rating, review_count, formatted_review_count, card_theme, accent_color, logo_url, base_url, free_shipping_threshold, standard_shipping_cost, courier, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    rating = excluded.rating,
                    review_count = excluded.review_count,
                    formatted_review_count = excluded.formatted_review_count,
                    card_theme = excluded.card_theme,
                    accent_color = excluded.accent_color,
                    logo_url = excluded.logo_url,
                    base_url = excluded.base_url,
                    free_shipping_threshold = excluded.free_shipping_threshold,
                    standard_shipping_cost = excluded.standard_shipping_cost,
                    courier = excluded.courier,
                    updated_at = CURRENT_TIMESTAMP
            """, (
                s_id,
                store_data.get("name", s_id.title()),
                store_data.get("rating", 4.8),
                store_data.get("review_count", 1200),
                store_data.get("formatted_review_count"),
                store_data.get("card_theme", "white"),
                store_data.get("accent_color"),
                store_data.get("logo_url"),
                store_data.get("base_url"),
                store_data.get("free_shipping_threshold"),
                store_data.get("standard_shipping_cost"),
                store_data.get("courier")
            ))
        return True

    def get_stores(self) -> List[Dict[str, Any]]:
        """Retrieve all store metadata from Supabase or SQLite."""
        if self.use_supabase and self.supabase:
            try:
                data = self.supabase.get_stores()
                if data:
                    return data
            except Exception as e:
                logger.error(f"[Database] Error get_stores from Supabase: {e}")

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM stores ORDER BY rating DESC")
            rows = cursor.fetchall()
            return [dict(r) for r in rows]

    def get_store(self, store_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve specific store metadata."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                st = self.supabase.get_store(s_id)
                if st:
                    return st
            except Exception as e:
                logger.error(f"[Database] Error get_store from Supabase: {e}")

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM stores WHERE LOWER(id) = LOWER(?)", (s_id,))
            row = cursor.fetchone()
            return dict(row) if row else None

    def hide_store(self, store_id: str, store_name: Optional[str] = None) -> bool:
        """Mark store as hidden from suggestions."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                self.supabase.hide_store(s_id, store_name)
            except Exception as e:
                logger.error(f"[Database] Error hide_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO hidden_stores (id, store_id, store_name)
                VALUES (?, ?, ?)
                ON CONFLICT(store_id) DO NOTHING
            """, (str(uuid.uuid4()), s_id, store_name))
        return True

    def unhide_store(self, store_id: str) -> bool:
        """Remove store from hidden list."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                self.supabase.unhide_store(s_id)
            except Exception as e:
                logger.error(f"[Database] Error unhide_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("DELETE FROM hidden_stores WHERE LOWER(store_id) = LOWER(?)", (s_id,))
        return True

    def get_hidden_stores(self) -> List[str]:
        """Retrieve list of hidden store ids."""
        if self.use_supabase and self.supabase:
            try:
                data = self.supabase.get_hidden_stores()
                if data:
                    return data
            except Exception as e:
                logger.error(f"[Database] Error get_hidden_stores in Supabase: {e}")

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT store_id FROM hidden_stores")
            rows = cursor.fetchall()
            return [r["store_id"].lower() for r in rows]

    def report_store(self, store_id: str, store_name: str, reason: str, details: Optional[str] = None) -> bool:
        """Record store report in database."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                self.supabase.report_store(s_id, store_name, reason, details)
            except Exception as e:
                logger.error(f"[Database] Error report_store in Supabase: {e}")

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO store_reports (id, store_id, store_name, reason, details)
                VALUES (?, ?, ?, ?, ?)
            """, (str(uuid.uuid4()), s_id, store_name, reason, details))
        return True

    def get_store_reviews(self, store_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieve real reviews for a store."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                data = self.supabase.get_store_reviews(s_id, limit=limit)
                if data:
                    return data
            except Exception as e:
                logger.error(f"[Database] Error get_store_reviews in Supabase: {e}")

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, store_id, author_name, rating, review_text, created_at
                FROM store_reviews
                WHERE LOWER(store_id) = LOWER(?)
                ORDER BY created_at DESC
                LIMIT ?
            """, (s_id, limit))
            return [dict(r) for r in cursor.fetchall()]

    def add_store_review(self, store_id: str, author_name: str, rating: int, review_text: str, device_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Insert user review for a store."""
        s_id = store_id.lower().strip()
        if self.use_supabase and self.supabase:
            try:
                res = self.supabase.add_store_review(s_id, author_name, rating, review_text, device_id)
                if res:
                    return res
            except Exception as e:
                logger.error(f"[Database] Error add_store_review in Supabase: {e}")

        rev_id = str(uuid.uuid4())
        payload = {
            "id": rev_id,
            "store_id": s_id,
            "author_name": author_name.strip() or "Runner",
            "rating": max(1, min(5, int(rating))),
            "review_text": review_text.strip(),
            "device_id": device_id or "default_device",
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO store_reviews (id, store_id, author_name, rating, review_text, device_id)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (rev_id, s_id, payload["author_name"], payload["rating"], payload["review_text"], payload["device_id"]))
        return payload

    # MARK: - Affiliate Clicks

    def record_affiliate_click(
        self,
        target_url: str,
        store_id: Optional[str] = None,
        offer_id: Optional[str] = None,
        monetized_url: Optional[str] = None,
        cuid: Optional[str] = None,
        source: Optional[str] = None,
        device_id: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> bool:
        """Record outbound affiliate click in Supabase and/or SQLite."""
        if self.use_supabase and self.supabase:
            try:
                self.supabase.record_affiliate_click(
                    target_url=target_url,
                    store_id=store_id,
                    offer_id=offer_id,
                    monetized_url=monetized_url,
                    cuid=cuid,
                    source=source,
                    device_id=device_id,
                    user_agent=user_agent,
                )
            except Exception as e:
                logger.warning(f"[AffiliateClick] Supabase record error: {e}")

        try:
            with self.get_connection() as conn:
                click_id = str(uuid.uuid4())
                conn.execute("""
                    INSERT INTO affiliate_clicks (id, store_id, offer_id, target_url, monetized_url, cuid, source, device_id, user_agent)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (click_id, store_id, offer_id, target_url, monetized_url, cuid, source, device_id, user_agent))
                conn.commit()
            return True
        except Exception as e:
            logger.error(f"[AffiliateClick] SQLite record error: {e}")
            return False

    def get_affiliate_click_stats(self, limit: int = 100) -> Dict[str, Any]:
        """Get affiliate click statistics from Supabase or SQLite."""
        if self.use_supabase and self.supabase:
            try:
                return self.supabase.get_affiliate_click_stats(limit=limit)
            except Exception as e:
                logger.warning(f"[AffiliateStats] Supabase error: {e}")

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM affiliate_clicks")
            total = cursor.fetchone()[0]

            cursor.execute("""
                SELECT COALESCE(store_id, 'unknown'), COUNT(*)
                FROM affiliate_clicks
                GROUP BY store_id
                ORDER BY COUNT(*) DESC
            """)
            by_store = {row[0]: row[1] for row in cursor.fetchall()}

            cursor.execute("""
                SELECT id, store_id, offer_id, target_url, cuid, source, device_id, created_at
                FROM affiliate_clicks
                ORDER BY created_at DESC
                LIMIT ?
            """, (min(limit, 25),))
            recent = [dict(row) for row in cursor.fetchall()]

            return {
                "total_clicks": total,
                "by_store": by_store,
                "recent_clicks": recent,
            }


