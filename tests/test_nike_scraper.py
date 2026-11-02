import pytest
from fitmatch.scrapers.nike import NikeScraper
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.models import STORE_SHIPPING_RULES


def test_nike_scraper_instantiation_and_registry():
    scraper = NikeScraper()
    assert scraper.store_id == "nike"
    assert scraper.store_name == "Nike"
    assert "nike.com/it" in scraper.base_url

    registry = ScraperRegistry()
    assert any(s.store_id == "nike" for s in registry.scrapers)
    assert len(registry.scrapers) == 11


def test_nike_shipping_rules():
    assert "nike" in STORE_SHIPPING_RULES
    rule = STORE_SHIPPING_RULES["nike"]
    assert rule["standard"] == 5.00
    assert rule["free_threshold"] == 99.0
    assert "courier" in rule


def test_nike_search_live_and_sizes():
    scraper = NikeScraper()
    offers = scraper.search("Pegasus", limit=3)
    assert isinstance(offers, list)
    assert len(offers) > 0

    first = offers[0]
    assert first.store_id == "nike"
    assert first.store_name == "Nike"
    assert first.brand == "Nike"
    assert first.price > 0
    assert "nike.com" in first.url
    assert first.in_stock is True

    # Test size extraction
    sizes = scraper.fetch_sizes(first.url)
    assert isinstance(sizes, list)
    assert len(sizes) > 0
