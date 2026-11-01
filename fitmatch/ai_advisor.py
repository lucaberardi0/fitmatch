import os
import re
import json
import logging
import ssl
from typing import List, Dict, Any, Optional

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import certifi
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.models import MatchedProductGroup, Offer

logger = logging.getLogger("fitmatch.ai_advisor")

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "meta-llama/llama-3.3-70b-instruct")
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


class AIShoppingAdvisor:
    """AI Assistant that interprets complex natural-language shopper needs,

    selects optimal technical sports gear models using Llama 3.3 70B and biomechanical rules,
    and finds the best multi-store deals.
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

        # 1. Budget extraction
        max_price = None
        price_match = re.search(r"(?:sotto\s*i?|meno\s*di|max|massimo|budget\s*di?)\s*(\d+)\s*(?:€|euro)?", text)
        if price_match:
            max_price = float(price_match.group(1))

        # 2. Size extraction
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

        # 4. Weight analysis
        weight_kg = None
        weight_match = re.search(r"(\d{2,3})\s*(?:kg|chili)", text)
        if weight_match:
            weight_kg = int(weight_match.group(1))

        # 5. Surface
        surface = "asfalto"
        if re.search(r"\b(trail|sterrato|fango|montagna|sentier[oi]|bosco)\b", text):
            surface = "trail"
        elif re.search(r"\b(pista|tartan)\b", text):
            surface = "pista"

        is_waterproof = bool(re.search(r"\b(impermeabil[ei]|gtx|gore[\s-]tex|pioggia)\b", text))
        is_speed = bool(re.search(r"\b(veloc[ei]|reattiv[ae]|gara|maratona|mezza|ripetute|piastra)\b", text))
        is_cushion = bool(re.search(r"\b(ammortizzat[ae]|morbida?|comod[ae]|protettiv[ae]|ginocchi[ao]|schiena|tendin[ei]|fascite)\b", text))

        is_gps = bool(re.search(r"\b(orolog[io]|smartwatch|gps|cardio|garmin|polar|suunto|coros|ciclocomputer)\b", text))
        is_eyewear = bool(re.search(r"\b(occhial[ie]|lenti|oakley|sole|prizm)\b", text))
        is_hydration = bool(re.search(r"\b(zain[oi]|gilet|flask|borracci[ae]|idratazione|camelbak)\b", text))
        is_recovery = bool(re.search(r"\b(theragun|pistola|massaggi[ao]|recupero|contrattur[ae]|massaggiante)\b", text))
        is_nutrition = bool(re.search(r"\b(gel|barrett[ae]|integrator[ei]|enervit|sali|maltodestrin[ae]|nutrizione)\b", text))

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
        # 1. Try LLM consultation first if OpenRouter is configured
        llm_result = self._try_llm_consultation(user_query)
        if llm_result:
            return llm_result

        # 2. Heuristic fallback
        return self._advise_heuristic(user_query)

    def _try_llm_consultation(self, user_query: str) -> Optional[Dict[str, Any]]:
        """Query Llama 3.3 70B for biomechanical reasoning and targeted models."""
        if not OPENROUTER_API_KEY:
            return None

        try:
            import urllib.request
            ctx = ssl.create_default_context(cafile=certifi.where())

            system_prompt = (
                "Sei un Coach e Biomeccanico sportivo d'élite per 'FitMatch'. "
                "L'utente ti spiega le sue caratteristiche fisiche (peso, altezza, appoggio, eventuali patologie come fascite plantare, tendinite, dolori alle ginocchia), "
                "i suoi obiettivi sportivi e il budget.\n"
                "Rispondi ESCLUSIVAMENTE con un JSON valido con questa struttura:\n"
                "{\n"
                "  \"category_name\": \"es. Massimo Ammortizzamento & Protezione Articolare\",\n"
                "  \"category_description\": \"descrizione chiara della categoria tecnica\",\n"
                "  \"biomechanical_reasoning\": \"Spiegazione biomeccanica dettagliata e cordiale in 2-3 frasi, evidenziando il carico articolare e la motivazione delle scelte tecniche.\",\n"
                "  \"recommended_models\": [\"modello 1 esatto (es. asics gel nimbus 26)\", \"modello 2 (es. hoka bondi 8)\", \"modello 3 (es. brooks glycerin 21)\"],\n"
                "  \"parsed_profile\": {\n"
                "    \"weight_kg\": int o null,\n"
                "    \"surface\": \"asfalto | trail | pista\",\n"
                "    \"gender\": \"Uomo | Donna | Unisex\",\n"
                "    \"size\": \"taglia stringa o null (es. 43)\",\n"
                "    \"max_price\": float o null\n"
                "  }\n"
                "}"
            )

            payload = {
                "model": OPENROUTER_MODEL,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_query}
                ],
                "temperature": 0.1,
                "max_tokens": 800
            }

            req = urllib.request.Request(
                OPENROUTER_URL,
                headers={
                    "Authorization": f"Bearer {OPENROUTER_API_KEY}",
                    "Content-Type": "application/json",
                    "HTTP-Referer": "https://fitmatch.it",
                    "X-Title": "FitMatch AI Advisor"
                },
                data=json.dumps(payload).encode("utf-8")
            )

            resp = urllib.request.urlopen(req, context=ctx, timeout=12)
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]

            raw_json = content
            if "```json" in content:
                raw_json = content.split("```json")[1].split("```")[0].strip()
            elif "```" in content:
                raw_json = content.split("```")[1].split("```")[0].strip()

            parsed = json.loads(raw_json)
            models = parsed.get("recommended_models", [])
            profile = parsed.get("parsed_profile", {})

            # Collect live offers for recommended models
            recommendations = self._fetch_model_offers(
                models=models,
                size=profile.get("size"),
                max_price=profile.get("max_price"),
                gender=profile.get("gender", "Unisex")
            )

            return {
                "user_profile": {
                    "raw_query": user_query,
                    "max_price": profile.get("max_price"),
                    "size": profile.get("size"),
                    "gender": profile.get("gender", "Unisex"),
                    "weight_kg": profile.get("weight_kg"),
                    "surface": profile.get("surface", "asfalto"),
                    "category": parsed.get("category_name", "Running & Sport Gear")
                },
                "category_name": parsed.get("category_name", "Consulenza Biomeccanica IA"),
                "category_description": parsed.get("category_description", ""),
                "biomechanical_reasoning": parsed.get("biomechanical_reasoning", ""),
                "recommendations": recommendations[:5],
                "source": "openrouter_llama_70b"
            }

        except Exception as e:
            logger.warning(f"[AIShoppingAdvisor] LLM consultation failed: {e}. Falling back to heuristic.")
            return None

    def _fetch_model_offers(
        self,
        models: List[str],
        size: Optional[str] = None,
        max_price: Optional[float] = None,
        gender: Optional[str] = "Unisex"
    ) -> List[Dict[str, Any]]:
        """Fetch live offers across stores for a list of target models."""
        recommendations = []
        for model in models[:3]:
            res = self.service.search_and_compare(
                query=model,
                size=size,
                limit_per_store=4,
                use_cache=True
            )
            for group in res.matched_products:
                if max_price and group.best_price and group.best_price > max_price:
                    continue
                if gender == "Donna" and "(Donna)" not in group.canonical_name and "Donna" not in group.canonical_name:
                    continue

                best_offer = group.best_offer
                if best_offer:
                    if best_offer.price < 20.0:
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
        recommendations.sort(key=lambda r: (r["best_price"] or 999))
        return recommendations

    def _advise_heuristic(self, user_query: str) -> Dict[str, Any]:
        """Local rule-based heuristic advisor fallback."""
        params = self.parse_user_request(user_query)
        cat_info = self.KNOWLEDGE_BASE[params["category"]]
        target_models = list(cat_info["models"])

        if params["is_waterproof"]:
            target_models = [f"{m} gtx" for m in target_models]

        recommendations = self._fetch_model_offers(
            models=target_models,
            size=params["size"],
            max_price=params["max_price"],
            gender=params["gender"]
        )

        reasons = []
        if params["weight_kg"]:
            reasons.append(f"Per un peso di **{params['weight_kg']} kg**, il carico articolare all'impatto supera i {params['weight_kg'] * 3} kg: occorre un'intersuola protettiva con elevato assorbimento dello shock.")
        if params["surface"] == "asfalto":
            reasons.append("L'asfalto è la superficie più traumatica per i tendini: abbiamo selezionato schiume tecniche ad alto smorzamento.")
        elif params["surface"] == "trail":
            reasons.append("Per lo sterrato abbiamo privilegiato suole artigliate e protezione dell'avampiede.")
        if params["max_price"]:
            reasons.append(f"Tutti i modelli rispettano il budget di **{params['max_price']:.0f} €**.")
        if params["size"]:
            reasons.append(f"Le offerte mostrate verificano la presenza della taglia **{params['size']}** in magazzino.")

        return {
            "user_profile": params,
            "category_name": cat_info["name"],
            "category_description": cat_info["description"],
            "biomechanical_reasoning": " ".join(reasons),
            "recommendations": recommendations[:5],
            "source": "local_heuristic"
        }
