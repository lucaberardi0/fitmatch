import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  buildCatalogSearchTerms,
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  detectProductType,
  detectSingleProductType,
  detectSubBrand,
  extractAllBrands,
  extractBrand,
  extractSpecificEntityTokens,
  isBroadeningFollowUp,
  jsonResponse,
  KNOWN_BRANDS,
  mapProductTypeToCategory,
  MatchedProductOut,
  normalizeProductTypeGroup,
  normalizeQueryTypos,
  ProductType,
  saveChatTurn,
  searchCatalogMultiQuery,
  searchCatalogOffers,
  SubQuerySpec,
} from "../_shared/catalog.ts";

const SMART_SEARCH_CACHE_VERSION = "v3_shop_1";
const CACHE_TTL_RESULTS_MS = 15 * 60 * 1000; // 15 min for grounded product searches
const CACHE_TTL_EMPTY_MS = 5 * 60 * 1000;    // 5 min for valid LLM empty / Q&A responses

async function buildSearchCacheKey(params: {
  q: string;
  mode: string | null;
  maxPrice: string | null;
  size: string | null;
  preferredSize: string | null;
  category: string | null;
  store: string | null;
  limit: number;
}): Promise<string> {
  const normQ = normalizeQueryTypos(params.q).toLowerCase().replace(/\s+/g, " ").trim();
  const modeNorm = params.mode === "classic" ? "classic" : "deep_dive";
  const canonical = [
    SMART_SEARCH_CACHE_VERSION,
    modeNorm,
    normQ,
    `mp=${(params.maxPrice ?? "").trim()}`,
    `sz=${(params.size ?? "").trim().toLowerCase()}`,
    `ps=${(params.preferredSize ?? "").trim().toLowerCase()}`,
    `cat=${(params.category ?? "").trim().toLowerCase()}`,
    `st=${(params.store ?? "").trim().toLowerCase()}`,
    `lim=${params.limit}`,
  ].join("|");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const slug = normQ.replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 48);
  return `${SMART_SEARCH_CACHE_VERSION}:${slug}:${hex.slice(0, 24)}`;
}

const VALID_PRODUCT_TYPES = new Set<ProductType>([
  "leggings_tights", "shorts", "pants", "long_sleeve_top", "short_sleeve_top",
  "singlet_top", "top", "jacket", "socks", "headwear", "heart_rate_monitor",
  "bike_computer", "gps_watch", "eyewear", "hydration", "swim", "padel_racket",
  "tennis_racket", "football_boots", "basketball_shoes", "tennis_shoes",
  "volleyball_shoes", "trail_shoes", "shoes", "winter_sports", "nutrition",
  "smart_trainer",
]);

const COLOR_MAP: Array<{ key: string; label: string; regex: RegExp; matchRegex: RegExp }> = [
  { key: "black", label: "Nero", regex: /\b(ner[oaie]|black|obsidian|anthracite)\b/i, matchRegex: /\b(ner[oaie]|black|blk|obsidian|anthracite|carbon|charcoal|dark)\b/i },
  { key: "white", label: "Bianco", regex: /\b(bianc[oa]|bianch[ei]|white|summit\s*white)\b/i, matchRegex: /\b(bianc[oa]|bianch[ei]|white|wht|ivory|cream|chalk|sail)\b/i },
  { key: "blue", label: "Blu", regex: /\b(blu|azzurr[oaie]|navy|blue)\b/i, matchRegex: /\b(blu|azzurr[oaie]|navy|blue|cobalt|indigo|royal|teal|cyan)\b/i },
  { key: "red", label: "Rosso", regex: /\b(ross[oaie]|red|crimson|bordeaux)\b/i, matchRegex: /\b(ross[oaie]|red|crimson|scarlet|burgundy|bordeaux|coral)\b/i },
  { key: "green", label: "Verde", regex: /\b(verd[ei]|green|oliva|olive|kaki|khaki)\b/i, matchRegex: /\b(verd[ei]|green|olive|oliva|kaki|khaki|sage|forest|lime|mint|emerald)\b/i },
  { key: "grey", label: "Grigio", regex: /\b(grigi[oaie]|grey|gray|argento|silver)\b/i, matchRegex: /\b(grigi[oaie]|grey|gray|silver|slate|smoke|ash|iron)\b/i },
  { key: "pink", label: "Rosa", regex: /\b(rosa|pink|fucsia|magenta)\b/i, matchRegex: /\b(rosa|pink|fucsia|magenta|rose|berry)\b/i },
  { key: "orange", label: "Arancione", regex: /\b(arancion[ei]|orange)\b/i, matchRegex: /\b(arancion[ei]|orange|amber|tangerine)\b/i },
  { key: "yellow", label: "Giallo", regex: /\b(giall[oaie]|yellow|volt|fluo)\b/i, matchRegex: /\b(giall[oaie]|yellow|volt|gold|lemon|neon)\b/i },
  { key: "brown", label: "Marrone", regex: /\b(marron[ei]|brown|beige|sabbia|tan)\b/i, matchRegex: /\b(marron[ei]|brown|beige|sand|tan|earth|khaki|orewood)\b/i },
  { key: "purple", label: "Viola", regex: /\b(viola|purple|lilla|violet)\b/i, matchRegex: /\b(viola|purple|violet|lilac|plum|iris)\b/i },
];

function detectColorConstraint(q: string): { key: string; label: string; matchRegex: RegExp } | null {
  const low = q.toLowerCase();
  for (const c of COLOR_MAP) {
    if (c.regex.test(low)) return { key: c.key, label: c.label, matchRegex: c.matchRegex };
  }
  return null;
}

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

function isPureAdviceQuestion(q: string, isFollowUp: boolean): boolean {
  const low = q.trim().toLowerCase();
  // Explicit shopping / filtering triggers are NEVER pure Q&A advice cards
  if (/\b(mostram|cerca|trovam|fammi\s+vedere|solo\s+|sotto\s+|filtra|alternative|altri\s+modelli|mia\s+taglia|taglia\s+\d|sotto\s+\d|meno\s+di\s+\d)\b/i.test(low)) {
    return false;
  }
  if (isFollowUp) {
    return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?|vanno|funzion(?:a|ano)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?|costa(?:no)?)|qual\s+[eè]\s+il\s+(?:drop|peso)|vanno\s+bene\s+per|sono\s+(?:comode?|buone?|adatte?|impermeabili?|neutre?)|hanno\s+(?:le\s+tasche|la\s+piastra|il\s+liner|il\s+boxer)|che\s+differenza\s+c['’][eè]|differenza\s+tra)/i.test(low) ||
      (low.endsWith("?") && /\b(calza(?:no|re)?|vest(?:e|ono|ire)?|drop|peso|dura(?:no)?|tasche|pronat|supinat|mezza\s+maratona|maratona|palestra|pioggia|comfort|comodi|comode|differenza)\b/i.test(low));
  }
  return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?)|qual\s+[eè]\s+il\s+(?:drop|peso)|vanno\s+bene\s+per)\b/i.test(low);
}

function parseLocalConstraints(q: string) {
  const norm = normalizeQueryTypos(q);
  const low = norm.toLowerCase();

  // Range price: "tra 100 e 180 euro"
  const rangeMatch = low.match(/\b(?:tra|da)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?\s*(?:e|a|-)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?\b/);
  const maxPriceMatch = low.match(/(?:sotto\s*i?|meno\s*di|max|massimo|entro\s*i?|fino\s*a|budget\s*(?:di)?)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?/);
  const minPriceMatch = low.match(/(?:sopra\s*i?|almeno|pi[uù]\s*di|minimo)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?/);

  const explicitSizeMatch = low.match(/\b(?:tagli[ae]|numero|misur[ae]|size|tg\.?|eu)\s*(\d{2}(?:[.,]\d)?|(?:xxs|xs|s|m|l|xl|xxl))\b/i);
  const decimalShoeSizeMatch = low.match(/(?<![\d.,])\b(3[5-9]|4[0-9])[.,](5)\b(?![\d.,])/);
  const asksMySize = /\b(la\s+mia\s+taglia|nella\s+mia\s+taglia|mia\s+taglia)\b/i.test(low);

  let gender: string | null = null;
  if (/\b(donna|donne|femmin[aei]|ragazza|wmns?|women|woman)\b/i.test(low)) gender = "Donna";
  else if (/\b(uomo|uomini|maschil[ei]|ragazzo|mens?|men|man)\b/i.test(low)) gender = "Uomo";
  else if (/\b(unisex|tutti\s+i\s+generi)\b/i.test(low)) gender = "Unisex";

  const color = detectColorConstraint(norm);

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
    asksMySize,
    gender,
    color,
  };
}

interface CuratedSection {
  id: string;
  title: string;
  subtitle: string;
  products: MatchedProductOut[];
}

interface FeaturedCardOut {
  product: MatchedProductOut;
  badge_text: string | null;
  highlights: string[];
}

interface ComparativeCardOut {
  product: MatchedProductOut;
  model_name: string;
  ideal_for: string;
  strengths: string;
  section_title: string;
}

function computeDiscountBadge(p: MatchedProductOut): string | null {
  const best = p.offers[0];
  if (best) {
    if (best.discount_pct != null && best.discount_pct >= 5) {
      return `${Math.round(best.discount_pct)}% di sconto`;
    }
    if (best.original_price != null && best.original_price > best.price + 1) {
      const pct = Math.round(((best.original_price - best.price) / best.original_price) * 100);
      if (pct >= 5) return `${pct}% di sconto`;
    }
  }
  if (p.cross_store_savings != null && p.cross_store_savings >= 10) {
    return `Risparmia ${Math.round(p.cross_store_savings)} €`;
  }
  return null;
}

function buildSmartFallbackMerchandising(opts: {
  query: string;
  results: MatchedProductOut[];
  roleById: Record<string, "primary" | "variant" | "complementary">;
  productType: ProductType | null;
  brand: string | null;
  maxPrice: number | null;
  gender: string | null;
  size: string | null;
  preferredSize: string | null;
  isExactModel: boolean;
}): {
  summary: string;
  sections: CuratedSection[];
  featuredCards: FeaturedCardOut[];
  comparativeCards: ComparativeCardOut[];
  followUps: string[];
} {
  const { results, roleById, productType, brand, maxPrice, gender, size, preferredSize } = opts;
  if (results.length === 0) {
    return { summary: "", sections: [], featuredCards: [], comparativeCards: [], followUps: [] };
  }

  const sections: CuratedSection[] = [];
  const usedIds = new Set<string>();
  const addSection = (id: string, title: string, subtitle: string, items: MatchedProductOut[]) => {
    const clean = items.filter((p) => !usedIds.has(p.id)).slice(0, 10);
    if (clean.length === 0) return;
    for (const p of clean) usedIds.add(p.id);
    sections.push({ id, title, subtitle, products: clean });
  };

  const primaryItems = results.filter((p) => roleById[p.id] === "primary");
  const secondaryItems = results.filter((p) => roleById[p.id] !== "primary");

  if (productType === "long_sleeve_top") {
    const technical = results.filter((p) => /\b(adv|dri[\s-]*fit|chinati|trail|zip|1\s*4|half\s*zip|uv)\b/i.test(`${p.canonical_name} ${p.offers[0]?.title ?? ""}`));
    const warm = results.filter((p) => /\b(therma|fleece|felpa|pile|polar|wolf\s*grid|wolf\s*tree|wolf\s*lichen|warm|termic)\b/i.test(`${p.canonical_name} ${p.offers[0]?.title ?? ""}`));
    const everyday = results.filter((p) => !technical.includes(p) && !warm.includes(p));
    if (everyday.length > 0) {
      addSection("sec_everyday", `${brand ? brand + " " : ""}Per tutti i giorni`.trim(), "Tagli versatili e tessuti traspiranti", everyday);
    }
    if (technical.length > 0) {
      addSection("sec_technical", "Modelli tecnici e traspiranti", "Dri-FIT, ventilazione e protezione per l'outdoor", technical);
    }
    if (warm.length > 0) {
      addSection("sec_warm", "Più calde per clima fresco", "Strati termici, half-zip e fleece", warm);
    }
  } else if (primaryItems.length > 0 && secondaryItems.length > 0) {
    const topLabel = primaryItems[0].canonical_name.replace(/\s*\((Uomo|Donna)\)$/i, "");
    addSection("sec_primary", topLabel, "Le opzioni più vicine alla tua ricerca", primaryItems);
    addSection("sec_related", brand ? `Altre varianti ${brand} della linea` : "Alternative e varianti correlate", "Opzioni simili confrontate nei negozi partner", secondaryItems);
  } else {
    addSection(
      "sec_top",
      brand ? `Selezione ${brand}` : "Le opzioni più pertinenti",
      "Confrontate in tempo reale nei negozi partner",
      results.slice(0, 10),
    );
  }

  // Catch any remaining unplaced products if only 1 small section existed
  const leftovers = results.filter((p) => !usedIds.has(p.id));
  if (leftovers.length >= 2 && sections.length < 3) {
    addSection("sec_more", "Altre opzioni da valutare", "Modelli aggiuntivi compatibili con la tua ricerca", leftovers);
  }

  // Build up to 2 contrasting featured cards
  const featuredCandidates: MatchedProductOut[] = [];
  if (sections.length >= 2) {
    featuredCandidates.push(sections[0].products[0]);
    featuredCandidates.push(sections[1].products[0]);
  } else {
    featuredCandidates.push(...results.slice(0, 2));
  }
  const uniqueFeatured: MatchedProductOut[] = [];
  for (const p of featuredCandidates) {
    if (p && !uniqueFeatured.some((u) => u.id === p.id)) uniqueFeatured.push(p);
  }

  const featuredCards: FeaturedCardOut[] = uniqueFeatured.slice(0, 2).map((p) => {
    const hls: string[] = [];
    const probe = `${p.canonical_name} ${p.offers[0]?.title ?? ""}`.toLowerCase();
    if (/carbon|vaporfly|alphafly|adios\s*pro|metaspeed|endorphin\s*pro/.test(probe)) {
      hls.push("Piastra reattiva per ritmi veloci");
    } else if (/dropset\s*(pro|elite)/.test(probe)) {
      hls.push("Pensata per functional training e gare ibride");
    } else if (/dropset/.test(probe)) {
      hls.push("Base stabile per forza, squat e sala pesi");
    } else if (/therma|fleece|polar|wolf/.test(probe)) {
      hls.push("Strato isolante per clima fresco e outdoor");
    } else if (/dri[\s-]*fit|adv|trail/.test(probe)) {
      hls.push("Tessuto tecnico traspirante ad asciugatura rapida");
    } else if (/gtx|gore/.test(probe)) {
      hls.push("Membrana impermeabile Gore-Tex");
    } else {
      hls.push("Selezionato per aderenza alla tua ricerca");
    }
    if (p.offers.length > 1) {
      hls.push(`Confrontato tra ${p.offers.length} negozi partner`);
    } else if (p.offers[0]?.is_free_shipping) {
      hls.push("Spedizione gratuita inclusa");
    } else {
      hls.push(`Disponibile su ${p.offers[0]?.store_name ?? "negozio partner"}`);
    }
    if (p.cross_store_savings && p.cross_store_savings >= 5) {
      hls.push(`Risparmio fino a €${Math.round(p.cross_store_savings)} tra gli store`);
    } else if (p.best_price != null) {
      hls.push(`Miglior prezzo rilevato €${p.best_price.toFixed(2)}`);
    }
    return {
      product: p,
      badge_text: computeDiscountBadge(p),
      highlights: hls.slice(0, 3),
    };
  });

  const comparativeCards: ComparativeCardOut[] = featuredCards.map((fc) => ({
    product: fc.product,
    model_name: fc.product.canonical_name,
    ideal_for: fc.highlights[0] ?? "Uso sportivo tecnico",
    strengths: fc.highlights[1] ?? (fc.product.best_price != null ? `Da €${fc.product.best_price.toFixed(2)}` : "Prezzo verificato"),
    section_title: "Confronto rapido",
  }));

  const topNames = sections.slice(0, 2).map((s) => `**${s.title}**`).join(" e ");
  const minP = Math.min(...results.map((r) => r.best_price ?? 9999));
  const summary = minP < 9999
    ? `Ho trovato **${results.length} modelli** per la tua ricerca, organizzati tra ${topNames}, con offerte verificate a partire da **€${minP.toFixed(2)}**.`
    : `Ho trovato **${results.length} modelli** compatibili organizzati tra ${topNames}.`;

  // Contextual short follow-ups
  const followUps: string[] = [];
  const isWearableSize = !productType || ["shoes", "trail_shoes", "football_boots", "basketball_shoes", "tennis_shoes", "volleyball_shoes", "leggings_tights", "shorts", "pants", "top", "long_sleeve_top", "short_sleeve_top", "singlet_top", "jacket"].includes(productType);
  if (!size && isWearableSize) {
    followUps.push(preferredSize ? `Mostrami taglia ${preferredSize}` : "Mostrami la mia taglia");
  }
  if (sections.length >= 2) {
    followUps.push(`Solo ${sections[0].title.slice(0, 26)}`);
  } else if (!gender && isWearableSize) {
    followUps.push("Solo modelli Donna");
  }
  if (maxPrice == null && minP < 9999) {
    const prices = results.map((r) => r.best_price ?? 0).filter((v) => v > 0).sort((a, b) => a - b);
    const median = prices[Math.floor(prices.length / 2)] ?? minP;
    const cap = Math.max(25, Math.round((median * 0.95) / 10) * 10);
    followUps.push(`Sotto ${cap} €`);
  }
  if (followUps.length < 3) followUps.push("Mostrami altre alternative");

  return {
    summary,
    sections,
    featuredCards,
    comparativeCards,
    followUps: followUps.slice(0, 3),
  };
}

function buildChips(intent: {
  brand: string | null;
  category: string | null;
  gender: string | null;
  max_price: number | null;
  size: string | null;
  color: string | null;
}) {
  const chips: Array<{ id: string; label: string; param_key: string; value: string }> = [];
  if (intent.brand) chips.push({ id: "chip_brand", label: intent.brand, param_key: "brand", value: intent.brand });
  if (intent.gender && intent.gender !== "Unisex") {
    chips.push({ id: "chip_gender", label: intent.gender, param_key: "gender", value: intent.gender });
  }
  if (intent.size) chips.push({ id: "chip_size", label: `Taglia ${intent.size}`, param_key: "size", value: intent.size });
  if (intent.color) chips.push({ id: "chip_color", label: intent.color, param_key: "color", value: intent.color });
  if (intent.max_price != null) {
    chips.push({ id: "chip_price", label: `Sotto €${Math.round(intent.max_price)}`, param_key: "max_price", value: String(intent.max_price) });
  }
  return chips;
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
  let noCache = url.searchParams.get("no_cache") === "1";
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
    if (body?.no_cache === true || body?.no_cache === "1") noCache = true;
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
        search_mode: "deep_dive",
        is_deep_dive: false,
        is_conversational_advice: true,
        conversational_header: "Solo articoli sportivi",
        conversational_summary: guard.reason ?? "Chiedimi prodotti sportivi!",
        searched_queries: [],
        curated_sections: [],
        comparative_cards: [],
        featured_cards: [],
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

    // =========================================================================
    // SERVER-SIDE RESPONSE CACHE (standalone fresh queries only, 15m TTL)
    // =========================================================================
    const isCacheEligible = !contextQuery?.trim() &&
      !sessionId?.trim() &&
      !userImageUrl?.trim() &&
      !noCache;
    let cacheKey: string | null = null;

    if (isCacheEligible) {
      try {
        cacheKey = await buildSearchCacheKey({
          q,
          mode,
          maxPrice: maxPriceParam,
          size: sizeParam,
          preferredSize,
          category: categoryParam,
          store: storeParam,
          limit,
        });
        const nowIso = new Date().toISOString();
        const { data: cachedRow } = await supabase
          .from("smart_search_cache")
          .select("payload,context_state,hit_count")
          .eq("cache_key", cacheKey)
          .gt("expires_at", nowIso)
          .maybeSingle();

        if (cachedRow?.payload && typeof cachedRow.payload === "object") {
          const cached = cachedRow.payload as Record<string, unknown>;
          const cachedResults = Array.isArray(cached.results) ? (cached.results as MatchedProductOut[]) : [];
          const cachedSections = Array.isArray(cached.curated_sections) ? cached.curated_sections : [];
          const cachedSq = Array.isArray(cached.searched_queries) ? (cached.searched_queries as string[]) : [];

          emitStep?.({
            id: "intent",
            status: "done",
            title: "Piano di ricerca pronto",
            detail: cachedSq.slice(0, 3).join(" · ") || q,
            elapsed_ms: Date.now() - startedAt,
          });
          emitStep?.({
            id: "catalog",
            status: "done",
            title: `${cachedResults.length} ${cachedResults.length === 1 ? "modello trovato" : "modelli trovati"}`,
            detail: "Catalogo verificato tra i negozi partner",
            elapsed_ms: Date.now() - startedAt,
          });
          emitStep?.({
            id: "curate",
            status: "done",
            title: `${cachedSections.length} ${cachedSections.length === 1 ? "sezione creata" : "sezioni create"}`,
            detail: "Selezione pronta",
            elapsed_ms: Date.now() - startedAt,
          });

          // Still persist user's personal chat turn & context_state so follow-ups work seamlessly
          let cachedSavedIds: { session_id: string; turn_id: string } | null = null;
          if (deviceId || userId) {
            cachedSavedIds = await saveChatTurn(supabase, {
              sessionId: null,
              deviceId,
              userId,
              chatType: "smart_search",
              query: q,
              isFollowUp: false,
              payload: {
                conversational_header: typeof cached.conversational_header === "string" ? cached.conversational_header : null,
                conversational_summary: typeof cached.conversational_summary === "string" ? cached.conversational_summary : null,
                is_conversational_advice: Boolean(cached.is_conversational_advice),
                intent: cached.intent,
                chips: Array.isArray(cached.chips) ? cached.chips : [],
                results: cachedResults,
                curated_sections: cachedSections,
                comparative_cards: Array.isArray(cached.comparative_cards) ? cached.comparative_cards : [],
                featured_cards: Array.isArray(cached.featured_cards) ? cached.featured_cards : [],
                searched_queries: cachedSq,
                spotlight: cached.spotlight ?? null,
                follow_up_suggestions: Array.isArray(cached.follow_up_suggestions) ? (cached.follow_up_suggestions as string[]) : [],
                is_off_topic: false,
                is_unsafe: false,
              },
              contextState: (cachedRow.context_state && typeof cachedRow.context_state === "object")
                ? (cachedRow.context_state as Record<string, unknown>)
                : {},
              userImageUrl: null,
            });
          }

          // Non-blocking hit counter increment via EdgeRuntime.waitUntil when available
          const hitUpdate = Promise.resolve(
            supabase
              .from("smart_search_cache")
              .update({ hit_count: Number(cachedRow.hit_count ?? 0) + 1 })
              .eq("cache_key", cacheKey),
          ).catch(() => {});
          (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
            .EdgeRuntime?.waitUntil?.(hitUpdate);

          return {
            ...cached,
            session_id: cachedSavedIds?.session_id ?? null,
            turn_id: cachedSavedIds?.turn_id ?? null,
            user_image_url: null,
            cache_hit: true,
          };
        }
      } catch {
        // Degrade silently to live search if cache read ever fails
      }
    }

    emitStep?.({
      id: "intent",
      status: "running",
      title: "Analisi della richiesta",
      detail: contextQuery ? "Collego il contesto della conversazione" : "Pianifico le ricerche nel catalogo",
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
    const pureQuestion = isPureAdviceQuestion(normalizedQ, isFollowUp);

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

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "openai/gpt-4o-mini";
    const plannerModels = ["google/gemini-2.5-flash-lite", "google/gemini-2.5-flash", primaryModel];
    const merchModels = ["google/gemini-2.5-flash", primaryModel, "meta-llama/llama-3.3-70b-instruct"];

    // =========================================================================
    // STAGE 1: QUERY UNDERSTANDING & MULTI-QUERY EXPANSION PLANNER
    // =========================================================================
    const plannerSystemPrompt =
      "Sei il Query Planner del motore di ricerca AI sportivo di FitMatch (stile Shopify Shop).\n" +
      "Capisci la richiesta dell'utente e pianifica 2-4 sotto-ricerche mirate per interrogare il catalogo italiano/inglese.\n" +
      "REGOLE:\n" +
      "1. 'query_type': exact_model | category_brand | advisory | comparison | followup_filter | pure_question (pure_question SOLO per domande tecniche senza ricerca prodotti, es. 'Come calzano?').\n" +
      "2. 'product_type': leggings_tights, shorts, pants, long_sleeve_top, short_sleeve_top, singlet_top, top, jacket, socks, headwear, heart_rate_monitor, bike_computer, gps_watch, eyewear, hydration, swim, padel_racket, tennis_racket, football_boots, basketball_shoes, tennis_shoes, volleyball_shoes, trail_shoes, shoes, winter_sports, nutrition, smart_trainer, o null.\n" +
      "3. 'sub_queries' (2-4 voci): { \"label\": \"query di ricerca pulita mostrata all'utente\", \"terms\": [\"termine1\", \"termine2\"], \"role\": \"primary|variant|complementary\" }.\n" +
      "   - 'label' DEVE sembrare una vera ricerca prodotto concreta (es. 'Adidas Adizero Dropset Pro', 'Nike ACG manica lunga trail', 'Nike ACG Therma-FIT fleece', 'Nike Vaporfly & Alphafly maratona'), MAI etichette meta come 'Specific models' o 'Alternative'!\n" +
      "   - Esempio 'Adidas adizero dropset shoes': primary ['Adidas Adizero Dropset Pro', 'Adidas Adizero Dropset Elite'], variant ['Adidas Dropset 4', 'Adidas Dropset 4 Power'], variant ['Adidas Dropset 3', 'Adidas Dropset Control'].\n" +
      "   - Esempio 'Long sleeve nike acg': primary ['Nike ACG manica lunga', 'Nike ACG ls', 'Nike ACG long sleeve'], variant ['Nike ACG Chinati', 'Nike ACG Wildsee zip', 'Nike ACG 1/4 zip'], complementary ['Nike ACG Wolf Grid', 'Nike ACG Wolf Tree', 'Nike ACG Therma-FIT', 'Nike ACG Tuff Fleece'].\n" +
      "   - Esempio 'Scarpe da gara per la maratona': primary ['Nike Vaporfly', 'Nike Alphafly', 'Adidas Adizero Adios Pro'], variant ['Asics Metaspeed', 'Saucony Endorphin Pro', 'New Balance Supercomp Elite'], complementary ['Nike Zoom Fly', 'Adidas Adizero Boston', 'Asics Superblast'].\n" +
      "   - Per query 'advisory' o di categoria generica con filtri (es. 'scarpe ammortizzate 85kg ginocchia' o 'scarpe running taglia 43 sotto 120 euro'), inserisci SEMPRE nomi di modelli/linee reali di riferimento nei terms divisi per 2-3 profili (es. ['Nike Pegasus', 'Asics Cumulus', 'Brooks Ghost'], ['Hoka Clifton', 'Asics Novablast', 'Saucony Ride']), MAI solo frasi generiche!\n" +
      "   - Per query 'comparison' (es. 'Confronta Asics Nimbus 26 vs Hoka Bondi 8'), crea una sub_query 'primary' SEPARATA per ciascun modello confrontato!\n" +
      "   - MAI inserire un nome di brand da solo nei terms!\n" +
      "4. Se query_type=='pure_question', compila SEMPRE 'direct_answer' (2-3 frasi tecniche concrete in italiano riferite al prodotto nel contesto).\n" +
      "Rispondi SOLO con JSON valido:\n" +
      '{"query_type":"...","corrected_query":"...","brand":null,"product_type":null,"gender":null,"max_price":null,"min_price":null,"size":null,"color":null,"model_tokens":[],"features":[],"sub_queries":[{"label":"...","terms":["..."],"role":"primary"}],"direct_answer":null}';

    const llmPlan = await callOpenRouterJSON({
      systemPrompt: plannerSystemPrompt,
      userPrompt: prevContext && !categorySwitched
        ? `Contesto precedente: ${JSON.stringify(prevContext)}\nRichiesta: ${effectiveQueryForLLM}`
        : effectiveQueryForLLM,
      models: plannerModels,
      temperature: 0.1,
      maxTokens: 380,
      title: "FitMatch Query Planner",
      timeoutMs: 6_500,
      disableReasoning: true,
    });

    // Deterministic reconciliation over LLM plan
    const llmPTypeRaw = typeof llmPlan?.product_type === "string"
      ? llmPlan.product_type.trim().toLowerCase()
      : null;
    const llmPType = llmPTypeRaw && VALID_PRODUCT_TYPES.has(llmPTypeRaw as ProductType)
      ? (llmPTypeRaw as ProductType)
      : null;

    const productType: ProductType | null = detProductType ?? llmPType;

    const explicitMaxPrice = maxPriceParam != null && maxPriceParam !== "" ? Number(maxPriceParam) : null;
    const maxPrice = explicitMaxPrice ??
      local.max_price ??
      (typeof llmPlan?.max_price === "number" ? llmPlan.max_price : null) ??
      (!categorySwitched && isFollowUp && typeof prevContext?.max_price === "number" ? prevContext.max_price : null);

    const minPrice = local.min_price ??
      (typeof llmPlan?.min_price === "number" ? llmPlan.min_price : null);

    const effectivePreferredSize = preferredSize && preferredSize.trim() ? preferredSize.trim() : null;
    const size = (sizeParam && sizeParam.trim()) ||
      local.size ||
      (local.asksMySize && effectivePreferredSize ? effectivePreferredSize : null) ||
      (llmPlan?.size && String(llmPlan.size).trim().toLowerCase() !== "null" ? String(llmPlan.size).trim() : null) ||
      (!categorySwitched && isFollowUp && prevContext?.size ? String(prevContext.size) : null);

    const gender = local.gender === "Unisex"
      ? null
      : (local.gender ??
        (llmPlan?.gender && ["Uomo", "Donna"].includes(String(llmPlan.gender)) ? String(llmPlan.gender) : null) ??
        (!categorySwitched && isFollowUp && prevContext?.gender ? String(prevContext.gender) : null));

    const colorConstraint = local.color ??
      (typeof llmPlan?.color === "string" && llmPlan.color.trim() ? detectColorConstraint(llmPlan.color) : null);

    const allQueryBrands = extractAllBrands(normalizedQ);
    const queryType = String(llmPlan?.query_type ?? "").toLowerCase();
    const isComparison = queryType === "comparison" ||
      allQueryBrands.length >= 2 ||
      /\b(confronta|confronto|\bvs\b|versus|differenz[ae])\b/i.test(normalizedQ);

    const llmBrandRaw = llmPlan?.brand && String(llmPlan.brand).trim().toLowerCase() !== "null"
      ? String(llmPlan.brand).trim()
      : null;
    const llmBrand = llmBrandRaw && KNOWN_BRANDS.some((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())
      ? KNOWN_BRANDS.find((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())!
      : null;
    const brand = (isComparison && allQueryBrands.length >= 2)
      ? null
      : (currentBrand ??
        (subBrand ? subBrand[0] : null) ??
        (isFollowUp && !categorySwitched ? prevBrand : null) ??
        (llmBrand && normalizedQ.toLowerCase().includes(llmBrand.toLowerCase()) ? llmBrand : null));

    const category = (categoryParam && categoryParam.trim() && categoryParam !== "all" && categoryParam !== "tutti")
      ? categoryParam.trim()
      : mapProductTypeToCategory(productType);

    const entityTokens: string[] = [...(currentEntities.length > 0 ? currentEntities : prevEntities)];
    if (entityTokens.length === 0 && !broadeningFollowUp && Array.isArray(llmPlan?.model_tokens)) {
      const qLow = normalizedQ.toLowerCase();
      for (const mt of llmPlan.model_tokens) {
        const tok = normalizeQueryTypos(String(mt ?? "")).toLowerCase().trim();
        if (tok.length >= 2 && qLow.includes(tok) && !entityTokens.includes(tok)) {
          entityTokens.push(tok);
        }
      }
    }

    const isPureQA = pureQuestion || (queryType === "pure_question" && isFollowUp && currentEntities.length === 0);
    const isAdvisory = !isPureQA && !isComparison && (
      queryType === "advisory" ||
      (currentEntities.length === 0 && /\b(miglior[ie]|consiglia|consigliami|\d+\s*kg|ginocchi|schiena|fascite|principiant|pronat)\b/i.test(normalizedQ))
    );
    const isExactModel = entityTokens.length > 0 && !broadeningFollowUp && !isComparison && !isAdvisory && !isPureQA;
    const effectiveEntityTokens = (isAdvisory || isPureQA) ? [] : entityTokens;

    // Build validated multi-query plan
    const plannedSubQueries: SubQuerySpec[] = [];
    const seenTermSigs = new Set<string>();

    const pushSubQuery = (sq: SubQuerySpec) => {
      const cleanTerms = sq.terms.map((t) => t.trim()).filter((t) => t.length >= 2);
      if (cleanTerms.length === 0) return;
      const sig = cleanTerms.map((t) => t.toLowerCase()).sort().join("|") + "|" + sq.role;
      if (seenTermSigs.has(sig)) return;
      seenTermSigs.add(sig);
      plannedSubQueries.push({ ...sq, terms: cleanTerms.slice(0, 5) });
    };

    // Parse LLM sub-queries safely
    const rawSubQueries = Array.isArray(llmPlan?.sub_queries) ? llmPlan.sub_queries : [];
    const rawPrimaryTermsFromLlm: string[] = [];
    for (const item of rawSubQueries) {
      if (!item || typeof item !== "object") continue;
      const obj = item as Record<string, unknown>;
      const label = String(obj.label ?? "").trim();
      const roleRaw = String(obj.role ?? "primary").toLowerCase();
      const role: "primary" | "variant" | "complementary" =
        roleRaw === "variant" ? "variant" : roleRaw === "complementary" ? "complementary" : "primary";
      const termsRaw = Array.isArray(obj.terms) ? obj.terms.map((t) => String(t ?? "").trim()).filter(Boolean) : [];
      if (termsRaw.length === 0) continue;

      if (role === "primary") {
        rawPrimaryTermsFromLlm.push(...termsRaw);
      }

      // Resolve per-subquery brand for cross-brand comparisons (e.g. "Asics Nimbus 26 vs Hoka Bondi 8")
      const sqBrandsFound = extractAllBrands(termsRaw.join(" "));
      const sqBrand = isComparison
        ? (sqBrandsFound.length === 1 ? sqBrandsFound[0] : null)
        : brand;

      // Compute shared entity tokens across ALL terms in a variant/complementary/comparison sub-query
      let sqEntities: string[];
      if (role === "primary" && !isComparison && !isAdvisory) {
        sqEntities = effectiveEntityTokens;
      } else {
        const perTermEnts = termsRaw.map((t) => new Set(extractSpecificEntityTokens(t, sqBrand)));
        const shared = perTermEnts.length > 0
          ? Array.from(perTermEnts[0]).filter((tok) => perTermEnts.every((s) => s.has(tok)))
          : [];
        sqEntities = shared.slice(0, 2);
      }

      const cleanedTerms = buildCatalogSearchTerms({
        rawQuery: (role === "primary" && !isComparison && !isAdvisory) ? normalizedQ : termsRaw[0],
        keywords: termsRaw,
        brand: sqBrand,
        productType,
        entityTokens: (role === "primary" && !isComparison && !isAdvisory) ? effectiveEntityTokens : [],
        isComparison: isComparison || isAdvisory || role !== "primary",
      });

      if (cleanedTerms.length > 0) {
        pushSubQuery({
          label: label || cleanedTerms[0],
          terms: cleanedTerms,
          role,
          brand: sqBrand,
          productType,
          entityTokens: sqEntities,
          allowSemantic: role === "primary" && !isExactModel && !isComparison,
          limit: role === "primary" ? 20 : 14,
        });
      }
    }

    // For pure Q&A follow-ups (e.g. "Come calzano come taglia?"), reuse previous session keywords or contextQuery instead of searching literal question text
    const prevQueryFallback = prevContext?.last_query
      ? String(prevContext.last_query)
      : (isFollowUp && contextQuery ? contextQuery.trim() : null);
    const prevKeywords = (shouldInheritPrevEntities || isPureQA) && Array.isArray(prevContext?.last_keywords)
      ? prevContext.last_keywords.map(String).filter(Boolean)
      : [];
    const qaEntities = currentEntities.length > 0 ? currentEntities : prevEntities;
    const qaRawForSearch = isPureQA
      ? (currentEntities.length > 0 || currentBrand ? normalizedQ : (prevQueryFallback ?? normalizedQ))
      : (shouldInheritPrevEntities && prevQueryFallback ? prevQueryFallback : normalizedQ);
    const primaryFallbackTerms = buildCatalogSearchTerms({
      rawQuery: qaRawForSearch,
      keywords: isPureQA
        ? (currentEntities.length > 0 ? rawPrimaryTermsFromLlm : prevKeywords)
        : (rawPrimaryTermsFromLlm.length > 0 ? rawPrimaryTermsFromLlm : prevKeywords),
      brand,
      productType,
      entityTokens: isPureQA ? qaEntities : effectiveEntityTokens,
      isComparison,
    });

    if (isPureQA) {
      plannedSubQueries.length = 0;
      if (primaryFallbackTerms.length > 0 || brand || productType) {
        plannedSubQueries.push({
          label: primaryFallbackTerms[0] ?? prevQueryFallback ?? normalizedQ,
          terms: primaryFallbackTerms.slice(0, 4),
          role: "primary",
          brand,
          productType,
          entityTokens: qaEntities,
          allowSemantic: primaryFallbackTerms.length === 0 && !brand,
          limit: 6,
        });
      }
    } else if (!plannedSubQueries.some((sq) => sq.role === "primary") && primaryFallbackTerms.length > 0) {
      plannedSubQueries.unshift({
        label: primaryFallbackTerms[0],
        terms: primaryFallbackTerms,
        role: "primary",
        brand,
        productType,
        entityTokens: effectiveEntityTokens,
        allowSemantic: !isExactModel,
        limit: 22,
      });
    } else if (plannedSubQueries.length === 0 && (brand || productType)) {
      // Pure category + filter query (e.g. "scarpe running taglia 43 sotto 120 euro") -> browse DB category directly
      plannedSubQueries.push({
        label: normalizedQ,
        terms: [],
        role: "primary",
        brand,
        productType,
        entityTokens: [],
        allowSemantic: true,
        limit: 28,
      });
    }

    // Deterministic sibling expansion for compound model lines of a KNOWN brand (e.g. "adizero dropset" -> also fetch "dropset 4", "dropset 3")
    if (brand && effectiveEntityTokens.length >= 2 && !isComparison) {
      const nonDigitTokens = effectiveEntityTokens.filter((t) => !/^\d+$/.test(t));
      const coreModel = nonDigitTokens[nonDigitTokens.length - 1];
      const hasNonPrimary = plannedSubQueries.some((sq) => sq.role !== "primary");
      if (coreModel && coreModel.length >= 4 && !hasNonPrimary) {
        const siblingTerm = `${brand} ${coreModel}`;
        pushSubQuery({
          label: `${siblingTerm} serie completa`,
          terms: [siblingTerm, coreModel],
          role: "variant",
          brand,
          productType,
          entityTokens: [coreModel],
          allowSemantic: false,
          limit: 12,
        });
      }
    }

    // Deterministic warm/midlayer expansion for long-sleeve queries (so Therma-FIT / Wolf Grid / fleece layers are found!)
    if (productType === "long_sleeve_top") {
      const subTag = subBrand ? subBrand[1] : null;
      const prefix = [brand, subTag].filter(Boolean).join(" ").trim();
      const hasWarmSubQuery = plannedSubQueries.some((sq) =>
        sq.terms.some((t) => /\b(therma|fleece|felpa|wolf|warm|termic|half\s*zip)\b/i.test(t))
      );
      if (!hasWarmSubQuery) {
        const warmTerms = prefix
          ? [`${prefix} therma fit`, `${prefix} half zip`, `${prefix} fleece`, `${prefix} zip`]
          : ["maglia termica manica lunga", "half zip running", "therma fit"];
        pushSubQuery({
          label: prefix ? `${prefix} strati caldi e Therma-FIT` : "Maglie termiche e half-zip",
          terms: warmTerms,
          role: "complementary",
          brand,
          productType: "long_sleeve_top",
          entityTokens: subTag ? [subTag] : [],
          allowSemantic: false,
          limit: 12,
        });
      }
    }

    const plannedLabels = plannedSubQueries.map((sq) => sq.label).slice(0, 5);

    emitStep?.({
      id: "intent",
      status: "done",
      title: "Piano di ricerca pronto",
      detail: plannedLabels.slice(0, 3).join(" · ") || normalizedQ,
      elapsed_ms: Date.now() - startedAt,
    });

    emitStep?.({
      id: "catalog",
      status: "running",
      title: "Cerco nei negozi partner",
      detail: plannedLabels.length > 1
        ? `${plannedLabels.length} ricerche mirate in parallelo`
        : "Confronto modelli, categorie e prezzi",
      elapsed_ms: Date.now() - startedAt,
    });

    const effectiveRawForSearch = shouldInheritPrevEntities && prevContext?.last_query
      ? `${String(prevContext.last_query)} ${normalizedQ}`
      : normalizedQ;

    const multiRes = await searchCatalogMultiQuery(supabase, {
      rawQuery: effectiveRawForSearch,
      subQueries: plannedSubQueries,
      brand,
      category,
      productType,
      maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
      minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
      size,
      preferredSize: effectivePreferredSize,
      gender,
      store: storeParam,
      isComparison,
      totalLimit: Math.min(Math.max(limit, 1), 45),
    });

    let finalResults = multiRes.products;
    const roleById: Record<string, "primary" | "variant" | "complementary"> = { ...multiRes.roleById };

    // Relaxed fallback pass if strict search returned 0 results:
    // NEVER drop entityTokens + trigger open semantic search for exact non-existent SKUs/brands (e.g. "Scarpe NASA Turbo 9000"),
    // otherwise semantic search hallucinates unrelated shoes!
    // Only allow relaxed fallback for generic/advisory/category queries, OR known-brand generation-only relaxation.
    if (finalResults.length === 0) {
      if (!isExactModel) {
        const relaxed = await searchCatalogOffers(supabase, {
          rawQuery: effectiveRawForSearch,
          keywords: primaryFallbackTerms,
          brand,
          category,
          productType,
          entityTokens: [],
          maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
          minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
          size,
          preferredSize: effectivePreferredSize,
          gender,
          store: storeParam,
          semanticQuery: normalizedQ,
          allowSemantic: true,
          limit: 16,
        });
        finalResults = relaxed;
        for (const p of relaxed) roleById[p.id] = "primary";
      } else if (brand && effectiveEntityTokens.some((t) => /^\d+$/.test(t))) {
        const nonDigit = effectiveEntityTokens.filter((t) => !/^\d+$/.test(t) && t.length >= 3);
        if (nonDigit.length > 0) {
          const genRelaxed = await searchCatalogOffers(supabase, {
            rawQuery: `${brand} ${nonDigit.join(" ")}`,
            keywords: [`${brand} ${nonDigit.join(" ")}`, nonDigit.join(" ")],
            brand,
            category,
            productType,
            entityTokens: nonDigit,
            maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
            minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
            size,
            preferredSize: effectivePreferredSize,
            gender,
            store: storeParam,
            semanticQuery: null,
            allowSemantic: false,
            limit: 12,
          });
          finalResults = genRelaxed;
          for (const p of genRelaxed) roleById[p.id] = "primary";
        }
      }
    }

    // Apply explicit color filter if requested by user (e.g. "Mostrami solo T-shirt nere")
    let colorFilteredNote: string | null = null;
    if (colorConstraint && finalResults.length > 0) {
      const colorMatched = finalResults.filter((p) => {
        const probe = `${p.canonical_name} ${p.offers.slice(0, 6).map((o) => o.title).join(" ")}`;
        return colorConstraint.matchRegex.test(probe);
      });
      if (colorMatched.length > 0) {
        finalResults = colorMatched;
      } else {
        colorFilteredNote = `Non ho trovato varianti esplicitamente etichettate **${colorConstraint.label.toLowerCase()}**, quindi ti mostro comunque i modelli più vicini disponibili.`;
      }
    }

    emitStep?.({
      id: "catalog",
      status: "done",
      title: `${finalResults.length} ${finalResults.length === 1 ? "modello trovato" : "modelli trovati"}`,
      detail: finalResults.length > 0
        ? "Catalogo verificato tra i negozi partner"
        : "Nessuna offerta attiva per questi filtri",
      elapsed_ms: Date.now() - startedAt,
    });

    // =========================================================================
    // STAGE 2: GROUNDED AI MERCHANDISER & EDITORIAL SYNTHESIS (Shop Style!)
    // =========================================================================
    let header = "Ho cercato prodotti";
    let summary = "";
    let curatedSections: CuratedSection[] = [];
    let featuredCards: FeaturedCardOut[] = [];
    let comparativeCards: ComparativeCardOut[] = [];
    let followUps: string[] = [];

    if (isPureQA) {
      // Pure Q&A follow-up MUST always return a direct expert answer (even if 0 filtered catalog items matched!)
      const refSubject = finalResults[0]?.canonical_name ?? prevQueryFallback ?? "i modelli selezionati";
      header = `Risposta su ${refSubject}`;
      const llmAns = typeof llmPlan?.direct_answer === "string" ? llmPlan.direct_answer.trim() : "";
      if (llmAns.length >= 20) {
        summary = llmAns;
      } else if (/calzan|taglia|veston/i.test(normalizedQ)) {
        summary = `In generale per **${refSubject}** la calzata è regolare: se corri lunghe distanze o hai la pianta leggermente larga, conviene scegliere **mezza taglia EU in più** rispetto alle scarpe casual per evitare pressione in punta.`;
      } else {
        summary = `Per **${refSubject}**, i modelli mostrati offrono un ottimo equilibrio tecnico per l'uso richiesto. Se vuoi affinare la scelta, dimmi il tuo budget, la taglia o il terreno su cui ti alleni.`;
      }
      if (finalResults.length > 0) {
        curatedSections = [{
          id: "qa_related",
          title: "Modelli di riferimento",
          subtitle: "Offerte verificate nei negozi partner",
          products: finalResults.slice(0, 6),
        }];
      }
      followUps = [
        effectivePreferredSize ? `Mostrami taglia ${effectivePreferredSize}` : "Mostrami la mia taglia",
        "Mostrami alternative simili",
        finalResults[0]?.best_price != null
          ? `Sotto ${Math.max(30, Math.round((finalResults[0].best_price * 0.9) / 10) * 10)} €`
          : "Mostrami le migliori offerte",
      ];
    } else if (finalResults.length === 0) {
      header = "Ho cercato prodotti";
      const filterNotes: string[] = [];
      if (maxPrice != null) filterNotes.push(`sotto €${Math.round(maxPrice)}`);
      if (size) filterNotes.push(`taglia ${size}`);
      if (gender) filterNotes.push(gender);
      if (colorConstraint) filterNotes.push(colorConstraint.label.toLowerCase());
      if (storeParam) filterNotes.push(`su ${storeParam}`);
      summary = filterNotes.length > 0
        ? `Non ho trovato offerte attive per **${normalizedQ}** con i filtri selezionati (${filterNotes.join(", ")}). Prova ad ampliare il budget o rimuovere un filtro per vedere i modelli disponibili.`
        : `Al momento non ho trovato offerte attive in catalogo per **${normalizedQ}**. Prova con un nome modello leggermente diverso o una ricerca più ampia.`;
      followUps = [
        brand ? `Tutti i modelli ${brand}` : "Mostrami modelli simili",
        maxPrice != null ? "Rimuovi limite di prezzo" : "Mostrami le migliori offerte",
        size ? "Mostra tutte le taglie" : "Cerca alternative consigliate",
      ];
    } else {
      emitStep?.({
        id: "curate",
        status: "running",
        title: "Organizzo sezioni e confronto",
        detail: "Seleziono categorie e punti chiave tecnici",
        elapsed_ms: Date.now() - startedAt,
      });

      // Balanced role sampling so Stage-2 sees primary + variant + complementary lines
      const pickBalancedIndices = (): number[] => {
        const prim: number[] = [];
        const vari: number[] = [];
        const comp: number[] = [];
        for (let i = 0; i < finalResults.length; i++) {
          const r = roleById[finalResults[i].id] ?? "primary";
          if (r === "primary") prim.push(i);
          else if (r === "variant") vari.push(i);
          else comp.push(i);
        }
        const chosen: number[] = [];
        const take = (arr: number[], maxCount: number) => {
          for (const idx of arr) {
            if (chosen.length >= 22 || maxCount <= 0) break;
            if (!chosen.includes(idx)) {
              chosen.push(idx);
              maxCount--;
            }
          }
        };
        take(prim, 10);
        take(vari, 6);
        take(comp, 6);
        for (let i = 0; i < finalResults.length && chosen.length < 22; i++) {
          if (!chosen.includes(i)) chosen.push(i);
        }
        return chosen;
      };

      const manifestIndices = pickBalancedIndices();
      const compactCatalogLines = manifestIndices.map((idx) => {
        const p = finalResults[idx];
        const bestOffer = p.offers[0];
        const roleTag = (roleById[p.id] ?? "primary")[0].toUpperCase();
        const disc = bestOffer?.discount_pct != null && bestOffer.discount_pct >= 5 ? `-${Math.round(bestOffer.discount_pct)}%` : "";
        const priceStr = p.best_price != null ? `€${p.best_price.toFixed(2)}` : "";
        const sample = (bestOffer?.title ?? "").replace(/\|/g, " ").slice(0, 75);
        return `${idx}|${roleTag}|${p.canonical_name}|${p.gender ?? "Unisex"}|${priceStr}|${disc}|${p.offers.length}st|${sample}`;
      }).join("\n");

      const merchSystemPrompt =
        "Sei il Merchandiser & Shopping Assistant AI di FitMatch, nello stile brillante, conciso e autorevole dell'app Shopify Shop.\n" +
        "Ricevi la query dell'utente e la lista REALE dei prodotti trovati (`indice|ruolo P/V/C|nome|genere|prezzo|sconto|store|titolo_offerta`).\n\n" +
        "REGOLE TASSATIVE:\n" +
        "1. 'summary' (2-3 frasi nitide in italiano, max 280 caratteri):\n" +
        "   - Stile editoriale diretto basato SOLO sui modelli presenti nella lista: spiega le famiglie/varianti trovate e per quale uso è pensata ciascuna, con **grassetto** su 2-4 nomi modello/tecnologie.\n" +
        "   - Esempio ottimo: 'Ho trovato diverse **adidas Adizero Dropset**, soprattutto le versioni **Dropset Pro** ed **Elite** pensate per allenamento funzionale e fitness racing: leggere, stabili e con buona trazione. Disponibili anche le più tradizionali **Dropset 3 e 4** per forza e sala pesi.'\n" +
        "   - Esempio ottimo: 'Ho trovato diverse **Nike ACG a manica lunga**, dalle T-shirt essenziali ai modelli tecnici **Dri-FIT ADV** per trail e hiking, fino agli strati caldi **Therma-FIT** e **Wolf Grid** per clima fresco.'\n" +
        "   - VIETA cliché vuoti ('Scopri la gamma', 'Offrono comfort e stile', 'Per ogni esigenza').\n" +
        "2. 'sections' (2-3 sezioni se ci sono >= 5 prodotti; 1-2 sezioni se < 5):\n" +
        "   - Raggruppa SEMPRE per **linea/modello, uso sportivo, tecnologia o clima** (es. 'adidas Adizero Dropset Pro & Elite' + 'Dropset 3 e 4 per forza e pesi'; oppure 'T-shirt ACG per tutti i giorni' + 'Modelli tecnici per trail e hiking' + 'Più calde per clima fresco'; oppure 'Super scarpe da gara in carbonio' + 'Per lunghi e preparazione veloce').\n" +
        "   - Titolo ultra-pulito (2-5 parole, SENZA due punti ':'), sottotitolo breve e chiaro (max 8 parole, senza punto finale).\n" +
        "   - VIETA ASSOLUTAMENTE sezioni divise per genere ('Per Uomo'/'Per Donna') o generiche ('Sconti più Alti', 'Miglior Prezzo', 'Varianti').\n" +
        "   - Ogni sezione DEVE avere almeno 2 prodotti (se il totale >= 4). Unisci modelli affini (es. Pro + Elite insieme) invece di creare sezioni da 1 prodotto!\n" +
        "   - La prima sezione raccoglie i prodotti `P` più vicini alla query (sottotitolo es. 'Le opzioni più vicine alla tua ricerca').\n" +
        "   - Ogni indice può comparire al massimo in UNA sezione (zero duplicati).\n" +
        "3. 'featured' (esattamente 2 schede se N >= 2, altrimenti 1):\n" +
        "   - Scegli 2 modelli CONTRASTANTI e con NOME MODELLO SPECIFICO (es. 1 della sezione 1 + 1 della sezione 2: Dropset Pro + Dropset 4/3; oppure LeBron XXII + Giannis Freak 8 — EVITA nomi generici di 2 parole come 'Nike Basket' se esistono modelli nominali).\n" +
        "   - Per ciascuno scrivi 3 'highlights' TECNICI REALI ultra-concisi (3-7 parole l'uno, es. 'Lightstrike Pro reattiva', 'Energyrods per transizioni rapide', 'Grip Continental per cambi di direzione' oppure 'Intersuola a doppia densità', 'Supporto laterale in TPU', 'Pensata per squat e pesi').\n" +
        "   - VIETA highlights banali su prezzo/sconto/stile ('Sconto del 40%', 'Stile versatile', 'Ottima vestibilità', 'Prezzo verificato')!\n" +
        "4. 'follow_ups' (esattamente 3 pillole brevi, 2-5 parole ciascuna):\n" +
        "   - Esempi perfetti: 'Mostrami la mia taglia', 'Solo Dropset Pro', 'Sotto 110 €', 'Mostrami solo T-shirt nere', 'Cerco un modello da trail', 'Solo Therma-FIT e pile'.\n" +
        "   - VIETA di ripetere parole già presenti nella query (es. mai 'Solo modelli ACG' se l'utente ha cercato ACG) e calcola un prezzo realistico rispetto alla lista.\n\n" +
        "Rispondi SOLO con JSON valido:\n" +
        '{"summary":"...","sections":[{"title":"...","subtitle":"...","indices":[0,1]}],"featured":[{"index":0,"ideal_for":"...","highlights":["...","...","..."]}],"follow_ups":["...","...","..."]}';

      const activeFiltersSummary = {
        gender,
        size,
        preferred_size: effectivePreferredSize,
        max_price: maxPrice,
        color: colorConstraint?.label ?? null,
      };

      const merchPrompt =
        `Query: "${q}"` +
        (isFollowUp ? ` (Contesto: "${contextQuery}")` : "") +
        `\nFiltri attivi: ${JSON.stringify(activeFiltersSummary)}` +
        `\nProdotti (${manifestIndices.length}):\n${compactCatalogLines}`;

      const merchJson = await callOpenRouterJSON({
        systemPrompt: merchSystemPrompt,
        userPrompt: merchPrompt,
        models: merchModels,
        temperature: 0.2,
        maxTokens: 780,
        title: "FitMatch Merchandiser",
        timeoutMs: 8_000,
        disableReasoning: true,
      });

      const fallback = buildSmartFallbackMerchandising({
        query: normalizedQ,
        results: finalResults,
        roleById,
        productType,
        brand,
        maxPrice,
        gender,
        size,
        preferredSize: effectivePreferredSize,
        isExactModel,
      });

      if (merchJson) {
        // 1. Grounded summary
        const llmSummary = typeof merchJson.summary === "string" ? merchJson.summary.trim() : "";
        summary = llmSummary.length >= 25 ? llmSummary : fallback.summary;
        if (colorFilteredNote) {
          summary = `${summary}\n\n${colorFilteredNote}`;
        }

        // 2. Validated disjoint curated sections (and merge any orphan 1-item section!)
        const rawSections = Array.isArray(merchJson.sections) ? merchJson.sections : [];
        const usedInSections = new Set<number>();
        const builtSections: CuratedSection[] = [];
        for (let sIdx = 0; sIdx < rawSections.length; sIdx++) {
          const sObj = rawSections[sIdx] as Record<string, unknown>;
          const title = String(sObj?.title ?? "").trim();
          const subtitle = String(sObj?.subtitle ?? "").trim();
          const indices = Array.isArray(sObj?.indices) ? sObj.indices : [];
          if (!title || indices.length === 0) continue;

          const secProds: MatchedProductOut[] = [];
          for (const rawI of indices) {
            const idx = Number(rawI);
            if (!Number.isInteger(idx) || idx < 0 || idx >= finalResults.length) continue;
            if (usedInSections.has(idx)) continue;
            usedInSections.add(idx);
            secProds.push(finalResults[idx]);
          }
          if (secProds.length > 0) {
            builtSections.push({
              id: `sec_ai_${sIdx}`,
              title,
              subtitle: subtitle || "Opzioni selezionate per la tua ricerca",
              products: secProds.slice(0, 10),
            });
          }
        }

        // Merge awkward 1-item sections into adjacent section when we have >= 4 products total
        if (builtSections.length > 1 && finalResults.length >= 4) {
          const consolidated: CuratedSection[] = [];
          for (const sec of builtSections) {
            if (sec.products.length === 1 && consolidated.length > 0) {
              consolidated[consolidated.length - 1].products.push(...sec.products);
            } else {
              consolidated.push(sec);
            }
          }
          if (consolidated.length > 1 && consolidated[0].products.length === 1) {
            consolidated[1].products.unshift(...consolidated[0].products);
            consolidated.shift();
          }
          builtSections.length = 0;
          builtSections.push(...consolidated);
        }

        // Ensure top primary items aren't accidentally omitted from the first section
        if (builtSections.length > 0) {
          const topPrimaryIndices = finalResults
            .slice(0, Math.min(6, finalResults.length))
            .map((p, idx) => ({ p, idx }))
            .filter(({ p, idx }) => (roleById[p.id] === "primary") && !usedInSections.has(idx));
          for (const { p, idx } of topPrimaryIndices) {
            if (builtSections[0].products.length < 10) {
              builtSections[0].products.push(p);
              usedInSections.add(idx);
            }
          }
          curatedSections = builtSections.slice(0, 4);
        } else {
          curatedSections = fallback.sections;
        }

        // 3. Validated featured highlight cards (Screenshot 2!)
        const rawFeatured = Array.isArray(merchJson.featured) ? merchJson.featured : [];
        const seenFeatIdx = new Set<number>();
        const builtFeatured: FeaturedCardOut[] = [];
        const builtComp: ComparativeCardOut[] = [];
        for (const fRaw of rawFeatured) {
          if (!fRaw || typeof fRaw !== "object") continue;
          const fObj = fRaw as Record<string, unknown>;
          const idx = Number(fObj.index);
          if (!Number.isInteger(idx) || idx < 0 || idx >= finalResults.length || seenFeatIdx.has(idx)) continue;
          seenFeatIdx.add(idx);
          const prod = finalResults[idx];
          const hls = Array.isArray(fObj.highlights)
            ? fObj.highlights
                .map((h) => String(h ?? "").trim())
                .filter((h) => h.length >= 3 && !/sconto\s+del|prezzo\s+verificat|disponibilit[aà]\s+immediat/i.test(h))
                .slice(0, 3)
            : [];
          if (hls.length < 2) continue;
          builtFeatured.push({
            product: prod,
            badge_text: computeDiscountBadge(prod),
            highlights: hls,
          });
          builtComp.push({
            product: prod,
            model_name: prod.canonical_name,
            ideal_for: String(fObj.ideal_for ?? hls[0]).trim(),
            strengths: hls.slice(0, 2).join(" · "),
            section_title: "Confronto rapido",
          });
          if (builtFeatured.length >= 2) break;
        }

        featuredCards = builtFeatured.length > 0 ? builtFeatured : fallback.featuredCards;
        comparativeCards = builtComp.length > 0 ? builtComp : fallback.comparativeCards;

        // 4. Validated follow-up pills (drop redundant query echoes)
        const qCleanTokens = new Set(normalizedQ.toLowerCase().split(/\s+/).filter((t) => t.length >= 3));
        const llmFollowUps = Array.isArray(merchJson.follow_ups)
          ? merchJson.follow_ups
              .map((s) => String(s ?? "").trim())
              .filter((s) => {
                if (s.length < 3 || s.length > 46) return false;
                const sToks = s.toLowerCase().replace(/^solo\s+(modelli\s+)?/, "").split(/\s+/).filter((t) => t.length >= 3);
                if (sToks.length > 0 && sToks.every((t) => qCleanTokens.has(t))) return false;
                return true;
              })
              .slice(0, 3)
          : [];
        followUps = llmFollowUps.length >= 2 ? llmFollowUps : fallback.followUps;
      } else {
        summary = colorFilteredNote ? `${fallback.summary}\n\n${colorFilteredNote}` : fallback.summary;
        curatedSections = fallback.sections;
        featuredCards = fallback.featuredCards;
        comparativeCards = fallback.comparativeCards;
        followUps = fallback.followUps;
      }

      emitStep?.({
        id: "curate",
        status: "done",
        title: `${curatedSections.length} ${curatedSections.length === 1 ? "sezione creata" : "sezioni create"}`,
        detail: curatedSections.map((s) => s.title).slice(0, 2).join(" · "),
        elapsed_ms: Date.now() - startedAt,
      });
    }

    // Reorder finalResults so section 0 products come first (clean consistency for Classic view too)
    if (curatedSections.length > 0) {
      const ordered: MatchedProductOut[] = [];
      const seenOrd = new Set<string>();
      for (const sec of curatedSections) {
        for (const p of sec.products) {
          if (!seenOrd.has(p.id)) {
            seenOrd.add(p.id);
            ordered.push(p);
          }
        }
      }
      for (const p of finalResults) {
        if (!seenOrd.has(p.id)) {
          seenOrd.add(p.id);
          ordered.push(p);
        }
      }
      finalResults = ordered;
    }

    const spotlight = featuredCards[0] ?? null;
    const isDeepDive = mode !== "classic";
    const searchedQueries = multiRes.executedLabels.length > 0
      ? multiRes.executedLabels
      : plannedLabels;

    const intentObj = {
      raw_query: q,
      search_mode: isDeepDive ? "deep_dive" : "classic",
      is_deep_dive: isDeepDive,
      target_keywords: primaryFallbackTerms,
      brand,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
      features: Array.isArray(llmPlan?.features) ? llmPlan.features.map(String) : [],
      explanation: summary,
      source: llmPlan ? "supabase_edge_v3_shop" : "supabase_edge_v3_heuristic",
      is_off_topic: false,
      is_unsafe: false,
      is_conversational_advice: isPureQA,
    };

    const chips = buildChips({
      brand,
      category,
      gender,
      max_price: maxPrice,
      size,
      color: colorConstraint?.label ?? null,
    });

    const contextStateObj: Record<string, unknown> = {
      last_query: normalizedQ,
      last_keywords: primaryFallbackTerms,
      entity_tokens: entityTokens,
      product_type: productType,
      brand,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
    };

    const cacheableResponse = {
      search_mode: isDeepDive ? "deep_dive" : "classic",
      is_deep_dive: isDeepDive,
      is_conversational_advice: isPureQA,
      conversational_header: header,
      conversational_summary: summary,
      searched_queries: searchedQueries,
      curated_sections: curatedSections,
      comparative_cards: isComparison ? comparativeCards : [],
      featured_cards: featuredCards,
      spotlight,
      follow_up_suggestions: followUps,
      intent: intentObj,
      chips,
      total_found: finalResults.length,
      results: finalResults,
      is_off_topic: false,
      is_unsafe: false,
    };

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
          is_conversational_advice: isPureQA,
          intent: intentObj,
          chips,
          results: finalResults,
          curated_sections: curatedSections,
          comparative_cards: isComparison ? comparativeCards : [],
          featured_cards: featuredCards,
          searched_queries: searchedQueries,
          spotlight,
          follow_up_suggestions: followUps,
          is_off_topic: false,
          is_unsafe: false,
        },
        contextState: contextStateObj,
        userImageUrl,
      });
    }

    // Store in server-side cache when eligible and backed by a successful LLM plan
    if (isCacheEligible && cacheKey && llmPlan) {
      try {
        const ttlMs = finalResults.length > 0 ? CACHE_TTL_RESULTS_MS : CACHE_TTL_EMPTY_MS;
        const now = Date.now();
        await supabase.from("smart_search_cache").upsert({
          cache_key: cacheKey,
          payload: cacheableResponse,
          context_state: contextStateObj,
          created_at: new Date(now).toISOString(),
          expires_at: new Date(now + ttlMs).toISOString(),
          hit_count: 0,
        }, { onConflict: "cache_key" });

        // Opportunistic expired row cleanup (5% of writes)
        if (Math.random() < 0.05) {
          const cleanup = Promise.resolve(
            supabase
              .from("smart_search_cache")
              .delete()
              .lt("expires_at", new Date(now).toISOString()),
          ).catch(() => {});
          (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
            .EdgeRuntime?.waitUntil?.(cleanup);
        }
      } catch {
        // Non-blocking: never fail search response if cache write fails
      }
    }

    return {
      ...cacheableResponse,
      session_id: savedIds?.session_id ?? sessionId ?? null,
      turn_id: savedIds?.turn_id ?? null,
      user_image_url: userImageUrl ?? null,
      cache_hit: false,
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
