#!/usr/bin/env python3
"""
Recategorize active Supabase products using combined canonical_name + store_offers.raw_title,
normalize brand names, and isolate non-sporting junk (moto armor, marine hardware, foosball).
"""

import os
import sys
import time
import argparse
import urllib.parse
from collections import Counter
from typing import Dict, Any, List

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from fitmatch.supabase_client import SupabaseClient
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.crawler import CategoryCrawler


def main():
    parser = argparse.ArgumentParser(description="Clean up and recategorize FitMatch Supabase catalog")
    parser.add_argument("--execute", action="store_true", help="Apply updates to Supabase (default is dry-run)")
    args = parser.parse_args()

    sb = SupabaseClient()
    crawler = CategoryCrawler.__new__(CategoryCrawler)
    crawler.normalizer = ProductNormalizer()

    print(f"Fetching active products with offers (mode={'EXECUTE' if args.execute else 'DRY-RUN'})...")
    t0 = time.time()
    all_prods: List[Dict[str, Any]] = []
    offset = 0
    page_size = 1000

    while True:
        ep = (
            "products?select=id,canonical_name,brand,category,store_offers!inner(raw_title)"
            f"&order=id.asc&limit={page_size}&offset={offset}"
        )
        resp = sb._request(ep)
        batch = resp.get("data") or []
        if not batch:
            break
        all_prods.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size

    print(f"Fetched {len(all_prods)} active products in {time.time() - t0:.1f}s.")

    cat_transitions = Counter()
    brand_updates = 0
    updates: List[Dict[str, Any]] = []

    for p in all_prods:
        pid = p["id"]
        cname = p.get("canonical_name") or ""
        old_cat = p.get("category") or ""
        old_brand = p.get("brand")
        raw_titles = [o.get("raw_title") or "" for o in (p.get("store_offers") or [])[:2]]
        combined = f"{cname} {' '.join(raw_titles)}".strip()

        new_cat = crawler._detect_category(combined)
        new_brand = ProductNormalizer.extract_brand(combined, existing_brand=old_brand)
        if new_cat == "non_sport":
            # Prevent false Brooks/brand attribution on moto armor etc.
            if old_brand == "Brooks" and "furygan" in combined.lower():
                new_brand = "Furygan"

        cat_changed = new_cat != old_cat
        brand_changed = bool(new_brand and new_brand != old_brand)

        if cat_changed:
            cat_transitions[(old_cat, new_cat)] += 1
        if brand_changed:
            brand_updates += 1

        if cat_changed or brand_changed:
            payload: Dict[str, Any] = {"id": pid}
            if cat_changed:
                payload["category"] = new_cat
            if brand_changed:
                payload["brand"] = new_brand
            updates.append(payload)

    print(f"\nPlanned updates: {len(updates)} products (brand fixes: {brand_updates})")
    print("Top category transitions:")
    for (oc, nc), cnt in cat_transitions.most_common(30):
        print(f"  {oc or 'NULL':16s} -> {nc:16s} : {cnt}")

    if not args.execute:
        print("\nDry-run complete. Re-run with --execute to apply changes.")
        return

    print("\nApplying updates to Supabase...")
    from concurrent.futures import ThreadPoolExecutor, as_completed
    applied = 0
    failed = 0

    def _patch_one(u: Dict[str, Any]):
        pid = u["id"]
        body = {k: v for k, v in u.items() if k != "id"}
        ep = f"products?id=eq.{urllib.parse.quote(pid, safe='')}"
        return pid, sb._request(ep, method="PATCH", data=body)

    with ThreadPoolExecutor(max_workers=12) as pool:
        futures = [pool.submit(_patch_one, u) for u in updates]
        for idx, fut in enumerate(as_completed(futures)):
            pid, res = fut.result()
            if res.get("status") in (200, 204):
                applied += 1
            else:
                failed += 1
                if failed <= 5:
                    print(f"  Warning updating {pid}: {res.get('error')}")
            if (idx + 1) % 500 == 0 or (idx + 1) == len(updates):
                print(f"  Progress: {idx + 1}/{len(updates)} (ok={applied}, err={failed})", flush=True)

    print(f"Done! Applied {applied} updates (failed={failed}) in {time.time() - t0:.1f}s.")


if __name__ == "__main__":
    main()
