from fitmatch.db import Database


def test_supabase_cloud_stats():
    db = Database()
    stats = db.get_stats()
    assert isinstance(stats, dict)
    assert stats["total_products"] > 0
    assert stats["total_offers"] > 0
    assert len(stats["store_breakdown"]) > 0


def test_supabase_cloud_search():
    db = Database()
    results = db.search_indexed(query="Pegasus", limit=3)
    assert isinstance(results, list)
    if results:
        first = results[0]
        assert "canonical_name" in first
        assert "best_price" in first
        assert len(first["offers"]) > 0


def test_supabase_store_details():
    db = Database()
    details = db.get_store_details("misterrunning", limit=5)
    assert details is not None
    assert details["store_id"] == "misterrunning"
    assert details["store_name"] == "Mister Running"
    assert len(details["products"]) > 0
