import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fitmatch.smart_search import (
    QueryProductGuardrail,
    FitMatchSportsAdvisor,
    SmartSearchEngine,
    LocalHeuristicParser,
)


def test_football_boots_query_blocks_jerseys_and_running_shoes():
    ptype = QueryProductGuardrail.detect_product_type("Scarpini calcio a 7")
    assert ptype == "football_boots"

    jersey = {
        "id": "p_jersey",
        "canonical_name": "Adidas Maglia Calcio Juventus",
        "brand": "Adidas",
        "category": "top",
        "best_price": 74.99,
        "offers": [{"raw_title": "Adidas Maglia Calcio Home 25/26"}],
    }
    boot = {
        "id": "p_boot",
        "canonical_name": "Adidas Predator League AG",
        "brand": "Adidas",
        "category": "football_boots",
        "best_price": 69.99,
        "offers": [{"raw_title": "Adidas Predator League AG Scarpe da Calcio"}],
    }
    running = {
        "id": "p_run",
        "canonical_name": "Nike Pegasus 41",
        "brand": "Nike",
        "category": "running_shoes",
        "best_price": 109.99,
        "offers": [{"raw_title": "Nike Air Zoom Pegasus 41"}],
    }

    assert QueryProductGuardrail.is_product_compatible(jersey, ptype, raw_query="Scarpini calcio a 7") is False
    assert QueryProductGuardrail.is_product_compatible(running, ptype, raw_query="Scarpini calcio a 7") is False
    assert QueryProductGuardrail.is_product_compatible(boot, ptype, raw_query="Scarpini calcio a 7") is True


def test_swim_goggles_query_blocks_socks_moto_armor_and_running_shoes():
    ptype = QueryProductGuardrail.detect_product_type("Occhialini per iniziare a nuotare")
    assert ptype == "swim"

    socks = {
        "id": "p_socks",
        "canonical_name": "Diadora Ghost 3Pack",
        "brand": "Diadora",
        "category": "socks",
        "best_price": 4.99,
        "offers": [{"raw_title": "Diadora Ghost 3Pack Calzini"}],
    }
    moto = {
        "id": "p_moto",
        "canonical_name": "Brooks Furygan Protezioni Gomiti Ginocchia D3O Ghost",
        "brand": "Brooks",
        "category": "non_sport",
        "best_price": 21.99,
        "offers": [{"raw_title": "Furygan Protezioni Gomiti Ginocchia D3O Ghost"}],
    }
    running = {
        "id": "p_peg",
        "canonical_name": "Nike Pegasus 41",
        "brand": "Nike",
        "category": "running_shoes",
        "best_price": 99.00,
        "offers": [{"raw_title": "Nike Pegasus 41"}],
    }
    sunglasses = {
        "id": "p_oak",
        "canonical_name": "Oakley Sutro Lite",
        "brand": "Oakley",
        "category": "eyewear",
        "best_price": 129.00,
        "offers": [{"raw_title": "Oakley Sutro Lite Occhiali Sole"}],
    }
    goggles = {
        "id": "p_gogg",
        "canonical_name": "Speedo Biofuse 2.0",
        "brand": "Speedo",
        "category": "swim",
        "best_price": 19.99,
        "offers": [{"raw_title": "Speedo Occhialini Nuoto Biofuse 2.0"}],
    }

    q = "Occhialini per iniziare a nuotare"
    assert QueryProductGuardrail.is_product_compatible(socks, ptype, raw_query=q) is False
    assert QueryProductGuardrail.is_product_compatible(moto, ptype, raw_query=q) is False
    assert QueryProductGuardrail.is_product_compatible(running, ptype, raw_query=q) is False
    assert QueryProductGuardrail.is_product_compatible(sunglasses, ptype, raw_query=q) is False
    assert QueryProductGuardrail.is_product_compatible(goggles, ptype, raw_query=q) is True

    intent = LocalHeuristicParser.parse(q)
    assert intent.category == "swim"
    assert "daily trainer" not in intent.conversational_summary.lower()


def test_open_beginner_running_discovery_does_not_hit_canned_single_model_advisor():
    q = "Cosa mi consigli come scarpe per iniziare a correre?"
    assert FitMatchSportsAdvisor.is_conversational_query(q, has_context=False) is False
    assert SmartSearchEngine.is_complex_natural_query(q) is True


def test_more_examples_followup_inherits_context_and_avoids_literal_word_search():
    q = "Fammi vedere più esempi"
    assert SmartSearchEngine.is_more_examples_query(q) is True

    engine = SmartSearchEngine(api_key="")
    intent = engine.parse_query(
        q,
        context_query="Cosa mi consigli come scarpe per iniziare a correre?",
        session_context={
            "last_search_query": "Cosa mi consigli come scarpe per iniziare a correre?",
            "last_keywords": ["nike pegasus", "asics novablast", "brooks ghost"],
            "category": "running_shoes",
            "shown_ids": ["id1", "id2", "id3"],
        },
    )
    joined_kws = " ".join(intent.target_keywords).lower()
    assert "fammi" not in joined_kws
    assert "vedere" not in joined_kws
    assert "esempi" not in joined_kws
    assert intent.category == "running_shoes"
    assert "Fammi vedere" not in intent.conversational_header or "Altri esempi" in intent.conversational_header


def test_non_sport_junk_always_blocked():
    vetus = {
        "id": "p_vetus",
        "canonical_name": "Vetus Modelli Più Vecchi Altus",
        "brand": "Vetus",
        "category": "gear",
        "best_price": 23.99,
        "offers": [{"raw_title": "Vetus Modelli Più Vecchi Altus Nautica"}],
    }
    crank = {
        "id": "p_crank",
        "canonical_name": "Crankbrothers Stamp Lace",
        "brand": "Crankbrothers",
        "category": "cycling",
        "best_price": 119.00,
        "offers": [{"raw_title": "Crankbrothers Scarpe MTB"}],
    }
    assert QueryProductGuardrail.is_product_compatible(vetus, "shoes", raw_query="scarpe per correre") is False
    assert QueryProductGuardrail.is_product_compatible(crank, "shoes", raw_query="scarpe per correre") is False


def test_followup_category_switch_watch_to_shoes_does_not_leak_garmin():
    q = "Mentre delle scarpe da corsa sempre per iniziare?"
    ctx = "Orologio da corsa per iniziare"

    assert FitMatchSportsAdvisor.is_conversational_query(q, has_context=True) is False
    assert QueryProductGuardrail.detect_product_type(q, ctx) == "shoes"
    assert QueryProductGuardrail.is_category_switch(q, context_query=ctx) is True

    sub, _, arch, brand = FitMatchSportsAdvisor.extract_subject(q, ctx)
    assert "forerunner" not in sub.lower()
    assert arch != "gps_watch"
    assert brand != "Garmin"

    engine = SmartSearchEngine(api_key="")
    intent = engine.parse_query(q, context_query=ctx)
    assert intent.is_conversational_advice is False
    assert intent.category == "running_shoes"
    assert intent.brand is None
    joined_kws = " ".join(intent.target_keywords).lower()
    assert "forerunner" not in joined_kws
    assert "garmin" not in joined_kws
    assert "mentre" not in joined_kws
    assert "forerunner" not in intent.conversational_header.lower()
    assert "forerunner" not in intent.conversational_summary.lower()


def test_followup_category_switch_across_multiple_categories_and_turns():
    engine = SmartSearchEngine(api_key="")

    # 1. Garmin watch with price -> shoes (do not inherit Garmin, 165, or watch budget)
    i_shoes = engine.parse_query(
        "Mentre delle scarpe da corsa?",
        context_query="Garmin Forerunner 165 sotto 300 euro",
        session_context={"brand": "Garmin", "category": "gps_watch", "max_price": 300.0},
    )
    assert i_shoes.category == "running_shoes"
    assert i_shoes.brand is None
    assert i_shoes.max_price is None
    assert all("forerunner" not in kw.lower() for kw in i_shoes.target_keywords)

    # 2. Shorts -> Garmin watch
    i_watch = engine.parse_query(
        "Mentre un orologio Garmin per iniziare?",
        context_query="Shorts di under armour",
        session_context={"brand": "Under Armour", "category": "pants"},
    )
    assert i_watch.category == "gps_watch"
    assert i_watch.brand == "Garmin"
    assert i_watch.is_conversational_advice is False

    # 3. Apparel with clothing size M -> trail shoes (do not inherit size M or brand Nike)
    i_trail = engine.parse_query(
        "E delle scarpe da trail?",
        context_query="Maglia Nike uomo taglia M",
        session_context={"brand": "Nike", "category": "top", "gender": "Uomo", "size": "M"},
    )
    assert i_trail.category == "trail_running"
    assert i_trail.brand is None
    assert i_trail.size is None
    assert i_trail.gender == "Uomo"

    # 4. Turn 3 refinement after a category switch ("Watch >> Shoes >> sotto i 120 euro")
    ctx_3 = "Orologio da corsa per iniziare >> Mentre delle scarpe da corsa sempre per iniziare?"
    assert QueryProductGuardrail.detect_product_type("Sotto i 120 euro", ctx_3) == "shoes"
    i_turn3 = engine.parse_query("Sotto i 120 euro", context_query=ctx_3)
    assert i_turn3.category == "running_shoes"
    assert i_turn3.max_price == 120.0
    assert i_turn3.brand is None


def test_smart_search_api_watch_to_shoes_followup():
    from fastapi.testclient import TestClient
    from api import app, cache_manager

    cache_manager.clear_all()
    client = TestClient(app)
    resp = client.get(
        "/api/search/smart",
        params={
            "q": "Mentre delle scarpe da corsa sempre per iniziare?",
            "context_query": "Orologio da corsa per iniziare",
            "limit": 10,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is False
    assert "forerunner" not in (data.get("conversational_header") or "").lower()
    assert "forerunner" not in (data.get("conversational_summary") or "").lower()
    assert (data.get("intent") or {}).get("category") in ("running_shoes", "shoes")
    for p in data.get("results") or []:
        assert (p.get("category") or "").lower() != "gps_watch"


def test_smart_search_stream_sse_emits_real_steps_and_result():
    import json
    from fastapi.testclient import TestClient
    from api import app, cache_manager

    cache_manager.clear_all()
    client = TestClient(app)
    events = []
    with client.stream(
        "GET",
        "/api/search/smart/stream",
        params={"q": "Scarpe da corsa Nike sotto 150 euro", "limit": 8},
    ) as resp:
        assert resp.status_code == 200
        assert "text/event-stream" in resp.headers.get("content-type", "")
        for raw_line in resp.iter_lines():
            line = raw_line.decode("utf-8") if isinstance(raw_line, bytes) else raw_line
            if not line or not line.startswith("data: "):
                continue
            events.append(json.loads(line[len("data: "):]))

    step_events = [e for e in events if e.get("type") == "step"]
    result_events = [e for e in events if e.get("type") == "result"]
    assert len(step_events) >= 2
    assert any(e.get("id") == "parse" and e.get("status") == "done" for e in step_events)
    assert any(e.get("id") == "catalog" and e.get("status") == "done" for e in step_events)
    assert len(result_events) == 1
    payload = result_events[0]["data"]
    assert payload.get("intent", {}).get("brand") == "Nike"
    assert isinstance(payload.get("results"), list)
