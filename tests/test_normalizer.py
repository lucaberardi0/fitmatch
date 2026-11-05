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


