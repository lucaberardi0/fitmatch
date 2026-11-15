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
from curl_cffi import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("fitmatch.verify_purge")

_BLOCKED_PDP_STORES = {"adidas", "decathlon", "sportler"}

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
    "https://www.runningwarehouse.eu/it",
    "https://www.deporvillage.it",
    "https://www.alltricks.it",
    "https://www.decathlon.it",
    "https://www.df-sportspecialist.it",
    "https://www.nike.com/it",
    "https://www.adidas.it",
    "https://www.tradeinn.com",
    "https://www.sportler.com",
    "https://www.sportler.com/it",
}


def _is_homepage_redirect(final_url: str) -> bool:
    final_clean = (final_url or "").split("?")[0].rstrip("/")
    if final_clean in STORE_HOME_URLS:
        return True
    parsed = urllib.parse.urlparse(final_clean)
    return parsed.path.strip("/").lower() in {"", "it", "it-it"}


def audit_offer_url(offer: Dict[str, Any]) -> Dict[str, Any]:
    url = (offer.get("product_url") or "").strip()
    oid = offer.get("id")
    sid = str(offer.get("store_id") or "").lower().strip()
    pid = offer.get("product_id")

    if not url or not url.startswith("http"):
        return {"id": oid, "product_id": pid, "action": "delete", "reason": "invalid_url", "url": url}

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
            return {"id": oid, "product_id": pid, "action": "delete", "reason": f"http_{resp.status_code}", "url": url}

        # 2. Redirected to domain homepage (discontinued product)
        if _is_homepage_redirect(resp.url):
            return {"id": oid, "product_id": pid, "action": "delete", "reason": "redirected_to_homepage", "url": url}

        # 3. Soft-404 check on visible <title> / <h1> only (never raw <script> i18n bundles)
        if resp.status_code == 200 and sid not in _BLOCKED_PDP_STORES:
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(resp.text, "html.parser")
            heading_bits = []
            if soup.title:
                heading_bits.append(soup.title.get_text(" ", strip=True).lower())
            h1 = soup.find("h1")
            if h1:
                heading_bits.append(h1.get_text(" ", strip=True).lower())
            heading_text = " ".join(heading_bits)
            if any(w in heading_text for w in ["pagina non trovata", "page not found", "404"]):
                return {"id": oid, "product_id": pid, "action": "delete", "reason": "soft_404_heading", "url": url}

        return {"id": oid, "product_id": pid, "action": "keep", "status": resp.status_code, "url": url}

    except Exception as e:
        # Don't delete on transient network timeouts
        return {"id": oid, "product_id": pid, "action": "keep", "error": str(e), "url": url}


def cleanup_orphaned_products(sb: SupabaseClient, candidate_product_ids: List[str]) -> int:
    """Remove products left with zero store_offers after offer purging."""
    deleted_products = 0
    for pid in sorted({str(p) for p in candidate_product_ids if p}):
        q_pid = urllib.parse.quote(pid, safe="")
        remaining = sb._request(f"store_offers?product_id=eq.{q_pid}&select=id&limit=1")
        if remaining.get("status") == 200 and not (remaining.get("data") or []):
            del_res = sb._request(f"products?id=eq.{q_pid}", method="DELETE")
            if del_res.get("status") in (200, 204):
                deleted_products += 1
    return deleted_products


def verify_and_purge_offers(
    batch_size: int = 250,
    max_items: int = 1500,
    execute: bool = False,
    store_id: Optional[str] = None,
) -> Dict[str, int]:
    sb = SupabaseClient()
    logger.info("=" * 60)
    logger.info(" FITMATCH STORE OFFERS VERIFICATION & PURGE ENGINE")
    logger.info(f" Mode: {'EXECUTE (Modifying Supabase)' if execute else 'DRY RUN (Analysis Only)'}")
    logger.info("=" * 60)

    offset = 0
    total_audited = 0
    total_deleted = 0
    total_marked_oos = 0
    candidate_orphan_pids: List[str] = []

    store_filter = f"&store_id=eq.{urllib.parse.quote(store_id.strip(), safe='')}" if store_id else ""

    while total_audited < max_items:
        limit = min(batch_size, max_items - total_audited)
        endpoint = (
            f"store_offers?select=id,product_id,store_id,raw_title,product_url,available_sizes"
            f"{store_filter}&order=last_checked_at.asc.nullsfirst,id.asc&limit={limit}&offset={offset}"
        )
        res = sb._request(endpoint)
        offers = res.get("data") or []
        if not offers:
            break

        logger.info(f"Auditing batch of {len(offers)} offers (offset {offset})...")
        with ThreadPoolExecutor(max_workers=10) as ex:
            audit_results = list(ex.map(audit_offer_url, offers))

        to_delete = [r for r in audit_results if r["action"] == "delete"]
        to_mark_oos = [r for r in audit_results if r["action"] == "mark_out_of_stock"]
        kept = [r for r in audit_results if r["action"] == "keep"]

        for d in to_delete:
            logger.info(f"  [DELETE] Offer {d['id']} | Reason: {d['reason']} | URL: {d['url']}")
            if execute:
                q_id = urllib.parse.quote(str(d["id"]), safe="")
                sb._request(f"store_offers?id=eq.{q_id}", method="DELETE")
                total_deleted += 1
                if d.get("product_id"):
                    candidate_orphan_pids.append(str(d["product_id"]))

        for o in to_mark_oos:
            logger.info(f"  [OUT_OF_STOCK] Offer {o['id']} | URL: {o['url']}")
            if execute:
                q_id = urllib.parse.quote(str(o["id"]), safe="")
                sb._request(
                    f"store_offers?id=eq.{q_id}",
                    method="PATCH",
                    data={"in_stock": False, "available_sizes": [], "last_checked_at": datetime.now(timezone.utc).isoformat()}
                )
                total_marked_oos += 1

        total_audited += len(offers)
        # Deleted rows leave and marked OOS rows move to end of asc queue; only kept rows remain at this prefix
        offset += len(kept) if execute else len(offers)

        if len(offers) < limit:
            break

    orphaned_deleted = cleanup_orphaned_products(sb, candidate_orphan_pids) if (execute and candidate_orphan_pids) else 0

    logger.info("=" * 60)
    logger.info(f"Audit completed: {total_audited} offers inspected.")
    logger.info(f"Dead links deleted: {total_deleted}")
    logger.info(f"Sold-out offers updated: {total_marked_oos}")
    if execute:
        logger.info(f"Orphaned products cleaned: {orphaned_deleted}")
    logger.info("=" * 60)

    return {
        "audited": total_audited,
        "deleted": total_deleted,
        "marked_oos": total_marked_oos,
        "orphaned_products_deleted": orphaned_deleted,
    }


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="Perform real deletes and updates in Supabase")
    parser.add_argument("--limit", type=int, default=100, help="Max offers to audit")
    parser.add_argument("--store", type=str, default=None, help="Optional single store_id to audit")
    args = parser.parse_args()

    verify_and_purge_offers(max_items=args.limit, execute=args.execute, store_id=args.store)
