from fastapi import FastAPI, Query, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor
from fitmatch.smart_search import SmartSearchEngine
from fitmatch.updater import PriceUpdater
from fitmatch.models import SearchResult

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
updater = PriceUpdater.get_instance()
smart_engine = SmartSearchEngine()


advisor = AIShoppingAdvisor(service=service, db=db)


@app.on_event("startup")
def on_startup():
    # Start background price refresh daemon (every 4 hours)
    updater.start_scheduler(interval_seconds=14400)


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
    sort: str = Query("discount", regex="^(discount|price_asc|price_desc|name)$"),
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
    """Live multi-store federated search across all 4 retailers with optional size verification."""
    try:
        results = service.search_and_compare(query=q, size=size, limit_per_store=limit, use_cache=cache)
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/crawl")
def trigger_crawl(
    background_tasks: BackgroundTasks,
    limit_per_store: int = Query(50, ge=10, le=500)
):
    """Trigger background crawler to update local catalog from all stores."""
    crawler = CategoryCrawler(db=db)
    background_tasks.add_task(crawler.run_full_sync, limit_per_store)
    return {
        "message": "Crawl job scheduled in background",
        "target_per_store": limit_per_store
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
    background_tasks.add_task(updater.run_update_sync, limit)
    return {
        "status": "scheduled",
        "message": f"Aggiornamento prezzi avviato in background per {limit} prodotti."
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
