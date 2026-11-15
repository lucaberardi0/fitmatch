from unittest.mock import patch
from fastapi.testclient import TestClient
from api import app


client = TestClient(app)


def test_get_stores_returns_dynamic_catalog_metadata():
    response = client.get("/api/stores")
    assert response.status_code == 200
    data = response.json()

    assert "active_stores" in data
    assert "stores" in data
    assert "categories" in data
    assert "known_brands" in data

    stores = data["active_stores"]
    assert isinstance(stores, list)
    assert len(stores) >= 17

    by_id = {s["id"]: s for s in stores}
    for required_id in ("sportit", "tennis_point", "basketballstore", "nonsolosport", "intersport", "bshopzone"):
        assert required_id in by_id
        entry = by_id[required_id]
        assert entry["name"]
        assert entry["base_url"].startswith("http")
        assert entry["accent_color"]
        assert entry["free_shipping_threshold"] is not None
        assert entry["standard_shipping_cost"] is not None
        assert entry["courier"]
        assert entry["subtitle"]
        assert entry["country"] in ("IT", "EU")

    if "top4running" in by_id:
        assert by_id["top4running"]["country"] == "EU"
    assert by_id["sportit"]["country"] == "IT"

    cat_ids = {c["id"] for c in data["categories"]}
    for expected_cat in ("tutti", "running", "calcio", "tennis", "basket", "sci", "nuoto", "nutrizione"):
        assert expected_cat in cat_ids

    brands = set(data["known_brands"])
    for brand in ("Nike", "Asics", "Garmin", "Babolat"):
        assert brand in brands


def test_get_stores_surfaces_db_only_store_without_code_change():
    fake_db_store = {
        "id": "nuovo_negozio_db",
        "name": "Nuovo Negozio DB",
        "base_url": "https://www.nuovonegoziodb.it",
        "rating": 4.9,
        "review_count": 320,
        "accent_color": "#123456",
        "card_theme": "white",
        "free_shipping_threshold": 65.0,
        "standard_shipping_cost": 5.5,
        "courier": "DHL Express",
        "country": "EU",
        "logo_url": "https://www.nuovonegoziodb.it/logo.png",
        "is_new": True,
    }
    with patch("api.db.get_stores", return_value=[fake_db_store]):
        response = client.get("/api/stores")

    assert response.status_code == 200
    by_id = {s["id"]: s for s in response.json()["active_stores"]}
    assert "nuovo_negozio_db" in by_id
    added = by_id["nuovo_negozio_db"]
    assert added["name"] == "Nuovo Negozio DB"
    assert added["accent_color"] == "#123456"
    assert added["free_shipping_threshold"] == 65.0
    assert added["standard_shipping_cost"] == 5.5
    assert added["courier"] == "DHL Express"
    assert added["country"] == "EU"
    assert added["logo_url"] == "https://www.nuovonegoziodb.it/logo.png"
    assert added["is_new"] is True
    assert "DHL Express" in added["subtitle"]
    assert "65" in added["subtitle"]
