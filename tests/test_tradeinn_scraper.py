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
    assert rule["free_threshold"] is None
    assert "courier" in rule


def test_tradeinn_dc_payload_extracts_rrp_sizes_and_stock():
    scraper = TradeinnScraper()
    payload = {
        "_source": {
            "precio_win_98": "103.49",
            "productes": [
                {
                    "talla": "EU 43",
                    "rec": "139.99",
                    "baja": "0",
                    "exist": "4",
                    "stock_disponible": 4,
                    "stock_reservat": 0,
                    "stock_volcado": "0",
                    "sellers": [{"id_seller": 1, "stock": "4", "stock_de": 0, "precios_paises": [{"id_pais": 98, "precio": 103.49}]}],
                },
                {
                    "talla": "EU 44 1/2",
                    "rec": "139.99",
                    "baja": "0",
                    "exist": "0",
                    "stock_disponible": 0,
                    "stock_reservat": 0,
                    "stock_volcado": "12",
                    "sellers": [{"id_seller": 1, "stock": "12", "stock_de": 0, "precios_paises": [{"id_pais": 98, "precio": 103.49}]}],
                },
                {
                    "talla": "EU 40",
                    "rec": "139.99",
                    "baja": "1",
                    "exist": "0",
                    "stock_disponible": 0,
                    "stock_reservat": 0,
                    "stock_volcado": "0",
                    "sellers": [],
                },
            ],
        }
    }

    parsed = scraper.parse_dc_payload(
        payload,
        fallback_price=105.0,
        title="Nike Scarpe da running Pegasus 41",
        product_url="https://www.tradeinn.com/runnerinn/it/nike-pegasus-41/143119794/p",
    )
    assert parsed["dc_ok"] is True
    assert parsed["price"] == 103.49
    assert parsed["original_price"] == 139.99
    assert parsed["in_stock"] is True
    assert "43" in parsed["sizes"]
    assert "44.5" in parsed["sizes"]
    assert "40" not in parsed["sizes"]


def test_tradeinn_dc_payload_guards_sentinel_and_tiny_discounts():
    scraper = TradeinnScraper()

    # 99968 / 99999 sentinel must NOT produce fake original_price
    sentinel_payload = {
        "_source": {
            "precio_win_98": "89.99",
            "productes": [{"talla": "EU 42", "rec": "99999.00", "baja": "0", "stock_disponible": 3, "sellers": []}],
        }
    }
    res_sentinel = scraper.parse_dc_payload(sentinel_payload, fallback_price=89.99, title="Asics Novablast")
    assert res_sentinel["original_price"] is None

    # Discount < 5% should not set original_price (matches Tradeinn frontend rule)
    tiny_disc_payload = {
        "_source": {
            "precio_win_98": "147.00",
            "productes": [{"talla": "EU 42", "rec": "150.00", "baja": "0", "stock_disponible": 3, "sellers": []}],
        }
    }
    res_tiny = scraper.parse_dc_payload(tiny_disc_payload, fallback_price=147.00, title="Asics Novablast")
    assert res_tiny["original_price"] is None


def test_tradeinn_search_running_and_padel():
    scraper = TradeinnScraper()

    # Running query
    offers = scraper.search("nike pegasus", limit=4)
    assert isinstance(offers, list)
    assert len(offers) > 0

    first = offers[0]
    assert first.store_id == "tradeinn"
    assert first.store_name == "Tradeinn"
    assert first.price > 0
    assert "tradeinn.com" in first.url
    assert first.image_url is not None
    # Verify any extracted original_price is strictly valid (> price and >= 5% discount)
    for o in offers:
        if o.original_price is not None:
            assert o.original_price > o.price
            assert (o.discount_pct or 0) >= 5.0

    # Padel query
    padel_offers = scraper.search("bullpadel hack", limit=3)
    assert isinstance(padel_offers, list)
    assert len(padel_offers) > 0
    assert any("bullpadel" in o.title.lower() for o in padel_offers)
