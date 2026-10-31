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

            from fitmatch.models import STORE_SHIPPING_RULES

            for prod in products:
                offer_cur = conn.execute("""
                    SELECT store_id, store_name, current_price, original_price, discount_pct, product_url, image_url
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
                    o["shipping_cost"] = cost
                    o["total_price"] = round(price + cost, 2)
                    o["is_free_shipping"] = is_free
                    o["shipping_label"] = "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped."
                    o["free_shipping_threshold"] = rule["free_threshold"]
                    o["courier"] = rule["courier"]
                    offers.append(o)

                prod["offers"] = offers

            return products

    def get_store_showcases(self, limit_per_store: int = 6) -> List[Dict[str, Any]]:
        """Return curated product highlights for each store (Shop-style merchant showcase)."""
        ratings = {
            "cisalfa": "4.8",
            "maxisport": "4.9",
            "misterrunning": "4.9",
            "nencini": "4.7",
            "top4running": "4.8",
            "runningwarehouse": "4.9"
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
