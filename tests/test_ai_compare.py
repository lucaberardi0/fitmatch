import pytest
from fitmatch.ai_comparator import AIModelComparator, LOCAL_SPECS_DATABASE
from fitmatch.scrapers.sportler import SportlerScraper
from fitmatch.scrapers.registry import ScraperRegistry


def test_sportler_scraper_instantiation_and_registry():
    scraper = SportlerScraper()
    assert scraper.store_id == "sportler"
    assert scraper.store_name == "Sportler"
    assert "sportler.com" in scraper.base_url

    registry = ScraperRegistry()
    assert any(s.store_id == "sportler" for s in registry.scrapers)
    assert len(registry.scrapers) >= 10


def test_ai_model_comparator_heuristic_specs():
    comparator = AIModelComparator()
    specs_a = comparator._get_heuristic_spec("pegasus")
    specs_b = comparator._get_heuristic_spec("nimbus")

    assert "Pegasus" in specs_a.name
    assert specs_a.brand == "Nike"
    assert specs_a.drop_mm == 10
    assert specs_a.weight_g == 285

    assert "Nimbus" in specs_b.name
    assert specs_b.brand == "Asics"
    assert specs_b.drop_mm == 8


def test_ai_model_comparator_structure():
    comparator = AIModelComparator()
    specs_a, specs_b, diffs, verdict, winner_perf, source = comparator._generate_specs_and_analysis("pegasus 41", "nimbus 26")

    assert specs_a.name
    assert specs_b.name
    assert len(diffs) > 0
    assert len(verdict) > 10
    assert winner_perf
