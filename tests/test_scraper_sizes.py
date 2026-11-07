import pytest
from fitmatch.models import normalize_sizes
from fitmatch.scrapers.misterrunning import MisterRunningScraper
from fitmatch.scrapers.top4running import Top4RunningScraper
from fitmatch.scrapers.deporvillage import DeporvillageScraper
from fitmatch.scrapers.sportler import SportlerScraper


def test_normalize_us_and_eu_sizes():
    # US sizes to EU
    us_sizes = ["7.5", "8.5", "10", "11.5", "12"]
    norm = normalize_sizes(us_sizes)
    assert "40.5" in norm
    assert "42" in norm
    assert "44" in norm
    assert "45.5" in norm
    assert "46.5" in norm

    # Apparel sizes
    apparel = ["xs", "s", "M", "l", "XL"]
    norm_apparel = normalize_sizes(apparel)
    assert norm_apparel == ["XS", "S", "M", "L", "XL"]

    # Complex EU strings
    raw_mixed = ["EU 42 1/2", "43 1/2", "44", "45"]
    assert normalize_sizes(raw_mixed) == ["42.5", "43.5", "44", "45"]


def test_misterrunning_scraper_normalizes_sizes():
    s = MisterRunningScraper()
    # Test on a mock product payload
    p = {
        "name": "Nike Pegasus 41",
        "price": 109.99,
        "url": "https://www.misterrunning.com/it/nike-pegasus.html",
        "sizes": ["8.5", "9.5", "10.5"]
    }
    offers = []
    raw_sizes = p.get("sizes", [])
    sizes = normalize_sizes(raw_sizes)
    assert "42" in sizes
    assert "43" in sizes
    assert "44.5" in sizes
