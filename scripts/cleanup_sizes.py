#!/usr/bin/env python3
"""
Clean up invalid, out-of-date, and fake size runs across all store_offers in Supabase.
"""
import sys
import logging
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Any
from fitmatch.supabase_client import SupabaseClient
from fitmatch.models import normalize_sizes

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("cleanup_sizes")

FAKE_ADIDAS_SET = {
    tuple(["40", "40.5", "41.5", "42", "42.5", "43.5", "44", "44.5", "45.5", "46", "46.5", "47.5"]),
    tuple(["40.5", "41.5", "42", "42.5", "43.5", "44", "44.5", "45.5", "46", "46.5", "47.5"]),
    tuple(["36", "36.5", "37.5", "38", "38.5", "39.5", "40", "40.5", "41.5", "42"]),
}
FAKE_NENCINI_SET = {
    tuple(["40", "41", "42", "42.5", "43", "44", "44.5", "45"]),
    tuple(["37", "38", "38.5", "39", "40", "40.5", "41"]),
}


def clean_offer(sb: SupabaseClient, offer: Dict[str, Any]) -> bool:
    oid = offer.get("id")
    if not oid:
        return False
    old_sizes = offer.get("available_sizes") or []
    
    # Check if known hardcoded fake size run
    old_tuple = tuple(old_sizes)
    if old_tuple in FAKE_ADIDAS_SET or old_tuple in FAKE_NENCINI_SET:
        new_sizes = []
    else:
        new_sizes = normalize_sizes(old_sizes)

    if new_sizes != old_sizes:
        q_id = urllib.parse.quote(oid)
        res = sb._request(f"store_offers?id=eq.{q_id}", method="PATCH", data={"available_sizes": new_sizes})
        if res.get("status") in (200, 204):
            logger.info(f"Updated {oid}: {old_sizes} -> {new_sizes}")
            return True
        else:
            logger.warning(f"Failed to update {oid}: {res}")
            return False
    return False


def main():
    sb = SupabaseClient()
    offset = 0
    batch_size = 500
    total_updated = 0
    total_inspected = 0

    logger.info("Starting database size cleanup...")

    while True:
        endpoint = f"store_offers?select=id,store_id,raw_title,available_sizes&limit={batch_size}&offset={offset}"
        res = sb._request(endpoint)
        offers = res.get("data") or []
        if not offers:
            break

        total_inspected += len(offers)
        logger.info(f"Fetched batch offset {offset}: {len(offers)} offers")

        with ThreadPoolExecutor(max_workers=10) as ex:
            results = list(ex.map(lambda o: clean_offer(sb, o), offers))

        total_updated += sum(1 for r in results if r)
        offset += batch_size

        if len(offers) < batch_size:
            break

    logger.info(f"Cleanup complete! Inspected: {total_inspected}, Updated: {total_updated}")


if __name__ == "__main__":
    main()
