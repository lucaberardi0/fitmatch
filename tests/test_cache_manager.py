import time
import os
import shutil
import pytest
from fitmatch.cache_manager import SearchCacheManager, LRUMemoryCache
from fitmatch.smart_search import SmartSearchIntent


@pytest.fixture
def temp_cache_dir(tmp_path):
    cache_dir = os.path.join(tmp_path, "test_cache")
    yield cache_dir
    if os.path.exists(cache_dir):
        shutil.rmtree(cache_dir, ignore_errors=True)


def test_lru_eviction():
    cache = LRUMemoryCache(max_size=3)
    cache.set("a", 1, ttl_seconds=100)
    cache.set("b", 2, ttl_seconds=100)
    cache.set("c", 3, ttl_seconds=100)

    # Access "a" so "b" becomes the least recently used
    assert cache.get("a") == 1

    # Adding "d" should evict "b"
    cache.set("d", 4, ttl_seconds=100)
    assert cache.get("b") is None
    assert cache.get("a") == 1
    assert cache.get("c") == 3
    assert cache.get("d") == 4


def test_ttl_expiration():
    cache = LRUMemoryCache(max_size=10)
    cache.set("short_lived", "hello", ttl_seconds=0.1)
    assert cache.get("short_lived") == "hello"

    time.sleep(0.15)
    assert cache.get("short_lived") is None


def test_query_normalization():
    mgr = SearchCacheManager(cache_dir="/tmp/test_norm")
    q1 = mgr.normalize_query("   Maison Margiela Scarpe Nere???  ")
    q2 = mgr.normalize_query("maison   margiela scarpe nere! ")
    assert q1 == "maison margiela scarpe nere"
    assert q2 == "maison margiela scarpe nere"
    assert q1 == q2


def test_intent_persistence_and_l2_reload(temp_cache_dir):
    mgr = SearchCacheManager(cache_dir=temp_cache_dir, intent_ttl=3600)

    mock_intent = SmartSearchIntent(
        raw_query="scarpe running ammortizzate",
        search_mode="deep_dive",
        is_deep_dive=True,
        target_keywords=["running", "ammortizzate"],
        brand="Nike",
        category="running_shoes"
    )

    mgr.set_intent("scarpe running ammortizzate", force_mode="deep_dive", intent_data=mock_intent)

    # 1. Immediate retrieval from L1
    cached_intent = mgr.get_intent("scarpe running ammortizzate", force_mode="deep_dive")
    assert cached_intent is not None
    assert cached_intent["brand"] == "Nike"
    assert cached_intent["is_deep_dive"] is True

    # 2. Simulate server restart: clear L1 memory cache, retrieve from L2 disk
    mgr.memory_cache.clear()
    assert mgr.memory_cache.size() == 0

    reloaded = mgr.get_intent("  scarpe running ammortizzate? ", force_mode="deep_dive")
    assert reloaded is not None
    assert reloaded["brand"] == "Nike"
    # Should have re-warmed L1 memory
    assert mgr.memory_cache.size() == 1


def test_response_caching_and_invalidation(temp_cache_dir):
    mgr = SearchCacheManager(cache_dir=temp_cache_dir, results_ttl=1200)

    key = mgr.make_response_key("nike pegasus 41", mode="classic", max_price=150.0)
    response_payload = {
        "search_mode": "classic",
        "total_found": 5,
        "results": [{"id": "p1", "canonical_name": "Nike Pegasus 41", "best_price": 119.0}]
    }

    mgr.set_search_response(key, response_payload)

    # Check hit
    cached = mgr.get_search_response(key)
    assert cached is not None
    assert cached["results"][0]["best_price"] == 119.0

    # Invalidate responses (e.g. after price update)
    purged = mgr.invalidate_responses()
    assert mgr.get_search_response(key) is None


def test_telemetry_metrics_and_savings(temp_cache_dir):
    mgr = SearchCacheManager(cache_dir=temp_cache_dir)
    mgr.intent_hits = 10
    mgr.intent_misses = 2
    mgr.response_hits = 5
    mgr.response_misses = 1

    metrics = mgr.get_metrics()
    assert metrics["telemetry"]["intent_hits"] == 10
    assert metrics["telemetry"]["response_hits"] == 5
    assert metrics["savings"]["llm_calls_saved"] == 15
    assert metrics["savings"]["estimated_tokens_saved"] == 15 * (450 + 250)
    assert metrics["savings"]["estimated_usd_saved"] > 0
