import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  detectSingleProductType,
  extractBrand,
  extractSpecificEntityTokens,
  jsonResponse,
  normalizeQueryTypos,
  searchCatalogOffers,
} from "../_shared/catalog.ts";

interface ModelSpecs {
  name: string;
  brand: string | null;
  drop_mm: number | null;
  weight_g: number | null;
  cushioning: string | null;
  midsole: string | null;
  plate: string | null;
  ideal_use: string | null;
  target_runner: string | null;
  pros: string[];
  cons: string[];
}

const LOCAL_SPECS: Record<string, ModelSpecs> = {
  pegasus: {
    name: "Nike Pegasus 41",
    brand: "Nike",
    drop_mm: 10,
    weight_g: 285,
    cushioning: "Bilanciato & Elastico",
    midsole: "ReactX + 2x Air Zoom",
    plate: "Nessuna",
    ideal_use: "Daily trainer versatile per qualsiasi distanza",
    target_runner: "Runner neutri di ogni livello per allenamenti quotidiani",
    pros: ["Eccezionale longevità del battistrada", "Grande versatilità di ritmi", "Ottimo prezzo"],
    cons: ["Meno ammortizzata oltre gli 80kg", "Non pensata per gare veloci"],
  },
  nimbus: {
    name: "Asics Gel Nimbus 26",
    brand: "Asics",
    drop_mm: 8,
    weight_g: 305,
    cushioning: "Massimo Ammortizzamento",
    midsole: "FF BLAST+ ECO + PureGEL",
    plate: "Nessuna",
    ideal_use: "Lunghi su asfalto, lenti rigeneranti e protezione",
    target_runner: "Runner medi o pesanti (>75kg) e chi vuole proteggere ginocchia e schiena",
    pros: ["Morbidezza e comfort ai vertici della categoria", "Tomaia in knit premium", "Elevata stabilità"],
    cons: ["Peso più elevato", "Meno reattiva a ritmi sostenuti (<4:20 min/km)"],
  },
  clifton: {
    name: "Hoka Clifton 9",
    brand: "Hoka",
    drop_mm: 5,
    weight_g: 248,
    cushioning: "Morbido & Leggero",
    midsole: "CMEVA sagomata a compressione",
    plate: "Nessuna",
    ideal_use: "Allenamenti quotidiani a ritmo medio ed endurance",
    target_runner: "Runner che cercano geometria Meta-Rocker e basso drop",
    pros: ["Rapporto peso/ammortizzamento eccezionale", "Rullata fluida con Meta-Rocker", "Grande comodità"],
    cons: ["Drop basso (5mm) richiede adattamento ai polpacci", "Tomaia calda d'estate"],
  },
  ghost: {
    name: "Brooks Ghost 16",
    brand: "Brooks",
    drop_mm: 12,
    weight_g: 270,
    cushioning: "Bilanciato & Neutro",
    midsole: "DNA LOFT v3 con infusione di azoto",
    plate: "Nessuna",
    ideal_use: "Daily trainer per chi atterra di tallone",
    target_runner: "Runner con appoggio tallonare che amano calzata tradizionale",
    pros: ["Transizione tacco-punta fluida", "Intersuola morbida e leggera con azoto", "Affidabilità comprovata"],
    cons: ["Drop alto (12mm) non adatto a chi corre d'avampiede", "Design sobrio"],
  },
  novablast: {
    name: "Asics Novablast 4",
    brand: "Asics",
    drop_mm: 8,
    weight_g: 260,
    cushioning: "Energetico & Elastico",
    midsole: "FF BLAST+ ECO a geometria trampolino",
    plate: "Nessuna",
    ideal_use: "Ritmi medi, corse progressive e lunghi brillanti",
    target_runner: "Runner neutri alla ricerca di scarpa scattante senza piastra",
    pros: ["Ritorno di energia esuberante", "Geometria trampolino molto divertente", "Peso contenuto"],
    cons: ["Stabilità laterale ridotta per iperpronatori", "Fondo scivoloso su bagnato"],
  },
  alphafly: {
    name: "Nike Alphafly 3",
    brand: "Nike",
    drop_mm: 8,
    weight_g: 218,
    cushioning: "Massima Reattività da Gara",
    midsole: "ZoomX integrale + doppio Air Pod",
    plate: "Fibra di Carbonio Flyplate a tutta lunghezza",
    ideal_use: "Gara maratona e mezza maratona",
    target_runner: "Podisti evoluti con buona tecnica alla ricerca del record personale",
    pros: ["Efficienza energetica impareggiabile", "ZoomX continuo per transizioni rapide", "Leggerezza estrema"],
    cons: ["Prezzo molto elevato", "Durata limitata ai chilometri di gara", "Richiede caviglie forti"],
  },
  "forerunner 165": {
    name: "Garmin Forerunner 165",
    brand: "Garmin",
    drop_mm: 0,
    weight_g: 39,
    cushioning: "Smartwatch GPS Corsa",
    midsole: "Display AMOLED touchscreen 1.2 pollici",
    plate: "Sensore cardio Elevate Gen 4",
    ideal_use: "Monitoraggio corsa, passo, recupero e sonno",
    target_runner: "Runner amatori e principianti che vogliono metriche Garmin con display AMOLED",
    pros: ["Display AMOLED brillante", "Prezzo competitivo per un Garmin AMOLED", "Autonomia fino a 11 giorni"],
    cons: ["Niente mappe cartografiche offline", "GPS a singola frequenza (non multibanda)"],
  },
  "forerunner 265": {
    name: "Garmin Forerunner 265",
    brand: "Garmin",
    drop_mm: 0,
    weight_g: 47,
    cushioning: "Smartwatch GPS Avanzato",
    midsole: "Display AMOLED touchscreen + GPS Multibanda",
    plate: "Training Readiness & Metriche Avanzate",
    ideal_use: "Triathlon, maratona e atleti multisport",
    target_runner: "Atleti intermedi ed evoluti che necessitano di Training Readiness e GPS a doppia frequenza",
    pros: ["GPS Multibanda ad altissima precisione", "Metrica Training Readiness completa", "Supporto Triathlon"],
    cons: ["Prezzo più alto del 165", "Nessuna cartografia topografica completa (riservata al 965)"],
  },
};

function isBlockedQuery(q: string): boolean {
  const low = q.toLowerCase();
  return /\b(ricetta|cucina|politica|meteo|oroscopo|borsa|crypto|bitcoin|codice|python|sql|hack)\b/i.test(low);
}

function getHeuristicSpec(query: string): ModelSpecs {
  const q = query.toLowerCase();
  for (const [k, v] of Object.entries(LOCAL_SPECS)) {
    if (q.includes(k)) return v;
  }
  return {
    name: query.trim(),
    brand: "Sport Tech",
    drop_mm: 8,
    weight_g: 280,
    cushioning: "Standard",
    midsole: "Mescola ammortizzante tecnica",
    plate: "Nessuna",
    ideal_use: "Allenamento e attività sportiva",
    target_runner: "Sportivi di livello amatoriale",
    pros: ["Comfort affidabile", "Costruzione resistente"],
    cons: ["Caratteristiche non specialistiche"],
  };
}

function toSpec(raw: Record<string, unknown> | undefined, fallbackQuery: string): ModelSpecs {
  if (!raw) return getHeuristicSpec(fallbackQuery);
  return {
    name: String(raw.name ?? fallbackQuery),
    brand: raw.brand ? String(raw.brand) : null,
    drop_mm: typeof raw.drop_mm === "number" ? raw.drop_mm : null,
    weight_g: typeof raw.weight_g === "number" ? raw.weight_g : null,
    cushioning: raw.cushioning ? String(raw.cushioning) : null,
    midsole: raw.midsole ? String(raw.midsole) : null,
    plate: raw.plate ? String(raw.plate) : null,
    ideal_use: raw.ideal_use ? String(raw.ideal_use) : null,
    target_runner: raw.target_runner ? String(raw.target_runner) : null,
    pros: Array.isArray(raw.pros) ? raw.pros.map(String) : [],
    cons: Array.isArray(raw.cons) ? raw.cons.map(String) : [],
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    let modelA = url.searchParams.get("model_a") ?? "";
    let modelB = url.searchParams.get("model_b") ?? "";

    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      modelA = String(body?.model_a ?? modelA);
      modelB = String(body?.model_b ?? modelB);
    }

    modelA = modelA.trim();
    modelB = modelB.trim();
    if (modelA.length < 2 || modelB.length < 2) {
      return jsonResponse({ detail: "Specificare entrambi i modelli da confrontare." }, 400);
    }

    if (isBlockedQuery(modelA) || isBlockedQuery(modelB)) {
      return jsonResponse({ detail: "Il confronto tecnico è disponibile esclusivamente per scarpe e attrezzatura sportiva." }, 400);
    }

    const supabase = createServiceClient();
    if (!supabase) {
      return jsonResponse({ detail: "Configurazione Supabase mancante." }, 500);
    }

    const systemPrompt =
      "Sei un esperto biomeccanico e tester professionista di calzature e tecnologia sportiva per 'FitMatch'. " +
      "Analizza con la massima precisione scientifica e tecnica i due modelli richiesti dall'utente. " +
      "Rispondi ESCLUSIVAMENTE con un JSON valido con questa esatta struttura:\n" +
      "{\n" +
      '  "model_a": { "name": "Nome completo modello A", "brand": "Brand", "drop_mm": int o null, "weight_g": int o null, "cushioning": "es. Massimo / Bilanciato / Reattivo", "midsole": "mescola e tecnologie", "plate": "Nessuna / Carbonio / Nylon", "ideal_use": "utilizzo principale", "target_runner": "profilo podista ideale", "pros": ["pro 1", "pro 2", "pro 3"], "cons": ["contro 1", "contro 2"] },\n' +
      '  "model_b": { "name": "Nome completo modello B", "brand": "Brand", "drop_mm": int o null, "weight_g": int o null, "cushioning": "es. Massimo / Bilanciato / Reattivo", "midsole": "mescola e tecnologie", "plate": "Nessuna / Carbonio / Nylon", "ideal_use": "utilizzo principale", "target_runner": "profilo podista ideale", "pros": ["pro 1", "pro 2", "pro 3"], "cons": ["contro 1", "contro 2"] },\n' +
      '  "key_differences": ["differenza 1", "differenza 2", "differenza 3"],\n' +
      '  "verdict_summary": "sintesi chiara in 2 frasi di chi dovrebbe comprare cosa",\n' +
      '  "winner_for_performance": "nome del modello e motivo"\n' +
      "}";

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "meta-llama/llama-3.3-70b-instruct";

    const normA = normalizeQueryTypos(modelA);
    const normB = normalizeQueryTypos(modelB);
    const brandA = extractBrand(normA, null);
    const brandB = extractBrand(normB, null);
    const pTypeA = detectSingleProductType(normA);
    const pTypeB = detectSingleProductType(normB);
    const entsA = extractSpecificEntityTokens(normA, brandA);
    const entsB = extractSpecificEntityTokens(normB, brandB);

    const [prodARes, prodBRes, llmParsed] = await Promise.all([
      searchCatalogOffers(supabase, {
        rawQuery: normA,
        keywords: [normA],
        brand: brandA,
        productType: pTypeA,
        entityTokens: entsA,
        semanticQuery: normA,
        allowSemantic: entsA.length === 0,
        limit: 6,
      }),
      searchCatalogOffers(supabase, {
        rawQuery: normB,
        keywords: [normB],
        brand: brandB,
        productType: pTypeB,
        entityTokens: entsB,
        semanticQuery: normB,
        allowSemantic: entsB.length === 0,
        limit: 6,
      }),
      callOpenRouterJSON({
        systemPrompt,
        userPrompt: `Confronta dettagliatamente il modello A ('${modelA}') con il modello B ('${modelB}').`,
        models: [primaryModel, "meta-llama/llama-3.1-8b-instruct", "openai/gpt-4o-mini"],
        temperature: 0.1,
        maxTokens: 1200,
        title: "FitMatch Price Comparator",
        timeoutMs: 15_000,
      }),
    ]);

    const toMarketData = (query: string, matches: Awaited<ReturnType<typeof searchCatalogOffers>>) => {
      const top = matches[0];
      if (!top) {
        return {
          model_name: query,
          brand: null,
          best_price: null,
          highest_price: null,
          best_store: null,
          image_url: null,
          total_offers: 0,
          cross_store_savings: null,
          top_offers: [],
        };
      }
      return {
        model_name: top.canonical_name,
        brand: top.brand,
        best_price: top.best_price,
        highest_price: top.highest_price,
        best_store: top.offers[0]?.store_name ?? null,
        image_url: top.image_url,
        total_offers: top.offers.length,
        cross_store_savings: top.cross_store_savings,
        top_offers: top.offers.slice(0, 5).map((o) => ({
          store_name: o.store_name,
          price: o.price,
          original_price: o.original_price,
          url: o.url,
          is_free_shipping: o.is_free_shipping,
          total_price: o.total_price,
        })),
      };
    };

    const marketA = toMarketData(modelA, prodARes);
    const marketB = toMarketData(modelB, prodBRes);

    let specsA: ModelSpecs;
    let specsB: ModelSpecs;
    let keyDiffs: string[];
    let verdict: string;
    let winnerPerf: string;
    let source = "openrouter_llama_70b";

    if (llmParsed && llmParsed.model_a && llmParsed.model_b) {
      specsA = toSpec(llmParsed.model_a as Record<string, unknown>, modelA);
      specsB = toSpec(llmParsed.model_b as Record<string, unknown>, modelB);
      keyDiffs = Array.isArray(llmParsed.key_differences) ? llmParsed.key_differences.map(String) : [];
      verdict = String(llmParsed.verdict_summary ?? "");
      winnerPerf = String(llmParsed.winner_for_performance ?? "");
    } else {
      source = "local_heuristic";
      specsA = getHeuristicSpec(modelA);
      specsB = getHeuristicSpec(modelB);
      keyDiffs = [
        `${specsA.name} presenta un drop di ${specsA.drop_mm ?? "N/D"} mm, mentre ${specsB.name} di ${specsB.drop_mm ?? "N/D"} mm.`,
        `Ammortizzamento: ${specsA.cushioning ?? "Standard"} (${specsA.midsole ?? ""}) contro ${specsB.cushioning ?? "Standard"} (${specsB.midsole ?? ""}).`,
        `Peso stimato: circa ${specsA.weight_g ?? "N/D"}g per ${specsA.name} vs ${specsB.weight_g ?? "N/D"}g per ${specsB.name}.`,
      ];
      verdict = `Scegli ${specsA.name} se cerchi ${(specsA.ideal_use ?? "versatilità").toLowerCase()}. Opta invece per ${specsB.name} se il tuo obiettivo principale è ${(specsB.ideal_use ?? "il massimo comfort").toLowerCase()}.`;
      winnerPerf = (specsA.weight_g ?? 300) < (specsB.weight_g ?? 300) ? specsA.name : specsB.name;
    }

    let priceDelta: number | null = null;
    let winnerValue = specsA.name;
    if (marketA.best_price != null && marketB.best_price != null) {
      priceDelta = Math.round(Math.abs(marketA.best_price - marketB.best_price) * 100) / 100;
      if (marketA.best_price < marketB.best_price) {
        const diff = marketB.best_price - marketA.best_price;
        winnerValue = `${specsA.name} (risparmi ${diff.toFixed(2)} € rispetto a ${specsB.name})`;
      } else if (marketB.best_price < marketA.best_price) {
        const diff = marketA.best_price - marketB.best_price;
        winnerValue = `${specsB.name} (risparmi ${diff.toFixed(2)} € rispetto a ${specsA.name})`;
      } else {
        winnerValue = "Prezzi identici: la scelta dipende solo dalle tue preferenze tecniche.";
      }
    }

    return jsonResponse({
      model_a_specs: specsA,
      model_b_specs: specsB,
      model_a_market: marketA,
      model_b_market: marketB,
      key_differences: keyDiffs,
      verdict_summary: verdict,
      winner_for_value: winnerValue,
      winner_for_performance: winnerPerf,
      price_delta: priceDelta,
      source,
    });
  } catch (err) {
    return jsonResponse({ detail: err instanceof Error ? err.message : "Errore interno" }, 500);
  }
});
