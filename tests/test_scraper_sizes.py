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


def test_normalize_gender_uk_decimal_and_category_awareness():
    # US Women's shoe sizes must map via US_TO_EU_WOMEN (not +2 EU men offset)
    assert normalize_sizes(["6", "7", "8.5", "10"], gender="women", category="shoes") == ["36.5", "38", "40", "42"]

    # Explicit UK shoe sizes
    assert normalize_sizes(["UK 7.5", "8 UK", "UK 10"], category="shoes") == ["41.5", "42", "44.5"]

    # Top4Running .3/.7 decimals and Unicode ½ fraction
    assert normalize_sizes(["41.3", "42.7", "42½ EU", "46.7"]) == ["41.5", "42.5", "46.5"]

    # Shoe/sock EU ranges should not collapse to their upper bound
    assert normalize_sizes(["EU 47-50", "39-42"]) == ["39-42", "47-50"]

    # Dimension tokens like 42mm / 175cm must be rejected
    assert normalize_sizes(["42mm", "47mm", "175cm"]) == []

    # UK/IT apparel numeric sizes on tops must not turn into shoe sizes 41/44/46
    assert normalize_sizes(["8", "10", "12", "S", "M"], category="top") == ["S", "M"]


def test_offer_matches_size_strict_and_gender_aware():
    from fitmatch.models import Offer

    empty_offer = Offer(store_id="nike", store_name="Nike", title="Nike Pegasus 42", price=120.0, url="https://www.nike.com/it/x", available_sizes=[])
    assert empty_offer.matches_size("42") is False
    assert empty_offer.matches_size("42", allow_unverified=True) is True

    women_offer = Offer(
        store_id="cisalfa",
        store_name="Cisalfa",
        title="Nike Pegasus 42 Scarpe Running Donna",
        price=120.0,
        url="https://www.cisalfasport.it/p",
        available_sizes=["39", "40"],
    )
    assert women_offer.matches_size("8.5") is True
    assert women_offer.matches_size("7") is False


def test_nike_gtin_filters_oos_sizes():
    import json
    from fitmatch.scrapers.nike import NikeScraper

    s = NikeScraper()
    next_payload = {
        "props": {
            "pageProps": {
                "selectedProduct": {
                    "styleColor": "TEST-001",
                    "productType": "footwear",
                    "genders": ["MEN"],
                    "sizes": [
                        {"status": "ACTIVE", "localizedLabel": "42", "gtins": [{"gtin": "G42"}]},
                        {"status": "ACTIVE", "localizedLabel": "43", "gtins": [{"gtin": "G43"}]},
                    ],
                }
            }
        }
    }
    mock_html = f'<script id="__NEXT_DATA__">{json.dumps(next_payload)}</script>'
    gtin_payload = {
        "objects": [
            {"gtin": "G42", "available": True, "level": "HIGH"},
            {"gtin": "G43", "available": False, "level": "OOS"},
        ]
    }
    with patch.object(s, "_fetch_html", return_value=mock_html), patch.object(s, "_fetch_json", return_value=gtin_payload):
        assert s.fetch_sizes("https://www.nike.com/it/t/test/TEST-001") == ["42"]

    with patch.object(s, "_fetch_html", return_value=mock_html), patch.object(s, "_fetch_json", return_value=None):
        assert s.fetch_sizes("https://www.nike.com/it/t/test/TEST-001") == []


def test_df_sport_uses_js_available_strictly():
    from fitmatch.scrapers.df_sport import DFSportScraper

    s = DFSportScraper()
    js_payload = {
        "title": "Hoka Clifton 9 Uomo",
        "type": "Scarpe running",
        "options": [{"name": "Taglia"}],
        "variants": [
            {"title": "42", "available": True, "options": ["42"]},
            {"title": "43", "available": False, "options": ["43"]},
        ],
    }
    with patch.object(s, "_fetch_json", return_value=js_payload):
        assert s.fetch_sizes("https://www.df-sportspecialist.it/products/hoka-clifton-9") == ["42"]


def test_decathlon_rsc_does_not_bleed_across_products():
    from bs4 import BeautifulSoup
    from fitmatch.scrapers.decathlon import DecathlonScraper

    rsc_script = (
        '<script>'
        '{\\"url\\":\\"/p/scarpa-vuota/111/c1\\",\\"models\\":[{\\"availableSizes\\":[]}]},'
        '{\\"url\\":\\"/p/maglia-dopo/222/c2\\",\\"models\\":[{\\"availableSizes\\":[\\"S\\",\\"M\\",\\"L\\"]}]}'
        '</script>'
    )
    soup = BeautifulSoup(rsc_script, "html.parser")
    raw_map = DecathlonScraper.extract_rsc_raw_sizes(soup)
    assert raw_map["/p/scarpa-vuota/111/c1"] == []
    assert raw_map["/p/maglia-dopo/222/c2"] == ["S", "M", "L"]


def test_sportler_preserves_uk_us_units():
    s = SportlerScraper()
    mock_html = """
    <h1>Hoka Clifton 9 Uomo</h1>
    <select id="filterorig_size">
        <option value="">Seleziona</option>
        <option value="1">8 UK</option>
        <option value="2">9.5 US</option>
    </select>
    """
    assert s.fetch_sizes("https://www.sportler.com/it/p/hoka-clifton-9", html=mock_html) == ["42", "43"]


def test_misterrunning_top4running_deporvillage_pdp_stock():
    mr = MisterRunningScraper()
    mr_html = """
    <h1>Nike Pegasus 42 Donna</h1>
    <div class="size_cont">
        <button class="opt opt_on big" data-usa="8.5" data-eu="40"><span>40</span></button>
        <div class="opt opt_off big" data-usa="9" data-eu="40.5"><span>Esaurito</span></div>
    </div>
    """
    with patch.object(mr, "_fetch_html", return_value=mr_html):
        assert mr.fetch_sizes("https://www.misterrunning.com/it/pegasus-donna.html") == ["40"]

    t4 = Top4RunningScraper()
    t4_html = """
    <h1>Adidas Adizero Boston 12</h1>
    <select id="js-detail-select-size" name="detail_size">
        <option value="" disabled selected>Scegli la tua taglia</option>
        <option value="1078">42½ EU | 8 UK | 9 US | 27 CM</option>
    </select>
    """
    with patch.object(t4, "_fetch_html", return_value=t4_html):
        assert t4.fetch_sizes("https://top4running.it/p/boston-12") == ["42.5"]

    dv = DeporvillageScraper()
    dv_html = """
    <h1>Scarpe Asics Novablast 5</h1>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"ProductGroup","hasVariant":[
        {"size":"42","offers":{"availability":"https://schema.org/InStock"}},
        {"size":"43","offers":{"availability":"https://schema.org/OutOfStock"}}
    ]}]}
    </script>
    """
    with patch.object(dv, "_fetch_html", return_value=dv_html):
        assert dv.fetch_sizes("https://www.deporvillage.it/scarpe-asics-novablast-5") == ["42"]


def test_tradeinn_apparel_numeric_uk_does_not_become_shoes():
    s = TradeinnScraper()
    mock_html = """
    <h1>Nike Jacket Running Donna</h1>
    <script type="application/ld+json">
    {"@type":"ProductGroup","hasVariant":[
        {"size":"8","offers":{"availability":"https://schema.org/InStock"}},
        {"size":"10","offers":{"availability":"https://schema.org/InStock"}},
        {"size":"M","offers":{"availability":"https://schema.org/InStock"}}
    ]}
    </script>
    """
    with patch.object(s, "_fetch_html", return_value=mock_html):
        assert s.fetch_sizes("https://www.tradeinn.com/runnerinn/it/nike-jacket-donna/123/p") == ["M"]


def test_maxisport_scopes_multicolor_jsonconfig_by_color():
    import json
    from fitmatch.scrapers.maxisport import MaxiSportScraper

    s = MaxiSportScraper()
    cfg = {
        "attributes": {
            "93": {
                "code": "color",
                "label": "Colore",
                "options": [
                    {"id": "10", "label": "Nero", "products": ["1001", "1002"]},
                    {"id": "20", "label": "Blu", "products": ["2001"]},
                ],
            },
            "409": {
                "code": "taglia",
                "label": "Taglia",
                "options": [
                    {"id": "1", "label": "42", "products": ["1001"]},
                    {"id": "2", "label": "43", "products": ["1002"]},
                    {"id": "3", "label": "44", "products": ["2001"]},
                ],
            },
        },
        "sku": {
            "1001": "052654601_020_42",
            "1002": "052654601_020_43",
            "2001": "052654601_999_44",
        },
    }
    mock_html = (
        '<script type="text/x-magento-init">'
        f'{{"[data-role=swatch-options]": {{"Magento_Swatches/js/swatch-renderer": {{"jsonConfig": {json.dumps(cfg)}, "jsonSwatchConfig": {{}}}}}}}}'
        "</script>"
    )
    with patch.object(s, "_fetch_html", return_value=mock_html):
        sizes = s.fetch_sizes("https://www.maxisport.com/asics-court-ff-3-scarpe-uomo-052654601-020", title="Asics Court FF 3 Uomo")
        assert sizes == ["42", "43"]
        assert "44" not in sizes


def test_adidas_search_uses_gender_and_apparel_context():
    from fitmatch.scrapers.adidas import AdidasScraper

    s = AdidasScraper()
    payload = {
        "itemList": {
            "items": [
                {
                    "displayName": "Ultraboost Light Scarpe Donna",
                    "price": 190.0,
                    "salePrice": 150.0,
                    "link": "/ultraboost-donna/HQ1234.html",
                    "productId": "HQ1234",
                    "availableSizes": ["6", "7.5"],
                    "orderable": True,
                }
            ]
        }
    }
    with patch.object(s, "_fetch_json", return_value=payload):
        offers = s.search("ultraboost", limit=1)
        assert len(offers) == 1
        assert offers[0].available_sizes == ["36.5", "38.5"]


def test_verify_and_purge_offers_safety_and_pagination():
    from scripts.verify_and_purge_offers import _is_homepage_redirect, audit_offer_url, verify_and_purge_offers

    assert _is_homepage_redirect("https://www.sportler.com/it/") is True
    assert _is_homepage_redirect("https://www.runningwarehouse.eu/it") is True
    assert _is_homepage_redirect("https://www.cisalfasport.it/it-it/scarpe/nike-123.html") is False

    # 403 anti-bot challenge response must never mark offer dead or sold out
    mock_403 = MagicMock(status_code=403, url="https://www.sportler.com/it/p/item-1", text="prodotto non più disponibile")
    with patch("scripts.verify_and_purge_offers.requests.get", return_value=mock_403):
        assert audit_offer_url({"id": "1", "store_id": "sportler", "product_url": "https://www.sportler.com/it/p/item-1"})["action"] == "keep"

    # Script i18n strings containing "non è più disponibile" must never falsely mark live PDPs out of stock
    mock_live_js = MagicMock(
        status_code=200,
        url="https://www.nike.com/it/t/pegasus",
        text='<html><head><title>Nike Pegasus</title></head><body><h1>Nike Pegasus</h1><script>var msg="non è più disponibile";</script></body></html>',
    )
    with patch("scripts.verify_and_purge_offers.requests.get", return_value=mock_live_js):
        assert audit_offer_url({"id": "2", "store_id": "nike", "product_url": "https://www.nike.com/it/t/pegasus"})["action"] == "keep"

    # Soft-404 title/heading should be marked for deletion
    mock_soft_404 = MagicMock(
        status_code=200,
        url="https://www.nencinisport.it/it/dead.html",
        text="<html><head><title>404 Pagina non trovata</title></head><body></body></html>",
    )
    with patch("scripts.verify_and_purge_offers.requests.get", return_value=mock_soft_404):
        assert audit_offer_url({"id": "3", "store_id": "nencini", "product_url": "https://www.nencinisport.it/it/dead.html"})["action"] == "delete"

    # When 1 of 2 items in batch 1 is deleted, batch 2 offset advances only by len(kept) == 1
    seen_offsets = []
    calls = {"idx": 0}

    def fake_sb_req(endpoint, method="GET", data=None):
        if method == "GET" and endpoint.startswith("store_offers?select=id,product_id"):
            seen_offsets.append(endpoint.split("offset=")[-1])
            calls["idx"] += 1
            if calls["idx"] == 1:
                return {"status": 200, "data": [
                    {"id": "o1", "product_id": "p1", "store_id": "nike", "product_url": "https://www.nike.com/it/t/dead"},
                    {"id": "o2", "product_id": "p2", "store_id": "nike", "product_url": "https://www.nike.com/it/t/ok"},
                ]}
            if calls["idx"] == 2:
                return {"status": 200, "data": [
                    {"id": "o3", "product_id": "p3", "store_id": "nike", "product_url": "https://www.nike.com/it/t/ok2"},
                ]}
            return {"status": 200, "data": []}
        if method == "GET" and endpoint.startswith("store_offers?product_id=eq."):
            return {"status": 200, "data": []}
        return {"status": 204, "data": []}

    mock_sb = MagicMock()
    mock_sb._request.side_effect = fake_sb_req

    def fake_audit(off):
        if off["id"] == "o1":
            return {"id": "o1", "product_id": "p1", "action": "delete", "reason": "http_404", "url": off["product_url"]}
        return {"id": off["id"], "product_id": off["product_id"], "action": "keep", "status": 200, "url": off["product_url"]}

    with patch("scripts.verify_and_purge_offers.SupabaseClient", return_value=mock_sb), \
         patch("scripts.verify_and_purge_offers.audit_offer_url", side_effect=fake_audit):
        stats = verify_and_purge_offers(batch_size=2, max_items=4, execute=True)

    assert seen_offsets == ["0", "1"]
    assert stats == {"audited": 3, "deleted": 1, "marked_oos": 0, "orphaned_products_deleted": 1}


def test_shopify_base_and_new_stores_filter_stock_and_option_slot():
    from fitmatch.scrapers.shopify_stores import (
        SportITScraper,
        TennisPointScraper,
        BasketballStoreScraper,
        NonSoloSportScraper,
        IntersportScraper,
        BshopzoneScraper,
    )

    tp = TennisPointScraper()
    product_payload = {
        "id": 999001,
        "title": "Babolat Pure Drive",
        "vendor": "Babolat",
        "product_type": "Racchette da tennis",
        "options": [
            {"name": "Colore", "position": 1, "values": ["Blu"]},
            {"name": "Dimensione impugnatura", "position": 2, "values": ["L1", "L2", "L3", "L4"]},
        ],
        "variants": [
            {"id": 11, "option1": "Blu", "option2": "L1", "available": True, "price": 20295},
            {"id": 12, "option1": "Blu", "option2": "L2", "available": False, "price": 20295},
            {"id": 13, "option1": "Blu", "option2": "L3", "available": True, "price": 20295},
            {"id": 14, "option1": "Blu", "option2": "L4", "available": False, "price": 20295},
        ],
    }
    sizes = tp._extract_sizes_from_js(
        product_payload,
        product_url="https://www.tennis-point.it/products/babolat-pure-drive",
        title="Babolat Pure Drive",
    )
    assert sizes == ["L1", "L3"]

    bz = BshopzoneScraper()
    ski_payload = {
        "id": 999002,
        "title": "Scarpa 4-Quattro SL Scarponi Sci",
        "vendor": "Scarpa",
        "product_type": "Scarponi Sci",
        "options": [{"name": "Taglia", "position": 1, "values": ["23", "24.5", "26"]}],
        "variants": [
            {"id": 21, "option1": "23", "available": True},
            {"id": 22, "option1": "24.5", "available": False},
            {"id": 23, "option1": "26", "available": True},
        ],
    }
    assert bz._extract_sizes_from_js(
        ski_payload,
        product_url="https://bshopzone.it/products/4-quattro-sl",
        title="Scarpa 4-Quattro SL Scarponi Sci",
    ) == ["23", "26"]

    # Variant-scoped URL must filter to the active colorway's stock only
    sportit = SportITScraper()
    multi_color = {
        "id": 999003,
        "title": "Mizuno Morelia II Pro AG",
        "vendor": "Mizuno",
        "product_type": "Scarpe Calcio",
        "options": [
            {"name": "Colore", "position": 1, "values": ["Bianco", "Nero"]},
            {"name": "Taglia", "position": 2, "values": ["41", "42", "43"]},
        ],
        "variants": [
            {"id": 101, "options": ["Bianco", "41"], "available": True},
            {"id": 102, "options": ["Bianco", "42"], "available": False},
            {"id": 201, "options": ["Nero", "42"], "available": True},
            {"id": 202, "options": ["Nero", "43"], "available": True},
        ],
    }
    assert sportit._extract_sizes_from_js(
        multi_color,
        product_url="https://sportit.com/products/morelia-ii?variant=101",
        title="Mizuno Morelia II Pro AG",
    ) == ["41"]
    assert BasketballStoreScraper().store_id == "basketballstore"
    assert NonSoloSportScraper().store_id == "nonsolosport"
    assert IntersportScraper().store_id == "intersport"


def test_normalize_us_unisex_and_shopify_brand_and_relevance_guards():
    from fitmatch.models import normalize_sizes
    from fitmatch.scrapers.shopify_stores import SportITScraper, BshopzoneScraper
    from fitmatch.scrapers.adidas import AdidasScraper
    from fitmatch.scrapers.df_sport import DFSportScraper

    # SportIT 'US UNISEX 7.5' format must normalize cleanly to EU sizes
    assert normalize_sizes(["US UNISEX 6.5", "US UNISEX 7.5"], gender=None, category="shoes") == ["39", "40.5"]

    # ShopifyBaseScraper prepends missing brand and uses variant compare_at_price
    sportit = SportITScraper()
    js_payload = {
        "id": 888001,
        "title": "Pegasus 42 - White",
        "vendor": "Nike",
        "options": [{"name": "taglia_id", "position": 1}],
        "variants": [
            {"id": 501, "options": ["US UNISEX 8"], "available": True, "price": 11900, "compare_at_price": 13999},
        ],
    }
    with patch.object(sportit, "_fetch_json", return_value=js_payload):
        offer = sportit._hydrate_candidate_from_js({
            "url": "https://www.sportit.com/products/pegasus-42-white",
            "title": "Pegasus 42 - White",
            "brand": "Nike",
        })
    assert offer is not None
    assert offer.title == "Nike Pegasus 42 - White"
    assert offer.price == 119.0
    assert offer.original_price == 139.99
    assert offer.available_sizes == ["41"]

    # Bshopzone must drop predictive-search Hoka noise when searching 'nike pegasus'
    bz = BshopzoneScraper()
    suggest_noise = {
        "resources": {"results": {"products": [
            {"id": 1, "title": "W Challenger 8", "vendor": "Hoka", "url": "/products/w-challenger-8", "price": "75.00"}
        ]}}
    }
    with patch.object(bz, "_fetch_json", return_value=suggest_noise):
        assert bz.search("nike pegasus", limit=5) == []

    # Adidas must skip competitor brand queries without returning fallback Handball Spezial
    ad = AdidasScraper()
    with patch.object(ad, "_fetch_json") as mock_fetch:
        assert ad.search("nike pegasus", limit=5) == []
        mock_fetch.assert_not_called()

    # DFSport one-size gear remains in_stock even when no size options exist
    df = DFSportScraper()
    with patch.object(df, "_fetch_json", return_value={"resources": {"results": {"products": [
        {"id": 2, "title": "Garmin Forerunner 265", "vendor": "Garmin", "price": "399.00", "url": "/products/forerunner-265", "available": True}
    ]}}}), patch.object(df, "fetch_sizes", return_value=[]):
        res = df.search("garmin 265", limit=5)
    assert len(res) == 1
    assert res[0].in_stock is True
