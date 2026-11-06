#!/usr/bin/env python3
"""
FitMatch Semantic Vector Backfill Script
Generates vector embeddings (1536-dim) using OpenRouter's text-embedding-3-small
and stores them into Supabase PostgreSQL (pgvector).
"""

import os
import sys
import json
import time
import argparse
import logging
import ssl
import certifi
import urllib.request
from typing import List, Dict, Any, Optional
from dotenv import load_dotenv

# Ensure fitmatch root is in path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from fitmatch.supabase_client import SupabaseClient

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("generate_embeddings")

# Domain knowledge hints to maximize vector retrieval recall for athletic gear
DOMAIN_HINTS = {
    "dropset": "scarpe allenamento palestra crossfit hyrox stacco squat pesi",
    "metcon": "scarpe allenamento palestra crossfit pesi interval training",
    "nano": "scarpe crossfit allenamento funzionale palestra hyrox",
    "tribase": "scarpe crossfit allenamento pesi palestra",
    "forerunner": "orologio smartwatch gps cardio corsa running maratona triathlon",
    "fenix": "smartwatch sport outdoor multisport gps trekking running",
    "epix": "smartwatch amoled gps multisport trekking corsa",
    "edge": "ciclocomputer ciclocomputer gps bici ciclismo navigatore",
    "pegasus": "scarpe corsa running asfalto ammortizzate allenamento quotidiano",
    "vaporfly": "scarpe running gara mezza maratona maratona piastra carbonio",
    "alphafly": "scarpe running gara maratona piastra carbonio record",
    "adizero": "scarpe corsa running gara velocita maratona",
    "novablast": "scarpe running asfalto massimo rimbalzo ammortizzazione",
    "kayano": "scarpe running stabili supporto pronazione ammortizzazione",
    "nimbus": "scarpe running massimo comfort ammortizzazione neutra",
    "ghost": "scarpe running asfalto neutra ammortizzata allenamento",
    "speedgoat": "scarpe trail running montagna sterrato aderenza vibram",
    "cascadia": "scarpe trail running fango sentieri montagna",
}


def build_embedding_text(product: Dict[str, Any]) -> str:
    """Build high-semantic-density textual representation for vector embedding."""
    brand = (product.get("brand") or "").strip()
    name = (product.get("canonical_name") or "").strip()
    category = (product.get("category") or "").strip()
    gender = (product.get("gender") or "").strip()

    name_lower = name.lower()
    hints = []
    for term, hint in DOMAIN_HINTS.items():
        if term in name_lower:
            hints.append(hint)

    tokens = []
    if brand:
        tokens.append(brand)
    if name:
        tokens.append(name)
    if category:
        tokens.append(f"categoria: {category}")
    if gender and gender.lower() != "unisex":
        tokens.append(f"genere: {gender}")
    if hints:
        tokens.append("caratteristiche: " + " ".join(hints))

    return " ".join(tokens)


class EmbeddingGenerator:
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv("OPENROUTER_API_KEY")
        if not self.api_key:
            raise ValueError("OPENROUTER_API_KEY environment variable is required.")
        self.ctx = ssl.create_default_context(cafile=certifi.where())
        self.sb = SupabaseClient()

    def get_embeddings_batch(self, texts: List[str], retries: int = 3) -> List[List[float]]:
        """Call OpenRouter text-embedding-3-small for a batch of strings."""
        url = "https://openrouter.ai/api/v1/embeddings"
        payload = json.dumps({
            "model": "text-embedding-3-small",
            "input": texts
        }).encode("utf-8")

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        for attempt in range(retries):
            try:
                req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
                with urllib.request.urlopen(req, context=self.ctx, timeout=25) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    # OpenRouter returns items sorted by index
                    items = sorted(data.get("data", []), key=lambda x: x.get("index", 0))
                    return [item["embedding"] for item in items]
            except Exception as e:
                logger.warning(f"Batch embedding request failed (attempt {attempt + 1}/{retries}): {e}")
                if attempt < retries - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise

        return []

    def save_batch_embeddings(self, items: List[Dict[str, Any]], retries: int = 3) -> bool:
        """Call Supabase RPC update_product_embeddings in a single database transaction with retries."""
        payload = {
            "items": [
                {"id": item["id"], "embedding": str(item["embedding"])}
                for item in items
            ]
        }
        for attempt in range(retries):
            res = self.sb._request("rpc/update_product_embeddings", method="POST", data=payload)
            if res.get("status") in (200, 204):
                return True
            logger.warning(f"save_batch_embeddings failed (attempt {attempt + 1}/{retries}): {res.get('error')}")
            time.sleep(1.5 * (attempt + 1))
        return False

    def run(self, batch_size: int = 50, limit: Optional[int] = None, active_only: bool = True):
        logger.info(f"Starting vector embedding backfill (batch_size={batch_size}, active_only={active_only})...")

        total_processed = 0
        start_time = time.time()

        while True:
            # Fetch products needing embeddings
            endpoint = (
                f"products?select=id,canonical_name,brand,category,gender"
                f"{',store_offers!inner(id)' if active_only else ''}"
                f"&embedding=is.null&limit={batch_size}"
            )
            resp = self.sb._request(endpoint, method="GET")
            batch = resp.get("data") or []

            if not batch:
                logger.info("No more products requiring embeddings.")
                break

            texts = [build_embedding_text(p) for p in batch]
            logger.info(f"Generating embeddings for batch of {len(texts)} products...")

            try:
                embeddings = self.get_embeddings_batch(texts)
                if len(embeddings) != len(batch):
                    logger.error(f"Mismatch: got {len(embeddings)} embeddings for {len(batch)} items. Skipping batch.")
                    break

                save_items = [
                    {"id": batch[i]["id"], "embedding": embeddings[i]}
                    for i in range(len(batch))
                ]
                ok = self.save_batch_embeddings(save_items)
                if not ok:
                    logger.error("Failed to save embeddings batch to Supabase. Aborting.")
                    break

                total_processed += len(batch)
                elapsed = time.time() - start_time
                rate = total_processed / elapsed if elapsed > 0 else 0
                logger.info(f"Saved {total_processed} products so far ({rate:.1f} prods/sec).")

                if limit and total_processed >= limit:
                    logger.info(f"Reached specified limit of {limit} products.")
                    break

                # Polite delay to prevent rate limits
                time.sleep(0.3)

            except Exception as e:
                logger.error(f"Error processing batch: {e}")
                break

        logger.info(f"Finished embedding backfill: {total_processed} products embedded in {time.time() - start_time:.2f}s.")


def main():
    parser = argparse.ArgumentParser(description="FitMatch Semantic Vector Backfill")
    parser.add_argument("--batch-size", type=int, default=25, help="Products per embedding batch (default 25)")
    parser.add_argument("--limit", type=int, default=None, help="Max products to embed in this run")
    parser.add_argument("--all", action="store_true", help="Embed all products including those without active offers")
    args = parser.parse_args()

    generator = EmbeddingGenerator()
    generator.run(batch_size=args.batch_size, limit=args.limit, active_only=not args.all)


if __name__ == "__main__":
    main()
