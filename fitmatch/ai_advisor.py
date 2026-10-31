import re
from typing import List, Dict, Any, Optional
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.models import MatchedProductGroup, Offer


class AIShoppingAdvisor:
    """AI Assistant that interprets complex natural-language shopper needs,

    selects optimal technical sports gear models, and finds the best multi-store deals.
    """

    KNOWLEDGE_BASE = {
        "max_cushion": {
            "name": "Massimo Ammortizzamento & Protezione",
            "description": "Suola ad alto assorbimento d'impatto, ideale per runner sopra i 75-80kg, lunghe distanze su asfalto o per chi vuole proteggere ginocchia e schiena.",
            "models": ["hoka bondi", "asics gel nimbus", "brooks glycerin", "hoka clifton"]
        },
        "daily_trainer": {
            "name": "Daily Trainer Polivalente",
            "description": "Scarpa equilibrata, resistente e versatile per allenamenti quotidiani di qualsiasi distanza a ritmo medio.",
            "models": ["nike pegasus", "brooks ghost", "asics cumulus"]
        },
        "speed_race": {
            "name": "Velocità, Reattività & Gara",
            "description": "Leggere e scattanti, con schiume reattive e/o piastra per migliorare il ritorno energetico in mezza maratona o ripetute veloci.",
            "models": ["adidas adizero", "asics magic speed", "nike vaporfly", "brooks hyperion"]
        },
        "trail_offroad": {
            "name": "Trail Running & Sterrato",
            "description": "Battistrada tassellato e tomaia rinforzata per trazione e stabilità su rocce, fango e sentieri irregolari.",
            "models": ["hoka speedgoat", "brooks cascadia", "salomon xa pro", "asics trabuco"]
        },
        "gps_watch": {
            "name": "GPS Smartwatch & Cardiofrequenzimetri",
            "description": "Dispositivi GPS per monitorare frequenza cardiaca, passo al chilometro, VO2 max, navigazione percorsi e tempi di recupero.",
            "models": ["garmin forerunner", "garmin fenix", "garmin edge", "polar vantage", "suunto"]
        },
        "hydration_gear": {
            "name": "Zaini Idratazione & Gilet Trail",
            "description": "Gilet ergonomici traspiranti con borracce morbide (soft flask) integrate per correre in autosufficienza fino alle lunghe distanze.",
            "models": ["salomon active skin", "salomon adv skin", "camelbak"]
        },
        "eyewear": {
            "name": "Occhiali Sportivi Tecnici",
            "description": "Lenti ad alto contrasto (Prizm/fotocromatiche) e montature ultraleggere che non scivolano col sudore.",
            "models": ["oakley radar", "oakley sutro", "bliz"]
        },
        "fitness_recovery": {
            "name": "Fitness & Recupero Muscolare",
            "description": "Dispositivi per massaggio a percussione, allentamento contratture e riscaldamento muscolare rapido.",
            "models": ["theragun", "therabody"]
        },
        "nutrition": {
            "name": "Nutrizione Sportiva & Energetici",
            "description": "Carboidrati a rilascio graduale o istantaneo, gel isotonici e sali minerali per prevenire crampi e cali di glicogeno.",
            "models": ["enervit gel", "enervit", "isocarb"]
        }
    }

    def __init__(self, service: Optional[ComparisonService] = None, db: Optional[Database] = None):
        self.service = service or ComparisonService()
        self.db = db or Database()

    def parse_user_request(self, user_query: str) -> Dict[str, Any]:
        """Extract user constraints: weight, surface, goal, budget, gender."""
        text = user_query.lower()

        # 1. Budget extraction (es. 'sotto i 140€', 'meno di 130 euro', 'max 100€')
        max_price = None
        price_match = re.search(r"(?:sotto\s*i?|meno\s*di|max|massimo|budget\s*di?)\s*(\d+)\s*(?:€|euro)?", text)
        if price_match:
            max_price = float(price_match.group(1))

        # 2. Size extraction (es. 'taglia 43', 'numero 42.5', 'porto il 44', 'taglia M')
        size = None
        size_match = re.search(r"(?:taglia|numero|misura|porto\s*(?:il|la)?)\s*([0-9]{2}(?:[\.,][0-9])?|[xXsSmMlL]{1,3})", text)
        if size_match:
            size = size_match.group(1).replace(",", ".")

        # 3. Gender extraction
        gender = "Unisex"
        if re.search(r"\b(donna|ragazza|femmin[eia]|wmns?)\b", text):
            gender = "Donna"
        elif re.search(r"\b(uomo|ragazzo|maschil[eia]|mens?)\b", text):
            gender = "Uomo"

        # 3. Weight analysis
        weight_kg = None
        weight_match = re.search(r"(\d{2,3})\s*(?:kg|chili)", text)
        if weight_match:
            weight_kg = int(weight_match.group(1))

        # 4. Surface
        surface = "asfalto"
        if re.search(r"\b(trail|sterrato|fango|montagna|sentier[oi]|bosco)\b", text):
            surface = "trail"
        elif re.search(r"\b(pista|tartan)\b", text):
            surface = "pista"

        # 5. Goal / Biomechanical profile or Accessory Request
        is_waterproof = bool(re.search(r"\b(impermeabil[ei]|gtx|gore[\s-]tex|pioggia)\b", text))
        is_speed = bool(re.search(r"\b(veloc[ei]|reattiv[ae]|gara|maratona|mezza|ripetute|piastra)\b", text))
        is_cushion = bool(re.search(r"\b(ammortizzat[ae]|morbida?|comod[ae]|protettiv[ae]|ginocchi[ao]|schiena|tendin[ei])\b", text))

        # Check if accessory is explicitly requested
        is_gps = bool(re.search(r"\b(orolog[io]|smartwatch|gps|cardio|garmin|polar|suunto|coros|ciclocomputer)\b", text))
        is_eyewear = bool(re.search(r"\b(occhial[ie]|lenti|oakley|sole|prizm)\b", text))
        is_hydration = bool(re.search(r"\b(zain[oi]|gilet|flask|borracci[ae]|idratazione|camelbak)\b", text))
        is_recovery = bool(re.search(r"\b(theragun|pistola|massaggi[ao]|recupero|contrattur[ae]|massaggiante)\b", text))
        is_nutrition = bool(re.search(r"\b(gel|barrett[ae]|integrator[ei]|enervit|sali|maltodestrin[ae]|nutrizione)\b", text))

        # Assign category archetype
        if is_gps:
            category = "gps_watch"
        elif is_eyewear:
            category = "eyewear"
        elif is_hydration:
            category = "hydration_gear"
        elif is_recovery:
            category = "fitness_recovery"
        elif is_nutrition:
            category = "nutrition"
        elif surface == "trail":
            category = "trail_offroad"
        elif is_speed and not (weight_kg and weight_kg > 82):
            category = "speed_race"
        elif is_cushion or (weight_kg and weight_kg >= 78):
            category = "max_cushion"
        else:
            category = "daily_trainer"

        return {
            "raw_query": user_query,
            "max_price": max_price,
            "size": size,
            "gender": gender,
            "weight_kg": weight_kg,
            "surface": surface,
            "is_waterproof": is_waterproof,
            "category": category,
        }

    def advise(self, user_query: str) -> Dict[str, Any]:
        """Generate structured AI recommendations with real multi-store price comparisons."""
        params = self.parse_user_request(user_query)
        cat_info = self.KNOWLEDGE_BASE[params["category"]]
        target_models = list(cat_info["models"])

        # Add GTX variant query if waterproof requested
        if params["is_waterproof"]:
            target_models = [f"{m} gtx" for m in target_models]

        recommendations = []
        all_candidate_offers = []

        # Query live stores for the target models with optional size filtering
        for model in target_models[:3]:
            res = self.service.search_and_compare(
                query=model,
                size=params["size"],
                limit_per_store=4,
                use_cache=True
            )
            for group in res.matched_products:
                # Apply budget filter if specified
                if params["max_price"] and group.best_price and group.best_price > params["max_price"]:
                    continue

                # Filter by gender if specific
                if params["gender"] == "Donna" and "(Donna)" not in group.canonical_name and "Donna" not in group.canonical_name:
                    continue

                best_offer = group.best_offer
                if best_offer:
                    # Filter out tiny accessories unless nutrition is explicitly requested
                    min_price_threshold = 2.0 if params["category"] == "nutrition" else 20.0
                    if best_offer.price < min_price_threshold:
                        continue
                    recommendations.append({
                        "product_name": group.canonical_name,
                        "brand": group.brand,
                        "best_price": group.best_price,
                        "best_store": best_offer.store_name,
                        "original_price": best_offer.original_price,
                        "discount_pct": best_offer.discount_pct,
                        "link": best_offer.url,
                        "image_url": group.image_url,
                        "cross_store_savings": group.cross_store_savings,
                        "all_offers": [
                            {"store": o.store_name, "price": o.price, "url": o.url}
                            for o in group.offers
                        ]
                    })

        # Sort recommendations: lowest price and highest discount first
        recommendations.sort(key=lambda r: (r["best_price"] or 999))

        # Biomechanical explanation
        reasons = []
        if params["weight_kg"]:
            reasons.append(f"Per un peso di **{params['weight_kg']} kg**, il carico sulle articolazioni ad ogni atterraggio è di circa {params['weight_kg'] * 3} kg. Ti occorrono scarpe con intersuola generosa per proteggere menischi e colonna.")
        if params["surface"] == "asfalto":
            reasons.append("L'asfalto è la superficie più traumatica: abbiamo selezionato schiume a massimo assorbimento d'urto.")
        elif params["surface"] == "trail":
            reasons.append("Per lo sterrato abbiamo selezionato modelli con suola con grip artigliato e tomaia protettiva anti-sassi.")
        if params["max_price"]:
            reasons.append(f"Tutti i modelli proposti rispettano il tuo budget di **{params['max_price']:.0f} €**.")
        if params["size"]:
            reasons.append(f"Tutte le offerte visualizzate hanno la taglia **{params['size']}** effettivamente disponibile in stock.")

        return {
            "user_profile": params,
            "category_name": cat_info["name"],
            "category_description": cat_info["description"],
            "biomechanical_reasoning": " ".join(reasons),
            "recommendations": recommendations[:5]
        }
