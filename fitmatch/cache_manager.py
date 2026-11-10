"""High-Performance Multi-Tier Caching System for FitMatch Smart Search.

Provides:
- L1: Thread-safe, in-memory LRU cache with fine-grained TTL.
- L2: Persistent disk cache ensuring cache survival across server restarts and deployments.
- Tiered retention:
    * Semantic Intent Cache (long TTL, e.g. 7 days): caches LLM parsing (brand, keywords, filters, sections).
    * Search Response Cache (medium TTL, e.g. 20 minutes): caches aggregated catalog offers and spotlight deals.
- Invalidation hooks for background price updaters and crawlers.
- Real-time telemetry: hit ratios, saved LLM tokens, and estimated monetary cost savings.
"""

import os
import re
import json
import time
import hashlib
import logging
import threading
from collections import OrderedDict
from typing import Optional, Dict, Any, Tuple
from pydantic import BaseModel

logger = logging.getLogger("fitmatch.cache")

DEFAULT_CACHE_DIR = os.path.join("data", "cache", "smart_search")

# LLM Pricing Constants for Savings Telemetry (OpenRouter Llama 3.3 70B rates)
PROMPT_COST_PER_M = 0.12     # $0.12 / 1M prompt tokens
COMPLETION_COST_PER_M = 0.30 # $0.30 / 1M completion tokens
AVG_PROMPT_TOKENS = 450
AVG_COMPLETION_TOKENS = 250
COST_PER_SAVED_QUERY = (AVG_PROMPT_TOKENS * PROMPT_COST_PER_M / 1_000_000) + (AVG_COMPLETION_TOKENS * COMPLETION_COST_PER_M / 1_000_000)


class CacheEntry:
    __slots__ = ("value", "expires_at", "created_at")

    def __init__(self, value: Any, ttl_seconds: float):
        self.value = value
        self.created_at = time.time()
        self.expires_at = self.created_at + ttl_seconds if ttl_seconds > 0 else float("inf")

    def is_expired(self) -> bool:
        return time.time() > self.expires_at


class LRUMemoryCache:
    """Thread-safe in-memory LRU cache with TTL eviction."""

    def __init__(self, max_size: int = 1000):
        self.max_size = max_size
        self._cache: OrderedDict[str, CacheEntry] = OrderedDict()
        self._lock = threading.RLock()

    def get(self, key: str) -> Optional[Any]:
        with self._lock:
            entry = self._cache.get(key)
            if not entry:
                return None
            if entry.is_expired():
                del self._cache[key]
                return None
            # Move to most-recently used position
            self._cache.move_to_end(key)
            return entry.value

    def set(self, key: str, value: Any, ttl_seconds: float) -> None:
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
            self._cache[key] = CacheEntry(value, ttl_seconds)
            # Evict oldest entry if capacity exceeded
            if len(self._cache) > self.max_size:
                self._cache.popitem(last=False)

    def delete(self, key: str) -> bool:
        with self._lock:
            if key in self._cache:
                del self._cache[key]
                return True
            return False

    def clear(self) -> None:
        with self._lock:
            self._cache.clear()

    def size(self) -> int:
        with self._lock:
            return len(self._cache)


class SearchCacheManager:
    """Enterprise-grade coordinator for Intent & Search Response caching."""

    _instance: Optional["SearchCacheManager"] = None
    _singleton_lock = threading.Lock()

    def __init__(
        self,
        cache_dir: str = DEFAULT_CACHE_DIR,
        intent_ttl: float = 86400 * 7,    # 7 days for LLM semantic parsing
        results_ttl: float = 1200.0,      # 20 minutes for live product offers
        max_memory_entries: int = 1500
    ):
        self.cache_dir = cache_dir
        self.intent_ttl = intent_ttl
        self.results_ttl = results_ttl

        self.memory_cache = LRUMemoryCache(max_size=max_memory_entries)
        self._lock = threading.RLock()

        # Telemetry metrics
        self.intent_hits = 0
        self.intent_misses = 0
        self.response_hits = 0
        self.response_misses = 0
        self.total_requests = 0

        try:
            os.makedirs(os.path.join(self.cache_dir, "intents"), exist_ok=True)
            os.makedirs(os.path.join(self.cache_dir, "responses"), exist_ok=True)
        except Exception as e:
            logger.warning(f"Could not create disk cache directory: {e}")

    @classmethod
    def get_instance(cls) -> "SearchCacheManager":
        with cls._singleton_lock:
            if cls._instance is None:
                cls._instance = SearchCacheManager()
            return cls._instance

    @staticmethod
    def normalize_query(query: str) -> str:
        """Sanitizes and normalizes user query for consistent cache lookups."""
        q = (query or "").strip().lower()
        # Collapse multiple spaces and remove noisy terminal punctuation (? ! .)
        q = re.sub(r"\s+", " ", q)
        q = re.sub(r"[?!.,;]+$", "", q).strip()
        return q

    CACHE_SCHEMA_VERSION = "v9"

    def make_intent_key(self, query: str, force_mode: Optional[str] = None) -> str:
        norm_q = self.normalize_query(query)
        mode_str = force_mode.strip().lower() if force_mode else "auto"
        return f"intent:{self.CACHE_SCHEMA_VERSION}:{norm_q}::{mode_str}"

    def make_response_key(
        self,
        query: str,
        mode: Optional[str] = None,
        max_price: Optional[float] = None,
        size: Optional[str] = None,
        category: Optional[str] = None,
        store: Optional[str] = None,
        limit: int = 35
    ) -> str:
        norm_q = self.normalize_query(query)
        params = [
            f"v={self.CACHE_SCHEMA_VERSION}",
            f"q={norm_q}",
            f"m={mode or 'auto'}",
            f"p={max_price or 'none'}",
            f"s={size or 'none'}",
            f"c={category or 'none'}",
            f"st={store or 'none'}",
            f"l={limit}"
        ]
        param_str = "&".join(params)
        h = hashlib.sha256(param_str.encode("utf-8")).hexdigest()[:16]
        return f"resp:{self.CACHE_SCHEMA_VERSION}:{norm_q}:{h}"

    # MARK: - L2 Disk Persistence Helpers

    def _disk_path(self, subfolder: str, key: str) -> str:
        key_hash = hashlib.sha256(key.encode("utf-8")).hexdigest()
        return os.path.join(self.cache_dir, subfolder, f"{key_hash}.json")

    def _read_from_disk(self, subfolder: str, key: str) -> Optional[Any]:
        path = self._disk_path(subfolder, key)
        if not os.path.exists(path):
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                payload = json.load(f)
            expires_at = payload.get("expires_at", 0)
            if time.time() > expires_at:
                try:
                    os.remove(path)
                except OSError:
                    pass
                return None
            return payload.get("data")
        except Exception as e:
            logger.debug(f"Disk cache read failed for key {key}: {e}")
            return None

    def _write_to_disk(self, subfolder: str, key: str, data: Any, ttl_seconds: float) -> None:
        path = self._disk_path(subfolder, key)
        try:
            payload = {
                "key": key,
                "created_at": time.time(),
                "expires_at": time.time() + ttl_seconds,
                "data": data
            }
            tmp_path = f"{path}.tmp.{os.getpid()}"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False)
            os.replace(tmp_path, path)
        except Exception as e:
            logger.debug(f"Disk cache write failed for key {key}: {e}")

    # MARK: - Tier 1: Intent Caching

    def get_intent(self, query: str, force_mode: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Retrieve parsed SmartSearchIntent from L1 memory or L2 disk cache."""
        self.total_requests += 1
        key = self.make_intent_key(query, force_mode)

        # 1. Check L1 Memory
        val = self.memory_cache.get(key)
        if val is not None:
            self.intent_hits += 1
            return val

        # 2. Check L2 Disk
        disk_val = self._read_from_disk("intents", key)
        if disk_val is not None:
            self.intent_hits += 1
            # Re-warm L1 memory
            self.memory_cache.set(key, disk_val, ttl_seconds=self.intent_ttl)
            return disk_val

        self.intent_misses += 1
        return None

    def set_intent(self, query: str, force_mode: Optional[str], intent_data: Any, ttl_seconds: Optional[float] = None) -> None:
        """Store parsed SmartSearchIntent into L1 memory and L2 persistent disk."""
        key = self.make_intent_key(query, force_mode)
        ttl = ttl_seconds if ttl_seconds is not None else self.intent_ttl

        # Normalize to dict if Pydantic model
        if hasattr(intent_data, "model_dump"):
            serializable = intent_data.model_dump()
        elif isinstance(intent_data, dict):
            serializable = intent_data
        else:
            return

        self.memory_cache.set(key, serializable, ttl_seconds=ttl)
        self._write_to_disk("intents", key, serializable, ttl_seconds=ttl)

    # MARK: - Tier 2: Full Response Caching

    def get_search_response(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Retrieve cached full smart search response dictionary."""
        val = self.memory_cache.get(cache_key)
        if val is not None:
            self.response_hits += 1
            return val

        disk_val = self._read_from_disk("responses", cache_key)
        if disk_val is not None:
            self.response_hits += 1
            self.memory_cache.set(cache_key, disk_val, ttl_seconds=self.results_ttl)
            return disk_val

        self.response_misses += 1
        return None

    def set_search_response(self, cache_key: str, response_data: Dict[str, Any], ttl_seconds: Optional[float] = None) -> None:
        """Store full smart search response into L1 memory and L2 disk."""
        ttl = ttl_seconds if ttl_seconds is not None else self.results_ttl
        self.memory_cache.set(cache_key, response_data, ttl_seconds=ttl)
        self._write_to_disk("responses", cache_key, response_data, ttl_seconds=ttl)

    # MARK: - Invalidation & Purging

    def invalidate_responses(self) -> int:
        """Purges cached search results and prices while preserving semantic intents."""
        with self._lock:
            # Clear responses from memory cache
            keys_to_del = [k for k in self.memory_cache._cache.keys() if k.startswith("resp:")]
            for k in keys_to_del:
                self.memory_cache.delete(k)

        # Remove from disk
        resp_dir = os.path.join(self.cache_dir, "responses")
        purged = 0
        if os.path.exists(resp_dir):
            for fname in os.listdir(resp_dir):
                if fname.endswith(".json"):
                    try:
                        os.remove(os.path.join(resp_dir, fname))
                        purged += 1
                    except OSError:
                        pass
        logger.info(f"[CacheManager] Invalidate responses: purged {purged} disk files and {len(keys_to_del)} memory entries.")
        return purged

    def clear_all(self) -> None:
        """Full purge of all in-memory and on-disk caches."""
        self.memory_cache.clear()
        for sub in ("intents", "responses"):
            folder = os.path.join(self.cache_dir, sub)
            if os.path.exists(folder):
                for fname in os.listdir(folder):
                    if fname.endswith(".json"):
                        try:
                            os.remove(os.path.join(folder, fname))
                        except OSError:
                            pass
        logger.info("[CacheManager] All caches cleared.")

    # MARK: - Telemetry & Metrics

    def get_metrics(self) -> Dict[str, Any]:
        """Provides real-time caching analytics, hit ratios, and savings calculations."""
        total_hits = self.intent_hits + self.response_hits
        total_evals = self.intent_hits + self.intent_misses + self.response_hits + self.response_misses
        hit_ratio = (total_hits / total_evals * 100.0) if total_evals > 0 else 0.0

        # Every intent hit or response hit avoids an LLM call
        saved_llm_queries = self.intent_hits + self.response_hits
        saved_tokens = saved_llm_queries * (AVG_PROMPT_TOKENS + AVG_COMPLETION_TOKENS)
        saved_usd = saved_llm_queries * COST_PER_SAVED_QUERY

        return {
            "status": "healthy",
            "memory_entries": self.memory_cache.size(),
            "telemetry": {
                "total_requests": self.total_requests,
                "overall_hit_ratio_pct": round(hit_ratio, 2),
                "intent_hits": self.intent_hits,
                "intent_misses": self.intent_misses,
                "response_hits": self.response_hits,
                "response_misses": self.response_misses,
            },
            "savings": {
                "llm_calls_saved": saved_llm_queries,
                "estimated_tokens_saved": saved_tokens,
                "estimated_usd_saved": round(saved_usd, 5),
                "estimated_eur_saved": round(saved_usd * 0.95, 5)
            },
            "ttl_config": {
                "intent_ttl_hours": self.intent_ttl / 3600.0,
                "results_ttl_minutes": self.results_ttl / 60.0
            }
        }
