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

logger = logging.getLogger("fitmatch.crawler")


class CategoryCrawler:
    """Orchestrates paginated crawling of store categories and indexes products in the database."""

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

    def crawl_cisalfa(self, max_items: int = 150) -> int:
        """Crawl Cisalfa running catalog with pagination (?start=0, 36, 72...)."""
        logger.info(f"[Cisalfa] Starting category crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.cisalfasport.it/it-it/sport/running/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/outdoor/scarpe/",
            "https://www.cisalfasport.it/it-it/sport/running/accessori/"
        ]
        page_size = 36
        total_indexed = 0

        for base_cat_url in base_cat_urls:
            offset = 0
            while total_indexed < max_items:
                url = f"{base_cat_url}?start={offset}&sz={page_size}"
                html = self.cisalfa._fetch_html(url)
                if not html:
                    break

                soup = BeautifulSoup(html, "html.parser")
                tiles = soup.select(".product-tile")
                if not tiles:
                    break

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

                        self.db.upsert_product_and_offer(
                            cluster_key=cluster_key,
                            canonical_name=canonical,
                            brand=brand,
                            category=category,
                            gender=gender,
                            offer=offer
                        )
                        total_indexed += 1
                        if total_indexed >= max_items:
                            break
                    except Exception as e:
                        continue

                offset += page_size
                time.sleep(0.3)
            if total_indexed >= max_items:
                break

        logger.info(f"[Cisalfa] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_maxisport(self, max_items: int = 150) -> int:
        """Crawl Maxi Sport running & trail catalog with pagination (?p=1, 2, 3...)."""
        logger.info(f"[Maxi Sport] Starting category crawl (target: {max_items} items)...")
        base_cat_urls = [
            "https://www.maxisport.com/running-scarpe-maxi-promo/",
            "https://www.maxisport.com/running-scarpe-trail-running/"
        ]
        total_indexed = 0

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

                        self.db.upsert_product_and_offer(
                            cluster_key=cluster_key,
                            canonical_name=canonical,
                            brand=brand,
                            category=category,
                            gender=gender,
                            offer=offer
                        )
                        total_indexed += 1
                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue

                page += 1
                time.sleep(0.3)
            if total_indexed >= max_items:
                break

        logger.info(f"[Maxi Sport] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_misterrunning(self, max_items: int = 150) -> int:
        """Crawl Mister Running via Clerk API with batch offset and category queries."""
        logger.info(f"[Mister Running] Starting catalog crawl (target: {max_items} items)...")
        import json
        batch_size = 50
        total_indexed = 0
        queries = ["running", "trail", "accessori", "garmin"]

        for q in queries:
            offset = 0
            while total_indexed < max_items:
                params = {
                    "key": self.misterrunning.clerk_key,
                    "query": q,
                    "limit": batch_size,
                    "offset": offset,
                    "attributes": json.dumps(["name", "price", "list_price", "image", "url", "brand", "id"])
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
                            in_stock=True
                        )

                        cluster_key = self.normalizer.extract_cluster_key(offer)
                        canonical_base, _ = self.normalizer.clean_title(offer.title)
                        gender = self.normalizer.extract_gender(offer.title, offer.url)
                        canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                        category = self._detect_category(offer.title)

                        self.db.upsert_product_and_offer(
                            cluster_key=cluster_key,
                            canonical_name=canonical,
                            brand=brand,
                            category=category,
                            gender=gender,
                            offer=offer
                        )
                        total_indexed += 1
                        if total_indexed >= max_items:
                            break
                    except Exception:
                        continue

                offset += batch_size
                time.sleep(0.2)
            if total_indexed >= max_items:
                break

        logger.info(f"[Mister Running] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_nencini(self, max_items: int = 150) -> int:
        """Crawl Nencini Sport running catalog with pagination (?page=1, 2, 3...)."""
        logger.info(f"[Nencini Sport] Starting category crawl (target: {max_items} items)...")
        self.nencini._ensure_session()
        base_cat_url = "https://www.nencinisport.it/it/sport/running/scarpe/"
        page = 1
        total_indexed = 0

        while total_indexed < max_items:
            url = f"{base_cat_url}?page={page}"
            html = self.nencini._fetch_html(url)
            if not html:
                break

            soup = BeautifulSoup(html, "html.parser")
            cards = soup.select(".product-card")
            if not cards:
                break

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
                        brand = link_el["data-gtmbrand"].strip().capitalize()
                    brand = self.normalizer.extract_brand(title, brand)

                    img_el = card.select_one("img")
                    img_url = (img_el.get("src") or img_el.get("data-src")) if img_el else None
                    if img_url:
                        img_url = urllib.parse.urljoin(self.nencini.base_url, img_url)

                    pid = card.get("data-clerk-product-id") or link_el.get("data-gtmid")

                    offer = Offer(
                        store_id=self.nencini.store_id,
                        store_name=self.nencini.store_name,
                        product_id=str(pid) if pid else None,
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

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=self._detect_category(offer.title),
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception:
                    continue

            page += 1
            time.sleep(0.3)

        logger.info(f"[Nencini Sport] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_top4running(self, max_items: int = 150) -> int:
        """Crawl Top4Running catalog via Luigi's Box API with expanded queries."""
        logger.info(f"[Top4Running] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        queries = [
            "running", "scarpe", "trail", "maratona", "nike vaporfly",
            "asics metaspeed", "salomon trail", "garmin", "saucony endorphin",
            "hoka rocket", "oakley"
        ]

        for q in queries:
            if total_indexed >= max_items:
                break
            offers = self.top4running.search(query=q, limit=min(max_items - total_indexed, 50))
            for offer in offers:
                try:
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    brand = offer.brand or self.normalizer.extract_brand(offer.title)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=self._detect_category(offer.title),
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception:
                    continue

        logger.info(f"[Top4Running] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_runningwarehouse(self, max_items: int = 150) -> int:
        """Crawl Running Warehouse Europe catalog."""
        logger.info(f"[Running Warehouse] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        cat_urls = [
            "https://www.runningwarehouse.eu/catpage-RWMRSSALE-EN.html",
            "https://www.runningwarehouse.eu/catpage-RWWRSSALE-EN.html"
        ]

        for cat_url in cat_urls:
            if total_indexed >= max_items:
                break
            html = self.runningwarehouse._fetch_html(cat_url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")
            cells = soup.select(".cattable-wrap-cell")

            for cell in cells:
                try:
                    title = cell.get("data-gtm_impression_name")
                    link_el = cell.select_one("a.cattable-wrap-cell-imgwrap-inner, a")
                    if not link_el or not link_el.get("href"):
                        continue
                    href = link_el["href"]
                    product_url = urllib.parse.urljoin(self.runningwarehouse.base_url, href)

                    if not title:
                        title = link_el.get_text(strip=True)
                    if not title:
                        continue

                    raw_brand = cell.get("data-gtm_impression_brand") or ""
                    import re
                    brand = re.sub(r"(?i)\s*(running|footwear|padel|tennis|-.*)$", "", raw_brand).strip()
                    brand = self.normalizer.extract_brand(title, brand)

                    price = self.runningwarehouse.parse_price(cell.get("data-gtm_impression_price"))
                    if not price:
                        m_p = re.search(r"(\d+[\.,]\d{2})\s*€", cell.text)
                        if m_p:
                            price = self.runningwarehouse.parse_price(m_p.group(1))
                    if not price:
                        continue

                    orig_price = None
                    m_srp = re.search(r"SRP\s*(\d+[\.,]\d{2})", cell.text)
                    if m_srp:
                        orig_price = self.runningwarehouse.parse_price(m_srp.group(1))

                    img_el = cell.select_one("img")
                    img_url = img_el.get("src") if img_el else None
                    if img_url and "nw=210" in img_url:
                        img_url = img_url.replace("nw=210", "nw=500")

                    pid = cell.get("data-code")

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
                        in_stock=True
                    )

                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=self._detect_category(offer.title),
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception:
                    continue

        logger.info(f"[Running Warehouse] Indexed {total_indexed} products.")
        return total_indexed

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
            "casco", "pompa", "luce", "bici", "padel", "racchetta", "overgrip", "tubo palline",
            "kask", "poc ", "bullpadel", "nox", "babolat", "copertone", "salopette", "shimano",
            "wilson blade", "head speed"
        ]):
            return "gear"
        return "running_shoes"

    def crawl_deporvillage(self, max_items: int = 150) -> int:
        """Crawl Deporvillage catalog via Algolia API, focusing on accessories, GPS, padel & outdoor."""
        logger.info(f"[Deporvillage] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        queries = [
            "garmin", "polar", "suunto", "oakley sutro", "oakley radar",
            "salomon active skin", "theragun", "enervit", "casco poc", "nike pegasus",
            "la sportiva", "bullpadel", "salewa", "saucony endorphin", "hoka bondi",
            "brooks ghost", "maurten", "hyperice", "babolat padel", "kask protone"
        ]

        for q in queries:
            if total_indexed >= max_items:
                break
            offers = self.deporvillage.search(query=q, limit=min(max_items - total_indexed, 25))
            for offer in offers:
                try:
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    brand = offer.brand or self.normalizer.extract_brand(offer.title)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=category,
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception as e:
                    logger.debug(f"[Deporvillage] Upsert skip: {e}")
                    continue

        logger.info(f"[Deporvillage] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_alltricks(self, max_items: int = 150) -> int:
        """Crawl Alltricks catalog via Constructor.io API, focusing on cycling, GPS, padel & fitness gear."""
        logger.info(f"[Alltricks] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        queries = [
            "garmin edge", "garmin forerunner", "oakley radar", "casco poc",
            "salomon gilet", "theragun", "polar", "enervit", "asics nimbus",
            "kask protone", "racchetta padel", "brooks glycerin", "hoka speedgoat",
            "shimano pedali", "maurten gel", "oakley sutro", "saucony triumph"
        ]

        for q in queries:
            if total_indexed >= max_items:
                break
            offers = self.alltricks.search(query=q, limit=min(max_items - total_indexed, 25))
            for offer in offers:
                try:
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    brand = offer.brand or self.normalizer.extract_brand(offer.title)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=category,
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception as e:
                    logger.debug(f"[Alltricks] Upsert skip: {e}")
                    continue

        logger.info(f"[Alltricks] Indexed {total_indexed} products.")
        return total_indexed

    def crawl_decathlon(self, max_items: int = 150) -> int:
        """Crawl Decathlon Italy catalog across top sports, running gear, padel & cycling."""
        logger.info(f"[Decathlon] Starting catalog crawl (target: {max_items} items)...")
        total_indexed = 0
        queries = [
            "scarpe running", "garmin forerunner", "asics novablast", "nike pegasus",
            "salomon speedcross", "hoka clifton", "polar vantage", "trail running",
            "racchetta padel", "zaino trail", "fascia cardio", "theragun", "occhiali ciclismo",
            "gel energetici", "manubri palestra", "saucony endorphin", "casco bici",
            "bullpadel", "kettlebell", "enervit"
        ]

        for q in queries:
            if total_indexed >= max_items:
                break
            offers = self.decathlon.search(query=q, limit=min(max_items - total_indexed, 25))
            for offer in offers:
                try:
                    cluster_key = self.normalizer.extract_cluster_key(offer)
                    canonical_base, _ = self.normalizer.clean_title(offer.title)
                    gender = self.normalizer.extract_gender(offer.title, offer.url)
                    brand = offer.brand or self.normalizer.extract_brand(offer.title)
                    canonical = f"{brand} {canonical_base.title()}" if brand and brand.lower() not in canonical_base.lower() else canonical_base.title()
                    category = self._detect_category(offer.title)

                    self.db.upsert_product_and_offer(
                        cluster_key=cluster_key,
                        canonical_name=canonical,
                        brand=brand,
                        category=category,
                        gender=gender,
                        offer=offer
                    )
                    total_indexed += 1
                    if total_indexed >= max_items:
                        break
                except Exception as e:
                    logger.debug(f"[Decathlon] Upsert skip: {e}")
                    continue

        logger.info(f"[Decathlon] Indexed {total_indexed} products.")
        return total_indexed

    def run_full_sync(self, limit_per_store: int = 150) -> Dict[str, Any]:
        """Run crawling across all 9 stores and populate the database."""
        start_time = time.time()
        counts = {}

        counts["cisalfa"] = self.crawl_cisalfa(max_items=limit_per_store)
        counts["maxisport"] = self.crawl_maxisport(max_items=limit_per_store)
        counts["misterrunning"] = self.crawl_misterrunning(max_items=limit_per_store)
        counts["nencini"] = self.crawl_nencini(max_items=limit_per_store)
        counts["top4running"] = self.crawl_top4running(max_items=limit_per_store)
        counts["runningwarehouse"] = self.crawl_runningwarehouse(max_items=limit_per_store)
        counts["deporvillage"] = self.crawl_deporvillage(max_items=limit_per_store)
        counts["alltricks"] = self.crawl_alltricks(max_items=limit_per_store)
        counts["decathlon"] = self.crawl_decathlon(max_items=limit_per_store)

        elapsed = round(time.time() - start_time, 2)
        stats = self.db.get_stats()

        return {
            "duration_seconds": elapsed,
            "crawled_by_store": counts,
            "total_crawled": sum(counts.values()),
            "catalog_stats": stats
        }
