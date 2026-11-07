import pytest
from fitmatch.affiliate import AffiliateManager


def test_affiliate_manager_fallback_without_key():
    mgr = AffiliateManager(sovrn_api_key="")
    target = "https://www.nike.com/it/t/scarpa-alphafly-3-road-racing-p3"
    result = mgr.build_monetized_url(target, store_id="nike")
    assert result == target


def test_affiliate_manager_with_sovrn_key():
    test_key = "abc123def456sovrnkey789"
    mgr = AffiliateManager(sovrn_api_key=test_key)
    target = "https://www.nike.com/it/t/scarpa-alphafly-3-road-racing-p3"

    monetized = mgr.build_monetized_url(
        target,
        store_id="nike",
        offer_id="nike:12345",
        device_id="iphone_test",
    )

    assert "https://redirect.viglink.com?" in monetized
    assert f"key={test_key}" in monetized
    assert "cuid=fm_nike_" in monetized
    assert "https%3A%2F%2Fwww.nike.com" in monetized


def test_affiliate_manager_cuid_max_length():
    mgr = AffiliateManager(sovrn_api_key="dummy_key")
    cuid = mgr.generate_cuid(
        store_id="runningwarehouse_europe_very_long_name",
        offer_id="offer_987654321_abcdef",
        device_id="device_uuid_very_long_identifier"
    )
    assert len(cuid) <= 32
    assert cuid.startswith("fm_")


def test_api_outbound_redirect_endpoint():
    from fastapi.testclient import TestClient
    from api import app

    client = TestClient(app)
    target = "https://www.nike.com/it/t/scarpa-alphafly-3"

    response = client.get(
        "/api/outbound/redirect",
        params={
            "url": target,
            "store_id": "nike",
            "offer_id": "nike:123",
            "source": "unit_test",
        },
        follow_redirects=False,
    )

    assert response.status_code == 302
    assert "location" in response.headers
    redirect_target = response.headers["location"]
    # Either points to Sovrn (if key set) or direct fallback
    assert "nike.com" in redirect_target

    # Test affiliate stats endpoint
    stats_res = client.get("/api/admin/affiliate/stats")
    assert stats_res.status_code == 200
    data = stats_res.json()
    assert "total_clicks" in data
    assert "by_store" in data

