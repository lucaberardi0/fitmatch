import tempfile
import os
import pytest
from fastapi.testclient import TestClient
from api import app
from fitmatch.db import Database

client = TestClient(app)


def test_price_history_endpoint_validation():
    # Calling without parameters should return 400
    res = client.get("/api/products/price-history")
    assert res.status_code == 400
    assert "Either canonical_name or product_id" in res.json()["detail"]


def test_price_history_sqlite_fallback():
    # Test SQLite database fallback directly
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        db = Database(db_path=tmp_path, use_supabase=False)
        with db.get_connection() as conn:
            conn.execute("INSERT INTO products (id, canonical_name, brand) VALUES ('prod1', 'Nike Pegasus 40', 'Nike')")
            conn.execute("INSERT INTO store_offers (id, product_id, store_id, store_name, raw_title, current_price, original_price, product_url) VALUES ('off1', 'prod1', 'cisalfa', 'Cisalfa Sport', 'Nike Pegasus 40', 89.99, 140.0, 'https://example.com/pegasus')")
            conn.execute("INSERT INTO price_history (offer_id, price, recorded_at) VALUES ('off1', 119.99, '2026-10-15 10:00:00')")
            conn.execute("INSERT INTO price_history (offer_id, price, recorded_at) VALUES ('off1', 89.99, '2026-11-01 12:00:00')")
            conn.commit()

        res = db.get_price_history(product_id="prod1")
        assert res["canonical_name"] == "Nike Pegasus 40"
        assert res["current_price"] == 89.99
        assert res["lowest_price"] == 89.99
        assert res["is_all_time_low"] is True
        assert res["total_data_points"] >= 2
        assert res["price_drop_percentage"] > 0
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_price_history_synthetic_baseline():
    # Test brand new product with only current price and original MSRP
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        db = Database(db_path=tmp_path, use_supabase=False)
        with db.get_connection() as conn:
            conn.execute("INSERT INTO products (id, canonical_name, brand) VALUES ('prod2', 'Asics Nimbus 26', 'Asics')")
            conn.execute("INSERT INTO store_offers (id, product_id, store_id, store_name, raw_title, current_price, original_price, product_url) VALUES ('off2', 'prod2', 'top4running', 'Top4Running', 'Asics Nimbus 26', 159.0, 200.0, 'https://example.com/nimbus')")
            conn.commit()

        res = db.get_price_history(canonical_name="Asics Nimbus 26")
        assert res["canonical_name"] == "Asics Nimbus 26"
        assert res["current_price"] == 159.0
        assert res["highest_price"] == 200.0
        assert res["total_data_points"] >= 2
        assert any(pt["price"] == 200.0 for pt in res["history_points"])
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_supabase_record_price_history_batch_dedup_and_no_synthetic_baseline():
    from unittest.mock import MagicMock
    from fitmatch.supabase_client import SupabaseClient

    sb = SupabaseClient.__new__(SupabaseClient)
    posted_batches = []

    def fake_request(endpoint, method="GET", data=None, **kwargs):
        if method == "GET" and endpoint.startswith("price_history?offer_id=in."):
            return {
                "status": 200,
                "data": [
                    {"offer_id": "o_same", "price": 100.0, "recorded_at": "2026-11-26T10:00:00Z"},
                    {"offer_id": "o_drop", "price": 120.0, "recorded_at": "2026-11-26T10:00:00Z"},
                ],
            }
        if method == "POST" and endpoint == "price_history":
            posted_batches.append(data)
            return {"status": 201, "data": data}
        if method == "GET" and endpoint.startswith("products?id=eq."):
            return {"status": 200, "data": [{"id": "p1", "canonical_name": "Nike Pegasus 42", "brand": "Nike"}]}
        if method == "GET" and endpoint.startswith("store_offers?product_id=eq."):
            return {
                "status": 200,
                "data": [{
                    "id": "o_new",
                    "store_id": "misterrunning",
                    "store_name": "Mister Running",
                    "current_price": 110.0,
                    "original_price": 150.0,
                    "discount_pct": 27,
                    "last_checked_at": "2026-11-26T12:00:00Z",
                }],
            }
        return {"status": 200, "data": []}

    sb._request = MagicMock(side_effect=fake_request)

    # Batch should skip unchanged recent o_same, insert changed o_drop and brand-new o_new
    count = sb.record_price_history_batch({"o_same": 100.0, "o_drop": 99.0, "o_new": 110.0})
    assert count == 2
    inserted_ids = {r["offer_id"] for batch in posted_batches for r in batch}
    assert inserted_ids == {"o_drop", "o_new"}

    # Supabase get_price_history must NOT fabricate a fake 30-day 'Listino Ufficiale' point
    hist = sb.get_price_history(product_id="p1")
    assert all(pt["store_name"] != "Listino Ufficiale" for pt in hist["history_points"])
    assert hist["current_price"] == 110.0
