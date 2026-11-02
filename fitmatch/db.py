import sqlite3
import os
import uuid
import logging
from datetime import datetime
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
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
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
                    crawled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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

                CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand);
                CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
                CREATE INDEX IF NOT EXISTS idx_offers_product_id ON store_offers(product_id);
                CREATE INDEX IF NOT EXISTS idx_offers_store_id ON store_offers(store_id);
                CREATE INDEX IF NOT EXISTS idx_offers_price ON store_offers(current_price);
                CREATE INDEX IF NOT EXISTS idx_wishlist_canonical ON wishlist(canonical_name);
                CREATE INDEX IF NOT EXISTS idx_wishlist_collection ON wishlist(collection_name);
            """)

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
                INSERT INTO products (id, canonical_name, brand, category, gender, image_url, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    canonical_name = excluded.canonical_name,
                    brand = COALESCE(excluded.brand, products.brand),
                    image_url = CASE 
                        WHEN products.image_url IS NOT NULL AND products.image_url LIKE 'http%' AND products.image_url NOT LIKE '%blank.gif%' THEN products.image_url
                        ELSE excluded.image_url
                    END,
                    updated_at = CURRENT_TIMESTAMP
            """, (cluster_key, canonical_name, brand, category, gender, clean_off_img))

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
                clean_off_img,
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
        duration_seconds: float
    ):
        """Record log of crawler job in database."""
        if self.use_supabase and self.supabase:
            self.supabase.record_crawl_log(store_id, category, items_found, duration_seconds)
            return

        with self.get_connection() as conn:
            conn.execute("""
                INSERT INTO crawl_logs (store_id, category, items_found, duration_seconds)
                VALUES (?, ?, ?, ?)
            """, (store_id, category, items_found, round(duration_seconds, 2)))
            conn.commit()

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
        store_id: Optional[str] = None,
        limit: int = 30
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
                    store_id=store_id,
                    limit=limit
                )
            except Exception as e:
                logger.error(f"[Database] Error search_smart from Supabase: {e}")

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
                where_clauses.append("LOWER(COALESCE(p.brand, '')) LIKE ?")
                params.append(f"%{brand.lower()}%")

            # 3. Category Filter
            if category and category.lower() not in ("all", "tutti"):
                where_clauses.append("p.category = ?")
                params.append(category.lower())

            # 4. Gender Filter
            if gender and gender.lower() in ("donna", "uomo"):
                where_clauses.append("(p.gender = ? OR p.gender = 'Unisex')")
                params.append(gender)

            # 5. Price bounds on the product's lowest offer
            if max_price:
                where_clauses.append("o.current_price <= ?")
                params.append(float(max_price))

            if min_price:
                where_clauses.append("o.current_price >= ?")
                params.append(float(min_price))

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
            "alltricks": "4.4"
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

                result.append({
                    "store_id": sid,
                    "store_name": sname,
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

            words = query.strip().lower().split()
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
            self._seed_initial_wishlist_if_empty(conn)

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
            self._seed_initial_wishlist_if_empty(conn)
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

