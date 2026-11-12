import pytest
from fastapi.testclient import TestClient
from api import app, cache_manager
from fitmatch.smart_search import FitMatchSportsAdvisor, SmartSearchEngine


@pytest.fixture(autouse=True)
def clean_cache():
    cache_manager.clear_all()


def test_fitmatch_sports_advisor_detection():
    # Advisory and informational athletic questions
    assert FitMatchSportsAdvisor.is_conversational_query("sono buone per mezza maratona?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("vanno bene per pronatori?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("come calzano?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("quanto durano?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("qual è la differenza con le vaporfly?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("hanno la piastra in carbonio?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("che drop hanno?", has_context=True)
    assert FitMatchSportsAdvisor.is_conversational_query("per che passo sono adatte?", has_context=True)

    # Plain shopping search commands or product filters should NOT be conversational advice
    assert not FitMatchSportsAdvisor.is_conversational_query("mostrami la versione nera", has_context=True)
    assert not FitMatchSportsAdvisor.is_conversational_query("sotto i 100 euro", has_context=True)
    assert not FitMatchSportsAdvisor.is_conversational_query("in taglia 43", has_context=True)
    assert not FitMatchSportsAdvisor.is_conversational_query("scarpe running ammortizzate", has_context=False)


def test_smart_search_conversational_advice_half_marathon():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "sono buone per mezza maratona?",
        "context_query": "Nike zoom fly 6"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is True
    assert "Nike Zoom Fly 6" in data.get("conversational_header", "")
    summary = data.get("conversational_summary", "").lower()
    assert "mezza maratona" in summary
    assert "zoomx" in summary or "carbonio" in summary
    assert len(data.get("follow_up_suggestions", [])) == 3


def test_smart_search_conversational_advice_pronation():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "vanno bene per pronatori?",
        "context_query": "Nike zoom fly 6"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is True
    summary = data.get("conversational_summary", "").lower()
    assert "neutro" in summary or "supporto" in summary


def test_smart_search_conversational_advice_vaporfly_diff():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "qual è la differenza con le vaporfly?",
        "context_query": "Nike zoom fly 6"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is True
    summary = data.get("conversational_summary", "").lower()
    assert "vaporfly" in summary


def test_smart_search_conversational_advice_shorts_comfort():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "Sono comodi?",
        "context_query": "Shorts di under armour"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is True
    assert "Shorts Under Armour" in data.get("conversational_header", "")
    summary = data.get("conversational_summary", "").lower()
    assert "comfort" in summary or "traspirabilità" in summary or "heatgear" in summary
    assert len(data.get("follow_up_suggestions", [])) == 3


def test_smart_search_conversational_advice_shorts_pockets():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "Hanno le tasche per il telefono?",
        "context_query": "Shorts di under armour"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") is True
    summary = data.get("conversational_summary", "").lower()
    assert "tasca" in summary or "smartphone" in summary


def test_catalog_refinement_still_runs_search():
    client = TestClient(app)
    resp = client.get("/api/search/smart", params={
        "q": "in taglia 43",
        "context_query": "Nike zoom fly 6"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("is_conversational_advice") in (False, None)
