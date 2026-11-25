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
import urllib.parse
import urllib.request
from typing import List, Dict, Any, Optional, Callable
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
    "vantage": "orologio smartwatch gps cardio multisport polar corsa",
    "pace": "orologio smartwatch gps corsa leggero coros maratona",
    "h10": "fascia cardio sensore frequenza cardiaca bluetooth ant+ corsa",
    "hrm": "fascia cardio sensore frequenza cardiaca garmin corsa ciclismo",
    "edge": "ciclocomputer ciclocomputer gps bici ciclismo navigatore",
    "pegasus": "scarpe corsa running asfalto ammortizzate allenamento quotidiano daily trainer",
    "vomero": "scarpe corsa running massima ammortizzazione comfort lunghe distanze",
    "zoom fly": "scarpe running allenamento veloce tempo run piastra carbonio maratona",
    "vaporfly": "scarpe running gara mezza maratona maratona piastra carbonio",
    "alphafly": "scarpe running gara maratona piastra carbonio record",
    "adizero": "scarpe corsa running gara velocita maratona leggere",
    "boston": "scarpe running tempo run allenamento veloce maratona",
    "evo sl": "scarpe running leggere reattive allenamento veloce asfalto",
    "ultraboost": "scarpe running comfort ammortizzazione asfalto uso quotidiano",
    "novablast": "scarpe running asfalto massimo rimbalzo ammortizzazione reattive",
    "superblast": "scarpe running super trainer lunghe distanze maratona ammortizzazione reattiva",
    "kayano": "scarpe running stabili supporto pronazione ammortizzazione",
    "nimbus": "scarpe running massimo comfort ammortizzazione neutra lunghi",
    "cumulus": "scarpe running asfalto neutre ammortizzate allenamento quotidiano",
    "trabuco": "scarpe trail running montagna grip asics sterrato",
    "clifton": "scarpe running leggere ammortizzazione comfort asfalto daily trainer",
    "bondi": "scarpe running massima ammortizzazione recupero lunghi comfort",
    "mach": "scarpe running tempo run leggere reattive asfalto",
    "ghost": "scarpe running asfalto neutra ammortizzata allenamento quotidiano",
    "glycerin": "scarpe running massima ammortizzazione morbida comfort lunghi",
    "adrenaline": "scarpe running stabili supporto antipronazione guida",
    "triumph": "scarpe running massima ammortizzazione comfort lunghe distanze",
    "ride": "scarpe running neutre ammortizzate allenamento quotidiano",
    "endorphin": "scarpe running velocita gara reattive maratona tempo run",
    "cloudmonster": "scarpe running massima ammortizzazione ritorno energia asfalto",
    "cloudsurfer": "scarpe running morbide transizione fluida allenamento asfalto",
    "1080": "scarpe running massima ammortizzazione fresh foam comfort lunghi",
    "rebel": "scarpe running leggere reattive fuelcell tempo run allenamento veloce",
    "deviate nitro": "scarpe running piastra carbonio allenamento veloce maratona",
    "velocity nitro": "scarpe running neutre daily trainer ammortizzate grip pumagrip",
    "speedgoat": "scarpe trail running montagna sterrato aderenza vibram",
    "speedcross": "scarpe trail running fango terreni morbidi grip tacchetti",
    "cascadia": "scarpe trail running fango sentieri montagna protezione",
    "terrex": "trail running outdoor trekking montagna impermeabile",
    "acg": "outdoor trail running trekking abbigliamento tecnico all conditions gear",
    "bonatti": "giacca impermeabile trail running antipioggia traspirante leggera",
    "active skin": "gilet zaino idratazione trail running soft flask corsa montagna",
    "adv skin": "gilet zaino idratazione trail running ultra marathon soft flask",
    "sutro": "occhiali ciclismo corsa sport sole lente prizm",
    "radar ev": "occhiali sportivi ciclismo running lente ventilata",
    "vertex": "racchetta padel potenza diamante attacco bullpadel",
    "hack": "racchetta padel potenza diamante competizione bullpadel",
    "at10": "racchetta padel controllo potenza bilanciata nox tapia",
    "gel resolution": "scarpe tennis stabilita campo terra battuta cemento",
    "court ff": "scarpe tennis velocita stabilita cemento terra battuta",
    "mercurial": "scarpini scarpe calcio velocita fg ag calcetto",
    "predator": "scarpini scarpe calcio controllo fg ag erba sintetica",
    "tiempo": "scarpini scarpe calcio pelle comfort fg ag",
    "phantom": "scarpini scarpe calcio precisione tiro fg ag",
    "copa": "scarpini scarpe calcio pelle tocco fg ag",
    "future": "scarpini scarpe calcio agilita fg ag",
    "top flex": "scarpe calcetto indoor futsal sala",
    "top sala": "scarpe calcetto indoor futsal",
    "magnetico": "scarpini scarpe calcio fg ag",
    "cobra ultra": "occhialini nuoto gara piscina antifog",
    "biofuse": "occhialini nuoto piscina comfort principianti",
    "fastskin": "nuoto piscina costume occhialini gara",
    "occhialini": "nuoto piscina allenamento principianti acqua",
    "gtx": "impermeabile gore-tex pioggia acqua protezione meteo inverno",
    "gore-tex": "impermeabile gore-tex pioggia acqua protezione meteo inverno",
    "therma-fit": "termico caldo inverno isolamento freddo abbigliamento tecnico",
    "dri-fit": "traspirante leggero asciugatura rapida sudore corsa allenamento",
    "manica lunga": "maglia manica lunga long sleeve strato tecnico corsa mezza stagione",
    "long sleeve": "maglia manica lunga long sleeve strato tecnico corsa mezza stagione",
    "half zip": "maglia mezza zip strato intermedio ventilazione corsa inverno",
    "windbreaker": "giacca antivento leggera traspirante corsa ciclismo",
    "antivento": "giacca antivento leggera traspirante corsa ciclismo",
    "2in1": "pantaloncini shorts 2 in 1 cosciale interno corsa running",
}

CATEGORY_HINTS = {
    "football_boots": "scarpini scarpe da calcio calcetto erba naturale sintetica ag fg tf",
    "swim": "nuoto piscina occhialini costume cuffia allenamento acquatico",
    "running_shoes": "scarpe da corsa running asfalto allenamento ammortizzazione",
    "shoes": "scarpe sportive corsa running allenamento calzature",
    "trail_running": "scarpe trail running montagna sentieri sterrato grip",
    "padel": "padel racchetta pala scarpe padel",
    "racket": "racchetta padel tennis pala campo",
    "tennis": "tennis racchetta scarpe tennis campo terra battuta cemento",
    "cycling": "ciclismo bici strada mtb allenamento",
    "gps_watch": "orologio smartwatch gps sport cardio corsa",
    "sensor": "fascia cardio sensore frequenza cardiaca cadenza potenza sport",
    "jacket": "giacca antivento impermeabile smanicato gilet outdoor corsa",
    "top": "maglia t-shirt canotta felpa pile manica lunga corsa allenamento",
    "pants": "pantaloni pantaloncini shorts leggings tights corsa palestra",
    "hydration": "zaino gilet trail borraccia soft flask idratazione",
    "eyewear": "occhiali sportivi sole ciclismo running lenti",
    "winter_sports": "sci snowboard scarponi montagna neve inverno",
}


def build_embedding_text(product: Dict[str, Any], offer_titles: Optional[List[str]] = None) -> str:
    """Build high-semantic-density textual representation for vector embedding."""
    brand = (product.get("brand") or "").strip()
    name = (product.get("canonical_name") or "").strip()
    category = (product.get("category") or "").strip()
    gender = (product.get("gender") or "").strip()

    raw_titles: List[str] = []
    if offer_titles:
        raw_titles.extend(offer_titles)
    elif isinstance(product.get("offer_titles"), list):
        raw_titles.extend(str(t) for t in product["offer_titles"] if t)
    elif isinstance(product.get("store_offers"), list):
        raw_titles.extend(str(o.get("raw_title") or "") for o in product["store_offers"] if isinstance(o, dict))

    # Deduplicate distinct store titles to capture colorways, fabrics & use-case descriptors
    distinct_titles: List[str] = []
    seen_norm = {name.lower()}
    for rt in raw_titles:
        clean_rt = " ".join(rt.strip().split())
        if not clean_rt or len(clean_rt) < 4:
            continue
        key = clean_rt.lower()
        if key in seen_norm:
            continue
        seen_norm.add(key)
        distinct_titles.append(clean_rt[:90])
        if len(distinct_titles) >= 3:
            break

    probe_lower = f"{name} {' '.join(distinct_titles)}".lower()
    hints = []
    seen_hints = set()
    for term, hint in DOMAIN_HINTS.items():
        if term in probe_lower and hint not in seen_hints:
            hints.append(hint)
            seen_hints.add(hint)

    tokens = []
    if brand:
        tokens.append(brand)
    if name:
        tokens.append(name)
    if distinct_titles:
        tokens.append("varianti: " + " | ".join(distinct_titles))
    if category:
        tokens.append(f"categoria: {category}")
        if category in CATEGORY_HINTS and CATEGORY_HINTS[category] not in seen_hints:
            hints.append(CATEGORY_HINTS[category])
    if gender and gender.lower() != "unisex":
        tokens.append(f"genere: {gender}")
    if hints:
        tokens.append("caratteristiche: " + " ".join(hints[:6]))

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
            res = self.sb._request("rpc/update_product_embeddings", method="POST", data=payload, timeout=65)
            if res.get("status") in (200, 204):
                return True
            logger.warning(f"save_batch_embeddings failed (attempt {attempt + 1}/{retries}): {res.get('error')}")
            time.sleep(4.0 * (attempt + 1))
        return False

    def get_coverage_summary(self) -> Dict[str, Any]:
        """Fetch active-catalog embedding coverage grouped by category via Supabase RPC."""
        res = self.sb._request("rpc/get_embedding_coverage", method="POST", data={})
        rows = res.get("data") if isinstance(res, dict) else []
        if not isinstance(rows, list):
            rows = []
        total_active = sum(int(r.get("active_count") or 0) for r in rows)
        total_embedded = sum(int(r.get("embedded_count") or 0) for r in rows)
        total_missing = sum(int(r.get("missing_count") or 0) for r in rows)
        pct = round((total_embedded / total_active) * 100, 1) if total_active > 0 else 100.0
        return {
            "total_active": total_active,
            "total_embedded": total_embedded,
            "total_missing": total_missing,
            "coverage_pct": pct,
            "by_category": rows,
        }

    def run(
        self,
        batch_size: int = 25,
        limit: Optional[int] = None,
        active_only: bool = True,
        category: Optional[str] = None,
        stop_event: Any = None,
        progress_callback: Optional[Callable[[int], None]] = None,
    ) -> Dict[str, Any]:
        clean_cat = (category or "").strip()
        if clean_cat.lower() in ("", "all", "tutte"):
            clean_cat = ""
        logger.info(
            f"Starting vector embedding backfill (batch_size={batch_size}, active_only={active_only}, category={clean_cat or 'all'})..."
        )

        total_processed = 0
        start_time = time.time()
        stopped = False
        error_msg = None

        while True:
            if stop_event is not None and stop_event.is_set():
                stopped = True
                logger.info("Embedding backfill stopped by request.")
                break

            effective_batch = batch_size
            if limit is not None:
                remaining = limit - total_processed
                if remaining <= 0:
                    break
                effective_batch = min(batch_size, remaining)

            cat_filter = f"&category=eq.{clean_cat}" if clean_cat else "&category=neq.non_sport"
            endpoint = (
                f"products?select=id,canonical_name,brand,category,gender"
                f"{',store_offers!inner(id)' if active_only else ''}"
                f"{cat_filter}&embedding=is.null&limit={effective_batch}"
            )
            resp = {}
            for fetch_attempt in range(3):
                resp = self.sb._request(
                    "rpc/get_products_missing_embeddings",
                    method="POST",
                    data={"p_limit": effective_batch, "p_category": clean_cat or None},
                    timeout=35,
                )
                if resp.get("status") != 200:
                    resp = self.sb._request(endpoint, method="GET")
                if resp.get("status") != 200 and active_only:
                    fallback_ep = (
                        f"products?select=id,canonical_name,brand,category,gender"
                        f"{cat_filter}&embedding=is.null&limit={effective_batch}"
                    )
                    resp = self.sb._request(fallback_ep, method="GET")
                if resp.get("status") == 200:
                    break
                logger.warning(f"Fetch batch failed (attempt {fetch_attempt + 1}/3): {resp.get('error')}")
                time.sleep(3.0 * (fetch_attempt + 1))
            if resp.get("status") != 200:
                error_msg = str(resp.get("error") or f"HTTP {resp.get('status')}")
                logger.error(f"Failed fetching products batch: {error_msg}")
                break
            batch = resp.get("data") or []

            if not batch:
                logger.info("No more products requiring embeddings.")
                break

            # Enrich embedding text with distinct raw_title descriptors from store_offers (colors, fabrics, usage)
            offer_titles_by_pid: Dict[str, List[str]] = {}
            try:
                pids = [str(p["id"]) for p in batch if p.get("id")]
                if pids:
                    id_list_str = ",".join('"' + pid.replace('\\', '\\\\').replace('"', '\\"') + '"' for pid in pids)
                    q_in = urllib.parse.quote(f"({id_list_str})")
                    off_resp = self.sb._request(
                        f"store_offers?select=product_id,raw_title&product_id=in.{q_in}&limit={max(len(pids) * 4, 80)}",
                        method="GET",
                        timeout=20,
                    )
                    if off_resp.get("status") == 200 and isinstance(off_resp.get("data"), list):
                        for o in off_resp["data"]:
                            pid = str(o.get("product_id") or "")
                            rt = (o.get("raw_title") or "").strip()
                            if pid and rt:
                                offer_titles_by_pid.setdefault(pid, []).append(rt)
            except Exception:
                pass

            texts = [build_embedding_text(p, offer_titles=offer_titles_by_pid.get(str(p.get("id")))) for p in batch]
            logger.info(f"Generating embeddings for batch of {len(texts)} products...")

            try:
                embeddings = self.get_embeddings_batch(texts)
                if len(embeddings) != len(batch):
                    error_msg = f"Mismatch: got {len(embeddings)} embeddings for {len(batch)} items."
                    logger.error(error_msg + " Skipping batch.")
                    break

                save_items = [
                    {"id": batch[i]["id"], "embedding": embeddings[i]}
                    for i in range(len(batch))
                ]
                ok = self.save_batch_embeddings(save_items)
                if not ok:
                    error_msg = "Failed to save embeddings batch to Supabase."
                    logger.error(error_msg + " Aborting.")
                    break

                total_processed += len(batch)
                if progress_callback is not None:
                    try:
                        progress_callback(total_processed)
                    except Exception:
                        pass

                elapsed = time.time() - start_time
                rate = total_processed / elapsed if elapsed > 0 else 0
                logger.info(f"Saved {total_processed} products so far ({rate:.1f} prods/sec).")

                if limit and total_processed >= limit:
                    logger.info(f"Reached specified limit of {limit} products.")
                    break

                # Polite delay to prevent rate limits
                time.sleep(0.3)

            except Exception as e:
                error_msg = str(e)
                logger.error(f"Error processing batch: {e}")
                break

        elapsed_total = round(time.time() - start_time, 2)
        logger.info(f"Finished embedding backfill: {total_processed} products embedded in {elapsed_total:.2f}s.")
        return {
            "processed": total_processed,
            "duration_seconds": elapsed_total,
            "stopped": stopped,
            "error": error_msg,
        }


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
