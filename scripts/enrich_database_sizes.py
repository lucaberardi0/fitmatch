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

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("fitmatch.enrich_sizes")


def enrich_sizes_for_store(
    store_id: str,
    limit: int = 500,
    max_workers: int = 10,
    dry_run: bool = False
):
    sb = SupabaseClient()
    logger.info(f"=== Starting Size Enrichment for Store: {store_id} (Target limit: {limit}) ===")

    # Initialize scraper
    scrapers = {
        "df_sportspecialist": DFSportScraper(),
        "df_sport": DFSportScraper(),
        "cisalfa": CisalfaScraper(),
        "maxisport": MaxiSportScraper(),
        "nike": NikeScraper(),
        "alltricks": AlltricksScraper(),
        "tradeinn": TradeinnScraper(),
        "decathlon": DecathlonScraper(),
        "runningwarehouse": RunningWarehouseScraper(),
    }

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

        sizes: List[str] = []
        try:
            if store_id == "decathlon":
                # For Decathlon, search by title gives the pre-rendered RSC sizes
                res = scraper.search(raw_title, limit=3)
                for o in res:
                    if o.available_sizes:
                        sizes = o.available_sizes
                        break
            else:
                sizes = scraper.fetch_sizes(purl)
        except Exception as e:
            logger.debug(f"Error fetching sizes for {oid}: {e}")

        if sizes:
            norm = normalize_sizes(sizes)
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
                            sb._request(f"store_offers?id=eq.{p['id']}", method="PATCH", data={"available_sizes": p["available_sizes"]})
                        updated_count += len(patches)
                    patches = []
                    logger.info(f"Enriched {success_count}/{len(offers)} offers so far...")

    # Flush remaining patches
    if patches and not dry_run:
        for p in patches:
            sb._request(f"store_offers?id=eq.{p['id']}", method="PATCH", data={"available_sizes": p["available_sizes"]})
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
        "df_sportspecialist",
        "cisalfa",
        "maxisport",
        "alltricks",
        "nike",
        "tradeinn",
        "decathlon",
        "runningwarehouse"
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
    scrapers = {
        "df_sportspecialist": DFSportScraper(),
        "df_sport": DFSportScraper(),
        "cisalfa": CisalfaScraper(),
        "maxisport": MaxiSportScraper(),
        "nike": NikeScraper(),
        "alltricks": AlltricksScraper(),
        "tradeinn": TradeinnScraper(),
        "decathlon": DecathlonScraper(),
        "runningwarehouse": RunningWarehouseScraper(),
    }

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

        sizes = []
        try:
            if sid == "decathlon":
                res = scraper.search(raw_title, limit=3)
                for o in res:
                    if o.available_sizes:
                        sizes = o.available_sizes
                        break
            else:
                sizes = scraper.fetch_sizes(purl)
        except Exception as e:
            logger.debug(f"Error on {oid}: {e}")

        if sizes:
            norm = normalize_sizes(sizes)
            if norm:
                return {"id": oid, "available_sizes": norm}
        return None

    updated = 0
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process, off): off for off in offers}
        for fut in as_completed(futures):
            res = fut.result()
            if res:
                sb._request(f"store_offers?id=eq.{res['id']}", method="PATCH", data={"available_sizes": res["available_sizes"]})
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
        "df_sportspecialist",
        "cisalfa",
        "maxisport",
        "alltricks",
        "nike",
        "tradeinn",
        "decathlon",
        "runningwarehouse"
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
