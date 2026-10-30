from fastapi import FastAPI, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from fitmatch.service import ComparisonService
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


@app.get("/api/search", response_model=SearchResult)
def search_products(
    q: str = Query(..., min_length=2, description="Product search query (e.g. 'nike pegasus', 'asics nimbus')"),
    limit: int = Query(8, ge=1, le=25, description="Max products to fetch per store"),
    cache: bool = Query(True, description="Enable local caching to speed up repeated queries")
):
    try:
        results = service.search_and_compare(query=q, limit_per_store=limit, use_cache=cache)
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
