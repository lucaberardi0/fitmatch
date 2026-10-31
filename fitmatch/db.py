import sqlite3
import os
import logging
from datetime import datetime
from typing import Optional, List, Dict, Any
from fitmatch.models import Offer, MatchedProductGroup

logger = logging.getLogger("fitmatch.db")

DB_DIR = "data"
DB_PATH = os.path.join(DB_DIR, "fitmatch.db")


class Database:
    """SQLite Database manager for indexing products, store offers and price history."""

    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self.init_schema()

    def get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
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

                CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand);
                CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
                CREATE INDEX IF NOT EXISTS idx_offers_product_id ON store_offers(product_id);
                CREATE INDEX IF NOT EXISTS idx_offers_store_id ON store_offers(store_id);
                CREATE INDEX IF NOT EXISTS idx_offers_price ON store_offers(current_price);
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
        with self.get_connection() as conn:
            # 1. Upsert product
            conn.execute("""
                INSERT INTO products (id, canonical_name, brand, category, gender, image_url, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    canonical_name = excluded.canonical_name,
                    brand = COALESCE(excluded.brand, products.brand),
                    image_url = COALESCE(products.image_url, excluded.image_url),
                    updated_at = CURRENT_TIMESTAMP
            """, (cluster_key, canonical_name, brand, category, gender, offer.image_url))

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
                offer.image_url,
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

    def get_stats(self) -> Dict[str, Any]:
        """Return catalog overview statistics."""
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

    def search_indexed(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        """Fast SQL query on pre-indexed products and their store offers."""
        with self.get_connection() as conn:
            words = query.strip().lower().split()
            where_clauses = ["(LOWER(p.canonical_name) LIKE ? OR LOWER(COALESCE(p.brand, '')) LIKE ?)" for _ in words]
            params = []
            for w in words:
                params.extend([f"%{w}%", f"%{w}%"])

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

            for prod in products:
                offer_cur = conn.execute("""
                    SELECT store_id, store_name, current_price, original_price, discount_pct, product_url, image_url
                    FROM store_offers
                    WHERE product_id = ?
                    ORDER BY current_price ASC
                """, (prod["id"],))
                prod["offers"] = [dict(o) for o in offer_cur.fetchall()]

            return products
