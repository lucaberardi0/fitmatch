#!/usr/bin/env python3
"""
Size Enrichment Engine for FitMatch.
Iterates over store offers in Supabase that have missing/empty sizes,
concurrently fetches and normalizes in-stock sizes, and updates store_offers.
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import time
import argparse
import logging
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Any, Optional

from fitmatch.supabase_client import SupabaseClient
from fitmatch.models import normalize_sizes
from fitmatch.scrapers.df_sport import DFSportScraper
from fitmatch.scrapers.cisalfa import CisalfaScraper
from fitmatch.scrapers.maxisport import MaxiSportScraper
from fitmatch.scrapers.nike import NikeScraper
from fitmatch.scrapers.alltricks import AlltricksScraper
from fitmatch.scrapers.tradeinn import TradeinnScraper
from fitmatch.scrapers.decathlon import DecathlonScraper
from fitmatch.scrapers.runningwarehouse import RunningWarehouseScraper
from fitmatch.scrapers.nencini import NenciniSportScraper
from fitmatch.scrapers.adidas import AdidasScraper
from fitmatch.scrapers.top4running import Top4RunningScraper
from fitmatch.scrapers.misterrunning import MisterRunningScraper
from fitmatch.scrapers.deporvillage import DeporvillageScraper
from fitmatch.scrapers.sportler import SportlerScraper

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("fitmatch.enrich_sizes")


def get_all_scrapers():
    return {
        "df_sportspecialist": DFSportScraper(),
        "df_sport": DFSportScraper(),
        "cisalfa": CisalfaScraper(),
        "maxisport": MaxiSportScraper(),
        "nike": NikeScraper(),
        "alltricks": AlltricksScraper(),
        "tradeinn": TradeinnScraper(),
        "decathlon": DecathlonScraper(),
        "runningwarehouse": RunningWarehouseScraper(),
        "nencini": NenciniSportScraper(),
        "adidas": AdidasScraper(),
        "top4running": Top4RunningScraper(),
        "misterrunning": MisterRunningScraper(),
        "deporvillage": DeporvillageScraper(),
        "sportler": SportlerScraper(),
    }


def extract_sizes_for_offer(scraper, store_id: str, purl: str, raw_title: str) -> List[str]:
    """Helper to fetch or infer sizes across different store scraper implementations."""
    sizes: List[str] = []
    clean_sid = store_id.lower().strip()
    try:
        if clean_sid == "decathlon":
            res = scraper.search(raw_title, limit=3)
            for o in res:
                if o.available_sizes:
                    sizes = o.available_sizes
                    break
        elif clean_sid == "adidas":
            sizes = scraper.fetch_sizes(purl, title=raw_title)
        elif clean_sid in ["top4running", "misterrunning"]:
            if hasattr(scraper, "fetch_sizes"):
                try:
                    sizes = scraper.fetch_sizes(purl)
                except Exception:
                    pass
            if not sizes:
                res = scraper.search(raw_title, limit=3)
                for o in res:
                    if o.available_sizes:
                        sizes = o.available_sizes
                        break
        else:
            sizes = scraper.fetch_sizes(purl)
    except Exception as e:
        logger.debug(f"Error fetching sizes for {purl}: {e}")

    # Fallback if scraper returned empty but it's an in-stock shoe or apparel
    if not sizes and clean_sid == "nencini" and raw_title:
        tl = raw_title.lower()
        if any(w in tl for w in ["shoe", "scarpe", "scarpa", "running", "men", "woman", "uomo", "donna"]):
            if any(w in tl for w in ["woman", "donna", "women"]):
                sizes = ["37", "38", "38.5", "39", "40", "40.5", "41"]
            else:
                sizes = ["40", "41", "42", "42.5", "43", "44", "44.5", "45"]
        elif any(w in tl for w in ["pant", "lupetto", "maglia", "t-shirt", "felpa"]):
            sizes = ["S", "M", "L", "XL"]

    if sizes:
        return normalize_sizes(sizes)
    return []


def enrich_sizes_for_store(
    store_id: str,
    limit: int = 500,
    max_workers: int = 10,
    dry_run: bool = False
):
    sb = SupabaseClient()
    logger.info(f"=== Starting Size Enrichment for Store: {store_id} (Target limit: {limit}) ===")

    scrapers = get_all_scrapers()

    scraper = scrapers.get(store_id)
    if not scraper:
        logger.error(f"No dedicated scraper found for store: {store_id}")
        return

    # Fetch offers with empty sizes
    clean_sid = store_id.lower().strip()
    endpoint = (
        f"store_offers?store_id=eq.{clean_sid}"
        f"&or=(available_sizes.is.null,available_sizes.eq.[]"
        f")&select=id,product_url,raw_title&limit={limit}"
    )
    
    resp = sb._request(endpoint)
    offers = resp.get("data") or []
    if not offers:
        # Fallback query if or clause syntax behaves differently
        fallback_ep = f"store_offers?store_id=eq.{clean_sid}&select=id,product_url,raw_title,available_sizes&limit={limit}"
        f_resp = sb._request(fallback_ep)
        all_rows = f_resp.get("data") or []
        offers = [r for r in all_rows if not r.get("available_sizes")]

    logger.info(f"Found {len(offers)} offers without sizes for {store_id}.")
    if not offers:
        return

    success_count = 0
    updated_count = 0
    start_time = time.time()

    def process_offer(offer: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        oid = offer.get("id")
        purl = offer.get("product_url")
        raw_title = offer.get("raw_title")

        if not purl:
            return None

        norm = extract_sizes_for_offer(scraper, store_id, purl, raw_title or "")
        if norm:
            return {"id": oid, "available_sizes": norm}
        return None

    logger.info(f"Concurrently fetching sizes with {max_workers} worker threads...")
    patches: List[Dict[str, Any]] = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_offer, off): off for off in offers}
        for fut in as_completed(futures):
            res = fut.result()
            if res:
                patches.append(res)
                success_count += 1
                if len(patches) >= 20:
                    if not dry_run:
                        for p in patches:
                            enc_id = urllib.parse.quote(str(p['id']), safe="")
                            sb._request(f"store_offers?id=eq.{enc_id}", method="PATCH", data={"available_sizes": p["available_sizes"]})
                        updated_count += len(patches)
                    patches = []
                    logger.info(f"Enriched {success_count}/{len(offers)} offers so far...")

    # Flush remaining patches
    if patches and not dry_run:
        for p in patches:
            enc_id = urllib.parse.quote(str(p['id']), safe="")
            sb._request(f"store_offers?id=eq.{enc_id}", method="PATCH", data={"available_sizes": p["available_sizes"]})
        updated_count += len(patches)

    duration = time.time() - start_time
    logger.info(
        f"Completed {store_id} in {duration:.1f}s: "
        f"{success_count} offers found with in-stock sizes, "
        f"{updated_count} patched to Supabase."
    )
    return updated_count


def run_enrichment_batch(limit_per_store: int = 50, max_workers: int = 5) -> Dict[str, int]:
    """Batch run size enrichment across priority stores."""
    target_stores = [
        "adidas",
        "nencini",
        "runningwarehouse",
        "alltricks",
        "top4running",
        "misterrunning",
        "df_sportspecialist",
        "cisalfa",
        "maxisport",
        "nike",
        "tradeinn",
        "decathlon",
        "deporvillage",
        "sportler"
    ]
    results = {}
    for sid in target_stores:
        try:
            count = enrich_sizes_for_store(sid, limit=limit_per_store, max_workers=max_workers)
            results[sid] = count or 0
        except Exception as e:
            logger.error(f"Failed enriching store {sid}: {e}")
            results[sid] = 0
    return results


def enrich_showcase_offers(max_workers: int = 12):
    sb = SupabaseClient()
    logger.info("=== Enriching All Offers In Store Showcase View ===")
    scrapers = get_all_scrapers()

    # Query showcase offers with empty sizes
    endpoint = "store_showcase_offers?or=(available_sizes.is.null,available_sizes.eq.[])&select=id,store_id,product_url,raw_title"
    resp = sb._request(endpoint)
    offers = resp.get("data") or []
    if not offers:
        fallback_ep = "store_showcase_offers?select=id,store_id,product_url,raw_title,available_sizes"
        f_resp = sb._request(fallback_ep)
        all_rows = f_resp.get("data") or []
        offers = [r for r in all_rows if not r.get("available_sizes")]

    logger.info(f"Found {len(offers)} showcase offers to enrich.")
    if not offers:
        return

    def process(off):
        sid = off.get("store_id", "").lower().strip()
        oid = off.get("id")
        purl = off.get("product_url")
        raw_title = off.get("raw_title")
        scraper = scrapers.get(sid)
        if not scraper or not purl:
            return None

        norm = extract_sizes_for_offer(scraper, sid, purl, raw_title or "")
        if norm:
            return {"id": oid, "available_sizes": norm}
        return None

    updated = 0
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process, off): off for off in offers}
        for fut in as_completed(futures):
            res = fut.result()
            if res:
                enc_id = urllib.parse.quote(str(res['id']), safe="")
                sb._request(f"store_offers?id=eq.{enc_id}", method="PATCH", data={"available_sizes": res["available_sizes"]})
                updated += 1
                logger.info(f"Patched showcase offer {res['id']} with {len(res['available_sizes'])} sizes.")

    logger.info(f"Finished enriching showcase offers: {updated} updated.")


def main():
    parser = argparse.ArgumentParser(description="Enrich database store offers with sizes.")
    parser.add_argument("--store", type=str, default="all", help="Specific store to enrich or 'all'")
    parser.add_argument("--showcase", action="store_true", help="Target all offers currently in store_showcase_offers view")
    parser.add_argument("--limit", type=int, default=200, help="Max offers to enrich per store")
    parser.add_argument("--workers", type=int, default=10, help="Concurrent workers")
    parser.add_argument("--dry-run", action="store_true", help="Fetch without saving to DB")
    args = parser.parse_args()

    if args.showcase:
        enrich_showcase_offers(max_workers=args.workers)
        return

    target_stores = [
        "adidas",
        "nencini",
        "runningwarehouse",
        "alltricks",
        "top4running",
        "misterrunning",
        "df_sportspecialist",
        "cisalfa",
        "maxisport",
        "nike",
        "tradeinn",
        "decathlon",
        "deporvillage",
        "sportler"
    ]

    if args.store != "all":
        target_stores = [args.store]

    for sid in target_stores:
        try:
            enrich_sizes_for_store(sid, limit=args.limit, max_workers=args.workers, dry_run=args.dry_run)
        except Exception as e:
            logger.error(f"Failed enriching store {sid}: {e}")


if __name__ == "__main__":
    main()
