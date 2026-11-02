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


def test_supabase_products_for_update():
    db = Database()
    prods = db.get_products_for_update(limit=3)
    assert isinstance(prods, list)
    assert len(prods) > 0
    first = prods[0]
    assert "id" in first
    assert "canonical_name" in first

    # Test touching product updated
    res = db.touch_product_updated(first["id"])
    assert res is True


def test_supabase_price_history_and_offer_price():
    db = Database()
    res = db.search_indexed(query="Pegasus", limit=1)
    assert len(res) > 0
    offers = res[0].get("offers", [])
    assert len(offers) > 0
    first_offer = offers[0]
    
    # Query offer price via helper
    raw_offers = db.supabase._request("store_offers?limit=1&select=id,current_price")
    offer_id = raw_offers["data"][0]["id"]
    price = db.get_offer_price(offer_id)
    assert price is not None
    assert price > 0

    # Test recording price history on an existing offer
    assert db.record_price_history(offer_id, price) is True
