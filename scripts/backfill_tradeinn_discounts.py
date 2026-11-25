"""
Polite, rate-limited backfill of verified original_price (PVC/RRP), discount_pct,
live Italy price, stock status, and available sizes for Tradeinn offers using dc.tradeinn.com.

Usage:
    python3 scripts/backfill_tradeinn_discounts.py --limit 150 --min-price 30 --delay 0.4
"""

import argparse
import os
import re
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fitmatch.scrapers.tradeinn import TradeinnScraper
from fitmatch.supabase_client import SupabaseClient


def _extract_tradeinn_id(offer_id: str, url: str) -> Optional[str]:
    if offer_id and ":" in offer_id:
        tail = offer_id.split(":", 1)[1].strip()
        if tail.isdigit():
            return tail
    m = re.search(r"/(\d{6,12})/p(?:$|[/?#])", url or "")
    return m.group(1) if m else None


def run_backfill(limit: int = 150, min_price: float = 30.0, delay: float = 0.4) -> Dict[str, Any]:
    sb = SupabaseClient()
    if not sb.api_key or not sb.base_url:
        raise RuntimeError("SupabaseClient non configurato (manca SUPABASE_URL o SUPABASE_KEY).")

    endpoint = (
        f"store_offers?store_id=eq.tradeinn&in_stock=eq.true&original_price=is.null"
        f"&current_price=gte.{min_price}"
        f"&select=id,product_id,raw_title,current_price,product_url,available_sizes,in_stock"
        f"&order=last_checked_at.desc.nullslast&limit={int(limit)}"
    )
    res = sb._request(endpoint)
    rows: List[Dict[str, Any]] = res.get("data") or []
    print(f"[TradeinnBackfill] Loaded {len(rows)} candidate offers (min_price>={min_price} EUR)", flush=True)
    if not rows:
        return {"candidates": 0, "fetched": 0, "patched": 0, "discounted": 0, "oos": 0, "rate_limited": False}

    scraper = TradeinnScraper()
    now_iso = datetime.now(timezone.utc).isoformat()
    t0 = time.time()

    fetched = 0
    patched = 0
    discounted = 0
    oos = 0
    consecutive_rate_limits = 0
    aborted_rate_limit = False

    for idx, row in enumerate(rows, 1):
        oid = row["id"]
        url = row.get("product_url") or ""
        pid = _extract_tradeinn_id(oid, url)
        if not pid:
            continue

        old_price = float(row.get("current_price") or 0)
        details = scraper.fetch_product_details(
            pid,
            fallback_price=old_price,
            fallback_in_stock=bool(row.get("in_stock", True)),
            title=row.get("raw_title"),
            product_url=url,
            allow_html_fallback=False,
        )

        if details.get("rate_limited"):
            consecutive_rate_limits += 1
            if consecutive_rate_limits >= 3:
                print(
                    f"[TradeinnBackfill] Rate-limited by dc.tradeinn.com after {idx} items; stopping politely.",
                    flush=True,
                )
                aborted_rate_limit = True
                break
            time.sleep(max(delay * 3, 1.5))
            continue

        consecutive_rate_limits = 0
        if not details.get("dc_ok"):
            time.sleep(delay)
            continue

        fetched += 1
        price = float(details.get("price") or old_price)
        orig = details.get("original_price")
        disc = round(((orig - price) / orig) * 100.0, 1) if (orig and price and orig > price) else None
        in_stock = bool(details.get("in_stock", True))
        sizes = details.get("sizes") or row.get("available_sizes") or []

        if disc and disc >= 5.0 and in_stock:
            discounted += 1
        if not in_stock:
            oos += 1

        patch = {
            "current_price": round(price, 2),
            "original_price": round(orig, 2) if orig else None,
            "discount_pct": disc,
            "available_sizes": sizes,
            "in_stock": in_stock,
            "last_checked_at": now_iso,
        }
        q_id = urllib.parse.quote(oid, safe="")
        resp = sb._request(f"store_offers?id=eq.{q_id}", method="PATCH", data=patch)
        if resp.get("status") in (200, 204):
            patched += 1
            if abs(price - old_price) > 0.01:
                sb.record_price_history(oid, round(price, 2))

        if delay > 0:
            time.sleep(delay)

    elapsed = round(time.time() - t0, 1)
    print(
        f"[TradeinnBackfill] Done in {elapsed}s: fetched={fetched}, patched={patched}, "
        f"in_stock_discounted={discounted}, oos={oos}, aborted_rate_limit={aborted_rate_limit}",
        flush=True,
    )
    return {
        "candidates": len(rows),
        "fetched": fetched,
        "patched": patched,
        "discounted": discounted,
        "oos": oos,
        "rate_limited": aborted_rate_limit,
        "duration_seconds": elapsed,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Polite Tradeinn RRP/discounts backfill via dc.tradeinn.com")
    parser.add_argument("--limit", type=int, default=150)
    parser.add_argument("--min-price", type=float, default=30.0)
    parser.add_argument("--delay", type=float, default=0.4)
    args = parser.parse_args()
    run_backfill(limit=args.limit, min_price=args.min_price, delay=args.delay)
