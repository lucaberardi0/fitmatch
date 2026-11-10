import pytest
from fitmatch.models import normalize_sizes
from fitmatch.scrapers.misterrunning import MisterRunningScraper
from fitmatch.scrapers.top4running import Top4RunningScraper
from fitmatch.scrapers.deporvillage import DeporvillageScraper
from fitmatch.scrapers.sportler import SportlerScraper
from fitmatch.scrapers.adidas import AdidasScraper
from fitmatch.scrapers.alltricks import AlltricksScraper
from fitmatch.scrapers.tradeinn import TradeinnScraper
from fitmatch.scrapers.nencini import NenciniSportScraper
from unittest.mock import patch, MagicMock


def test_normalize_us_and_eu_sizes():
    # US sizes to EU
    us_sizes = ["7.5", "8.5", "10", "11.5", "12", "12.5"]
    norm = normalize_sizes(us_sizes)
    assert "40.5" in norm
    assert "42" in norm
    assert "44" in norm
    assert "45.5" in norm
    assert "46" in norm
    assert "46.5" in norm

    # Apparel sizes
    apparel = ["xs", "s", "M", "l", "XL"]
    norm_apparel = normalize_sizes(apparel)
    assert norm_apparel == ["XS", "S", "M", "L", "XL"]

    # Complex EU strings
    raw_mixed = ["EU 42 1/2", "43 1/2", "44", "45"]
    assert normalize_sizes(raw_mixed) == ["42.5", "43.5", "44", "45"]


def test_normalize_rejects_placeholders_and_dimensions():
    # Test that non-size items and store placeholders are rejected completely
    invalid_samples = [
        "Scegliere l'articolo",
        "Vedere le taglie",
        "Senza taglia",
        "NO SIZE",
        "Taille_textile",
        "Options pièces roues",
        "Dimensions roulement",
        "Prizm Dark Golf/CAT2",
        "10x28x8mm",
        "12x32x10mm",
        "32 trous",
        "nd_12",
        "Seleziona la taglia",
        "Guida alle taglie",
        "Esaurito",
        "Non disponibile",
        "10-12 Years",
        "10 anni / 140 cm"
    ]
    for sample in invalid_samples:
        assert normalize_sizes([sample]) == [], f"Failed to reject: {sample}"


def test_normalize_fractions_and_dual_formats():
    # Test Adidas/Salomon 1/3 and 2/3 fraction conversions
    assert normalize_sizes(["42 2/3"]) == ["42.5"]
    assert normalize_sizes(["43 1/3"]) == ["43.5"]
    assert normalize_sizes(["41.1/3"]) == ["41.5"]
    assert normalize_sizes(["40.2/3"]) == ["40.5"]
    assert normalize_sizes(["46 2/3"]) == ["46.5"]

    # Dual UK/EU formats
    assert normalize_sizes(["10 UK - 44.5"]) == ["44.5"]
    assert normalize_sizes(["7.5 UK - 41.5"]) == ["41.5"]
    assert normalize_sizes(["46 (UK 11)"]) == ["46"]


def test_adidas_never_invents_fake_sizes():
    s = AdidasScraper()
    # Scraper must return [] when product sizes cannot be verified
    sizes = s.fetch_sizes("https://www.adidas.it/scarpe-adizero/IG6439.html", title="Adizero Adios Pro 3")
    assert sizes == []
    # Verify infer_standard_sizes is completely removed
    assert not hasattr(s, "infer_standard_sizes")


def test_alltricks_excludes_out_of_stock_sizes():
    s = AlltricksScraper()
    mock_html = """
    <select name="product_id">
        <option value="">Taglia</option>
        <option value="1" data-label="40" data-stock-label="Stock esaurito">40</option>
        <option value="2" data-label="41" data-stock-label="In magazzino">41</option>
        <option value="3" data-label="42" data-stock-label="In magazzino">42</option>
        <option value="4" data-label="43" data-stock-label="Stock esaurito">43</option>
        <option value="5" data-label="44" data-stock-label="è l'ultimo, fai presto !">44</option>
    </select>
    """
    with patch.object(s, "_fetch_html", return_value=mock_html):
        sizes = s.fetch_sizes("https://www.alltricks.it/mock-url")
        assert sizes == ["41", "42", "44"]
        assert "40" not in sizes
        assert "43" not in sizes


def test_tradeinn_only_returns_in_stock_variants():
    s = TradeinnScraper()
    mock_html = """
    {
        "hasVariant": [
            {
                "size": "EU 42",
                "offers": { "availability": "https://schema.org/InStock" }
            },
            {
                "size": "EU 43",
                "offers": { "availability": "https://schema.org/OutOfStock" }
            },
            {
                "size": "EU 44",
                "offers": { "availability": "https://schema.org/InStock" }
            }
        ]
    }
    """
    with patch.object(s, "_fetch_html", return_value=mock_html):
        sizes = s.fetch_sizes("https://www.tradeinn.com/mock-url")
        assert sizes == ["42", "44"]
        assert "43" not in sizes

    # When all variants are out of stock, it must return []
    mock_all_oos = """
    {
        "hasVariant": [
            { "size": "EU 42", "offers": { "availability": "https://schema.org/OutOfStock" } },
            { "size": "EU 44", "offers": { "availability": "https://schema.org/OutOfStock" } }
        ]
    }
    """
    with patch.object(s, "_fetch_html", return_value=mock_all_oos):
        sizes = s.fetch_sizes("https://www.tradeinn.com/mock-url")
        assert sizes == []


def test_sportler_excludes_disabled_options():
    s = SportlerScraper()
    mock_html = """
    <select id="filterorig_size">
        <option value="">Seleziona la taglia</option>
        <option value="41" disabled>41 EU</option>
        <option value="42">42 EU</option>
        <option value="43" class="disabled">43 EU</option>
        <option value="44">44 EU</option>
    </select>
    """
    sizes = s.fetch_sizes("https://www.sportler.com/mock-url", html=mock_html)
    assert sizes == ["42", "44"]
    assert "41" not in sizes
    assert "43" not in sizes


def test_nencini_parses_stock_and_eu_map():
    s = NenciniSportScraper()
    mock_html = """
    <script>
    window.tipiTaglia = {
        "EU": [
            {"attributi_dettaglio_ID": 101, "descr": "42"},
            {"attributi_dettaglio_ID": 102, "descr": "43"},
            {"attributi_dettaglio_ID": 103, "descr": "44"}
        ]
    };
    </script>
    <div class="gescat_detail_info_size">
        <a class="dettaglio-id-101 virtualClick" data-disponibilita="3"><span class="desc_size">8.5</span></a>
        <a class="dettaglio-id-102 virtualClick" data-disponibilita="0"><span class="desc_size">9.5</span></a>
        <a class="dettaglio-id-103 virtualClick non_disponibile" data-disponibilita="5"><span class="desc_size">10</span></a>
    </div>
    """
    with patch.object(s, "_fetch_html", return_value=mock_html):
        sizes = s.fetch_sizes("https://www.nencinisport.it/mock-url")
        assert sizes == ["42"]
        assert "43" not in sizes
        assert "44" not in sizes


def test_misterrunning_scraper_normalizes_sizes():
    s = MisterRunningScraper()
    p = {
        "name": "Nike Pegasus 41",
        "price": 109.99,
        "url": "https://www.misterrunning.com/it/nike-pegasus.html",
        "sizes": ["8.5", "9.5", "10.5"]
    }
    raw_sizes = p.get("sizes", [])
    sizes = normalize_sizes(raw_sizes)
    assert "42" in sizes
    assert "43" in sizes
    assert "44.5" in sizes
