import pytest
from fastapi.testclient import TestClient
from api import app

client = TestClient(app)


def test_get_collections_endpoint():
    response = client.get("/api/collections")
    assert response.status_code == 200
    data = response.json()
    assert "collections" in data
    assert isinstance(data["collections"], list)

    names = [c["name"] for c in data["collections"]]
    assert "Tutti" in names
    assert "Scarpe da Corsa" in names
    assert "Smartwatch & GPS" in names


def test_create_and_delete_collection_endpoint():
    # 1. Create collection
    res_create = client.post("/api/collections", json={"name": "Test Maratona 2026"})
    assert res_create.status_code == 200
    assert res_create.json().get("success") is True

    # 2. Check it appears
    res_list = client.get("/api/collections")
    names = [c["name"] for c in res_list.json()["collections"]]
    assert "Test Maratona 2026" in names

    # 3. Delete collection
    res_del = client.delete("/api/collections/Test%20Maratona%202026")
    assert res_del.status_code == 200
    assert res_del.json().get("success") is True


def test_update_wishlist_item_collection_endpoint():
    # Attempt updating a wishlist item's collection
    res = client.patch(
        "/api/wishlist/Nike%20Air%20Zoom%20Pegasus%2041/collection",
        json={"collection_name": "Scarpe da Corsa"}
    )
    assert res.status_code == 200
    assert res.json().get("success") is True
