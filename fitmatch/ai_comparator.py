import os
import re
import json
import logging
import ssl
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import certifi
from fitmatch.service import ComparisonService
from fitmatch.models import MatchedProductGroup, Offer

logger = logging.getLogger("fitmatch.ai_comparator")

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "meta-llama/llama-3.3-70b-instruct")
OPENROUTER_BACKUP_MODEL = "meta-llama/llama-3.1-8b-instruct"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


class ModelSpecs(BaseModel):
    name: str
    brand: Optional[str] = None
    drop_mm: Optional[int] = None
    weight_g: Optional[int] = None
    cushioning: Optional[str] = None
    midsole: Optional[str] = None
    plate: Optional[str] = None
    ideal_use: Optional[str] = None
    target_runner: Optional[str] = None
    pros: List[str] = Field(default_factory=list)
    cons: List[str] = Field(default_factory=list)


class StoreOfferBrief(BaseModel):
    store_name: str
    price: float
    original_price: Optional[float] = None
    url: str
    is_free_shipping: bool = False
    total_price: float = 0.0


class ModelMarketData(BaseModel):
    model_name: str
    brand: Optional[str] = None
    best_price: Optional[float] = None
    highest_price: Optional[float] = None
    best_store: Optional[str] = None
    image_url: Optional[str] = None
    total_offers: int = 0
    cross_store_savings: Optional[float] = None
    top_offers: List[StoreOfferBrief] = Field(default_factory=list)


class ModelComparisonResponse(BaseModel):
    model_a_specs: ModelSpecs
    model_b_specs: ModelSpecs
    model_a_market: ModelMarketData
    model_b_market: ModelMarketData
    key_differences: List[str] = Field(default_factory=list)
    verdict_summary: str = ""
    winner_for_value: str = ""
    winner_for_performance: str = ""
    price_delta: Optional[float] = None
    source: str = "openrouter_llama_70b"


# Heuristic specs catalog for instant offline fallback
LOCAL_SPECS_DATABASE = {
    "pegasus": {
        "name": "Nike Pegasus 41", "brand": "Nike", "drop_mm": 10, "weight_g": 285,
        "cushioning": "Bilanciato & Elastico", "midsole": "ReactX + 2x Air Zoom",
        "plate": "Nessuna", "ideal_use": "Daily trainer versatile per qualsiasi distanza",
        "target_runner": "Runner neutri di ogni livello per allenamenti quotidiani",
        "pros": ["Eccezionale longevità del battistrada", "Grande versatilità di ritmi", "Ottimo prezzo"],
        "cons": ["Meno ammortizzata oltre gli 80kg", "Non pensata per gare veloci"]
    },
    "nimbus": {
        "name": "Asics Gel Nimbus 26", "brand": "Asics", "drop_mm": 8, "weight_g": 305,
        "cushioning": "Massimo Ammortizzamento", "midsole": "FF BLAST+ ECO + PureGEL",
        "plate": "Nessuna", "ideal_use": "Lunghi su asfalto, lenti rigeneranti e protezione",
        "target_runner": "Runner medi o pesanti (>75kg) e chi vuole proteggere ginocchia e schiena",
        "pros": ["Morbidezza e comfort ai vertici della categoria", "Tomaia in knit premium", "Elevata stabilità"],
        "cons": ["Peso più elevato", "Meno reattiva a ritmi sostenuti (<4:20 min/km)"]
    },
    "clifton": {
        "name": "Hoka Clifton 9", "brand": "Hoka", "drop_mm": 5, "weight_g": 248,
        "cushioning": "Morbido & Leggero", "midsole": "CMEVA sagomata a compressione",
        "plate": "Nessuna", "ideal_use": "Allenamenti quotidiani a ritmo medio ed endurance",
        "target_runner": "Runner che cercano geometria Meta-Rocker e basso drop",
        "pros": ["Rapporto peso/ammortizzamento eccezionale", "Rullata fluida con Meta-Rocker", "Grande comodità"],
        "cons": ["Drop basso (5mm) richiede adattamento ai polpacci", "Tomaia calda d'estate"]
    },
    "ghost": {
        "name": "Brooks Ghost 16", "brand": "Brooks", "drop_mm": 12, "weight_g": 270,
        "cushioning": "Bilanciato & Neutro", "midsole": "DNA LOFT v3 con infusione di azoto",
        "plate": "Nessuna", "ideal_use": "Daily trainer per chi atterra di tallone",
        "target_runner": "Runner con appoggio tallonare che amano calzata tradizionale",
        "pros": ["Transizione tacco-punta fluida", "Intersuola morbida e leggera con azoto", "Affidabilità comprovata"],
        "cons": ["Drop alto (12mm) non adatto a chi corre d'avampiede", "Design sobrio"]
    },
    "novablast": {
        "name": "Asics Novablast 4", "brand": "Asics", "drop_mm": 8, "weight_g": 260,
        "cushioning": "Energetico & Elastico", "midsole": "FF BLAST+ ECO a geometria trampolino",
        "plate": "Nessuna", "ideal_use": "Ritmi medi, corse progressive e lunghi brillanti",
        "target_runner": "Runner neutri alla ricerca di scarpa scattante senza piastra",
        "pros": ["Ritorno di energia esuberante", "Geometria trampolino molto divertente", "Peso contenuto"],
        "cons": ["Stabilità laterale ridotta per iperpronatori", "Fondo scivoloso su bagnato"]
    },
    "alphafly": {
        "name": "Nike Alphafly 3", "brand": "Nike", "drop_mm": 8, "weight_g": 218,
        "cushioning": "Massima Reattività da Gara", "midsole": "ZoomX integrale + doppio Air Pod",
        "plate": "Fibra di Carbonio Flyplate a tutta lunghezza", "ideal_use": "Gara maratona e mezza maratona",
        "target_runner": "Podisti evoluti con buona tecnica alla ricerca del record personale",
        "pros": ["Efficienza energetica impareggiabile", "ZoomX continuo per transizioni rapide", "Leggerezza estrema"],
        "cons": ["Prezzo molto elevato", "Durata limitata ai chilometri di gara", "Richiede caviglie forti"]
    },
    "forerunner 165": {
        "name": "Garmin Forerunner 165", "brand": "Garmin", "drop_mm": 0, "weight_g": 39,
        "cushioning": "Smartwatch GPS Corsa", "midsole": "Display AMOLED touchscreen 1.2 pollici",
        "plate": "Sensore cardio Elevate Gen 4", "ideal_use": "Monitoraggio corsa, passo, recupero e sonno",
        "target_runner": "Runner amatori e principianti che vogliono metriche Garmin con display AMOLED",
        "pros": ["Display AMOLED brillante", "Prezzo competitivo per un Garmin AMOLED", "Autonomia fino a 11 giorni"],
        "cons": ["Niente mappe cartografiche offline", "GPS a singola frequenza (non multibanda)"]
    },
    "forerunner 265": {
        "name": "Garmin Forerunner 265", "brand": "Garmin", "drop_mm": 0, "weight_g": 47,
        "cushioning": "Smartwatch GPS Avanzato", "midsole": "Display AMOLED touchscreen + GPS Multibanda",
        "plate": "Training Readiness & Metriche Avanzate", "ideal_use": "Triathlon, maratona e atleti multisport",
        "target_runner": "Atleti intermedi ed evoluti che necessitano di Training Readiness e GPS a doppia frequenza",
        "pros": ["GPS Multibanda ad altissima precisione", "Metrica Training Readiness completa", "Supporto Triathlon"],
        "cons": ["Prezzo più alto del 165", "Nessuna cartografia topografica completa (riservata al 965)"]
    }
}


class AIModelComparator:
    """Intelligent engine for side-by-side technical and live pricing comparisons of sports gear."""

    def __init__(self, service: Optional[ComparisonService] = None):
        self.service = service or ComparisonService()

    def compare_models(self, model_a_query: str, model_b_query: str) -> ModelComparisonResponse:
        """Compare two models by fetching technical specs and live multi-store prices."""
        # 1. Fetch live market data for Model A & Model B concurrently
        market_a = self._fetch_market_data(model_a_query)
        market_b = self._fetch_market_data(model_b_query)

        # 2. Extract technical specs and analysis via LLM (with heuristic fallback)
        specs_a, specs_b, key_diffs, verdict, winner_perf, source = self._generate_specs_and_analysis(
            model_a_query, model_b_query
        )

        # 3. Calculate price delta and value winner
        price_delta = None
        winner_value = specs_a.name
        if market_a.best_price and market_b.best_price:
            price_delta = round(abs(market_a.best_price - market_b.best_price), 2)
            if market_a.best_price < market_b.best_price:
                diff = market_b.best_price - market_a.best_price
                winner_value = f"{specs_a.name} (risparmi {diff:.2f} € rispetto a {specs_b.name})"
            elif market_b.best_price < market_a.best_price:
                diff = market_a.best_price - market_b.best_price
                winner_value = f"{specs_b.name} (risparmi {diff:.2f} € rispetto a {specs_a.name})"
            else:
                winner_value = "Prezzi identici: la scelta dipende solo dalle tue preferenze tecniche."

        return ModelComparisonResponse(
            model_a_specs=specs_a,
            model_b_specs=specs_b,
            model_a_market=market_a,
            model_b_market=market_b,
            key_differences=key_diffs,
            verdict_summary=verdict,
            winner_for_value=winner_value,
            winner_for_performance=winner_perf,
            price_delta=price_delta,
            source=source
        )

    def _fetch_market_data(self, query: str) -> ModelMarketData:
        """Fetch live product pricing and stores for a query."""
        try:
            res = self.service.search_and_compare(query=query, limit_per_store=4, use_cache=True)
            matched = res.matched_products
            if not matched:
                return ModelMarketData(model_name=query, total_offers=0)

            top_prod = matched[0]
            top_offers_brief = [
                StoreOfferBrief(
                    store_name=o.store_name,
                    price=o.price,
                    original_price=o.original_price,
                    url=o.url,
                    is_free_shipping=o.is_free_shipping,
                    total_price=o.total_price
                )
                for o in top_prod.offers[:5]
            ]

            return ModelMarketData(
                model_name=top_prod.canonical_name,
                brand=top_prod.brand,
                best_price=top_prod.best_price,
                highest_price=top_prod.highest_price,
                best_store=top_prod.best_offer.store_name if top_prod.best_offer else None,
                image_url=top_prod.image_url,
                total_offers=len(top_prod.offers),
                cross_store_savings=top_prod.cross_store_savings,
                top_offers=top_offers_brief
            )
        except Exception as e:
            logger.error(f"[AIModelComparator] Error fetching market data for {query}: {e}")
            return ModelMarketData(model_name=query, total_offers=0)

    def _generate_specs_and_analysis(self, query_a: str, query_b: str):
        """Invoke OpenRouter LLM or fallback to local knowledge base."""
        if OPENROUTER_API_KEY:
            try:
                import urllib.request
                ctx = ssl.create_default_context(cafile=certifi.where())

                system_prompt = (
                    "Sei un esperto biomeccanico e tester professionista di calzature e tecnologia sportiva per 'FitMatch'. "
                    "Analizza con la massima precisione scientifica e tecnica i due modelli richiesti dall'utente. "
                    "Rispondi ESCLUSIVAMENTE con un JSON valido con questa esatta struttura:\n"
                    "{\n"
                    "  \"model_a\": {\n"
                    "    \"name\": \"Nome completo modello A\",\n"
                    "    \"brand\": \"Brand\",\n"
                    "    \"drop_mm\": int o null,\n"
                    "    \"weight_g\": int o null,\n"
                    "    \"cushioning\": \"es. Massimo / Bilanciato / Reattivo\",\n"
                    "    \"midsole\": \"mescola e tecnologie\",\n"
                    "    \"plate\": \"Nessuna / Carbonio / Nylon\",\n"
                    "    \"ideal_use\": \"utilizzo principale\",\n"
                    "    \"target_runner\": \"profilo podista ideale\",\n"
                    "    \"pros\": [\"pro 1\", \"pro 2\", \"pro 3\"],\n"
                    "    \"cons\": [\"contro 1\", \"contro 2\"]\n"
                    "  },\n"
                    "  \"model_b\": {\n"
                    "    \"name\": \"Nome completo modello B\",\n"
                    "    \"brand\": \"Brand\",\n"
                    "    \"drop_mm\": int o null,\n"
                    "    \"weight_g\": int o null,\n"
                    "    \"cushioning\": \"es. Massimo / Bilanciato / Reattivo\",\n"
                    "    \"midsole\": \"mescola e tecnologie\",\n"
                    "    \"plate\": \"Nessuna / Carbonio / Nylon\",\n"
                    "    \"ideal_use\": \"utilizzo principale\",\n"
                    "    \"target_runner\": \"profilo podista ideale\",\n"
                    "    \"pros\": [\"pro 1\", \"pro 2\", \"pro 3\"],\n"
                    "    \"cons\": [\"contro 1\", \"contro 2\"]\n"
                    "  },\n"
                    "  \"key_differences\": [\"differenza 1\", \"differenza 2\", \"differenza 3\"],\n"
                    "  \"verdict_summary\": \"sintesi chiara in 2 frasi di chi dovrebbe comprare cosa\",\n"
                    "  \"winner_for_performance\": \"nome del modello e motivo\"\n"
                    "}"
                )

                user_prompt = f"Confronta dettagliatamente il modello A ('{query_a}') con il modello B ('{query_b}')."

                payload = {
                    "model": OPENROUTER_MODEL,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    "temperature": 0.1,
                    "max_tokens": 1200
                }

                req = urllib.request.Request(
                    OPENROUTER_URL,
                    headers={
                        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
                        "Content-Type": "application/json",
                        "HTTP-Referer": "https://fitmatch.it",
                        "X-Title": "FitMatch Price Comparator"
                    },
                    data=json.dumps(payload).encode("utf-8")
                )

                resp = urllib.request.urlopen(req, context=ctx, timeout=14)
                data = json.loads(resp.read().decode("utf-8"))
                content = data["choices"][0]["message"]["content"]

                # Extract JSON if wrapped in markdown blocks
                raw_json = content
                if "```json" in content:
                    raw_json = content.split("```json")[1].split("```")[0].strip()
                elif "```" in content:
                    raw_json = content.split("```")[1].split("```")[0].strip()

                parsed = json.loads(raw_json)
                specs_a = ModelSpecs(**parsed["model_a"])
                specs_b = ModelSpecs(**parsed["model_b"])
                key_diffs = parsed.get("key_differences", [])
                verdict = parsed.get("verdict_summary", "")
                winner_perf = parsed.get("winner_for_performance", "")
                return specs_a, specs_b, key_diffs, verdict, winner_perf, "openrouter_llama_70b"

            except Exception as e:
                logger.warning(f"[AIModelComparator] OpenRouter call failed: {e}. Falling back to local heuristic.")

        # Local Heuristic Fallback
        specs_a = self._get_heuristic_spec(query_a)
        specs_b = self._get_heuristic_spec(query_b)
        key_diffs = [
            f"{specs_a.name} presenta un drop di {specs_a.drop_mm or 'N/D'} mm, mentre {specs_b.name} di {specs_b.drop_mm or 'N/D'} mm.",
            f"Ammortizzamento: {specs_a.cushioning} ({specs_a.midsole}) contro {specs_b.cushioning} ({specs_b.midsole}).",
            f"Peso stimato: circa {specs_a.weight_g or 'N/D'}g per {specs_a.name} vs {specs_b.weight_g or 'N/D'}g per {specs_b.name}."
        ]
        verdict = (
            f"Scegli {specs_a.name} se cerchi {specs_a.ideal_use.lower() if specs_a.ideal_use else 'versatilità'}. "
            f"Opta invece per {specs_b.name} se il tuo obiettivo principale è {specs_b.ideal_use.lower() if specs_b.ideal_use else 'il massimo comfort'}."
        )
        winner_perf = specs_a.name if (specs_a.weight_g or 300) < (specs_b.weight_g or 300) else specs_b.name
        return specs_a, specs_b, key_diffs, verdict, winner_perf, "local_heuristic"

    def _get_heuristic_spec(self, query: str) -> ModelSpecs:
        """Match query against local knowledge base."""
        q = query.lower()
        for key, data in LOCAL_SPECS_DATABASE.items():
            if key in q:
                return ModelSpecs(**data)

        # Generic sports gear fallback
        return ModelSpecs(
            name=query.title(),
            brand="Sport Tech",
            drop_mm=8,
            weight_g=280,
            cushioning="Standard",
            midsole="Mescola ammortizzante tecnica",
            plate="Nessuna",
            ideal_use="Allenamento e attività sportiva",
            target_runner="Sportivi di livello amatoriale",
            pros=["Comfort affidabile", "Costruzione resistente"],
            cons=["Caratteristiche non specialistiche"]
        )
