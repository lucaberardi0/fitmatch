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
