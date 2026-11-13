import asyncio
import json
import logging
import re
import threading
import time
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, Query, HTTPException, BackgroundTasks, Request
from fastapi.responses import HTMLResponse, RedirectResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List, Callable
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

    # Autonomous background vector embedding backfill (ensures coverage for newly indexed products)
    startup_limit = int(os.getenv("FITMATCH_STARTUP_EMBEDDING_LIMIT", "200"))
    if startup_limit > 0:
        _start_embedding_job(batch_size=25, limit=startup_limit, category=None, trigger_source="startup", standalone=False)


@app.on_event("shutdown")
def on_shutdown():
    _embedding_stop_event.set()
    scheduler.stop()


# --- Embedding Job State & Admin Controls ---

_embedding_lock = threading.Lock()
_embedding_stop_event = threading.Event()
_embedding_state = {
    "is_running": False,
    "category": None,
    "batch_size": 25,
    "limit": None,
    "processed_count": 0,
    "started_at": None,
    "last_finished_at": None,
    "last_status": "idle",
    "last_error": None,
}


def _start_embedding_job(
    batch_size: int = 25,
    limit: Optional[int] = None,
    category: Optional[str] = None,
    trigger_source: str = "manual_admin_api",
    standalone: bool = True,
) -> dict:
    clean_cat = (category or "").strip()
    if clean_cat.lower() in ("", "all", "tutte"):
        clean_cat = None

    with _embedding_lock:
        if _embedding_state["is_running"]:
            return {
                "status": "busy",
                "message": f"Embedding già in corso ({_embedding_state.get('category') or 'tutte le categorie'}, processati: {_embedding_state.get('processed_count', 0)}).",
            }
        _embedding_stop_event.clear()
        _embedding_state.update({
            "is_running": True,
            "category": clean_cat,
            "batch_size": batch_size,
            "limit": limit,
            "processed_count": 0,
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "last_status": "running",
            "last_error": None,
        })

    def _progress(count: int):
        with _embedding_lock:
            _embedding_state["processed_count"] = count

    def _worker():
        res = {"status": "error", "error": "unknown"}
        try:
            res = scheduler.run_embedding_task(
                batch_size=batch_size,
                limit=limit,
                standalone=standalone,
                trigger_source=trigger_source,
                category=clean_cat,
                stop_event=_embedding_stop_event,
                progress_callback=_progress,
            )
        except Exception as exc:
            res = {"status": "error", "error": str(exc)}
        finally:
            with _embedding_lock:
                _embedding_state["is_running"] = False
                _embedding_state["last_finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                _embedding_state["last_status"] = res.get("status", "completed")
                _embedding_state["last_error"] = res.get("error")
                if "processed" in res:
                    _embedding_state["processed_count"] = int(res.get("processed") or _embedding_state["processed_count"])

    threading.Thread(target=_worker, daemon=True, name="FitMatch-Embedding-Worker").start()
    target_label = clean_cat or "tutte le categorie"
    limit_label = f" (max {limit})" if limit else ""
    return {
        "status": "accepted",
        "message": f"Generazione embedding avviata per {target_label}{limit_label}.",
    }


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


@app.get("/api/admin/embeddings/status")
def get_embeddings_status():
    """Return real-time embedding job state and active-catalog coverage by category."""
    rows = []
    try:
        if getattr(db, "supabase", None) and getattr(db.supabase, "api_key", None):
            res = db.supabase._request("rpc/get_embedding_coverage", method="POST", data={})
            if isinstance(res, dict) and isinstance(res.get("data"), list):
                rows = res["data"]
    except Exception as e:
        logger.warning(f"[AdminEmbeddings] Coverage RPC warning: {e}")

    total_active = sum(int(r.get("active_count") or 0) for r in rows)
    total_embedded = sum(int(r.get("embedded_count") or 0) for r in rows)
    total_missing = sum(int(r.get("missing_count") or 0) for r in rows)
    coverage_pct = round((total_embedded / total_active) * 100, 1) if total_active > 0 else (100.0 if rows else 0.0)

    with _embedding_lock:
        job_snapshot = dict(_embedding_state)
        job_snapshot["stop_requested"] = _embedding_stop_event.is_set()

    return {
        "job": job_snapshot,
        "coverage": {
            "total_active": total_active,
            "total_embedded": total_embedded,
            "total_missing": total_missing,
            "coverage_pct": coverage_pct,
            "by_category": rows,
        },
    }


@app.post("/api/admin/embeddings/sync")
def trigger_embedding_sync(
    category: Optional[str] = Query(None, description="Specific product category or 'all'"),
    limit: Optional[int] = Query(None, ge=1, le=20000, description="Max products to embed in this run"),
    batch_size: int = Query(25, ge=5, le=50, description="Products per batch"),
):
    """Trigger autonomous background vector embedding generation for unindexed products."""
    return _start_embedding_job(
        batch_size=batch_size,
        limit=limit,
        category=category,
        trigger_source="manual_admin_api",
        standalone=True,
    )


@app.post("/api/admin/embeddings/stop")
def stop_embedding_sync():
    """Gracefully stop an active vector embedding backfill job after the current batch."""
    with _embedding_lock:
        was_running = _embedding_state["is_running"]
    _embedding_stop_event.set()
    return {
        "status": "stopping" if was_running else "idle",
        "message": "Arresto richiesto: il job terminerà al termine del batch corrente." if was_running else "Nessun job di embedding in esecuzione.",
    }


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


@app.get("/api/feed/personalized")
def get_personalized_home_feed(
    device_id: Optional[str] = Query(None, description="Persistent anonymous client device ID"),
    user_id: Optional[str] = Query(None, description="Authenticated Supabase User ID"),
    shoe_size: Optional[str] = Query(None, description="User preferred shoe size (e.g. '42')"),
    apparel_size: Optional[str] = Query(None, description="User preferred apparel size (e.g. 'M')"),
    brands: Optional[str] = Query(None, description="Comma-separated favorite brands (e.g. 'Nike,Asics,Hoka')"),
    sports: Optional[str] = Query(None, description="Comma-separated sports (e.g. 'corsa,trail')"),
    min_discount: int = Query(20, ge=0, le=90, description="Minimum discount threshold"),
    limit_per_store: int = Query(12, ge=3, le=30, description="Products per store showcase")
):
    """Generate intelligent personalized home feed: ranked merchant showcases, size-matched deals, and re-ranked products."""
    brand_list = [b.strip() for b in brands.split(",") if b.strip()] if brands else None
    sports_list = [s.strip() for s in sports.split(",") if s.strip()] if sports else None

    return db.get_personalized_feed(
        device_id=device_id,
        user_id=user_id,
        shoe_size=shoe_size,
        apparel_size=apparel_size,
        brands=brand_list,
        sports=sports_list,
        min_discount=min_discount,
        limit_per_store=limit_per_store
    )


@app.get("/api/feed/size-deals")
def get_size_deals_endpoint(
    size: str = Query("42", description="Target EU size for shoes or clothing (e.g. '42', 'M')"),
    min_discount: int = Query(20, ge=0, le=90, description="Minimum discount threshold"),
    limit: int = Query(12, ge=1, le=30, description="Maximum deals to return"),
    brands: Optional[str] = Query(None, description="Optional comma-separated preferred brands")
):
    """Retrieve top cross-store discounted offers strictly in-stock in the user's specific size."""
    brand_list = [b.strip() for b in brands.split(",") if b.strip()] if brands else None
    deals = db.get_size_deals(size=size, min_discount=min_discount, limit=limit, favorite_brands=brand_list)
    return {"size": size, "deals": deals, "count": len(deals)}


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
    prompt: str = Query(..., min_length=4, description="Natural language shopper needs (e.g. 'peso 85kg corro su asfalto sotto i 140 euro')"),
    session_id: Optional[str] = Query(None, description="Optional chat session ID for persistence"),
    device_id: Optional[str] = Query(None, description="Client device ID for chat history"),
    user_id: Optional[str] = Query(None, description="Optional authenticated user ID")
):
    """AI Shopper: translates natural language runner profiles into optimal models and live bargains."""
    res = advisor.advise(prompt)
    eff_sid = session_id.strip() if isinstance(session_id, str) and session_id.strip() else None
    eff_did = device_id.strip() if isinstance(device_id, str) and device_id.strip() else None
    eff_uid = user_id.strip() if isinstance(user_id, str) and user_id.strip() else None
    if eff_sid or eff_did or eff_uid:
        try:
            saved = db.save_chat_turn(
                session_id=eff_sid,
                device_id=eff_did or "default_device",
                user_id=eff_uid,
                chat_type="ai_advisor",
                query=prompt.strip(),
                is_follow_up=bool(eff_sid),
                response_payload={
                    "conversational_header": res.get("category_name") or "Consulenza IA",
                    "conversational_summary": res.get("biomechanical_reasoning") or res.get("category_description"),
                    "is_conversational_advice": True,
                    "results": [
                        {
                            "id": r.get("link") or r.get("product_name", ""),
                            "canonical_name": r.get("product_name", ""),
                            "brand": r.get("brand"),
                            "image_url": r.get("image_url"),
                            "best_price": r.get("best_price"),
                            "cross_store_savings": r.get("cross_store_savings"),
                            "offers": r.get("all_offers") or [],
                        }
                        for r in (res.get("recommendations") or [])
                        if isinstance(r, dict)
                    ],
                },
                context_state={"user_profile": res.get("user_profile")},
            )
            res = dict(res)
            res["session_id"] = saved.get("session_id")
            res["turn_id"] = saved.get("turn_id")
        except Exception as e:
            logger.warning(f"[ai_advise] Failed to persist chat turn: {e}")
    return res


@app.get("/api/ai/compare", response_model=ModelComparisonResponse)
def compare_models(
    model_a: str = Query(..., min_length=2, description="First model to compare (e.g. 'Pegasus 41', 'Forerunner 165')"),
    model_b: str = Query(..., min_length=2, description="Second model to compare (e.g. 'Nimbus 26', 'Forerunner 265')")
):
    """AI Side-by-side technical, biomechanical, and live pricing comparison between two sports gear models."""
    from fitmatch.smart_search import QuerySecurityGuardrail
    for m in [model_a, model_b]:
        sec = QuerySecurityGuardrail.evaluate(m)
        if sec and sec.get("is_blocked"):
            raise HTTPException(status_code=400, detail="Il confronto tecnico è disponibile esclusivamente per scarpe e attrezzatura sportiva.")
    return comparator.compare_models(model_a, model_b)


def _persist_smart_search_turn(
    result_data: dict,
    query: str,
    session_id: Optional[str],
    device_id: Optional[str],
    user_id: Optional[str],
    is_follow_up: bool,
    prev_session_context: Optional[dict] = None,
) -> dict:
    """Persist a Smart Search turn to DB if tracking identifiers are supplied and return a shallow copy with IDs."""
    if not (session_id or device_id or user_id):
        return result_data
    try:
        intent_dict = result_data.get("intent") or {}
        q_clean = query.strip()
        is_more = smart_engine.is_more_examples_query(q_clean)
        prev_search_q = (prev_session_context or {}).get("last_search_query") or (prev_session_context or {}).get("last_query")
        effective_topic_q = prev_search_q if (is_more and prev_search_q) else q_clean

        prev_shown = list((prev_session_context or {}).get("shown_ids") or [])
        cur_shown = [str(p.get("id")) for p in (result_data.get("results") or [])[:15] if p.get("id")]
        merged_shown = list(dict.fromkeys(prev_shown + cur_shown))[-50:]

        saved = db.save_chat_turn(
            session_id=session_id,
            device_id=device_id or "default_device",
            user_id=user_id,
            chat_type="smart_search",
            query=q_clean,
            is_follow_up=is_follow_up,
            response_payload=result_data,
            context_state={
                "last_query": q_clean,
                "last_search_query": effective_topic_q,
                "last_keywords": intent_dict.get("target_keywords") or (prev_session_context or {}).get("last_keywords") or [],
                "shown_ids": merged_shown,
                "brand": intent_dict.get("brand"),
                "category": intent_dict.get("category"),
                "gender": intent_dict.get("gender"),
                "max_price": intent_dict.get("max_price"),
                "min_price": intent_dict.get("min_price"),
                "size": intent_dict.get("size"),
                "features": intent_dict.get("features") or [],
            },
        )
        out = dict(result_data)
        out["session_id"] = saved.get("session_id")
        out["turn_id"] = saved.get("turn_id")
        return out
    except Exception as e:
        logger.warning(f"[search_smart] Failed to persist chat turn: {e}")
        return result_data


def _execute_smart_search(
    q: str,
    mode: Optional[str] = None,
    max_price: Optional[float] = None,
    size: Optional[str] = None,
    category: Optional[str] = None,
    store: Optional[str] = None,
    context_query: Optional[str] = None,
    session_id: Optional[str] = None,
    device_id: Optional[str] = None,
    user_id: Optional[str] = None,
    preferred_size: Optional[str] = None,
    limit: int = 35,
    progress_cb: Optional[Callable[[dict], None]] = None,
) -> dict:
    """Shared smart-search execution pipeline used by both JSON and SSE streaming endpoints."""
    started_at = time.monotonic()

    def _emit_step(step_id: str, status: str, title: str, detail: Optional[str] = None) -> None:
        if not progress_cb:
            return
        try:
            evt = {
                "type": "step",
                "id": step_id,
                "status": status,
                "title": title,
                "elapsed_ms": int((time.monotonic() - started_at) * 1000),
            }
            if detail:
                evt["detail"] = detail
            progress_cb(evt)
        except Exception:
            pass

    def _emit_child(evt: dict) -> None:
        if not progress_cb or not isinstance(evt, dict):
            return
        try:
            payload = dict(evt)
            payload.setdefault("elapsed_ms", int((time.monotonic() - started_at) * 1000))
            progress_cb(payload)
        except Exception:
            pass

    eff_mode = mode.strip() if isinstance(mode, str) and mode.strip() else None
    eff_max_price_param = float(max_price) if isinstance(max_price, (int, float)) else None
    eff_size_param = size.strip() if isinstance(size, str) and size.strip() else None
    eff_category_param = category.strip() if isinstance(category, str) and category.strip() else None
    eff_store = store.strip() if isinstance(store, str) and store.strip() else None
    eff_context = context_query.strip() if isinstance(context_query, str) and context_query.strip() else None
    eff_session_id = session_id.strip() if isinstance(session_id, str) and session_id.strip() else None
    eff_device_id = device_id.strip() if isinstance(device_id, str) and device_id.strip() else None
    eff_user_id = user_id.strip() if isinstance(user_id, str) and user_id.strip() else None
    eff_pref_size = preferred_size.strip() if isinstance(preferred_size, str) and preferred_size.strip() else None

    session_context = None
    conversation_history = []
    if eff_session_id:
        _emit_step("context", "running", "Recupero il contesto della conversazione…")
        try:
            sess_detail = db.get_chat_session_detail(eff_session_id)
            if sess_detail:
                if isinstance(sess_detail.get("context_state"), dict):
                    session_context = sess_detail.get("context_state")
                for msg in (sess_detail.get("messages") or [])[-8:]:
                    if not isinstance(msg, dict):
                        continue
                    q_m = (msg.get("query") or msg.get("user_query") or "").strip()
                    rp = msg.get("response_payload") or {}
                    a_m = (rp.get("conversational_summary") or msg.get("assistant_summary") or "").strip()
                    if q_m or a_m:
                        conversation_history.append({"query": q_m, "summary": a_m})
        except Exception as e:
            logger.warning(f"[search_smart] Failed to load session context for {eff_session_id}: {e}")
        ctx_detail = f"{len(conversation_history)} messaggi precedenti considerati" if conversation_history else "Nuova sessione inizializzata"
        _emit_step("context", "done", "Contesto conversazione caricato", ctx_detail)

    is_more_examples = smart_engine.is_more_examples_query(q)
    effective_q = f"{eff_context} >> {q.strip()}" if eff_context else q
    if eff_pref_size:
        effective_q = f"{effective_q} [pref_size:{eff_pref_size}]"

    # 1. Tier-2 Response Cache Check (skip cache on follow-up pagination / active chat history so fresh products & replies serve)
    cache_key = cache_manager.make_response_key(
        query=effective_q,
        mode=eff_mode,
        max_price=eff_max_price_param,
        size=eff_size_param,
        category=eff_category_param,
        store=eff_store,
        limit=limit
    )
    cached_resp = None if (is_more_examples or conversation_history) else cache_manager.get_search_response(cache_key)
    if cached_resp is not None:
        cached_count = len(cached_resp.get("results") or [])
        _emit_step("cache", "done", "Risposta rapida dalla cache", f"{cached_count} modelli già verificati pronti")
        return _persist_smart_search_turn(
            cached_resp,
            query=q,
            session_id=eff_session_id,
            device_id=eff_device_id,
            user_id=eff_user_id,
            is_follow_up=bool(eff_context or (session_context is not None)),
            prev_session_context=session_context,
        )

    intent = smart_engine.parse_query(
        q,
        force_mode=eff_mode,
        context_query=eff_context,
        session_context=session_context,
        conversation_history=conversation_history or None,
        progress_cb=_emit_child,
    )

    # 1. Guardrail Safety & Relevance Check: Strictly block off-topic and unsafe queries!
    if getattr(intent, "is_off_topic", False) or getattr(intent, "is_unsafe", False) or not intent.target_keywords:
        logger.info(f"[search_smart] Guardrail blocked query '{q}' (off_topic={getattr(intent, 'is_off_topic', False)}, unsafe={getattr(intent, 'is_unsafe', False)})")
        from fitmatch.smart_search import QuerySecurityGuardrail
        result_data = {
            "search_mode": intent.search_mode,
            "is_deep_dive": True,
            "conversational_header": intent.conversational_header or "Richiesta non pertinente",
            "conversational_summary": intent.conversational_summary or "FitMatch è un assistente specializzato in prodotti per lo sport, la corsa, il fitness e l'outdoor.",
            "curated_sections": [],
            "comparative_cards": [],
            "spotlight": None,
            "follow_up_suggestions": intent.follow_up_suggestions or QuerySecurityGuardrail.DEFAULT_SPORTS_SUGGESTIONS,
            "chips": [],
            "intent": intent.model_dump(),
            "total_found": 0,
            "results": [],
            "is_off_topic": getattr(intent, "is_off_topic", False),
            "is_unsafe": getattr(intent, "is_unsafe", False)
        }
        cache_manager.set_search_response(cache_key, result_data)
        return result_data

    from fitmatch.smart_search import QueryProductGuardrail
    detected_product_type = QueryProductGuardrail.detect_product_type(q, eff_context)

    # Use explicit query overrides if user modified/toggled active chips
    eff_max_price = eff_max_price_param if eff_max_price_param is not None else intent.max_price
    eff_size = eff_size_param if eff_size_param is not None else intent.size
    eff_category = eff_category_param if eff_category_param is not None else intent.category

    shown_ids_to_exclude = list((session_context or {}).get("shown_ids") or []) if is_more_examples else None

    scope_parts = []
    if intent.target_keywords:
        scope_parts.append(", ".join(intent.target_keywords[:3]))
    if eff_max_price is not None:
        scope_parts.append(f"≤ €{int(eff_max_price) if float(eff_max_price).is_integer() else eff_max_price}")
    if eff_size:
        scope_parts.append(f"taglia {eff_size}")
    if eff_store:
        scope_parts.append(f"store {eff_store}")
    _emit_step(
        "catalog",
        "running",
        "Cerco nel catalogo multi-store…",
        " · ".join(scope_parts) if scope_parts else None,
    )

    products = db.search_smart(
        target_keywords=intent.target_keywords,
        category=eff_category,
        brand=intent.brand,
        gender=intent.gender,
        max_price=eff_max_price,
        min_price=intent.min_price,
        size=eff_size,
        store_id=eff_store,
        limit=limit,
        raw_query=q,
        preferred_size=eff_pref_size,
        exclude_ids=shown_ids_to_exclude,
    )

    if not products and is_more_examples and shown_ids_to_exclude:
        products = db.search_smart(
            target_keywords=intent.target_keywords,
            category=eff_category,
            brand=intent.brand,
            gender=intent.gender,
            max_price=eff_max_price,
            min_price=intent.min_price,
            size=eff_size,
            store_id=eff_store,
            limit=limit,
            raw_query=q,
            preferred_size=eff_pref_size,
        )

    # Extra safety filter: ensure every returned product satisfies product-type guardrails
    if products and detected_product_type:
        products = [
            p for p in products
            if QueryProductGuardrail.is_product_compatible(p, detected_product_type, raw_query=q)
        ]

    # Strict Price Guardrail: ensure every offer and product strictly respects eff_max_price
    if products and eff_max_price is not None:
        filtered_by_price = []
        for p in products:
            valid_offers = [o for o in (p.get("offers") or []) if float(o.get("price") or 0.0) <= float(eff_max_price)]
            if valid_offers:
                p["offers"] = valid_offers
                prices = [float(o["price"]) for o in valid_offers]
                p["best_price"] = min(prices)
                p["highest_price"] = max(prices)
                p["cross_store_savings"] = round(p["highest_price"] - p["best_price"], 2) if len(prices) > 1 else 0.0
                if p["best_price"] <= float(eff_max_price):
                    filtered_by_price.append(p)
        products = filtered_by_price

    # Strict Gender Guardrail
    if products and intent.gender in ("Uomo", "Donna"):
        req_g = intent.gender.lower()
        filtered_by_gender = []
        for p in products:
            p_g = (p.get("gender") or "unisex").lower()
            cname = (p.get("canonical_name") or "").lower()
            if req_g == "uomo" and (p_g == "donna" or "(donna)" in cname or " wmns " in cname or "women" in cname):
                continue
            if req_g == "donna" and (p_g == "uomo" or "(uomo)" in cname or " men " in cname or " mens " in cname):
                continue
            filtered_by_gender.append(p)
        products = filtered_by_gender

    # Model relevance re-ranking: prioritize products matching the specific requested model
    if products and intent.target_keywords:
        primary_kws = [k.lower().strip() for k in intent.target_keywords[:2] if k.strip()]
        def _relevance_sort_key(p):
            pname = (p.get("canonical_name") or "").lower()
            for rank, kw in enumerate(primary_kws):
                if kw in pname:
                    return (rank, p.get("best_price") or 0.0)
            return (99, p.get("best_price") or 0.0)
        products.sort(key=_relevance_sort_key)

    if products:
        unique_stores = {
            (o.get("store_id") or o.get("store_name"))
            for p in products
            for o in (p.get("offers") or [])
            if (o.get("store_id") or o.get("store_name"))
        }
        min_found_price = min((float(p.get("best_price") or 0.0) for p in products if p.get("best_price")), default=0.0)
        detail_parts = []
        if unique_stores:
            detail_parts.append(f"{len(unique_stores)} store confrontati")
        if min_found_price > 0:
            detail_parts.append(f"a partire da €{min_found_price:.2f}")
        _emit_step(
            "catalog",
            "done",
            f"Trovati {len(products)} modelli compatibili",
            " · ".join(detail_parts) if detail_parts else None,
        )
    else:
        _emit_step(
            "catalog",
            "done",
            "Nessun modello locale immediato",
            "Avvio aggiornamento prezzi sugli store partner",
        )

    # Stage-2 Grounded RAG Synthesis: when query is conversational/discovery/follow-up and LLM key is available,
    # synthesize an intelligent response grounded strictly in the retrieved real Supabase products.
    if smart_engine.should_synthesize_grounded(q, intent, context_query=eff_context):
        _emit_step(
            "synthesis",
            "running",
            "Confronto specifiche e prezzi…",
            f"Valutazione tecnica su {min(len(products), 12)} modelli selezionati" if products else "Preparazione guida tecnica",
        )
        try:
            from fitmatch.smart_search import (
                OpenRouterParser,
                CuratedSectionDef,
                SpecComparisonDef,
                SpotlightDef,
            )
            grounded = OpenRouterParser.synthesize_grounded_response(
                user_query=q,
                intent=intent,
                products=products,
                api_key=smart_engine.api_key,
                model=smart_engine.model,
                conversation_history=conversation_history or None,
                context_query=eff_context,
            )
            if isinstance(grounded, dict):
                if grounded.get("conversational_header"):
                    intent.conversational_header = str(grounded["conversational_header"]).strip()
                if grounded.get("conversational_summary"):
                    intent.conversational_summary = str(grounded["conversational_summary"]).strip()
                    intent.explanation = intent.conversational_summary
                raw_secs = grounded.get("curated_sections")
                if isinstance(raw_secs, list) and raw_secs:
                    parsed_secs = [
                        CuratedSectionDef(
                            id=str(s.get("id") or f"sec_rag_{i}"),
                            title=str(s.get("title") or "").strip(),
                            subtitle=str(s.get("subtitle") or "").strip(),
                            keywords=[str(k).strip() for k in (s.get("keywords") or []) if k],
                        )
                        for i, s in enumerate(raw_secs)
                        if isinstance(s, dict) and s.get("title")
                    ]
                    if parsed_secs:
                        intent.curated_sections = parsed_secs
                raw_specs = grounded.get("spec_comparisons")
                if isinstance(raw_specs, list) and raw_specs:
                    parsed_specs = [
                        SpecComparisonDef(
                            model_name=str(sc.get("model_name") or "").strip(),
                            ideal_for=str(sc.get("ideal_for") or "").strip(),
                            strengths=str(sc.get("strengths") or "").strip(),
                            target_keyword=str(sc.get("target_keyword") or "").strip() or None,
                        )
                        for sc in raw_specs
                        if isinstance(sc, dict) and sc.get("model_name")
                    ]
                    if parsed_specs:
                        intent.spec_comparisons = parsed_specs
                raw_spot = grounded.get("spotlight")
                if isinstance(raw_spot, dict) and raw_spot.get("target_keyword"):
                    intent.spotlight = SpotlightDef(
                        target_keyword=str(raw_spot["target_keyword"]).strip(),
                        badge_text=str(raw_spot.get("badge_text") or "Consigliato").strip(),
                        highlights=[str(h).strip() for h in (raw_spot.get("highlights") or []) if h],
                    )
                raw_fups = grounded.get("follow_up_suggestions")
                if isinstance(raw_fups, list) and raw_fups:
                    clean_fups = [str(f).strip() for f in raw_fups if str(f).strip()]
                    if clean_fups:
                        intent.follow_up_suggestions = clean_fups[:3]
                intent.source = "openrouter_grounded"
            _emit_step(
                "synthesis",
                "done",
                "Sintesi tecnica completata",
                intent.conversational_header or "Analisi comparativa pronta",
            )
        except Exception as e:
            logger.warning(f"[search_smart] Stage-2 grounded synthesis warning: {e}")
            _emit_step("synthesis", "done", "Analisi tecnica completata")

    # Live Multi-Store Federated Search:
    # If indexed catalog returns 0 products for this smart query, launch background multi-store scrapers
    # and return fast recommendations without freezing the HTTP response!
    if not products:
        brand_names = {"nike", "adidas", "puma", "asics", "brooks", "saucony", "hoka", "mizuno", "on", "new balance", "salomon", "garmin"}
        candidate_kws = [k for k in (intent.target_keywords or []) if k.strip().lower() not in brand_names]
        queries_to_crawl = candidate_kws[:2] if len(candidate_kws) >= 2 else ([candidate_kws[0]] if candidate_kws else [q])
        logger.info(f"[search_smart] 0 local products for '{q}'. Triggering asynchronous background crawler for {queries_to_crawl}")

        import threading
        def _bg_crawl_worker():
            for kw in queries_to_crawl:
                eff_kw = f"{intent.brand} {kw}" if intent.brand and intent.brand.lower() not in kw.lower() else kw
                try:
                    service.search_and_compare(query=eff_kw, size=eff_size, limit_per_store=4, use_cache=True)
                except Exception as e:
                    logger.warning(f"[search_smart] Background crawler warning for '{eff_kw}': {e}")

        threading.Thread(target=_bg_crawl_worker, daemon=True).start()

    # Helper to check if a section title/subtitle is locked to a specific brand
    SECTION_BRAND_NAMES = [
        "adidas", "nike", "puma", "asics", "hoka", "saucony", "brooks",
        "salomon", "garmin", "mizuno", "odlo", "new balance", "on", "reebok", "oakley",
        "coros", "suunto", "polar", "bullpadel", "nox", "babolat", "head"
    ]

    def _product_matches_section(p: dict, sec_kws: list, sec_brand_lock: Optional[str], sec_title_sub: str = "") -> bool:
        name_lower = (p.get("canonical_name") or "").lower()
        brand_lower = (p.get("brand") or "").lower()
        p_cat = (p.get("category") or "").lower()
        off_titles = " ".join((o.get("title") or "") for o in (p.get("offers") or [])[:2]).lower()
        combined = f"{name_lower} {brand_lower} {off_titles}"

        if sec_brand_lock and not re.search(rf"\b{re.escape(sec_brand_lock)}\b", f"{brand_lower} {name_lower}"):
            return False

        # Guard against cross-category contamination inside thematic sections
        is_apparel_sec = bool(re.search(r"\b(abbigliamento|magli[ae]|t[\s-]*shirt|canott[ae]|pantaloncin[oi]|leggings|giacc(?:a|he)|antivento|termic[aoe]|long\s*sleeve|manic(?:a|he))\b", sec_title_sub))
        is_shoe_sec = bool(re.search(r"\b(scarp[ae]|calzatur[ae]|sneakers?|daily\s*trainer|ammortizzat[ae]|maratona)\b", sec_title_sub)) and not is_apparel_sec
        is_road_sec = bool(re.search(r"\b(strada|asfalto)\b", sec_title_sub)) and not bool(re.search(r"\b(trail|sterrato|sentier)\b", sec_title_sub))
        is_trail_sec = bool(re.search(r"\b(trail|sterrato|sentier[oi]|montagna|fango)\b", sec_title_sub)) and not bool(re.search(r"\b(strada|asfalto)\b", sec_title_sub))

        if is_apparel_sec:
            if p_cat in ("shoes", "running_shoes", "trail_running", "gps_watch", "cycling", "eyewear", "padel", "racket"):
                return False
            if not re.search(r"\b(magli[ae]|t[\s-]*shirt|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet|pantaloncin[oi]|shorts?|leggings|tights|giacc(?:a|he)|jacket|antivento|gilet|felp[ae]|hoodie|calz[ae]|top|tee\b)\b", combined):
                return False
        elif is_shoe_sec:
            if not QueryProductGuardrail.is_product_compatible(p, "shoes", raw_query=q):
                return False

        if is_road_sec and (p_cat == "trail_running" or re.search(r"\b(trail|speedcross|trabuco|speedgoat|cascadia|terrex\s*agravic|sonoma|mujin|ultra\s*raptor|akasha)\b", name_lower)):
            return False
        if is_trail_sec and not (p_cat == "trail_running" or re.search(r"\b(trail|speedcross|trabuco|speedgoat|cascadia|terrex|ultra\s*glide|prodigio|akasha|bushido|peregrine|hierro|salomon)\b", combined)):
            return False

        # Gender guardrails when section title explicitly targets Uomo or Donna
        p_gender = (p.get("gender") or "").lower()
        sec_wants_men = bool(re.search(r"\b(per\s+uomo|da\s+uomo|\buomo\b)\b", sec_title_sub)) and not bool(re.search(r"\b(donna|unisex)\b", sec_title_sub))
        sec_wants_women = bool(re.search(r"\b(per\s+donna|da\s+donna|\bdonna\b)\b", sec_title_sub)) and not bool(re.search(r"\b(uomo|unisex)\b", sec_title_sub))
        if sec_wants_men and (p_gender == "donna" or "(donna)" in name_lower):
            return False
        if sec_wants_women and (p_gender == "uomo" or "(uomo)" in name_lower):
            return False

        if not sec_kws:
            return True

        # Strip the query's own global brand or generic words if there are more specific section keywords
        q_brand_low = (intent.brand or "").lower().strip()
        specific_sec_kws = [
            k for k in sec_kws
            if k not in QueryProductGuardrail.GENERIC_CATEGORY_KEYWORDS
            and k != q_brand_low
        ]
        if not specific_sec_kws:
            return True

        return any(re.search(rf"\b{re.escape(k)}\b", combined) for k in specific_sec_kws)

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
                if _product_matches_section(p, sec_kws, sec_brand_lock, sec_title_sub):
                    sec_prods.append(p)
                    used_product_ids.add(p.get("id"))
                if len(sec_prods) >= 8:
                    break

            # Fallback without brand lock if 0 products matched and user didn't filter by that brand
            if not sec_prods and sec_kws:
                for p in products:
                    if p.get("id") in used_product_ids:
                        continue
                    if _product_matches_section(p, sec_kws, None, sec_title_sub):
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
        is_exact_sec = curated_sections_out[0].get("id") == "sec_exact_model"
        if not is_exact_sec and len(curated_sections_out[0]["products"]) < 6:
            need = 8 - len(curated_sections_out[0]["products"])
            curated_sections_out[0]["products"].extend(unused_products[:need])
            unused_products = unused_products[need:]
        if unused_products:
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
    def _default_tech_highlights_for_product(prod: dict) -> List[str]:
        pname = (prod.get("canonical_name") or "").lower()
        pcat = (prod.get("category") or "").lower()
        if pcat == "gps_watch" or re.search(r"\b(forerunner|fenix|instinct|coros|suunto|vantage|pacer)\b", pname):
            return [
                "GPS multi-banda ad alta precisione e cardio al polso",
                "Metriche avanzate di passo, carico di allenamento e recupero"
            ]
        if pcat == "cycling" or re.search(r"\b(edge|ciclocomputer|bsc|igpsport|bryton|kickr|flux)\b", pname):
            return [
                "Navigazione GPS e metriche di performance per ciclismo",
                "Connettività ANT+ / Bluetooth e lunga autonomia"
            ]
        if pcat == "eyewear" or re.search(r"\b(oakley|sutro|radar|jawbreaker|occhiali|bliz|rudy)\b", pname):
            return [
                "Lenti ad alto contrasto con protezione UV 100%",
                "Montatura ultraleggera e stabile anche con sudore intenso"
            ]
        if pcat in ("padel", "racket") or re.search(r"\b(vertex|hack|at10|viper|metalbone|racchetta|pala)\b", pname):
            return [
                "Costruzione in carbonio per equilibrio tra potenza e controllo",
                "Nucleo reattivo con assorbimento delle vibrazioni"
            ]
        if pcat in ("hydration", "pack") or re.search(r"\b(active\s*skin|adv\s*skin|zaino|gilet|flask)\b", pname):
            return [
                "Vestibilità ergonomica stabile senza rimbalzi in corsa",
                "Scomparti rapidi per borracce morbide e accessori"
            ]
        if pcat == "football_boots" or re.search(r"\b(mercurial|predator|phantom|tiempo|copa|future|top\s*sala|top\s*flex|scarpin[oi]|calcetto)\b", pname):
            return [
                "Tacchettatura progettata per trazione, cambi di direzione e stabilità",
                "Tomaia aderente per controllo preciso e sensibilità sul pallone"
            ]
        if pcat == "swim" or re.search(r"\b(occhialin|biofuse|cobra\s*ultra|fastskin|nuoto|arena|speedo|tyr)\b", pname):
            return [
                "Guarnizioni ergonomiche morbide per tenuta confortevole in vasca",
                "Lenti trattate anti-appannamento e protezione UV"
            ]
        if pcat in ("top", "jacket", "pants", "socks", "apparel"):
            return [
                "Tessuto tecnico traspirante ad asciugatura rapida",
                "Taglio ergonomico sportivo con cuciture anti-sfregamento"
            ]
        if re.search(r"\b(vaporfly|alphafly|adios\s*pro|metaspeed|endorphin\s*pro|cielo|deviate\s*nitro\s*elite)\b", pname):
            return [
                "Intersuola super-critica ad alto ritorno di energia per gara",
                "Geometria propulsiva leggera per maratona e ritmi veloci"
            ]
        if re.search(r"\b(nimbus|bondi|glycerin|clifton|1080|triumph|vomero|wave\s*sky)\b", pname):
            return [
                "Massima ammortizzazione e assorbimento degli impatti su strada",
                "Tomaia traspirante progettata per lunghi chilometraggi"
            ]
        if re.search(r"\b(speedgoat|speedcross|trabuco|cascadia|ultra\s*raptor|prodigio|akasha|peregrine)\b", pname):
            return [
                "Suola tassellata ad alta aderenza su sentieri, rocce e fango",
                "Tomaia rinforzata per stabilità e protezione in montagna"
            ]
        return [
            "Ammortizzazione reattiva e transizione fluida",
            "Tomaia in mesh ingegnerizzato leggero e traspirante"
        ]

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

        if not clean_tech_hl:
            clean_tech_hl = _default_tech_highlights_for_product(prod)

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
        spec_words = [w for w in re.findall(r"\b\w+\b", target_kw) if len(w) > 3 and w not in GENERIC_COMP_WORDS]
        matched_spotlight_prod = next(
            (
                p for p in products
                if re.search(rf"\b{re.escape(target_kw)}\b", (p.get("canonical_name") or "").lower())
                or (spec_words and all(re.search(rf"\b{re.escape(sw)}\b", (p.get("canonical_name") or "").lower()) for sw in spec_words))
            ),
            None
        )
        if matched_spotlight_prod:
            spotlight_out = _build_truthful_spotlight(
                matched_spotlight_prod,
                intent.spotlight.badge_text,
                intent.spotlight.highlights
            )

    # If no explicit spotlight or didn't match, pick the top relevance product with product-accurate highlights
    if not spotlight_out and products:
        best_p = products[0]
        raw_badge = intent.spotlight.badge_text if intent.spotlight else "Miglior Scelta"
        spotlight_out = _build_truthful_spotlight(best_p, raw_badge, None)

    def _compact_product(p: dict) -> dict:
        if not p or not isinstance(p, dict):
            return p
        cp = dict(p)
        if cp.get("gallery_images"):
            cp["gallery_images"] = cp["gallery_images"][:5]
        if cp.get("offers"):
            cp["offer_count"] = len(cp["offers"])
            clean_offers = []
            for o in cp["offers"][:8]:
                co = dict(o) if isinstance(o, dict) else o.model_dump() if hasattr(o, "model_dump") else {}
                co["gallery_images"] = None
                clean_offers.append(co)
            cp["offers"] = clean_offers
        return cp

    compact_results = [_compact_product(p) for p in products]
    compact_sections = []
    for sec in curated_sections_out:
        sec_copy = dict(sec)
        sec_copy["products"] = [_compact_product(p) for p in sec.get("products", [])]
        compact_sections.append(sec_copy)
    compact_cards = []
    for card in comparative_cards_out:
        card_copy = dict(card)
        if "product" in card_copy:
            card_copy["product"] = _compact_product(card_copy["product"])
        compact_cards.append(card_copy)
    compact_spotlight = None
    if spotlight_out:
        compact_spotlight = dict(spotlight_out)
        if "product" in compact_spotlight:
            compact_spotlight["product"] = _compact_product(compact_spotlight["product"])

    result_data = {
        "search_mode": intent.search_mode,
        "is_deep_dive": intent.is_deep_dive,
        "is_conversational_advice": getattr(intent, "is_conversational_advice", False),
        "conversational_header": intent.conversational_header,
        "conversational_summary": intent.conversational_summary,
        "curated_sections": compact_sections,
        "comparative_cards": compact_cards,
        "spotlight": compact_spotlight,
        "follow_up_suggestions": intent.follow_up_suggestions,
        "chips": [c.model_dump() for c in intent.chips],
        "intent": {
            "raw_query": intent.raw_query,
            "search_mode": intent.search_mode,
            "is_deep_dive": intent.is_deep_dive,
            "is_conversational_advice": getattr(intent, "is_conversational_advice", False),
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
        "results": compact_results
    }

    if compact_sections or compact_cards:
        curation_parts = []
        if compact_sections:
            curation_parts.append(f"{len(compact_sections)} sezioni")
        if compact_cards:
            curation_parts.append(f"{len(compact_cards)} confronti")
        _emit_step(
            "curation",
            "done",
            "Risultati organizzati",
            " · ".join(curation_parts),
        )

    # Store full curated response into L1 memory & L2 disk cache (20-min TTL) for non-paginated queries
    if not is_more_examples and not conversation_history:
        cache_manager.set_search_response(cache_key, result_data)
    return _persist_smart_search_turn(
        result_data,
        query=q,
        session_id=eff_session_id,
        device_id=eff_device_id,
        user_id=eff_user_id,
        is_follow_up=bool(eff_context or (session_context is not None)),
        prev_session_context=session_context,
    )


@app.get("/api/search/smart")
def search_smart(
    q: str = Query(..., min_length=2, description="Natural language or keywords query (e.g. 'scarpe running ammortizzate sotto 140 euro')"),
    mode: Optional[str] = Query(None, description="Force search mode: 'deep_dive' or 'classic'"),
    max_price: Optional[float] = Query(None, description="Explicit max price override from active chip"),
    size: Optional[str] = Query(None, description="Explicit size filter"),
    category: Optional[str] = Query(None, description="Category filter override"),
    store: Optional[str] = Query(None, description="Store filter (e.g. 'cisalfa', 'top4running')"),
    context_query: Optional[str] = Query(None, description="Previous search query to maintain conversational context"),
    session_id: Optional[str] = Query(None, description="Persistent chat session UUID"),
    device_id: Optional[str] = Query(None, description="Client device ID for persistent chat history"),
    user_id: Optional[str] = Query(None, description="Optional user ID for persistent chat history"),
    preferred_size: Optional[str] = Query(None, description="Optional soft preference size boost from user profile"),
    limit: int = Query(35, ge=1, le=100)
):
    """Shopify Shop-style intelligent search: interprets user intent, classifies query mode (AI deep dive vs classic),
    clusters results into curated thematic carousels, provides spotlight recommendation and follow-up prompts.
    """
    return _execute_smart_search(
        q=q,
        mode=mode,
        max_price=max_price,
        size=size,
        category=category,
        store=store,
        context_query=context_query,
        session_id=session_id,
        device_id=device_id,
        user_id=user_id,
        preferred_size=preferred_size,
        limit=limit,
    )


@app.get("/api/search/smart/stream")
async def search_smart_stream(
    q: str = Query(..., min_length=2, description="Natural language or keywords query"),
    mode: Optional[str] = Query(None, description="Force search mode: 'deep_dive' or 'classic'"),
    max_price: Optional[float] = Query(None, description="Explicit max price override from active chip"),
    size: Optional[str] = Query(None, description="Explicit size filter"),
    category: Optional[str] = Query(None, description="Category filter override"),
    store: Optional[str] = Query(None, description="Store filter"),
    context_query: Optional[str] = Query(None, description="Previous search query to maintain conversational context"),
    session_id: Optional[str] = Query(None, description="Persistent chat session UUID"),
    device_id: Optional[str] = Query(None, description="Client device ID for persistent chat history"),
    user_id: Optional[str] = Query(None, description="Optional user ID for persistent chat history"),
    preferred_size: Optional[str] = Query(None, description="Optional soft preference size boost from user profile"),
    limit: int = Query(35, ge=1, le=100),
):
    """Server-Sent Events (SSE) version of /api/search/smart emitting real execution trace events followed by final result."""
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue = asyncio.Queue()
    started = time.monotonic()

    def _push(payload: Optional[dict]) -> None:
        loop.call_soon_threadsafe(queue.put_nowait, payload)

    def _worker() -> None:
        try:
            result = _execute_smart_search(
                q=q,
                mode=mode,
                max_price=max_price,
                size=size,
                category=category,
                store=store,
                context_query=context_query,
                session_id=session_id,
                device_id=device_id,
                user_id=user_id,
                preferred_size=preferred_size,
                limit=limit,
                progress_cb=_push,
            )
            _push({
                "type": "result",
                "elapsed_ms": int((time.monotonic() - started) * 1000),
                "data": result,
            })
        except Exception as exc:
            logger.exception("[search_smart_stream] Unhandled error during streaming smart search")
            _push({"type": "error", "message": str(exc)})
        finally:
            _push(None)

    threading.Thread(target=_worker, daemon=True).start()

    async def _event_generator():
        while True:
            item = await queue.get()
            if item is None:
                break
            yield f"data: {json.dumps(item, default=str)}\n\n"

    return StreamingResponse(
        _event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )



@app.get("/api/search", response_model=SearchResult)
def search_live(
    q: str = Query(..., min_length=2, description="Product search query (e.g. 'nike pegasus', 'asics nimbus')"),
    size: Optional[str] = Query(None, description="Filter only offers having this size in stock (e.g. '43', '42.5', 'M')"),
    limit: int = Query(8, ge=1, le=25, description="Max products to fetch per store"),
    cache: bool = Query(True, description="Enable local caching to speed up repeated queries")
):
    """Live multi-store federated search across all 10 retailers with optional size verification."""
    from fitmatch.smart_search import QuerySecurityGuardrail
    sec_eval = QuerySecurityGuardrail.evaluate(q)
    if sec_eval and sec_eval.get("is_blocked"):
        return SearchResult(query=q, total_found=0, matched_products=[], execution_time_ms=0.5)

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


# MARK: - Persistent AI Search Chats & Messages

@app.get("/api/chats")
def list_chat_sessions_endpoint(
    device_id: Optional[str] = Query(None, description="Filter chats by device_id"),
    user_id: Optional[str] = Query(None, description="Filter chats by authenticated user_id"),
    chat_type: Optional[str] = Query(None, description="Filter by chat_type: 'smart_search' or 'ai_advisor'"),
    limit: int = Query(30, ge=1, le=100),
):
    """List saved conversation sessions ordered by most recently updated."""
    eff_did = device_id.strip() if isinstance(device_id, str) and device_id.strip() else None
    eff_uid = user_id.strip() if isinstance(user_id, str) and user_id.strip() else None
    eff_type = chat_type.strip() if isinstance(chat_type, str) and chat_type.strip() else None
    sessions = db.get_chat_sessions(device_id=eff_did, user_id=eff_uid, chat_type=eff_type, limit=limit)
    return {"sessions": sessions}


@app.get("/api/chats/{session_id}")
def get_chat_session_detail_endpoint(session_id: str):
    """Retrieve a saved chat session with all ordered turns and snapshots."""
    session = db.get_chat_session_detail(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Chat non trovata.")
    return session


@app.post("/api/chats/sync")
def sync_chat_turn_endpoint(payload: dict):
    """Persist or sync a conversation turn directly to Supabase + SQLite."""
    query_str = str(payload.get("query") or "").strip()
    if not query_str:
        raise HTTPException(status_code=400, detail="Campo 'query' obbligatorio.")
    saved = db.save_chat_turn(
        session_id=payload.get("session_id"),
        device_id=str(payload.get("device_id") or "default_device"),
        user_id=payload.get("user_id"),
        chat_type=str(payload.get("chat_type") or "smart_search"),
        query=query_str,
        is_follow_up=bool(payload.get("is_follow_up", False)),
        response_payload=payload.get("response_payload") or {},
        context_state=payload.get("context_state"),
    )
    return {"status": "ok", **saved}


@app.patch("/api/chats/{session_id}/messages/{turn_id}/feedback")
def update_chat_feedback_endpoint(session_id: str, turn_id: str, payload: dict):
    """Save positive/negative feedback (1 or -1) on a specific chat turn."""
    fb = payload.get("feedback")
    if fb not in (-1, 0, 1):
        raise HTTPException(status_code=400, detail="Il valore feedback deve essere -1, 0 o 1.")
    ok = db.update_chat_message_feedback(session_id, turn_id, int(fb))
    return {"status": "ok", "success": ok}


@app.delete("/api/chats/{session_id}")
def delete_chat_session_endpoint(session_id: str, device_id: Optional[str] = Query(None)):
    """Delete a single saved chat session and its turns."""
    eff_did = device_id.strip() if isinstance(device_id, str) and device_id.strip() else None
    ok = db.delete_chat_session(session_id, device_id=eff_did)
    return {"status": "ok", "success": ok}


@app.delete("/api/chats")
def clear_chat_sessions_endpoint(
    device_id: Optional[str] = Query(None),
    user_id: Optional[str] = Query(None),
):
    """Clear all saved chat sessions for a device or user."""
    eff_did = device_id.strip() if isinstance(device_id, str) and device_id.strip() else None
    eff_uid = user_id.strip() if isinstance(user_id, str) and user_id.strip() else None
    if not (eff_did or eff_uid):
        raise HTTPException(status_code=400, detail="Specificare almeno device_id o user_id.")
    ok = db.clear_chat_sessions(device_id=eff_did, user_id=eff_uid)
    return {"status": "ok", "success": ok}


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
