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


def analyze_and_recluster(execute: bool = False, limit: int = 100000):
    sb = SupabaseClient()
    print("=" * 60)
    print(" FITMATCH DATABASE RE-CLUSTERING ENGINE")
    print(f" Mode: {'EXECUTE (Writing to Supabase)' if execute else 'DRY RUN (Read-only analysis)'}")
    print("=" * 60)

    # 1. Fetch existing master products using fast keyset pagination (immune to OFFSET timeouts)
    print("\n[1/4] Fetching existing products and store offers from Supabase...")
    t0 = time.time()
    existing_products: Dict[str, Dict[str, Any]] = {}
    page_size = 1000
    last_prod_id = None
    while len(existing_products) < limit:
        ep = f"products?select=id,canonical_name,brand,category,gender,image_url&order=id.asc&limit={page_size}"
        if last_prod_id is not None:
            ep += f"&id=gt.{urllib.parse.quote(last_prod_id, safe='')}"
        resp = sb._request(ep, timeout=30)
        batch = resp.get("data") or []
        if not batch:
            break
        for p in batch:
            existing_products[p["id"]] = p
        last_prod_id = batch[-1]["id"]
        if len(batch) < page_size:
            break
    print(f"  Fetched {len(existing_products)} existing master products in {time.time() - t0:.2f}s.")

    # 2. Keyset-page through all store offers
    t1 = time.time()
    all_offers: List[Dict[str, Any]] = []
    last_offer_id = None

    while len(all_offers) < limit:
        endpoint = f"store_offers?select=id,product_id,raw_title,store_name,store_id,current_price,original_price,discount_pct,product_url,image_url,available_sizes,in_stock&order=id.asc&limit={page_size}"
        if last_offer_id is not None:
            endpoint += f"&id=gt.{urllib.parse.quote(last_offer_id, safe='')}"
        resp = sb._request(endpoint, timeout=30)
        batch = resp.get("data") or []
        if not batch:
            break
        all_offers.extend(batch)
        last_offer_id = batch[-1]["id"]
        print(f"  Fetched {len(all_offers)} offers...", end="\r", flush=True)
        if len(batch) < page_size:
            break

    print(f"\n  Fetched {len(all_offers)} total offers in {time.time() - t1:.2f}s.")

    # 3. Cluster offers using ProductNormalizer
    print("\n[2/4] Running ProductNormalizer entity resolution across all offers...")
    raw_clusters: Dict[str, List[tuple]] = {}

    for row in all_offers:
        title = row.get("raw_title") or ""
        off = Offer(
            title=title,
            store_name=row.get("store_name") or "",
            store_id=(row.get("store_id") or row.get("store_name") or "").lower(),
            price=float(row.get("current_price") or 0.0),
            original_price=float(row.get("original_price")) if row.get("original_price") else None,
            discount_pct=float(row.get("discount_pct")) if row.get("discount_pct") else None,
            url=row.get("product_url") or "https://example.com",
            image_url=clean_image_url(row.get("image_url")),
            available_sizes=row.get("available_sizes") or [],
            in_stock=row.get("in_stock") is not False,
        )

        cluster_key = ProductNormalizer.extract_cluster_key(off)
        raw_clusters.setdefault(cluster_key, []).append((row, off))

    # Apply price sanity partitioning so extreme price outliers (e.g. €19 case vs €400 device) never share a cluster
    clusters: Dict[str, Dict[str, Any]] = {}
    for base_key, pair_list in raw_clusters.items():
        if len(pair_list) <= 1:
            partitions = [pair_list]
        else:
            off_to_row = {id(off): row for row, off in pair_list}
            parts = ProductNormalizer.partition_by_price_sanity([off for _, off in pair_list])
            partitions = [[(off_to_row[id(o)], o) for o in p] for p in parts if p]

        for part_idx, part_pairs in enumerate(partitions):
            eff_key = base_key if part_idx == 0 else f"{base_key} [alt-{part_idx}]"
            for row, off in part_pairs:
                title = row.get("raw_title") or ""
                prev_ex = existing_products.get(row.get("product_id") or "")
                prev_brand = prev_ex.get("brand") if prev_ex else None
                brand = ProductNormalizer.extract_brand(title, existing_brand=prev_brand, url=off.url) or prev_brand
                display_name = ProductNormalizer.build_canonical_display_name(title, brand=brand, url=off.url)
                art_type = ProductNormalizer.detect_article_type(title, url=off.url)
                if art_type != "case" and any(k in (off.url or "").lower() for k in ("copertura", "custodia", "silicone-case", "pellicola")):
                    art_type = "case"
                gender = ProductNormalizer.extract_gender(title, off.url)

                if eff_key not in clusters:
                    clusters[eff_key] = {
                        "cluster_key": eff_key,
                        "canonical_name": display_name,
                        "brand": brand,
                        "category": art_type,
                        "gender": gender,
                        "image_url": off.image_url,
                        "offers": []
                    }
                else:
                    existing_name = clusters[eff_key]["canonical_name"]
                    existing_brand = clusters[eff_key]["brand"]
                    if brand and not existing_brand:
                        clusters[eff_key]["brand"] = brand
                        existing_brand = brand
                    # Upgrade generic 'gear' category when another offer in the cluster resolves specifically
                    if clusters[eff_key]["category"] in (None, "", "gear", "other") and art_type not in (None, "", "gear", "other"):
                        clusters[eff_key]["category"] = art_type
                    # Prefer a clean display name that includes the resolved brand and isn't overly verbose
                    cand_has_brand = bool(existing_brand and existing_brand.lower() in display_name.lower())
                    curr_has_brand = bool(existing_brand and existing_brand.lower() in existing_name.lower())
                    if (
                        (cand_has_brand and not curr_has_brand and len(display_name) <= 60)
                        or (cand_has_brand == curr_has_brand and len(display_name) > len(existing_name) and len(display_name) <= 55)
                    ):
                        clusters[eff_key]["canonical_name"] = display_name

                if off.image_url and not clusters[eff_key]["image_url"]:
                    clusters[eff_key]["image_url"] = off.image_url

                clusters[eff_key]["offers"].append((row, off))

    # Align each cluster's master image_url with the cheapest active in-stock offer that has a valid image
    for ck, c in clusters.items():
        active_with_img = [
            off for _, off in c["offers"]
            if off.in_stock and off.price > 0 and off.image_url
        ]
        if active_with_img:
            active_with_img.sort(key=lambda o: o.price)
            c["image_url"] = active_with_img[0].image_url
            c["active_offer_images"] = {o.image_url for o in active_with_img}
        else:
            all_with_img = [off for _, off in c["offers"] if off.image_url]
            if all_with_img:
                all_with_img.sort(key=lambda o: o.price if o.price > 0 else 999999)
                c["image_url"] = all_with_img[0].image_url
            c["active_offer_images"] = {o.image_url for o in all_with_img}

    print(f"  Collapsed {len(all_offers)} offers into {len(clusters)} distinct master products!")

    # 4. Multi-store statistics & cross-store savings
    multi_store_clusters = [c for c in clusters.values() if len(set(x[1].store_name for x in c["offers"])) > 1]
    single_store_clusters = [c for c in clusters.values() if len(set(x[1].store_name for x in c["offers"])) == 1]

    # Compute diff against existing master products (in-place safe: preserves embeddings!)
    existing_multi_counts: Dict[str, set] = {}
    for row in all_offers:
        pid = row.get("product_id")
        if pid:
            existing_multi_counts.setdefault(pid, set()).add(row.get("store_name") or "")
    old_multi_store_count = sum(1 for stores in existing_multi_counts.values() if len(stores) > 1)

    changed_prod_rows: List[Dict[str, Any]] = []
    new_cluster_count = 0
    updated_meta_count = 0
    relinked_offer_count = 0
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    for ck, c in clusters.items():
        ex = existing_products.get(ck)
        eff_gender = c["gender"] or "Unisex"
        if ex is None:
            new_cluster_count += 1
            changed_prod_rows.append({
                "id": ck,
                "canonical_name": c["canonical_name"],
                "brand": c["brand"],
                "category": c["category"],
                "gender": eff_gender,
                "image_url": c["image_url"],
                "updated_at": now_iso,
            })
        else:
            eff_brand = c["brand"] or ex.get("brand")
            ex_img = ex.get("image_url")
            active_imgs = c.get("active_offer_images") or set()
            img_needs_heal = bool(c["image_url"] and (not ex_img or (active_imgs and ex_img not in active_imgs)))
            needs_update = (
                (ex.get("canonical_name") or "") != (c["canonical_name"] or "")
                or (ex.get("brand") or "") != (eff_brand or "")
                or (ex.get("category") or "") != (c["category"] or "")
                or (ex.get("gender") or "Unisex") != eff_gender
                or img_needs_heal
            )
            if needs_update:
                updated_meta_count += 1
                changed_prod_rows.append({
                    "id": ck,
                    "canonical_name": c["canonical_name"],
                    "brand": eff_brand,
                    "category": c["category"],
                    "gender": eff_gender,
                    "image_url": c["image_url"] if img_needs_heal else (ex_img or c["image_url"]),
                    "updated_at": now_iso,
                })
        relinked_offer_count += sum(1 for row, _ in c["offers"] if row.get("product_id") != ck)

    print("\n[3/4] Re-Clustering Results (Safe In-Place Diff):")
    print(f"  Distinct master products:    {len(clusters)} (existing rows: {len(existing_products)})")
    print(f"  Multi-store products:        {len(multi_store_clusters)} (was {old_multi_store_count})")
    print(f"  Single-store products:       {len(single_store_clusters)}")
    print(f"  Delta -> new clusters:       {new_cluster_count}")
    print(f"  Delta -> metadata updates:   {updated_meta_count} (existing embeddings preserved!)")
    print(f"  Delta -> offers to re-link:  {relinked_offer_count}")

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

    # 5. EXECUTE MODE: Apply ONLY the diff in-place to Supabase (preserves existing embeddings!)
    print("\n[4/4] Applying safe in-place delta to Supabase Cloud PostgreSQL...")

    # 5a. Upsert ONLY new or metadata-changed master products (never touches embedding column!)
    print(f"  Upserting {len(changed_prod_rows)} changed/new master products (skipping {len(clusters) - len(changed_prod_rows)} unchanged)...")
    prod_chunks = [changed_prod_rows[i:i + 40] for i in range(0, len(changed_prod_rows), 40)]

    def _upsert_chunk(chunk):
        sb.upsert_products(chunk)
        return len(chunk)

    upserted_count = 0
    with ThreadPoolExecutor(max_workers=4) as executor:
        for cnt in executor.map(_upsert_chunk, prod_chunks):
            upserted_count += cnt
            print(f"    Upserted {upserted_count}/{len(changed_prod_rows)} products...", end="\r", flush=True)
    print("\n    ✓ Master products delta upserted successfully (existing embeddings preserved).")

    # 5b. Update store_offers.product_id to cluster_key
    print("  Re-linking store offers to unified master product IDs...")
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
        for attempt in range(3):
            res = sb._request(endpoint, method="PATCH", data={"product_id": ck}, timeout=45)
            status = res.get("status")
            if status in (200, 204):
                return len(ids)
            if status == 409 and ck in clusters:
                # Ensure target master product exists (in case an earlier upsert timed out)
                c = clusters[ck]
                sb.upsert_products([{
                    "id": ck,
                    "canonical_name": c["canonical_name"],
                    "brand": c["brand"],
                    "category": c["category"],
                    "gender": c["gender"] or "Unisex",
                    "image_url": c["image_url"],
                    "updated_at": now_iso,
                }])
                continue
            time.sleep(0.5 * (attempt + 1))
        # Fallback: patch offers individually if a batch timed out
        done = 0
        for single_id in ids:
            q_one = urllib.parse.quote(f'("{single_id}")')
            r1 = sb._request(f"store_offers?id=in.{q_one}", method="PATCH", data={"product_id": ck}, timeout=45)
            if r1.get("status") in (200, 204):
                done += 1
        return done

    updated_offers = 0
    with ThreadPoolExecutor(max_workers=3) as executor:
        for count in executor.map(_execute_patch, patch_tasks):
            updated_offers += count
            print(f"    Re-linked {updated_offers}/{relinked_offer_count} offers...", end="\r", flush=True)

    print(f"\n    ✓ Successfully re-linked {updated_offers} store offers to unified cluster IDs.")
    print(f"  Multi-store products:  {len(multi_store_clusters)} (up from {old_multi_store_count})")
    print("  Done! Run `python3 scripts/generate_embeddings.py` next to backfill embeddings for new/unembedded active products.")
    print("\nRe-clustering completed successfully!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Re-cluster FitMatch product catalog in Supabase.")
    parser.add_argument("--execute", action="store_true", help="Actually apply the changes to Supabase")
    parser.add_argument("--limit", type=int, default=100000, help="Max offers to process")
    args = parser.parse_args()

    analyze_and_recluster(execute=args.execute, limit=args.limit)
