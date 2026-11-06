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
    assert "hyrox" in summary or "allenamento" in summary or "palestra" in summary or "stabilità" in summary

    # Verify follow-up suggestions include domain specific Hyrox/Dropset questions
    follow_ups = res.get("follow_up_suggestions", [])
    assert any("hyrox" in f.lower() or "dropset" in f.lower() for f in follow_ups)
