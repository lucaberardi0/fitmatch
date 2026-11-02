import pytest
from fitmatch.scrapers.adidas import AdidasScraper
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.models import STORE_SHIPPING_RULES


def test_adidas_scraper_instantiation_and_registry():
    scraper = AdidasScraper()
    assert scraper.store_id == "adidas"
    assert scraper.store_name == "Adidas"
    assert "adidas.it" in scraper.base_url

    registry = ScraperRegistry()
    assert any(s.store_id == "adidas" for s in registry.scrapers)
    assert len(registry.scrapers) >= 12


def test_adidas_shipping_rules():
    assert "adidas" in STORE_SHIPPING_RULES
    rule = STORE_SHIPPING_RULES["adidas"]
    assert rule["standard"] == 4.99
    assert rule["free_threshold"] == 50.0
    assert "courier" in rule


def test_adidas_search_live():
    scraper = AdidasScraper()
    offers = scraper.search("Adizero", limit=3)
    assert isinstance(offers, list)
    assert len(offers) > 0

    first = offers[0]
    assert first.store_id == "adidas"
    assert first.store_name == "Adidas"
    assert first.brand == "Adidas"
    assert first.price > 0
    assert "adidas.it" in first.url
    assert isinstance(first.in_stock, bool)
