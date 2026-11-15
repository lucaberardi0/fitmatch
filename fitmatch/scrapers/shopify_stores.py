from fitmatch.scrapers.shopify_base import ShopifyBaseScraper


class SportITScraper(ShopifyBaseScraper):
    """Scraper for SportIT (sportit.com) — Italian multisport leader (Calcio, Padel, Tennis, Running, Nuoto, Sci)."""

    store_id = "sportit"
    store_name = "SportIT"
    base_url = "https://www.sportit.com"
    rating = 4.8
    review_count = 13900
    formatted_review_count = "13,9K"
    card_theme = "white"
    accent_color = "#0055A4"
    free_shipping_threshold = 59.90
    standard_shipping_cost = 5.99
    courier = "GLS / DHL / InPost"


class TennisPointScraper(ShopifyBaseScraper):
    """Scraper for Tennis-Point Italia (tennis-point.it) — #1 European specialist for Tennis & Padel."""

    store_id = "tennis_point"
    store_name = "Tennis-Point"
    base_url = "https://www.tennis-point.it"
    rating = 4.1
    review_count = 9200
    formatted_review_count = "9,2K"
    card_theme = "white"
    accent_color = "#E30613"
    free_shipping_threshold = 59.0
    standard_shipping_cost = 5.99
    courier = "DHL / UPS"


class BasketballStoreScraper(ShopifyBaseScraper):
    """Scraper for Basketball Store (basketballstore.net) — #1 Italian specialist for Basketball & NBA gear."""

    store_id = "basketballstore"
    store_name = "Basketball Store"
    base_url = "https://www.basketballstore.net"
    rating = 4.9
    review_count = 474
    formatted_review_count = "474"
    card_theme = "dark"
    accent_color = "#FF6B00"
    free_shipping_threshold = 50.0
    standard_shipping_cost = 6.90
    courier = "BRT / UPS / Poste"


class NonSoloSportScraper(ShopifyBaseScraper):
    """Scraper for NonSoloSport (nonsolosport.it) — Italian omnichannel multisport & footwear retailer."""

    store_id = "nonsolosport"
    store_name = "NonSoloSport"
    base_url = "https://www.nonsolosport.it"
    rating = 4.5
    review_count = 5300
    formatted_review_count = "5,3K"
    card_theme = "white"
    accent_color = "#1D1D1B"
    free_shipping_threshold = 89.99
    standard_shipping_cost = 5.00
    courier = "BRT"


class IntersportScraper(ShopifyBaseScraper):
    """Scraper for Intersport Italia (intersport.it) — International multisport group across Running, Calcio, Sci, Basket, Ciclismo."""

    store_id = "intersport"
    store_name = "Intersport Italia"
    base_url = "https://www.intersport.it"
    rating = 4.3
    review_count = 1200
    formatted_review_count = "1,2K"
    card_theme = "white"
    accent_color = "#E2001A"
    free_shipping_threshold = 59.0
    standard_shipping_cost = 5.90
    courier = "GLS / BRT"


class BshopzoneScraper(ShopifyBaseScraper):
    """Scraper for Bshopzone (bshopzone.it) — Italian Outdoor, Climbing, Trail Running & Ski-Mountaineering specialist."""

    store_id = "bshopzone"
    store_name = "Bshopzone"
    base_url = "https://www.bshopzone.it"
    rating = 4.5
    review_count = 390
    formatted_review_count = "390"
    card_theme = "white"
    accent_color = "#2E7D32"
    free_shipping_threshold = 100.0
    standard_shipping_cost = 10.00
    courier = "BRT / SDA / GLS"
