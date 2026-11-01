import logging
from fastapi import FastAPI, Query, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor
from fitmatch.ai_comparator import AIModelComparator, ModelComparisonResponse
from fitmatch.smart_search import SmartSearchEngine
from fitmatch.updater import PriceUpdater
from fitmatch.scheduler import SyncScheduler
from fitmatch.models import SearchResult

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
smart_engine = SmartSearchEngine()


advisor = AIShoppingAdvisor(service=service, db=db)
comparator = AIModelComparator(service=service)


@app.on_event("startup")
def on_startup():
    # Start autonomous background scheduler (Price monitor every 2h, catalog discovery every 24h)
    scheduler.start(refresh_interval_seconds=7200, discovery_interval_seconds=86400)


@app.on_event("shutdown")
def on_shutdown():
    scheduler.stop()


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "FitMatch Price Engine"}


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
    max_price: Optional[float] = Query(None, description="Explicit max price override from active chip"),
    size: Optional[str] = Query(None, description="Explicit size filter"),
    category: Optional[str] = Query(None, description="Category filter override"),
    store: Optional[str] = Query(None, description="Store filter (e.g. 'cisalfa', 'top4running')"),
    limit: int = Query(35, ge=1, le=100)
):
    """Shopify Shop-style intelligent search: interprets user intent, extracts filters and returns ranked multi-store products."""
    intent = smart_engine.parse_query(q)

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
        store_id=store,
        limit=limit
    )

    # Live Multi-Store Federated Search Fallback:
    # If local indexed DB returns 0 products for this smart query, immediately trigger live scrapers across retailers!
    if not products:
        live_kw = intent.target_keywords[0] if intent.target_keywords else q
        logger.info(f"[search_smart] 0 local products for '{q}'. Triggering live multi-store crawler for '{live_kw}'")
        try:
            live_res = service.search_and_compare(query=live_kw, size=eff_size, limit_per_store=8, use_cache=True)
            if live_res.matched_products:
                products = [
                    {
                        "id": mp.canonical_name,
                        "canonical_name": mp.canonical_name,
                        "brand": mp.brand or intent.brand,
                        "category": eff_category or "running_shoes",
                        "gender": intent.gender or "Unisex",
                        "image_url": mp.image_url,
                        "offer_count": len(mp.offers),
                        "best_price": mp.best_price,
                        "max_price": mp.highest_price,
                        "offers": [o.model_dump() for o in mp.offers],
                        "highest_price": mp.highest_price,
                        "cross_store_savings": mp.cross_store_savings
                    }
                    for mp in live_res.matched_products
                ]
                # Index into database so future searches are cached
                try:
                    for mp in live_res.matched_products:
                        for off in mp.offers:
                            cluster_key = f"{mp.canonical_name.lower()} [{eff_category or 'running_shoes'}] [{intent.gender or 'Unisex'}]"
                            db.upsert_product_and_offer(
                                cluster_key=cluster_key,
                                canonical_name=mp.canonical_name,
                                brand=mp.brand or intent.brand,
                                category=eff_category or "running_shoes",
                                gender=intent.gender or "Unisex",
                                offer=off
                            )
                except Exception as save_err:
                    logger.warning(f"[search_smart] Failed to cache live offers: {save_err}")
        except Exception as e:
            logger.error(f"[search_smart] Live crawl federation error: {e}")

    return {
        "intent": {
            "raw_query": intent.raw_query,
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
        "chips": [c.model_dump() for c in intent.chips],
        "total_found": len(products),
        "results": products
    }



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


@app.post("/api/crawl")
def trigger_crawl(
    background_tasks: BackgroundTasks,
    limit_per_store: int = Query(100, ge=10, le=2000),
    store: Optional[str] = Query(None, description="Specific store ID to crawl (e.g. 'cisalfa', 'deporvillage') or all")
):
    """Trigger background crawler to update local catalog from all or specific stores."""
    crawler = CategoryCrawler(db=db)
    stores = [store] if store else None
    background_tasks.add_task(crawler.run_full_sync, limit_per_store, stores)
    return {
        "status": "scheduled",
        "message": f"Crawl job avviato in background per {store or 'tutti i 10 negozi'}",
        "target_per_store": limit_per_store
    }


# --- Autonomous Scheduler Endpoints ---

@app.get("/api/scheduler/status")
def get_scheduler_status():
    """Retrieve live status, cycles and schedule of the autonomous spider engine."""
    return scheduler.get_status()


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
    """Trigger an immediate catalog discovery run across all stores in background."""
    return scheduler.trigger_discovery_now(limit_per_store=limit_per_store)


@app.post("/api/scheduler/run-refresh")
def trigger_scheduler_refresh(limit: int = Query(50, ge=10, le=500)):
    """Trigger an immediate price & stock refresh for indexed products in background."""
    return scheduler.trigger_refresh_now(limit=limit)


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
    return {"status": "ok", "collection": created}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
