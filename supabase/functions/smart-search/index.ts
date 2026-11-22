import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  buildCatalogSearchTerms,
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  detectProductType,
  detectSingleProductType,
  detectSubBrand,
  extractBrand,
  extractSpecificEntityTokens,
  isBroadeningFollowUp,
  jsonResponse,
  mapProductTypeToCategory,
  MatchedProductOut,
  normalizeProductTypeGroup,
  normalizeQueryTypos,
  ProductType,
  saveChatTurn,
  searchCatalogOffers,
} from "../_shared/catalog.ts";

const VALID_PRODUCT_TYPES = new Set<ProductType>([
  "leggings_tights", "shorts", "pants", "long_sleeve_top", "short_sleeve_top",
  "singlet_top", "top", "jacket", "socks", "headwear", "heart_rate_monitor",
  "bike_computer", "gps_watch", "eyewear", "hydration", "swim", "padel_racket",
  "tennis_racket", "football_boots", "basketball_shoes", "tennis_shoes",
  "volleyball_shoes", "trail_shoes", "shoes", "winter_sports", "nutrition",
  "smart_trainer",
]);

function evaluateGuardrail(q: string): { isOffTopic: boolean; isUnsafe: boolean; reason?: string } {
  const low = q.toLowerCase();
  if (/(ignore\s+previous|system\s+prompt|jailbreak|drop\s+table|<script|exec\s*\()/i.test(low)) {
    return {
      isOffTopic: true,
      isUnsafe: true,
      reason: "Posso aiutarti solo con ricerche su scarpe e attrezzatura sportiva su FitMatch.",
    };
  }
  if (/\b(ricetta|cucina|politica|elezioni|oroscopo|meteo|bitcoin|crypto|codice\s+python|scrivi\s+un\s+programma|compiti\s+di\s+storia|film\s+da\s+vedere|ristorante)\b/i.test(low)) {
    return {
      isOffTopic: true,
      isUnsafe: false,
      reason: "Sono l'assistente sportivo di FitMatch: chiedimi scarpe da running, smartwatch GPS, abbigliamento o attrezzatura sportiva!",
    };
  }
  return { isOffTopic: false, isUnsafe: false };
}

function parseLocalConstraints(q: string) {
  const norm = normalizeQueryTypos(q);
  const low = norm.toLowerCase();

  // Range price: "tra 100 e 180 euro"
  const rangeMatch = low.match(/\b(?:tra|da)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?\s*(?:e|a|-)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?\b/);
  const maxPriceMatch = low.match(/(?:sotto\s*i?|meno\s*di|max|massimo|entro\s*i?|fino\s*a|budget\s*(?:di)?)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?/);
  const minPriceMatch = low.match(/(?:sopra\s*i?|almeno|pi[uù]\s*di|minimo)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?/);

  const explicitSizeMatch = low.match(/\b(?:tagli[ae]|numero|misur[ae]|size|tg\.?|eu)\s*(\d{2}(?:[.,]\d)?|(?:xxs|xs|s|m|l|xl|xxl))\b/i);
  const decimalShoeSizeMatch = low.match(/(?<![\d.,])\b(3[5-9]|4[0-9])[.,](5)\b(?![\d.,])/);

  let gender: string | null = null;
  if (/\b(donna|donne|femmin[aei]|ragazza|wmns?|women|woman)\b/i.test(low)) gender = "Donna";
  else if (/\b(uomo|uomini|maschil[ei]|ragazzo|mens?|men|man)\b/i.test(low)) gender = "Uomo";
  else if (/\b(unisex|tutti\s+i\s+generi)\b/i.test(low)) gender = "Unisex";

  const isDeepDive = norm.split(/\s+/).length >= 4 ||
    /\b(consiglia|consigliami|miglior[ie]|quale|quali|confronta|differenza|per\s+(?:correre|maratona|mezza|trail|ginocchia|peso|iniziare)|fascite|ammortizzat|principiant|pronat)\b/i.test(low);

  let maxPrice: number | null = null;
  let minPrice: number | null = null;
  if (rangeMatch) {
    minPrice = Number(rangeMatch[1].replace(",", "."));
    maxPrice = Number(rangeMatch[2].replace(",", "."));
  } else {
    if (maxPriceMatch) maxPrice = Number(maxPriceMatch[1].replace(",", "."));
    if (minPriceMatch) minPrice = Number(minPriceMatch[1].replace(",", "."));
  }

  let size: string | null = null;
  if (explicitSizeMatch) {
    size = explicitSizeMatch[1].replace(",", ".").toUpperCase();
  } else if (decimalShoeSizeMatch) {
    size = `${decimalShoeSizeMatch[1]}.${decimalShoeSizeMatch[2]}`;
  }

  return {
    normalizedQuery: norm,
    max_price: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
    min_price: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
    size,
    gender,
    is_deep_dive: isDeepDive,
  };
}

interface CuratedSection {
  id: string;
  title: string;
  subtitle: string;
  products: MatchedProductOut[];
}

function buildCuratedSections(
  results: MatchedProductOut[],
  opts: {
    isExactModel: boolean;
    modelDisplayLabel: string | null;
    relatedAlternatives?: MatchedProductOut[];
  },
): CuratedSection[] {
  if (results.length === 0) return [];
  const sections: CuratedSection[] = [];

  // Exact model query with few exact variants (e.g. Garmin Forerunner 165 + 165 Music, Nike Zoom Fly 6)
  if (opts.isExactModel && results.length <= 5) {
    const label = opts.modelDisplayLabel || results[0].canonical_name;
    sections.push({
      id: "exact_model_offers",
      title: `Offerte ${label}`,
      subtitle: "Modelli esatti trovati e confrontati in tempo reale nei negozi partner",
      products: results,
    });

    if (opts.relatedAlternatives && opts.relatedAlternatives.length > 0) {
      sections.push({
        id: "related_alternatives",
        title: "Modelli Simili & Alternative",
        subtitle: "Altre opzioni della stessa categoria da confrontare",
        products: opts.relatedAlternatives.slice(0, 6),
      });
    }
    return sections;
  }

  // Category / brand / advisory query with rich verified results
  const multiStore = results.filter((p) => p.offers.length > 1);
  if (multiStore.length >= 2) {
    sections.push({
      id: "best_comparison",
      title: "Migliori Confronti Multi-Store",
      subtitle: "Modelli disponibili su più negozi per risparmiare subito",
      products: multiStore.slice(0, 8),
    });
  } else {
    sections.push({
      id: "top_matches",
      title: "Migliori Risultati",
      subtitle: "Prodotti più pertinenti alla tua ricerca",
      products: results.slice(0, 8),
    });
  }

  const discounted = [...results]
    .filter((p) => (p.offers[0]?.discount_pct ?? 0) >= 15)
    .sort((a, b) => (b.offers[0]?.discount_pct ?? 0) - (a.offers[0]?.discount_pct ?? 0));
  if (discounted.length >= 2) {
    sections.push({
      id: "top_discounts",
      title: "Sconti più Alti",
      subtitle: "Ribassi verificati nei negozi partner",
      products: discounted.slice(0, 8),
    });
  }

  if (results.length >= 2) {
    const lowestPrice = [...results].sort((a, b) => (a.best_price ?? 9999) - (b.best_price ?? 9999));
    sections.push({
      id: "best_value",
      title: "Miglior Prezzo Finale",
      subtitle: "Offerte ordinate dal prezzo più basso",
      products: lowestPrice.slice(0, 8),
    });
  }

  return sections;
}

function buildChips(intent: {
  brand: string | null;
  category: string | null;
  gender: string | null;
  max_price: number | null;
  size: string | null;
}) {
  const chips: Array<{ id: string; label: string; param_key: string; value: string }> = [];
  if (intent.brand) chips.push({ id: "chip_brand", label: intent.brand, param_key: "brand", value: intent.brand });
  if (intent.gender && intent.gender !== "Unisex") {
    chips.push({ id: "chip_gender", label: intent.gender, param_key: "gender", value: intent.gender });
  }
  if (intent.size) chips.push({ id: "chip_size", label: `Taglia ${intent.size}`, param_key: "size", value: intent.size });
  if (intent.max_price != null) {
    chips.push({ id: "chip_price", label: `Sotto €${Math.round(intent.max_price)}`, param_key: "max_price", value: String(intent.max_price) });
  }
  return chips;
}

function buildDefaultFollowUps(opts: {
  isExactModel: boolean;
  brand: string | null;
  productType: ProductType | null;
  maxPrice: number | null;
  gender: string | null;
  topProduct: MatchedProductOut | null;
}): string[] {
  const out: string[] = [];
  if (opts.isExactModel && opts.topProduct) {
    if (opts.brand) out.push(`Altri modelli ${opts.brand} simili`);
    if (opts.maxPrice == null && opts.topProduct.best_price != null) {
      const budget = Math.max(30, Math.round((opts.topProduct.best_price * 0.9) / 10) * 10);
      out.push(`Alternative sotto ${budget} euro`);
    }
    if (!opts.gender && opts.productType && ["shoes", "trail_shoes", "leggings_tights", "shorts", "pants", "top", "long_sleeve_top", "short_sleeve_top", "jacket"].includes(opts.productType)) {
      out.push("Mostrami versione Donna");
    } else {
      out.push("Quali sono le caratteristiche principali?");
    }
  } else {
    if (opts.maxPrice == null && opts.topProduct?.best_price != null) {
      const target = Math.max(25, Math.round((opts.topProduct.best_price * 1.15) / 10) * 10);
      out.push(`Solo sotto ${target} euro`);
    }
    if (!opts.gender) out.push("Filtra per Donna");
    out.push("Mostrami altri modelli simili");
  }
  return out.slice(0, 3);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const url = new URL(req.url);
  let q = url.searchParams.get("q") ?? "";
  let mode = url.searchParams.get("mode");
  let maxPriceParam = url.searchParams.get("max_price");
  let sizeParam = url.searchParams.get("size");
  let categoryParam = url.searchParams.get("category");
  let storeParam = url.searchParams.get("store");
  let contextQuery = url.searchParams.get("context_query");
  let sessionId = url.searchParams.get("session_id");
  let deviceId = url.searchParams.get("device_id");
  let userId = url.searchParams.get("user_id");
  let preferredSize = url.searchParams.get("preferred_size");
  let userImageUrl = url.searchParams.get("user_image_url");
  let limit = Number(url.searchParams.get("limit") ?? "35") || 35;
  const wantsStream = url.searchParams.get("stream") === "1" ||
    (req.headers.get("accept") ?? "").toLowerCase().includes("text/event-stream");

  if (req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    q = String(body?.q ?? q);
    mode = body?.mode ?? mode;
    maxPriceParam = body?.max_price != null ? String(body.max_price) : maxPriceParam;
    sizeParam = body?.size ?? sizeParam;
    categoryParam = body?.category ?? categoryParam;
    storeParam = body?.store ?? storeParam;
    contextQuery = body?.context_query ?? contextQuery;
    sessionId = body?.session_id ?? sessionId;
    deviceId = body?.device_id ?? deviceId;
    userId = body?.user_id ?? userId;
    preferredSize = body?.preferred_size ?? preferredSize;
    userImageUrl = body?.user_image_url ?? userImageUrl;
    if (body?.limit != null) limit = Number(body.limit) || limit;
  }

  q = q.trim();
  if (q.length < 2) {
    return jsonResponse({ detail: "Query troppo corta." }, 400);
  }

  const execute = async (emitStep?: (step: Record<string, unknown>) => void) => {
    const startedAt = Date.now();
    const supabase = createServiceClient();
    if (!supabase) {
      throw new Error("Configurazione Supabase mancante.");
    }

    const guard = evaluateGuardrail(q);
    if (guard.isOffTopic) {
      return {
        search_mode: "classic",
        is_deep_dive: false,
        is_conversational_advice: true,
        conversational_header: "Solo articoli sportivi",
        conversational_summary: guard.reason ?? "Chiedimi prodotti sportivi!",
        curated_sections: [],
        comparative_cards: [],
        spotlight: null,
        follow_up_suggestions: ["Nike Pegasus 41", "Scarpe running ammortizzate", "Garmin Forerunner 165"],
        intent: {
          raw_query: q,
          search_mode: "classic",
          is_deep_dive: false,
          target_keywords: [],
          brand: null,
          category: null,
          gender: null,
          max_price: null,
          min_price: null,
          size: null,
          features: [],
          explanation: guard.reason ?? null,
          source: "guardrail",
          is_off_topic: true,
          is_unsafe: guard.isUnsafe,
          is_conversational_advice: true,
        },
        chips: [],
        total_found: 0,
        results: [],
        is_off_topic: true,
        is_unsafe: guard.isUnsafe,
        session_id: sessionId ?? null,
        turn_id: null,
        user_image_url: userImageUrl ?? null,
      };
    }

    emitStep?.({
      id: "intent",
      status: "running",
      title: "Analisi della richiesta",
      detail: contextQuery ? "Collego il contesto della conversazione" : "Interpreto modello, categoria e filtri",
      elapsed_ms: Date.now() - startedAt,
    });

    // Load previous session context if available
    let prevContext: Record<string, unknown> | null = null;
    if (sessionId && /^[0-9a-f-]{36}$/i.test(sessionId.trim())) {
      const { data: sessRow } = await supabase
        .from("chat_sessions")
        .select("context_state")
        .eq("id", sessionId.trim().toLowerCase())
        .maybeSingle();
      if (sessRow?.context_state && typeof sessRow.context_state === "object") {
        prevContext = sessRow.context_state as Record<string, unknown>;
      }
    }

    const local = parseLocalConstraints(q);
    const normalizedQ = local.normalizedQuery;
    const isFollowUp = Boolean(contextQuery && contextQuery.trim());

    // Deterministic analysis of current query & follow-up transition
    const currentBrand = extractBrand(normalizedQ, null);
    const subBrand = detectSubBrand(normalizedQ);
    const currentSinglePType = detectSingleProductType(normalizedQ);
    const prevPTypeRaw = prevContext?.product_type && VALID_PRODUCT_TYPES.has(prevContext.product_type as ProductType)
      ? (prevContext.product_type as ProductType)
      : (contextQuery ? detectProductType(contextQuery) : null);

    const categorySwitched = Boolean(
      currentSinglePType && prevPTypeRaw &&
      normalizeProductTypeGroup(currentSinglePType) !== normalizeProductTypeGroup(prevPTypeRaw),
    );
    const broadeningFollowUp = isFollowUp && isBroadeningFollowUp(normalizedQ);

    const currentEntities = extractSpecificEntityTokens(normalizedQ, currentBrand);
    const prevBrand = !categorySwitched && prevContext?.brand ? String(prevContext.brand) : null;
    const brandSwitched = Boolean(currentBrand && prevBrand && currentBrand.toLowerCase() !== prevBrand.toLowerCase());

    const shouldInheritPrevEntities = isFollowUp &&
      currentEntities.length === 0 &&
      !categorySwitched &&
      !brandSwitched &&
      !broadeningFollowUp;

    const prevEntities = shouldInheritPrevEntities && Array.isArray(prevContext?.entity_tokens)
      ? prevContext.entity_tokens.map(String).filter(Boolean)
      : [];

    const detProductType: ProductType | null = currentSinglePType ??
      (!categorySwitched ? prevPTypeRaw : null) ??
      detectProductType(normalizedQ, isFollowUp ? contextQuery : null);

    const effectiveQueryForLLM = isFollowUp && !categorySwitched
      ? `${contextQuery!.trim()} -> follow-up: ${normalizedQ}`
      : normalizedQ;

    const systemPrompt =
      "Sei il motore di ricerca AI sportivo di FitMatch (comparatore prezzi multi-store di calzature, smartwatch GPS, abbigliamento tecnico e attrezzatura sportiva).\n" +
      "Analizza la richiesta dell'utente, correggi eventuali errori di battitura (es. 'leggins' -> 'leggings', 'garmen forunner' -> 'garmin forerunner') ed estrai l'intent preciso per interrogare il catalogo prodotti.\n" +
      "REGOLE CRITICHE:\n" +
      "1. 'query_type':\n" +
      "   - 'exact_model' se l'utente chiede un modello specifico (es. 'Garmin Forerunner 165', 'Nike Zoom Fly 6', 'Salomon Adv Skin 12').\n" +
      "   - 'category_brand' se l'utente chiede una categoria + brand senza modello specifico (es. 'leggins under armour da corsa', 'scarpe hoka donna').\n" +
      "   - 'advisory' se chiede consigli/raccomandazioni/caratteristiche (es. 'migliori scarpe ammortizzate 85kg', 'scarpe maratona sotto 180 euro').\n" +
      "   - 'comparison' se confronta 2+ modelli.\n" +
      "   - 'followup_filter' se raffina i filtri del turno precedente (prezzo, taglia, genere).\n" +
      "2. 'product_type': scegli il tipo ESATTO tra: leggings_tights, shorts, pants, long_sleeve_top, short_sleeve_top, singlet_top, top, jacket, socks, headwear, heart_rate_monitor, bike_computer, gps_watch, eyewear, hydration, swim, padel_racket, tennis_racket, football_boots, basketball_shoes, tennis_shoes, volleyball_shoes, trail_shoes, shoes, winter_sports, nutrition, smart_trainer, oppure null.\n" +
      "3. 'target_keywords': 2-5 stringhe brevi pulite per cercare nel catalogo.\n" +
      "   - MAI inserire un nome di brand da solo (es. MAI 'Nike' o 'Under Armour' da solo) se c'è una categoria o modello!\n" +
      "   - Se query_type='exact_model': metti SOLO il modello esatto richiesto (es. ['Garmin Forerunner 165', 'Forerunner 165'] o ['Nike Zoom Fly 6', 'Zoom Fly 6']). NON aggiungere altri modelli!\n" +
      "   - Se query_type='category_brand': includi sinonimi catalogo IT/EN con il brand (es. ['Under Armour leggings', 'Under Armour tights', 'Under Armour calzamaglia']).\n" +
      "   - Se query_type='advisory': elenca 4-5 modelli reali di riferimento nel mercato italiano adatti alla richiesta.\n" +
      "4. 'brand': valorizza SOLO se l'utente ha chiesto esplicitamente un brand (o lo eredita da follow-up), altrimenti null.\n" +
      "5. 'model_tokens': token specifici del modello/versione citati dall'utente (es. ['forerunner', '165'] o ['zoom', 'fly', '6']), oppure [] se non cita un modello specifico.\n" +
      "Rispondi ESCLUSIVAMENTE con JSON valido:\n" +
      "{\n" +
      '  "query_type": "exact_model|category_brand|advisory|comparison|followup_filter",\n' +
      '  "corrected_query": "query corretta",\n' +
      '  "is_deep_dive": true | false,\n' +
      '  "target_keywords": ["keyword 1", "keyword 2"],\n' +
      '  "model_tokens": ["token1", "token2"],\n' +
      '  "brand": string | null,\n' +
      '  "product_type": string | null,\n' +
      '  "gender": "Uomo" | "Donna" | null,\n' +
      '  "max_price": number | null,\n' +
      '  "min_price": number | null,\n' +
      '  "size": string | null,\n' +
      '  "features": ["es. ammortizzata", "piastra carbonio"],\n' +
      '  "conversational_header": "Titolo breve (max 6 parole)",\n' +
      '  "conversational_summary": "Consiglio tecnico chiaro in 2 frasi in italiano coerente col prodotto richiesto",\n' +
      '  "follow_up_suggestions": ["Follow-up pertinente 1", "Follow-up pertinente 2", "Follow-up pertinente 3"]\n' +
      "}";

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "openai/gpt-4o-mini";
    const llmIntent = await callOpenRouterJSON({
      systemPrompt,
      userPrompt: prevContext && !categorySwitched
        ? `Contesto sessione precedente: ${JSON.stringify(prevContext)}\nRichiesta attuale: ${effectiveQueryForLLM}`
        : effectiveQueryForLLM,
      models: [primaryModel, "meta-llama/llama-3.3-70b-instruct"],
      temperature: 0.1,
      maxTokens: 550,
      title: "FitMatch Smart Search",
      timeoutMs: 9_000,
    });

    // Deterministic reconciliation over LLM output (LLM helps, guardrails guarantee reliability!)
    const llmPTypeRaw = typeof llmIntent?.product_type === "string"
      ? llmIntent.product_type.trim().toLowerCase()
      : null;
    const llmPType = llmPTypeRaw && VALID_PRODUCT_TYPES.has(llmPTypeRaw as ProductType)
      ? (llmPTypeRaw as ProductType)
      : null;

    const productType: ProductType | null = detProductType ?? llmPType;

    const explicitMaxPrice = maxPriceParam != null && maxPriceParam !== "" ? Number(maxPriceParam) : null;
    const maxPrice = explicitMaxPrice ??
      local.max_price ??
      (typeof llmIntent?.max_price === "number" ? llmIntent.max_price : null) ??
      (!categorySwitched && isFollowUp && typeof prevContext?.max_price === "number" ? prevContext.max_price : null);

    const minPrice = local.min_price ??
      (typeof llmIntent?.min_price === "number" ? llmIntent.min_price : null);

    const size = (sizeParam && sizeParam.trim()) ||
      local.size ||
      (llmIntent?.size ? String(llmIntent.size).trim() : null) ||
      (!categorySwitched && isFollowUp && prevContext?.size ? String(prevContext.size) : null);

    const gender = local.gender === "Unisex"
      ? null
      : (local.gender ??
        (llmIntent?.gender && ["Uomo", "Donna"].includes(String(llmIntent.gender)) ? String(llmIntent.gender) : null) ??
        (!categorySwitched && isFollowUp && prevContext?.gender ? String(prevContext.gender) : null));

    // Only enforce a brand if explicitly present in current query, sub-brand, or inherited from non-switched follow-up!
    const llmBrand = llmIntent?.brand && String(llmIntent.brand).trim().toLowerCase() !== "null"
      ? String(llmIntent.brand).trim()
      : null;
    const brand = currentBrand ??
      (subBrand ? subBrand[0] : null) ??
      (isFollowUp && !categorySwitched ? prevBrand : null) ??
      (llmBrand && normalizedQ.toLowerCase().includes(llmBrand.toLowerCase()) ? llmBrand : null);

    const category = (categoryParam && categoryParam.trim() && categoryParam !== "all" && categoryParam !== "tutti")
      ? categoryParam.trim()
      : mapProductTypeToCategory(productType);

    // Combine deterministic entity tokens with validated LLM model tokens
    const entityTokens: string[] = [...(currentEntities.length > 0 ? currentEntities : prevEntities)];
    if (entityTokens.length === 0 && !broadeningFollowUp && Array.isArray(llmIntent?.model_tokens)) {
      const qLow = normalizedQ.toLowerCase();
      for (const mt of llmIntent.model_tokens) {
        const tok = normalizeQueryTypos(String(mt ?? "")).toLowerCase().trim();
        if (tok.length >= 2 && qLow.includes(tok) && !entityTokens.includes(tok)) {
          entityTokens.push(tok);
        }
      }
    }

    const queryType = String(llmIntent?.query_type ?? "").toLowerCase();
    const isComparison = queryType === "comparison" ||
      /\b(confronta|confronto|\bvs\b|versus|differenz[ae])\b/i.test(normalizedQ);
    const isAdvisory = queryType === "advisory" && currentEntities.length === 0;
    const isExactModel = entityTokens.length > 0 && !broadeningFollowUp && !isComparison && !isAdvisory;
    const effectiveEntityTokens = isAdvisory ? [] : entityTokens;

    const rawLlmKeywords = Array.isArray(llmIntent?.target_keywords)
      ? llmIntent.target_keywords.map((k) => String(k ?? "").trim()).filter(Boolean)
      : [];

    // Inherit previous search keywords on pure filter follow-ups
    const prevKeywords = shouldInheritPrevEntities && Array.isArray(prevContext?.last_keywords)
      ? prevContext.last_keywords.map(String).filter(Boolean)
      : [];

    const searchKeywords = buildCatalogSearchTerms({
      rawQuery: shouldInheritPrevEntities && prevContext?.last_query
        ? String(prevContext.last_query)
        : normalizedQ,
      keywords: rawLlmKeywords.length > 0 ? rawLlmKeywords : prevKeywords,
      brand,
      productType,
      entityTokens: effectiveEntityTokens,
      isComparison,
    });

    const isDeepDive = mode === "deep_dive" ||
      (mode !== "classic" && (Boolean(llmIntent?.is_deep_dive) || local.is_deep_dive));

    emitStep?.({
      id: "intent",
      status: "done",
      title: "Richiesta compresa",
      detail: searchKeywords.slice(0, 3).join(", ") || normalizedQ,
      elapsed_ms: Date.now() - startedAt,
    });

    emitStep?.({
      id: "catalog",
      status: "running",
      title: "Ricerca nel catalogo multi-store",
      detail: "Confronto modelli, categorie e prezzi verificati",
      elapsed_ms: Date.now() - startedAt,
    });

    const effectiveRawForSearch = shouldInheritPrevEntities && prevContext?.last_query
      ? `${String(prevContext.last_query)} ${normalizedQ}`
      : normalizedQ;

    const results = await searchCatalogOffers(supabase, {
      rawQuery: effectiveRawForSearch,
      keywords: searchKeywords,
      brand,
      category,
      productType,
      entityTokens: effectiveEntityTokens,
      isComparison,
      maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
      minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
      size,
      preferredSize: preferredSize && preferredSize.trim() ? preferredSize.trim() : null,
      gender,
      store: storeParam,
      semanticQuery: `${normalizedQ} ${searchKeywords.slice(0, 3).join(" ")}`,
      allowSemantic: !isExactModel, // Exact models use precision lexical search; semantic only if lexical returns 0
      limit: Math.min(Math.max(limit, 1), 60),
    });

    // If exact-model search returned 0 results strictly, try one careful semantic+relaxed pass (still strictly gated by brand & productType!)
    let finalResults = results;
    if (finalResults.length === 0 && isExactModel) {
      finalResults = await searchCatalogOffers(supabase, {
        rawQuery: effectiveRawForSearch,
        keywords: searchKeywords,
        brand,
        category,
        productType,
        entityTokens: [],
        maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
        minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
        size,
        preferredSize: preferredSize && preferredSize.trim() ? preferredSize.trim() : null,
        gender,
        store: storeParam,
        semanticQuery: normalizedQ,
        allowSemantic: true,
        limit: 12,
      });
    }

    // For exact-model queries with 1-3 exact variants, optionally fetch strictly compatible same-category alternatives
    // for a clearly separated "Modelli Simili & Alternative" section (NEVER polluting primary results or spotlight!)
    let relatedAlternatives: MatchedProductOut[] = [];
    if (isExactModel && finalResults.length >= 1 && finalResults.length <= 3 && productType) {
      const exactIds = new Set(finalResults.map((p) => p.id));
      const exactNames = new Set(finalResults.map((p) => p.canonical_name.toLowerCase()));
      const altTerms = buildCatalogSearchTerms({
        rawQuery: brand ? `${brand} ${productType}` : productType,
        keywords: [],
        brand,
        productType,
        entityTokens: [],
      });
      const altCandidates = await searchCatalogOffers(supabase, {
        rawQuery: brand ? `${brand} ${productType}` : normalizedQ,
        keywords: altTerms,
        brand,
        category,
        productType,
        entityTokens: [],
        maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
        minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
        size,
        gender,
        store: storeParam,
        allowSemantic: false,
        limit: 10,
      });
      relatedAlternatives = altCandidates
        .filter((p) => !exactIds.has(p.id) && !exactNames.has(p.canonical_name.toLowerCase()))
        .slice(0, 6);
    }

    emitStep?.({
      id: "catalog",
      status: "done",
      title: `${finalResults.length} ${finalResults.length === 1 ? "modello trovato" : "modelli trovati"}`,
      detail: finalResults.length > 0
        ? "Risultati verificati e ordinati per pertinenza e miglior prezzo"
        : "Nessuna offerta attiva per questi filtri",
      elapsed_ms: Date.now() - startedAt,
    });

    const topProduct = finalResults[0] ?? null;
    const modelDisplayLabel = isExactModel && topProduct
      ? topProduct.canonical_name.replace(/\s*\((Uomo|Donna)\)$/i, "")
      : null;

    let header = String(llmIntent?.conversational_header ?? "").trim() ||
      (topProduct ? `Offerte per ${modelDisplayLabel ?? normalizedQ}` : `Nessuna offerta per "${q}"`);
    let summary = String(llmIntent?.conversational_summary ?? "").trim();

    if (finalResults.length === 0) {
      header = `Nessuna offerta per "${q}"`;
      const filterNotes: string[] = [];
      if (maxPrice != null) filterNotes.push(`sotto €${Math.round(maxPrice)}`);
      if (size) filterNotes.push(`taglia ${size}`);
      if (gender) filterNotes.push(gender);
      if (storeParam) filterNotes.push(`su ${storeParam}`);
      summary = filterNotes.length > 0
        ? `Non ho trovato offerte attive per **${normalizedQ}** con i filtri selezionati (${filterNotes.join(", ")}). Prova ad ampliare il budget o rimuovere un filtro per vedere i modelli disponibili.`
        : `Al momento non ho trovato offerte attive in catalogo per **${normalizedQ}**. Prova con un nome modello leggermente diverso o una ricerca più ampia.`;
    } else if (!summary) {
      summary = topProduct?.best_price != null
        ? `Ho trovato **${finalResults.length}** ${finalResults.length === 1 ? "modello compatibile" : "modelli compatibili"}: miglior offerta a partire da **€${topProduct.best_price.toFixed(2)}** confrontando i negozi partner.`
        : `Ho trovato ${finalResults.length} modelli compatibili confrontando i negozi partner.`;
    }

    const curatedSections = buildCuratedSections(finalResults, {
      isExactModel,
      modelDisplayLabel,
      relatedAlternatives,
    });

    const spotlight = topProduct
      ? {
          product: topProduct,
          badge_text: topProduct.offers.length > 1
            ? `Confrontato su ${topProduct.offers.length} negozi`
            : "Miglior Prezzo",
          highlights: [
            topProduct.best_price != null ? `Miglior offerta da €${topProduct.best_price.toFixed(2)}` : "Prezzo verificato",
            topProduct.cross_store_savings != null && topProduct.cross_store_savings > 1
              ? `Risparmi fino a €${topProduct.cross_store_savings.toFixed(2)} tra gli store`
              : "Disponibilità e spedizione verificate",
          ],
        }
      : null;

    const comparativeCards = isDeepDive && finalResults.length >= 2
      ? finalResults.slice(0, 3).map((p) => ({
          product: p,
          model_name: p.canonical_name,
          ideal_for: p.brand ? `Selezione ${p.brand}` : "Uso sportivo tecnico",
          strengths: p.best_price != null
            ? `Miglior prezzo €${p.best_price.toFixed(2)} (${p.offers.length} ${p.offers.length === 1 ? "offerta" : "offerte"})`
            : `${p.offers.length} offerte`,
          section_title: "Confronto rapido",
        }))
      : [];

    const rawFollowUps = Array.isArray(llmIntent?.follow_up_suggestions)
      ? llmIntent.follow_up_suggestions.map((s) => String(s ?? "").trim()).filter(Boolean).slice(0, 3)
      : [];
    const followUps = rawFollowUps.length > 0
      ? rawFollowUps
      : buildDefaultFollowUps({ isExactModel, brand, productType, maxPrice, gender, topProduct });

    const intentObj = {
      raw_query: q,
      search_mode: isDeepDive ? "deep_dive" : "classic",
      is_deep_dive: isDeepDive,
      target_keywords: searchKeywords,
      brand,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
      features: Array.isArray(llmIntent?.features) ? llmIntent.features.map(String) : [],
      explanation: summary,
      source: llmIntent ? "supabase_edge_v2_hybrid" : "supabase_edge_v2_heuristic",
      is_off_topic: false,
      is_unsafe: false,
      is_conversational_advice: isDeepDive,
    };

    const chips = buildChips({ brand, category, gender, max_price: maxPrice, size });

    let savedIds: { session_id: string; turn_id: string } | null = null;
    if (sessionId || deviceId || userId) {
      savedIds = await saveChatTurn(supabase, {
        sessionId,
        deviceId,
        userId,
        chatType: "smart_search",
        query: q,
        isFollowUp,
        payload: {
          conversational_header: header,
          conversational_summary: summary,
          is_conversational_advice: isDeepDive,
          intent: intentObj,
          chips,
          results: finalResults,
          curated_sections: curatedSections,
          comparative_cards: comparativeCards,
          spotlight,
          follow_up_suggestions: followUps,
          is_off_topic: false,
          is_unsafe: false,
        },
        contextState: {
          last_query: normalizedQ,
          last_keywords: searchKeywords,
          entity_tokens: entityTokens,
          product_type: productType,
          brand,
          category,
          gender,
          max_price: maxPrice,
          min_price: minPrice,
          size,
        },
        userImageUrl,
      });
    }

    return {
      search_mode: isDeepDive ? "deep_dive" : "classic",
      is_deep_dive: isDeepDive,
      is_conversational_advice: isDeepDive,
      conversational_header: header,
      conversational_summary: summary,
      curated_sections: curatedSections,
      comparative_cards: comparativeCards,
      spotlight,
      follow_up_suggestions: followUps,
      intent: intentObj,
      chips,
      total_found: finalResults.length,
      results: finalResults,
      is_off_topic: false,
      is_unsafe: false,
      session_id: savedIds?.session_id ?? sessionId ?? null,
      turn_id: savedIds?.turn_id ?? null,
      user_image_url: userImageUrl ?? null,
    };
  };

  if (!wantsStream) {
    try {
      const result = await execute();
      return jsonResponse(result);
    } catch (err) {
      return jsonResponse({ detail: err instanceof Error ? err.message : "Errore interno" }, 500);
    }
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const send = (obj: unknown) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));
      };
      const started = Date.now();
      try {
        const result = await execute((step) => send({ type: "step", ...step }));
        send({ type: "result", elapsed_ms: Date.now() - started, data: result });
      } catch (err) {
        send({ type: "error", message: err instanceof Error ? err.message : "Errore interno" });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  });
});
