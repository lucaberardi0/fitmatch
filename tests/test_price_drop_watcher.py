import asyncio
import pytest
from fitmatch.price_drop_watcher import PriceDropWatcher, _offer_matches_size


class FakePushService:
    def __init__(self):
        self.sent = []

    async def send_push(self, **kwargs):
        self.sent.append(kwargs)
        return {"ok": True}


class FakeSupabase:
    def __init__(self, wishlists, offers_by_pid=None, tokens=None, search_fallback=None):
        self.wishlists = wishlists
        self.offers_by_pid = offers_by_pid or {}
        self.tokens = tokens or []
        self.search_fallback = search_fallback or {}
        self.notifications = []
        self.patches = []
        self.search_calls = []

    def _request(self, endpoint, method="GET", data=None, **kwargs):
        if method == "GET" and endpoint.startswith("wishlists?"):
            return {"status": 200, "data": self.wishlists}
        if method == "GET" and endpoint.startswith("store_offers?product_id=eq."):
            import urllib.parse
            raw_pid = endpoint.split("product_id=eq.", 1)[1].split("&", 1)[0]
            pid = urllib.parse.unquote(raw_pid)
            return {"status": 200, "data": self.offers_by_pid.get(pid, [])}
        if method == "GET" and endpoint.startswith("device_tokens?"):
            return {"status": 200, "data": self.tokens}
        if method == "POST" and endpoint == "notifications":
            self.notifications.append(data)
            return {"status": 201, "data": [data]}
        if method == "PATCH" and endpoint.startswith("wishlists?id=eq."):
            wid = endpoint.split("id=eq.", 1)[1]
            self.patches.append((wid, data))
            return {"status": 200, "data": [data]}
        return {"status": 200, "data": []}

    def search_indexed(self, query):
        self.search_calls.append(query)
        return self.search_fallback.get(query, [])


def test_offer_matches_size_eu_and_comma_normalization():
    assert _offer_matches_size(["EU 42.5", "EU 43"], "42,5") is True
    assert _offer_matches_size(["42 1/2", "44"], "42.5") is True
    assert _offer_matches_size(["40", "41"], "44") is False
    assert _offer_matches_size(["M", "L"], "m") is True


def test_watcher_uses_product_id_and_updates_full_snapshot():
    supa = FakeSupabase(
        wishlists=[
            {
                "id": "w-1",
                "user_id": "u-1",
                "device_id": "dev-1",
                "product_id": "saucony ride 19 [shoes] [Adult]",
                "canonical_name": "Saucony Ride 19",
                "current_price": 120.0,
                "original_price": 160.0,
                "selected_size": "42,5",
                "target_alert_price": 100.0,
                "is_alert_enabled": True,
            }
        ],
        offers_by_pid={
            "saucony ride 19 [shoes] [Adult]": [
                {
                    "id": "o-1",
                    "product_id": "saucony ride 19 [shoes] [Adult]",
                    "store_id": "top4running",
                    "store_name": "Top4Running",
                    "current_price": 85.0,
                    "original_price": 160.0,
                    "product_url": "https://top4running.it/ride-19-no-size",
                    "image_url": "https://img/1.jpg",
                    "available_sizes": ["40", "41"],
                },
                {
                    "id": "o-2",
                    "product_id": "saucony ride 19 [shoes] [Adult]",
                    "store_id": "misterrunning",
                    "store_name": "Mister Running",
                    "current_price": 92.0,
                    "original_price": 160.0,
                    "product_url": "https://misterrunning.com/ride-19",
                    "image_url": "https://img/2.jpg",
                    "available_sizes": ["EU 42.5", "43"],
                },
            ]
        },
        tokens=[{"device_token": "tok-abc", "environment": "production", "min_discount_pct": 5.0}],
    )
    push = FakePushService()
    watcher = PriceDropWatcher(supabase=supa, push_service=push)

    stats = asyncio.run(watcher.run_check())

    # Must NOT have fallen back to text search
    assert supa.search_calls == []
    assert stats["drops_detected"] == 1
    assert stats["notifications_dispatched"] == 1
    assert stats["devices_notified"] == 1

    # Picked the offer that actually has size 42.5 (€92 on Mister Running), NOT €85 without size
    assert supa.notifications[0]["type"] == "target_reached"
    assert supa.notifications[0]["new_price"] == 92.0
    assert supa.notifications[0]["store_name"] == "Mister Running"

    # Full snapshot updated consistently without touching saved_price
    wid, patch = supa.patches[0]
    assert wid == "w-1"
    assert patch["current_price"] == 92.0
    assert patch["store_id"] == "misterrunning"
    assert patch["store_name"] == "Mister Running"
    assert patch["product_url"] == "https://misterrunning.com/ride-19"
    assert patch["discount_pct"] == 42.5
    assert "saved_price" not in patch


def test_watcher_blocks_cross_category_corruption_without_product_id():
    supa = FakeSupabase(
        wishlists=[
            {
                "id": "w-2",
                "user_id": "u-2",
                "device_id": "dev-2",
                "product_id": None,
                "canonical_name": "Ride 19",
                "current_price": 159.95,
                "original_price": 159.95,
                "selected_size": None,
                "target_alert_price": None,
                "is_alert_enabled": True,
            }
        ],
        search_fallback={
            "Ride 19": [
                {
                    "offers": [
                        {
                            "store_id": "maxisport",
                            "store_name": "Maxi Sport",
                            "price": 8.95,
                            "url": "https://maxisport.com/bogus-sock",
                        }
                    ]
                }
            ]
        },
    )
    watcher = PriceDropWatcher(supabase=supa, push_service=FakePushService())
    stats = asyncio.run(watcher.run_check())

    assert stats["drops_detected"] == 0
    assert supa.patches == []
    assert supa.notifications == []
