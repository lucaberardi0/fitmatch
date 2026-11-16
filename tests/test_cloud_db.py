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


def test_sqlite_auto_cleanup_orphan_products_trigger(tmp_path):
    from fitmatch.models import Offer

    db = Database(db_path=str(tmp_path / "orphan_test.db"), use_supabase=False)
    offer = Offer(
        store_id="cisalfa",
        store_name="Cisalfa Sport",
        product_id="o1",
        title="Nike Pegasus 41",
        brand="Nike",
        price=120.0,
        url="https://www.cisalfasport.it/p/1",
    )
    db.upsert_product_and_offer("ck_old", "Nike Pegasus 41", "Nike", "shoes", "Adult", offer)
    db.upsert_product_and_offer(
        "ck_new",
        "Nike Pegasus 41",
        "Nike",
        "shoes",
        "Adult",
        Offer(
            store_id="maxisport",
            store_name="Maxi Sport",
            product_id="o2",
            title="Nike Pegasus 41",
            brand="Nike",
            price=125.0,
            url="https://www.maxisport.com/p/2",
        ),
    )

    with db.get_connection() as conn:
        # Moving o1 from ck_old -> ck_new must automatically delete ck_old
        conn.execute("UPDATE store_offers SET product_id = 'ck_new' WHERE id = 'cisalfa:o1'")
        old_prod = conn.execute("SELECT id FROM products WHERE id = 'ck_old'").fetchone()
        assert old_prod is None

        # Deleting o1 while o2 still points to ck_new keeps ck_new
        conn.execute("DELETE FROM store_offers WHERE id = 'cisalfa:o1'")
        assert conn.execute("SELECT id FROM products WHERE id = 'ck_new'").fetchone() is not None

        # Deleting last offer o2 automatically deletes ck_new
        conn.execute("DELETE FROM store_offers WHERE id = 'maxisport:o2'")
        assert conn.execute("SELECT id FROM products WHERE id = 'ck_new'").fetchone() is None


def test_supabase_upsert_cleans_up_product_on_offer_failure():
    from fitmatch.models import Offer
    from fitmatch.supabase_client import SupabaseClient

    sc = SupabaseClient(base_url="https://example.supabase.co", api_key="test")
    calls = []

    def fake_request(endpoint, method="GET", data=None, **kwargs):
        calls.append((method, endpoint))
        if method == "POST" and endpoint == "products":
            return {"status": 201, "data": data}
        if method == "POST" and endpoint == "store_offers":
            return {"status": 500, "data": None}
        if method == "GET" and endpoint.startswith("store_offers?product_id=eq."):
            return {"status": 200, "data": []}
        if method == "DELETE" and endpoint.startswith("products?id=eq."):
            return {"status": 204, "data": None}
        return {"status": 200, "data": []}

    sc._request = fake_request
    sc.upsert_product_and_offer(
        cluster_key="test_ck",
        canonical_name="Test Product",
        brand="Nike",
        category="shoes",
        gender="Adult",
        image_url=None,
        offer=Offer(
            store_id="nike",
            store_name="Nike",
            product_id="p1",
            title="Test Product",
            price=100.0,
            url="https://www.nike.com/it/t/test/1",
        ),
    )

    assert any(m == "DELETE" and ep == "products?id=eq.test_ck" for m, ep in calls)
    assert not any(m == "POST" and ep == "price_history" for m, ep in calls)


def test_supabase_save_chat_turn_validates_user_id_uuid():
    from fitmatch.supabase_client import SupabaseClient

    sc = SupabaseClient(base_url="https://example.supabase.co", api_key="test")
    assert sc.parse_valid_uuid("a6a4e25d-c4fc-4481-ba7b-22f8e24fc8cb") == "a6a4e25d-c4fc-4481-ba7b-22f8e24fc8cb"
    assert sc.parse_valid_uuid("001234.apple-non-uuid-id") is None
    assert sc.parse_valid_uuid("") is None

    captured_sessions = []

    def fake_request(endpoint, method="GET", data=None, **kwargs):
        if method == "POST" and endpoint.startswith("chat_sessions"):
            captured_sessions.append(data)
            return {"status": 201, "data": [data]}
        if method == "POST" and endpoint == "chat_messages":
            return {"status": 201, "data": [data]}
        return {"status": 200, "data": []}

    sc._request = fake_request

    # Non-UUID user_id (e.g. legacy Apple credential id) must not be sent to Postgres uuid column
    sc.save_chat_turn(
        session_id="11111111-1111-4111-8111-111111111111",
        device_id="DEV-1",
        user_id="001234.apple-non-uuid",
        chat_type="smart_search",
        query="Nike Pegasus",
        is_follow_up=False,
        response_payload={"results": []},
    )
    assert "user_id" not in captured_sessions[-1]

    # Valid UUID user_id is preserved in lowercase canonical form
    sc.save_chat_turn(
        session_id="11111111-1111-4111-8111-111111111111",
        device_id="DEV-1",
        user_id="A6A4E25D-C4FC-4481-BA7B-22F8E24FC8CB",
        chat_type="smart_search",
        query="Nike Pegasus",
        is_follow_up=False,
        response_payload={"results": []},
    )
    assert captured_sessions[-1]["user_id"] == "a6a4e25d-c4fc-4481-ba7b-22f8e24fc8cb"


