import uuid
from fastapi.testclient import TestClient

from api import app, db, search_smart
from fitmatch.smart_search import (
    ConversationContextMerger,
    FitMatchSportsAdvisor,
    LocalHeuristicParser,
    SmartSearchEngine,
)
from fitmatch.supabase_client import SupabaseClient


client = TestClient(app)


def test_new_sports_knowledge_archetypes():
    """Verify stability/pronation, trekking/hiking, and recovery slides intent recognition."""
    # 1. Stability / Overpronation
    intent_stab = LocalHeuristicParser.parse("scarpe running antipronazione per iperpronatore")
    assert any(k in " ".join(intent_stab.target_keywords).lower() for k in ["kayano", "gt-2000", "tempos", "guide", "adrenaline", "arahi"])
    assert intent_stab.category in ("running_shoes", "shoes")
    assert intent_stab.is_deep_dive is True

    # 2. Trekking / Hiking
    intent_trek = LocalHeuristicParser.parse("scarponi trekking montagna impermeabili gore-tex")
    assert any(k in " ".join(intent_trek.target_keywords).lower() for k in ["x ultra", "moab", "terrex", "tx4", "quest", "lone peak", "speedgoat"])
    assert intent_trek.category in ("trail_running", "shoes")

    # 3. Recovery slides
    intent_rec = LocalHeuristicParser.parse("ciabatte recovery dopo corsa hoka ora")
    assert any(k in " ".join(intent_rec.target_keywords).lower() for k in ["hoka ora", "ora recovery", "reelax", "calm"])


def test_advisor_joint_rain_and_summer_handlers():
    """Verify expanded FitMatchSportsAdvisor handles joint protection, rain/Gore-Tex, and summer breathability."""
    res_joint = FitMatchSportsAdvisor.answer(
        "proteggono bene le ginocchia per un runner di 90 kg?",
        context_query="hoka bondi 8",
    )
    assert res_joint is not None
    assert "80-85 kg" in res_joint["answer"] or "shock" in res_joint["answer"].lower() or "ginocchia" in res_joint["answer"].lower()

    res_rain = FitMatchSportsAdvisor.answer(
        "vanno bene con pioggia e gore-tex?",
        context_query="salomon speedcross 6 gtx",
    )
    assert res_rain is not None
    assert "impermeab" in res_rain["answer"].lower() or "gore-tex" in res_rain["answer"].lower()

    res_summer = FitMatchSportsAdvisor.answer(
        "sono traspiranti per correre d'estate?",
        context_query="nike pegasus 41",
    )
    assert res_summer is not None
    assert "traspir" in res_summer["answer"].lower() or "mesh" in res_summer["answer"].lower()


def test_multi_turn_cumulative_context_inheritance():
    """Verify 3-turn cumulative context inheritance without losing brand, gender, or max_price."""
    engine = SmartSearchEngine()
    ctx = "scarpe nike uomo sotto 150 euro >> taglia 43"
    intent = engine.parse_query(
        "fammele vedere ammortizzate",
        context_query=ctx,
        session_context={
            "brand": "Nike",
            "gender": "Uomo",
            "max_price": 150.0,
            "size": "43",
            "category": "running_shoes",
        },
    )
    assert intent.brand == "Nike"
    assert intent.gender == "Uomo"
    assert intent.max_price == 150.0
    assert intent.size == "43"
    assert "cushioning" in " ".join(intent.features).lower()

    extracted = ConversationContextMerger.extract_cumulative_constraints(
        "asics gel nimbus donna sotto 170 euro >> taglia 39"
    )
    assert extracted["brand"] == "Asics"
    assert extracted["gender"] == "Donna"
    assert extracted["max_price"] == 170.0
    assert extracted["size"] == "39"


def test_category_equivalents_coverage():
    """Verify Supabase category equivalents map real DB categories coherently."""
    cat_eq = SupabaseClient.CATEGORY_EQUIVALENTS
    assert "trail_running" in cat_eq["shoes"]
    assert "trail_running" in cat_eq
    assert "racket" in cat_eq["padel"]
    assert "apparel" in cat_eq
    assert "hydration" in cat_eq
    assert "cycling" in cat_eq


def test_chat_persistence_api_end_to_end():
    """Verify /api/search/smart persists chat turns and /api/chats CRUD endpoints retrieve, feedback, and delete them."""
    test_device_id = f"pytest-device-{uuid.uuid4().hex[:10]}"
    test_session_id = str(uuid.uuid4())

    try:
        # Turn 1 via direct smart search with tracking IDs
        r1 = client.get(
            "/api/search/smart",
            params={
                "q": "nike pegasus 41 uomo sotto 160 euro",
                "session_id": test_session_id,
                "device_id": test_device_id,
                "limit": 8,
            },
        )
        assert r1.status_code == 200
        d1 = r1.json()
        assert d1.get("session_id") == test_session_id
        assert d1.get("turn_id") is not None

        # Turn 2 follow-up reusing session_id
        r2 = client.get(
            "/api/search/smart",
            params={
                "q": "mostramele taglia 43",
                "context_query": "nike pegasus 41 uomo sotto 160 euro",
                "session_id": test_session_id,
                "device_id": test_device_id,
                "limit": 8,
            },
        )
        assert r2.status_code == 200
        d2 = r2.json()
        assert d2.get("session_id") == test_session_id
        assert d2["intent"]["brand"] == "Nike"
        assert d2["intent"]["max_price"] == 160.0
        assert d2["intent"]["size"] == "43"

        # List sessions for device_id
        list_res = client.get("/api/chats", params={"device_id": test_device_id})
        assert list_res.status_code == 200
        sessions = list_res.json().get("sessions", [])
        assert any(s["id"] == test_session_id for s in sessions)
        matched_sess = next(s for s in sessions if s["id"] == test_session_id)
        assert matched_sess["turn_count"] >= 2

        # Fetch session detail with all ordered turns
        detail_res = client.get(f"/api/chats/{test_session_id}")
        assert detail_res.status_code == 200
        detail = detail_res.json()
        assert detail["id"] == test_session_id
        assert len(detail.get("messages", [])) >= 2
        first_msg_id = detail["messages"][0]["id"]

        # Update feedback on first turn
        fb_res = client.patch(
            f"/api/chats/{test_session_id}/messages/{first_msg_id}/feedback",
            json={"feedback": 1},
        )
        assert fb_res.status_code == 200
        assert fb_res.json().get("success") is True

        # Sync custom turn via POST /api/chats/sync
        sync_res = client.post(
            "/api/chats/sync",
            json={
                "session_id": test_session_id,
                "device_id": test_device_id,
                "chat_type": "smart_search",
                "query": "vanno bene per lunghi?",
                "is_follow_up": True,
                "response_payload": {
                    "conversational_header": "Consiglio lunghi",
                    "conversational_summary": "Ottima scelta per lunghi quotidiani.",
                    "results": [],
                },
            },
        )
        assert sync_res.status_code == 200
        assert sync_res.json().get("session_id") == test_session_id

        # Also check direct Python call compatibility with omitted optional Query defaults
        direct_out = search_smart(q="garmin forerunner 165", limit=5)
        assert direct_out["total_found"] >= 0
    finally:
        # Clean up test session from Supabase & SQLite
        del_res = client.delete(f"/api/chats/{test_session_id}", params={"device_id": test_device_id})
        assert del_res.status_code == 200
        after_del = client.get(f"/api/chats/{test_session_id}")
        assert after_del.status_code == 404
