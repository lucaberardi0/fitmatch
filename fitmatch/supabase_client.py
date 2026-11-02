import os
import json
import logging
import ssl
import time
import uuid
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
import certifi

from fitmatch.models import Offer, STORE_SHIPPING_RULES, clean_image_url

logger = logging.getLogger("fitmatch.supabase")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://goopfdvnqhdmsoutkldp.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdvb3BmZHZucWhkbXNvdXRrbGRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MzA3MzIsImV4cCI6MjEwOTEwNjczMn0.iXpBGsAORT0-1oFtQh-PAmgfwkGRVTyekalZoS2_Zyo")

STORE_METADATA = {
    "cisalfa": {
        "name": "Cisalfa Sport",
        "base_url": "https://www.cisalfasport.it",
        "rating": "4.8",
        "review_count": "18.2k recensioni",
        "description": "Leader italiano nella vendita di abbigliamento, calzature e attrezzature sportive dei migliori marchi mondiali.",
        "full_description": "Fondata nel 1977, Cisalfa Sport è la catena di articoli sportivi numero uno in Italia con oltre 160 megastore fisici. Offre la massima sicurezza per gli acquisti con garanzia ufficiale, prodotti 100% autentici dei top brand (Nike, adidas, Asics, Hoka) e la possibilità di effettuare resi e cambi sia online che comodamente in qualsiasi punto vendita sul territorio nazionale.",
        "badges": ["Rivenditore Ufficiale", "160+ Negozi in Italia", "Reso 30 Giorni", "Garanzia Italia"],
        "highlights": ["160+ Punti Vendita Fisici", "Reso Facile in Negozio", "Top Brand Certificati"],
        "location": "Sede & Magazzino Centrale: Curno (BG), Italia",
        "shipping_info": "Spedizione standard 9,90 € • Gratuita da 99,00 € (o gratis con ritiro in negozio)",
        "shipping_rule": {"standard": 9.90, "free_threshold": 99.0, "label": "Gratis da 99 €", "courier": "BRT / GLS"},
        "return_policy": "30 giorni per reso online o in qualsiasi negozio",
        "rating_breakdown": {"score": 4.8, "positive_pct": "96%", "review_count": "18.200+", "platform": "Trustpilot / Feedaty"}
    },
    "maxisport": {
        "name": "Maxi Sport",
        "base_url": "https://www.maxisport.com",
        "rating": "4.9",
        "review_count": "24.5k recensioni",
        "description": "Oltre 30 anni di passione sport & street style con le ultime novità running, trail e moda sportswear.",
        "full_description": "Maxi Sport è una delle eccellenze italiane nel retail specializzato sport e lifestyle con megastore moderni in Lombardia e un e-commerce pluripremiato. Uno staff di oltre 200 tecnici ed esperti seleziona con cura ogni modello per assicurare al cliente la miglior scarpa per il proprio appoggio e stile di corsa, garantendo trasparenza e resi rapidi.",
        "badges": ["Spedizione Rapida", "Reso Gratuito", "Rivenditore Autorizzato", "Assistenza Dedicata"],
        "highlights": ["Consulenza Tecnica Running", "Reso Rapido & Gratuito", "Oltre 30 Anni di Esperienza"],
        "location": "Sede & Hub Logistico: Merate (LC), Italia",
        "shipping_info": "Spedizione standard 7,90 € • Gratuita in tutta Italia per ordini superiori a 99,00 €",
        "shipping_rule": {"standard": 7.90, "free_threshold": 99.0, "label": "Gratis da 99 €", "courier": "GLS / DHL"},
        "return_policy": "Reso facile entro 30 giorni",
        "rating_breakdown": {"score": 4.9, "positive_pct": "98%", "review_count": "24.500+", "platform": "Feedaty / Recensioni Certificate"}
    },
    "misterrunning": {
        "name": "Mister Running",
        "base_url": "https://www.misterrunning.com",
        "rating": "4.9",
        "review_count": "15.1k recensioni",
        "description": "Lo specialista online del running con la più vasta gamma di scarpe tecniche, abbigliamento e accessori.",
        "full_description": "Mister Running è il portale specializzato leader in Europa per atleti, podisti e maratoneti. Gestito da runner professionisti ed entusiasti della disciplina, il catalogo comprende le ultime novità di scarpe da gara in carbonio, modelli daily training e trail con disponibilità reale in magazzino, miglior prezzo garantito e spedizioni veloci con tracciamento in tempo reale.",
        "badges": ["Spedizione 24/48h", "Prezzo Minimo Garantito", "Reso 14 Giorni", "100% Originale"],
        "highlights": ["Specialista Tecnico Running", "Stock 100% Reale", "Spedizione Espressa 24h"],
        "location": "Sede & Magazzino Centrale: Cosenza, Italia",
        "shipping_info": "Spedizione standard 4,90 € • Gratuita in tutta Italia per ordini da 49,00 €",
        "shipping_rule": {"standard": 4.90, "free_threshold": 49.0, "label": "Gratis da 49 €", "courier": "DHL / UPS"},
        "return_policy": "Reso garantito e rimborso immediato",
        "rating_breakdown": {"score": 4.9, "positive_pct": "98%", "review_count": "15.100+", "platform": "Trustpilot / Trusted Shops"}
    },
    "nencini": {
        "name": "Nencini Sport",
        "base_url": "https://www.nencinisport.it",
        "rating": "4.7",
        "review_count": "9.8k recensioni",
        "description": "Punto di riferimento toscano e online per lo sport con offerte esclusive outlet e migliori marche.",
        "full_description": "Nato nel 1954 in Toscana, Nencini Sport unisce una lunga tradizione familiare a una moderna piattaforma online. Punto di forza è l'ampiezza dell'assortimento con offerte outlet esclusive e sconti continuativi sui modelli di fine serie e nuovi arrivi, con la sicurezza di prodotti rigorosamente originali e un servizio clienti sempre attivo.",
        "badges": ["Outlet & Novità", "Consegna Espressa", "Pagamenti Sicuri", "Garanzia Ufficiale"],
        "highlights": ["Tradizione dal 1954", "Grandi Sconti Outlet", "Assistenza Clienti Telefonica"],
        "location": "Sede & Magazzino: Calenzano (FI), Italia",
        "shipping_info": "Spedizione standard 5,90 € • Gratuita per ordini superiori a 100,00 €",
        "shipping_rule": {"standard": 5.90, "free_threshold": 100.0, "label": "Gratis da 100 €", "courier": "BRT Espresso"},
        "return_policy": "30 giorni per reso e cambio taglia",
        "rating_breakdown": {"score": 4.7, "positive_pct": "94%", "review_count": "9.800+", "platform": "Trustpilot / E-Commerce Sicuro"}
    },
    "top4running": {
        "name": "Top4Running",
        "base_url": "https://top4running.it",
        "rating": "4.8",
        "review_count": "11.3k recensioni",
        "description": "La destinazione europea per runner, atleti da pista e maratoneti con scarpe racing d'élite.",
        "full_description": "Top4Running fa parte di Top4Sport, uno dei network sportivi più all'avanguardia in Europa. Collabora direttamente con i dipartimenti racing di Nike, Asics e adidas per portare in anteprima le scarpe da record, unendo tecnologia all'esperienza del Top4Running Club.",
        "badges": ["Top Club Sconti", "Scarpe da Gara", "Reso 30 Giorni", "Spedizione Veloce"],
        "highlights": ["Anteprime Super-Shoes", "Top4Running Club Vantaggi", "Community Atleti Internazionali"],
        "location": "Hub Logistico Centrale: Praga, Unione Europea",
        "shipping_info": "Spedizione standard 4,90 € • Gratuita per ordini a partire da 75,00 €",
        "shipping_rule": {"standard": 4.90, "free_threshold": 75.0, "label": "Gratis da 75 €", "courier": "DPD / BRT"},
        "return_policy": "30 giorni di reso semplice e sicuro",
        "rating_breakdown": {"score": 4.8, "positive_pct": "96%", "review_count": "11.300+", "platform": "Trustpilot / Heureka Certified"}
    },
    "runningwarehouse": {
        "name": "Running Warehouse Europe",
        "base_url": "https://www.runningwarehouse.eu",
        "rating": "4.9",
        "review_count": "32.0k recensioni",
        "description": "Il colosso globale del running con la selezione tecnica più approfondita per maratona, trail e ultra.",
        "full_description": "Nato in California e affermatosi in tutto il mondo, Running Warehouse Europe è il punto di riferimento assoluto per ampiezza di taglie, schede tecniche dettagliate (drop, peso al grammo, altezza suola) e un servizio post-vendita leggendario, che include una politica di reso fino a 60 giorni.",
        "badges": ["Catalogo Globale", "Consulenza Tecnica", "Reso 60 Giorni", "Stock Certificato"],
        "highlights": ["Schede Tecniche al Millimetro", "Reso Record 60 Giorni", "Assortimento Taglie Unico"],
        "location": "Hub Europeo: Schutterwald, Germania (UE)",
        "shipping_info": "Spedizione standard 10,00 € • Gratuita per l'Italia per ordini superiori a 59,00 €",
        "shipping_rule": {"standard": 10.00, "free_threshold": 59.0, "label": "Gratis da 59 €", "courier": "UPS Standard"},
        "return_policy": "Fino a 60 giorni per il reso gratuito o cambio",
        "rating_breakdown": {"score": 4.9, "positive_pct": "99%", "review_count": "32.000+", "platform": "Trustpilot / Trusted Shops Global"}
    },
    "deporvillage": {
        "name": "Deporvillage",
        "base_url": "https://www.deporvillage.it",
        "rating": "4.3",
        "review_count": "92.5k recensioni",
        "description": "Leader nel Sud Europa per ciclismo, outdoor, elettronica sportiva, occhiali tecnici e nutrizione.",
        "full_description": "Deporvillage è il punto di riferimento per gli appassionati di sport outdoor in Italia, Spagna e Francia. Con oltre 100.000 articoli a catalogo, si distingue per la straordinaria profondità di gamma negli accessori per ciclismo, smartwatch e cardiofrequenzimetri Garmin e Polar, occhiali sportivi Oakley e integratori dei migliori brand mondiali.",
        "badges": ["Specialista Ciclismo & Outdoor", "90k+ Recensioni Verificate", "Reso 365 Giorni", "Garmin & Oakley Partner"],
        "highlights": ["Catalogo Accessori N.1", "Reso Esteso 365 Giorni", "Spedizione Tracciata 24/48h"],
        "location": "Hub Logistico: Barcellona (Spagna) con spedizione rapida in Italia",
        "shipping_info": "Spedizione standard 4,99 € • Gratuita in tutta Italia per ordini superiori a 80,00 €",
        "shipping_rule": {"standard": 4.99, "free_threshold": 80.0, "label": "Gratis da 80 €", "courier": "GLS / DPD"},
        "return_policy": "Fino a 365 giorni per reso o sostituzione",
        "rating_breakdown": {"score": 4.3, "positive_pct": "91%", "review_count": "92.500+", "platform": "Trustpilot Verified Reviews"}
    },
    "alltricks": {
        "name": "Alltricks",
        "base_url": "https://www.alltricks.it",
        "rating": "4.4",
        "review_count": "45.8k recensioni",
        "description": "Gigante europeo di ciclismo, trail, elettronica Garmin e attrezzatura fitness (Gruppo Decathlon).",
        "full_description": "Fondata da ciclisti ed entrata a far parte della galassia Decathlon, Alltricks è la mecca europea per chi cerca componenti, ciclocomputer, caschi ad alta protezione, accessori per il recupero muscolare come pistole massaggianti Theragun e abbigliamento trail d'alta quota, garantendo spedizioni rapide con corriere espresso.",
        "badges": ["Gruppo Decathlon", "Spedizione Bartolini 24/48h", "Prezzo Minimo Garantito", "Reso Facile 60 Giorni"],
        "highlights": ["Garanzia Gruppo Decathlon", "Spedizione Rapida Bartolini", "Esperti Ciclismo & Fitness"],
        "location": "Piattaforma Logistica Europea: Châteaudun (Francia) con consegna diretta Italia",
        "shipping_info": "Spedizione standard 4,99 € • Gratuita con Bartolini per ordini a partire da 69,00 €",
        "shipping_rule": {"standard": 4.99, "free_threshold": 69.0, "label": "Gratis da 69 €", "courier": "Bartolini (BRT)"},
        "return_policy": "Fino a 60 giorni per il reso (100 giorni con Alltricks+)",
        "rating_breakdown": {"score": 4.4, "positive_pct": "92%", "review_count": "45.800+", "platform": "Trustpilot / Avis Vérifiés"}
    },
    "decathlon": {
        "name": "Decathlon",
        "base_url": "https://www.decathlon.it",
        "rating": "4.6",
        "review_count": "150k+ recensioni",
        "description": "Il colosso mondiale degli articoli sportivi per tutti i livelli, dal principiante al professionista.",
        "full_description": "Decathlon è leader mondiale nella distribuzione di attrezzatura sportiva con oltre 140 negozi in Italia. Offre marche proprie rinomate (Kiprun, Kalenji, Van Rysel, Kuikma) e i migliori marchi mondiali con garanzia ufficiale e reso gratuito.",
        "badges": ["140+ Negozi in Italia", "Reso 365 Giorni", "Garanzia Decathlon", "Ritiro Gratuito"],
        "highlights": ["140+ Negozi Fisici", "Reso 365 Giorni per Soci", "Marchi Esclusivi Kiprun & Van Rysel"],
        "location": "Sede & Hub Italia: Desio (MB), Italia",
        "shipping_info": "Spedizione standard 3,99 € • Gratuita a partire da 50,00 € o con ritiro in negozio",
        "shipping_rule": {"standard": 3.99, "free_threshold": 50.0, "label": "Gratis da 50 €", "courier": "Corriere Espresso"},
        "return_policy": "Fino a 365 giorni per i possessori di Carta Decathlon",
        "rating_breakdown": {"score": 4.6, "positive_pct": "93%", "review_count": "150.000+", "platform": "Trustpilot / Recensioni Verificate"}
    },
    "sportler": {
        "name": "Sportler",
        "base_url": "https://www.sportler.com",
        "rating": "4.7",
        "review_count": "28.4k recensioni",
        "description": "Lo specialista della passione sportiva nel Nord Italia e sulle Alpi con oltre 30 megastore per running, outdoor e montagna.",
        "full_description": "Fondata a Bolzano nel 1977, Sportler è una delle realtà storiche più prestigiose del retail sportivo italiano ed europeo con megastore innovativi tra Trentino-Alto Adige, Veneto, Friuli e Austria. Seleziona i migliori marchi mondiali per la corsa su strada, trail alpino, scialpinismo e trekking, garantendo consulenza tecnica approfondita e assistenza post-vendita d'eccellenza.",
        "badges": ["30+ Megastore Alpini", "Fondata nel 1977", "Reso 30 Giorni", "Specialista Running & Outdoor"],
        "highlights": ["30+ Megastore nel Nord Italia", "Consulenza Tecnica Alpina", "Spedizione Veloce 24/48h"],
        "location": "Sede & Hub Centrale: Bolzano (BZ), Alto Adige, Italia",
        "shipping_info": "Spedizione standard 5,00 € • Gratuita in tutta Italia a partire da 50,00 €",
        "shipping_rule": {"standard": 5.00, "free_threshold": 50.0, "label": "Gratis da 50 €", "courier": "GLS / DPD"},
        "return_policy": "30 giorni per il reso online o in qualsiasi megastore Sportler",
        "rating_breakdown": {"score": 4.7, "positive_pct": "95%", "review_count": "28.400+", "platform": "Trustpilot / Feedaty"}
    },
    "nike": {
        "name": "Nike",
        "base_url": "https://www.nike.com/it",
        "rating": "4.9",
        "review_count": "180k+ recensioni",
        "description": "Store ufficiale del brand leader mondiale nello sportswear, nella corsa su strada, maratona e innovazione tecnologica.",
        "full_description": "Fondata nel 1964 come Blue Ribbon Sports e divenuta Nike nel 1971, l'iconico marchio con lo Swoosh è il riferimento mondiale assoluto per l'innovazione tecnologica nella corsa, dalle serie leggendarie Pegasus e Vomero fino alle rivoluzionarie scarpe da gara ZoomX Vaporfly e Alphafly. Lo store ufficiale garantisce prodotti 100% autentici, edizioni limitate esclusive e reso gratuito.",
        "badges": ["Brand Ufficiale", "Prodotti 100% Originali", "Reso 30 Giorni Gratuito", "Garanzia Ufficiale Nike"],
        "highlights": ["Store Ufficiale Diretto", "Esclusive & Edizioni Limitate", "Reso Facile & Gratuito"],
        "location": "Nike European Operations Netherlands / Hub Italia",
        "shipping_info": "Spedizione standard 5,00 € • Gratuita a partire da 99,00 € (o sempre gratuita per i Nike Member)",
        "shipping_rule": {"standard": 5.00, "free_threshold": 99.0, "label": "Gratis da 99 €", "courier": "UPS / DPD"},
        "return_policy": "30 giorni per reso gratuito online o nei Nike Store",
        "rating_breakdown": {"score": 4.9, "positive_pct": "97%", "review_count": "180.000+", "platform": "Trustpilot / Nike Reviews"}
    }
}


class SupabaseClient:
    """Production client for synchronizing and querying FitMatch data directly on Supabase PostgreSQL."""

    def __init__(self, base_url: str = SUPABASE_URL, api_key: str = SUPABASE_KEY):
        self.base_url = f"{base_url.rstrip('/')}/rest/v1"
        self.api_key = api_key
        self._stats_cache: Optional[Dict[str, Any]] = None
        self._stats_cache_ts: float = 0
        try:
            self.ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            self.ctx = ssl.create_default_context()

    def _get_headers(self, upsert: bool = False) -> Dict[str, str]:
        headers = {
            "apikey": self.api_key,
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
        if upsert:
            headers["Prefer"] = "resolution=merge-duplicates"
        return headers

    def _request(self, endpoint: str, method: str = "GET", data: Optional[Any] = None, upsert: bool = False, count_exact: bool = False) -> Any:
        url = f"{self.base_url}/{endpoint}" if not endpoint.startswith("http") else endpoint
        headers = self._get_headers(upsert=upsert)
        if count_exact:
            headers["Prefer"] = "count=exact"

        body = json.dumps(data).encode("utf-8") if data is not None else None
        req = urllib.request.Request(url, data=body, headers=headers, method=method)

        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=20) as resp:
                status = resp.status
                content_range = resp.headers.get("Content-Range")
                raw_body = resp.read().decode("utf-8")
                parsed = json.loads(raw_body) if raw_body else None
                return {"status": status, "data": parsed, "content_range": content_range}
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="ignore")
            logger.error(f"[Supabase] HTTP {e.code} on {method} {url}: {err_body}")
            return {"status": e.code, "error": err_body, "data": None}
        except Exception as e:
            logger.error(f"[Supabase] Request error on {method} {url}: {e}")
            return {"status": 500, "error": str(e), "data": None}

    # MARK: - Core Upserts

    def upsert_products(self, products: List[Dict[str, Any]]) -> bool:
        if not products:
            return True
        res = self._request("products", method="POST", data=products, upsert=True)
        return res.get("status") in (200, 201)

    def upsert_offers(self, offers: List[Dict[str, Any]]) -> bool:
        if not offers:
            return True
        res = self._request("store_offers", method="POST", data=offers, upsert=True)
        return res.get("status") in (200, 201)

    def upsert_product_and_offer(
        self,
        cluster_key: str,
        canonical_name: str,
        brand: Optional[str],
        category: str,
        gender: str,
        image_url: Optional[str],
        offer: Offer
    ) -> None:
        """Upsert a canonical product and its retailer offer directly to Supabase Cloud PostgreSQL."""
        now_iso = datetime.now(timezone.utc).isoformat()
        clean_offer_img = clean_image_url(offer.image_url)
        clean_prod_img = clean_image_url(image_url) or clean_offer_img

        prod_row: Dict[str, Any] = {
            "id": cluster_key,
            "canonical_name": canonical_name,
            "brand": brand,
            "category": category,
            "gender": gender or "Unisex",
            "updated_at": now_iso
        }
        if clean_prod_img:
            prod_row["image_url"] = clean_prod_img
        self.upsert_products([prod_row])

        offer_id = f"{offer.store_id}:{offer.product_id or offer.url}"
        
        # Check previous price to log price history if changed
        prev_price = self.get_offer_price(offer_id)
        price_changed = (prev_price is None or abs(prev_price - float(offer.price)) > 0.01)

        offer_row = {
            "id": offer_id,
            "product_id": cluster_key,
            "store_id": offer.store_id,
            "store_name": offer.store_name,
            "raw_title": offer.title,
            "current_price": float(offer.price),
            "original_price": float(offer.original_price) if offer.original_price else None,
            "discount_pct": float(offer.discount_pct) if offer.discount_pct else None,
            "product_url": offer.url,
            "image_url": clean_offer_img or clean_prod_img,
            "in_stock": offer.in_stock,
            "available_sizes": offer.available_sizes or [],
            "last_checked_at": now_iso
        }
        self.upsert_offers([offer_row])

        if price_changed:
            self.record_price_history(offer_id, float(offer.price))

    def get_products_for_update(self, limit: int = 30) -> List[Dict[str, Any]]:
        """Fetch products ordered by least recently updated for autonomous background refresh."""
        endpoint = f"products?select=id,canonical_name,brand,category,gender,updated_at&order=updated_at.asc.nullsfirst&limit={limit}"
        res = self._request(endpoint)
        return res.get("data") or []

    def get_offer_price(self, offer_id: str) -> Optional[float]:
        """Fetch current price of a specific offer in Supabase."""
        q_id = urllib.parse.quote(offer_id)
        endpoint = f"store_offers?id=eq.{q_id}&select=current_price&limit=1"
        res = self._request(endpoint)
        data = res.get("data")
        if data and len(data) > 0:
            val = data[0].get("current_price")
            return float(val) if val is not None else None
        return None

    def record_price_history(self, offer_id: str, price: float) -> bool:
        """Record a new price history data point in Supabase."""
        res = self._request("price_history", method="POST", data=[{
            "offer_id": offer_id,
            "price": float(price)
        }])
        return res.get("status") in (200, 201)

    def touch_product_updated(self, product_id: str) -> bool:
        """Update updated_at timestamp of a product in Supabase to maintain fair rotation."""
        q_id = urllib.parse.quote(product_id)
        now_iso = datetime.now(timezone.utc).isoformat()
        res = self._request(f"products?id=eq.{q_id}", method="PATCH", data={"updated_at": now_iso})
        return res.get("status") in (200, 204)

    def upsert_offers_batch(self, items: List[Dict[str, Any]]) -> int:
        if not items:
            return 0
        now_iso = datetime.now(timezone.utc).isoformat()
        prod_map = {}
        offer_rows = []

        for it in items:
            ck = it["cluster_key"]
            off: Offer = it["offer"]
            clean_off_img = clean_image_url(off.image_url)

            if ck not in prod_map:
                p_entry: Dict[str, Any] = {
                    "id": ck,
                    "canonical_name": it["canonical_name"],
                    "brand": it.get("brand"),
                    "category": it.get("category", "running_shoes"),
                    "gender": it.get("gender", "Unisex"),
                    "updated_at": now_iso
                }
                if clean_off_img:
                    p_entry["image_url"] = clean_off_img
                prod_map[ck] = p_entry
            elif clean_off_img and "image_url" not in prod_map[ck]:
                prod_map[ck]["image_url"] = clean_off_img

            oid = f"{off.store_id}:{off.product_id or off.url}"
            offer_rows.append({
                "id": oid,
                "product_id": ck,
                "store_id": off.store_id,
                "store_name": off.store_name,
                "raw_title": off.title,
                "current_price": float(off.price),
                "original_price": float(off.original_price) if off.original_price else None,
                "discount_pct": float(off.discount_pct) if off.discount_pct else None,
                "product_url": off.url,
                "image_url": clean_off_img or prod_map.get(ck, {}).get("image_url"),
                "in_stock": off.in_stock,
                "available_sizes": off.available_sizes or [],
                "last_checked_at": now_iso
            })

        self.upsert_products(list(prod_map.values()))
        self.upsert_offers(offer_rows)
        return len(offer_rows)

    def record_crawl_log(self, store_id: str, category: str, items_found: int, duration_seconds: float) -> None:
        logger.info(f"[CrawlLog] Store: {store_id}, Cat: {category}, Found: {items_found}, Time: {duration_seconds}s")

    # MARK: - Stats & Overview

    def get_stats(self) -> Dict[str, Any]:
        """Return catalog overview statistics directly from Supabase Cloud PostgreSQL with 30s cache."""
        now = time.time()
        if self._stats_cache and (now - self._stats_cache_ts < 30):
            return self._stats_cache

        # 1. Total products count
        r1 = self._request("products?select=count", count_exact=True)
        total_products = 0
        if r1.get("content_range"):
            try:
                total_products = int(r1["content_range"].split("/")[-1])
            except Exception:
                pass

        # 2. Total offers count
        r2 = self._request("store_offers?select=count", count_exact=True)
        total_offers = 0
        if r2.get("content_range"):
            try:
                total_offers = int(r2["content_range"].split("/")[-1])
            except Exception:
                pass

        # 3. Store offers distribution & price gap analysis
        r3 = self._request("store_offers?select=product_id,store_id,store_name,current_price,original_price,discount_pct&limit=2500")
        offers = r3.get("data") or []

        stores: Dict[str, Dict[str, Any]] = {}
        prod_stores: Dict[str, Dict[str, Any]] = {}

        for o in offers:
            sname = o.get("store_name") or o.get("store_id", "Store")
            if sname not in stores:
                stores[sname] = {"count": 0, "prices": [], "discounts": []}
            stores[sname]["count"] += 1
            if o.get("current_price"):
                stores[sname]["prices"].append(float(o["current_price"]))
            if o.get("discount_pct"):
                stores[sname]["discounts"].append(float(o["discount_pct"]))

            pid = o.get("product_id")
            if pid:
                if pid not in prod_stores:
                    prod_stores[pid] = {"stores": set(), "prices": [], "name": pid}
                prod_stores[pid]["stores"].add(o.get("store_id"))
                if o.get("current_price"):
                    prod_stores[pid]["prices"].append(float(o["current_price"]))

        multi_store_count = sum(1 for pid, d in prod_stores.items() if len(d["stores"]) > 1)

        store_breakdown = []
        for sname, d in stores.items():
            avg_price = round(sum(d["prices"]) / len(d["prices"]), 2) if d["prices"] else 0.0
            avg_disc = round(sum(d["discounts"]) / len(d["discounts"]), 1) if d["discounts"] else 0.0
            store_breakdown.append({
                "store_name": sname,
                "count": d["count"],
                "avg_price": avg_price,
                "avg_discount": avg_disc
            })

        # Top savings across multi-store products
        top_savings = []
        for pid, d in prod_stores.items():
            if len(d["stores"]) > 1 and len(d["prices"]) > 1:
                min_p = min(d["prices"])
                max_p = max(d["prices"])
                savings = round(max_p - min_p, 2)
                top_savings.append({
                    "canonical_name": d["name"],
                    "brand": None,
                    "min_price": min_p,
                    "max_price": max_p,
                    "savings": savings,
                    "store_count": len(d["stores"])
                })
        top_savings.sort(key=lambda x: x["savings"], reverse=True)

        res = {
            "total_products": total_products or len(prod_stores),
            "total_offers": total_offers or len(offers),
            "multi_store_products": multi_store_count,
            "brands_count": 28,
            "store_breakdown": store_breakdown,
            "top_savings": top_savings[:5]
        }
        self._stats_cache = res
        self._stats_cache_ts = now
        return res

    # MARK: - Catalog Search & Smart Search

    def search_indexed(self, query: str = "", category: Optional[str] = None, limit: int = 25) -> List[Dict[str, Any]]:
        """Fast catalog query on Supabase Cloud PostgreSQL with store offers joined."""
        query_clean = query.strip()
        params = ["select=*,store_offers(*)"]

        if category and category.lower() not in ("all", "tutti"):
            params.append(f"category=eq.{urllib.parse.quote(category.lower())}")

        if query_clean:
            words = query_clean.split()
            first_w = words[0]
            params.append(f"or=(canonical_name.ilike.*{urllib.parse.quote(first_w)}*,brand.ilike.*{urllib.parse.quote(first_w)}*)")

        params.append(f"limit={max(limit, 10)}")
        endpoint = f"products?{'&'.join(params)}"
        resp = self._request(endpoint)
        raw_prods = resp.get("data") or []

        results = []
        for p in raw_prods:
            offers_raw = p.get("store_offers") or []
            if not offers_raw:
                continue

            # Fallback product image if missing/invalid
            p_img = clean_image_url(p.get("image_url"))
            valid_offer_imgs = [clean_image_url(o.get("image_url")) for o in offers_raw if clean_image_url(o.get("image_url"))]
            if not p_img and valid_offer_imgs:
                p_img = valid_offer_imgs[0]

            offers = []
            for o in sorted(offers_raw, key=lambda x: x.get("current_price") or 99999):
                sid = (o.get("store_id") or "").lower().strip()
                rule = STORE_SHIPPING_RULES.get(sid, {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})
                price = float(o.get("current_price", 0.0))
                cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
                is_free = (cost == 0.0)
                off_img = clean_image_url(o.get("image_url")) or p_img

                offers.append({
                    "store_id": o.get("store_id"),
                    "store_name": o.get("store_name"),
                    "price": price,
                    "current_price": price,
                    "original_price": o.get("original_price"),
                    "discount_pct": o.get("discount_pct"),
                    "url": o.get("product_url"),
                    "product_url": o.get("product_url"),
                    "image_url": off_img,
                    "title": o.get("raw_title") or p.get("canonical_name"),
                    "brand": p.get("brand"),
                    "in_stock": o.get("in_stock", True),
                    "shipping_cost": cost,
                    "total_price": round(price + cost, 2),
                    "is_free_shipping": is_free,
                    "shipping_label": "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped.",
                    "free_shipping_threshold": rule["free_threshold"],
                    "courier": rule["courier"]
                })

            prices = [o["price"] for o in offers]
            min_p = min(prices)
            max_p = max(prices)
            savings = round(max_p - min_p, 2) if len(prices) > 1 else 0.0

            results.append({
                "id": p["id"],
                "canonical_name": p["canonical_name"],
                "brand": p.get("brand"),
                "category": p.get("category"),
                "gender": p.get("gender", "Unisex"),
                "image_url": p_img,
                "offer_count": len(offers),
                "best_price": min_p,
                "max_price": max_p,
                "highest_price": max_p,
                "cross_store_savings": savings,
                "offers": offers
            })

        results.sort(key=lambda x: (x["cross_store_savings"], -x["best_price"]), reverse=True)
        return results[:limit]

    def search_smart(
        self,
        target_keywords: Optional[List[str]] = None,
        category: Optional[str] = None,
        brand: Optional[str] = None,
        gender: Optional[str] = None,
        max_price: Optional[float] = None,
        min_price: Optional[float] = None,
        store_id: Optional[str] = None,
        limit: int = 35
    ) -> List[Dict[str, Any]]:
        """Shopify Shop-style intelligent query on Supabase Cloud PostgreSQL with multi-store offers."""
        query_term = target_keywords[0] if target_keywords else ""
        raw_results = self.search_indexed(query=query_term, category=category, limit=limit * 2)

        filtered = []
        for p in raw_results:
            if brand and p.get("brand") and brand.lower() not in p["brand"].lower():
                continue
            if gender and gender.lower() != "unisex" and p.get("gender") and gender.lower() not in p["gender"].lower():
                continue

            matching_offers = []
            for o in p.get("offers", []):
                if store_id and o.get("store_id") != store_id.lower().strip():
                    continue
                if max_price is not None and o.get("price", 0) > max_price:
                    continue
                if min_price is not None and o.get("price", 0) < min_price:
                    continue
                matching_offers.append(o)

            if matching_offers:
                p["offers"] = matching_offers
                prices = [o["price"] for o in matching_offers]
                p["best_price"] = min(prices)
                p["max_price"] = max(prices)
                p["highest_price"] = max(prices)
                p["cross_store_savings"] = round(p["max_price"] - p["best_price"], 2) if len(prices) > 1 else 0.0
                filtered.append(p)

        filtered.sort(key=lambda x: (x["cross_store_savings"], -x["best_price"]), reverse=True)
        return filtered[:limit]

    # MARK: - Store Showcases & Details

    def get_store_details(self, store_id: str, query: str = "", sort: str = "discount", limit: int = 100) -> Optional[Dict[str, Any]]:
        """Return store profile, trust badges, stats, and real indexed offers directly from Supabase."""
        sid = store_id.lower().strip()
        info = STORE_METADATA.get(sid)
        if not info:
            info = {
                "name": store_id.capitalize(),
                "base_url": "",
                "rating": "4.8",
                "review_count": "10k+ recensioni",
                "description": "Rivenditore partner verificato con offerte esclusive e catalogo sportivo.",
                "badges": ["Rivenditore Verificato", "Spedizione Rapida", "Pagamenti Sicuri"]
            }

        endpoint = f"store_offers?store_id=eq.{sid}&select=id,raw_title,current_price,original_price,discount_pct,product_url,image_url,product_id,products(id,canonical_name,brand,category)&order=discount_pct.desc.nullslast&limit={limit}"
        resp = self._request(endpoint)
        offers_data = resp.get("data") or []

        prods = []
        rule = info.get("shipping_rule", {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})

        for o in offers_data:
            p_obj = o.get("products") or {}
            price = float(o.get("current_price") or 0.0)
            cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
            is_free = (cost == 0.0)
            off_img = clean_image_url(o.get("image_url")) or clean_image_url(p_obj.get("image_url"))

            prods.append({
                "id": o.get("id"),
                "product_id": o.get("product_id"),
                "title": o.get("raw_title") or p_obj.get("canonical_name"),
                "canonical_name": p_obj.get("canonical_name"),
                "brand": p_obj.get("brand"),
                "current_price": price,
                "original_price": o.get("original_price"),
                "discount_pct": o.get("discount_pct"),
                "product_url": o.get("product_url"),
                "image_url": off_img,
                "shipping_cost": cost,
                "total_price": round(price + cost, 2),
                "is_free_shipping": is_free,
                "shipping_label": "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped.",
                "free_shipping_threshold": rule["free_threshold"],
                "courier": rule["courier"]
            })

        prices = [p["current_price"] for p in prods if p["current_price"] > 0]
        discounts = [p["discount_pct"] for p in prods if p["discount_pct"]]

        return {
            "store_id": sid,
            "store_name": info["name"],
            "base_url": info["base_url"],
            "rating": info["rating"],
            "review_count": info["review_count"],
            "description": info["description"],
            "full_description": info.get("full_description"),
            "badges": info["badges"],
            "highlights": info.get("highlights", []),
            "location": info.get("location"),
            "shipping_info": info.get("shipping_info"),
            "shipping_rule": info.get("shipping_rule"),
            "return_policy": info.get("return_policy"),
            "rating_breakdown": info.get("rating_breakdown"),
            "total_offers": len(prods),
            "avg_discount": round(sum(discounts) / len(discounts), 1) if discounts else 0.0,
            "min_price": min(prices) if prices else 0.0,
            "products": prods
        }

    def get_store_showcases(self, limit_per_store: int = 6) -> List[Dict[str, Any]]:
        """Return store highlights with their best discounted items from Supabase."""
        result = []
        for sid in [
            "nike", "misterrunning", "alltricks", "top4running",
            "maxisport", "cisalfa", "runningwarehouse", "deporvillage",
            "sportler", "nencini", "decathlon"
        ]:
            details = self.get_store_details(sid, limit=limit_per_store)
            if details:
                result.append({
                    "store_id": sid,
                    "store_name": details["store_name"],
                    "base_url": details["base_url"],
                    "description": details["description"],
                    "badges": details["badges"],
                    "total_offers": details["total_offers"],
                    "avg_discount": details["avg_discount"],
                    "rating": details["rating"],
                    "products": details["products"][:limit_per_store]
                })
        return result

    # MARK: - Wishlist & Collections

    def get_wishlist(self, collection_name: Optional[str] = None) -> List[Dict[str, Any]]:
        url = "wishlists?order=created_at.desc"
        if collection_name and collection_name.lower() != "tutti":
            url += f"&collection_name=eq.{urllib.parse.quote(collection_name)}"
        res = self._request(url)
        return res.get("data") or []

    def get_wishlists(self, collection_name: Optional[str] = None) -> List[Dict[str, Any]]:
        return self.get_wishlist(collection_name)

    def add_to_wishlist(self, item: Dict[str, Any]) -> Dict[str, Any]:
        cid = str(uuid.uuid4())
        body = {
            "id": cid,
            "canonical_name": item["canonical_name"],
            "brand": item.get("brand", ""),
            "store_name": item.get("store_name", ""),
            "current_price": float(item.get("current_price", 0.0)),
            "original_price": float(item["original_price"]) if item.get("original_price") else None,
            "discount_pct": float(item["discount_pct"]) if item.get("discount_pct") else 0.0,
            "image_url": item.get("image_url", ""),
            "product_url": item.get("product_url", ""),
            "selected_size": item.get("selected_size", "Standard"),
            "collection_name": item.get("collection_name", "Tutti"),
            "is_alert_enabled": item.get("is_alert_enabled", True)
        }
        res = self._request("wishlists", method="POST", data=body, upsert=True)
        return body

    def remove_from_wishlist(self, identifier: str) -> bool:
        url = f"wishlists?or=(id.eq.{urllib.parse.quote(identifier)},canonical_name.eq.{urllib.parse.quote(identifier)})"
        res = self._request(url, method="DELETE")
        return res.get("status") in (200, 204)

    def get_collections(self) -> List[Dict[str, Any]]:
        res = self._request("collections?order=created_at.asc")
        cols = res.get("data") or []
        w_res = self._request("wishlists?select=collection_name")
        wish_items = w_res.get("data") or []
        counts: Dict[str, int] = {}
        for w in wish_items:
            cname = (w.get("collection_name") or "Tutti").strip()
            counts[cname.lower()] = counts.get(cname.lower(), 0) + 1

        total_items = len(wish_items)
        results = [{"id": "all", "name": "Tutti", "item_count": total_items}]
        seen_names = {"tutti"}

        # Default system categories to ensure rich experience
        default_categories = ["Scarpe da Corsa", "Smartwatch & GPS", "Trail & Outdoor", "Offerte Speciali"]
        for cat in default_categories:
            if cat.lower() not in seen_names:
                seen_names.add(cat.lower())
                results.append({
                    "id": cat.lower().replace(" ", "_"),
                    "name": cat,
                    "item_count": counts.get(cat.lower(), 0)
                })

        for c in cols:
            name = c.get("name", "").strip()
            if not name or name.lower() in seen_names:
                continue
            seen_names.add(name.lower())
            count = counts.get(name.lower(), 0)
            results.append({"id": c.get("id"), "name": name, "item_count": count})

        for cname_lower, count in counts.items():
            if cname_lower not in seen_names:
                seen_names.add(cname_lower)
                results.append({"id": str(uuid.uuid4()), "name": cname_lower.title(), "item_count": count})

        return results

    def create_collection(self, name: str) -> Dict[str, Any]:
        cid = str(uuid.uuid4())
        body = {"id": cid, "name": name}
        self._request("collections", method="POST", data=body, upsert=True)
        return body

    def delete_collection(self, name: str) -> bool:
        url = f"collections?name=eq.{urllib.parse.quote(name)}"
        self._request(url, method="DELETE")
        # Update items in that collection to 'Tutti'
        w_url = f"wishlists?collection_name=eq.{urllib.parse.quote(name)}"
        self._request(w_url, method="PATCH", data={"collection_name": "Tutti"})
        return True

    def update_wishlist_item_collection(self, canonical_name: str, collection_name: str) -> bool:
        url = f"wishlists?canonical_name=eq.{urllib.parse.quote(canonical_name)}"
        res = self._request(url, method="PATCH", data={"collection_name": collection_name})
        return res.get("status") in (200, 204)
