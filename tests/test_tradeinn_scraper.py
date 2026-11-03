import pytest
from fitmatch.scrapers.tradeinn import TradeinnScraper
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.models import STORE_SHIPPING_RULES


def test_tradeinn_scraper_instantiation_and_registry():
    scraper = TradeinnScraper()
    assert scraper.store_id == "tradeinn"
    assert scraper.store_name == "Tradeinn"
    assert "tradeinn.com" in scraper.base_url

    registry = ScraperRegistry()
    assert any(s.store_id == "tradeinn" for s in registry.scrapers)
    assert len(registry.scrapers) >= 14


def test_tradeinn_shipping_rules():
    assert "tradeinn" in STORE_SHIPPING_RULES
    rule = STORE_SHIPPING_RULES["tradeinn"]
    assert rule["standard"] == 4.99
    assert rule["free_threshold"] == 150.0
    assert "courier" in rule


def test_tradeinn_search_running_and_padel():
    scraper = TradeinnScraper()

    # Running query
    offers = scraper.search("nike pegasus", limit=3)
    assert isinstance(offers, list)
    assert len(offers) > 0

    first = offers[0]
    assert first.store_id == "tradeinn"
    assert first.store_name == "Tradeinn"
    assert first.price > 0
    assert "tradeinn.com" in first.url
    assert first.image_url is not None

    # Padel query
    padel_offers = scraper.search("bullpadel hack", limit=3)
    assert isinstance(padel_offers, list)
    assert len(padel_offers) > 0
    assert any("bullpadel" in o.title.lower() for o in padel_offers)
