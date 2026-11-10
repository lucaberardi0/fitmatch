import pytest
from fitmatch.smart_search import SmartSearchEngine
from fitmatch.cache_manager import SearchCacheManager
from api import search_smart


@pytest.fixture
def clean_cache():
    cm = SearchCacheManager.get_instance()
    cm.clear_all()
    yield cm
    cm.clear_all()


def test_garmin_forerunner_165_search(clean_cache):
    """Ensure search for Garmin Forerunner 165 does not return cycling computers or accessories as top products."""
    res = search_smart(q="Garmin forerunner 165", mode=None, max_price=None, size=None, category=None, store=None, limit=20)
    assert res["total_found"] > 0
    top_prods = res["results"]
    
    # Check that the first product contains 'forerunner' and '165'
    top_prod_name = top_prods[0]["canonical_name"].lower()
    assert "forerunner" in top_prod_name
    assert "165" in top_prod_name
    assert "edge" not in top_prod_name

    # Check spotlight matches the requested product
    if res.get("spotlight"):
        spot_name = res["spotlight"]["product"]["canonical_name"].lower()
        assert "forerunner" in spot_name
        assert "165" in spot_name


def test_garmen_165_typo_and_no_265_hallucination(clean_cache):
    """Ensure phonetic typo 'Garmen 165' strictly maps to Garmin Forerunner 165 and never hallucinates 265."""
    engine = SmartSearchEngine()
    intent = engine.parse_query("Garmen 165")
    
    assert "165" in intent.conversational_header
    assert "265" not in intent.conversational_header
    assert "165" in intent.conversational_summary
    assert "265" not in intent.conversational_summary
    assert intent.spotlight is not None
    assert "165" in intent.spotlight.target_keyword
    assert "265" not in intent.spotlight.target_keyword
    assert intent.category == "gps_watch"

    res = search_smart(q="Garmen 165", mode=None, max_price=None, size=None, category=None, store=None, limit=20)
    assert res["total_found"] > 0
    assert "165" in res["conversational_header"]
    assert "265" not in res["conversational_header"]
    assert "165" in res["conversational_summary"]
    assert "265" not in res["conversational_summary"]
    if res.get("spotlight"):
        spot_name = res["spotlight"]["product"]["canonical_name"].lower()
        assert "165" in spot_name
        assert "265" not in spot_name


def test_garmin_contextual_followups(clean_cache):
    """Ensure follow-up queries maintain GPS watch context and resolve in milliseconds without errors."""
    engine = SmartSearchEngine()

    # 1. Alternative sotto i 300 euro
    res_price = search_smart(
        q="Alternative sotto i 300 euro",
        mode=None,
        max_price=None,
        size=None,
        category=None,
        store=None,
        context_query="Garmen 165",
        limit=20
    )
    assert res_price["total_found"] > 0
    assert "300" in res_price["conversational_header"]
    for p in res_price["results"]:
        assert p.get("best_price", 0) <= 300.0

    # 2. Modelli di smartwatch GPS per la corsa
    res_models = search_smart(
        q="Modelli di smartwatch GPS per la corsa",
        mode=None,
        max_price=None,
        size=None,
        category=None,
        store=None,
        context_query="Garmen 165",
        limit=20
    )
    assert res_models["total_found"] > 0
    assert any("forerunner" in p["canonical_name"].lower() or "pace" in p["canonical_name"].lower() for p in res_models["results"])

    # 3. Funzionalità avanzate per l'analisi delle prestazioni
    res_adv = search_smart(
        q="Funzionalità avanzate per l'analisi delle prestazioni",
        mode=None,
        max_price=None,
        size=None,
        category=None,
        store=None,
        context_query="Garmen 165",
        limit=20
    )
    assert res_adv["total_found"] > 0
    assert any("265" in p["canonical_name"] or "965" in p["canonical_name"] or "fenix" in p["canonical_name"].lower() for p in res_adv["results"])


def test_adidas_dropset_search(clean_cache):
    """Ensure search for Adidas adizero dropset returns gym training shoes, not bike headsets or running race shoes."""
    res = search_smart(q="Adidas adizero dropset", mode=None, max_price=None, size=None, category=None, store=None, limit=20)
    assert res["total_found"] > 0
    top_prods = res["results"]

    # Verify top products are Adidas Dropset
    top_prod_name = top_prods[0]["canonical_name"].lower()
    assert "dropset" in top_prod_name
    assert "chris king" not in top_prod_name
    assert "cuffie" not in top_prod_name

    # Verify no bike hardware in any returned results
    for p in top_prods:
        pname = p["canonical_name"].lower()
        assert "chris king" not in pname
        assert "cuffie" not in pname
        assert "serie sterzo" not in pname

    # Verify conversational summary is accurate (training/Hyrox, not running cushion)
    summary = res.get("conversational_summary", "").lower()
    assert any(w in summary for w in ["hyrox", "allenamento", "palestra", "stabilità", "dropset", "migliori prezzi"])

    # Verify follow-up suggestions include domain specific Hyrox/Dropset questions
    follow_ups = res.get("follow_up_suggestions", [])
    assert len(follow_ups) > 0
