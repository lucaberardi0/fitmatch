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

from datetime import datetime, timezone
from fitmatch.supabase_client import SupabaseClient
from fitmatch.models import normalize_sizes
from fitmatch.matcher.normalizer import ProductNormalizer
from scripts.verify_and_purge_offers import audit_offer_url, cleanup_orphaned_products
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
from fitmatch.scrapers.shopify_stores import (
    SportITScraper,
    TennisPointScraper,
    BasketballStoreScraper,
    NonSoloSportScraper,
    IntersportScraper,
    BshopzoneScraper,
)

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
        "sportit": SportITScraper(),
        "tennis_point": TennisPointScraper(),
        "basketballstore": BasketballStoreScraper(),
        "nonsolosport": NonSoloSportScraper(),
        "intersport": IntersportScraper(),
        "bshopzone": BshopzoneScraper(),
    }


_BLOCKED_PDP_STORES = {"adidas", "decathlon", "sportler"}


def _urls_match(purl: str, candidate_url: str) -> bool:
    """Verify two store URLs refer to the same product path/slug before trusting search fallback."""
    if not purl or not candidate_url:
        return False
    p1 = urllib.parse.urlparse(purl).path.rstrip("/").lower()
    p2 = urllib.parse.urlparse(candidate_url).path.rstrip("/").lower()
    return bool(p1 and p2 and (p1 == p2 or p1.split("/")[-1] == p2.split("/")[-1]))


def extract_details_for_offer(scraper, store_id: str, purl: str, raw_title: str) -> Dict[str, Any]:
    """Fetch verified sizes, multi-angle gallery_images, and stock status in a single PDP request."""
    sizes: List[str] = []
    gallery: List[str] = []
    in_stock: Optional[bool] = None
    clean_sid = store_id.lower().strip()
    try:
        if clean_sid == "decathlon":
            res = scraper.search(raw_title, limit=5)
            for o in res:
                if _urls_match(purl, o.url):
                    if o.available_sizes:
                        sizes = o.available_sizes
                    if o.gallery_images:
                        gallery = list(o.gallery_images)
                    break
        elif clean_sid == "adidas":
            sizes = scraper.fetch_sizes(purl, title=raw_title)
        else:
            if hasattr(scraper, "fetch_pdp_details"):
                pdp = scraper.fetch_pdp_details(purl, title=raw_title) or {}
                sizes = pdp.get("sizes") or []
                gallery = pdp.get("gallery_images") or []
                in_stock = pdp.get("in_stock")
            else:
                sizes = scraper.fetch_sizes(purl, title=raw_title)

            if not sizes and clean_sid in ("top4running", "misterrunning", "deporvillage"):
                res = scraper.search(raw_title, limit=5)
                for o in res:
                    if _urls_match(purl, o.url):
                        if o.available_sizes:
                            sizes = o.available_sizes
                        if not gallery and o.gallery_images:
                            gallery = list(o.gallery_images)
                        break
    except Exception as e:
        logger.debug(f"Error fetching PDP details for {purl}: {e}")

    norm_sizes: List[str] = []
    if sizes:
        if hasattr(scraper, "normalize_sizes_for_product"):
            norm_sizes = scraper.normalize_sizes_for_product(sizes, title=raw_title, url=purl)
        else:
            normalizer = ProductNormalizer()
            norm_sizes = normalize_sizes(
                sizes,
                gender=normalizer.extract_gender(raw_title, purl),
                category=normalizer.detect_article_type(raw_title),
            )
    return {
        "sizes": norm_sizes,
        "gallery_images": gallery[:8],
        "in_stock": in_stock,
    }


def extract_sizes_for_offer(scraper, store_id: str, purl: str, raw_title: str) -> List[str]:
    """Fetch verified sizes for a specific offer URL without cross-product contamination."""
    return extract_details_for_offer(scraper, store_id, purl, raw_title).get("sizes", [])


def enrich_sizes_for_store(
    store_id: str,
    limit: int = 500,
    max_workers: int = 10,
    dry_run: bool = False,
    refresh_stale: bool = False,
    galleries_only: bool = False,
):
    sb = SupabaseClient()
    if galleries_only:
        mode_label = "Gallery + Size Enrichment"
    elif refresh_stale:
        mode_label = "Stale Size/Gallery Refresh"
    else:
        mode_label = "Size + Gallery Enrichment"
    logger.info(f"=== Starting {mode_label} for Store: {store_id} (Target limit: {limit}) ===")

    scrapers = get_all_scrapers()

    scraper = scrapers.get(store_id)
    if not scraper:
        logger.error(f"No dedicated scraper found for store: {store_id}")
        return 0

    clean_sid = store_id.lower().strip()
    if clean_sid in _BLOCKED_PDP_STORES and (refresh_stale or galleries_only):
        logger.info(f"Skipping PDP enrichment for anti-bot-gated store: {clean_sid}")
        return 0

    if galleries_only:
        # Target active offers currently missing multi-angle gallery_images (prioritize freshest/higher-value items)
        endpoint = (
            f"store_offers?store_id=eq.{clean_sid}&in_stock=neq.false&current_price=gt.20"
            f"&or=(gallery_images.is.null,gallery_images.eq.[])"
            f"&order=discount_pct.desc.nullslast,current_price.desc"
            f"&select=id,product_id,product_url,raw_title,image_url,available_sizes,gallery_images&limit={limit}"
        )
        resp = sb._request(endpoint)
        offers = resp.get("data") or []
        if len(offers) < limit:
            # Also catch offers that currently have only 1 image in gallery_images (e.g. df_sportspecialist)
            extra_ep = (
                f"store_offers?store_id=eq.{clean_sid}&in_stock=neq.false&current_price=gt.20"
                f"&order=discount_pct.desc.nullslast,current_price.desc"
                f"&select=id,product_id,product_url,raw_title,image_url,available_sizes,gallery_images&limit={min(limit * 3, 600)}"
            )
            extra_rows = sb._request(extra_ep).get("data") or []
            seen_ids = {r["id"] for r in offers}
            for r in extra_rows:
                if r["id"] in seen_ids:
                    continue
                g = r.get("gallery_images") or []
                if not isinstance(g, list) or len(g) < 2:
                    offers.append(r)
                    seen_ids.add(r["id"])
                    if len(offers) >= limit:
                        break
    elif refresh_stale:
        endpoint = (
            f"store_offers?store_id=eq.{clean_sid}"
            f"&order=last_checked_at.asc.nullsfirst"
            f"&select=id,product_id,product_url,raw_title,image_url,available_sizes,gallery_images&limit={limit}"
        )
        resp = sb._request(endpoint)
        offers = resp.get("data") or []
    else:
        # Fetch active offers with empty sizes
        endpoint = (
            f"store_offers?store_id=eq.{clean_sid}&in_stock=neq.false"
            f"&or=(available_sizes.is.null,available_sizes.eq.[])"
            f"&select=id,product_id,product_url,raw_title,image_url,available_sizes,gallery_images&limit={limit}"
        )
        resp = sb._request(endpoint)
        offers = resp.get("data") or []
        if not offers:
            fallback_ep = f"store_offers?store_id=eq.{clean_sid}&in_stock=neq.false&select=id,product_id,product_url,raw_title,image_url,available_sizes,gallery_images&limit={limit}"
            f_resp = sb._request(fallback_ep)
            all_rows = f_resp.get("data") or []
            offers = [r for r in all_rows if not r.get("available_sizes")]

    logger.info(f"Found {len(offers)} offers to check for {store_id}.")
    if not offers:
        return 0

    success_count = 0
    gallery_count = 0
    oos_count = 0
    updated_count = 0
    purged_count = 0
    candidate_orphan_pids: List[str] = []
    start_time = time.time()

    def process_offer(offer: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        oid = offer.get("id")
        pid = offer.get("product_id")
        purl = offer.get("product_url")
        raw_title = offer.get("raw_title") or ""
        existing_img = (offer.get("image_url") or "").strip()
        existing_gallery = offer.get("gallery_images") or []
        existing_sizes = offer.get("available_sizes") or []

        if not purl:
            return None

        details = extract_details_for_offer(scraper, store_id, purl, raw_title)
        norm = details.get("sizes") or []
        gallery = details.get("gallery_images") or []
        pdp_in_stock = details.get("in_stock")

        # Keep offer's existing primary image first when building gallery so hero thumbnail never jumps
        if gallery and existing_img and existing_img not in gallery:
            gallery = [existing_img] + gallery
        gallery = gallery[:8]

        payload: Dict[str, Any] = {"id": oid}
        has_new_gallery = len(gallery) >= 2 and (not isinstance(existing_gallery, list) or len(existing_gallery) < len(gallery))

        if norm:
            payload["available_sizes"] = norm
        if has_new_gallery:
            payload["gallery_images"] = gallery
        if pdp_in_stock is False and not norm:
            payload["available_sizes"] = []
            payload["in_stock"] = False

        if len(payload) > 1:
            payload["last_checked_at"] = datetime.now(timezone.utc).isoformat()
            return payload

        if refresh_stale:
            audit = audit_offer_url({"id": oid, "product_id": pid, "store_id": clean_sid, "product_url": purl})
            if audit.get("action") == "delete":
                return {"id": oid, "product_id": pid, "_action": "delete", "_reason": audit.get("reason")}
            if audit.get("action") == "mark_out_of_stock":
                return {
                    "id": oid,
                    "available_sizes": [],
                    "in_stock": False,
                    "last_checked_at": datetime.now(timezone.utc).isoformat(),
                }
            return {"id": oid, "last_checked_at": datetime.now(timezone.utc).isoformat()}

        # In gallery mode, touch last_checked_at only if we actually verified the page (avoid re-fetching empty ones forever)
        if galleries_only and existing_sizes and gallery:
            return {
                "id": oid,
                "gallery_images": gallery,
                "last_checked_at": datetime.now(timezone.utc).isoformat(),
            }
        return None

    logger.info(f"Concurrently fetching PDP details with {max_workers} worker threads...")
    patches: List[Dict[str, Any]] = []

    def _flush_patches(batch: List[Dict[str, Any]]) -> int:
        nonlocal purged_count
        if not batch or dry_run:
            return 0
        count = 0
        for p in batch:
            enc_id = urllib.parse.quote(str(p["id"]), safe="")
            if p.get("_action") == "delete":
                del_res = sb._request(f"store_offers?id=eq.{enc_id}", method="DELETE")
                if del_res.get("status") in (200, 204):
                    purged_count += 1
                    if p.get("product_id"):
                        candidate_orphan_pids.append(str(p["product_id"]))
                    count += 1
                continue
            patch_body = {k: v for k, v in p.items() if k != "id" and not k.startswith("_")}
            res = sb._request(f"store_offers?id=eq.{enc_id}", method="PATCH", data=patch_body)
            if res.get("status") in (200, 204):
                count += 1
        return count

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_offer, off): off for off in offers}
        for fut in as_completed(futures):
            res = fut.result()
            if res:
                patches.append(res)
                if res.get("available_sizes"):
                    success_count += 1
                if isinstance(res.get("gallery_images"), list) and len(res["gallery_images"]) >= 2:
                    gallery_count += 1
                if res.get("in_stock") is False:
                    oos_count += 1
                if len(patches) >= 20:
                    updated_count += _flush_patches(patches)
                    patches = []
                    logger.info(f"Processed {success_count} sizes / {gallery_count} galleries / {oos_count} OOS so far...")

    updated_count += _flush_patches(patches)
    if candidate_orphan_pids and not dry_run:
        cleanup_orphaned_products(sb, candidate_orphan_pids)

    duration = time.time() - start_time
    logger.info(
        f"Completed {store_id} in {duration:.1f}s: "
        f"{success_count} size updates, "
        f"{gallery_count} multi-image galleries, "
        f"{oos_count} marked OOS, "
        f"{purged_count} dead offers purged, "
        f"{updated_count} patched in Supabase."
    )
    return updated_count


def run_enrichment_batch(
    limit_per_store: int = 50,
    max_workers: int = 5,
    refresh_stale_limit: int = 15,
    gallery_limit_per_store: int = 0,
) -> Dict[str, int]:
    """Batch run missing-size enrichment, multi-angle gallery backfill, and stale-offer refresh across stores."""
    target_stores = [
        "alltricks",
        "basketballstore",
        "sportit",
        "maxisport",
        "nencini",
        "misterrunning",
        "top4running",
        "df_sportspecialist",
        "cisalfa",
        "intersport",
        "nonsolosport",
        "tennis_point",
        "bshopzone",
        "nike",
        "tradeinn",
        "deporvillage",
        "runningwarehouse",
        "adidas",
        "decathlon",
        "sportler",
    ]
    results = {}
    for sid in target_stores:
        try:
            count = enrich_sizes_for_store(sid, limit=limit_per_store, max_workers=max_workers) or 0
            if gallery_limit_per_store > 0 and sid not in _BLOCKED_PDP_STORES:
                count += enrich_sizes_for_store(
                    sid,
                    limit=gallery_limit_per_store,
                    max_workers=max_workers,
                    galleries_only=True,
                ) or 0
            if refresh_stale_limit > 0 and sid not in _BLOCKED_PDP_STORES:
                count += enrich_sizes_for_store(sid, limit=refresh_stale_limit, max_workers=max_workers, refresh_stale=True) or 0
            results[sid] = count
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
    parser.add_argument("--refresh-stale", action="store_true", help="Re-check existing populated offers ordered by oldest last_checked_at")
    parser.add_argument("--galleries", action="store_true", help="Backfill multi-angle gallery_images (and missing sizes) on active offers")
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
        "sportler",
        "sportit",
        "tennis_point",
        "basketballstore",
        "nonsolosport",
        "intersport",
        "bshopzone",
    ]

    if args.store != "all":
        target_stores = [args.store]

    for sid in target_stores:
        try:
            enrich_sizes_for_store(
                sid,
                limit=args.limit,
                max_workers=args.workers,
                dry_run=args.dry_run,
                refresh_stale=args.refresh_stale,
                galleries_only=args.galleries,
            )
        except Exception as e:
            logger.error(f"Failed enriching store {sid}: {e}")


if __name__ == "__main__":
    main()
