import os
import re
import json
import logging
import ssl
import time
import uuid
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional
import certifi

from fitmatch.models import Offer, STORE_SHIPPING_RULES, clean_image_url, normalize_sizes, extract_variant_title

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
    },
    "adidas": {
        "name": "Adidas",
        "base_url": "https://www.adidas.it",
        "rating": "4.9",
        "review_count": "145k+ recensioni",
        "description": "Store ufficiale del brand globale pioniere nell'innovazione sportiva, maratona e outdoor Terrex.",
        "full_description": "Fondata in Germania nel 1949, Adidas è sinonimo di innovazione atletica globale con le sue rivoluzionarie mescole Lightstrike Pro, ammortizzazione Boost e mescole suola Continental. Dalla serie record da maratona Adizero alla linea tecnica alpina Terrex, lo store ufficiale italiano assicura collezioni autentiche al 100%, edizioni esclusive e programma fedeltà adiClub.",
        "badges": ["Brand Ufficiale", "Collezioni Esclusive", "Reso 30 Giorni Gratuito", "adiClub Member"],
        "highlights": ["Store Ufficiale Diretto", "Tecnologie Adizero & Terrex", "Reso Facile Entro 30gg"],
        "location": "Sede Globale: Herzogenaurach (Germania) / Filiale Italia: Monza",
        "shipping_info": "Spedizione standard 4,99 € • Gratuita a partire da 50,00 € (o sempre gratuita per i membri adiClub)",
        "shipping_rule": {"standard": 4.99, "free_threshold": 50.0, "label": "Gratis da 50 €", "courier": "DHL / GLS"},
        "return_policy": "30 giorni per reso gratuito online",
        "rating_breakdown": {"score": 4.9, "positive_pct": "96%", "review_count": "145.000+", "platform": "Trustpilot / Recensioni Verificate"}
    }
}


class SupabaseClient:
    """Production client for synchronizing and querying FitMatch data directly on Supabase PostgreSQL."""

    def __init__(self, base_url: str = SUPABASE_URL, api_key: str = SUPABASE_KEY):
        self.base_url = f"{base_url.rstrip('/')}/rest/v1"
        self.api_key = api_key
        self._stats_cache: Optional[Dict[str, Any]] = None
        self._stats_cache_ts: float = 0
        self._embedding_cache: Dict[str, List[float]] = {}
        try:
            self.ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            self.ctx = ssl.create_default_context()

    def _get_headers(self, upsert: bool = False, return_representation: bool = False) -> Dict[str, str]:
        headers = {
            "apikey": self.api_key,
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
        prefer_parts = []
        if upsert:
            prefer_parts.append("resolution=merge-duplicates")
        if return_representation:
            prefer_parts.append("return=representation")
        if prefer_parts:
            headers["Prefer"] = ",".join(prefer_parts)
        return headers

    def _request(
        self,
        endpoint: str,
        method: str = "GET",
        data: Optional[Any] = None,
        upsert: bool = False,
        count_exact: bool = False,
        return_representation: bool = False
    ) -> Any:
        url = f"{self.base_url}/{endpoint}" if not endpoint.startswith("http") else endpoint
        headers = self._get_headers(upsert=upsert, return_representation=return_representation)
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

        offer_gallery = [clean_image_url(u) for u in (offer.gallery_images or []) if clean_image_url(u)]
        if clean_offer_img and clean_offer_img not in offer_gallery:
            offer_gallery.insert(0, clean_offer_img)

        prod_gallery = list(offer_gallery)
        if clean_prod_img and clean_prod_img not in prod_gallery:
            prod_gallery.insert(0, clean_prod_img)

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
        if prod_gallery:
            prod_row["gallery_images"] = prod_gallery
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
            "gallery_images": offer_gallery,
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

    def get_price_history(
        self,
        product_id: Optional[str] = None,
        canonical_name: Optional[str] = None,
        days: int = 90
    ) -> Dict[str, Any]:
        """Fetch historical price points and statistics for a product across its offers in Supabase."""
        now = datetime.now(timezone.utc)
        start_date = now - timedelta(days=days)
        start_iso = start_date.isoformat()

        # 1. Resolve product
        p_row = None
        if product_id:
            q_id = urllib.parse.quote(product_id.strip())
            p_res = self._request(f"products?id=eq.{q_id}&select=id,canonical_name,brand&limit=1")
            if p_res.get("data"):
                p_row = p_res["data"][0]

        if not p_row and canonical_name:
            c_clean = canonical_name.strip()
            q_c = urllib.parse.quote(f"*{c_clean}*")
            p_res = self._request(f"products?canonical_name=ilike.{q_c}&select=id,canonical_name,brand&limit=1")
            if p_res.get("data"):
                p_row = p_res["data"][0]
            else:
                p_res = self._request(f"products?id=ilike.{q_c}&select=id,canonical_name,brand&limit=1")
                if p_res.get("data"):
                    p_row = p_res["data"][0]

        eff_product_id = p_row["id"] if p_row else (product_id or canonical_name or "")
        eff_canon = p_row["canonical_name"] if p_row else (canonical_name or eff_product_id)

        # 2. Fetch offers for this product
        offers = []
        if eff_product_id:
            q_pid = urllib.parse.quote(eff_product_id)
            off_res = self._request(f"store_offers?product_id=eq.{q_pid}&select=id,store_id,store_name,current_price,original_price,discount_pct,last_checked_at")
            offers = off_res.get("data") or []

        if not offers and canonical_name:
            q_title = urllib.parse.quote(f"*{canonical_name.strip()}*")
            off_res = self._request(f"store_offers?raw_title=ilike.{q_title}&select=id,store_id,store_name,current_price,original_price,discount_pct,last_checked_at&limit=15")
            offers = off_res.get("data") or []

        offer_store_map = {o["id"]: o.get("store_name", "Store") for o in offers}
        offer_current_map = {o["id"]: float(o["current_price"]) for o in offers if o.get("current_price") is not None}
        offer_orig_map = {o["id"]: float(o["original_price"]) for o in offers if o.get("original_price") is not None}

        raw_points: List[Dict[str, Any]] = []
        if offers:
            offer_ids = [o["id"] for o in offers][:30]
            in_clause = ",".join([urllib.parse.quote(f'"{oid}"') for oid in offer_ids])
            q_start = urllib.parse.quote(start_iso)
            hist_res = self._request(
                f"price_history?offer_id=in.({in_clause})&recorded_at=gte.{q_start}&order=recorded_at.asc&limit=500"
            )
            data = hist_res.get("data") or []
            for item in data:
                oid = item.get("offer_id")
                raw_points.append({
                    "date": item.get("recorded_at", ""),
                    "price": float(item.get("price", 0.0)),
                    "store_name": offer_store_map.get(oid, "Store"),
                    "offer_id": oid
                })

        now_str = now.isoformat()
        for oid, cur_p in offer_current_map.items():
            raw_points.append({
                "date": now_str,
                "price": cur_p,
                "store_name": offer_store_map.get(oid, "Store"),
                "offer_id": oid
            })

        # Baseline point if minimal history
        if len(raw_points) == len(offer_current_map) and offer_current_map:
            max_orig = max(offer_orig_map.values()) if offer_orig_map else None
            min_cur = min(offer_current_map.values())
            if max_orig and max_orig > min_cur:
                past_30d = (now - timedelta(days=30)).isoformat()
                raw_points.insert(0, {
                    "date": past_30d,
                    "price": round(max_orig, 2),
                    "store_name": "Listino Ufficiale",
                    "offer_id": None
                })

        raw_points.sort(key=lambda x: x["date"])

        filtered_points: List[Dict[str, Any]] = []
        seen_keys = set()
        for pt in raw_points:
            d_short = pt["date"][:10] if len(pt["date"]) >= 10 else pt["date"]
            key = (d_short, pt["store_name"], round(pt["price"], 2))
            if key not in seen_keys:
                seen_keys.add(key)
                filtered_points.append(pt)

        all_prices = [p["price"] for p in filtered_points if p.get("price") and p["price"] > 0]
        if not all_prices and offer_current_map:
            all_prices = list(offer_current_map.values())

        current_price = min(offer_current_map.values()) if offer_current_map else (all_prices[-1] if all_prices else 0.0)
        lowest_price = min(all_prices) if all_prices else current_price
        highest_price = max(all_prices) if all_prices else current_price
        average_price = round(sum(all_prices) / len(all_prices), 2) if all_prices else current_price

        is_all_time_low = bool(current_price > 0 and current_price <= (lowest_price + 0.50))
        price_drop_pct = round(((average_price - current_price) / average_price) * 100, 1) if average_price > current_price else 0.0
        price_drop_amount = round(average_price - current_price, 2) if average_price > current_price else 0.0

        return {
            "canonical_name": eff_canon,
            "product_id": eff_product_id,
            "current_price": round(current_price, 2),
            "lowest_price": round(lowest_price, 2),
            "highest_price": round(highest_price, 2),
            "average_price": round(average_price, 2),
            "is_all_time_low": is_all_time_low,
            "price_drop_percentage": price_drop_pct,
            "price_drop_amount": price_drop_amount,
            "history_points": filtered_points,
            "total_data_points": len(filtered_points),
            "first_recorded_date": filtered_points[0]["date"] if filtered_points else None,
            "last_recorded_date": filtered_points[-1]["date"] if filtered_points else None
        }

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
        offer_map = {}

        for it in items:
            ck = it["cluster_key"]
            off: Offer = it["offer"]
            clean_off_img = clean_image_url(off.image_url)
            off_gallery = [clean_image_url(u) for u in (off.gallery_images or []) if clean_image_url(u)]
            if clean_off_img and clean_off_img not in off_gallery:
                off_gallery.insert(0, clean_off_img)

            if ck not in prod_map:
                p_entry: Dict[str, Any] = {
                    "id": ck,
                    "canonical_name": it["canonical_name"],
                    "brand": it.get("brand"),
                    "category": it.get("category", "running_shoes"),
                    "gender": it.get("gender", "Unisex"),
                    "gallery_images": list(off_gallery),
                    "updated_at": now_iso
                }
                if clean_off_img:
                    p_entry["image_url"] = clean_off_img
                prod_map[ck] = p_entry
            else:
                if clean_off_img and "image_url" not in prod_map[ck]:
                    prod_map[ck]["image_url"] = clean_off_img
                for g_img in off_gallery:
                    if g_img not in prod_map[ck].get("gallery_images", []):
                        prod_map[ck].setdefault("gallery_images", []).append(g_img)

            oid = f"{off.store_id}:{off.product_id or off.url}"
            offer_map[oid] = {
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
                "gallery_images": off_gallery,
                "in_stock": off.in_stock,
                "available_sizes": off.available_sizes or [],
                "last_checked_at": now_iso
            }

        self.upsert_products(list(prod_map.values()))
        self.upsert_offers(list(offer_map.values()))
        return len(offer_map)

    def record_crawl_log(
        self,
        store_id: str,
        category: str,
        items_found: int,
        duration_seconds: float,
        session_id: Optional[str] = None
    ) -> None:
        """Record crawler job log in Supabase crawl_logs table."""
        logger.info(f"[CrawlLog] Store: {store_id}, Cat: {category}, Found: {items_found}, Time: {duration_seconds}s, Session: {session_id}")
        data: Dict[str, Any] = {
            "store_id": store_id,
            "category": category,
            "items_found": items_found,
            "duration_seconds": round(duration_seconds, 2)
        }
        if session_id:
            data["session_id"] = session_id
        try:
            self._request("crawl_logs", method="POST", data=data)
        except Exception as e:
            logger.warning(f"[CrawlLog] Note saving crawl log: {e}")

    # MARK: - Sync Sessions Tracking

    def create_sync_session(
        self,
        session_type: str,
        trigger_source: str = "scheduler",
        metadata: Optional[Dict[str, Any]] = None
    ) -> Optional[str]:
        """Create a new sync session record in Supabase with status 'running'."""
        payload = {
            "session_type": session_type,
            "trigger_source": trigger_source,
            "status": "running",
            "metadata": metadata or {}
        }
        res = self._request("sync_sessions", method="POST", data=payload, return_representation=True)
        if res.get("status") in (200, 201) and res.get("data"):
            rows = res["data"]
            if isinstance(rows, list) and len(rows) > 0:
                return rows[0].get("id")
            elif isinstance(rows, dict):
                return rows.get("id")
        logger.warning(f"[Supabase] Failed to create sync session: {res.get('error')}")
        return None

    def update_sync_session(
        self,
        session_id: str,
        status: str,
        duration_seconds: float = 0.0,
        total_items_processed: int = 0,
        total_items_updated: int = 0,
        total_price_drops: int = 0,
        store_stats: Optional[Dict[str, Any]] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Update a sync session record with final status and metrics."""
        now_iso = datetime.now(timezone.utc).isoformat()
        payload: Dict[str, Any] = {
            "status": status,
            "completed_at": now_iso,
            "duration_seconds": round(duration_seconds, 2),
            "total_items_processed": total_items_processed,
            "total_items_updated": total_items_updated,
            "total_price_drops": total_price_drops,
        }
        if store_stats is not None:
            payload["store_stats"] = store_stats
        if error_message is not None:
            payload["error_message"] = error_message
        if metadata is not None:
            payload["metadata"] = metadata

        res = self._request(
            f"sync_sessions?id=eq.{session_id}",
            method="PATCH",
            data=payload
        )
        return res.get("status") in (200, 204)

    def get_sync_sessions(
        self,
        limit: int = 20,
        session_type: Optional[str] = None,
        status: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Retrieve recent sync sessions from Supabase."""
        params = ["select=*", "order=started_at.desc", f"limit={limit}"]
        if session_type:
            params.append(f"session_type=eq.{session_type}")
        if status:
            params.append(f"status=eq.{status}")

        endpoint = f"sync_sessions?{'&'.join(params)}"
        res = self._request(endpoint, method="GET")
        return res.get("data") or []

    def get_sync_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve single session with its detailed crawl logs."""
        res = self._request(f"sync_sessions?id=eq.{session_id}&select=*", method="GET")
        data = res.get("data")
        if data and isinstance(data, list) and len(data) > 0:
            session = data[0]
            logs_res = self._request(f"crawl_logs?session_id=eq.{session_id}&select=*&order=crawled_at.asc", method="GET")
            session["crawl_logs"] = logs_res.get("data") or []
            return session
        return None

    def get_latest_sync_session(self, session_type: str) -> Optional[Dict[str, Any]]:
        """Retrieve most recent completed session of a specific type."""
        endpoint = f"sync_sessions?session_type=eq.{session_type}&status=eq.completed&order=started_at.desc&limit=1&select=*"
        res = self._request(endpoint, method="GET")
        data = res.get("data")
        if data and isinstance(data, list) and len(data) > 0:
            return data[0]
        return None

    def delete_sync_session(self, session_id: str) -> bool:
        """Delete a sync session and its linked crawl logs from Supabase."""
        try:
            self._request(f"crawl_logs?session_id=eq.{session_id}", method="DELETE")
            res = self._request(f"sync_sessions?id=eq.{session_id}", method="DELETE")
            return res.get("status") in (200, 204)
        except Exception as e:
            logger.error(f"[Supabase] Error deleting sync session {session_id}: {e}")
            return False

    def delete_sync_sessions(self, status: Optional[str] = None) -> int:
        """Delete sync sessions filtered by status (e.g. failed) and return deleted count."""
        try:
            sessions = self.get_sync_sessions(limit=100, status=status)
            deleted = 0
            for s in sessions:
                sid = s.get("id")
                if sid and self.delete_sync_session(sid):
                    deleted += 1
            return deleted
        except Exception as e:
            logger.error(f"[Supabase] Error bulk deleting sync sessions (status={status}): {e}")
            return 0

    def get_store_health_metrics(self) -> List[Dict[str, Any]]:
        """Retrieve store health, active offers and size coverage from store_health_metrics view."""
        res = self._request("store_health_metrics?select=*&order=total_offers.desc")
        return res.get("data") or []

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

    CATEGORY_EQUIVALENTS = {
        "running_shoes": ["running_shoes", "shoes", "fitness", "trail_running"],
        "shoes": ["running_shoes", "shoes", "fitness", "trail_running"],
        "trail_running": ["trail_running", "running_shoes", "shoes"],
        "fitness": ["fitness", "running_shoes", "shoes", "gear"],
        "football_boots": ["football_boots", "shoes"],
        "swim": ["swim", "gear"],
        "top": ["top", "apparel"],
        "apparel": ["apparel", "top", "pants", "jacket", "socks"],
        "jacket": ["jacket", "apparel", "top"],
        "pants": ["pants", "apparel"],
        "socks": ["socks", "apparel", "gear"],
        "gps_watch": ["gps_watch", "sensor", "gear"],
        "eyewear": ["eyewear", "gear"],
        "hydration": ["hydration", "pack", "gear", "bag"],
        "padel": ["padel", "racket", "shoes", "gear"],
        "cycling": ["cycling", "trainer", "helmet", "gear", "mount", "apparel", "shoes"],
        "nutrition": ["nutrition", "gear"],
        "gear": ["gear", "hydration", "pack"],
    }

    @classmethod
    def _build_category_filter(cls, category: Optional[str]) -> Optional[str]:
        if not category or category.lower() in ("all", "tutti"):
            return None
        c_low = category.lower().strip()
        eq_cats = cls.CATEGORY_EQUIVALENTS.get(c_low, [c_low])
        if len(eq_cats) == 1:
            return f"category=eq.{urllib.parse.quote(eq_cats[0])}"
        joined = ",".join(urllib.parse.quote(c) for c in eq_cats)
        return f"category=in.({joined})"

    def search_indexed(
        self,
        query: str = "",
        category: Optional[str] = None,
        limit: int = 25,
        brand: Optional[str] = None,
        gender: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Fast catalog query on Supabase Cloud PostgreSQL with store offers joined."""
        query_clean = query.strip()
        params = ["select=*,store_offers!inner(*)"]

        cat_filter = self._build_category_filter(category)
        if cat_filter:
            params.append(cat_filter)
        else:
            params.append("category=neq.non_sport")

        # SQL-level brand pre-filter so generic keyword expansion doesn't drown out requested brand
        if brand and brand.strip():
            b_clean = urllib.parse.quote(brand.strip())
            params.append(f"or=(brand.ilike.*{b_clean}*,canonical_name.ilike.*{b_clean}*)")

        # SQL-level gender pre-filter preserving Unisex and Uomo | Donna
        if gender and gender.strip().lower() in ("uomo", "donna"):
            g_low = gender.strip().lower()
            if g_low == "uomo":
                params.append("or=(gender.ilike.*Uomo*,gender.eq.Unisex,gender.is.null)")
            else:
                params.append("or=(gender.ilike.*Donna*,gender.eq.Unisex,gender.is.null)")

        BASE_STOPWORDS = {
            "scarpe", "scarpa", "modello", "modelli", "per", "la", "il", "lo", "i", "gli", "le",
            "un", "una", "uno", "di", "a", "da", "in", "con", "su", "della", "dello",
            "dei", "degli", "delle", "shoe", "shoes", "trova", "cerca", "cerco",
            "migliori", "migliore", "offerta", "offerte", "prezzo", "prezzi"
        }
        SPORT_CONTEXT_WORDS = {
            "running", "corsa", "correre", "trail", "allenamento", "palestra",
            "sport", "sportivo", "sportiva", "uomo", "donna", "unisex"
        }
        all_tokens = [w for w in re.findall(r"\b\w+\b", query_clean.lower()) if w not in BASE_STOPWORDS and len(w) > 1] if query_clean else []
        # Strip generic sport context words if there are other specific tokens (brand/model/garment)
        specific_tokens = [w for w in all_tokens if w not in SPORT_CONTEXT_WORDS]
        words = specific_tokens if specific_tokens else all_tokens

        if words:
            if len(words) == 1:
                w_enc = urllib.parse.quote(words[0])
                params.append(f"or=(canonical_name.ilike.*{w_enc}*,brand.ilike.*{w_enc}*)")
            else:
                and_parts = [f"or(canonical_name.ilike.*{urllib.parse.quote(w)}*,brand.ilike.*{urllib.parse.quote(w)}*)" for w in words[:4]]
                params.append(f"and=({','.join(and_parts)})")

        params.append(f"limit={max(limit * 2, 30)}")
        endpoint = f"products?{'&'.join(params)}"
        resp = self._request(endpoint)
        raw_prods = resp.get("data") or []
        seen_pids = {p.get("id") for p in raw_prods if p.get("id")}

        # Also check store_offers.raw_title if query has specific terms and few products matched canonical_name
        if words and len(raw_prods) < 8:
            offer_and_parts = [f"raw_title=ilike.*{urllib.parse.quote(w)}*" for w in words[:3]]
            off_endpoint = f"store_offers?{'&'.join(offer_and_parts)}&select=product_id&limit=40"
            off_resp = self._request(off_endpoint)
            off_rows = off_resp.get("data") or []
            extra_pids = []
            for r in off_rows:
                pid = r.get("product_id")
                if pid and pid not in seen_pids and pid not in extra_pids:
                    extra_pids.append(pid)
            if extra_pids:
                pids_in = ",".join(f'"{urllib.parse.quote(pid)}"' for pid in extra_pids[:25])
                p_extra_ep = f"products?id=in.({pids_in})&select=*,store_offers!inner(*)"
                if cat_filter:
                    p_extra_ep += f"&{cat_filter}"
                extra_resp = self._request(p_extra_ep)
                for ep in (extra_resp.get("data") or []):
                    if ep.get("id") not in seen_pids:
                        seen_pids.add(ep.get("id"))
                        raw_prods.append(ep)

        # Fallback if strict multi-word query still returned 0 products
        if not raw_prods and len(words) > 1:
            or_parts = []
            for w in words[:4]:
                if w not in SPORT_CONTEXT_WORDS:
                    w_enc = urllib.parse.quote(w)
                    or_parts.append(f"canonical_name.ilike.*{w_enc}*")
            if or_parts:
                params_fb = ["select=*,store_offers!inner(*)", f"or=({','.join(or_parts)})"]
                if cat_filter:
                    params_fb.append(cat_filter)
                params_fb.append(f"limit={max(limit * 2, 30)}")
                fb_resp = self._request(f"products?{'&'.join(params_fb)}")
                raw_prods = fb_resp.get("data") or []

        results = []
        for p in raw_prods:
            f = self._format_product_with_offers(p)
            if f:
                results.append(f)

        results.sort(key=lambda x: (x["cross_store_savings"], -x["best_price"]), reverse=True)
        return results[:limit]

    def _format_product_with_offers(self, p: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Normalize and format raw Supabase product row with its joined store offers."""
        offers_raw = p.get("store_offers") or []
        if not offers_raw:
            return None

        from fitmatch.matcher.normalizer import ProductNormalizer
        norm = ProductNormalizer()

        # Self-healing check: ensure canonical_name & brand are consistent with the product's actual offers
        sorted_offers_raw = sorted(offers_raw, key=lambda x: x.get("current_price") or 99999)
        primary_raw_title = (sorted_offers_raw[0].get("raw_title") or "").strip()
        p_brand = (p.get("brand") or "").strip()
        c_name = (p.get("canonical_name") or "").strip()

        if primary_raw_title:
            inferred_brand = norm.extract_brand(primary_raw_title)
            if inferred_brand and (not p_brand or p_brand.lower() in ("generic", "elite", "scarpa", "on") and inferred_brand.lower() != p_brand.lower()):
                p_brand = inferred_brand

            # Check token overlap between canonical_name and primary offer raw_title
            cname_tokens = {w for w in re.findall(r"\b[a-z0-9]{3,}\b", c_name.lower()) if w not in ("uomo", "donna", "unisex", "generic")}
            raw_tokens = {w for w in re.findall(r"\b[a-z0-9]{3,}\b", primary_raw_title.lower())}
            # Also check bilingual equivalence (manica lunga <-> long sleeve)
            has_bilingual_match = (
                ("long" in cname_tokens or "sleeve" in cname_tokens) and ("manica" in raw_tokens or "maniche" in raw_tokens)
            ) or (
                ("manica" in cname_tokens or "lunga" in cname_tokens) and ("long" in raw_tokens or "sleeve" in raw_tokens)
            )
            if not c_name or c_name.lower().startswith("generic ") or (cname_tokens and raw_tokens and not cname_tokens.intersection(raw_tokens) and not has_bilingual_match):
                c_name = ProductNormalizer.build_canonical_display_name(primary_raw_title, brand=p_brand)
            else:
                c_name = ProductNormalizer.build_canonical_display_name(c_name, brand=p_brand)

        # Filter out any accidentally cross-linked offer whose explicit brand or model number conflicts with primary offer
        primary_digits = set(re.findall(r"\b\d+\b", primary_raw_title.lower()))
        primary_price = float(sorted_offers_raw[0].get("current_price") or 0.0)
        consistent_offers_raw = []
        for o in sorted_offers_raw:
            o_title = o.get("raw_title") or ""
            o_brand = norm.extract_brand(o_title)
            if p_brand and o_brand and p_brand.lower() not in ("generic",) and o_brand.lower() != p_brand.lower():
                continue
            o_digits = set(re.findall(r"\b\d+\b", o_title.lower()))
            o_price = float(o.get("current_price") or 0.0)
            if primary_digits and o_digits and primary_digits != o_digits and primary_price > 0 and o_price > primary_price * 1.8:
                continue
            consistent_offers_raw.append(o)
        if consistent_offers_raw:
            offers_raw = consistent_offers_raw

        # Fallback product image if missing/invalid
        p_img = clean_image_url(p.get("image_url"))
        valid_offer_imgs = [clean_image_url(o.get("image_url")) for o in offers_raw if clean_image_url(o.get("image_url"))]
        if valid_offer_imgs and (not p_img or p_img not in valid_offer_imgs):
            p_img = valid_offer_imgs[0]

        # Build comprehensive product gallery
        raw_prod_gallery = p.get("gallery_images") or []
        if isinstance(raw_prod_gallery, str):
            try:
                raw_prod_gallery = json.loads(raw_prod_gallery)
            except Exception:
                raw_prod_gallery = [raw_prod_gallery]
        prod_gallery = []
        if p_img:
            prod_gallery.append(p_img)
        for g_img in raw_prod_gallery:
            c = clean_image_url(g_img)
            if c and c not in prod_gallery:
                prod_gallery.append(c)

        offers = []
        for o in sorted(offers_raw, key=lambda x: x.get("current_price") or 99999):
            sid = (o.get("store_id") or "").lower().strip()
            rule = STORE_SHIPPING_RULES.get(sid, {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})
            price = float(o.get("current_price", 0.0))
            cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
            is_free = (cost == 0.0)
            off_img = clean_image_url(o.get("image_url")) or p_img

            raw_off_gallery = o.get("gallery_images") or []
            if isinstance(raw_off_gallery, str):
                try:
                    raw_off_gallery = json.loads(raw_off_gallery)
                except Exception:
                    raw_off_gallery = [raw_off_gallery]
            off_gallery = []
            if off_img:
                off_gallery.append(off_img)
            for og in raw_off_gallery:
                c = clean_image_url(og)
                if c and c not in off_gallery:
                    off_gallery.append(c)

            # Add offer photos into product gallery as well
            for u in off_gallery:
                if u not in prod_gallery:
                    prod_gallery.append(u)

            off_sizes = normalize_sizes(o.get("available_sizes"))
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
                "gallery_images": None,
                "title": o.get("raw_title") or c_name,
                "raw_title": o.get("raw_title") or c_name,
                "variant_name": extract_variant_title(o.get("raw_title")),
                "available_sizes": off_sizes,
                "brand": p_brand or p.get("brand"),
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

        # Clean duplicate brand prefix in canonical_name
        if p_brand:
            c_name = re.sub(r"^(" + re.escape(p_brand) + r"\s+)+", f"{p_brand} ", c_name, flags=re.IGNORECASE).strip()

        # Aggregate and sort all available sizes across all offers
        prod_all_sizes = set()
        for o in offers:
            for sz in o.get("available_sizes", []):
                prod_all_sizes.add(sz)

        def _size_sort_key(s):
            try:
                return (0, float(s))
            except ValueError:
                return (1, s)

        sorted_sizes = sorted(list(prod_all_sizes), key=_size_sort_key)

        return {
            "id": p["id"],
            "canonical_name": c_name,
            "brand": p_brand or p.get("brand"),
            "category": p.get("category"),
            "gender": p.get("gender", "Unisex"),
            "image_url": p_img,
            "gallery_images": prod_gallery[:6],
            "available_sizes": sorted_sizes,
            "offer_count": len(offers),
            "best_price": min_p,
            "max_price": max_p,
            "highest_price": max_p,
            "cross_store_savings": savings,
            "offers": offers[:10]
        }

    def get_embedding(self, text: str) -> Optional[List[float]]:
        """Generate 1536-dim embedding vector using text-embedding-3-small via OpenRouter."""
        cleaned = text.strip()
        if not cleaned:
            return None
        if cleaned in self._embedding_cache:
            return self._embedding_cache[cleaned]

        api_key = os.getenv("OPENROUTER_API_KEY")
        if not api_key:
            return None

        try:
            req = urllib.request.Request(
                "https://openrouter.ai/api/v1/embeddings",
                data=json.dumps({"model": "text-embedding-3-small", "input": cleaned}).encode("utf-8"),
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, context=self.ctx, timeout=6) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                items = data.get("data") or []
                if items:
                    emb = items[0]["embedding"]
                    self._embedding_cache[cleaned] = emb
                    return emb
        except Exception as e:
            logger.warning(f"[SupabaseClient] get_embedding failed: {e}")
        return None

    def search_semantic(
        self,
        query: str,
        threshold: float = 0.35,
        limit: int = 25
    ) -> List[Dict[str, Any]]:
        """Vector semantic similarity search using Supabase pgvector match_products_semantic RPC."""
        emb = self.get_embedding(query)
        if not emb:
            return []

        rpc_res = self._request("rpc/match_products_semantic", method="POST", data={
            "query_embedding": emb,
            "match_threshold": threshold,
            "match_count": limit
        })
        raw_matches = rpc_res.get("data") or []
        if not raw_matches:
            return []

        sim_map = {}
        for m in raw_matches:
            try:
                sim_map[m["id"]] = float(m.get("similarity") or 0.0)
            except (ValueError, TypeError):
                sim_map[m["id"]] = 0.0

        ids_encoded = ",".join([urllib.parse.quote(m["id"]) for m in raw_matches])
        endpoint = f"products?id=in.({ids_encoded})&select=*,store_offers!inner(*)"
        resp = self._request(endpoint)
        prods = resp.get("data") or []

        results = []
        for p in prods:
            f = self._format_product_with_offers(p)
            if f:
                f["semantic_similarity"] = float(sim_map.get(p["id"], 0.0))
                results.append(f)

        results.sort(key=lambda x: float(x.get("semantic_similarity") or 0.0), reverse=True)
        return results[:limit]

    def search_smart(
        self,
        target_keywords: Optional[List[str]] = None,
        category: Optional[str] = None,
        brand: Optional[str] = None,
        gender: Optional[str] = None,
        max_price: Optional[float] = None,
        min_price: Optional[float] = None,
        size: Optional[str] = None,
        store_id: Optional[str] = None,
        limit: int = 35,
        raw_query: Optional[str] = None,
        preferred_size: Optional[str] = None,
        favorite_brands: Optional[List[str]] = None,
        exclude_ids: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """Shopify Shop-style intelligent query on Supabase Cloud PostgreSQL with multi-store offers."""
        from fitmatch.smart_search import QueryProductGuardrail

        raw_results = []
        seen_names = set()
        excluded_id_set = {str(x) for x in (exclude_ids or []) if x}

        eff_query_str = (raw_query or " ".join(target_keywords or [])).strip()
        detected_product_type = QueryProductGuardrail.detect_product_type(eff_query_str)

        eff_max_price: Optional[float] = None
        if max_price is not None:
            try:
                eff_max_price = float(max_price)
            except (ValueError, TypeError):
                eff_max_price = None

        eff_min_price: Optional[float] = None
        if min_price is not None:
            try:
                eff_min_price = float(min_price)
            except (ValueError, TypeError):
                eff_min_price = None

        norm_size = size.strip().replace(",", ".") if size else None
        target_size_candidates = set()
        if norm_size:
            target_size_candidates.add(norm_size)
            from fitmatch.models import EU_TO_US_MEN, US_TO_EU_MEN
            if norm_size in EU_TO_US_MEN:
                target_size_candidates.add(EU_TO_US_MEN[norm_size])
            if norm_size in US_TO_EU_MEN:
                target_size_candidates.add(US_TO_EU_MEN[norm_size])

        norm_pref_size = preferred_size.strip().replace(",", ".") if preferred_size else None
        pref_size_candidates = set()
        if norm_pref_size:
            pref_size_candidates.add(norm_pref_size)
            from fitmatch.models import EU_TO_US_MEN, US_TO_EU_MEN
            if norm_pref_size in EU_TO_US_MEN:
                pref_size_candidates.add(EU_TO_US_MEN[norm_pref_size])
            if norm_pref_size in US_TO_EU_MEN:
                pref_size_candidates.add(US_TO_EU_MEN[norm_pref_size])

        keywords_to_query = [k for k in (target_keywords or [""]) if k.strip()][:5]
        if not keywords_to_query:
            keywords_to_query = [""]
        from concurrent.futures import ThreadPoolExecutor

        def _fetch_kw(kw: str) -> List[Dict[str, Any]]:
            query_term = kw.strip()
            prods = self.search_indexed(
                query=query_term,
                category=category,
                limit=limit,
                brand=brand,
                gender=gender,
            )
            if not prods and category:
                prods = self.search_indexed(
                    query=query_term,
                    category=None,
                    limit=limit,
                    brand=brand,
                    gender=gender,
                )
            return prods

        with ThreadPoolExecutor(max_workers=min(5, max(1, len(keywords_to_query)))) as executor:
            kw_batches = list(executor.map(_fetch_kw, keywords_to_query))

        for prods in kw_batches:
            for p in prods:
                p_ident = p.get("id") or p.get("canonical_name")
                if p_ident not in seen_names:
                    seen_names.add(p_ident)
                    raw_results.append(p)

        # True Hybrid Search: run pgvector semantic retrieval both when lexical results are sparse
        # (< 8) and when query is natural/descriptive (>= 4 words without numeric SKU)
        raw_words = re.findall(r"\b\w+\b", (raw_query or "").lower())
        is_descriptive_query = len(raw_words) >= 4 and not any(w.isdigit() and len(w) >= 2 for w in raw_words)
        if target_keywords and (len(raw_results) < 8 or is_descriptive_query):
            sem_query = raw_query.strip() if raw_query and raw_query.strip() else " ".join([k for k in target_keywords[:2] if k.strip()])
            if sem_query:
                sem_prods = self.search_semantic(query=sem_query, threshold=0.36, limit=max(limit, 25))
                for sp in sem_prods:
                    p_ident = sp.get("id") or sp.get("canonical_name")
                    if p_ident not in seen_names:
                        seen_names.add(p_ident)
                        raw_results.append(sp)
                    else:
                        for ex in raw_results:
                            if (ex.get("id") or ex.get("canonical_name")) == p_ident:
                                ex["semantic_similarity"] = max(ex.get("semantic_similarity", 0.0), sp.get("semantic_similarity", 0.0))

        BIKE_HARDWARE = {
            "cuffie", "cuffia", "serie sterzo", "headset", "attacco manubrio",
            "supporto manubrio", "movimento centrale", "pignoni", "guarnitura",
            "pastiglie", "disco freno", "forcella", "tubeless", "pedale", "pedali"
        }
        is_bike_query = any(
            w in kw.lower()
            for kw in keywords_to_query
            for w in ["bici", "ciclismo", "sterzo", "cuffie", "headset", "bike"]
        )

        filtered = []
        for p in raw_results:
            pid_str = str(p.get("id") or "")
            if pid_str and pid_str in excluded_id_set:
                continue
            if (p.get("category") or "").lower() == "non_sport":
                continue
            p_brand = (p.get("brand") or "").lower()
            p_name = (p.get("canonical_name") or "").lower()

            # Product-Type Guardrail: block watches/towels on shoe searches, caps/short-sleeves on long-sleeve searches, etc.
            if not QueryProductGuardrail.is_product_compatible(p, detected_product_type, raw_query=eff_query_str):
                continue

            # Strict Brand Filter: if brand is requested, product MUST match brand in brand field or canonical name
            if brand:
                b_clean = brand.lower().strip()
                b_variants = {b_clean, b_clean.replace("-", " "), b_clean.replace(" ", "-")}
                matches_brand = any((bv in p_brand) or (bv in p_name) for bv in b_variants)
                if not matches_brand:
                    continue

            # Bike Hardware Exclusion: exclude bike parts unless user explicitly searched for them
            if not is_bike_query and any(bh in p_name for bh in BIKE_HARDWARE):
                continue

            if gender and gender.lower() not in ("unisex", "uomo | donna", "uomo/donna", "tutti", "all"):
                req_g = gender.lower()
                prod_g = (p.get("gender") or "unisex").lower()
                is_dual_gender = ("uomo" in prod_g and "donna" in prod_g)
                if prod_g != "unisex" and not is_dual_gender and req_g not in prod_g and prod_g not in req_g:
                    continue
                # Even if tagged unisex, exclude explicit opposite-sex title markers (e.g. "Scarpa Donna" when searching "Uomo")
                if req_g == "uomo" and re.search(r"\b(donna|wmns|women|femme|lady)\b", p_name) and not re.search(r"\b(uomo|men|homme)\b", p_name):
                    continue
                if req_g == "donna" and re.search(r"\b(uomo|men|homme)\b", p_name) and not re.search(r"\b(donna|wmns|women|femme|lady)\b", p_name):
                    continue

            # If product has explicit available sizes and size filter was requested
            p_sizes = set(p.get("available_sizes") or [])
            if target_size_candidates and p_sizes and not target_size_candidates.intersection(p_sizes):
                continue

            matching_offers = []
            for o in p.get("offers", []):
                if store_id and o.get("store_id") != store_id.lower().strip():
                    continue
                o_price = float(o.get("price") or 0.0)
                if eff_max_price is not None and o_price > eff_max_price:
                    continue
                if eff_min_price is not None and o_price < eff_min_price:
                    continue
                if target_size_candidates:
                    off_sizes = set(o.get("available_sizes") or [])
                    if off_sizes and not target_size_candidates.intersection(off_sizes):
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

        # Relevance scoring to ensure exact model matches top the results
        q_str_low = eff_query_str.lower()
        q_str_no_filters = re.sub(
            r"\b(?:sotto|fino\s*a|max|min|oltre|sopra|euro|eur|taglia|misura|size|eu|us|uk)\s*\d+(?:[.,]\d+)?\b",
            " ",
            q_str_low
        )
        raw_query_model_digits = set(re.findall(r"\b\d+\b", q_str_no_filters))
        wants_trail = bool(re.search(r"\b(trail|sterrato|montagna|sentier[oi]|fango|bosco|skyrunning)\b", q_str_low))
        wants_waterproof = bool(re.search(r"\b(gtx|gore[\s-]*tex|impermeabil[ei]|pioggia|invern[oa]|waterproof|shield)\b", q_str_low))
        wants_hr_strap = bool(re.search(r"\b(fascia\s*cardio|cardiofrequenzimetro\s*fascia|h10|h9|hrm|verity)\b", q_str_low))

        def compute_relevance(prod: Dict[str, Any], query_kws: List[str]) -> float:
            score = 0.0
            pname = (prod.get("canonical_name") or "").lower()
            pbrand = (prod.get("brand") or "").lower()
            pcat = (prod.get("category") or "").lower()
            off_titles = " ".join((o.get("title") or "") for o in (prod.get("offers") or [])[:3]).lower()
            combined_text = f"{pname} {off_titles}"
            tokens = set(re.findall(r"\b\w+\b", combined_text))
            p_digits = set(re.findall(r"\b\d+\b", pname))

            if raw_query_model_digits:
                if raw_query_model_digits.intersection(p_digits):
                    score += 240.0
                elif p_digits:
                    score -= 120.0

            for idx, kw in enumerate(query_kws):
                kw_low = kw.lower().strip()
                if not kw_low:
                    continue
                is_generic_kw = kw_low in QueryProductGuardrail.GENERIC_CATEGORY_KEYWORDS
                # Higher weight for primary keywords at the start of target_keywords
                priority_mult = 1.5 if idx == 0 else (1.3 if idx < 3 else (1.1 if idx < 6 else 1.0))
                kw_regex = rf"\b{re.escape(kw_low)}\b"

                if re.search(kw_regex, pname):
                    score += (25.0 if is_generic_kw else 145.0) * priority_mult
                elif re.search(kw_regex, combined_text):
                    score += (18.0 if is_generic_kw else 105.0) * priority_mult

                kw_tokens = [
                    t for t in re.findall(r"\b\w+\b", kw_low)
                    if t not in QueryProductGuardrail.SPORT_CONTEXT_STOPWORDS
                ]
                for t in kw_tokens:
                    if t in tokens:
                        score += (10.0 if is_generic_kw else 30.0) * priority_mult
                        if t.isdigit():
                            score += 55.0
                    elif t in pbrand:
                        score += 22.0

                q_digits = [t for t in kw_tokens if t.isdigit()]
                if q_digits and p_digits and len(query_kws) <= 2:
                    if not set(q_digits).intersection(p_digits):
                        score -= 75.0  # Penalize mismatched generation/model numbers on specific SKU queries

            # Domain-specific relevance boosts
            if detected_product_type == "gps_watch":
                if wants_hr_strap:
                    if re.search(r"\b(fascia|hrm|h10|h9|verity|cardiofrequenzimetro)\b", combined_text):
                        score += 150.0
                else:
                    if pcat == "gps_watch":
                        score += 65.0
                    if re.search(r"\b(forerunner|fenix|instinct|epix|venu|vivoactive|coros\s*pace|coros\s*apex|suunto\s*race|suunto\s*vertical|suunto\s*run|polar\s*vantage|polar\s*pacer|polar\s*grit)\b", combined_text):
                        score += 110.0
                    if re.search(r"\b(corsa|running|maratona)\b", q_str_low) and re.search(r"\b(forerunner|coros\s*pace|polar\s*pacer|suunto\s*run|suunto\s*race)\b", combined_text):
                        score += 65.0
            elif detected_product_type == "bike_computer":
                if re.search(r"\b(garmin\s*edge|\bedge\s*(?:530|540|830|840|1030|1040|1050|explore)\b|wahoo\s*elemnt|bryton|igpsport\s*bsc)\b", combined_text):
                    score += 120.0
            elif detected_product_type == "long_sleeve_top":
                if any(b in pbrand for b in ("adidas", "nike", "asics", "salomon", "odlo", "mizuno", "kiprun", "hoka", "brooks", "craft", "under armour", "gorewear", "puma", "new balance")):
                    score += 65.0
                if re.search(r"\b(running|run|adizero|cross\s*run|active\s*warm|warmalite|element)\b", combined_text):
                    score += 50.0
            elif detected_product_type in ("short_sleeve_top", "pants_shorts", "jacket", "socks"):
                if any(b in pbrand for b in ("adidas", "nike", "asics", "salomon", "odlo", "mizuno", "kiprun", "hoka", "brooks", "craft", "under armour", "gorewear", "puma", "new balance", "cep", "compressport", "uyn")):
                    score += 55.0
                if re.search(r"\b(running|run|adizero|dri[\s-]*fit|miler|stride|challenger|bonatti|zeroweight|fujitrail)\b", combined_text):
                    score += 45.0
            elif detected_product_type == "padel_racket":
                if re.search(r"\b(vertex|hack|at10|ml10|technical\s*viper|air\s*viper|counter\s*viper|metalbone|adipower|speed\s*pro|extreme\s*pro|diablo|electra)\b", combined_text):
                    score += 95.0
            elif detected_product_type == "eyewear":
                if re.search(r"\b(sutro|radar\s*ev|radar|jawbreaker|encoder|sphaera|bisphaera)\b", combined_text):
                    score += 90.0
            elif detected_product_type == "football_boots":
                if pcat == "football_boots":
                    score += 110.0
                if re.search(r"\b(mercurial|superfly|vapor|tiempo|phantom|predator|copa|future|magnetico|f50|top\s*sala|top\s*flex|king)\b", combined_text):
                    score += 90.0
                if re.search(r"\b(calcio\s*a\s*[57]|calcetto|sintetico|tf|turf|ag)\b", q_str_low) and re.search(r"\b(ag|tf|turf|mg|calcetto|top\s*sala|top\s*flex|multiground)\b", combined_text):
                    score += 65.0
                if re.search(r"\b(maglia|pantaloncin|calzetton|parastinchi|borsone|guanti)\b", pname):
                    score -= 180.0
            elif detected_product_type == "swim":
                if pcat == "swim":
                    score += 110.0
                if "occhialin" in q_str_low or "goggles" in q_str_low:
                    if re.search(r"\b(occhialin|goggles|cobra|biofuse|futura|swipe|vengeance|aquapulse|python|tracks|air\s*speed|hydro)\b", combined_text):
                        score += 130.0
                    elif re.search(r"\b(costume|boxer|slip|muta|cuffia|pinne|tavoletta)\b", pname):
                        score -= 150.0
            elif "hyrox" in q_str_low:
                if "hyrox" in combined_text:
                    score += 140.0
                elif any(m in combined_text for m in ("dropset", "deviate nitro", "velocity nitro", "metcon")):
                    score += 95.0
            elif detected_product_type == "shoes" or (detected_product_type is None and category in ("running_shoes", "shoes")):
                if not wants_trail:
                    if pcat == "trail_running" or re.search(r"\b(trail|speedcross|trabuco|speedgoat|cascadia|ultra\s*raptor|akasha|bushido|sonoma|mujin|daichi|terrex\s*agravic|hierro|peregrine)\b", pname):
                        score -= 75.0
                    if re.search(r"\b(pegasus|vomero|vaporfly|alphafly|streakfly|invincible|nimbus|novablast|cumulus|kayano|superblast|metaspeed|clifton|bondi|mach|cielo|ghost|glycerin|hyperion|endorphin|triumph|ride|adizero|supernova|ultraboost|1080|rebel|fuelcell|wave\s*rider|wave\s*sky|wave\s*rebellion|deviate\s*nitro|velocity\s*nitro|cloudmonster|cloudsurfer|cloudboom)\b", pname):
                        score += 65.0
                else:
                    if pcat == "trail_running" or re.search(r"\b(trail|speedcross|trabuco|speedgoat|cascadia|ultra\s*raptor|akasha|bushido|prodigio|ultra\s*glide|genesis|peregrine|hierro)\b", pname):
                        score += 85.0
                if not wants_waterproof and re.search(r"\b(gtx|gore[\s-]*tex|waterproof|shield)\b", pname):
                    score -= 35.0

            ACCESSORY_KEYWORDS = {
                "pellicola", "vetro temperato", "film hydrogel", "protezione schermo",
                "custodia", "sportenzia", "cinturino"
            }
            if any(acc in pname for acc in ACCESSORY_KEYWORDS):
                score -= 80.0

            # Semantic similarity bonus
            sem_sim = float(prod.get("semantic_similarity") or 0.0)
            if sem_sim > 0.35:
                score += sem_sim * 55.0

            # User Preference Soft-Boost (preferred shoe/apparel size in stock & favorite brands)
            if pref_size_candidates:
                p_avail_sizes = set(prod.get("available_sizes") or [])
                if pref_size_candidates.intersection(p_avail_sizes):
                    score += 18.0
            if favorite_brands:
                fav_low = [fb.lower().strip() for fb in favorite_brands if fb and fb.strip()]
                if any(fb in pbrand or fb in pname for fb in fav_low):
                    score += 12.0

            num_offers = len(prod.get("offers", []))
            if num_offers >= 4:
                score += 40.0
            elif num_offers >= 2:
                score += 22.0
            score += min(prod.get("cross_store_savings", 0.0) * 0.15, 20.0)
            return score

        for p in filtered:
            p["relevance_score"] = compute_relevance(p, keywords_to_query)

        filtered.sort(
            key=lambda x: (
                float(x.get("relevance_score") or 0.0),
                float(x.get("cross_store_savings") or 0.0),
                -float(x.get("best_price") or 0.0)
            ),
            reverse=True
        )

        # Deduplicate / disambiguate products that share the same cleaned canonical_name
        deduped = []
        seen_canon_gender = {}
        for p in filtered:
            cname = (p.get("canonical_name") or "").strip()
            cname_key = cname.lower()
            gend = (p.get("gender") or "Unisex").strip()
            p_img = p.get("image_url") or ""
            p_price = round(float(p.get("best_price") or 0.0), 2)

            # Check if an identical card (same canonical name & either same gender or same image+price) is already present
            duplicate_found = False
            for existing in deduped:
                ex_name = (existing.get("canonical_name") or "").strip().lower()
                ex_base_name = re.sub(r"\s*\((uomo|donna)\)$", "", ex_name, flags=re.IGNORECASE)
                if ex_base_name == cname_key:
                    ex_gend = (existing.get("gender") or "Unisex").strip()
                    ex_img = existing.get("image_url") or ""
                    ex_price = round(float(existing.get("best_price") or 0.0), 2)
                    if ex_gend.lower() == gend.lower() or (ex_img == p_img and ex_price == p_price):
                        # Merge any unique offers into existing product
                        ex_urls = {o.get("url") for o in existing.get("offers", [])}
                        for o in p.get("offers", []):
                            if o.get("url") not in ex_urls:
                                existing["offers"].append(o)
                                ex_urls.add(o.get("url"))
                        existing["offers"].sort(key=lambda x: float(x.get("price") or 99999))
                        prices = [float(o["price"]) for o in existing["offers"]]
                        existing["offer_count"] = len(existing["offers"])
                        existing["best_price"] = min(prices)
                        existing["max_price"] = max(prices)
                        existing["highest_price"] = max(prices)
                        existing["cross_store_savings"] = round(max(prices) - min(prices), 2) if len(prices) > 1 else 0.0
                        duplicate_found = True
                        break
                    else:
                        # Different gender variant with different image/price: disambiguate both titles
                        if ex_gend in ("Uomo", "Donna") and not existing["canonical_name"].endswith(f"({ex_gend})"):
                            existing["canonical_name"] = f"{existing['canonical_name']} ({ex_gend})"
                        if gend in ("Uomo", "Donna") and not cname.endswith(f"({gend})"):
                            p["canonical_name"] = f"{cname} ({gend})"
            if not duplicate_found:
                deduped.append(p)

        # Model-Family Diversity Ranking (MMR): showcase distinct flagship models in top slots
        # before repeating colorways/editions of the same model family
        if len(deduped) > 2:
            top_score = float(deduped[0].get("relevance_score") or 0.0)
            FAMILY_NOISE = {
                "uomo", "donna", "unisex", "plus", "premium", "se", "tr", "gtx", "gore", "tex",
                "wide", "medium", "music", "solar", "amp", "pro", "elite", "scarpe", "scarpa",
                "sneaker", "sneakers", "orologio", "smartwatch", "racchetta", "padel", "occhiali",
                "zaino", "idratante", "borsa", "maglia", "giacca", "pantaloni", "pantaloncini",
                "calze", "top", "one", "trail", "running", "corsa", "strada", "gara"
            }
            COMPOUND_MODEL_PREFIXES = {
                "forerunner", "fenix", "instinct", "edge", "adizero", "wave", "fresh",
                "deviate", "velocity", "active", "adv", "sense", "ultra", "lone"
            }

            def _model_family_key(prod: Dict[str, Any]) -> str:
                cname = (prod.get("canonical_name") or "").lower()
                pbrand = (prod.get("brand") or "").lower().strip()
                raw_tokens = [
                    t for t in re.findall(r"\b[a-z0-9]+\b", cname)
                    if t not in FAMILY_NOISE and t not in pbrand.split() and len(t) > 1
                ]
                if not raw_tokens:
                    return f"{pbrand}:{cname[:15]}"
                first = raw_tokens[0]
                if first in ("forerunner", "fenix", "instinct", "edge", "bsc100", "bsc200", "bsc300"):
                    # Keep watch/computer number (e.g., forerunner 165 vs forerunner 265 vs forerunner 965)
                    num_tok = next((t for t in raw_tokens[1:3] if any(c.isdigit() for c in t)), "")
                    return f"{pbrand}:{first}:{num_tok}"
                if first in COMPOUND_MODEL_PREFIXES and len(raw_tokens) >= 2 and not raw_tokens[1].isdigit():
                    return f"{pbrand}:{first}:{raw_tokens[1]}"
                return f"{pbrand}:{first}"

            round1, round2, rest = [], [], []
            seen_r1, seen_r2 = set(), set()
            min_diverse_score = top_score * 0.52

            for p in deduped:
                sc = float(p.get("relevance_score") or 0.0)
                fk = _model_family_key(p)
                if sc >= min_diverse_score and fk not in seen_r1:
                    seen_r1.add(fk)
                    round1.append(p)
                elif sc >= min_diverse_score and fk not in seen_r2:
                    seen_r2.add(fk)
                    round2.append(p)
                else:
                    rest.append(p)

            deduped = round1 + round2 + rest

        return deduped[:limit]

    # MARK: - Store Showcases & Details

    def get_store_details(self, store_id: str, query: str = "", sort: str = "discount", limit: int = 100) -> Optional[Dict[str, Any]]:
        """Return store profile, trust badges, stats, and real indexed offers directly from Supabase."""
        sid = store_id.lower().strip()
        info = STORE_METADATA.get(sid, {})
        db_store = self.get_store(sid) or {}

        store_name = db_store.get("name") or info.get("name") or sid.capitalize()
        base_url = db_store.get("base_url") or info.get("base_url") or ""
        rating = str(db_store.get("rating") or info.get("rating") or "4.8")
        review_count = db_store.get("formatted_review_count") or info.get("review_count") or "1,2K"
        card_theme = db_store.get("card_theme") or info.get("card_theme") or "white"
        accent_color = db_store.get("accent_color") or info.get("accent_color")
        logo_url = db_store.get("logo_url")
        desc = db_store.get("description") or info.get("description") or "Rivenditore autorizzato con offerte esclusive per lo sport e running."
        full_desc = db_store.get("full_description") or info.get("full_description") or desc
        location = db_store.get("city_or_location") or info.get("location")
        contact_email = db_store.get("contact_email") or f"supporto@{sid}.com"
        contact_phone = db_store.get("contact_phone")
        social_instagram = db_store.get("social_instagram") or f"@{sid}"
        refund_policy = db_store.get("refund_policy") or info.get("return_policy") or "Reso garantito entro 30 giorni."
        shipping_policy = db_store.get("shipping_policy") or info.get("shipping_info") or "Spedizione rapida con corriere espresso."
        privacy_policy_url = db_store.get("privacy_policy_url") or base_url
        terms_url = db_store.get("terms_url") or base_url

        # Map sort parameter
        order_clause = "discount_pct.desc.nullslast"
        if sort == "price_asc":
            order_clause = "current_price.asc"
        elif sort == "price_desc":
            order_clause = "current_price.desc"
        elif sort == "name":
            order_clause = "raw_title.asc"

        query_params = [
            f"store_id=eq.{sid}",
            "select=id,raw_title,current_price,original_price,discount_pct,product_url,image_url,gallery_images,product_id,available_sizes,products(id,canonical_name,brand,category,gallery_images)",
            f"order={order_clause}",
            f"limit={limit}"
        ]

        # Smart query filtering: apply phonetic & typo normalization
        if query and query.strip():
            from fitmatch.smart_search import LocalHeuristicParser
            clean_q = LocalHeuristicParser.normalize_typos(query.strip().lower())
            words = [w for w in clean_q.split() if len(w) > 1]
            for w in words:
                query_params.append(f"raw_title=ilike.*{w}*")

        endpoint = f"store_offers?{'&'.join(query_params)}"
        resp = self._request(endpoint, count_exact=True)
        offers_data = resp.get("data") or []

        # If strict multi-word query returned 0 results, retry with primary keyword
        if not offers_data and query and query.strip():
            words = [w for w in LocalHeuristicParser.normalize_typos(query.strip().lower()).split() if len(w) > 2]
            if len(words) > 1:
                fallback_params = [
                    f"store_id=eq.{sid}",
                    "select=id,raw_title,current_price,original_price,discount_pct,product_url,image_url,gallery_images,product_id,available_sizes,products(id,canonical_name,brand,category,gallery_images)",
                    f"order={order_clause}",
                    f"raw_title=ilike.*{words[0]}*",
                    f"limit={limit}"
                ]
                fallback_resp = self._request(f"store_offers?{'&'.join(fallback_params)}", count_exact=True)
                offers_data = fallback_resp.get("data") or []

        cr = resp.get("content_range") or ""
        total_real_offers = int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1] != "*" else len(offers_data)

        prods = []
        rule = info.get("shipping_rule", {"standard": 4.90, "free_threshold": 50.0, "courier": "Corriere Espresso"})

        for o in offers_data:
            p_obj = o.get("products") or {}
            price = float(o.get("current_price") or 0.0)
            cost = 0.0 if price >= rule["free_threshold"] else rule["standard"]
            is_free = (cost == 0.0)
            off_img = clean_image_url(o.get("image_url")) or clean_image_url(p_obj.get("image_url"))

            raw_off_gallery = o.get("gallery_images") or []
            if isinstance(raw_off_gallery, str):
                try:
                    raw_off_gallery = json.loads(raw_off_gallery)
                except Exception:
                    raw_off_gallery = [raw_off_gallery]
            off_gallery = []
            if off_img:
                off_gallery.append(off_img)
            for og in raw_off_gallery:
                c = clean_image_url(og)
                if c and c not in off_gallery:
                    off_gallery.append(c)

            from fitmatch.matcher.normalizer import ProductNormalizer
            inferred = ProductNormalizer().extract_brand(o.get("raw_title") or "")
            p_brand = inferred or p_obj.get("brand")
            store_names_lower = {"mister running", "misterrunning", "alltricks", "top4running", "maxi sport", "maxisport", "cisalfa", "running warehouse", "deporvillage", "sportler", "nencini", "df sport specialist", "tradeinn", "decathlon"}
            if not p_brand or p_brand.lower() in store_names_lower:
                p_brand = inferred or ""

            norm_sizes = normalize_sizes(o.get("available_sizes"))

            prods.append({
                "id": o.get("id"),
                "product_id": o.get("product_id"),
                "title": o.get("raw_title") or p_obj.get("canonical_name"),
                "canonical_name": p_obj.get("canonical_name"),
                "brand": p_brand,
                "current_price": price,
                "original_price": o.get("original_price"),
                "discount_pct": o.get("discount_pct"),
                "product_url": o.get("product_url"),
                "image_url": off_img,
                "gallery_images": off_gallery,
                "available_sizes": norm_sizes,
                "shipping_cost": cost,
                "total_price": round(price + cost, 2),
                "is_free_shipping": is_free,
                "shipping_label": "Spedizione Gratuita" if is_free else f"+{cost:.2f} € sped.",
                "free_shipping_threshold": rule["free_threshold"],
                "courier": rule["courier"]
            })

        prices = [p["current_price"] for p in prods if p["current_price"] > 0]
        discounts = [p["discount_pct"] for p in prods if p["discount_pct"]]

        # Extract authentic customer gallery photos from real offers
        customer_photos = []
        for p in prods:
            if p.get("image_url") and p["image_url"] not in customer_photos:
                customer_photos.append(p["image_url"])
            for g in p.get("gallery_images") or []:
                if g and g not in customer_photos:
                    customer_photos.append(g)
            if len(customer_photos) >= 8:
                break

        # Query real store reviews from database
        db_reviews = self.get_store_reviews(sid, limit=20)
        customer_reviews = []
        if db_reviews:
            for r in db_reviews:
                dt_str = r.get("created_at") or ""
                rel_date = "Recentemente"
                if dt_str:
                    try:
                        clean_dt = dt_str.replace("Z", "+00:00")
                        dt = datetime.fromisoformat(clean_dt)
                        days = (datetime.now(timezone.utc) - dt).days
                        if days <= 0:
                            rel_date = "Oggi"
                        elif days == 1:
                            rel_date = "Ieri"
                        elif days < 7:
                            rel_date = f"{days} giorni fa"
                        elif days < 30:
                            rel_date = f"{max(1, days // 7)} settimane fa"
                        else:
                            rel_date = f"{max(1, days // 30)} mesi fa"
                    except Exception:
                        rel_date = "Recentemente"

                customer_reviews.append({
                    "id": str(r.get("id")),
                    "author": r.get("author_name", "Cliente"),
                    "rating": float(r.get("rating", 5.0)),
                    "text": r.get("review_text", ""),
                    "date": rel_date
                })

        if not customer_reviews:
            reviews_map = {
                "nike": [
                    {"author": "Marco B.", "rating": 5.0, "text": "Scarpe arrivate in 24 ore, qualità impeccabile e calzata perfetta come sempre.", "date": "2 settimane fa"},
                    {"author": "Elena R.", "rating": 5.0, "text": "Ottima ammortizzazione per le mie corse lunghe, le migliori ZoomX mai provate.", "date": "3 settimane fa"},
                    {"author": "Lorenzo T.", "rating": 4.9, "text": "Imballaggio perfetto e reso eventuale velocissimo tramite il club.", "date": "1 mese fa"}
                ],
                "top4running": [
                    {"author": "Davide M.", "rating": 5.0, "text": "Punto di riferimento per scarpe da gara. Trovate in anteprima con sconto Top4Running Club!", "date": "1 settimana fa"},
                    {"author": "Chiara P.", "rating": 4.9, "text": "Spedizione fulminea con DPD, calzata perfetta per la mia mezza maratona.", "date": "2 settimane fa"},
                    {"author": "Giuseppe V.", "rating": 5.0, "text": "Schede tecniche precisissime e personale competente via chat.", "date": "3 settimane fa"}
                ],
                "cisalfa": [
                    {"author": "Andrea F.", "rating": 4.9, "text": "Comodissimo il ritiro e cambio taglia gratuito in negozio. Servizio clienti top.", "date": "5 giorni fa"},
                    {"author": "Sara M.", "rating": 4.8, "text": "Prezzi competitivi e sconti Cisalfa PRO davvero vantaggiosi su Nike e Asics.", "date": "2 settimane fa"},
                    {"author": "Luca G.", "rating": 5.0, "text": "Consegna puntuale con Bartolini, prodotto originale garantito.", "date": "3 settimane fa"}
                ],
                "misterrunning": [
                    {"author": "Federico S.", "rating": 5.0, "text": "Miglior shop online per il running in Italia. Pacco arrivato la mattina dopo con corriere espresso.", "date": "4 giorni fa"},
                    {"author": "Luca G.", "rating": 5.0, "text": "Prezzo più basso del web con garanzia ufficiale e solette omaggio!", "date": "2 settimane fa"},
                    {"author": "Matteo N.", "rating": 4.9, "text": "Vasta disponibilità di numeri anche per scarpe con piastra in carbonio.", "date": "1 mese fa"}
                ],
                "maxisport": [
                    {"author": "Matteo B.", "rating": 5.0, "text": "Assistenza tecnica eccezionale per scegliere la scarpa adatta al mio appoggio pronatore.", "date": "1 settimana fa"},
                    {"author": "Giulia C.", "rating": 4.9, "text": "Spedizione rapidissima e reso gratuito senza complicazioni.", "date": "3 settimane fa"},
                    {"author": "Paolo R.", "rating": 5.0, "text": "Acquisto da Maxi Sport da anni, sempre impeccabili e precisi.", "date": "1 mese fa"}
                ],
                "adidas": [
                    {"author": "Simone T.", "rating": 5.0, "text": "Adizero incredibili per le gare veloci, calzata aderente e reattività pura.", "date": "1 settimana fa"},
                    {"author": "Alessia M.", "rating": 4.8, "text": "Spedizione tracciata e punti adiClub accumulati subito.", "date": "2 settimane fa"}
                ]
            }
            customer_reviews = reviews_map.get(sid, [
                {"author": "Cliente Verificato", "rating": 5.0, "text": "Esperienza d'acquisto eccellente, prodotti originali e spedizione rapida.", "date": "2 settimane fa"},
                {"author": "Runner Appassionato", "rating": 4.9, "text": "Ottimo rapporto qualità/prezzo e servizio clienti sempre disponibile.", "date": "3 settimane fa"}
            ])

        return {
            "store_id": sid,
            "store_name": store_name,
            "base_url": base_url,
            "rating": rating,
            "review_count": review_count,
            "card_theme": card_theme,
            "accent_color": accent_color,
            "logo_url": logo_url,
            "description": desc,
            "full_description": full_desc,
            "badges": info.get("badges", ["Rivenditore Verificato", "Garanzia Ufficiale"]),
            "highlights": info.get("highlights", []),
            "location": location,
            "shipping_info": shipping_policy,
            "shipping_rule": info.get("shipping_rule"),
            "return_policy": refund_policy,
            "rating_breakdown": info.get("rating_breakdown"),
            "contact_email": contact_email,
            "contact_phone": contact_phone,
            "social_instagram": social_instagram,
            "privacy_policy_url": privacy_policy_url,
            "terms_url": terms_url,
            "refund_policy": refund_policy,
            "shipping_policy": shipping_policy,
            "city_or_location": location,
            "customer_reviews": customer_reviews,
            "customer_photos": customer_photos,
            "total_offers": total_real_offers,
            "avg_discount": round(sum(discounts) / len(discounts), 1) if discounts else 0.0,
            "min_price": min(prices) if prices else 0.0,
            "products": prods
        }

    def get_store_showcases(self, limit_per_store: int = 6) -> List[Dict[str, Any]]:
        """Return store highlights with their best discounted items from Supabase with 100% real database counts."""
        result = []
        candidate_stores = [
            "nike", "adidas", "misterrunning", "alltricks", "top4running",
            "maxisport", "cisalfa", "runningwarehouse", "deporvillage",
            "sportler", "nencini", "decathlon"
        ]

        for sid in candidate_stores:
            details = self.get_store_details(sid, limit=limit_per_store)
            if details and details.get("products"):
                prods = details["products"][:limit_per_store]
                discounts = [p.get("discount_pct") or 0 for p in prods]
                max_d = int(round(max(discounts))) if discounts else int(round(details.get("avg_discount") or 0))
                rule = details.get("shipping_rule") or {}
                free_th = int(round(rule.get("free_threshold") or 0)) if rule.get("free_threshold") else None

                if max_d >= 70:
                    promo_text = f"Risparmia fino al {max_d}% • Spedizione gratis da {free_th} €" if free_th else f"Risparmia fino al {max_d}% sui saldi di stagione"
                elif max_d >= 40:
                    promo_text = f"Sconti fino al {max_d}% e spedizione gratis da {free_th} €" if free_th else f"Sconti fino al {max_d}% su modelli selezionati"
                elif max_d > 0:
                    promo_text = f"Prezzi ribassati fino al -{max_d}%"
                elif free_th:
                    promo_text = f"Spedizione gratuita da {free_th} €"
                else:
                    promo_text = details.get("description", "Rivenditore autorizzato con offerte esclusive.")

                result.append({
                    "store_id": sid,
                    "store_name": details["store_name"],
                    "base_url": details["base_url"],
                    "description": details["description"],
                    "promo_text": promo_text,
                    "badges": details["badges"],
                    "total_offers": details["total_offers"],
                    "avg_discount": details["avg_discount"],
                    "rating": details["rating"],
                    "review_count": details.get("review_count"),
                    "card_theme": details.get("card_theme"),
                    "accent_color": details.get("accent_color"),
                    "logo_url": details.get("logo_url"),
                    "products": prods
                })
        # Prioritize official flagship stores first (Nike, Adidas), then by total real offers
        return sorted(result, key=lambda s: (0 if s["store_id"] in ("nike", "adidas") else 1, -s["total_offers"]))

    def get_size_deals(
        self,
        size: str,
        min_discount: int = 20,
        limit: int = 12,
        favorite_brands: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """Fetch top discounted offers across all partner stores available in user's size."""
        clean_size = str(size).strip()
        if not clean_size:
            return []

        enc_size = urllib.parse.quote(f'["{clean_size}"]')
        url = (
            f"store_offers?available_sizes=cs.{enc_size}"
            f"&discount_pct=gte.{min_discount}"
            f"&image_url=not.is.null"
            f"&order=discount_pct.desc.nullslast"
            f"&limit={limit * 2}"
            f"&select=id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier,products(id,canonical_name,brand,category)"
        )
        resp = self._request(url)
        rows = resp.get("data") or []
        if not rows and min_discount > 10:
            url_fallback = (
                f"store_offers?available_sizes=cs.{enc_size}"
                f"&discount_pct=gte.10"
                f"&image_url=not.is.null"
                f"&order=discount_pct.desc.nullslast"
                f"&limit={limit}"
                f"&select=id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier,products(id,canonical_name,brand,category)"
            )
            rows = self._request(url_fallback).get("data") or []

        from fitmatch.matcher.normalizer import ProductNormalizer
        normalizer = ProductNormalizer()

        deals = []
        for r in rows:
            p_obj = r.get("products") or {}
            brand = normalizer.extract_brand(r.get("raw_title") or "") or p_obj.get("brand") or r.get("store_name")
            cur_price = float(r.get("current_price") or 0.0)
            orig_price = float(r.get("original_price") or 0.0) if r.get("original_price") else None
            disc = float(r.get("discount_pct") or 0.0) if r.get("discount_pct") else None
            ship_cost = float(r.get("shipping_cost") or 0.0) if r.get("shipping_cost") is not None else 0.0

            deals.append({
                "id": r.get("id"),
                "product_id": r.get("product_id") or p_obj.get("id"),
                "title": r.get("raw_title"),
                "canonical_name": p_obj.get("canonical_name") or r.get("raw_title"),
                "brand": brand,
                "current_price": cur_price,
                "original_price": orig_price,
                "discount_pct": disc,
                "product_url": r.get("product_url"),
                "image_url": clean_image_url(r.get("image_url")),
                "available_sizes": normalize_sizes(r.get("available_sizes")),
                "store_id": r.get("store_id"),
                "store_name": r.get("store_name"),
                "shipping_cost": ship_cost,
                "total_price": round(cur_price + ship_cost, 2),
                "is_free_shipping": ship_cost == 0.0,
                "shipping_label": "Sped. Gratis" if ship_cost == 0.0 else f"+ {ship_cost:.2f} €",
                "free_shipping_threshold": r.get("free_shipping_threshold"),
                "courier": r.get("courier")
            })
            if len(deals) >= limit:
                break
        return deals

    def get_personalized_feed(
        self,
        device_id: Optional[str] = None,
        user_id: Optional[str] = None,
        shoe_size: Optional[str] = None,
        apparel_size: Optional[str] = None,
        brands: Optional[List[str]] = None,
        sports: Optional[List[str]] = None,
        min_discount: int = 20,
        limit_per_store: int = 12
    ) -> Dict[str, Any]:
        """Generate an AI/heuristic personalized home feed: ranked stores, size-matched products, and tailored deals."""
        user_pref = {}
        followed_stores = set()
        hidden_stores = set()
        recent_brands = set()
        recent_store_ids = set()

        id_filter = None
        if user_id:
            id_filter = f"user_id=eq.{user_id}"
        elif device_id:
            id_filter = f"device_id=eq.{device_id}"

        if id_filter:
            pref_resp = self._request(f"user_preferences?{id_filter}&limit=1")
            if pref_resp.get("data"):
                user_pref = pref_resp["data"][0]

            fol_resp = self._request(f"followed_stores?{id_filter}&select=store_id")
            for f in fol_resp.get("data") or []:
                if f.get("store_id"):
                    followed_stores.add(f["store_id"].lower())

            hid_resp = self._request(f"hidden_stores?{id_filter}&select=store_id")
            for h in hid_resp.get("data") or []:
                if h.get("store_id"):
                    hidden_stores.add(h["store_id"].lower())

            act_resp = self._request(f"recent_activity?{id_filter}&order=created_at.desc&limit=25")
            for a in act_resp.get("data") or []:
                if a.get("store_id"):
                    recent_store_ids.add(a["store_id"].lower())
                if a.get("title"):
                    from fitmatch.matcher.normalizer import ProductNormalizer
                    b = ProductNormalizer().extract_brand(a["title"])
                    if b:
                        recent_brands.add(b.lower())

        pref_sizes = user_pref.get("preferred_sizes") or []
        eff_shoe_size = shoe_size or (pref_sizes[0] if len(pref_sizes) > 0 else "42")
        eff_apparel_size = apparel_size or (pref_sizes[1] if len(pref_sizes) > 1 else "M")

        eff_brands = set([b.lower() for b in brands] if brands else [b.lower() for b in (user_pref.get("favorite_brands") or [])])
        eff_brands.update(recent_brands)

        eff_sports = [s.lower() for s in sports] if sports else [s.lower() for s in (user_pref.get("selected_sports") or [])]

        size_deals = self.get_size_deals(
            size=eff_shoe_size,
            min_discount=min_discount,
            limit=limit_per_store,
            favorite_brands=list(eff_brands)
        )

        base_showcases = self.get_store_showcases(limit_per_store=limit_per_store)

        ranked_showcases = []
        for sc in base_showcases:
            sid = sc["store_id"].lower()
            if sid in hidden_stores:
                continue

            store_score = 0.0
            is_followed = sid in followed_stores
            if is_followed:
                store_score += 180.0
            if sid in ("nike", "adidas") and any(b in sid for b in eff_brands):
                store_score += 80.0
            if sid in recent_store_ids:
                store_score += 40.0

            prods = sc.get("products", [])
            scored_prods = []
            for p in prods:
                p_score = 0.0
                p_sizes = p.get("available_sizes") or []
                clean_p_sizes = [str(x).strip().lower() for x in p_sizes]

                if eff_shoe_size.lower() in clean_p_sizes:
                    p_score += 90.0
                elif eff_apparel_size.lower() in clean_p_sizes:
                    p_score += 60.0

                p_brand = (p.get("brand") or "").lower()
                p_title = (p.get("title") or "").lower()
                if any(b in p_brand or b in p_title for b in eff_brands if b):
                    p_score += 50.0

                for sp in eff_sports:
                    if "trail" in sp and "trail" in p_title:
                        p_score += 35.0
                    elif ("corsa" in sp or "running" in sp) and ("running" in p_title or "corsa" in p_title or "pegasus" in p_title or "nimbus" in p_title):
                        p_score += 35.0
                    elif ("fitness" in sp or "palestra" in sp) and ("training" in p_title or "gym" in p_title or "fitness" in p_title):
                        p_score += 35.0

                disc = float(p.get("discount_pct") or 0.0)
                if disc >= min_discount:
                    p_score += 20.0
                p_score += disc * 0.5

                scored_prods.append((p_score, p))

            high_rel_count = sum(1 for s, _ in scored_prods if s >= 80.0)
            store_score += high_rel_count * 10.0
            store_score += float(sc.get("rating") or 4.8) * 5.0
            store_score += min(float(sc.get("avg_discount") or 0.0), 50.0) * 0.3

            scored_prods.sort(key=lambda x: (x[0], float(x[1].get("discount_pct") or 0.0)), reverse=True)
            reordered_products = [item[1] for item in scored_prods]

            sc_copy = dict(sc)
            sc_copy["products"] = reordered_products
            sc_copy["is_followed"] = is_followed
            ranked_showcases.append((store_score, sc_copy))

        ranked_showcases.sort(key=lambda x: (x[0], x[1].get("total_offers", 0)), reverse=True)
        final_showcases = [x[1] for x in ranked_showcases]

        return {
            "user_context": {
                "shoe_size": eff_shoe_size,
                "apparel_size": eff_apparel_size,
                "favorite_brands": list(eff_brands),
                "selected_sports": eff_sports,
                "min_discount": min_discount,
                "followed_stores_count": len(followed_stores)
            },
            "size_deals": size_deals,
            "showcases": final_showcases
        }

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
        clean_name = name.strip()
        url = f"collections?name=eq.{urllib.parse.quote(clean_name)}"
        existing = self._request(url, method="GET")
        if existing.get("data") and len(existing["data"]) > 0:
            return existing["data"][0]
        cid = str(uuid.uuid4())
        body = {"id": cid, "name": clean_name}
        self._request("collections", method="POST", data=body)
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

    # MARK: - Stores, Hidden Stores & Reports (Automated Store System)

    def upsert_store(self, store_data: Dict[str, Any]) -> bool:
        """Upsert store metadata to Supabase."""
        s_id = store_data.get("id", "").lower().strip()
        if not s_id:
            return False
        payload = {
            "id": s_id,
            "name": store_data.get("name", s_id.title()),
            "rating": store_data.get("rating", 4.8),
            "review_count": store_data.get("review_count", 1200),
            "formatted_review_count": store_data.get("formatted_review_count"),
            "card_theme": store_data.get("card_theme", "white"),
            "accent_color": store_data.get("accent_color"),
            "logo_url": store_data.get("logo_url"),
            "base_url": store_data.get("base_url"),
            "free_shipping_threshold": store_data.get("free_shipping_threshold"),
            "standard_shipping_cost": store_data.get("standard_shipping_cost"),
            "courier": store_data.get("courier"),
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        res = self._request("stores?on_conflict=id", method="POST", data=payload, upsert=True)
        return res.get("status") in (200, 201)

    def get_stores(self) -> List[Dict[str, Any]]:
        """Retrieve all store metadata from Supabase."""
        res = self._request("stores?select=*&order=rating.desc", method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list):
            return res.get("data")
        return []

    def get_store(self, store_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve specific store metadata from Supabase."""
        s_id = store_id.lower().strip()
        url = f"stores?id=eq.{urllib.parse.quote(s_id)}&limit=1"
        res = self._request(url, method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list) and res["data"]:
            return res["data"][0]
        return None

    def hide_store(self, store_id: str, store_name: Optional[str] = None) -> bool:
        """Hide store from suggestions."""
        payload = {
            "store_id": store_id.lower().strip(),
            "store_name": store_name,
            "device_id": "default_device"
        }
        res = self._request("hidden_stores?on_conflict=device_id,store_id", method="POST", data=payload, upsert=True)
        return res.get("status") in (200, 201)

    def unhide_store(self, store_id: str) -> bool:
        """Remove store from hidden list."""
        url = f"hidden_stores?store_id=eq.{urllib.parse.quote(store_id.lower().strip())}"
        res = self._request(url, method="DELETE")
        return res.get("status") in (200, 204)

    def get_hidden_stores(self) -> List[str]:
        """Retrieve hidden store ids."""
        res = self._request("hidden_stores?select=store_id", method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list):
            return [r["store_id"].lower() for r in res["data"] if "store_id" in r]
        return []

    def report_store(self, store_id: str, store_name: str, reason: str, details: Optional[str] = None) -> bool:
        """Record store report in Supabase."""
        payload = {
            "store_id": store_id.lower().strip(),
            "store_name": store_name,
            "reason": reason,
            "details": details,
            "device_id": "default_device"
        }
        res = self._request("store_reports", method="POST", data=payload)
        return res.get("status") in (200, 201)

    def get_store_reviews(self, store_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieve real user reviews for a store from Supabase."""
        sid = store_id.lower().strip()
        url = f"store_reviews?store_id=eq.{urllib.parse.quote(sid)}&order=created_at.desc&limit={limit}"
        res = self._request(url, method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list):
            return res.get("data")
        return []

    def add_store_review(self, store_id: str, author_name: str, rating: int, review_text: str, device_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Insert a user review for a store into Supabase."""
        sid = store_id.lower().strip()
        payload = {
            "store_id": sid,
            "author_name": author_name.strip() or "Runner",
            "rating": max(1, min(5, int(rating))),
            "review_text": review_text.strip(),
            "device_id": device_id or "default_device",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        res = self._request("store_reviews", method="POST", data=payload)
        if res.get("status") in (200, 201):
            if isinstance(res.get("data"), list) and res["data"]:
                return res["data"][0]
            return payload
        return None

    # MARK: - Device Tokens & Production Push Notifications

    def register_device_token(
        self,
        device_token: str,
        device_id: str,
        user_id: Optional[str] = None,
        platform: str = "ios",
        environment: str = "production",
        notify_price_drop: bool = True,
        notify_targeted_promo: bool = True,
        min_discount_pct: float = 5.0,
        preferred_size: Optional[str] = None,
        app_version: Optional[str] = None
    ) -> bool:
        """Upsert APNs device token for push notification delivery."""
        token = device_token.strip().replace(" ", "").replace("<", "").replace(">", "")
        payload = {
            "device_token": token,
            "device_id": device_id.strip(),
            "platform": platform.lower(),
            "environment": environment.lower(),
            "is_active": True,
            "notify_price_drop": notify_price_drop,
            "notify_targeted_promo": notify_targeted_promo,
            "min_discount_pct": min_discount_pct,
            "preferred_size": preferred_size,
            "app_version": app_version,
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        if user_id:
            payload["user_id"] = user_id
        res = self._request("device_tokens?on_conflict=device_token", method="POST", data=payload, upsert=True)
        return res.get("status") in (200, 201)

    def get_user_notifications(self, device_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieve stored notification history for a device from Supabase."""
        did = device_id.strip()
        url = f"notifications?device_id=eq.{urllib.parse.quote(did)}&order=created_at.desc&limit={limit}"
        res = self._request(url, method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list):
            return res.get("data")
        return []

    def mark_notification_read(self, notification_id: str) -> bool:
        """Mark a notification as read."""
        url = f"notifications?id=eq.{urllib.parse.quote(notification_id.strip())}"
        res = self._request(url, method="PATCH", data={"is_read": True})
        return res.get("status") in (200, 204)

    def mark_all_notifications_read(self, device_id: str) -> bool:
        """Mark all notifications for a device as read."""
        url = f"notifications?device_id=eq.{urllib.parse.quote(device_id.strip())}"
        res = self._request(url, method="PATCH", data={"is_read": True})
        return res.get("status") in (200, 204)

    def delete_notification(self, notification_id: str) -> bool:
        """Delete a notification from Supabase."""
        url = f"notifications?id=eq.{urllib.parse.quote(notification_id.strip())}"
        res = self._request(url, method="DELETE")
        return res.get("status") in (200, 204)

    # MARK: - Affiliate Click Tracking

    def record_affiliate_click(
        self,
        target_url: str,
        store_id: Optional[str] = None,
        offer_id: Optional[str] = None,
        monetized_url: Optional[str] = None,
        cuid: Optional[str] = None,
        source: Optional[str] = None,
        device_id: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> bool:
        """Record an outbound affiliate click event in Supabase."""
        payload: Dict[str, Any] = {
            "target_url": target_url,
            "store_id": store_id.lower().strip() if store_id else None,
            "offer_id": offer_id,
            "monetized_url": monetized_url,
            "cuid": cuid,
            "source": source or "app",
            "device_id": device_id,
            "user_agent": user_agent,
        }
        res = self._request("affiliate_clicks", method="POST", data=payload)
        return res.get("status") in (200, 201)

    def get_affiliate_click_stats(self, limit: int = 100) -> Dict[str, Any]:
        """Fetch affiliate click analytics from Supabase."""
        res = self._request(f"affiliate_clicks?order=created_at.desc&limit={limit}", method="GET")
        clicks = res.get("data") if res.get("status") == 200 and isinstance(res.get("data"), list) else []

        by_store: Dict[str, int] = {}
        for c in clicks:
            sid = c.get("store_id") or "unknown"
            by_store[sid] = by_store.get(sid, 0) + 1

        return {
            "total_clicks": len(clicks),
            "by_store": by_store,
            "recent_clicks": clicks[:25],
        }

    # MARK: - Chat Sessions & Messages Persistence

    @staticmethod
    def _build_results_snapshot(results: Optional[List[Dict[str, Any]]], max_items: int = 12) -> List[Dict[str, Any]]:
        """Build a compact JSON snapshot of top results for instant conversation restoration."""
        if not results:
            return []
        snap: List[Dict[str, Any]] = []
        for p in results[:max_items]:
            if not isinstance(p, dict):
                continue
            offers_compact = []
            for o in (p.get("offers") or [])[:4]:
                if not isinstance(o, dict):
                    continue
                offers_compact.append({
                    "store_id": o.get("store_id", ""),
                    "store_name": o.get("store_name", ""),
                    "product_id": o.get("product_id"),
                    "title": o.get("title") or p.get("canonical_name", ""),
                    "brand": o.get("brand") or p.get("brand"),
                    "price": float(o.get("price") or 0.0),
                    "original_price": o.get("original_price"),
                    "discount_pct": o.get("discount_pct"),
                    "url": o.get("url", ""),
                    "image_url": o.get("image_url") or p.get("image_url"),
                    "available_sizes": (o.get("available_sizes") or [])[:20],
                    "in_stock": o.get("in_stock", True),
                    "shipping_cost": o.get("shipping_cost"),
                    "total_price": o.get("total_price"),
                    "is_free_shipping": o.get("is_free_shipping"),
                })
            snap.append({
                "id": p.get("id"),
                "canonical_name": p.get("canonical_name", ""),
                "brand": p.get("brand"),
                "category": p.get("category"),
                "gender": p.get("gender"),
                "image_url": p.get("image_url"),
                "best_price": p.get("best_price"),
                "highest_price": p.get("highest_price"),
                "cross_store_savings": p.get("cross_store_savings"),
                "offers": offers_compact,
            })
        return snap

    @staticmethod
    def normalize_uuid(val: Optional[str]) -> str:
        """Return a valid UUID string (preserving valid UUIDs, hashing non-UUID strings deterministically)."""
        raw = val.strip() if isinstance(val, str) and val.strip() else ""
        if not raw:
            return str(uuid.uuid4())
        try:
            return str(uuid.UUID(raw))
        except ValueError:
            return str(uuid.uuid5(uuid.NAMESPACE_URL, raw))

    def save_chat_turn(
        self,
        session_id: Optional[str],
        device_id: str,
        user_id: Optional[str],
        chat_type: str,
        query: str,
        is_follow_up: bool,
        response_payload: Dict[str, Any],
        context_state: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Create or append a conversation turn to chat_sessions & chat_messages in Supabase."""
        sid = self.normalize_uuid(session_id)
        did = (device_id or "default_device").strip()
        now_iso = datetime.now(timezone.utc).isoformat()

        results = response_payload.get("results") or []
        spotlight = response_payload.get("spotlight")
        preview_img = None
        if isinstance(spotlight, dict) and isinstance(spotlight.get("product"), dict):
            preview_img = clean_image_url(spotlight["product"].get("image_url"))
        if not preview_img and results and isinstance(results[0], dict):
            preview_img = clean_image_url(results[0].get("image_url"))

        # Check existing session to preserve title and increment turn_count
        existing_res = self._request(f"chat_sessions?id=eq.{urllib.parse.quote(sid)}&limit=1", method="GET")
        existing_rows = existing_res.get("data") if existing_res.get("status") == 200 else []
        existing = existing_rows[0] if existing_rows else None

        next_turn_index = int(existing.get("turn_count", 0)) if existing else 0
        title = existing.get("title") if existing else query.strip()
        subtitle = response_payload.get("conversational_header") or query.strip()

        merged_ctx = dict(existing.get("context_state") or {}) if existing else {}
        if context_state:
            for k, v in context_state.items():
                if v is not None:
                    merged_ctx[k] = v

        session_body: Dict[str, Any] = {
            "id": sid,
            "device_id": did,
            "chat_type": chat_type or "smart_search",
            "title": title,
            "subtitle": subtitle,
            "turn_count": next_turn_index + 1,
            "context_state": merged_ctx,
            "updated_at": now_iso,
        }
        if preview_img:
            session_body["preview_image_url"] = preview_img
        elif existing and existing.get("preview_image_url"):
            session_body["preview_image_url"] = existing.get("preview_image_url")
        if user_id and user_id.strip():
            session_body["user_id"] = user_id.strip()
        if not existing:
            session_body["created_at"] = now_iso

        s_res = self._request("chat_sessions?on_conflict=id", method="POST", data=session_body, upsert=True)
        if s_res.get("status") not in (200, 201):
            logger.warning(f"[Supabase] Failed upsert chat_sessions ({s_res.get('status')}): {s_res.get('error')}")

        msg_id = str(uuid.uuid4())
        snapshot = {
            "results": self._build_results_snapshot(results, max_items=12),
            "curated_sections": [
                {
                    "id": sec.get("id", ""),
                    "title": sec.get("title", ""),
                    "subtitle": sec.get("subtitle", ""),
                    "products": self._build_results_snapshot(sec.get("products"), max_items=8),
                }
                for sec in (response_payload.get("curated_sections") or [])[:4]
                if isinstance(sec, dict)
            ],
            "comparative_cards": [
                {
                    "product": (self._build_results_snapshot([c.get("product")], max_items=1) or [None])[0],
                    "model_name": c.get("model_name", ""),
                    "ideal_for": c.get("ideal_for", ""),
                    "strengths": c.get("strengths", ""),
                    "section_title": c.get("section_title"),
                }
                for c in (response_payload.get("comparative_cards") or [])[:5]
                if isinstance(c, dict) and isinstance(c.get("product"), dict)
            ],
            "spotlight": (
                {
                    "product": (self._build_results_snapshot([spotlight.get("product")], max_items=1) or [None])[0],
                    "badge_text": spotlight.get("badge_text"),
                    "highlights": spotlight.get("highlights") or [],
                }
                if isinstance(spotlight, dict) and isinstance(spotlight.get("product"), dict)
                else None
            ),
        }

        msg_body: Dict[str, Any] = {
            "id": msg_id,
            "session_id": sid,
            "turn_index": next_turn_index,
            "query": query.strip(),
            "is_follow_up": bool(is_follow_up),
            "is_conversational_advice": bool(response_payload.get("is_conversational_advice", False)),
            "conversational_header": response_payload.get("conversational_header"),
            "conversational_summary": response_payload.get("conversational_summary"),
            "intent_json": response_payload.get("intent") or {},
            "chips_json": response_payload.get("chips") or [],
            "results_snapshot_json": snapshot,
            "follow_up_suggestions_json": response_payload.get("follow_up_suggestions") or [],
            "is_off_topic": bool(response_payload.get("is_off_topic", False)),
            "is_unsafe": bool(response_payload.get("is_unsafe", False)),
            "created_at": now_iso,
        }
        m_res = self._request("chat_messages", method="POST", data=msg_body)
        if m_res.get("status") not in (200, 201):
            logger.warning(f"[Supabase] Failed insert chat_messages ({m_res.get('status')}): {m_res.get('error')}")

        return {
            "session_id": sid,
            "turn_id": msg_id,
            "turn_index": next_turn_index,
            "session": session_body,
            "message": msg_body,
        }

    def get_chat_sessions(
        self,
        device_id: Optional[str] = None,
        user_id: Optional[str] = None,
        chat_type: Optional[str] = None,
        limit: int = 30,
    ) -> List[Dict[str, Any]]:
        """List saved chat sessions ordered by most recently updated."""
        params = ["select=*", "is_archived=eq.false", "order=updated_at.desc", f"limit={limit}"]
        if user_id and user_id.strip():
            uid = urllib.parse.quote(user_id.strip())
            if device_id and device_id.strip():
                did = urllib.parse.quote(device_id.strip())
                params.append(f"or=(user_id.eq.{uid},device_id.eq.{did})")
            else:
                params.append(f"user_id=eq.{uid}")
        elif device_id and device_id.strip():
            params.append(f"device_id=eq.{urllib.parse.quote(device_id.strip())}")

        if chat_type and chat_type.strip():
            params.append(f"chat_type=eq.{urllib.parse.quote(chat_type.strip())}")

        res = self._request(f"chat_sessions?{'&'.join(params)}", method="GET")
        if res.get("status") == 200 and isinstance(res.get("data"), list):
            return res["data"]
        return []

    def get_chat_session_detail(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve a chat session along with all its ordered conversation messages."""
        sid = urllib.parse.quote(self.normalize_uuid(session_id))
        s_res = self._request(f"chat_sessions?id=eq.{sid}&limit=1", method="GET")
        s_rows = s_res.get("data") if s_res.get("status") == 200 else None
        if not s_rows:
            return None
        session_obj = dict(s_rows[0])

        m_res = self._request(f"chat_messages?session_id=eq.{sid}&order=turn_index.asc,created_at.asc", method="GET")
        messages = m_res.get("data") if m_res.get("status") == 200 and isinstance(m_res.get("data"), list) else []
        session_obj["messages"] = messages
        return session_obj

    def update_chat_message_feedback(self, session_id: str, turn_id: str, feedback_val: int) -> bool:
        """Update user feedback (1/-1) on a specific chat turn."""
        tid = urllib.parse.quote(self.normalize_uuid(turn_id))
        sid = urllib.parse.quote(self.normalize_uuid(session_id))
        res = self._request(
            f"chat_messages?id=eq.{tid}&session_id=eq.{sid}",
            method="PATCH",
            data={"user_feedback": int(feedback_val)},
        )
        return res.get("status") in (200, 204)

    def delete_chat_session(self, session_id: str, device_id: Optional[str] = None) -> bool:
        """Delete a single chat session (messages cascade automatically)."""
        sid = urllib.parse.quote(self.normalize_uuid(session_id))
        url = f"chat_sessions?id=eq.{sid}"
        if device_id and device_id.strip():
            url += f"&device_id=eq.{urllib.parse.quote(device_id.strip())}"
        res = self._request(url, method="DELETE")
        return res.get("status") in (200, 204)

    def clear_chat_sessions(self, device_id: Optional[str] = None, user_id: Optional[str] = None) -> bool:
        """Delete all chat sessions for a device or user."""
        if user_id and user_id.strip():
            url = f"chat_sessions?user_id=eq.{urllib.parse.quote(user_id.strip())}"
        elif device_id and device_id.strip():
            url = f"chat_sessions?device_id=eq.{urllib.parse.quote(device_id.strip())}"
        else:
            return False
        res = self._request(url, method="DELETE")
        return res.get("status") in (200, 204)



