import re
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
from fitmatch.models import Offer, MatchedProductGroup

KNOWN_BRANDS = [
    "nike", "adidas", "asics", "brooks", "hoka", "on", "saucony", "puma",
    "new balance", "mizuno", "under armour", "salomon", "altra", "decathlon",
    "kalenji", "kiprun", "garmin", "polar", "suunto", "la sportiva", "scarpa"
]

TECH_PREFIXES = {
    "air", "zoom", "air zoom", "gel", "react", "fuelcell", "fresh foam",
    "flyknit", "hovr", "cloud", "boost"
}

STOPWORDS = {
    "scarpe", "scarpa", "running", "corsa", "sneakers", "calzature", "uomo",
    "donna", "unisex", "bambino", "bambina", "junior", "ragazzo", "ragazza",
    "m", "w", "men", "women", "mens", "womens", "wmns", "trail", "asfalto",
    "per", "di", "con", "e", "the", "in", "de", "ed", "da"
}


class ProductNormalizer:
    """Normalizes titles and clusters offers of the same product across stores."""

    @staticmethod
    def extract_gender(title: str, url: str = "") -> str:
        """Detect gender category from text or URL."""
        combined = f"{title} {url}".lower()
        if re.search(r"\b(bambin[oi]|junior|jr|kids?|boy|girl)\b", combined):
            return "Junior"
        if re.search(r"\b(donna|women|womens|wmns|\bw\b)\b", combined):
            return "Donna"
        if re.search(r"\b(uomo|men|mens|\bm\b)\b", combined):
            return "Uomo"
        return "Unisex"

    @staticmethod
    def extract_brand(title: str, existing_brand: Optional[str] = None) -> Optional[str]:
        if existing_brand and existing_brand.lower() in KNOWN_BRANDS:
            return existing_brand.capitalize()
        lower_title = title.lower()
        for b in sorted(KNOWN_BRANDS, key=len, reverse=True):
            if re.search(rf"\b{re.escape(b)}\b", lower_title):
                return b.title()
        return existing_brand.capitalize() if existing_brand else None

    @classmethod
    def clean_title(cls, title: str) -> Tuple[str, Optional[str]]:
        """Splits off colorway/descriptions and strips noise words."""
        # Split on dash, pipe or slash that separates model from color description
        parts = re.split(r"\s+[-–—|]\s+", title, maxsplit=1)
        base = parts[0]
        colorway = parts[1].strip() if len(parts) > 1 else None

        # Clean noise characters
        text = base.lower()
        text = re.sub(r"\(.*?\)", "", text)
        text = re.sub(r"[^\w\s]", " ", text)

        tokens = text.split()
        cleaned_tokens = [
            t for t in tokens
            if t not in STOPWORDS and not re.match(r"^\d{6,}$", t)
        ]
        return " ".join(cleaned_tokens).strip(), colorway

    @classmethod
    def extract_cluster_key(cls, offer: Offer) -> str:
        """Generates a key for grouping identical or near-identical products."""
        brand = cls.extract_brand(offer.title, offer.brand) or "Generic"
        gender = cls.extract_gender(offer.title, offer.url)
        cleaned_base, _ = cls.clean_title(offer.title)

        words = cleaned_base.split()
        # Remove brand name from tokens
        words = [w for w in words if w.lower() != brand.lower()]

        # Remove tech prefixes like 'air', 'zoom' to align 'Air Zoom Pegasus 42' with 'Pegasus 42'
        filtered_words = []
        for w in words:
            if w in TECH_PREFIXES and len(words) > 2:
                continue
            filtered_words.append(w)

        # Retain model tokens (e.g., 'pegasus 42', 'pegasus premium')
        model_key = " ".join(filtered_words[:2]) if filtered_words else "general"
        return f"{brand.lower()} {model_key} [{gender}]".strip()

    @classmethod
    def group_offers(cls, offers: List[Offer]) -> List[MatchedProductGroup]:
        """Group offers from different stores into consolidated matched product cards."""
        clusters: Dict[str, List[Offer]] = defaultdict(list)

        for offer in offers:
            key = cls.extract_cluster_key(offer)
            clusters[key].append(offer)

        groups: List[MatchedProductGroup] = []

        for key, cluster_offers in clusters.items():
            # Pick best title
            sample_offer = max(cluster_offers, key=lambda o: len(o.title))
            brand = cls.extract_brand(sample_offer.title, sample_offer.brand)
            gender = cls.extract_gender(sample_offer.title, sample_offer.url)

            # Clean canonical name
            cleaned_base, _ = cls.clean_title(sample_offer.title)
            canonical = f"{brand} {cleaned_base.title()}" if brand and brand.lower() not in cleaned_base.lower() else cleaned_base.title()
            if gender in ("Donna", "Junior"):
                canonical += f" ({gender})"

            sorted_offers = sorted(cluster_offers, key=lambda o: o.price)
            image = next((o.image_url for o in cluster_offers if o.image_url), None)

            groups.append(
                MatchedProductGroup(
                    canonical_name=canonical,
                    brand=brand,
                    image_url=image,
                    offers=sorted_offers
                )
            )

        # Sort: products with offers from distinct stores first, then by cross-store savings
        groups.sort(
            key=lambda g: (
                len({o.store_id for o in g.offers}) > 1,
                g.cross_store_savings or 0,
                len(g.offers)
            ),
            reverse=True
        )
        return groups
