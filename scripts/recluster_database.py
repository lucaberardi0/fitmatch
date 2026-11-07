#!/usr/bin/env python3
"""
Entity Re-Clustering & Multi-Store Unification Tool for FitMatch.
Iterates offers in Supabase, applies the updated ProductNormalizer logic,
identifies cross-store overlaps, and (optionally with --execute) updates
the canonical master products and points offers to unified cluster IDs.
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import time
import argparse
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Any
from fitmatch.supabase_client import SupabaseClient
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import Offer, clean_image_url


def analyze_and_recluster(execute: bool = False, limit: int = 15000):
    sb = SupabaseClient()
    print("=" * 60)
    print(" FITMATCH DATABASE RE-CLUSTERING ENGINE")
    print(f" Mode: {'EXECUTE (Writing to Supabase)' if execute else 'DRY RUN (Read-only analysis)'}")
    print("=" * 60)

    # 1. Fetch current catalog statistics
    stats_before = sb.get_stats()
    print("\n[Current Supabase Stats]")
    print(f"  Total products:        {stats_before.get('total_products')}")
    print(f"  Total offers:          {stats_before.get('total_offers')}")
    print(f"  Multi-store products:  {stats_before.get('multi_store_products')}")

    # 2. Page through all store offers
    print("\n[1/4] Fetching all store offers from Supabase...")
    t0 = time.time()
    all_offers: List[Dict[str, Any]] = []
    page_size = 1000
    offset = 0

    while offset < limit:
        endpoint = f"store_offers?select=id,product_id,raw_title,store_name,store_id,current_price,original_price,discount_pct,product_url,image_url,available_sizes&order=id.asc&limit={page_size}&offset={offset}"
        resp = sb._request(endpoint)
        batch = resp.get("data") or []
        if not batch:
            break
        all_offers.extend(batch)
        print(f"  Fetched {len(all_offers)} offers...", end="\r", flush=True)
        if len(batch) < page_size:
            break
        offset += page_size

    print(f"\n  Fetched {len(all_offers)} total offers in {time.time() - t0:.2f}s.")

    # 3. Cluster offers using ProductNormalizer
    print("\n[2/4] Running ProductNormalizer entity resolution across all offers...")
    clusters: Dict[str, Dict[str, Any]] = {}

    for row in all_offers:
        title = row.get("raw_title") or ""
        off = Offer(
            id=row.get("id") or "",
            title=title,
            store_name=row.get("store_name") or "",
            store_id=(row.get("store_id") or row.get("store_name") or "").lower(),
            price=float(row.get("current_price") or 0.0),
            original_price=float(row.get("original_price")) if row.get("original_price") else None,
            discount_pct=float(row.get("discount_pct")) if row.get("discount_pct") else None,
            url=row.get("product_url") or "https://example.com",
            image_url=clean_image_url(row.get("image_url")),
            available_sizes=row.get("available_sizes") or []
        )

        cluster_key = ProductNormalizer.extract_cluster_key(off)
        brand = ProductNormalizer.extract_brand(title)
        display_name = ProductNormalizer.build_canonical_display_name(title, brand=brand)
        art_type = ProductNormalizer.detect_article_type(title)
        gender = ProductNormalizer.extract_gender(title, off.url)

        if cluster_key not in clusters:
            clusters[cluster_key] = {
                "cluster_key": cluster_key,
                "canonical_name": display_name,
                "brand": brand,
                "category": art_type,
                "gender": gender,
                "image_url": off.image_url,
                "offers": []
            }
        else:
            # Prefer a richer canonical name if current one is very short
            if len(display_name) > len(clusters[cluster_key]["canonical_name"]) and len(display_name) <= 55:
                clusters[cluster_key]["canonical_name"] = display_name
            if brand and not clusters[cluster_key]["brand"]:
                clusters[cluster_key]["brand"] = brand
        
        # Keep highest quality image if available
        if off.image_url and not clusters[cluster_key]["image_url"]:
            clusters[cluster_key]["image_url"] = off.image_url

        clusters[cluster_key]["offers"].append((row, off))

    print(f"  Collapsed {len(all_offers)} offers into {len(clusters)} distinct master products!")

    # 4. Multi-store statistics & cross-store savings
    multi_store_clusters = [c for c in clusters.values() if len(set(x[1].store_name for x in c["offers"])) > 1]
    single_store_clusters = [c for c in clusters.values() if len(set(x[1].store_name for x in c["offers"])) == 1]

    print("\n[3/4] Re-Clustering Results:")
    print(f"  Distinct master products:    {len(clusters)}")
    print(f"  Multi-store products:        {len(multi_store_clusters)} (was {stats_before.get('multi_store_products')})")
    print(f"  Single-store products:       {len(single_store_clusters)}")

    # Show Top 10 Multi-Store Deals
    multi_store_with_savings = []
    for c in multi_store_clusters:
        prices = [x[1].price for x in c["offers"] if x[1].price > 0]
        if prices and max(prices) > min(prices):
            savings = max(prices) - min(prices)
            stores = set(x[1].store_name for x in c["offers"])
            multi_store_with_savings.append((c, stores, min(prices), max(prices), savings))

    multi_store_with_savings.sort(key=lambda x: x[4], reverse=True)

    print("\n  Top 10 Cross-Store Savings Discovered:")
    for c, stores, p_min, p_max, sav in multi_store_with_savings[:10]:
        brand_str = f"[{c['brand']}] " if c['brand'] else ""
        print(f"  • {brand_str}{c['canonical_name']} ({len(stores)} negozi: {', '.join(sorted(stores))})")
        print(f"    Prezzi: €{p_min:.2f} - €{p_max:.2f} -> Risparmio immediato: €{sav:.2f}")

    if not execute:
        print("\n[DRY RUN FINISHED] No database rows were modified.")
        print("To apply these changes directly to Supabase, run with: python3 scripts/recluster_database.py --execute")
        return

    # 5. EXECUTE MODE: Apply to Supabase
    print("\n[4/4] Applying changes to Supabase Cloud PostgreSQL...")
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # 5a. Upsert all master products
    print(f"  Upserting {len(clusters)} master products...")
    prod_rows = []
    for c in clusters.values():
        prod_rows.append({
            "id": c["cluster_key"],
            "canonical_name": c["canonical_name"],
            "brand": c["brand"],
            "category": c["category"],
            "gender": c["gender"] or "Unisex",
            "image_url": c["image_url"],
            "updated_at": now_iso
        })

    # Batch upsert in chunks of 100 (with fallback to 25 on statement timeout)
    chunk_size = 100
    for i in range(0, len(prod_rows), chunk_size):
        chunk = prod_rows[i:i + chunk_size]
        res = sb.upsert_products(chunk)
        if not res:
            for k in range(0, len(chunk), 25):
                sb.upsert_products(chunk[k:k + 25])
        print(f"    Upserted {min(i + chunk_size, len(prod_rows))}/{len(prod_rows)} products...", end="\r", flush=True)
    print("\n    ✓ Master products upserted successfully.")

    # 5b. Update store_offers.product_id to cluster_key
    print("  Re-linking store offers to new master product IDs...")
    patch_tasks = []
    for cluster_key, c_data in clusters.items():
        offer_ids = [row["id"] for row, off in c_data["offers"] if row.get("product_id") != cluster_key]
        for j in range(0, len(offer_ids), 40):
            sub_ids = offer_ids[j:j + 40]
            patch_tasks.append((cluster_key, sub_ids))

    print(f"  Executing {len(patch_tasks)} concurrent batch PATCH updates...")

    def _execute_patch(task):
        ck, ids = task
        id_list_str = ",".join(f'"{x}"' for x in ids)
        q_in = urllib.parse.quote(f"({id_list_str})")
        endpoint = f"store_offers?id=in.{q_in}"
        sb._request(endpoint, method="PATCH", data={"product_id": ck})
        return len(ids)

    updated_offers = 0
    with ThreadPoolExecutor(max_workers=6) as executor:
        for count in executor.map(_execute_patch, patch_tasks):
            updated_offers += count
            print(f"    Re-linked {updated_offers} offers...", end="\r", flush=True)

    print(f"\n    ✓ Successfully re-linked {updated_offers} store offers to unified cluster IDs.")

    # 5c. Clear stats cache
    sb._stats_cache = None
    stats_after = sb.get_stats()
    print("\n[Updated Supabase Stats]")
    print(f"  Total products:        {stats_after.get('total_products')}")
    print(f"  Total offers:          {stats_after.get('total_offers')}")
    print(f"  Multi-store products:  {stats_after.get('multi_store_products')} (up from {stats_before.get('multi_store_products')})")
    print("\nRe-clustering completed successfully!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Re-cluster FitMatch product catalog in Supabase.")
    parser.add_argument("--execute", action="store_true", help="Actually apply the changes to Supabase")
    parser.add_argument("--limit", type=int, default=15000, help="Max offers to process")
    args = parser.parse_args()

    analyze_and_recluster(execute=args.execute, limit=args.limit)
