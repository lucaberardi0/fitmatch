import pytest
from fitmatch.models import clean_image_url, Offer, MatchedProductGroup
from fitmatch.matcher.normalizer import ProductNormalizer
from fitmatch.supabase_client import SupabaseClient


def test_clean_image_url_valid():
    assert clean_image_url("https://cdn.deporvillage.com/images/prod1.jpg") == "https://cdn.deporvillage.com/images/prod1.jpg"
    assert clean_image_url("http://img.runningwarehouse.eu/watermark/rs.php?path=NPM1-1.jpg&nw=500") == "http://img.runningwarehouse.eu/watermark/rs.php?path=NPM1-1.jpg&nw=500"
    assert clean_image_url("   https://static.nike.com/a/images/shoe.jpg   ") == "https://static.nike.com/a/images/shoe.jpg"


def test_clean_image_url_invalid():
    assert clean_image_url(None) is None
    assert clean_image_url("") is None
    assert clean_image_url("   ") is None
    assert clean_image_url("/images/blank.gif") is None
    assert clean_image_url("https://example.com/assets/blank.gif") is None
    assert clean_image_url("https://example.com/spacer.gif") is None
    assert clean_image_url("https://example.com/pixel.gif") is None
    assert clean_image_url("ftp://example.com/photo.jpg") is None
    assert clean_image_url(12345) is None


def test_offer_model_sanitization():
    # Placeholder image is sanitized to None
    offer1 = Offer(
        store_id="runningwarehouse",
        store_name="Running Warehouse Europe",
        title="Nike Pegasus 41",
        price=139.99,
        url="https://runningwarehouse.eu/prod",
        image_url="/images/blank.gif"
    )
    assert offer1.image_url is None

    # Valid image is preserved
    offer2 = Offer(
        store_id="runningwarehouse",
        store_name="Running Warehouse Europe",
        title="Nike Pegasus 41",
        price=139.99,
        url="https://runningwarehouse.eu/prod",
        image_url="https://img.runningwarehouse.eu/watermark/rs.php?path=NP41-1.jpg&nw=500"
    )
    assert offer2.image_url == "https://img.runningwarehouse.eu/watermark/rs.php?path=NP41-1.jpg&nw=500"


def test_normalizer_picks_valid_image_over_placeholder():
    normalizer = ProductNormalizer()
    offers = [
        Offer(
            store_id="runningwarehouse",
            store_name="Running Warehouse Europe",
            title="Nike Pegasus 41",
            price=130.0,
            url="https://runningwarehouse.eu/1",
            image_url="/images/blank.gif"  # will be None
        ),
        Offer(
            store_id="misterrunning",
            store_name="Mister Running",
            title="Nike Pegasus 41",
            price=140.0,
            url="https://misterrunning.com/1",
            image_url="https://misterrunning.com/img/pegasus41.jpg"
        )
    ]
    groups = normalizer.group_offers(offers)
    assert len(groups) == 1
    assert groups[0].image_url == "https://misterrunning.com/img/pegasus41.jpg"


def test_supabase_search_indexed_fallback(monkeypatch):
    client = SupabaseClient()
    mock_data = [
        {
            "id": "nike pegasus 41 [running_shoes] [unisex]",
            "canonical_name": "Nike Pegasus 41",
            "brand": "Nike",
            "category": "running_shoes",
            "gender": "Unisex",
            "image_url": "/images/blank.gif",  # corrupted/placeholder in db
            "store_offers": [
                {
                    "store_id": "runningwarehouse",
                    "store_name": "Running Warehouse Europe",
                    "current_price": 125.0,
                    "original_price": 140.0,
                    "product_url": "https://runningwarehouse.eu/item",
                    "image_url": None
                },
                {
                    "store_id": "top4running",
                    "store_name": "Top4Running",
                    "current_price": 129.0,
                    "original_price": 140.0,
                    "product_url": "https://top4running.it/item",
                    "image_url": "https://top4running.it/cdn/peg41.jpg"
                }
            ]
        }
    ]

    monkeypatch.setattr(client, "_request", lambda endpoint: {"status": 200, "data": mock_data})
    results = client.search_indexed("Pegasus 41")
    assert len(results) == 1
    prod = results[0]
    # Canonical product must inherit valid image from top4running
    assert prod["image_url"] == "https://top4running.it/cdn/peg41.jpg"
    # RW offer with None must also inherit the valid product image
    rw_offer = next(o for o in prod["offers"] if o["store_id"] == "runningwarehouse")
    assert rw_offer["image_url"] == "https://top4running.it/cdn/peg41.jpg"
    assert "gallery_images" in prod
    assert "https://top4running.it/cdn/peg41.jpg" in prod["gallery_images"]


def test_gallery_images_sanitization():
    raw_gallery = [
        "https://cdn.deporvillage.com/img1.jpg",
        "/images/blank.gif",  # should be discarded
        "https://cdn.deporvillage.com/img2.jpg",
        "https://cdn.deporvillage.com/img1.jpg",  # duplicate, should be deduplicated
        "ftp://invalid.com/img.jpg"  # non-http, should be discarded
    ]
    offer = Offer(
        store_id="deporvillage",
        store_name="Deporvillage",
        title="Nike Vomero",
        price=120.0,
        url="https://deporvillage.it/item",
        image_url="https://cdn.deporvillage.com/img1.jpg",
        gallery_images=raw_gallery
    )
    assert len(offer.gallery_images) == 2
    assert offer.gallery_images == [
        "https://cdn.deporvillage.com/img1.jpg",
        "https://cdn.deporvillage.com/img2.jpg"
    ]


def test_normalizer_aggregates_multi_store_galleries():
    normalizer = ProductNormalizer()
    offers = [
        Offer(
            store_id="runningwarehouse",
            store_name="Running Warehouse",
            title="Asics Novablast 4",
            price=120.0,
            url="https://runningwarehouse.eu/1",
            image_url="https://img.runningwarehouse.eu/path=ANB4-1.jpg&nw=500",
            gallery_images=[
                "https://img.runningwarehouse.eu/path=ANB4-1.jpg&nw=500",
                "https://img.runningwarehouse.eu/path=ANB4-2.jpg&nw=500",
                "https://img.runningwarehouse.eu/path=ANB4-3.jpg&nw=500"
            ]
        ),
        Offer(
            store_id="top4running",
            store_name="Top4Running",
            title="Asics Novablast 4",
            price=135.0,
            url="https://top4running.it/1",
            image_url="https://top4running.it/img/novablast4_front.jpg",
            gallery_images=[
                "https://top4running.it/img/novablast4_front.jpg",
                "https://top4running.it/img/novablast4_sole.jpg"
            ]
        )
    ]
    groups = normalizer.group_offers(offers)
    assert len(groups) == 1
    g = groups[0]
    # Primary image is RW's first image (best price)
    assert g.image_url == "https://img.runningwarehouse.eu/path=ANB4-1.jpg&nw=500"
    # Gallery must contain all unique angles from both stores
    assert len(g.gallery_images) == 5
    assert g.gallery_images[0] == g.image_url
    assert "https://img.runningwarehouse.eu/path=ANB4-2.jpg&nw=500" in g.gallery_images
    assert "https://top4running.it/img/novablast4_sole.jpg" in g.gallery_images
