import re
import json
import logging
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional, Dict, Any, Set
from bs4 import BeautifulSoup
from fitmatch.scrapers.base import BaseScraper
from fitmatch.models import Offer, normalize_sizes, is_female_context

logger = logging.getLogger("fitmatch.scraper.nike")


class NikeScraper(BaseScraper):
    """Scraper for Nike Italy (nike.com/it) — Official brand store and innovation benchmark."""

    store_id = "nike"
    store_name = "Nike"
    base_url = "https://www.nike.com/it"
    rating = 1.5
    review_count = 13200
    formatted_review_count = "13,2K"
    card_theme = "olive"
    accent_color = "#627D56"
    free_shipping_threshold = 99.00
    standard_shipping_cost = 5.00
    courier = "UPS / DHL Express"
    search_base_url = "https://www.nike.com/it/w"

    def __init__(self, timeout: int = 15):
        super().__init__(timeout=timeout)
        self.headers.update({
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Referer": "https://www.nike.com/it",
        })

    def search(self, query: str, limit: int = 10) -> List[Offer]:
        """Search Nike Italy catalog via Next.js rendered payload and structured product data."""
        clean_query = query.strip()
        if not clean_query:
            return []

        search_url = f"{self.search_base_url}?q={urllib.parse.quote_plus(clean_query)}"
        html = self._fetch_html(search_url)
        if not html:
            logger.warning(f"[Nike] Failed to fetch search HTML for '{query}'")
            return []

        offers = self._parse_wall_products(html, limit=limit)
        return offers

    def _parse_wall_products(self, html: str, limit: int = 10) -> List[Offer]:
        """Extract product cards from Next.js __NEXT_DATA__ wall state."""
        try:
            soup = BeautifulSoup(html, "html.parser")
            tag = soup.find("script", id="__NEXT_DATA__")
            if not tag or not tag.string:
                logger.debug("[Nike] No __NEXT_DATA__ tag found in page")
                return []

            data = json.loads(tag.string)
            wall = data.get("props", {}).get("pageProps", {}).get("initialState", {}).get("Wall", {})
            groupings = wall.get("productGroupings") or []

            offers: List[Offer] = []
            candidates = []
            seen_codes = set()

            for group in groupings:
                products = group.get("products") or []
                for p in products:
                    if not isinstance(p, dict):
                        continue

                    code = p.get("productCode") or p.get("internalPid") or p.get("globalProductId")
                    if not code or code in seen_codes:
                        continue
                    seen_codes.add(code)

                    copy_data = p.get("copy") or {}
                    title = (copy_data.get("title") or "").strip()
                    subtitle = (copy_data.get("subTitle") or "").strip()
                    if not title:
                        continue

                    full_title = f"{title} ({subtitle})" if subtitle else title

                    prices = p.get("prices") or {}
                    curr_price = prices.get("currentPrice")
                    if curr_price is None:
                        continue

                    init_price = prices.get("initialPrice")
                    disc_pct = prices.get("discountPercentage")

                    pdp = p.get("pdpUrl") or {}
                    purl = pdp.get("url") or ""
                    if purl.startswith("/"):
                        purl = f"https://www.nike.com{purl}"

                    imgs = p.get("colorwayImages") or {}
                    img_url = imgs.get("squarishURL") or imgs.get("portraitURL")
                    gallery_urls = []
                    for k in ["squarishURL", "portraitURL"]:
                        u = imgs.get(k)
                        if u and u not in gallery_urls:
                            gallery_urls.append(u)

                    candidates.append({
                        "code": str(code),
                        "title": full_title,
                        "price": float(curr_price),
                        "orig_price": float(init_price) if init_price and init_price > curr_price else None,
                        "disc_pct": float(disc_pct) if disc_pct and disc_pct > 0 else None,
                        "url": purl,
                        "image_url": img_url,
                        "gallery_images": gallery_urls
                    })

                    if len(candidates) >= limit:
                        break
                if len(candidates) >= limit:
                    break

            if not candidates:
                return []

            # Concurrently fetch sizes for all candidate items
            with ThreadPoolExecutor(max_workers=min(len(candidates), 8)) as executor:
                sizes_list = list(executor.map(lambda c: self.fetch_sizes(c["url"], title=c["title"]), candidates))

            for c, sizes in zip(candidates, sizes_list):
                offers.append(
                    Offer(
                        store_id=self.store_id,
                        store_name=self.store_name,
                        product_id=c["code"],
                        title=c["title"],
                        brand="Nike",
                        price=c["price"],
                        original_price=c["orig_price"],
                        discount_pct=c["disc_pct"],
                        url=c["url"],
                        image_url=c["image_url"],
                        gallery_images=c["gallery_images"],
                        available_sizes=sizes,
                        in_stock=bool(sizes)
                    )
                )

            return offers
        except Exception as e:
            logger.error(f"[Nike] Error parsing search wall: {e}")
            return []

    def _fetch_in_stock_gtins(self, style_color: str) -> Optional[Set[str]]:
        """Query Nike deliver/available_gtins/v3 for EU real-time stock by GTIN."""
        if not style_color:
            return None
        url = (
            "https://api.nike.com/deliver/available_gtins/v3"
            f"?filter=styleColor({urllib.parse.quote(style_color)})&filter=merchGroup(EU)"
        )
        data = self._fetch_json(url)
        if not isinstance(data, dict) or not isinstance(data.get("objects"), list):
            return None
        return {
            str(obj["gtin"])
            for obj in data["objects"]
            if isinstance(obj, dict)
            and obj.get("gtin")
            and obj.get("available") is True
            and obj.get("level") != "OOS"
        }

    def _extract_style_color(self, sp: Dict[str, Any], product_url: str) -> Optional[str]:
        sc = sp.get("styleColor")
        if sc:
            return str(sc).strip()
        m = re.search(r"/([A-Z0-9]{5,10}-[A-Z0-9]{2,5})(?:[/?#]|$)", product_url)
        return m.group(1) if m else None

    def _detect_nike_context(self, sp: Dict[str, Any], title: Optional[str]) -> tuple[Optional[str], Optional[str]]:
        genders = [str(g).upper() for g in (sp.get("genders") or ([sp.get("gender")] if sp.get("gender") else []))]
        gender: Optional[str] = None
        if "WOMEN" in genders and "MEN" not in genders:
            gender = "women"
        elif is_female_context(title=title):
            gender = "women"

        ptype = str(sp.get("productType") or "").strip().lower()
        category: Optional[str] = None
        if ptype == "apparel":
            category = "apparel"
        elif ptype == "equipment":
            category = "gear"
        elif ptype == "footwear":
            category = "shoes"
        return gender, category

    def fetch_sizes(self, product_url: str, title: Optional[str] = None) -> List[str]:
        """Fetch verified EU in-stock sizes from Nike PDP state intersected with deliver/available_gtins."""
        try:
            html = self._fetch_html(product_url)
            if not html:
                return []

            soup = BeautifulSoup(html, "html.parser")
            tag = soup.find("script", id="__NEXT_DATA__")
            if not tag or not tag.string:
                return []

            data = json.loads(tag.string)
            sp = data.get("props", {}).get("pageProps", {}).get("selectedProduct") or {}
            sizes_raw = sp.get("sizes") or []
            if not sizes_raw:
                return []

            style_color = self._extract_style_color(sp, product_url)
            in_stock_gtins = self._fetch_in_stock_gtins(style_color) if style_color else None
            if in_stock_gtins is None:
                # GTIN stock could not be verified: do not falsely mark catalog sizes as available
                return []

            active_sizes = []
            for s in sizes_raw:
                if not isinstance(s, dict) or s.get("status") != "ACTIVE":
                    continue
                s_gtins = {
                    str(g.get("gtin"))
                    for g in (s.get("gtins") or [])
                    if isinstance(g, dict) and g.get("gtin")
                }
                if s.get("gtin"):
                    s_gtins.add(str(s["gtin"]))
                if not (s_gtins & in_stock_gtins):
                    continue
                label = s.get("localizedLabel") or s.get("label")
                if label:
                    active_sizes.append(str(label))

            pdp_title = title or sp.get("title") or sp.get("subTitle")
            gender, category = self._detect_nike_context(sp, pdp_title)
            return normalize_sizes(active_sizes, gender=gender, category=category)
        except Exception as e:
            logger.warning(f"[Nike] Error fetching sizes for {product_url}: {e}")
            return []
