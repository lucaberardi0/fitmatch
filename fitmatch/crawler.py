import time
import logging
import urllib.parse
from typing import List, Dict, Any, Optional
from bs4 import BeautifulSoup
from fitmatch.db import Database
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import Offer, normalize_sizes
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
from fitmatch.scrapers.shopify_stores import (
    SportITScraper,
    TennisPointScraper,
    BasketballStoreScraper,
    NonSoloSportScraper,
    IntersportScraper,
    BshopzoneScraper,
)

logger = logging.getLogger("fitmatch.crawler")


class CategoryCrawler:
    """Orchestrates comprehensive crawling of multi-store catalogs and indexes products in the database."""

    BATCH_SIZE = 40

    SHOPIFY_CRAWL_CONFIG: Dict[str, Dict[str, List[str]]] = {
        "sportit": {
            "collections": [
                "running", "padel", "tennis", "nuoto", "sci", "fitness",
                "ciclismo", "trekking", "completi-calcio-abbigliamento", "felpe-calcio-abbigliamento",
            ],
            "queries": ["scarpe calcio", "scarpini", "running", "padel", "tennis", "nuoto", "sci", "fitness"],
        },
        "tennis_point": {
            "collections": [
                "aktion-10-sale",
                "aktion-deal",
                "all",
            ],
            "queries": ["tennis", "padel", "babolat", "wilson", "head", "yonex", "asics", "scarpe tennis", "racchetta padel"],
        },
        "basketballstore": {
            "collections": ["scarpe-basket", "abbigliamento-basket", "accessori-basket", "palloni-basket", "canotte-basket"],
            "queries": ["jordan", "nike basket", "curry", "spalding", "lebron"],
        },
        "nonsolosport": {
            "collections": [
                "calcio", "calcetto", "basket", "abbigliamento-running",
                "abbigliamento-sci", "abbigliamento-padel-e-tennis", "abbigliamento-trekking", "abbigliamento-training",
            ],
            "queries": ["scarpe calcio", "scarpe basket", "running", "sci", "nuoto"],
        },
        "intersport": {
            "collections": [
                "sci", "abbigliamento-basket", "abbigliamento-calcetto", "abbigliamento-ciclismo",
                "abbigliamento-tennis", "abbigliamento-padel", "abbigliamento-fitness-e-palestra",
                "abbigliamento-trekking", "nuoto",
            ],
            "queries": ["running", "salomon", "nike", "sci", "nuoto", "calcio"],
        },
        "bshopzone": {
            "collections": [
                "scarpe-trail-running", "scarpe-trekking", "scarpe-arrampicata",
                "scarponi-sci", "caschi-sci", "sci-attacchi", "alpinismo", "running",
            ],
            "queries": ["scarpa", "nordica", "atomic", "salomon", "hoka"],
        },
    }

    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()
        self.normalizer = ProductNormalizer()
        self.current_session_id: Optional[str] = None
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
        self.sportit = SportITScraper()
        self.tennis_point = TennisPointScraper()
        self.basketballstore = BasketballStoreScraper()
        self.nonsolosport = NonSoloSportScraper()
        self.intersport = IntersportScraper()
        self.bshopzone = BshopzoneScraper()

    def _flush_batch(self, batch: List[Dict[str, Any]]) -> int:
        """Helper to flush pending offers to DB in a single transaction."""
        if not batch:
            return 0
        count = self.db.upsert_offers_batch(batch)
        batch.clear()
        return count

    def _detect_category(self, title: str, url: Optional[str] = None) -> str:
        """Categorize product by title keywords + structured store URL using ProductNormalizer as single source of truth."""
        tl = (title or "").lower()
        art_type = ProductNormalizer.detect_article_type(title, url=url)
        if art_type == "non_sport":
            return "non_sport"
        if art_type in (
            "swim", "football_boots", "tennis", "basketball", "winter_sports",
            "gps_watch", "eyewear", "hydration", "nutrition", "cycling",
            "case", "mount", "strap", "pack", "sensor", "socks", "top", "pants", "jacket",
        ):
            return art_type
        if art_type == "racket":
            if any(w in tl for w in ["tennis", "pure drive", "pure aero", "blade ", "pro staff", "ezone", "vcore", "percept", "speed mp", "radical mp"]):
                return "tennis"
            return "padel"
        if art_type == "trainer":
            return "cycling"
        if any(w in tl for w in [
            "scarponi sci", "maschera sci", "casco sci", "attacchi sci", "snowboard",
            "rossignol", "nordica", "dalbello", "tecnica mach", "lange ", "head kore", "blizzard ",
        ]) or (
            "atomic " in tl and not any(c in tl for c in ["atomic pink", "atomic orange", "atomic red", "atomic green", "atomic teal", "atomic blue", "atomic purple"])
        ) or (
            "volkl" in tl and not any(t in tl for t in ["overgrip", "tennis", "corda", "grip"])
        ):
            return "winter_sports"
        is_juan_lebron_padel = any(w in tl for w in ["babolat", "juan lebron", "premura", "veron", "padel", "viper"])
        if not is_juan_lebron_padel and any(w in tl for w in [
            "basket", "basketball", "pallacanestro", "lebron", "curry", "luka ", "giannis",
            "kd ", "kobe ", "air jordan", "spalding", "molten", "canotta nba",
        ]):
            return "basketball"
        if any(w in tl for w in [
            "tennis", "terra battuta", "terra rossa", "gel-resolution", "gel resolution",
            "gel-challenger", "gel challenger", "solution speed", "court ff",
            "barricade", "nikecourt", "babolat pure", "wilson blade", "pro staff", "yonex ezone",
        ]) and "padel" not in tl:
            return "tennis"
        if any(w in tl for w in [
            "calcio", "calcetto", "futsal", "parastinchi", "guanti portiere", "mercurial", "predator", "phantom", "copa pure",
        ]):
            return "football_boots"
        is_bike_handlebar = "manubri" in tl and any(w in tl for w in ["ergo", "compact", "aero", "carbon", "alluminio", "mm", "strada", "gravel", "mtb", "bici", "vibe", "sostegno", "supporto"])
        if not is_bike_handlebar and any(w in tl for w in [
            "theragun", "hyperice", "massaggiante", "recupero", "loop band", "elastico", "elastici",
            "manubri", "kettlebell", "foam roller", "tappetino", "pesi", "corda saltare", "compex",
            "dropset", "metcon", "tribase", "nano"
        ]):
            return "fitness"
        if art_type == "shoes":
            if any(w in tl for w in [
                "trail", "speedcross", "peregrine", "mafate", "cascadia", "caldera", "trabuco",
                "fujitrail", "bushido", "mutant", "catamount", "ultra raptor", "wildhorse",
                "pegasus trail", "terrex agravic", "terrex speed", "sense ride", "lone peak",
                "speedgoat", "challenger atr", "stinson", "hierro", "norvan"
            ]):
                return "trail_running"
            if any(w in tl for w in [
                "trekking", "outdoor", "scarpon", "escursionismo", "puez", "salewa", "meindl",
                "tx4", "tx5", "lowa", "moab", "merrell", "mojito", "ribelle"
            ]):
                return "outdoor"
            if any(w in tl for w in [
                "running", "corsa", "maratona", "pegasus", "vomero", "streakfly", "vaporfly", "alphafly",
                "zoom fly", "invincible", "nimbus", "cumulus", "novablast", "kayano", "superblast",
                "metaspeed", "clifton", "bondi", "mach ", "rincon", "ghost", "glycerin", "adizero",
                "endorphin", "triumph", "deviate", "velocity nitro", "cloudmonster", "cloudsurfer",
                "fresh foam", "fuelcell", "1080",
            ]):
                return "running_shoes"
            return "shoes"
        return art_type or "gear"

    def crawl_cisalfa(self, max_items: int = 500) -> int:
        """Crawl Cisalfa multi-department sports catalog with deep pagination."""
        start_time = time.time()
        logger.info(f"[Cisalfa] Starting catalog crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.cisalfasport.it/it-it/sport/running/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/running/trail-running/",
            "https://www.cisalfasport.it/it-it/sport/running/abbigliamento/",
            "https://www.cisalfasport.it/it-it/sport/running/accessori-e-zaini/",
            "https://www.cisalfasport.it/it-it/sport/outdoor/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/tennis/racchette/",
            "https://www.cisalfasport.it/it-it/sport/tennis/padel/",
            "https://www.cisalfasport.it/it-it/sport/tennis/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/ciclismo/",
            "https://www.cisalfasport.it/it-it/sport/fitness/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/calcio/scarpe-calcio-e-calcetto/",
            "https://www.cisalfasport.it/it-it/sport/altri-sport/basket/",
            "https://www.cisalfasport.it/it-it/sport/sci/",
            "https://www.cisalfasport.it/it-it/sport/altri-sport/piscina/",
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

                        brand = self.normalizer.extract_brand(title, url=product_url)

                        pid_el = tile.select_one("[data-itemid]")
                        pid = pid_el["data-itemid"] if pid_el and pid_el.get("data-itemid") else None
                        sizes = self.cisalfa.fetch_sizes(product_url, title=title)

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
                            available_sizes=sizes,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title, url=offer.url)

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
        self.db.record_crawl_log("cisalfa", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Cisalfa] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_maxisport(self, max_items: int = 500) -> int:
        """Crawl Maxi Sport multi-department sports catalog with pagination."""
        start_time = time.time()
        logger.info(f"[Maxi Sport] Starting catalog crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.maxisport.com/running-scarpe-maxi-promo/",
            "https://www.maxisport.com/sport-running-scarpe/",
            "https://www.maxisport.com/sport-montagna-scarpe/",
            "https://www.maxisport.com/sport-padel-racchette/",
            "https://www.maxisport.com/sport-padel-scarpe/",
            "https://www.maxisport.com/sport-tennis-scarpe/",
            "https://www.maxisport.com/scarpe-sneaker",
            "https://www.maxisport.com/reparto-maxipromo-scarpe/",
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

                        brand = self.normalizer.extract_brand(title, url=product_url)

                        pid_el = item.select_one("[data-product-id]")
                        pid = pid_el["data-product-id"] if pid_el and pid_el.get("data-product-id") else None
                        sizes = self.maxisport.fetch_sizes(product_url, title=title)

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
                            available_sizes=sizes,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title, url=offer.url)

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
        self.db.record_crawl_log("maxisport", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
                        brand = self.normalizer.extract_brand(name, p.get("brand"), url=url)
                        image = p.get("image")
                        pid = str(p.get("id")) if p.get("id") else None

                        raw_sizes = p.get("sizes", [])
                        gender = self.normalizer.extract_gender(name, url)
                        category = self._detect_category(name, url=url)
                        sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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
                        category = self._detect_category(offer.title, url=offer.url)

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
        self.db.record_crawl_log("misterrunning", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
            "https://www.nencinisport.it/it/sport/trail-running/",
            "https://www.nencinisport.it/it/sport/ciclismo/",
            "https://www.nencinisport.it/it/sport/padel/",
            "https://www.nencinisport.it/it/sport/tennis/",
            "https://www.nencinisport.it/it/sport/calcio-calcetto/",
            "https://www.nencinisport.it/it/sport/basket/",
            "https://www.nencinisport.it/it/sport/sci/",
            "https://www.nencinisport.it/it/sport/nuoto/",
            "https://www.nencinisport.it/it/scarpe/"
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
                        time.sleep(0.12)
                        sizes = self.nencini.fetch_sizes(product_url, title=title)

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
                            available_sizes=sizes,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title, url=offer.url)

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
        self.db.record_crawl_log("nencini", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
                    raw_sizes = attrs.get("sizes_eu") or attrs.get("sizes_default") or attrs.get("Size") or []
                    gender = self.normalizer.extract_gender(full_title, product_url)
                    category = self._detect_category(full_title)
                    sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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
                        available_sizes=sizes,
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()

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
        self.db.record_crawl_log("top4running", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Top4Running] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_runningwarehouse(self, max_items: int = 500) -> int:
        """Crawl Running Warehouse Europe catalog across all departments."""
        start_time = time.time()
        logger.info(f"[Running Warehouse] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []
        cat_urls = [
            "https://www.runningwarehouse.eu/catpage-RWMRSSALE-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWWRSSALE-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWMRASALE-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWWRASALE-IT.html",
            "https://www.runningwarehouse.eu/catpage-RMSNEU-IT.html",
            "https://www.runningwarehouse.eu/catpage-RMSSTAB-IT.html",
            "https://www.runningwarehouse.eu/catpage-TRAILSHPP.html",
            "https://www.runningwarehouse.eu/catpage-NEWMRUNAPP-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWACCBAGS-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWACCELEC-IT.html",
            "https://www.runningwarehouse.eu/catpage-RWACCNUTR-IT.html",
        ]

        for cat_url in cat_urls:
            html = self.runningwarehouse._fetch_html(cat_url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")
            cells = soup.select(".cattable-wrap-cell")

            for cell in cells:
                try:
                    link_el = cell.select_one("a.cattable-wrap-cell-info, a.cattable-wrap-cell-imgwrap-inner, a")
                    if not link_el or not link_el.get("href"):
                        continue

                    name_el = cell.select_one(".cattable-wrap-cell-info-name")
                    title = (
                        cell.get("data-gtm_impression_name")
                        or (name_el.get_text(strip=True) if name_el else None)
                        or link_el.get_text(strip=True)
                    )
                    if not title:
                        continue

                    raw_href = link_el["href"]
                    product_url = urllib.parse.urljoin(self.runningwarehouse.base_url, raw_href)

                    # Prices
                    price = self.runningwarehouse.parse_price(cell.get("data-gtm_impression_price"))
                    price_wrap = cell.select_one(".cattable-wrap-cell-info-price")
                    if not price and price_wrap:
                        first_span = price_wrap.find("span")
                        p_text = first_span.get_text(strip=True) if first_span else price_wrap.get_text()
                        price = self.runningwarehouse.parse_price(p_text)
                    if not price:
                        continue

                    orig_price = None
                    if price_wrap:
                        strike_el = price_wrap.select_one("span.is-crossout, span.strike, strike, del")
                        if strike_el:
                            orig_price = self.runningwarehouse.parse_price(strike_el.get_text())

                    brand = self.normalizer.extract_brand(title, cell.get("data-gtm_impression_brand"))
                    pid = cell.get("data-code")
                    if not pid and "descpage-" in product_url:
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

                    time.sleep(0.3)
                    sizes = self.runningwarehouse.fetch_sizes(product_url, title=title)

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

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("runningwarehouse", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
            "maglia termica", "shorts running",
            "calcio", "tennis", "basket", "sci", "scarponi sci", "nuoto", "enervit", "maurten"
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
                    gender = self.normalizer.extract_gender(full_title, url_str)
                    category = self._detect_category(full_title)
                    sizes = normalize_sizes(sizes, gender=gender, category=category)

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
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()

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
        self.db.record_crawl_log("deporvillage", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
                    time.sleep(0.12)
                    sizes = self.alltricks.fetch_sizes(raw_url, title=full_title)

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
        self.db.record_crawl_log("alltricks", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Alltricks] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_decathlon(self, max_items: int = 500, cat_urls_override: Optional[List[str]] = None) -> int:
        """Crawl Decathlon Italy catalog across top sports, running gear, padel & cycling."""
        start_time = time.time()
        logger.info(f"[Decathlon] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        # Category pages + search terms for maximum catalog coverage
        cat_urls = cat_urls_override or [
            "https://www.decathlon.it/tutti-gli-sport/running/scarpe-running",
            "https://www.decathlon.it/tutti-gli-sport/running/abbigliamento-running",
            "https://www.decathlon.it/tutti-gli-sport/trail-running",
            "https://www.decathlon.it/tutti-gli-sport/ciclismo/accessori-bici",
            "https://www.decathlon.it/tutti-gli-sport/fitness-palestra",
            "https://www.decathlon.it/tutti-gli-sport/padel",
            "https://www.decathlon.it/tutti-gli-sport/tennis",
            "https://www.decathlon.it/tutti-gli-sport/basket",
            "https://www.decathlon.it/tutti-gli-sport/sport-invernali",
            "https://www.decathlon.it/tutti-gli-sport/snowboard",
            "https://www.decathlon.it/tutti-gli-sport/calcio/scarpe-calcio",
            "https://www.decathlon.it/search?Ntt=scarpe+calcetto",
            "https://www.decathlon.it/tutti-gli-sport/nuoto",
            "https://www.decathlon.it/search?Ntt=occhialini+nuoto",
            "https://www.decathlon.it/search?Ntt=gel+energetici+running",
        ]

        for cat_url in cat_urls:
            if total_indexed >= max_items:
                break
            html = self.decathlon._fetch_html(cat_url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")
            raw_url_to_sizes = self.decathlon.extract_rsc_raw_sizes(soup)

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
                    raw_href = link_el["href"]
                    product_url = urllib.parse.urljoin(self.decathlon.base_url, raw_href)
                    clean_rel = raw_href.split("?")[0]
                    raw_sizes = raw_url_to_sizes.get(clean_rel) or raw_url_to_sizes.get(raw_href) or []
                    gender = self.normalizer.extract_gender(title, product_url)
                    category = self._detect_category(title)
                    sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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
                raw_url_to_sizes = self.decathlon.extract_rsc_raw_sizes(soup)
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
                        raw_href = link_el["href"]
                        product_url = urllib.parse.urljoin(self.decathlon.base_url, raw_href)
                        clean_rel = raw_href.split("?")[0]
                        raw_sizes = raw_url_to_sizes.get(clean_rel) or raw_url_to_sizes.get(raw_href) or []
                        gender = self.normalizer.extract_gender(title, product_url)
                        category = self._detect_category(title)
                        sizes = normalize_sizes(raw_sizes, gender=gender, category=category)

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
                            available_sizes=sizes,
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title, url=offer.url)

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
        self.db.record_crawl_log("decathlon", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
                    if not offer.available_sizes:
                        offer.available_sizes = self.nike.fetch_sizes(offer.url)

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
        self.db.record_crawl_log("nike", "catalog", total_indexed, duration, session_id=self.current_session_id)
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
                        gender = self.normalizer.extract_gender(name, url) or default_gender
                        category = self._detect_category(name)
                        if category == "running_shoes" and fallback_cat != "running_shoes":
                            category = fallback_cat
                        sizes = normalize_sizes(raw_sizes, gender=gender, category=category)
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
                        canonical = f"Adidas {canonical_base.title()}" if not canonical_base.lower().startswith("adidas") else canonical_base.title()

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
                total_count = data.get("itemList", {}).get("count")
                if total_count is not None and start_idx >= int(total_count):
                    break
                time.sleep(0.15)

            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("adidas", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Adidas] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_tradeinn(self, max_items: int = 500) -> int:
        """Crawl Tradeinn catalog across sports categories."""
        start_time = time.time()
        logger.info(f"[Tradeinn] Starting catalog crawl (target: {max_items} items)...")
        queries = [
            "running", "scarpe running", "trail running", "garmin", "smartwatch",
            "bullpadel", "racchetta padel", "racchetta tennis", "babolat pure drive",
            "scarpe calcio", "mercurial", "scarponi sci", "atomic", "occhialini nuoto",
            "ciclismo", "rullo", "oakley", "enervit"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for q in queries:
            try:
                offers = self.tradeinn.search(q, limit=min(max_items - total_indexed, 40))
                for offer in offers:
                    brand = self.normalizer.extract_brand(offer.title, offer.brand, url=offer.url)
                    cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                    category = self._detect_category(offer.title, url=offer.url)
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
        self.db.record_crawl_log("tradeinn", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Tradeinn] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_df_sport(self, max_items: int = 500) -> int:
        """Crawl DF Sport Specialist catalog across sports categories."""
        start_time = time.time()
        logger.info(f"[DF Sport Specialist] Starting catalog crawl (target: {max_items} items)...")
        queries = [
            "running", "trail running", "scarpe", "garmin", "smartwatch",
            "padel", "tennis", "calcio", "basket", "sci", "scarponi sci",
            "nuoto", "ciclismo", "trekking", "salewa", "asics", "hoka"
        ]
        total_indexed = 0
        batch: List[Dict[str, Any]] = []

        for q in queries:
            try:
                offers = self.df_sport.search(q, limit=min(max_items - total_indexed, 40))
                for offer in offers:
                    brand = self.normalizer.extract_brand(offer.title, offer.brand, url=offer.url)
                    cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                    category = self._detect_category(offer.title, url=offer.url)
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
        self.db.record_crawl_log("df_sportspecialist", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[DF Sport Specialist] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_sportler(self, max_items: int = 500) -> int:
        """Crawl Sportler catalog across running, outdoor, cycling and trail queries."""
        start_time = time.time()
        logger.info(f"[Sportler] Starting catalog crawl (target: {max_items} items)...")
        queries = [
            "running", "trail running", "scarpe running", "scarpa trekking",
            "garmin", "hoka", "asics", "salomon", "la sportiva", "ciclismo"
        ]
        total_indexed = 0
        seen_urls = set()
        batch: List[Dict[str, Any]] = []

        for q in queries:
            try:
                offers = self.sportler.search(q, limit=min(max_items - total_indexed, 40))
                for offer in offers:
                    if offer.url in seen_urls:
                        continue
                    seen_urls.add(offer.url)
                    brand = self.normalizer.extract_brand(offer.title, offer.brand, url=offer.url)
                    cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                    category = self._detect_category(offer.title, url=offer.url)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical = f"{brand} {cleaned_title}".strip() if brand else cleaned_title

                    batch.append({
                        "cluster_key": cluster_key,
                        "canonical_name": canonical,
                        "brand": brand,
                        "category": category,
                        "gender": gender,
                        "offer": offer,
                    })
                    total_indexed += 1
                    if len(batch) >= self.BATCH_SIZE:
                        self._flush_batch(batch)

                    if total_indexed >= max_items:
                        break
            except Exception as e:
                logger.debug(f"[Sportler] Crawl query {q} error: {e}")
            if total_indexed >= max_items:
                break

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log("sportler", "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[Sportler] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def _crawl_shopify_store(self, scraper, max_items: int = 500) -> int:
        """Shared crawler for Shopify stores using verified collection feeds + search queries."""
        start_time = time.time()
        cfg = self.SHOPIFY_CRAWL_CONFIG.get(scraper.store_id, {})
        collections = cfg.get("collections", [])
        queries = cfg.get("queries", [])
        logger.info(f"[{scraper.store_name}] Starting catalog crawl (target: {max_items} items)...")

        total_indexed = 0
        seen_urls = set()
        batch: List[Dict[str, Any]] = []

        def _index_offers(offers: List[Offer]) -> None:
            nonlocal total_indexed
            for offer in offers:
                if total_indexed >= max_items:
                    break
                if not offer.url or offer.url in seen_urls:
                    continue
                seen_urls.add(offer.url)
                brand = self.normalizer.extract_brand(offer.title, offer.brand, url=offer.url)
                cleaned_title, _ = self.normalizer.clean_title(offer.title, brand)
                category = self._detect_category(offer.title, url=offer.url)
                if category == "non_sport":
                    continue
                gender = self.normalizer.extract_gender(offer.title, offer.url)
                cluster_key = self.normalizer.extract_cluster_key(offer)
                canonical = f"{brand} {cleaned_title}".strip() if brand else cleaned_title
                batch.append({
                    "cluster_key": cluster_key,
                    "canonical_name": canonical,
                    "brand": brand,
                    "category": category,
                    "gender": gender,
                    "offer": offer,
                })
                total_indexed += 1
                if len(batch) >= self.BATCH_SIZE:
                    self._flush_batch(batch)

        per_collection_cap = max(25, min(60, max_items // max(len(collections), 1) + 10))
        for col in collections:
            if total_indexed >= max_items:
                break
            try:
                offers = scraper.fetch_collection_offers(col, limit=per_collection_cap)
                _index_offers(offers)
            except Exception as e:
                logger.debug(f"[{scraper.store_name}] Collection '{col}' crawl error: {e}")

        for q in queries:
            if total_indexed >= max_items:
                break
            try:
                offers = scraper.search(q, limit=min(max_items - total_indexed, 30))
                _index_offers(offers)
            except Exception as e:
                logger.debug(f"[{scraper.store_name}] Query '{q}' crawl error: {e}")

        self._flush_batch(batch)
        duration = time.time() - start_time
        self.db.record_crawl_log(scraper.store_id, "catalog", total_indexed, duration, session_id=self.current_session_id)
        logger.info(f"[{scraper.store_name}] Indexed {total_indexed} products in {round(duration, 1)}s.")
        return total_indexed

    def crawl_sportit(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.sportit, max_items=max_items)

    def crawl_tennis_point(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.tennis_point, max_items=max_items)

    def crawl_basketballstore(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.basketballstore, max_items=max_items)

    def crawl_nonsolosport(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.nonsolosport, max_items=max_items)

    def crawl_intersport(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.intersport, max_items=max_items)

    def crawl_bshopzone(self, max_items: int = 500) -> int:
        return self._crawl_shopify_store(self.bshopzone, max_items=max_items)

    def crawl_store(self, store_id: str, max_items: int = 500, session_id: Optional[str] = None) -> int:
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
            "sportler": self.crawl_sportler,
            "nike": self.crawl_nike,
            "adidas": self.crawl_adidas,
            "tradeinn": self.crawl_tradeinn,
            "df_sportspecialist": self.crawl_df_sport,
            "df_sport": self.crawl_df_sport,
            "sportit": self.crawl_sportit,
            "tennis_point": self.crawl_tennis_point,
            "basketballstore": self.crawl_basketballstore,
            "nonsolosport": self.crawl_nonsolosport,
            "intersport": self.crawl_intersport,
            "bshopzone": self.crawl_bshopzone,
        }
        crawler_fn = crawlers.get(store_id.lower())
        if not crawler_fn:
            raise ValueError(f"Unknown store_id '{store_id}'. Supported: {list(crawlers.keys())}")
        self.current_session_id = session_id
        try:
            return crawler_fn(max_items=max_items)
        finally:
            self.current_session_id = None

    def run_full_sync(
        self,
        limit_per_store: int = 500,
        stores: Optional[List[str]] = None,
        session_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """Run crawling across selected or all partner stores and populate the database."""
        start_time = time.time()
        counts: Dict[str, int] = {}
        self.current_session_id = session_id

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
            ("sportler", self.crawl_sportler),
            ("nike", self.crawl_nike),
            ("adidas", self.crawl_adidas),
            ("tradeinn", self.crawl_tradeinn),
            ("df_sportspecialist", self.crawl_df_sport),
            ("sportit", self.crawl_sportit),
            ("tennis_point", self.crawl_tennis_point),
            ("basketballstore", self.crawl_basketballstore),
            ("nonsolosport", self.crawl_nonsolosport),
            ("intersport", self.crawl_intersport),
            ("bshopzone", self.crawl_bshopzone),
        ]

        target_stores = all_stores
        if stores:
            allowed = {s.lower() for s in stores}
            target_stores = [item for item in all_stores if item[0] in allowed]
        else:
            # Crawl stalest stores first so tail stores (e.g. Shopify partners) never starve on timeouts
            freshness_order = self.db.get_store_freshness_order()
            if freshness_order:
                rank_map = {sid: idx for idx, sid in enumerate(freshness_order)}
                target_stores = sorted(
                    target_stores,
                    key=lambda item: (rank_map.get(item[0], -1), item[0]),
                )

        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading

        counts_lock = threading.Lock()

        def _run_store(store_id: str, crawl_func):
            try:
                crawled = crawl_func(max_items=limit_per_store)
            except Exception as e:
                logger.error(f"Error during crawl for store '{store_id}': {e}")
                crawled = 0
            with counts_lock:
                counts[store_id] = crawled

        try:
            workers = min(3, max(len(target_stores), 1))
            if workers <= 1:
                for store_id, crawl_func in target_stores:
                    _run_store(store_id, crawl_func)
            else:
                with ThreadPoolExecutor(max_workers=workers) as pool:
                    futures = [pool.submit(_run_store, sid, fn) for sid, fn in target_stores]
                    for fut in as_completed(futures):
                        try:
                            fut.result()
                        except Exception as e:
                            logger.error(f"Store crawl worker error: {e}")
        finally:
            self.current_session_id = None

        elapsed = round(time.time() - start_time, 2)
        stats = self.db.get_stats()

        return {
            "duration_seconds": elapsed,
            "crawled_by_store": counts,
            "total_crawled": sum(counts.values()),
            "catalog_stats": stats
        }
