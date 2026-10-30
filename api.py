from fastapi import FastAPI, Query, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor
from fitmatch.models import SearchResult

app = FastAPI(
    title="FitMatch API",
    description="Multi-store Sportswear Scraping & Price Comparison Engine",
    version="0.1.0"
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


advisor = AIShoppingAdvisor(service=service, db=db)


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


@app.get("/api/stats")
def get_catalog_stats():
    """Retrieve indexed database overview statistics and price gap metrics."""
    return db.get_stats()


@app.get("/api/catalog")
def search_local_catalog(
    q: str = Query("", description="Keywords to filter indexed products (e.g. 'nike', 'asics', 'donna')"),
    limit: int = Query(25, ge=1, le=100)
):
    """Sub-millisecond query directly on the pre-indexed database catalog."""
    return {
        "query": q,
        "results": db.search_indexed(query=q, limit=limit)
    }


@app.get("/api/ai/advise")
def ai_advise(
    prompt: str = Query(..., min_length=4, description="Natural language shopper needs (e.g. 'peso 85kg corro su asfalto sotto i 140 euro')")
):
    """AI Shopper: translates natural language runner profiles into optimal models and live bargains."""
    return advisor.advise(prompt)


@app.get("/api/search", response_model=SearchResult)
def search_live(
    q: str = Query(..., min_length=2, description="Product search query (e.g. 'nike pegasus', 'asics nimbus')"),
    limit: int = Query(8, ge=1, le=25, description="Max products to fetch per store"),
    cache: bool = Query(True, description="Enable local caching to speed up repeated queries")
):
    """Live multi-store federated search across all 4 retailers."""
    try:
        results = service.search_and_compare(query=q, limit_per_store=limit, use_cache=cache)
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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
