import pytest
from fastapi.testclient import TestClient
from api import app


@pytest.fixture
def client():
    return TestClient(app)


def test_size_deals_endpoint(client):
    response = client.get("/api/feed/size-deals?size=42&min_discount=15&limit=5")
    assert response.status_code == 200
    data = response.json()
    assert "deals" in data
    assert "size" in data
    assert data["size"] == "42"
    assert isinstance(data["deals"], list)
    if data["deals"]:
        first = data["deals"][0]
        assert "title" in first
        assert "current_price" in first
        assert "store_name" in first


def test_personalized_feed_endpoint(client):
    response = client.get("/api/feed/personalized?shoe_size=42&brands=Nike,Hoka&limit_per_store=4")
    assert response.status_code == 200
    data = response.json()
    assert "user_context" in data
    assert data["user_context"]["shoe_size"] == "42"
    assert "showcases" in data
    assert isinstance(data["showcases"], list)
    if data["showcases"]:
        first_store = data["showcases"][0]
        assert "store_name" in first_store
        assert "products" in first_store
