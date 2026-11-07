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
