import logging
import re
import time
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, Query, HTTPException, BackgroundTasks, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor
from fitmatch.ai_comparator import AIModelComparator, ModelComparisonResponse
from fitmatch.smart_search import SmartSearchEngine
from fitmatch.cache_manager import SearchCacheManager
from fitmatch.updater import PriceUpdater
from fitmatch.scheduler import SyncScheduler
from fitmatch.models import SearchResult
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.push_service import APNsPushService
from fitmatch.price_drop_watcher import PriceDropWatcher
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.admin_dashboard import get_admin_overview, render_admin_html
from fitmatch.affiliate import affiliate_manager

logger = logging.getLogger("fitmatch.api")

app = FastAPI(
    title="FitMatch API",
    description="Multi-store Sportswear Scraping & Price Comparison Engine",
    version="0.2.0"
)

# Enable CORS for frontend integration (Next.js, mobile apps, etc.)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

service = ComparisonService()
db = Database()
updater = PriceUpdater.get_instance(db=db)
scheduler = SyncScheduler.get_instance(db=db)
cache_manager = SearchCacheManager.get_instance()
smart_engine = SmartSearchEngine(cache_manager=cache_manager)


advisor = AIShoppingAdvisor(service=service, db=db)
comparator = AIModelComparator(service=service)
push_service = APNsPushService()
price_watcher = PriceDropWatcher(supabase=db.supabase, push_service=push_service)


@app.on_event("startup")
def on_startup():
    try:
        registry = ScraperRegistry()
        synced = registry.sync_stores_to_database(db)
        logger.info(f"[Startup] Automated store sync completed: {synced} stores synced.")
    except Exception as e:
        logger.warning(f"[Startup] Store sync note: {e}")

    # Autonomous background scheduler (Configurable via env, default: price refresh every 2h, catalog discovery every 24h)
    import os
    refresh_h = float(os.getenv("FITMATCH_REFRESH_INTERVAL_HOURS", "2.0"))
    discovery_h = float(os.getenv("FITMATCH_DISCOVERY_INTERVAL_HOURS", "24.0"))
    enable_sched = os.getenv("FITMATCH_ENABLE_SCHEDULER", "true").lower() in ("true", "1", "yes")

    if enable_sched:
        scheduler.start(
            refresh_interval_seconds=int(refresh_h * 3600),
            discovery_interval_seconds=int(discovery_h * 3600)
        )

    # Autonomous background vector embedding backfill (ensures 100% vector coverage for catalog)
    import threading
    def _startup_embedding_worker():
        try:
            from scripts.generate_embeddings import EmbeddingGenerator
            generator = EmbeddingGenerator()
            generator.run(batch_size=50, active_only=True)
        except Exception as emb_e:
            logger.warning(f"[Startup] Background embedding backfill note: {emb_e}")

    threading.Thread(target=_startup_embedding_worker, daemon=True, name="Startup-Embedding-Worker").start()


@app.on_event("shutdown")
def on_shutdown():
    scheduler.stop()


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "FitMatch Price Engine"}


@app.get("/admin", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
def get_admin_dashboard_ui():
    """Serve the FitMatch interactive Control Center & Admin Dashboard SPA."""
    return HTMLResponse(content=render_admin_html())


@app.get("/api/admin/overview")
def get_admin_overview_api():
    """Retrieve full aggregated telemetry for the admin control center."""
    return get_admin_overview(db=db, scheduler=scheduler)


@app.post("/api/admin/embeddings/sync")
def trigger_embedding_sync(background_tasks: BackgroundTasks):
    """Trigger autonomous background vector embedding generation for any unindexed products."""
    def _run():
        scheduler.run_embedding_task(batch_size=50, limit=None, standalone=True, trigger_source="manual_admin_api")
    background_tasks.add_task(_run)
    return {"status": "accepted", "message": "Vector embedding sync running in background"}


@app.get("/api/stores")
def get_stores():
    return {
        "active_stores": [
            {
                "id": s.store_id,
                "name": s.store_name,
                "base_url": s.base_url
            }
            for s in service.registry.scrapers
        ]
    }


@app.get("/api/stores/showcase")
def get_store_showcases(limit: int = Query(6, ge=1, le=20)):
    """Retrieve Shopify Shop-style featured merchant showcase cards with top products."""
    return {
        "showcases": db.get_store_showcases(limit_per_store=limit)
    }


@app.get("/api/stores/{store_id}")
def get_store_details(
    store_id: str,
    q: str = Query("", description="Keywords to search within this store"),
    sort: str = Query("discount", pattern="^(discount|price_asc|price_desc|name)$"),
    limit: int = Query(100, ge=1, le=200)
):
    """Retrieve full store profile, trust badges, stats, and catalog of products for a dedicated store screen."""
    details = db.get_store_details(store_id=store_id, query=q, sort=sort, limit=limit)
    if not details:
        raise HTTPException(status_code=404, detail="Store not found")
    return details


@app.get("/api/stats")
def get_catalog_stats():
    """Retrieve indexed database overview statistics and price gap metrics."""
    return db.get_stats()


@app.get("/api/catalog")
def search_local_catalog(
    q: str = Query("", description="Keywords to filter indexed products (e.g. 'nike', 'asics', 'garmin', 'oakley')"),
    category: Optional[str] = Query(None, description="Category filter (e.g. 'gps_watch', 'eyewear', 'hydration', 'fitness', 'nutrition', 'running_shoes')"),
    limit: int = Query(25, ge=1, le=100)
):
    """Sub-millisecond query directly on the pre-indexed database catalog."""
    return {
        "query": q,
        "category": category,
        "results": db.search_indexed(query=q, category=category, limit=limit)
    }


@app.get("/api/products/price-history")
def get_product_price_history(
    canonical_name: Optional[str] = Query(None, description="Canonical product name"),
    name: Optional[str] = Query(None, description="Alias for canonical_name"),
    product_id: Optional[str] = Query(None, description="Product cluster ID"),
    days: int = Query(90, ge=7, le=365, description="Historical lookback window in days")
):
    """Retrieve historical price data points, min/max metrics, and all-time low status for a product."""
    target_name = canonical_name or name
    if not target_name and not product_id:
        raise HTTPException(status_code=400, detail="Either canonical_name or product_id must be provided")

    return db.get_price_history(product_id=product_id, canonical_name=target_name, days=days)


@app.get("/api/ai/advise")
def ai_advise(
    prompt: str = Query(..., min_length=4, description="Natural language shopper needs (e.g. 'peso 85kg corro su asfalto sotto i 140 euro')")
):
    """AI Shopper: translates natural language runner profiles into optimal models and live bargains."""
    return advisor.advise(prompt)


@app.get("/api/ai/compare", response_model=ModelComparisonResponse)
def compare_models(
    model_a: str = Query(..., min_length=2, description="First model to compare (e.g. 'Pegasus 41', 'Forerunner 165')"),
    model_b: str = Query(..., min_length=2, description="Second model to compare (e.g. 'Nimbus 26', 'Forerunner 265')")
):
    """AI Side-by-side technical, biomechanical, and live pricing comparison between two sports gear models."""
    return comparator.compare_models(model_a, model_b)


@app.get("/api/search/smart")
def search_smart(
    q: str = Query(..., min_length=2, description="Natural language or keywords query (e.g. 'scarpe running ammortizzate sotto 140 euro')"),
    mode: Optional[str] = Query(None, description="Force search mode: 'deep_dive' or 'classic'"),
    max_price: Optional[float] = Query(None, description="Explicit max price override from active chip"),
    size: Optional[str] = Query(None, description="Explicit size filter"),
    category: Optional[str] = Query(None, description="Category filter override"),
    store: Optional[str] = Query(None, description="Store filter (e.g. 'cisalfa', 'top4running')"),
    context_query: Optional[str] = Query(None, description="Previous search query to maintain conversational context"),
    limit: int = Query(35, ge=1, le=100)
):
    """Shopify Shop-style intelligent search: interprets user intent, classifies query mode (AI deep dive vs classic),
    clusters results into curated thematic carousels, provides spotlight recommendation and follow-up prompts.
    """
    eff_context = context_query.strip() if isinstance(context_query, str) and context_query.strip() else None
    effective_q = f"{eff_context} >> {q.strip()}" if eff_context else q

    # 1. Tier-2 Response Cache Check (Fast-path < 5ms)
    cache_key = cache_manager.make_response_key(
        query=effective_q,
        mode=mode,
        max_price=max_price,
        size=size,
        category=category,
        store=store,
        limit=limit
    )
    cached_resp = cache_manager.get_search_response(cache_key)
    if cached_resp is not None:
        return cached_resp

    intent = smart_engine.parse_query(q, force_mode=mode, context_query=eff_context)

    from fitmatch.smart_search import QueryProductGuardrail
    detected_product_type = QueryProductGuardrail.detect_product_type(q, eff_context)

    # Use explicit query overrides if user modified/toggled active chips
    eff_max_price = max_price if max_price is not None else intent.max_price
    eff_size = size if size is not None else intent.size
    eff_category = category if category is not None else intent.category

    products = db.search_smart(
        target_keywords=intent.target_keywords,
        category=eff_category,
        brand=intent.brand,
        gender=intent.gender,
        max_price=eff_max_price,
        min_price=intent.min_price,
        size=eff_size,
        store_id=store,
        limit=limit,
        raw_query=q
    )

    # Extra safety filter: ensure every returned product satisfies product-type guardrails
    if products and detected_product_type:
        products = [
            p for p in products
            if QueryProductGuardrail.is_product_compatible(p, detected_product_type, raw_query=q)
        ]

    # Live Multi-Store Federated Search Fallback:
    # If local indexed DB returns 0 products for this smart query, immediately trigger live scrapers across retailers!
    if not products:
        brand_names = {"nike", "adidas", "puma", "asics", "brooks", "saucony", "hoka", "mizuno", "on", "new balance", "salomon", "garmin"}
        candidate_kws = [k for k in (intent.target_keywords or []) if k.strip().lower() not in brand_names]
        queries_to_crawl = candidate_kws[:2] if len(candidate_kws) >= 2 else ([candidate_kws[0]] if candidate_kws else [q])
        logger.info(f"[search_smart] 0 local products for '{q}'. Triggering fan-out live multi-store crawler for {queries_to_crawl}")

        from concurrent.futures import ThreadPoolExecutor
        def _crawl_kw(kw: str):
            eff_kw = f"{intent.brand} {kw}" if intent.brand and intent.brand.lower() not in kw.lower() else kw
            try:
                return service.search_and_compare(query=eff_kw, size=eff_size, limit_per_store=6, use_cache=True)
            except Exception as e:
                logger.error(f"[search_smart] Live crawl federation error for '{eff_kw}': {e}")
                return None

        with ThreadPoolExecutor(max_workers=min(2, len(queries_to_crawl))) as executor:
            crawl_results = list(executor.map(_crawl_kw, queries_to_crawl))

        BIKE_HARDWARE = {"cuffie", "cuffia", "serie sterzo", "headset", "attacco manubrio", "supporto manubrio", "movimento centrale"}
        is_bike_query = any(w in q.lower() for w in ["bici", "ciclismo", "sterzo", "cuffie", "headset", "bike"])

        merged_prods = {}
        for live_res in crawl_results:
            if not live_res or not live_res.matched_products:
                continue
            for mp in live_res.matched_products:
                mp_name = (mp.canonical_name or "").lower()
                mp_brand = (mp.brand or "").lower()

                # Brand strictness
                if intent.brand:
                    b_low = intent.brand.lower()
                    if b_low not in mp_brand and b_low not in mp_name:
                        continue

                # Bike hardware exclusion
                if not is_bike_query and any(bh in mp_name for bh in BIKE_HARDWARE):
                    continue

                if mp.canonical_name not in merged_prods:
                    merged_prods[mp.canonical_name] = mp
                    # Index into database so future searches are cached
                    try:
                        for off in mp.offers:
                            cluster_key = ProductNormalizer.extract_cluster_key(off)
                            brand = ProductNormalizer.extract_brand(off.title) or mp.brand or intent.brand
                            canon_display = ProductNormalizer.build_canonical_display_name(off.title, brand=brand)
                            cat = ProductNormalizer.detect_article_type(off.title)
                            gend = ProductNormalizer.extract_gender(off.title, off.url)
                            db.upsert_product_and_offer(
                                cluster_key=cluster_key,
                                canonical_name=canon_display or mp.canonical_name,
                                brand=brand,
                                category=cat,
                                gender=gend,
                                offer=off
                            )
                    except Exception as save_err:
                        logger.warning(f"[search_smart] Failed to cache live offers: {save_err}")

        if merged_prods:
            candidate_live = [
                {
                    "id": mp.canonical_name,
                    "canonical_name": mp.canonical_name,
                    "brand": mp.brand or intent.brand,
                    "category": eff_category or "running_shoes",
                    "gender": intent.gender or "Unisex",
                    "image_url": mp.image_url,
                    "gallery_images": mp.gallery_images,
                    "offer_count": len(mp.offers),
                    "best_price": mp.best_price,
                    "max_price": mp.highest_price,
                    "offers": [o.model_dump() for o in mp.offers],
                    "highest_price": mp.highest_price,
                    "cross_store_savings": mp.cross_store_savings
                }
                for mp in merged_prods.values()
            ]
            products = [
                p for p in candidate_live
                if QueryProductGuardrail.is_product_compatible(p, detected_product_type, raw_query=q)
            ]

    # Helper to check if a section title/subtitle is locked to a specific brand
    SECTION_BRAND_NAMES = [
        "adidas", "nike", "puma", "asics", "hoka", "saucony", "brooks",
        "salomon", "garmin", "mizuno", "odlo", "new balance", "on", "reebok", "oakley"
    ]

    def _product_matches_section(p: dict, sec_kws: list, sec_brand_lock: Optional[str]) -> bool:
        name_lower = (p.get("canonical_name") or "").lower()
        brand_lower = (p.get("brand") or "").lower()
        off_titles = " ".join((o.get("title") or "") for o in (p.get("offers") or [])[:2]).lower()
        combined = f"{name_lower} {brand_lower} {off_titles}"
        if sec_brand_lock and sec_brand_lock not in brand_lower and sec_brand_lock not in name_lower:
            return False
        if not sec_kws:
            return True
        return any(k in combined for k in sec_kws)

    # Curate Thematic Carousels for AI Deep Dive
    curated_sections_out = []
    used_product_ids = set()

    if intent.curated_sections and products:
        for sec_def in intent.curated_sections:
            sec_prods = []
            sec_kws = [k.lower().strip() for k in (sec_def.keywords or []) if k.strip()]
            sec_title_sub = f"{sec_def.title} {sec_def.subtitle}".lower()
            sec_brands_mentioned = [b for b in SECTION_BRAND_NAMES if re.search(rf"\b{re.escape(b)}\b", sec_title_sub)]
            sec_brand_lock = sec_brands_mentioned[0] if len(sec_brands_mentioned) == 1 else None

            for p in products:
                if p.get("id") in used_product_ids:
                    continue
                if _product_matches_section(p, sec_kws, sec_brand_lock):
                    sec_prods.append(p)
                    used_product_ids.add(p.get("id"))
                if len(sec_prods) >= 8:
                    break

            # Fallback without brand lock if 0 products matched and user didn't filter by that brand
            if not sec_prods and sec_kws:
                for p in products:
                    if p.get("id") in used_product_ids:
                        continue
                    if _product_matches_section(p, sec_kws, None):
                        sec_prods.append(p)
                        used_product_ids.add(p.get("id"))
                    if len(sec_prods) >= 6:
                        break

            if sec_prods:
                sec_title = QueryProductGuardrail.strip_markdown_bold(sec_def.title)
                sec_subtitle = QueryProductGuardrail.strip_markdown_bold(sec_def.subtitle)
                # Ensure section title doesn't claim a single brand if products inside belong to other brands
                if sec_brand_lock:
                    actual_brands = {(sp.get("brand") or "").lower() for sp in sec_prods if sp.get("brand")}
                    if actual_brands and not all(sec_brand_lock in ab for ab in actual_brands):
                        sec_title = "I Modelli Più Rilevanti"
                        sec_subtitle = "Selezionati e confrontati tra i migliori store specializzati."
                curated_sections_out.append({
                    "id": sec_def.id,
                    "title": sec_title,
                    "subtitle": sec_subtitle,
                    "products": sec_prods
                })

    # If remaining relevant products were not placed in any section, either enrich the sole section or add a second section
    unused_products = [p for p in products if p.get("id") not in used_product_ids]
    if not curated_sections_out and products:
        curated_sections_out.append({
            "id": "sec_all",
            "title": "I Modelli Selezionati",
            "subtitle": "I migliori prodotti trovati in base alla tua ricerca.",
            "products": products[:10]
        })
    elif len(curated_sections_out) == 1 and unused_products:
        if len(curated_sections_out[0]["products"]) < 6:
            need = 8 - len(curated_sections_out[0]["products"])
            curated_sections_out[0]["products"].extend(unused_products[:need])
            unused_products = unused_products[need:]
        if len(unused_products) >= 2:
            curated_sections_out.append({
                "id": "sec_more_options",
                "title": "Altre Opzioni Consigliate",
                "subtitle": "Ulteriori modelli tecnici compatibili con la tua ricerca.",
                "products": unused_products[:8]
            })

    # Populate Comparative Spec Cards ("Confronto rapido" section matching Shopify Shop)
    comparative_cards_out = []
    used_comp_ids = set()
    used_comp_models = set()
    GENERIC_COMP_WORDS = {
        "long", "sleeve", "manica", "lunga", "maniche", "lunghe", "short", "corta",
        "running", "corsa", "scarpe", "scarpa", "uomo", "donna", "maglia", "shirt", "hyrox", "pro", "elite"
    }

    def _model_dedup_signature(prod: dict) -> str:
        cname = (prod.get("canonical_name") or "").lower()
        # Strip gender & colorway tags so two variants of the same shoe/garment share a signature
        cname = re.sub(r"\b(uomo|donna|unisex|wide|gtx|gore-tex)\b", "", cname)
        tokens = [t for t in re.findall(r"\b[a-z0-9]+\b", cname) if len(t) > 1]
        return " ".join(tokens[:4])

    if intent.spec_comparisons and products:
        for spec in intent.spec_comparisons:
            target_kw = (spec.target_keyword or spec.model_name).lower().strip()
            spec_model_low = (spec.model_name or "").lower()
            spec_brand = next((b for b in SECTION_BRAND_NAMES if re.search(rf"\b{re.escape(b)}\b", spec_model_low)), None)

            matched_spec_prod = None
            for p in products:
                pid = p.get("id") or p.get("canonical_name")
                msig = _model_dedup_signature(p)
                if pid in used_comp_ids or (msig and msig in used_comp_models):
                    continue
                pname = (p.get("canonical_name") or "").lower()
                pbrand = (p.get("brand") or "").lower()
                # If spec card names a specific brand, product must match that brand
                if spec_brand and spec_brand not in pbrand and spec_brand not in pname:
                    continue
                if target_kw and target_kw in pname:
                    matched_spec_prod = p
                    break
                specific_words = [w for w in target_kw.split() if len(w) > 3 and w not in GENERIC_COMP_WORDS]
                if specific_words and any(w in pname for w in specific_words):
                    matched_spec_prod = p
                    break

            if matched_spec_prod:
                pid = matched_spec_prod.get("id") or matched_spec_prod.get("canonical_name")
                msig = _model_dedup_signature(matched_spec_prod)
                used_comp_ids.add(pid)
                if msig:
                    used_comp_models.add(msig)
                # Ensure displayed model_name reflects the actual matched product
                display_model_name = matched_spec_prod.get("canonical_name") or spec.model_name
                comparative_cards_out.append({
                    "product": matched_spec_prod,
                    "model_name": QueryProductGuardrail.strip_markdown_bold(display_model_name),
                    "ideal_for": QueryProductGuardrail.strip_markdown_bold(spec.ideal_for),
                    "strengths": QueryProductGuardrail.strip_markdown_bold(spec.strengths),
                    "section_title": "Confronto rapido"
                })

    # Top up comparative_cards_out to at least 2-3 distinct products if we have more products available
    if len(comparative_cards_out) < 2 and len(products) >= 2:
        for p in products:
            pid = p.get("id") or p.get("canonical_name")
            msig = _model_dedup_signature(p)
            if pid in used_comp_ids or (msig and msig in used_comp_models):
                continue
            used_comp_ids.add(pid)
            if msig:
                used_comp_models.add(msig)
            p_name = p.get("canonical_name") or "Modello Selezionato"
            p_brand = p.get("brand") or ""
            p_offers = p.get("offers") or []
            best_off = p_offers[0] if p_offers else {}
            disc = best_off.get("discount_pct")

            if len(comparative_cards_out) == 0:
                ideal = "Scelta principale per rapporto qualità/prezzo"
            elif "warm" in p_name.lower() or "termic" in p_name.lower() or "odlo" in p_brand.lower():
                ideal = "Uscite con clima freddo e isolamento termico"
            elif "hyrox" in p_name.lower() or "deviate" in p_name.lower() or "velocity" in p_name.lower():
                ideal = "Frazioni di corsa e trazione su slitta Hyrox"
            elif "dropset" in p_name.lower() or "metcon" in p_name.lower():
                ideal = "Stabilità sotto carico, affondi e wall ball"
            else:
                ideal = f"Alternativa tecnica {p_brand}".strip()

            if len(p_offers) > 1 and p.get("cross_store_savings", 0) > 0:
                strength = f"Confrontato in {len(p_offers)} store (risparmi € {p['cross_store_savings']:.0f})"
            elif disc and float(disc) >= 10:
                strength = f"In offerta a € {p.get('best_price', 0):.2f} (-{int(round(float(disc)))}%)"
            elif best_off.get("is_free_shipping"):
                strength = f"€ {p.get('best_price', 0):.2f} con spedizione gratuita"
            else:
                strength = f"Miglior prezzo verificato a € {p.get('best_price', 0):.2f}"

            comparative_cards_out.append({
                "product": p,
                "model_name": p_name,
                "ideal_for": ideal,
                "strengths": strength,
                "section_title": "Confronto rapido"
            })
            if len(comparative_cards_out) >= 3:
                break

    # Populate Spotlight Deal / Best Pick Card (Shopify Shop Best Pick)
    def _build_truthful_spotlight(prod: dict, raw_badge: Optional[str], raw_highlights: Optional[List[str]]) -> dict:
        offers = prod.get("offers") or []
        best_off = offers[0] if offers else {}
        num_stores = len({o.get("store_id") for o in offers if o.get("store_id")}) or len(offers) or 1
        best_price = float(prod.get("best_price") or best_off.get("price") or 0.0)
        orig_price = float(best_off.get("original_price") or 0.0)
        disc_pct = float(best_off.get("discount_pct") or 0.0)
        if not disc_pct and orig_price > best_price > 0:
            disc_pct = ((orig_price - best_price) / orig_price) * 100.0
        savings_cross = float(prod.get("cross_store_savings") or 0.0)
        avail_sizes = prod.get("available_sizes") or best_off.get("available_sizes") or []

        # Clean technical highlights from intent (strip ** and filter out fake store-count claims)
        clean_tech_hl = []
        for h in (raw_highlights or []):
            ch = QueryProductGuardrail.strip_markdown_bold(h)
            if not ch:
                continue
            if any(phrase in ch.lower() for phrase in ["1 negozi", "12 store", "più negozi", "più store", "risparmio garantito rispetto"]):
                continue
            clean_tech_hl.append(ch)

        final_highlights = clean_tech_hl[:2]

        # Add 100% truthful real-time pricing/store/availability bullets
        if num_stores > 1 and savings_cross >= 5:
            final_highlights.append(f"Confrontato tra {num_stores} negozi con risparmio immediato di € {savings_cross:.0f}")
        elif num_stores > 1:
            final_highlights.append(f"Prezzo più basso confrontato tra {num_stores} negozi ufficiali")
        elif disc_pct >= 5 and orig_price > best_price:
            final_highlights.append(f"In sconto del {int(round(disc_pct))}% rispetto al listino (€ {orig_price:.2f})")
        else:
            store_label = best_off.get("store_name") or "store ufficiale"
            final_highlights.append(f"Miglior offerta verificata su {store_label} a € {best_price:.2f}")

        if len(final_highlights) < 3:
            if avail_sizes:
                final_highlights.append(f"Taglie disponibili: {', '.join(str(s) for s in avail_sizes[:6])}")
            elif best_off.get("is_free_shipping"):
                final_highlights.append("Spedizione gratuita inclusa sul miglior prezzo")
            else:
                final_highlights.append("Disponibilità e spedizione rapida verificate")

        badge = QueryProductGuardrail.strip_markdown_bold(raw_badge or "Miglior Scelta")
        # Don't show fake discount % badge if the product isn't discounted
        if "sconto" in badge.lower() and disc_pct < 5:
            badge = "Miglior Scelta"
        elif disc_pct >= 15 and badge in ("Miglior Scelta", "Prezzo Top"):
            badge = f"-{int(round(disc_pct))}% Miglior Prezzo"

        return {
            "product": prod,
            "badge_text": badge,
            "highlights": final_highlights[:3]
        }

    spotlight_out = None
    if products and intent.spotlight and intent.spotlight.target_keyword:
        target_kw = intent.spotlight.target_keyword.lower().strip()
        matched_spotlight_prod = next(
            (
                p for p in products
                if target_kw in (p.get("canonical_name") or "").lower()
                or target_kw in (p.get("brand") or "").lower()
            ),
            None
        )
        if matched_spotlight_prod:
            spotlight_out = _build_truthful_spotlight(
                matched_spotlight_prod,
                intent.spotlight.badge_text,
                intent.spotlight.highlights
            )

    # If no explicit spotlight or didn't match, pick the top relevance product
    if not spotlight_out and products:
        best_p = products[0]
        raw_hl = intent.spotlight.highlights if intent.spotlight else None
        raw_badge = intent.spotlight.badge_text if intent.spotlight else "Miglior Scelta"
        spotlight_out = _build_truthful_spotlight(best_p, raw_badge, raw_hl)

    result_data = {
        "search_mode": intent.search_mode,
        "is_deep_dive": intent.is_deep_dive,
        "conversational_header": intent.conversational_header,
        "conversational_summary": intent.conversational_summary,
        "curated_sections": curated_sections_out,
        "comparative_cards": comparative_cards_out,
        "spotlight": spotlight_out,
        "follow_up_suggestions": intent.follow_up_suggestions,
        "chips": [c.model_dump() for c in intent.chips],
        "intent": {
            "raw_query": intent.raw_query,
            "search_mode": intent.search_mode,
            "is_deep_dive": intent.is_deep_dive,
            "target_keywords": intent.target_keywords,
            "brand": intent.brand,
            "category": eff_category,
            "gender": intent.gender,
            "max_price": eff_max_price,
            "min_price": intent.min_price,
            "size": eff_size,
            "features": intent.features,
            "explanation": intent.explanation,
            "source": intent.source
        },
        "total_found": len(products),
        "results": products
    }

    # Store full curated response into L1 memory & L2 disk cache (20-min TTL)
    cache_manager.set_search_response(cache_key, result_data)
    return result_data



@app.get("/api/search", response_model=SearchResult)
def search_live(
    q: str = Query(..., min_length=2, description="Product search query (e.g. 'nike pegasus', 'asics nimbus')"),
    size: Optional[str] = Query(None, description="Filter only offers having this size in stock (e.g. '43', '42.5', 'M')"),
    limit: int = Query(8, ge=1, le=25, description="Max products to fetch per store"),
    cache: bool = Query(True, description="Enable local caching to speed up repeated queries")
):
    """Live multi-store federated search across all 10 retailers with optional size verification."""
    try:
        results = service.search_and_compare(query=q, size=size, limit_per_store=limit, use_cache=cache)
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/search/feedback")
def submit_search_feedback(payload: dict):
    """Save user feedback on search results."""
    try:
        # Save directly to Supabase search_feedback table if client is present
        if hasattr(db, "supabase") and db.supabase and hasattr(db.supabase, "client") and db.supabase.client:
            db.supabase.client.table("search_feedback").insert(payload).execute()
    except Exception as e:
        logger.warning(f"Error persisting search feedback: {e}")
    return {"status": "ok", "message": "Feedback salvato con successo"}


@app.post("/api/crawl")
def trigger_crawl(
    background_tasks: BackgroundTasks,
    limit_per_store: int = Query(100, ge=10, le=2000),
    store: Optional[str] = Query(None, description="Specific store ID to crawl (e.g. 'cisalfa', 'deporvillage') or all")
):
    """Trigger background crawler to update catalog from all or specific stores with session tracking."""
    cache_manager.invalidate_responses()
    session_id = db.create_sync_session(
        session_type="manual_crawl",
        trigger_source="manual_api",
        metadata={"limit_per_store": limit_per_store, "store": store}
    )

    def _do_crawl():
        try:
            start_t = time.time()
            crawler = CategoryCrawler(db=db)
            if store:
                c = crawler.crawl_store(store, max_items=limit_per_store, session_id=session_id)
                dur = round(time.time() - start_t, 2)
                db.update_sync_session(
                    session_id=session_id,
                    status="completed",
                    duration_seconds=dur,
                    total_items_processed=c,
                    total_items_updated=c,
                    store_stats={store: c}
                )
            else:
                res = crawler.run_full_sync(limit_per_store=limit_per_store, session_id=session_id)
                db.update_sync_session(
                    session_id=session_id,
                    status="completed",
                    duration_seconds=res.get("duration_seconds", 0),
                    total_items_processed=res.get("total_crawled", 0),
                    total_items_updated=res.get("total_crawled", 0),
                    store_stats=res.get("crawled_by_store", {})
                )
        except Exception as e:
            logger.error(f"[ManualCrawl] Error in session {session_id}: {e}")
            db.update_sync_session(session_id=session_id, status="failed", error_message=str(e))

    background_tasks.add_task(_do_crawl)
    return {
        "status": "scheduled",
        "session_id": session_id,
        "message": f"Crawl job avviato in background per {store or 'tutti i negozi'}",
        "target_per_store": limit_per_store
    }


# --- Autonomous Scheduler Endpoints ---

@app.get("/api/scheduler/status")
def get_scheduler_status():
    """Retrieve live status, cycles and schedule of the autonomous spider engine."""
    return scheduler.get_status()


@app.get("/api/scheduler/sessions")
def get_scheduler_sessions(
    limit: int = Query(20, ge=1, le=100),
    type: Optional[str] = Query(None, description="Filter by session type: discovery, price_refresh, size_enrichment, manual_crawl"),
    status: Optional[str] = Query(None, description="Filter by status: running, completed, failed")
):
    """Retrieve history of persistent crawler and scheduler sync sessions from the database."""
    sessions = db.get_sync_sessions(limit=limit, session_type=type, status=status)
    return {
        "total": len(sessions),
        "sessions": sessions
    }


@app.get("/api/scheduler/sessions/{session_id}")
def get_scheduler_session_detail(session_id: str):
    """Retrieve full details of a specific sync session, including breakdown by store and crawl logs."""
    session = db.get_sync_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' non trovata.")
    return session


@app.delete("/api/scheduler/sessions/{session_id}")
def delete_scheduler_session(session_id: str):
    """Delete a sync session record and its associated logs from Supabase/SQLite."""
    ok = db.delete_sync_session(session_id)
    if not ok:
        raise HTTPException(status_code=500, detail="Impossibile eliminare la sessione.")
    return {"status": "success", "session_id": session_id, "message": "Sessione eliminata con successo."}


@app.delete("/api/scheduler/sessions")
def clear_scheduler_sessions(
    status: Optional[str] = Query(None, description="Filtra per status da eliminare: running, completed, failed")
):
    """Bulk delete sync sessions by status (e.g. failed to clear all errors)."""
    count = db.delete_sync_sessions(status=status)
    return {
        "status": "success",
        "deleted_count": count,
        "message": f"{count} sessioni con stato '{status or 'tutti'}' eliminate con successo."
    }


@app.post("/api/scheduler/start")
def start_scheduler(
    refresh_interval_hours: float = Query(2.0, ge=0.5, le=24.0),
    discovery_interval_hours: float = Query(24.0, ge=1.0, le=168.0)
):
    """Start or restart the autonomous background scheduler."""
    scheduler.start(
        refresh_interval_seconds=int(refresh_interval_hours * 3600),
        discovery_interval_seconds=int(discovery_interval_hours * 3600)
    )
    return {
        "status": "started",
        "message": f"Scheduler attivo: refresh ogni {refresh_interval_hours}h, discovery ogni {discovery_interval_hours}h."
    }


@app.post("/api/scheduler/stop")
def stop_scheduler():
    """Stop the autonomous background scheduler."""
    scheduler.stop()
    return {"status": "stopped", "message": "Scheduler arrestato."}


@app.post("/api/scheduler/run-discovery")
def trigger_scheduler_discovery(limit_per_store: int = Query(200, ge=10, le=1000)):
    """Trigger an immediate catalog discovery run across all stores in background with session tracking."""
    return scheduler.trigger_discovery_now(limit_per_store=limit_per_store, trigger_source="manual_api")


@app.post("/api/scheduler/run-refresh")
def trigger_scheduler_refresh(limit: int = Query(50, ge=10, le=500)):
    """Trigger an immediate price & stock refresh for indexed products in background with session tracking."""
    return scheduler.trigger_refresh_now(limit=limit, trigger_source="manual_api")


@app.post("/api/scheduler/run-enrichment")
def trigger_scheduler_enrichment(limit_per_store: int = Query(50, ge=5, le=500)):
    """Trigger an immediate size enrichment run across stores in background with session tracking."""
    return scheduler.trigger_enrichment_now(limit_per_store=limit_per_store, trigger_source="manual_api")


@app.post("/api/catalog/recluster")
def trigger_catalog_recluster(background_tasks: BackgroundTasks):
    """Trigger autonomous entity resolution and catalog re-clustering across all stores in background."""
    background_tasks.add_task(scheduler.run_reclustering_task)
    return {
        "status": "started",
        "message": "Re-clustering catalogo e unificazione multinegozio avviata in background."
    }


@app.get("/api/updater/status")
def get_updater_status():
    """Retrieve real-time status of the automated background price updater."""
    return updater.get_status()


@app.post("/api/updater/run")
def trigger_updater(
    background_tasks: BackgroundTasks,
    limit: int = Query(25, ge=5, le=100)
):
    """Trigger an on-demand price refresh across stores for indexed products."""
    if updater.is_running:
        return {"status": "busy", "message": "Aggiornamento prezzi già in corso in background."}
    cache_manager.invalidate_responses()
    background_tasks.add_task(updater.run_update_sync, limit)
    return {
        "status": "scheduled",
        "message": f"Aggiornamento prezzi avviato in background per {limit} prodotti."
    }


# MARK: - Wishlist & Collections Endpoints (Database Connected)

@app.get("/api/wishlist")
def get_wishlist_endpoint(collection: Optional[str] = None):
    """Retrieve all saved wishlist products connected to the SQLite database."""
    items = db.get_wishlist(collection_name=collection)
    return {"items": items, "count": len(items)}


@app.post("/api/wishlist")
def add_to_wishlist_endpoint(payload: dict):
    """Add or update a saved product in the database."""
    saved_item = db.add_to_wishlist(payload)
    return {"status": "ok", "item": saved_item}


@app.patch("/api/wishlist/{canonical_name}/collection")
def update_wishlist_collection_endpoint(canonical_name: str, payload: dict):
    """Move a saved product to a specific collection."""
    col = payload.get("collection_name", "Tutti")
    updated = db.update_wishlist_item_collection(canonical_name, col)
    return {"status": "ok" if updated else "error", "success": updated, "collection_name": col}


@app.delete("/api/wishlist/{identifier}")
def delete_from_wishlist_endpoint(identifier: str):
    """Remove a saved product from the database."""
    deleted = db.remove_from_wishlist(identifier)
    return {"status": "ok" if deleted else "not_found", "deleted": deleted}


@app.get("/api/collections")
def get_collections_endpoint():
    """Retrieve all collections and product counts from the database."""
    cols = db.get_collections()
    return {"collections": cols}


@app.post("/api/collections")
def create_collection_endpoint(payload: dict):
    """Create a new collection category in the database."""
    name = payload.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Il nome della collezione è obbligatorio.")
    created = db.create_collection(name)
    return {"status": "ok", "success": True, "collection": created}


@app.delete("/api/collections/{name}")
def delete_collection_endpoint(name: str):
    """Delete a collection and reassign items to Tutti."""
    deleted = db.delete_collection(name)
    return {"status": "ok" if deleted else "not_found", "success": deleted}


@app.get("/api/followed_stores")
def get_followed_stores_endpoint():
    """Retrieve all followed stores from the database."""
    stores = db.get_followed_stores()
    return {"stores": stores}


@app.post("/api/followed_stores")
def follow_store_endpoint(payload: dict):
    """Follow a partner store in the database."""
    store_id = payload.get("store_id", "").strip()
    store_name = payload.get("store_name", "").strip()
    store_logo = payload.get("store_logo")
    if not store_id or not store_name:
        raise HTTPException(status_code=400, detail="store_id e store_name sono obbligatori.")
    success = db.follow_store(store_id, store_name, store_logo)
    return {"status": "ok", "success": success}


@app.delete("/api/followed_stores/{store_id}")
def unfollow_store_endpoint(store_id: str):
    """Unfollow a partner store."""
    success = db.unfollow_store(store_id)
    return {"status": "ok", "success": success}


@app.get("/api/recent_activity")
def get_recent_activity_endpoint(limit: int = Query(30, ge=1, le=100)):
    """Retrieve user recent activity from the database."""
    activities = db.get_recent_activity(limit=limit)
    return {"activities": activities}


@app.post("/api/recent_activity")
def record_recent_activity_endpoint(payload: dict):
    """Record an item or search to user's recent activity in the database."""
    success = db.record_recent_activity(payload)
    return {"status": "ok", "success": success}


# MARK: - Stores, Hidden Stores & Store Reports

@app.get("/api/stores")
def get_all_stores_endpoint():
    """Retrieve all store metadata directly from the database."""
    stores = db.get_stores()
    return {"stores": stores}


@app.get("/api/stores/{store_id}")
def get_store_endpoint(store_id: str):
    """Retrieve a specific store's metadata."""
    store = db.get_store(store_id)
    if not store:
        raise HTTPException(status_code=404, detail="Negozio non trovato.")
    return {"store": store}


@app.post("/api/stores/report")
def report_store_endpoint(payload: dict):
    """Report a store for verification."""
    store_id = payload.get("store_id", "").strip()
    store_name = payload.get("store_name", "").strip()
    reason = payload.get("reason", "Prezzi non aggiornati o violazione")
    details = payload.get("details")
    if not store_id or not store_name:
        raise HTTPException(status_code=400, detail="store_id e store_name sono obbligatori.")
    success = db.report_store(store_id, store_name, reason, details)
    return {"status": "ok", "success": success}


@app.get("/api/stores/hidden")
def get_hidden_stores_endpoint():
    """Retrieve hidden stores."""
    return {"hidden_stores": db.get_hidden_stores()}


@app.post("/api/stores/hide")
def hide_store_endpoint(payload: dict):
    """Hide a store from suggestions."""
    store_id = payload.get("store_id", "").strip()
    store_name = payload.get("store_name")
    if not store_id:
        raise HTTPException(status_code=400, detail="store_id obbligatorio.")
    success = db.hide_store(store_id, store_name)
    return {"status": "ok", "success": success}


@app.delete("/api/stores/hide/{store_id}")
def unhide_store_endpoint(store_id: str):
    """Unhide a store."""
    success = db.unhide_store(store_id)
    return {"status": "ok", "success": success}


@app.get("/api/stores/{store_id}/reviews")
def get_store_reviews_endpoint(store_id: str, limit: int = Query(50, ge=1, le=100)):
    """Retrieve real user reviews for a specific store."""
    reviews = db.get_store_reviews(store_id, limit=limit)
    return {"reviews": reviews}


@app.post("/api/stores/{store_id}/reviews")
def add_store_review_endpoint(store_id: str, payload: dict):
    """Submit a real user review and rating for a store."""
    author_name = (payload.get("author_name") or "").strip() or "Cliente Verificato"
    rating = int(payload.get("rating", 5))
    review_text = (payload.get("review_text") or "").strip()
    device_id = payload.get("device_id")
    if not (1 <= rating <= 5):
        raise HTTPException(status_code=400, detail="La valutazione deve essere compresa tra 1 e 5.")
    res = db.add_store_review(store_id, author_name, rating, review_text, device_id)
    if not res:
        raise HTTPException(status_code=500, detail="Impossibile salvare la recensione.")
    return {"status": "ok", "review": res}


# MARK: - Smart Cache Management & Analytics

@app.get("/api/cache/stats")
def get_cache_stats():
    """Retrieve real-time metrics on smart search cache efficiency, hit ratios and monetary savings."""
    return cache_manager.get_metrics()


@app.post("/api/cache/clear")
def clear_cache(scope: str = Query("all", description="Scope: 'all' for full flush, 'responses' to only invalidate search product offers")):
    """Clear or invalidate in-memory and persistent disk caches."""
    if scope == "responses":
        purged = cache_manager.invalidate_responses()
        return {"status": "ok", "scope": "responses", "purged": purged, "message": f"Invalidati {purged} risultati di ricerca cached."}
    cache_manager.clear_all()
    return {"status": "ok", "scope": "all", "message": "Tutte le cache (intenti LLM e risultati catalogo) sono state svuotate."}


# MARK: - Device Tokens & Production Push Notifications (Piano B)

@app.post("/api/devices/register")
def register_device(payload: dict):
    """Register or update an iOS device token for APNs push notifications."""
    token = payload.get("device_token")
    device_id = payload.get("device_id")
    if not token or not device_id:
        raise HTTPException(status_code=400, detail="device_token e device_id sono obbligatori.")
    
    success = db.supabase.register_device_token(
        device_token=token,
        device_id=device_id,
        user_id=payload.get("user_id"),
        platform=payload.get("platform", "ios"),
        environment=payload.get("environment", "production"),
        notify_price_drop=payload.get("notify_price_drop", True),
        notify_targeted_promo=payload.get("notify_targeted_promo", True),
        min_discount_pct=float(payload.get("min_discount_pct", 5.0)),
        preferred_size=payload.get("preferred_size"),
        app_version=payload.get("app_version")
    )
    if not success:
        raise HTTPException(status_code=500, detail="Impossibile registrare il device token in Supabase.")
    return {"status": "ok", "message": "Device token registrato con successo per le push notifications."}


@app.get("/api/notifications")
def get_user_notifications(device_id: str = Query(..., description="Device ID")):
    """Retrieve stored in-app notifications feed from Supabase."""
    items = db.supabase.get_user_notifications(device_id=device_id)
    return {"status": "ok", "notifications": items}


@app.post("/api/notifications/read")
def mark_notification_read(payload: dict):
    """Mark one or all notifications as read."""
    notif_id = payload.get("notification_id")
    device_id = payload.get("device_id")
    if notif_id:
        db.supabase.mark_notification_read(notif_id)
    elif device_id:
        db.supabase.mark_all_notifications_read(device_id)
    else:
        raise HTTPException(status_code=400, detail="Fornire notification_id o device_id.")
    return {"status": "ok"}


@app.delete("/api/notifications/{notification_id}")
def delete_notification(notification_id: str):
    """Delete a notification from user history."""
    db.supabase.delete_notification(notification_id)
    return {"status": "ok"}


@app.get("/api/notifications/apns-status")
def get_apns_status():
    """Return Apple Push Notification service (APNs) credential configuration status."""
    return push_service.get_status()


@app.post("/api/notifications/trigger-watcher")
async def trigger_price_watcher(min_drop: float = Query(1.0, description="Min price drop amount in EUR")):
    """Trigger the server-side price drop watcher to scan wishlists and dispatch push notifications."""
    result = await price_watcher.run_check(min_drop_amount=min_drop)
    return {"status": "ok", "scan_results": result}


@app.post("/api/notifications/test-push")
async def send_test_push(payload: dict):
    """Send a test push notification to verify APNs integration."""
    token = payload.get("device_token")
    if not token:
        raise HTTPException(status_code=400, detail="device_token obbligatorio.")
    title = payload.get("title", "🔥 Test Push FitMatch")
    body = payload.get("body", "Le notifiche push in tempo reale sono configurate correttamente!")
    res = await push_service.send_push(
        device_token=token,
        title=title,
        body=body,
        custom_data={"type": "test"}
    )
    return {"status": "ok", "push_result": res}


# MARK: - Affiliate Outbound Gateway & Click Analytics

@app.get("/api/outbound/redirect")
async def outbound_redirect(
    request: Request,
    background_tasks: BackgroundTasks,
    url: Optional[str] = Query(None, description="Direct target merchant product URL"),
    store_id: Optional[str] = Query(None, description="Store ID, e.g. nike, decathlon, cisalfa"),
    offer_id: Optional[str] = Query(None, description="Offer ID for tracking"),
    source: Optional[str] = Query("app", description="Source interface: product_detail, ai_advisor, wishlist"),
    device_id: Optional[str] = Query(None, description="Client device identifier"),
):
    """
    Gateway redirect endpoint for outbound merchant links.
    Wraps the destination URL with Sovrn //Commerce affiliate parameters,
    records the click event asynchronously, and returns an HTTP 302 redirect.
    """
    target = (url or "").strip()

    if not target:
        raise HTTPException(status_code=400, detail="Parametro 'url' obbligatorio.")

    # Generate tracking CUID
    cuid = affiliate_manager.generate_cuid(store_id=store_id, offer_id=offer_id, device_id=device_id)

    # Build monetized Sovrn Commerce URL (or fallback to target if no key)
    monetized = affiliate_manager.build_monetized_url(
        target_url=target,
        store_id=store_id,
        offer_id=offer_id,
        device_id=device_id,
        cuid=cuid,
    )

    user_agent = request.headers.get("user-agent")

    # Record click event asynchronously
    background_tasks.add_task(
        db.record_affiliate_click,
        target_url=target,
        store_id=store_id,
        offer_id=offer_id,
        monetized_url=monetized,
        cuid=cuid,
        source=source,
        device_id=device_id,
        user_agent=user_agent,
    )

    return RedirectResponse(url=monetized, status_code=302)


@app.get("/api/admin/affiliate/stats")
def get_affiliate_stats_endpoint(limit: int = Query(50, ge=1, le=500)):
    """Retrieve outbound affiliate click telemetry and store breakdowns."""
    stats = db.get_affiliate_click_stats(limit=limit)
    stats["sovrn_active"] = bool(affiliate_manager.sovrn_api_key)
    return stats


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
