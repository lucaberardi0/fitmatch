import time
import logging
import urllib.parse
from typing import List, Dict, Any, Optional
from bs4 import BeautifulSoup
from fitmatch.db import Database
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import Offer
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

logger = logging.getLogger("fitmatch.crawler")


class CategoryCrawler:
    """Orchestrates comprehensive crawling of multi-store catalogs and indexes products in the database."""

    BATCH_SIZE = 40

    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()
        self.normalizer = ProductNormalizer()
        self.cisalfa = CisalfaScraper()
        self.maxisport = MaxiSportScraper()
        self.misterrunning = MisterRunningScraper()
        self.nencini = NenciniSportScraper()
        self.top4running = Top4RunningScraper()
        self.runningwarehouse = RunningWarehouseScraper()
        self.deporvillage = DeporvillageScraper()
        self.alltricks = AlltricksScraper()
        self.decathlon = DecathlonScraper()
        self.sportler = SportlerScraper()
        self.nike = NikeScraper()
        self.adidas = AdidasScraper()
        self.tradeinn = TradeinnScraper()
        self.df_sport = DFSportScraper()

    def _flush_batch(self, batch: List[Dict[str, Any]]) -> int:
        """Helper to flush pending offers to DB in a single transaction."""
        if not batch:
            return 0
        count = self.db.upsert_offers_batch(batch)
        batch.clear()
        return count

    def _detect_category(self, title: str) -> str:
        """Categorize product by title keywords into appropriate sports gear category."""
        tl = title.lower()
        if any(w in tl for w in [
            "garmin", "polar", "suunto", "coros", "smartwatch", "orologio", "gps", "cardio",
            "ciclocomputer", "fascia cardio", "edge", "fenix", "forerunner", "vantage", "grit x", "instinct"
        ]):
            return "gps_watch"
        if any(w in tl for w in [
            "oakley", "occhiali", "lenti", "prizm", "bliz", "rudy", "maschera", "sunglasses",
            "sutro", "radar", "jawbreaker", "evzero", "flight jacket"
        ]):
            return "eyewear"
        if any(w in tl for w in [
            "zaino", "gilet", "adv skin", "active skin", "flask", "borraccia", "idratazione",
            "camelbak", "cintura", "soft flask", "running vest"
        ]):
            return "hydration"
        if any(w in tl for w in [
            "theragun", "hyperice", "massaggiante", "recupero", "loop band", "elastico", "elastici",
            "manubri", "kettlebell", "foam roller", "tappetino", "pesi", "corda saltare", "compex",
            "gun", "percussione"
        ]):
            return "fitness"
        if any(w in tl for w in [
            "gel", "enervit", "isocarb", "barretta", "barrette", "proteine", "whey", "creatina",
            "integratore", "maltodestrine", "sali minerali", "sis", "maurten", "energetico",
            "hydrogel", "bcaa"
        ]):
            return "nutrition"
        if any(w in tl for w in [
            "padel", "racchetta", "pala", "overgrip", "tubo palline", "bullpadel", "nox", "starvie",
            "siux", "kuikma", "babolat technical", "head speed", "head gravity", "wilson blade"
        ]):
            return "padel"
        if any(w in tl for w in [
            "ciclismo", "bici", "ciclocomputer", "rullo", "smart trainer", "kickr", "flux", "tacx",
            "wahoo", "favero", "assioma", "kask", "poc ", "castelli", "sportful", "santini",
            "salopette", "shimano", "sram", "campagnolo", "copertone", "casco bici", "gravel"
        ]):
            return "cycling"
        if any(w in tl for w in [
            "casco", "pompa", "luce", "bici",
            "kask", "poc ", "copertone", "salopette", "shimano"
        ]):
            return "gear"
        if any(w in tl for w in [
            "trail", "speedcross", "peregrine", "mafate", "cascadia", "caldera", "trabuco",
            "fujitrail", "bushido", "mutant", "catamount", "ultra raptor", "wildhorse",
            "pegasus trail", "terrex agravic", "terrex speed", "sense ride", "lone peak",
            "speedgoat", "challenger atr", "stinson", "hierro", "norvan"
        ]):
            return "trail_running"
        if any(w in tl for w in [
            "trekking", "outdoor", "scarpon", "escursionismo", "puez", "salewa", "meindl",
            "tx4", "tx5", "lowa", "moab", "merrell", "columbia", "mojito", "ribelle",
            "hardshell", "gore-tex paclite", "3l", "impermeabile", "antipioggia"
        ]):
            return "outdoor"
        if any(w in tl for w in [
            "maglia", "t-shirt", "pantaloncini", "shorts", "giacca", "leggings", "calze",
            "canotta", "antivento", "felpa", "tight", "windstopper", "thermo", "intimo",
            "compressione", "bra", "reggiseno", "boxer", "calzamaglia"
        ]):
            return "apparel"
        return "running_shoes"

    def crawl_cisalfa(self, max_items: int = 500) -> int:
        """Crawl Cisalfa multi-department sports catalog with deep pagination."""
        start_time = time.time()
        logger.info(f"[Cisalfa] Starting catalog crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.cisalfasport.it/it-it/sport/running/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/outdoor/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/running/accessori/",
            "https://www.cisalfasport.it/it-it/sport/running/abbigliamento/",
            "https://www.cisalfasport.it/it-it/scarpe/sneakers/",
            "https://www.cisalfasport.it/it-it/sport/tennis-padel/",
            "https://www.cisalfasport.it/it-it/sport/ciclismo/",
            "https://www.cisalfasport.it/it-it/sport/training-palestra/",
            "https://www.cisalfasport.it/it-it/sport/calcio/scarpe-calcio/"
        ]
        page_size = 36
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for base_cat_url in base_cat_urls:
            offset = 0
            empty_pages = 0
            while total_indexed < max_items:
                url = f"{base_cat_url}?start={offset}&sz={page_size}"
                html = self.cisalfa._fetch_html(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "html.parser")
                tiles = soup.select(".product-tile")
                if not tiles:
                    empty_pages += 1
                    if empty_pages >= 2:
                        break
                    offset += page_size
                    continue

                empty_pages = 0
                items_in_page = 0
                for tile in tiles:
                    try:
                        title_el = tile.select_one(".cc-tile__title, .product-tile-title, [itemprop='name']")
                        link_el = tile.select_one("a.cc-tile__url-absolute, a.link")
                        if not title_el or not link_el or not link_el.get("href"):
                            continue

                        title = title_el.get_text(strip=True)
                        raw_href = link_el["href"]
                        product_url = urllib.parse.urljoin(self.cisalfa.base_url, raw_href)

                        # Price
                        price = None
                        sales_val = tile.select_one(".sales .value[content], .sales [content]")
                        if sales_val and sales_val.get("content"):
                            price = self.cisalfa.parse_price(sales_val["content"])
                        if not price:
                            p_text = tile.select_one(".sales, .price")
                            price = self.cisalfa.parse_price(p_text.get_text()) if p_text else None
                        if not price:
                            continue

                        # Original price
                        orig_price = None
                        s_val = tile.select_one("s.value[content], .strike .value[content]")
                        if s_val and s_val.get("content"):
                            orig_price = self.cisalfa.parse_price(s_val["content"])

                        # Image
                        img_el = tile.select_one("img")
                        img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

                        brand = None
                        if "/it-it/" in raw_href:
                            parts = raw_href.split("/")
                            if len(parts) >= 3 and parts[2] not in ("sport", "donna", "uomo", "search"):
                                brand = parts[2].capitalize()
                        brand = self.normalizer.extract_brand(title, brand)

                        pid_el = tile.select_one("[data-itemid]")
                        pid = pid_el["data-itemid"] if pid_el and pid_el.get("data-itemid") else None

                        offer = Offer(
                            store_id=self.cisalfa.store_id,
                            store_name=self.cisalfa.store_name,
                            product_id=pid,
                            title=title,
                            brand=brand,
                            price=price,
                            original_price=orig_price,
                            url=product_url,
                            image_url=img_url,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": brand,
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        items_in_page += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception as e:
                        logger.debug(f"[Cisalfa] Item parse error: {e}")
                        continue

                if items_in_page == 0:
                    break

                offset += page_size
                time.sleep(0.2)
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("cisalfa", "catalog", total_indexed, duration)
        logger.info(f"[Cisalfa] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_maxisport(self, max_items: int = 500) -> int:
        """Crawl Maxi Sport multi-department sports catalog with pagination."""
        start_time = time.time()
        logger.info(f"[Maxi Sport] Starting catalog crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.maxisport.com/running-scarpe-maxi-promo/",
            "https://www.maxisport.com/running-scarpe-trail-running/",
            "https://www.maxisport.com/running-scarpe-uomo/",
            "https://www.maxisport.com/running-scarpe-donna/",
            "https://www.maxisport.com/outdoor-scarpe-trekking/",
            "https://www.maxisport.com/running-accessori/",
            "https://www.maxisport.com/sneaker/",
            "https://www.maxisport.com/padel/",
            "https://www.maxisport.com/ciclismo/"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for base_cat_url in base_cat_urls:
            page = 1
            while total_indexed < max_items:
                url = f"{base_cat_url}?p={page}"
                html = self.maxisport._fetch_html(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "html.parser")
                items = soup.select(".item.product.product-item")
                if not items:
                    break

                items_in_page = 0
                for item in items:
                    try:
                        link_el = item.select_one("a.product-item-link")
                        if not link_el or not link_el.get("href"):
                            continue

                        title = link_el.get_text(strip=True)
                        product_url = link_el["href"]

                        # Price
                        price = None
                        p_wrap = item.select_one("[data-price-type='finalPrice']")
                        if p_wrap and p_wrap.has_attr("data-price-amount"):
                            price = self.maxisport.parse_price(p_wrap["data-price-amount"])
                        if not price:
                            continue

                        orig_price = None
                        o_wrap = item.select_one("[data-price-type='oldPrice']")
                        if o_wrap and o_wrap.has_attr("data-price-amount"):
                            orig_price = self.maxisport.parse_price(o_wrap["data-price-amount"])

                        img_el = item.select_one("img.product-image-photo, img")
                        img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

                        brand = None
                        if "/" in product_url:
                            slug = product_url.rstrip("/").split("/")[-1]
                            slug_parts = slug.split("-")
                            if slug_parts:
                                brand = slug_parts[0].capitalize()
                        brand = self.normalizer.extract_brand(title, brand)

                        pid_el = item.select_one("[data-product-id]")
                        pid = pid_el["data-product-id"] if pid_el and pid_el.get("data-product-id") else None

                        offer = Offer(
                            store_id=self.maxisport.store_id,
                            store_name=self.maxisport.store_name,
                            product_id=pid,
                            title=title,
                            brand=brand,
                            price=price,
                            original_price=orig_price,
                            url=product_url,
                            image_url=img_url,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": brand,
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        items_in_page += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue

                if items_in_page == 0:
                    break

                page += 1
                time.sleep(0.2)
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("maxisport", "catalog", total_indexed, duration)
        logger.info(f"[Maxi Sport] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_misterrunning(self, max_items: int = 500) -> int:
        """Crawl Mister Running via Clerk API with full pagination across sports gear categories."""
        start_time = time.time()
        logger.info(f"[Mister Running] Starting catalog crawl (target: {max_items} items)...")
        import json
        batch_size = 50
        total_indexed = 0
        batch: List[Dict[str, Any]] = []
        queries = [
            "running", "scarpe", "trail", "trekking", "outdoor", "gore-tex",
            "abbigliamento", "maglia termica", "shorts", "giacca antivento",
            "garmin", "polar", "coros", "zaino idratazione",
            "asics", "hoka", "nike", "adidas", "salomon", "saucony", "on running", "brooks"
        ]

        for q in queries:
            offset = 0
            while total_indexed < max_items:
                params = {
                    "key": self.misterrunning.clerk_key,
                    "query": q,
                    "limit": batch_size,
                    "offset": offset,
                    "attributes": json.dumps(["name", "price", "list_price", "image", "url", "brand", "id", "sizes"])
                }
                data = self.misterrunning._fetch_json(self.misterrunning.api_url, params=params)
                if not data or not isinstance(data, dict):
                    break

                products = data.get("product_data", [])
                if not products:
                    break

                for p in products:
                    try:
                        name = p.get("name")
                        price = self.misterrunning.parse_price(p.get("price"))
                        url = p.get("url")
                        if not name or not price or not url:
                            continue

                        orig_price = self.misterrunning.parse_price(p.get("list_price"))
                        brand = self.normalizer.extract_brand(name, p.get("brand"))
                        image = p.get("image")
                        pid = str(p.get("id")) if p.get("id") else None

                        raw_sizes = p.get("sizes", [])
                        sizes = [str(s).strip() for s in raw_sizes if s]

                        offer = Offer(
                            store_id=self.misterrunning.store_id,
                            store_name=self.misterrunning.store_name,
                            product_id=pid,
                            title=name,
                            brand=brand,
                            price=price,
                            original_price=orig_price,
                            url=url,
                            image_url=image,
                            available_sizes=sizes,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": brand,
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue

                offset += batch_size
                time.sleep(0.1)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("misterrunning", "catalog", total_indexed, duration)
        logger.info(f"[Mister Running] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_nencini(self, max_items: int = 500) -> int:
        """Crawl Nencini Sport catalog with pagination across departments."""
        start_time = time.time()
        logger.info(f"[Nencini Sport] Starting category crawl (target: {max_items} items)...")
        self.nencini._ensure_session()
        base_cat_urls = [
            "https://www.nencinisport.it/it/sport/running/scarpe/",
            "https://www.nencinisport.it/it/sport/running/abbigliamento/",
            "https://www.nencinisport.it/it/sport/running/accessori/",
            "https://www.nencinisport.it/it/sport/outdoor/scarpe/",
            "https://www.nencinisport.it/it/sport/ciclismo/",
            "https://www.nencinisport.it/it/sport/padel/",
            "https://www.nencinisport.it/it/sneakers/"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for base_cat_url in base_cat_urls:
            page = 1
            while total_indexed < max_items:
                url = f"{base_cat_url}?page={page}"
                html = self.nencini._fetch_html(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "html.parser")
                cards = soup.select(".product-card")
                if not cards:
                    break

                items_in_page = 0
                for card in cards:
                    try:
                        link_el = card.select_one("a.card-img-link") or card.select_one(".product-title a")
                        if not link_el or not link_el.get("href"):
                            continue

                        raw_href = link_el["href"]
                        product_url = urllib.parse.urljoin(self.nencini.base_url, raw_href)

                        title = None
                        if link_el.has_attr("data-gtmname"):
                            title = link_el["data-gtmname"].strip()
                        if not title:
                            t_el = card.select_one(".product-title a, .product-title")
                            title = t_el.get_text(strip=True) if t_el else None

                        price = None
                        if link_el.has_attr("data-gtmprice"):
                            price = self.nencini.parse_price(link_el["data-gtmprice"])
                        if not price:
                            p_el = card.select_one(".price, .current-price")
                            price = self.nencini.parse_price(p_el.get_text()) if p_el else None

                        if not title or not price:
                            continue

                        orig_price = None
                        old_p_el = card.select_one(".old-price, .regular-price")
                        if old_p_el:
                            orig_price = self.nencini.parse_price(old_p_el.get_text())

                        brand = None
                        if link_el.has_attr("data-gtmbrand"):
                            brand = link_el["data-gtmbrand"].strip()
                        brand = self.normalizer.extract_brand(title, brand)

                        img_el = card.select_one("img.img-fluid, img")
                        img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

                        pid = None
                        if link_el.has_attr("data-gtmid"):
                            pid = str(link_el["data-gtmid"])

                        offer = Offer(
                            store_id=self.nencini.store_id,
                            store_name=self.nencini.store_name,
                            product_id=pid,
                            title=title,
                            brand=brand,
                            price=price,
                            original_price=orig_price,
                            url=product_url,
                            image_url=img_url,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": brand,
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        items_in_page += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue

                if items_in_page == 0:
                    break

                page += 1
                time.sleep(0.2)
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("nencini", "catalog", total_indexed, duration)
        logger.info(f"[Nencini Sport] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_top4running(self, max_items: int = 500) -> int:
        """Crawl Top4Running catalog via Luigi's Box API with pagination."""
        start_time = time.time()
        logger.info(f"[Top4Running] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []
        queries = [
            "running", "scarpe", "trail", "trekking", "gore-tex", "maratona", "abbigliamento",
            "nike", "asics", "adidas", "hoka", "salomon", "saucony", "on running",
            "brooks", "puma", "garmin", "polar", "coros", "zaino", "maglia termica"
        ]

        for q in queries:
            page = 1
            while total_indexed < max_items:
                params = {
                    "tracker_id": self.top4running.tracker_id,
                    "q": q,
                    "size": 50,
                    "page": page
                }
                data = self.top4running._fetch_json(self.top4running.api_url, params=params)
                if not data or not isinstance(data, dict):
                    break

                hits = data.get("results", {}).get("hits", [])
                if not hits:
                    break

                hits_found = 0
                for h in hits:
                    attrs = h.get("attributes", {})
                    title = attrs.get("title")
                    price = self.top4running.parse_price(attrs.get("price_amount"))
                    raw_url = h.get("url")
                    if not title or not price or not raw_url:
                        continue

                    brand_raw = attrs.get("brand")
                    brand = brand_raw[0] if isinstance(brand_raw, list) and brand_raw else (brand_raw if isinstance(brand_raw, str) else None)
                    brand = self.normalizer.extract_brand(title, brand)

                    full_title = f"{brand} {title}" if brand and not title.lower().startswith(brand.lower()) else title
                    orig_price = self.top4running.parse_price(attrs.get("price_old_amount"))
                    img_url = attrs.get("image_link")
                    product_url = urllib.parse.urljoin(self.top4running.base_url, raw_url)
                    pid = str(h.get("id") or attrs.get("id") or "")

                    offer = Offer(
                        store_id=self.top4running.store_id,
                        store_name=self.top4running.store_name,
                        product_id=pid,
                        title=full_title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=product_url,
                        image_url=img_url,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })

                    total_indexed += 1
                    hits_found += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break

                if hits_found == 0:
                    break

                page += 1
                time.sleep(0.1)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("top4running", "catalog", total_indexed, duration)
        logger.info(f"[Top4Running] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_runningwarehouse(self, max_items: int = 500) -> int:
        """Crawl Running Warehouse Europe catalog across all departments."""
        start_time = time.time()
        logger.info(f"[Running Warehouse] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []
        cat_urls = [
            "https://www.runningwarehouse.eu/catpage-RWMRSSALE-EN.html",
            "https://www.runningwarehouse.eu/catpage-RWWRSSALE-EN.html",
            "https://www.runningwarehouse.eu/catpage-MENRWH-EN.html",
            "https://www.runningwarehouse.eu/catpage-WOMENRWH-EN.html",
            "https://www.runningwarehouse.eu/catpage-TRMRUN-EN.html",
            "https://www.runningwarehouse.eu/catpage-TRWRUN-EN.html",
            "https://www.runningwarehouse.eu/catpage-RUNMAPP-EN.html",
            "https://www.runningwarehouse.eu/catpage-RUNWAPP-EN.html",
            "https://www.runningwarehouse.eu/catpage-GEAR-EN.html"
        ]

        for cat_url in cat_urls:
            html = self.runningwarehouse._fetch_html(cat_url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")
            cells = soup.select(".cattable-wrap-cell")

            for cell in cells:
                try:
                    name_el = cell.select_one(".cattable-wrap-cell-info strong a, .cattable-wrap-cell-info a")
                    if not name_el or not name_el.get("href"):
                        continue

                    title = name_el.get_text(strip=True)
                    raw_href = name_el["href"]
                    product_url = urllib.parse.urljoin(self.runningwarehouse.base_url, raw_href)

                    # Prices
                    p_text = None
                    price_wrap = cell.select_one(".cattable-wrap-cell-info-price")
                    if price_wrap:
                        p_text = price_wrap.get_text()

                    price = self.runningwarehouse.parse_price(p_text) if p_text else None
                    if not price:
                        continue

                    orig_price = None
                    if price_wrap:
                        strike_el = price_wrap.select_one("span.strike, strike, del")
                        if strike_el:
                            orig_price = self.runningwarehouse.parse_price(strike_el.get_text())

                    brand = self.normalizer.extract_brand(title)
                    pid = None
                    if "descpage-" in product_url:
                        pid = product_url.split("descpage-")[-1].split(".")[0]

                    img_el = cell.select_one("img")
                    raw_img = None
                    if img_el:
                        raw_img = img_el.get("src")
                        if not raw_img or "blank.gif" in raw_img:
                            raw_img = img_el.get("data-src") or (img_el.get("data-srcset", "").split(" ")[0] if img_el.get("data-srcset") else None)
                    if (not raw_img or not raw_img.startswith("http")) and pid:
                        raw_img = f"https://img.runningwarehouse.eu/watermark/rs.php?path={pid}-1.jpg&nw=500"

                    img_url = raw_img if raw_img and raw_img.startswith("http") else None
                    if img_url and "nw=210" in img_url:
                        img_url = img_url.replace("nw=210", "nw=500")

                    gallery_urls = []
                    if img_url:
                        gallery_urls.append(img_url)
                    if pid:
                        for i in range(1, 5):
                            u = f"https://img.runningwarehouse.eu/watermark/rs.php?path={pid}-{i}.jpg&nw=500"
                            if u not in gallery_urls:
                                gallery_urls.append(u)

                    offer = Offer(
                        store_id=self.runningwarehouse.store_id,
                        store_name=self.runningwarehouse.store_name,
                        product_id=pid,
                        title=title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=product_url,
                        image_url=img_url,
                        gallery_images=gallery_urls,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })

                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
                except Exception:
                    continue

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("runningwarehouse", "catalog", total_indexed, duration)
        logger.info(f"[Running Warehouse] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_deporvillage(self, max_items: int = 500) -> int:
        """Crawl Deporvillage catalog via Algolia API with pagination across products."""
        start_time = time.time()
        logger.info(f"[Deporvillage] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        url = f"https://{self.deporvillage.app_id}-dsn.algolia.net/1/indexes/{self.deporvillage.index_name}/query"
        headers = {
            "x-algolia-application-id": self.deporvillage.app_id,
            "x-algolia-api-key": self.deporvillage.api_key,
            "Content-Type": "application/json"
        }

        # Query all items via empty string + category queries for deep coverage
        queries = [
            "", "running", "trail running", "trekking", "outdoor", "giacca gore-tex",
            "garmin", "polar", "suunto", "hoka", "asics", "salomon", "zaino idratazione",
            "maglia termica", "shorts running"
        ]

        for q in queries:
            page = 0
            while total_indexed < max_items:
                payload = {
                    "query": q,
                    "hitsPerPage": 100,
                    "page": page
                }
                try:
                    resp = self.deporvillage.session.post(
                        url,
                        headers=headers,
                        json=payload,
                        impersonate="chrome",
                        timeout=self.deporvillage.timeout
                    )
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                except Exception as e:
                    logger.error(f"[Deporvillage] Algolia error: {e}")
                    break

                hits = data.get("hits", [])
                if not hits:
                    break

                for h in hits:
                    title = h.get("title") or h.get("name")
                    url_str = h.get("url")
                    price_info = h.get("price")

                    if isinstance(price_info, dict):
                        raw_price = price_info.get("price")
                        pvp = self.deporvillage.parse_price(price_info.get("pvp"))
                    else:
                        raw_price = price_info
                        pvp = None

                    price = self.deporvillage.parse_price(raw_price)
                    if not title or not price or not url_str:
                        continue

                    # Brand
                    brand_info = h.get("brand")
                    brand = brand_info.get("name") if isinstance(brand_info, dict) else (brand_info if isinstance(brand_info, str) else None)
                    brand = self.normalizer.extract_brand(title, brand)

                    full_title = f"{brand} {title}" if brand and not title.lower().startswith(brand.lower()) else title
                    orig_price = pvp if (pvp and pvp > price) else None

                    # Images & Gallery
                    gallery_data = h.get("gallery") or {}
                    images = gallery_data.get("images", []) if isinstance(gallery_data, dict) else (h.get("images") or [])
                    if not isinstance(images, list):
                        images = []

                    gallery_urls = [
                        f"https://cdn.deporvillage.com/cdn-cgi/image/h=500,w=400,f=auto,q=75,fit=contain,background=white/product-vertical/{img_name}"
                        for img_name in images if img_name
                    ]
                    img_url = gallery_urls[0] if gallery_urls else (h.get("image") or h.get("image_url"))

                    # Sizes
                    sizes = []
                    raw_sizes = h.get("sizes")
                    if isinstance(raw_sizes, list):
                        for s in raw_sizes:
                            if isinstance(s, dict) and s.get("name"):
                                sizes.append(str(s["name"]).strip())
                            elif isinstance(s, str):
                                sizes.append(s.strip())

                    pid = str(h.get("objectID") or h.get("id") or "")

                    offer = Offer(
                        store_id=self.deporvillage.store_id,
                        store_name=self.deporvillage.store_name,
                        product_id=pid,
                        title=full_title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=url_str,
                        image_url=img_url,
                        gallery_images=gallery_urls,
                        available_sizes=sizes,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })

                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break

                page += 1
                time.sleep(0.1)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("deporvillage", "catalog", total_indexed, duration)
        logger.info(f"[Deporvillage] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_alltricks(self, max_items: int = 500) -> int:
        """Crawl Alltricks catalog via Constructor.io API across sports categories."""
        start_time = time.time()
        logger.info(f"[Alltricks] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []
        queries = [
            "running", "scarpe", "trail running", "trekking", "outdoor", "giacca gore-tex",
            "garmin", "polar", "salomon speedcross", "hoka", "asics", "zaino idratazione",
            "maglia termica", "ciclismo", "fitness"
        ]

        for q in queries:
            page = 1
            while total_indexed < max_items:
                quoted = urllib.parse.quote(q)
                url = f"{self.alltricks.api_base}/{quoted}?key={self.alltricks.api_key}&num_results_per_page=30&page={page}"
                data = self.alltricks._fetch_json(url)
                if not data or not isinstance(data, dict):
                    break

                results = data.get("response", {}).get("results", [])
                if not results:
                    break

                for item in results:
                    title = item.get("value")
                    d = item.get("data") or {}
                    raw_url = d.get("url")

                    raw_price = d.get("sale_price") or d.get("price")
                    price = self.alltricks.parse_price(raw_price)

                    if not title or not price or not raw_url:
                        continue

                    brand = d.get("brand")
                    if not brand or not isinstance(brand, str):
                        brand = None
                    brand = self.normalizer.extract_brand(title, brand)

                    full_title = f"{brand} {title}" if brand and not title.lower().startswith(brand.lower()) else title
                    list_price = self.alltricks.parse_price(d.get("price"))
                    orig_price = list_price if (list_price and list_price > price) else None

                    img_url = d.get("image_url")
                    pid = str(d.get("id") or item.get("variation_id") or "")

                    offer = Offer(
                        store_id=self.alltricks.store_id,
                        store_name=self.alltricks.store_name,
                        product_id=pid,
                        title=full_title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=raw_url,
                        image_url=img_url,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })

                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break

                page += 1
                time.sleep(0.1)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("alltricks", "catalog", total_indexed, duration)
        logger.info(f"[Alltricks] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_decathlon(self, max_items: int = 500) -> int:
        """Crawl Decathlon Italy catalog across top sports, running gear, padel & cycling."""
        start_time = time.time()
        logger.info(f"[Decathlon] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        # Category pages + search terms for maximum catalog coverage
        cat_urls = [
            "https://www.decathlon.it/tutti-gli-sport/running/scarpe-running",
            "https://www.decathlon.it/tutti-gli-sport/running/abbigliamento-running",
            "https://www.decathlon.it/tutti-gli-sport/trail-running",
            "https://www.decathlon.it/tutti-gli-sport/ciclismo/accessori-bici",
            "https://www.decathlon.it/tutti-gli-sport/fitness-palestra",
            "https://www.decathlon.it/tutti-gli-sport/padel"
        ]

        for cat_url in cat_urls:
            if total_indexed >= max_items:
                break
            html = self.decathlon._fetch_html(cat_url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")
            articles = soup.find_all("article")
            for art in articles:
                try:
                    title = None
                    h2 = art.find("h2")
                    if h2:
                        title = h2.get_text(strip=True)
                    if not title:
                        a_label = art.find("a", attrs={"aria-label": True})
                        if a_label and a_label.get("aria-label"):
                            title = a_label["aria-label"].strip()
                    if not title:
                        continue

                    link_el = art.find("a", href=lambda h: h and "/p/" in h)
                    if not link_el or not link_el.get("href"):
                        continue
                    product_url = urllib.parse.urljoin(self.decathlon.base_url, link_el["href"])

                    # Prices
                    price_blocks = art.select(".vp-price-amount, [class*='price-amount']")
                    price = None
                    orig_price = None

                    for pb in price_blocks:
                        t = pb.get_text(strip=True)
                        val = self.decathlon.parse_price(t)
                        if val:
                            if "precedente" in t.lower() or "prima" in t.lower():
                                orig_price = val
                            else:
                                price = val

                    if not price:
                        import re
                        text_match = re.search(r"Prezzo attuale\s*([\d\.,]+)", art.get_text())
                        if text_match:
                            price = self.decathlon.parse_price(text_match.group(1))

                    if not price:
                        continue

                    brand = self.normalizer.extract_brand(title)
                    img_el = art.find("img")
                    img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

                    pid = None
                    if "/p/" in product_url:
                        parts = [p for p in product_url.split("/") if p]
                        if len(parts) >= 2:
                            pid = parts[-1].replace(".html", "").replace("p-", "")

                    offer = Offer(
                        store_id=self.decathlon.store_id,
                        store_name=self.decathlon.store_name,
                        product_id=pid,
                        title=title,
                        brand=brand,
                        price=price,
                        original_price=orig_price,
                        url=product_url,
                        image_url=img_url,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })

                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
                except Exception:
                    continue

        # If more items needed, query search pagination
        queries = ["running", "garmin", "asics", "nike pegasus", "salomon trail", "bici corsa", "padel racchetta"]
        for q in queries:
            if total_indexed >= max_items:
                break
            for from_offset in (0, 40, 80):
                if total_indexed >= max_items:
                    break
                url = f"{self.decathlon.base_url}/it/search?Ntt={urllib.parse.quote(q)}&from={from_offset}&size=40"
                html = self.decathlon._fetch_html(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "html.parser")
                articles = soup.find_all("article")
                if not articles:
                    break

                for art in articles:
                    try:
                        title = None
                        h2 = art.find("h2")
                        if h2:
                            title = h2.get_text(strip=True)
                        if not title:
                            a_label = art.find("a", attrs={"aria-label": True})
                            if a_label and a_label.get("aria-label"):
                                title = a_label["aria-label"].strip()
                        if not title:
                            continue

                        link_el = art.find("a", href=lambda h: h and "/p/" in h)
                        if not link_el or not link_el.get("href"):
                            continue
                        product_url = urllib.parse.urljoin(self.decathlon.base_url, link_el["href"])

                        price_blocks = art.select(".vp-price-amount, [class*='price-amount']")
                        price = None
                        orig_price = None
                        for pb in price_blocks:
                            t = pb.get_text(strip=True)
                            val = self.decathlon.parse_price(t)
                            if val:
                                if "precedente" in t.lower() or "prima" in t.lower():
                                    orig_price = val
                                else:
                                    price = val
                        if not price:
                            import re
                            text_match = re.search(r"Prezzo attuale\s*([\d\.,]+)", art.get_text())
                            if text_match:
                                price = self.decathlon.parse_price(text_match.group(1))

                        if not price:
                            continue

                        brand = self.normalizer.extract_brand(title)
                        img_el = art.find("img")
                        img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None

                        pid = None
                        if "/p/" in product_url:
                            parts = [p for p in product_url.split("/") if p]
                            if len(parts) >= 2:
                                pid = parts[-1].replace(".html", "").replace("p-", "")

                        offer = Offer(
                            store_id=self.decathlon.store_id,
                            store_name=self.decathlon.store_name,
                            product_id=pid,
                            title=title,
                            brand=brand,
                            price=price,
                            original_price=orig_price,
                            url=product_url,
                            image_url=img_url,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": brand,
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue
                time.sleep(0.2)

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("decathlon", "catalog", total_indexed, duration)
        logger.info(f"[Decathlon] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_nike(self, max_items: int = 500) -> int:
        """Crawl official Nike Italy catalog categories and index canonical products."""
        start_time = time.time()
        logger.info(f"[Nike] Starting catalog crawl (target: {max_items} items)...")
        base_cat_urls = [
            ("https://www.nike.com/it/w/saldi-running-37v7jz3yaep", "running_shoes", "Unisex"),
            ("https://www.nike.com/it/w/running-scarpe-37v7jzy7ok", "running_shoes", "Unisex"),
            ("https://www.nike.com/it/w/uomo-running-scarpe-37v7jz180yzy7ok", "running_shoes", "Uomo"),
            ("https://www.nike.com/it/w/donna-running-scarpe-37v7jz5e1x6zy7ok", "running_shoes", "Donna"),
            ("https://www.nike.com/it/w/trail-running-scarpe-37v7jzbp9wizy7ok", "trail_running", "Unisex"),
            ("https://www.nike.com/it/w/running-abbigliamento-37v7jz6ymx6", "apparel", "Unisex"),
            ("https://www.nike.com/it/w/acg-35t49", "outdoor", "Unisex"),
            ("https://www.nike.com/it/w/fitness-training-scarpe-58jtozy7ok", "fitness", "Unisex"),
        ]

        batch: List[Dict[str, Any]] = []
        total_indexed = 0
        seen_urls = set()

        for cat_url, default_cat, default_gender in base_cat_urls:
            if total_indexed >= max_items:
                break
            try:
                html = self.nike._fetch_html(cat_url)
                if not html:
                    continue

                offers = self.nike._parse_wall_products(html, limit=max_items - total_indexed)
                for offer in offers:
                    if offer.url in seen_urls:
                        continue
                    seen_urls.add(offer.url)

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url) or default_gender
                    canonical = f"Nike {canonical_base.title()}" if "nike" not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title) or default_cat

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": "Nike",
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })
                    total_indexed += 1

                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
            except Exception as e:
                logger.error(f"[Nike] Error crawling category {cat_url}: {e}")

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("nike", "catalog", total_indexed, duration)
        logger.info(f"[Nike] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_adidas(self, max_items: int = 500) -> int:
        """Crawl Adidas Italy official catalog across running, trail, terrex, and apparel."""
        start_time = time.time()
        logger.info(f"[Adidas] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        categories = [
            ("running", "running_shoes", "Unisex"),
            ("trail-running", "trail_running", "Unisex"),
            ("terrex", "outdoor", "Unisex"),
            ("giacche-outdoor", "apparel", "Unisex"),
            ("scarpe-uomo-running", "running_shoes", "Uomo"),
            ("scarpe-donna-running", "running_shoes", "Donna"),
            ("abbigliamento-running", "apparel", "Unisex"),
        ]

        for query_tag, fallback_cat, default_gender in categories:
            start_idx = 0
            while total_indexed < max_items:
                params = {
                    "sitePath": "it",
                    "query": query_tag,
                    "start": start_idx
                }
                try:
                    data = self.adidas._fetch_json(self.adidas.taxonomy_api_url, params=params)
                except Exception as e:
                    logger.debug(f"[Adidas] Error querying {query_tag}: {e}")
                    break

                if not data or not isinstance(data, dict):
                    break

                items = data.get("itemList", {}).get("items", [])
                if not items:
                    break

                for p in items:
                    try:
                        name = p.get("displayName")
                        if not name:
                            continue

                        raw_price = p.get("salePrice") or p.get("price")
                        price = float(raw_price) if raw_price is not None else None
                        if not price or price <= 0:
                            continue

                        list_price = p.get("price")
                        orig_price = float(list_price) if list_price and float(list_price) > price else None

                        link = p.get("link")
                        if not link:
                            continue
                        url = urllib.parse.urljoin(self.adidas.base_url, link)

                        img_obj = p.get("image")
                        img_url = img_obj.get("src") if isinstance(img_obj, dict) else (img_obj if isinstance(img_obj, str) else None)
                        if not img_url:
                            sec_img = p.get("secondImage")
                            img_url = sec_img.get("src") if isinstance(sec_img, dict) else sec_img

                        pid = str(p.get("productId") or p.get("modelId") or "")
                        raw_sizes = p.get("availableSizes", [])
                        sizes = [str(s).strip() for s in raw_sizes if s]
                        in_stock = p.get("orderable", True)

                        offer = Offer(
                            store_id=self.adidas.store_id,
                            store_name=self.adidas.store_name,
                            product_id=pid,
                            title=name,
                            brand="Adidas",
                            price=price,
                            original_price=orig_price,
                            url=url,
                            image_url=img_url,
                            available_sizes=sizes,
                            in_stock=in_stock
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url) or default_gender
                        canonical = f"Adidas {canonical_base.title()}" if not canonical_base.lower().startswith("adidas") else canonical_base.title()
                        category = self._detect_category(offer.title)
                        if category == "running_shoes" and fallback_cat != "running_shoes":
                            category = fallback_cat

                        batch.append({
                            "cluster_key": cluster_key,
                            "canonical_name": canonical,
                            "brand": "Adidas",
                            "category": category,
                            "gender": gender,
                            "offer": offer
                        })

                        total_indexed += 1
                        if len(batch) >= self.BATCH_SIZE:
                            self._flush_batch(batch)

                        if total_indexed >= max_items:
                            break
                    except Exception as e:
                        logger.debug(f"[Adidas] Offer parse error: {e}")
                        continue

                start_idx += len(items)
                time.sleep(0.15)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("adidas", "catalog", total_indexed, duration)
        logger.info(f"[Adidas] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_tradeinn(self, max_items: int = 500) -> int:
        """Crawl Tradeinn catalog across sports categories."""
        start_time = time.time()
        logger.info(f"[Tradeinn] Starting catalog crawl (target: {max_items} items)...")
        queries = [
            "running", "scarpe running", "trail running", "garmin", "smartwatch",
            "bullpadel", "racchetta padel", "ciclismo", "rullo", "oakley"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for q in queries:
            try:
                offers = self.tradeinn.search(q, limit=min(max_items - total_indexed, 40))
                for offer in offers:
                    brand = self.normalizer.extract_brand(offer.title, offer.brand)
                    cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                    category = self._detect_category(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical = f"{brand} {cleaned_title}".strip() if brand else cleaned_title

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })
                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
            except Exception as e:
                logger.debug(f"[Tradeinn] Crawl query {q} error: {e}")
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("tradeinn", "catalog", total_indexed, duration)
        logger.info(f"[Tradeinn] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_df_sport(self, max_items: int = 500) -> int:
        """Crawl DF Sport Specialist catalog across sports categories."""
        start_time = time.time()
        logger.info(f"[DF Sport Specialist] Starting catalog crawl (target: {max_items} items)...")
        queries = [
            "running", "trail running", "scarpe", "garmin", "smartwatch",
            "padel", "ciclismo", "trekking", "salewa", "asics", "hoka"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for q in queries:
            try:
                offers = self.df_sport.search(q, limit=min(max_items - total_indexed, 40))
                for offer in offers:
                    brand = self.normalizer.extract_brand(offer.title, offer.brand)
                    cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                    category = self._detect_category(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical = f"{brand} {cleaned_title}".strip() if brand else cleaned_title

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer
                    })
                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
            except Exception as e:
                logger.debug(f"[DFSport] Crawl query {q} error: {e}")
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("df_sportspecialist", "catalog", total_indexed, duration)
        logger.info(f"[DF Sport Specialist] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_store(self, store_id: str, max_items: int = 500) -> int:
        """Crawl a specific store by its ID."""
        crawlers = {
            "cisalfa": self.crawl_cisalfa,
            "maxisport": self.crawl_maxisport,
            "misterrunning": self.crawl_misterrunning,
            "nencini": self.crawl_nencini,
            "top4running": self.crawl_top4running,
            "runningwarehouse": self.crawl_runningwarehouse,
            "deporvillage": self.crawl_deporvillage,
            "alltricks": self.crawl_alltricks,
            "decathlon": self.crawl_decathlon,
            "nike": self.crawl_nike,
            "adidas": self.crawl_adidas,
            "tradeinn": self.crawl_tradeinn,
            "df_sportspecialist": self.crawl_df_sport,
            "df_sport": self.crawl_df_sport,
        }
        crawler_fn = crawlers.get(store_id.lower())
        if not crawler_fn:
            raise ValueError(f"Unknown store_id '{store_id}'. Supported: {list(crawlers.keys())}")
        return crawler_fn(max_items=max_items)

    def run_full_sync(self, limit_per_store: int = 500, stores: Optional[List[str]] = None) -> Dict[str, Any]:
        """Run crawling across selected or all partner stores and populate the database."""
        start_time = time.time()
        counts: Dict[str, int] = {}

        all_stores = [
            ("cisalfa", self.crawl_cisalfa),
            ("maxisport", self.crawl_maxisport),
            ("misterrunning", self.crawl_misterrunning),
            ("nencini", self.crawl_nencini),
            ("top4running", self.crawl_top4running),
            ("runningwarehouse", self.crawl_runningwarehouse),
            ("deporvillage", self.crawl_deporvillage),
            ("alltricks", self.crawl_alltricks),
            ("decathlon", self.crawl_decathlon),
            ("nike", self.crawl_nike),
            ("adidas", self.crawl_adidas),
            ("tradeinn", self.crawl_tradeinn),
            ("df_sportspecialist", self.crawl_df_sport),
        ]

        target_stores = all_stores
        if stores:
            allowed = {s.lower() for s in stores}
            target_stores = [item for item in all_stores if item[0] in allowed]

        for store_id, crawl_func in target_stores:
            try:
                counts[store_id] = crawl_func(max_items=limit_per_store)
            except Exception as e:
                logger.error(f"Error during crawl for store '{store_id}': {e}")
                counts[store_id] = 0

        elapsed = round(time.time() - start_time, 2)
        stats = self.db.get_stats()

        return {
            "duration_seconds": elapsed,
            "crawled_by_store": counts,
            "total_crawled": sum(counts.values()),
            "catalog_stats": stats
        }
