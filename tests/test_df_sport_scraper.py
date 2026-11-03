import pytest
from fitmatch.scrapers.df_sport import DFSportScraper
from fitmatch.scrapers.registry import ScraperRegistry
from fitmatch.models import STORE_SHIPPING_RULES


def test_df_sport_scraper_instantiation_and_registry():
    scraper = DFSportScraper()
    assert scraper.store_id == "df_sportspecialist"
    assert scraper.store_name == "DF Sport Specialist"
    assert "df-sportspecialist.it" in scraper.base_url

    registry = ScraperRegistry()
    assert any(s.store_id == "df_sportspecialist" for s in registry.scrapers)
    assert len(registry.scrapers) >= 14


def test_df_sport_shipping_rules():
    assert "df_sportspecialist" in STORE_SHIPPING_RULES
    rule = STORE_SHIPPING_RULES["df_sportspecialist"]
    assert rule["standard"] == 5.90
    assert rule["free_threshold"] == 60.0
    assert "courier" in rule


def test_df_sport_search_and_sizes():
    scraper = DFSportScraper()
    offers = scraper.search("nike pegasus", limit=3)
    assert isinstance(offers, list)
    assert len(offers) > 0

    first = offers[0]
    assert first.store_id == "df_sportspecialist"
    assert first.store_name == "DF Sport Specialist"
    assert first.price > 0
    assert "df-sportspecialist.it" in first.url
    assert first.image_url is not None

    # Test size extraction
    sizes = scraper.fetch_sizes(first.url)
    assert isinstance(sizes, list)
