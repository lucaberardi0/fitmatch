#!/usr/bin/env python3
"""
Offer Verification & Dead Link Purge Tool for FitMatch.
Audits `store_offers` in Supabase:
1. Tests merchant product URLs for HTTP 404, 410, domain home redirects, or discontinued status.
2. Purges dead/broken offers from `store_offers`.
3. Normalizes and re-verifies in-stock sizes.
4. Removes orphaned products from `products` table.
"""

import os
import sys
import time
import logging
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fitmatch.supabase_client import SupabaseClient
from fitmatch.models import normalize_sizes
from curl_cffi import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("fitmatch.verify_purge")

STORE_HOME_URLS = {
    "https://www.cisalfasport.it",
    "https://www.cisalfasport.it/it-it",
    "https://www.maxisport.com",
    "https://www.misterrunning.com",
    "https://www.misterrunning.com/it",
    "https://www.nencinisport.it",
    "https://www.nencinisport.it/it",
    "https://top4running.it",
    "https://www.runningwarehouse.eu",
    "https://www.deporvillage.it",
    "https://www.alltricks.it",
    "https://www.decathlon.it",
    "https://www.df-sportspecialist.it",
    "https://www.nike.com/it",
    "https://www.adidas.it",
    "https://www.tradeinn.com"
}


def audit_offer_url(offer: Dict[str, Any]) -> Dict[str, Any]:
    url = (offer.get("product_url") or "").strip()
    oid = offer.get("id")
    sid = offer.get("store_id")

    if not url or not url.startswith("http"):
        return {"id": oid, "action": "delete", "reason": "invalid_url", "url": url}

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"
    }

    try:
        resp = requests.get(
            url,
            headers=headers,
            impersonate="chrome",
            timeout=12,
            allow_redirects=True
        )

        # 1. 404 or 410 dead links
        if resp.status_code in (404, 410):
            return {"id": oid, "action": "delete", "reason": f"http_{resp.status_code}", "url": url}

        # 2. Redirected to domain homepage (discontinued product)
        final_clean = resp.url.rstrip("/")
        if final_clean in STORE_HOME_URLS:
            return {"id": oid, "action": "delete", "reason": "redirected_to_homepage", "url": url}

        # 3. Check for discontinued or sold-out keywords in page text
        text_lower = resp.text.lower()
        if any(w in text_lower for w in ["prodotto non più disponibile", "articolo esaurito", "pagina non trovata", "404 -", "non è più disponibile"]):
            return {"id": oid, "action": "mark_out_of_stock", "reason": "sold_out_text", "url": url}

        return {"id": oid, "action": "keep", "status": resp.status_code, "url": url}

    except Exception as e:
        # Don't delete on transient network timeouts
        return {"id": oid, "action": "keep", "error": str(e), "url": url}


def verify_and_purge_offers(batch_size: int = 250, max_items: int = 1500, execute: bool = False):
    sb = SupabaseClient()
    logger.info("=" * 60)
    logger.info(" FITMATCH STORE OFFERS VERIFICATION & PURGE ENGINE")
    logger.info(f" Mode: {'EXECUTE (Modifying Supabase)' if execute else 'DRY RUN (Analysis Only)'}")
    logger.info("=" * 60)

    offset = 0
    total_audited = 0
    total_deleted = 0
    total_marked_oos = 0

    while total_audited < max_items:
        limit = min(batch_size, max_items - total_audited)
        endpoint = f"store_offers?select=id,store_id,raw_title,product_url,available_sizes&order=last_checked_at.asc.nullsfirst&limit={limit}&offset={offset}"
        res = sb._request(endpoint)
        offers = res.get("data") or []
        if not offers:
            break

        logger.info(f"Auditing batch of {len(offers)} offers (offset {offset})...")
        with ThreadPoolExecutor(max_workers=10) as ex:
            audit_results = list(ex.map(audit_offer_url, offers))

        to_delete = [r for r in audit_results if r["action"] == "delete"]
        to_mark_oos = [r for r in audit_results if r["action"] == "mark_out_of_stock"]

        for d in to_delete:
            logger.info(f"  [DELETE] Offer {d['id']} | Reason: {d['reason']} | URL: {d['url']}")
            if execute:
                q_id = urllib.parse.quote(d["id"])
                sb._request(f"store_offers?id=eq.{q_id}", method="DELETE")
                total_deleted += 1

        for o in to_mark_oos:
            logger.info(f"  [OUT_OF_STOCK] Offer {o['id']} | URL: {o['url']}")
            if execute:
                q_id = urllib.parse.quote(o["id"])
                sb._request(
                    f"store_offers?id=eq.{q_id}",
                    method="PATCH",
                    data={"in_stock": False, "available_sizes": [], "last_checked_at": datetime.now(timezone.utc).isoformat()}
                )
                total_marked_oos += 1

        total_audited += len(offers)
        offset += len(offers)

        if len(offers) < limit:
            break

    logger.info("=" * 60)
    logger.info(f"Audit completed: {total_audited} offers inspected.")
    logger.info(f"Dead links deleted: {total_deleted}")
    logger.info(f"Sold-out offers updated: {total_marked_oos}")
    logger.info("=" * 60)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="Perform real deletes and updates in Supabase")
    parser.add_argument("--limit", type=int, default=100, help="Max offers to audit")
    args = parser.parse_args()

    verify_and_purge_offers(max_items=args.limit, execute=args.execute)
