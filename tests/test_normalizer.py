import pytest
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.models import Offer


@pytest.fixture
def normalizer():
    return ProductNormalizer()


def test_garmin_device_vs_case_isolation(normalizer):
    """Ensure silicone case and bundles never cluster with core device."""
    offers = [
        Offer(store_id="deporvillage", store_name="Deporvillage", title="Garmin Edge Explore 2", price=229.95, url="http://1"),
        Offer(store_id="deporvillage", store_name="Deporvillage", title="Garmin Edge Explore 2 Pack", price=294.95, url="http://2"),
        Offer(store_id="alltricks", store_name="Alltricks", title="Garmin Edge Explore 2 Custodia in silicone nera", price=19.0, url="http://3"),
        Offer(store_id="cisalfa", store_name="Cisalfa Sport", brand="Garmin", title="Ciclocomputer Edge Explore 2", price=198.0, url="http://4"),
    ]

    groups = normalizer.group_offers(offers)
    # The device (deporvillage + cisalfa), the pack (deporvillage), and the case (alltricks) must be distinct groups
    device_groups = [g for g in groups if "custodia" not in g.canonical_name.lower() and "pack" not in g.canonical_name.lower()]
    case_groups = [g for g in groups if "custodia" in g.canonical_name.lower()]
    pack_groups = [g for g in groups if "pack" in g.canonical_name.lower() or "bundle" in g.canonical_name.lower()]

    assert len(case_groups) == 1
    assert case_groups[0].best_price == 19.0

    assert len(pack_groups) == 1
    assert pack_groups[0].best_price == 294.95

    # Core device group must contain the real device offers (and NOT the 19 euro case)
    assert len(device_groups) == 1
    assert len(device_groups[0].offers) == 2
    assert device_groups[0].best_price == 198.0
    for offer in device_groups[0].offers:
        assert offer.price > 100.0


def test_model_version_number_preservation(normalizer):
    """Ensure generation numbers (e.g. 55 vs 965, Pro 4 vs Pro 5) do not collapse."""
    offers = [
        Offer(store_id="decathlon", store_name="Decathlon", title="Smartwatch Garmin Forerunner 965 nero", price=509.99, url="http://1"),
        Offer(store_id="decathlon", store_name="Decathlon", title="Smartwatch gps Garmin Forerunner 55 nero", price=149.99, url="http://2"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas Adizero Adios Pro 5", price=260.0, url="http://3"),
        Offer(store_id="runningwarehouse", store_name="Running Warehouse", title="adidas adizero Adios Pro 4", price=172.9, url="http://4"),
        Offer(store_id="runningwarehouse", store_name="Running Warehouse", title="adidas Adizero Adios 9", price=94.9, url="http://5"),
    ]

    groups = normalizer.group_offers(offers)
    assert len(groups) == 5  # Each is a distinct generation / tier


def test_brand_duplication_handling(normalizer):
    """Ensure titles with repeated brand names ('New Balance Scarpe New Balance 530') clean correctly."""
    offer = Offer(
        store_id="deporvillage",
        store_name="Deporvillage",
        title="New balance Scarpe New Balance 530 bianco grigio blu navy",
        price=107.95,
        url="http://nb"
    )
    key = normalizer.extract_cluster_key(offer)
    assert "new balance" in key
    # Should not repeat 'new balance new balance'
    assert "new balance 530" in key


def test_garment_type_separation(normalizer):
    """Ensure jackets, pants and t-shirts of the same line do not cluster together."""
    offers = [
        Offer(store_id="misterrunning", store_name="Mister Running", title="Joma Elite Viii Giacca - Fluor Green", price=39.9, url="http://1"),
        Offer(store_id="misterrunning", store_name="Mister Running", title="Joma Elite Viii Maglietta - Navy/yellow Fluor", price=10.71, url="http://2"),
    ]

    groups = normalizer.group_offers(offers)
    assert len(groups) == 2


def test_price_sanity_outlier_guardrail(normalizer):
    """Ensure that if two offers accidentally share tokens, extreme price outliers are isolated."""
    offers = [
        Offer(store_id="store1", store_name="Store 1", title="Special Shoe Model X", price=150.0, url="http://1"),
        Offer(store_id="store2", store_name="Store 2", title="Special Shoe Model X", price=160.0, url="http://2"),
        Offer(store_id="store3", store_name="Store 3", title="Special Shoe Model X", price=15.0, url="http://3"),
    ]

    partitions = normalizer.partition_by_price_sanity(offers)
    assert len(partitions) == 2  # Main group [150, 160] and outlier [15]
    assert len(partitions[0]) == 2
    assert len(partitions[1]) == 1
    assert partitions[1][0].price == 15.0


def test_barcode_exact_matching(normalizer):
    """Ensure offers with the same EAN/barcode group together deterministically."""
    offers = [
        Offer(store_id="df_sportspecialist", store_name="DF Sport Specialist", barcode="198729183163", title="Scarpe Nike Pegasus Trail", price=99.9, url="http://1"),
        Offer(store_id="tradeinn", store_name="Tradeinn", barcode="198729183163", title="Nike Pegasus Trail 4 Man", price=94.5, url="http://2"),
        Offer(store_id="cisalfa", store_name="Cisalfa", barcode="843512345678", title="Racchetta Bullpadel Hack 04", price=199.0, url="http://3"),
    ]

    groups = normalizer.group_offers(offers)
    assert len(groups) == 2
    pegasus_group = next(g for g in groups if len(g.offers) == 2)
    assert len(pegasus_group.offers) == 2
    assert pegasus_group.best_price == 94.5
    assert pegasus_group.cross_store_savings == round(99.9 - 94.5, 2)


def test_padel_and_cycling_article_types(normalizer):
    """Ensure rackets and bike trainers are properly typed and named."""
    assert normalizer.detect_article_type("Racchetta Padel Bullpadel Hack 04") == "racket"
    assert normalizer.detect_article_type("Pala de padel Nox AT10 Genius") == "racket"
    assert normalizer.detect_article_type("Rullo Smart Tacx Flux 2") == "trainer"
    assert normalizer.detect_article_type("Wahoo Kickr V6 Smart Trainer") == "trainer"


def test_iconic_model_brand_inference_and_cross_gender_clustering(normalizer):
    """Ensure iconic models without explicit brand in title infer correct brand and cluster cross-store."""
    # 1. Supernova Rise 3 without 'Adidas' in title
    b1 = normalizer.extract_brand("Scarpe Supernova Rise 3 - Bianco")
    assert b1 == "Adidas"

    # 2. Cross-store clustering of Supernova Rise 3 between one store saying 'Uomo' and another saying nothing (Unisex)
    o1 = Offer(store_id="store1", store_name="Cisalfa", title="Scarpe Corsa Uomo Adidas Supernova Rise 3", price=120.0, url="http://1")
    o2 = Offer(store_id="store2", store_name="Mister Running", title="Supernova Rise 3 Scarpe Running", price=95.0, url="http://2")
    groups = normalizer.group_offers([o1, o2])
    assert len(groups) == 1
    assert len(groups[0].offers) == 2
    assert groups[0].best_price == 95.0
    assert groups[0].cross_store_savings == 25.0

    # 3. Super shoes (Adios Pro 4, Alphafly, etc.) cluster as unisex racing models
    o3 = Offer(store_id="storeA", store_name="Decathlon", title="Scarpe running Adidas Adizero Adios Pro 4 donna", price=250.0, url="http://3")
    o4 = Offer(store_id="storeB", store_name="Top4Running", title="Adidas Adizero Adios Pro 4 uomo", price=179.0, url="http://4")
    groups_super = normalizer.group_offers([o3, o4])
    assert len(groups_super) == 1
    assert len(groups_super[0].offers) == 2
    assert groups_super[0].cross_store_savings == 71.0


def test_article_type_edge_and_apparel_isolation(normalizer):
    assert normalizer.detect_article_type("adidas Hyperboost Edge Scarpe Running") == "shoes"
    assert normalizer.detect_article_type("Garmin Edge 840 Ciclocomputer GPS") == "cycling"
    assert normalizer.detect_article_type("Asics Court FF 3 Clay Scarpe Tennis") == "shoes"
    assert normalizer.detect_article_type("UYN Biking Shirt Manica Corta") == "top"
    assert normalizer.detect_article_type("Nike Tech Fleece Track Pants Uomo") == "pants"


def test_new_categories_brands_and_sizes(normalizer):
    from fitmatch.models import normalize_sizes, STORE_SHIPPING_RULES

    # Tennis & Winter Sports brand extraction
    assert normalizer.extract_brand("Racchetta Babolat Pure Drive 2025") == "Babolat"
    assert normalizer.extract_brand("Scarponi Sci Atomic Hawx Prime 110 S") == "Atomic"
    assert normalizer.extract_brand("Pallone Basket Spalding TF-1000") == "Spalding"

    # Article types for new categories (shoes still stay 'shoes' when explicit scarpe tennis)
    assert normalizer.detect_article_type("Racchetta Tennis Yonex Ezone 100") == "tennis"
    assert normalizer.detect_article_type("Scarponi Sci Nordica Speedmachine 3 110") == "winter_sports"
    assert normalizer.detect_article_type("Canotta NBA Chicago Bulls Swingman") == "basketball"

    # Grip sizes for tennis/padel and Mondopoint for ski boots
    assert normalize_sizes(["L1", "2", "L3", "4"]) == ["L1", "L2", "L3", "L4"]
    assert normalize_sizes(["24.5", "25,5", "27.0"], category="winter_sports") == ["24.5", "25.5", "27"]

    # Verified shipping rules on newly integrated stores
    assert STORE_SHIPPING_RULES["sportit"]["free_threshold"] == 59.90
    assert STORE_SHIPPING_RULES["tennis_point"]["standard"] == 5.99
    assert STORE_SHIPPING_RULES["bshopzone"]["free_threshold"] == 100.0


def test_shipping_cost_handles_none_free_threshold():
    from fitmatch.models import calculate_shipping_cost, STORE_SHIPPING_RULES
    from fitmatch.supabase_client import SupabaseClient

    # Store with free_threshold=None (e.g. tradeinn) must always return standard shipping cost
    tradeinn_rule = STORE_SHIPPING_RULES["tradeinn"]
    assert tradeinn_rule["free_threshold"] is None
    assert calculate_shipping_cost(200.0, tradeinn_rule) == 4.99

    # Store with numeric threshold returns 0.0 once threshold is met
    assert calculate_shipping_cost(100.0, STORE_SHIPPING_RULES["cisalfa"]) == 0.0
    assert calculate_shipping_cost(50.0, STORE_SHIPPING_RULES["cisalfa"]) == 9.90

    # Formatting a Supabase product with a Tradeinn offer must not raise TypeError
    sc = SupabaseClient(base_url="https://example.supabase.co", api_key="test")
    formatted = sc._format_product_with_offers({
        "id": "p1",
        "canonical_name": "Nike Pegasus 41",
        "brand": "Nike",
        "category": "running_shoes",
        "store_offers": [{
            "store_id": "tradeinn",
            "store_name": "Tradeinn",
            "current_price": 120.0,
            "product_url": "https://www.tradeinn.com/runnerinn/it/nike-pegasus-41/1",
            "raw_title": "Nike Pegasus 41",
            "available_sizes": ["42"],
        }],
    })
    assert formatted["offers"][0]["shipping_cost"] == 4.99
    assert formatted["offers"][0]["free_shipping_threshold"] is None
    assert formatted["offers"][0]["is_free_shipping"] is False


def test_cross_store_matching_and_category_refinements(normalizer):
    # Gore-Tex / GTX and Garmin Multifunzione/Sportivo and Nike Zm unify cleanly
    o1 = Offer(store_id="deporvillage", store_name="Deporvillage", title="Hoka Clifton 9 Gore Tex Donna", price=125.0, url="http://1")
    o2 = Offer(store_id="alltricks", store_name="Alltricks", title="Hoka Clifton 9 Gtx Donna", price=119.0, url="http://2")
    assert len(normalizer.group_offers([o1, o2])) == 1

    g1 = Offer(store_id="cisalfa", store_name="Cisalfa Sport", title="Garmin Forerunner 265S", price=399.0, url="http://3")
    g2 = Offer(store_id="intersport", store_name="Intersport", title="Garmin Multifunzione Forerunner 265S", price=379.0, url="http://4")
    g3 = Offer(store_id="decathlon", store_name="Decathlon", title="Garmin Sportivo Forerunner 265S", price=389.0, url="http://5")
    assert len(normalizer.group_offers([g1, g2, g3])) == 1

    n1 = Offer(store_id="cisalfa", store_name="Cisalfa Sport", title="Nike Pegasus 41 Gore-Tex", price=130.0, url="http://6")
    n2 = Offer(store_id="tradeinn", store_name="Tradeinn", title="Nike Zm Pegasus 41 Gore Tex", price=115.0, url="http://7")
    assert len(normalizer.group_offers([n1, n2])) == 1

    # Sports knee pads stay sport gear; moto armor stays non_sport
    assert normalizer.detect_article_type("Nike Pro Open Ginocchiera") == "gear"
    assert normalizer.detect_article_type("Asics Ginocchiera Fluo") == "gear"
    assert normalizer.is_non_sport_junk("Alpinestars Ginocchiera Moto") is True

    # Former 'gear' buckets classify into specific categories
    assert normalizer.detect_article_type("Under Armour Vanish Elite Seamless Short Blk") == "pants"
    assert normalizer.detect_article_type("The North Face Router Backpack 40L") == "hydration"
    assert normalizer.detect_article_type("Bianchi Bicicletta Strada Oltre Race 105 Di2") == "cycling"
    assert normalizer.detect_article_type("Karpos Pile Full Zip Vertice Evo") == "top"
    assert normalizer.detect_article_type("Decathlon Bevanda Energetica Powder Iso") == "nutrition"


def test_subbrand_resolution_and_false_positive_prevention(normalizer):
    # Sub-brands resolve to parent brand cleanly without false-positive Bullpadel / football_boots collisions
    assert normalizer.extract_brand("ACG Lava Flow (Smanicato Therma-FIT ADV – Donna)") == "Nike"
    assert normalizer.detect_article_type("ACG Lava Flow (Smanicato Therma-FIT ADV – Donna)") == "jacket"
    assert normalizer.detect_article_type("ACG Rope de Dope (Smanicato da trail running Therma-FIT ADV – Donna)") == "jacket"

    assert normalizer.extract_brand("Nike Acg Pegasus Trail - Summit White/black/phantom/safety Orange") == "Nike"
    assert normalizer.detect_article_type("Nike Acg Pegasus Trail - Summit White/black/phantom/safety Orange") == "shoes"

    assert normalizer.extract_brand("Mount To Coast Mount To Coast M1") == "Mount To Coast"
    assert normalizer.detect_article_type("Mount To Coast Mount To Coast M1") == "gear"

    assert normalizer.extract_brand("Nikecourt Tshirt Tennis Max90") == "Nike"
    assert normalizer.detect_article_type("Nikecourt Tshirt Tennis Max90") == "top"

    assert normalizer.is_non_sport_junk("Trixie Pettorina Cani Trekking New Premium 20 Mm") is True
    assert normalizer.is_non_sport_junk("Victorinox Fiaschetta Trekking Inossidabile C30") is True
    assert normalizer.is_non_sport_junk("Invertika Slip Sgambato V") is True

    # Parenthetical garment words and full model tokens survive clean_title and extract_cluster_key
    o_ls = Offer(
        store_id="nike",
        store_name="Nike",
        title="ACG Radical AirFlow NXT (Maglia da trail running a manica lunga Dri-FIT – Uomo)",
        price=149.99,
        url="http://nike",
    )
    key_ls = normalizer.extract_cluster_key(o_ls)
    assert "acg radical airflow nxt" in key_ls
    assert "lunga" in key_ls
    assert "[top]" in key_ls


def test_apparel_long_sleeve_and_fleece_vs_polar_watch():
    normalizer = ProductNormalizer()
    assert normalizer.detect_article_type("Nike Acg Radical Airflow Nxt Maglia Trail Manica Lunga") == "top"
    assert normalizer.detect_article_type("Nike Acg Wolf Grid") == "top"
    assert normalizer.detect_article_type("Nike Pile Acg Canwell Glacier") == "top"
    assert normalizer.detect_article_type("Nike Polar Acg Wolf Tree") == "top"
    assert normalizer.detect_article_type("Adidas Adizero Long-Sleeve Running Shirt") == "top"
    # Polar sports watches & HRMs must NEVER be misclassified as fleece tops
    assert normalizer.detect_article_type("Polar Vantage V3 Orologio GPS") == "gps_watch"
    assert normalizer.detect_article_type("Polar H10 Fascia Cardio") == "sensor"


def test_pack_mount_strap_case_racket_swim_false_positives():
    normalizer = ProductNormalizer()
    # Footwear colorway "Pack" names must stay football_boots / shoes, never 'pack'
    assert normalizer.detect_article_type("Adidas Calcio Predator 24 Elite Turf Tf Solar Energy Pack") == "football_boots"
    assert normalizer.detect_article_type("Nike Pegasus Plus Fast Pack") == "shoes"
    # Sports bras ("supporto") and stirrup leggings ("staffa") must not become bike mounts
    assert normalizer.detect_article_type("Adidas Reggiseno Optimé 3 Stripes Supporto Medio") == "top"
    assert normalizer.detect_article_type("Nike One Leggings Tutta Lunghezza Vita Alta Staffa") == "pants"
    # Cover-up jackets/fleeces must not become watch cases
    assert normalizer.detect_article_type("Adidas Cover Up Giacca Uomini") == "jacket"
    assert normalizer.detect_article_type("Adidas Cover Up Half Zip Felpa") == "top"
    # Bikinis & strap sneakers must not become watch straps
    assert normalizer.detect_article_type("New Balance Sneaker 578 Bungee Lace Top Strap") == "shoes"
    # Padel shorts/shoes must not become padel rackets
    assert normalizer.detect_article_type("Asics Shorts Padel Court 7In") == "pants"
    # Aquasphere Phantom swim wetsuit must be swim, not football_boots
    assert normalizer.detect_article_type("Aquasphere Tuta Neoprene Aquasphere Phantom V3") == "swim"


def test_url_brand_and_category_extraction_prevents_null_brand_and_gear_dump():
    normalizer = ProductNormalizer()
    # Cisalfa deterministic URL brand & category recovery
    assert normalizer.extract_brand(
        "Quandary m",
        url="https://www.cisalfasport.it/it-it/patagonia/pantalone-outdoor-quandary-m-S5845313.html",
    ) == "Patagonia"
    assert normalizer.detect_article_type(
        "Quandary m",
        url="https://www.cisalfasport.it/it-it/patagonia/pantalone-outdoor-quandary-m-S5845313.html",
    ) == "pants"
    assert normalizer.extract_brand(
        "Icon m",
        url="https://www.cisalfasport.it/it-it/under-armour/felpa-icon-m-S6021258.html",
    ) == "Under Armour"
    assert normalizer.detect_article_type(
        "Icon m",
        url="https://www.cisalfasport.it/it-it/under-armour/felpa-icon-m-S6021258.html",
    ) == "top"
    # Maxisport multi-word brand slug must never truncate to 'Under' / 'La' / 'New'
    assert normalizer.extract_brand(
        "Gel-resolution x night energy",
        url="https://www.maxisport.com/asics-1041a526-gel-resolution-x-night-energy-scarpe-tennis-uomo-052654401-020",
    ) == "Asics"
    assert normalizer.extract_brand(
        "Felpa mezza zip",
        url="https://www.maxisport.com/under-armour-1379757-felpa-mezza-zip-uomo-053400001-510",
    ) == "Under Armour"
    # Tennis-Point & Alltricks URL extraction
    assert normalizer.extract_brand(
        "Fast Lightweight Crew Calze",
        url="https://www.tennis-point.it/products/nike-fast-lightweight-crew-calze-da-corsa-unisex-rosa-nero-a0000010360902",
    ) == "Nike"
    assert normalizer.detect_article_type(
        "Pasta Frutta Carbofruit Fragola 25 Pezzi",
        url="https://www.alltricks.it/F-11928-nutrition/P-2551893-pasta_di_frutta_carbofruit_fragola_25_pezzi",
    ) == "nutrition"
    assert normalizer.detect_article_type(
        "Abus Airbreaker Pure",
        url="https://www.alltricks.it/F-10007-casques/P-3028313-abus_airbreaker_pure_road_casco_grigio",
    ) == "cycling"
    # Hyphenated / truncated existing_brand aliases normalize cleanly
    assert normalizer.extract_brand("Canotta Tech", existing_brand="Under-armour") == "Under Armour"
    assert normalizer.extract_brand("Giacca Alpha", existing_brand="the-north-face") == "The North Face"


def test_phase2_clustering_cleanup_and_enriched_embeddings(normalizer):
    from scripts.generate_embeddings import build_embedding_text

    # 1. Repeated brand / noisy descriptors collapse into clean unified clusters
    o1 = Offer(store_id="nike", store_name="Nike", title="Nike Zoom Fly 6 (Uomo)", price=169.99, url="http://1")
    o2 = Offer(store_id="misterrunning", store_name="Mister Running", title="Zoom Fly 6 Competizione Uomini", price=139.9, url="http://2")
    o3 = Offer(store_id="alltricks", store_name="Alltricks", title="Nike Zoom Fly 6 Gara su strada uomo", price=149.9, url="http://3")
    groups = normalizer.group_offers([o1, o2, o3])
    assert len(groups) == 1
    assert len(groups[0].offers) == 3

    # 2. Air Zoom / Zoom Pegasus unify cleanly with Nike Pegasus
    p1 = Offer(store_id="store1", store_name="Store 1", title="Nike Air Zoom Pegasus 41 Uomo", price=129.0, url="http://4")
    p2 = Offer(store_id="store2", store_name="Store 2", title="Nike Pegasus 41 Uomo", price=109.0, url="http://5")
    assert len(normalizer.group_offers([p1, p2])) == 1

    # 3. Under Armour 'UA' abbreviation & 'Visiera' unify cleanly
    ua1 = Offer(store_id="store1", store_name="Store 1", title="Under Armour Cappellino Visiera Blitzing", price=22.0, url="http://6")
    ua2 = Offer(store_id="store2", store_name="Store 2", title="Under Armour Cappellino UA Blitzing", price=19.0, url="http://7")
    assert len(normalizer.group_offers([ua1, ua2])) == 1

    # 4. Non-consecutive duplicate words are removed from canonical display names
    clean_cap = normalizer.build_canonical_display_name("Asics Cappellino Asics 5 Pannelli Cappellino")
    assert clean_cap.lower().count("asics") == 1
    assert clean_cap.lower().count("cappellino") == 1

    # 5. Kipsta Decathlon brand is recognized
    assert normalizer.extract_brand("Kipsta Scarpe Calcio Viralto III FG") == "Kipsta"

    # 6. Enriched embedding text incorporates offer raw_title descriptors + expanded domain hints
    emb_text = build_embedding_text(
        {"brand": "Nike", "canonical_name": "Nike Pegasus 41 Gtx", "category": "running_shoes", "gender": "Uomo"},
        offer_titles=["Nike Pegasus 41 Gore-Tex Impermeabile Nero Uomo", "Nike Pegasus 41 Gtx"],
    )
    assert "varianti:" in emb_text
    assert "impermeabile" in emb_text.lower()
    assert "daily trainer" in emb_text.lower()


def test_deals_audit_taxonomy_false_positive_regressions(normalizer):
    from fitmatch.crawler import CategoryCrawler

    crawler = CategoryCrawler.__new__(CategoryCrawler)
    crawler.normalizer = normalizer

    # Non-watches containing "fenix" / "instinct" must NEVER become Garmin gps_watch
    assert normalizer.detect_article_type("Ridley Prodotto ricondizionato - Ridley Fenix SL Disc Tiagra") == "cycling"
    assert normalizer.extract_brand("Ridley Prodotto ricondizionato - Ridley Fenix SL Disc Tiagra") != "Garmin"
    assert normalizer.detect_article_type("Peruzzo Portabici Pure Instinct 4 Su Gancio Sfera") == "cycling"
    assert normalizer.extract_brand("Peruzzo Portabici Pure Instinct 4 Su Gancio Sfera") != "Garmin"
    assert normalizer.detect_article_type("Instinct Trail Gilet Idratazione Eklipse 12L") == "hydration"
    assert normalizer.extract_brand("Instinct Trail Gilet Idratazione Eklipse 12L") != "Garmin"
    assert normalizer.detect_article_type("Scarpa Instinct VSR Arrampicata") != "gps_watch"
    assert normalizer.extract_brand("Scarpa Instinct VSR Arrampicata") == "Scarpa"
    assert normalizer.detect_article_type("Joma Fenix Scarpe Running") == "shoes"
    assert normalizer.extract_brand("Joma Fenix Scarpe Running") == "Joma"
    assert normalizer.detect_article_type("Muta Apnea Instinct 5mm") == "swim"
    assert normalizer.detect_article_type("Siux Racchetta Padel Fenix Pro 2026") == "racket"

    # Real Garmin watches stay Garmin gps_watch
    assert normalizer.detect_article_type("Garmin Fenix 8 AMOLED 47mm") == "gps_watch"
    assert normalizer.extract_brand("Garmin Fenix 8 AMOLED 47mm") == "Garmin"
    assert normalizer.detect_article_type("Garmin Instinct 3 Solar 45mm") == "gps_watch"

    # Juan Lebron (Padel) must never be classified as NBA Basketball / Nike
    assert normalizer.extract_brand("BABOLAT VERON JUAN LEBRON 3.1") == "Babolat"
    assert crawler._detect_category("BABOLAT VERON JUAN LEBRON 3.1") == "padel"
    assert normalizer.extract_brand("BABOLAT PREMURA 3 MEN LEBRON") == "Babolat"
    assert crawler._detect_category("BABOLAT PREMURA 3 MEN LEBRON") != "basketball"

    # Apparel items (camicia, corsaro, 2inch, bib) must never be classified as shoes
    assert normalizer.detect_article_type("adizero Camicia da corsa Donna-viola") == "top"
    assert normalizer.detect_article_type("UNDER ARMOUR Corsaro Uomo UA Coolswitch Run Compression") == "pants"
    assert normalizer.detect_article_type("adidas Adizero 2inch") == "pants"
    assert normalizer.detect_article_type("Adventure Ride II Bib") == "pants"
    assert normalizer.extract_brand("Adventure Ride II Bib") != "Saucony"

    # Bike handlebar ("manubrio") vs fitness dumbbells ("manubri")
    assert normalizer.detect_article_type("Pro Manubrio PRO LT COMPACT ERGO 31,8mm") == "cycling"
    assert crawler._detect_category("Pro Manubrio PRO LT COMPACT ERGO 31,8mm") == "cycling"

    # "Atomic Pink" shoe colorway & "Volkl Overgrip" must never be winter_sports
    assert crawler._detect_category("Nike Streakfly 2 - Atomic Pink/white/racer Blue") == "running_shoes"
    assert crawler._detect_category("Confezione da 12 Overgrip Volkl Super Grip II Bianco") != "winter_sports"

    # Tennis shoes (Solution Speed / Gel-Challenger) must route to tennis, not running_shoes
    assert crawler._detect_category("ASICS Scarpe tennis uomo Asics SOLUTION SPEED FF 4 terra battuta") == "tennis"
    assert crawler._detect_category("Asics Gel-Challenger 14 Scarpa per terra rossa Donna") == "tennis"


def test_overmerged_clusters_and_variant_isolation(normalizer):
    """Prevent multi-generation shoes, GTX/TR/Wide variants, kids GS, and collection apparel from colliding."""
    # 1. Multi-number model families (GT-2000 14 vs 15, TR vs GTX, 880 v13 vs v15)
    gt_offers = [
        Offer(store_id="s1", store_name="S1", title="ASICS GT 2000 14 Men's Shoes Black/White", price=130.0, url="http://1"),
        Offer(store_id="s2", store_name="S2", title="Asics Gt-2000 15 - Black/energy Aqua", price=145.0, url="http://2"),
        Offer(store_id="s3", store_name="S3", title="Asics Gt 2000 14 Tr - Aurora Green/cacti", price=135.0, url="http://3"),
        Offer(store_id="s4", store_name="S4", title="ASICS GT 2000 14 GTX Men's Shoes Black/Vanilla", price=155.0, url="http://4"),
    ]
    assert len(normalizer.group_offers(gt_offers)) == 4

    nb_offers = [
        Offer(store_id="s1", store_name="S1", title="New Balance Fresh Foam X 880 v13 Running Shoes Blue", price=110.0, url="http://1"),
        Offer(store_id="s2", store_name="S2", title="New Balance Fresh Foam X 880v15", price=150.0, url="http://2"),
        Offer(store_id="s3", store_name="S3", title="NEW BALANCE 880 V15", price=145.0, url="http://3"),
    ]
    nb_groups = normalizer.group_offers(nb_offers)
    assert len(nb_groups) == 2  # v13 isolated; 880v15 & 880 V15 unified

    # 2. GTX / Waterproof & Wide variants stay separate from standard models
    peg_offers = [
        Offer(store_id="s1", store_name="S1", title="Nike Pegasus 42 - Black/anthracite", price=120.0, url="http://1"),
        Offer(store_id="s2", store_name="S2", title="Nike Pegasus 42 Gore-Tex Impermeabile", price=155.0, url="http://2"),
        Offer(store_id="s3", store_name="S3", title="Nike Pegasus 42 Wide - Black", price=125.0, url="http://3"),
    ]
    assert len(normalizer.group_offers(peg_offers)) == 3

    # 3. Kids / GS / Bambina / Children shoes never cluster with Adult shoes
    kids_offers = [
        Offer(store_id="s1", store_name="S1", title="Asics Novablast 6 - Black/khaki", price=140.0, url="http://1"),
        Offer(store_id="s2", store_name="S2", title="Asics Scarpe da running Novablast 6 GS", price=80.0, url="http://2"),
        Offer(store_id="s3", store_name="S3", title="ASICS Scarpe bambina Gel Noosa Tri 16 GS", price=75.0, url="http://3"),
        Offer(store_id="s4", store_name="S4", title="ASICS Noosa Tri 16 Men's Shoes", price=130.0, url="http://4"),
    ]
    assert normalizer.extract_gender("Asics Scarpe da running Novablast 6 GS") == "Junior"
    assert normalizer.extract_gender("ASICS Scarpe bambina Gel Noosa Tri 16 GS") == "Junior"
    assert normalizer.extract_gender("Atomic Redster GS Sci Gigante") != "Junior"
    assert len(normalizer.group_offers(kids_offers)) == 4

    # 4. Multi-dash brand prefix titles ('SCOTT Scarpe - Trail - Uomo - Supertrac 3 - Arancione') never fall into 'general'
    scott_offers = [
        Offer(store_id="decathlon", store_name="Decathlon", title="SCOTT Scarpe - Trail - Uomo - Supertrac 3 - Arancione", price=129.0, url="http://1"),
        Offer(store_id="decathlon", store_name="Decathlon", title="SCOTT Scarpe - Running - Uomo - Pursuit Ride 2 M - Giallo", price=119.0, url="http://2"),
    ]
    k_st = normalizer.extract_cluster_key(scott_offers[0])
    k_pr = normalizer.extract_cluster_key(scott_offers[1])
    assert "supertrac 3" in k_st and "general" not in k_st
    assert "pursuit ride 2" in k_pr and "general" not in k_pr
    assert len(normalizer.group_offers(scott_offers)) == 2

    # 5. Collection-only Top4Running titles split cleanly by URL garment subtype & gender
    berlin_offers = [
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=16.0, url="https://top4running.it/p/adidas-ber26-ru-sock-kx2166"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=21.0, url="https://top4running.it/p/adidas-ber26-aop-tank-kg8253"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=21.3, url="https://top4running.it/p/adidas-bmw-berlin-marathon-2026-t-shirt-women-hz9489"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=26.0, url="https://top4running.it/p/adidas-bmw-berlin-marathon-2026-running-cap-hz9531"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=33.0, url="https://top4running.it/p/adidas-ber26-ls-tee-m-kx2155"),
        Offer(store_id="top4running", store_name="Top4Running", title="adidas BMW Berlin Marathon 2026", price=45.0, url="https://top4running.it/p/adidas-ber26-lg-tightm-kg8214"),
    ]
    assert len(normalizer.group_offers(berlin_offers)) == 6

    swift_offers = [
        Offer(store_id="top4running", store_name="Top4Running", title="Nike Swift", price=55.0, url="https://top4running.it/p/nike-dri-fit-swift-halfzip-sweatshirt-women-hq0499-570"),
        Offer(store_id="top4running", store_name="Top4Running", title="Nike Swift", price=60.0, url="https://top4running.it/p/nike-swift-high-waisted-running-leggings-women-ih8138-630"),
        Offer(store_id="top4running", store_name="Top4Running", title="Nike Swift", price=85.0, url="https://top4running.it/p/nike-swift-repel-packable-running-jacket-women-hq0650-006"),
    ]
    assert len(normalizer.group_offers(swift_offers)) == 3

    # 6. Football boots separate by tier & soleplate (Club TF vs Elite FG)
    f50_offers = [
        Offer(store_id="s1", store_name="S1", title="ADIDAS F50 HYPERFAST CLUB TF", price=59.0, url="http://1"),
        Offer(store_id="s2", store_name="S2", title="ADIDAS F50 HYPERFAST ELITE FG", price=249.0, url="http://2"),
        Offer(store_id="s3", store_name="S3", title="ADIDAS F50 HYPERFAST LEAGUE SG", price=99.0, url="http://3"),
    ]
    assert len(normalizer.group_offers(f50_offers)) == 3

    # 7. Tech-fabric-only titles preserve their product line instead of collapsing to 'general'
    ua_offers = [
        Offer(store_id="s1", store_name="S1", title="Under Armour ColdGear", price=45.0, url="https://example.com/ua-coldgear-top"),
        Offer(store_id="s2", store_name="S2", title="Under Armour HeatGear", price=35.0, url="https://example.com/ua-heatgear-top"),
    ]
    assert "coldgear" in normalizer.extract_cluster_key(ua_offers[0])
    assert "heatgear" in normalizer.extract_cluster_key(ua_offers[1])
    assert len(normalizer.group_offers(ua_offers)) == 2










