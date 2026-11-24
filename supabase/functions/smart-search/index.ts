import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  buildCatalogSearchTerms,
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  detectExplicitProductType,
  detectProductType,
  detectSingleProductType,
  detectSubBrand,
  extractAllBrands,
  extractBrand,
  extractExcludedBrands,
  extractExcludedStores,
  extractSpecificEntityTokens,
  extractStoreFilter,
  isBroadeningFollowUp,
  jsonResponse,
  KNOWN_BRANDS,
  KNOWN_STORES,
  loadChatHistoryContext,
  mapProductTypeToCategory,
  MatchedProductOut,
  normalizeProductTypeGroup,
  normalizeQueryTypos,
  ProductType,
  saveChatTurn,
  searchCatalogMultiQuery,
  searchCatalogOffers,
  SortByMode,
  SubQuerySpec,
} from "../_shared/catalog.ts";

const SMART_SEARCH_CACHE_VERSION = "v6_hybrid_1";
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

interface ColorConstraint {
  key: string;
  label: string;
  matchRegex: RegExp;
  sqlTokens: string[];
}

const COLOR_MAP: Array<{ key: string; label: string; regex: RegExp; matchRegex: RegExp; sqlTokens: string[] }> = [
  { key: "black", label: "Nero", regex: /\b(ner[oaie]|black|obsidian|anthracite)\b/i, matchRegex: /\b(ner[oaie]|black|blk|obsidian|anthracite|carbon|charcoal|dark)\b/i, sqlTokens: ["nero", "nera", "neri", "nere", "black", "blk", "obsidian", "anthracite", "charcoal"] },
  { key: "white", label: "Bianco", regex: /\b(bianc[oa]|bianch[ei]|white|summit\s*white)\b/i, matchRegex: /\b(bianc[oa]|bianch[ei]|white|wht|ivory|cream|chalk|sail)\b/i, sqlTokens: ["bianco", "bianca", "bianchi", "bianche", "white", "wht", "ivory", "cream", "chalk", "sail"] },
  { key: "blue", label: "Blu", regex: /\b(blu|azzurr[oaie]|navy|blue)\b/i, matchRegex: /\b(blu|azzurr[oaie]|navy|blue|cobalt|indigo|royal|teal|cyan)\b/i, sqlTokens: ["blu", "azzurro", "azzurra", "azzurri", "azzurre", "navy", "blue", "cobalt", "indigo", "royal", "teal", "cyan"] },
  { key: "red", label: "Rosso", regex: /\b(ross[oaie]|red|crimson|bordeaux)\b/i, matchRegex: /\b(ross[oaie]|red|crimson|scarlet|burgundy|bordeaux|coral)\b/i, sqlTokens: ["rosso", "rossa", "rossi", "rosse", "red", "crimson", "scarlet", "burgundy", "bordeaux", "coral"] },
  { key: "green", label: "Verde", regex: /\b(verd[ei]|green|oliva|olive|kaki|khaki)\b/i, matchRegex: /\b(verd[ei]|green|olive|oliva|kaki|khaki|sage|forest|lime|mint|emerald)\b/i, sqlTokens: ["verde", "verdi", "green", "olive", "oliva", "kaki", "khaki", "sage", "forest", "lime", "mint", "emerald"] },
  { key: "grey", label: "Grigio", regex: /\b(grigi[oaie]|grey|gray|argento|silver)\b/i, matchRegex: /\b(grigi[oaie]|grey|gray|silver|slate|smoke|ash|iron)\b/i, sqlTokens: ["grigio", "grigia", "grigi", "grigie", "grey", "gray", "silver", "slate", "smoke", "ash", "iron"] },
  { key: "pink", label: "Rosa", regex: /\b(rosa|pink|fucsia|magenta)\b/i, matchRegex: /\b(rosa|pink|fucsia|magenta|rose|berry)\b/i, sqlTokens: ["rosa", "pink", "fucsia", "magenta", "rose", "berry"] },
  { key: "orange", label: "Arancione", regex: /\b(arancion[ei]|orange)\b/i, matchRegex: /\b(arancion[ei]|orange|amber|tangerine)\b/i, sqlTokens: ["arancione", "arancioni", "orange", "amber", "tangerine"] },
  { key: "yellow", label: "Giallo", regex: /\b(giall[oaie]|yellow|volt|fluo)\b/i, matchRegex: /\b(giall[oaie]|yellow|volt|gold|lemon|neon)\b/i, sqlTokens: ["giallo", "gialla", "gialli", "gialle", "yellow", "volt", "gold", "lemon", "neon"] },
  { key: "brown", label: "Marrone", regex: /\b(marron[ei]|brown|beige|sabbia|tan)\b/i, matchRegex: /\b(marron[ei]|brown|beige|sand|tan|earth|khaki|orewood)\b/i, sqlTokens: ["marrone", "marroni", "brown", "beige", "sand", "tan", "earth", "orewood"] },
  { key: "purple", label: "Viola", regex: /\b(viola|purple|lilla|violet)\b/i, matchRegex: /\b(viola|purple|violet|lilac|plum|iris)\b/i, sqlTokens: ["viola", "purple", "violet", "lilac", "plum", "iris"] },
];

function detectColorConstraint(q: string): ColorConstraint | null {
  const low = q.toLowerCase();
  for (const c of COLOR_MAP) {
    if (c.regex.test(low)) return { key: c.key, label: c.label, matchRegex: c.matchRegex, sqlTokens: c.sqlTokens };
  }
  return null;
}

function getColorByKey(key: string | null | undefined): ColorConstraint | null {
  if (!key) return null;
  const k = key.trim().toLowerCase();
  const found = COLOR_MAP.find((c) => c.key === k || c.label.toLowerCase() === k);
  return found ? { key: found.key, label: found.label, matchRegex: found.matchRegex, sqlTokens: found.sqlTokens } : null;
}

function coercePositiveNumber(val: unknown): number | null {
  if (typeof val === "number" && Number.isFinite(val) && val > 0) return val;
  if (typeof val === "string") {
    const cleaned = val.replace(/[€$\s]/g, "").replace(",", ".").trim();
    if (!cleaned) return null;
    const n = Number(cleaned);
    if (Number.isFinite(n) && n > 0) return n;
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
  if (/\b(mostram|cerca|trovam|fammi\s+vedere|solo\s+|filtra|alternative|altri\s+modelli|mia\s+taglia|taglia\s+\S|sotto\s*(?:i|ai|gli)?\s*€?\s*\d|meno\s+di\s*€?\s*\d|fino\s+a\s*€?\s*\d|su\s+(?:cisalfa|decathlon|alltricks|deporvillage|mister\s*running|top4running|maxisport))\b/i.test(low)) {
    return false;
  }
  if (isFollowUp) {
    return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?|vanno|funzion(?:a|ano)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?|costa(?:no)?)|qual\s+[eè]\s+(?:il\s+(?:drop|peso)|la\s+pi[uù]\s+\w+|il\s+pi[uù]\s+\w+|la\s+miglior|il\s+miglior|la\s+differenza)|quale\s+(?:mi\s+consigli|conviene|tiene\s+pi[uù]|sceglieresti|[eè]\s+meglio)|vanno\s+bene\s+per|va\s+bene\s+per|sono\s+(?:comode?|buone?|adatte?|impermeabili?|neutre?|traspiranti?|calde?)|hanno\s+(?:le\s+tasche|la\s+piastra|il\s+liner|il\s+boxer)|che\s+differenza\s+c['’][eè]|differenza\s+tra)/i.test(low) ||
      (low.endsWith("?") && /\b(calza(?:no|re)?|vest(?:e|ono|ire)?|drop|peso|dura(?:no)?|tasche|pronat|supinat|mezza\s+maratona|maratona|palestra|pioggia|comfort|comodi|comode|differenza|traspirant|pi[uù]\s+legger|pi[uù]\s+cald|tra\s+quest[aeio])\b/i.test(low));
  }
  return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?)|qual\s+[eè]\s+il\s+(?:drop|peso)|vanno\s+bene\s+per)\b/i.test(low);
}

interface ParsedLocalConstraints {
  normalizedQuery: string;
  max_price: number | null;
  min_price: number | null;
  size: string | null;
  asksMySize: boolean;
  gender: string | null;
  color: ColorConstraint | null;
  store: { id: string; label: string } | null;
  excluded_brands: string[];
  excluded_stores: Array<{ id: string; label: string }>;
  excluded_features: string[];
  sort_by: SortByMode | null;
  free_shipping: boolean;
  on_sale: boolean;
  min_discount: number | null;
  features: string[];
  resetPrice: boolean;
  resetSize: boolean;
  resetGender: boolean;
  resetColor: boolean;
  resetStore: boolean;
  resetBrand: boolean;
  resetFreeShipping: boolean;
  resetOnSale: boolean;
  resetExclusions: boolean;
  resetSort: boolean;
  resetAllFilters: boolean;
}

function extractExcludedFeaturesFromText(low: string): string[] {
  const ex: string[] = [];
  if (/\b(?:senza|no|non)\s+(?:la\s+|una\s+|con\s+)?(?:piastra(?:\s+(?:in|di)\s+carbonio)?|carbonio|carbon(?:\s*plate)?)\b/.test(low)) {
    ex.push("no_carbon");
  }
  if (/\b(?:non|senza)\s+(?:essere\s+)?(?:impermeabil[ei]|gtx|gore[\s-]*tex|waterproof)\b/.test(low)) {
    ex.push("no_waterproof");
  }
  if (/\b(?:senza|no|non)\s+(?:il\s+)?(?:cappuccio|hood|hoodie)\b/.test(low)) {
    ex.push("no_hood");
  }
  return ex;
}

function extractFeaturesFromText(low: string, excludedFeats: string[]): string[] {
  const ex = new Set(excludedFeats);
  const feats: string[] = [];
  if (!ex.has("no_waterproof") && /\b(impermeabil[ei]|gtx|gore[\s-]*tex|waterproof|antipioggia|pioggia)\b/.test(low)) feats.push("waterproof");
  if (/\b(half[\s-]*zip|mezza[\s-]*zip|1\/[24]\s*zip|quarter[\s-]*zip)\b/.test(low)) feats.push("half_zip");
  if (/\b(termic[aohe]+|invern[aoei]+|warm|merino|freddo|coldgear|therma[\s-]*fit|fleece|pile)\b/.test(low)) feats.push("thermal");
  if (/\b(ammortizzat[aoei]*|max\s*cushion|morbide?|ginocch|schiena)\b/.test(low)) feats.push("cushioned");
  if (!ex.has("no_carbon") && /\b(carbonio|carbon|piastra)\b/.test(low)) feats.push("carbon");
  if (/\b(tasc[ah]e?|pocket|speedpocket|2[\s-]*in[\s-]*1|2in1)\b/.test(low)) feats.push("pockets");
  if (/\b(trail|sterrato|montagna|sentier[oi])\b/.test(low)) feats.push("trail");
  if (/\b(running|corsa|correre|maratona|mezza\s*maratona)\b/.test(low)) feats.push("running");
  if (/\b(hyrox|crossfit|funzional[ei])\b/.test(low)) feats.push("hyrox");
  if (/\b(compression[ei]?)\b/.test(low)) feats.push("compression");
  return feats;
}

function parseLocalConstraints(q: string): ParsedLocalConstraints {
  const norm = normalizeQueryTypos(q);
  const low = norm.toLowerCase();

  // Non-currency unit guard so "sotto i 250g", "sopra 85 kg", "drop sotto 8 mm", "almeno 30%" are NEVER parsed as prices!
  const NON_PRICE_UNIT_RE = /^\s*(?:kg|chili|chilo|g\b|gr\b|grammi|km|m\b|metri|mm|cm|ore|ora|minuti|min\b|sec|giorni|mesi|anni|%|settiman|watt|bpm|volte|stelle|drop)/i;
  const CURRENCY_HINT_RE = /(?:€|euro|eur|prezzo|budget|spesa|spendere|cost[aio])/i;

  // 1. Price range: "tra 100 e 180 euro", "da €100 a €150", "100-150€"
  const rangeMatchA = low.match(/\b(?:tra|da)\s*(?:i|gli)?\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?\s*(?:e|a|-|–)\s*(?:i|gli)?\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?(?:\b|(?=\s|$|[?!.,]))/i);
  const rangeMatchB = low.match(/(?<![\d.,])\b(?:€\s*)?(\d+(?:[.,]\d+)?)\s*[-–]\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)(?:\b|(?=\s|$|[?!.,]))/i) ??
    low.match(/(?:€\s*)(\d+(?:[.,]\d+)?)\s*[-–]\s*(?:€\s*)?(\d+(?:[.,]\d+)?)(?:\b|(?=\s|$|[?!.,]))/i);
  const rawRangeMatch = rangeMatchA ?? rangeMatchB;
  let rangeMatch: RegExpMatchArray | null = null;
  if (rawRangeMatch && rawRangeMatch.index != null) {
    const afterRange = low.slice(rawRangeMatch.index + rawRangeMatch[0].length);
    const aVal = Number(rawRangeMatch[1].replace(",", "."));
    const bVal = Number(rawRangeMatch[2].replace(",", "."));
    const hasCurr = CURRENCY_HINT_RE.test(rawRangeMatch[0]) || CURRENCY_HINT_RE.test(low);
    if (!NON_PRICE_UNIT_RE.test(afterRange) && (hasCurr || (aVal >= 15 && bVal >= 15))) {
      rangeMatch = rawRangeMatch;
    }
  }

  // 2. Max price: handles ALL Italian & English phrasings AND € before or after number!
  const maxPricePatterns: RegExp[] = [
    /(?:al\s+di\s+sotto\s*(?:di|dei|degli)?|sotto\s*(?:i|ai|gli|le|di|dei)?|a\s+meno\s+di|meno\s*di|non\s+(?:oltre|pi[uù]\s*di)|fino\s*a(?:i|gli|lle)?|entro\s*(?:i|ai|gli)?|(?:prezzo|budget)\s*(?:al\s+)?(?:massimo|max)\s*(?:di)?|budget\s*(?:di)?|al\s+massimo|massimo|max|under|below|<=|<)\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?/i,
    /\bda\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?\s*in\s*gi[uù]\b/i,
  ];
  let maxPriceMatch: RegExpMatchArray | null = null;
  for (const re of maxPricePatterns) {
    const m = low.match(re);
    if (m && m.index != null) {
      const after = low.slice(m.index + m[0].length);
      const val = Number(m[1].replace(",", "."));
      const hasCurr = CURRENCY_HINT_RE.test(m[0]) || CURRENCY_HINT_RE.test(low);
      if (!NON_PRICE_UNIT_RE.test(after) && (hasCurr || val >= 15)) {
        maxPriceMatch = m;
        break;
      }
    }
  }

  // 3. Min price (guard against "non più di", non-currency units, and percentage discounts like "almeno 30%")
  const lowWithoutNegMax = low.replace(/\bnon\s+(?:oltre|pi[uù]\s*di)\s*(?:€\s*)?\d+(?:[.,]\d+)?/gi, " ");
  const minPricePatterns: RegExp[] = [
    /(?:al\s+di\s+sopra\s*(?:di|dei|degli)?|sopra\s*(?:i|ai|gli|le|di|dei)?|oltre\s*(?:i|ai|gli|le)?|pi[uù]\s*di|(?:prezzo\s*)?(?:minimo|min)\s*(?:di)?|almeno|over|above|>=|>)\s*(?:€\s*)?(\d+(?:[.,]\d+)?)(?!\s*%)\s*(?:€|euro|eur)?/i,
    /\bda\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?\s*in\s*su\b/i,
  ];
  let minPriceMatch: RegExpMatchArray | null = null;
  for (const re of minPricePatterns) {
    const m = lowWithoutNegMax.match(re);
    if (m && m.index != null) {
      const after = lowWithoutNegMax.slice(m.index + m[0].length);
      const val = Number(m[1].replace(",", "."));
      const hasCurr = CURRENCY_HINT_RE.test(m[0]) || CURRENCY_HINT_RE.test(lowWithoutNegMax);
      if (!NON_PRICE_UNIT_RE.test(after) && (hasCurr || val >= 15)) {
        minPriceMatch = m;
        break;
      }
    }
  }

  // 4. Size (explicit prefix or decimal shoe size, including fractions like "42 2/3")
  const explicitSizeMatch = low.match(/\b(?:tagli[ae]|numero|num\.?|n\.?|misur[ae]|size|tg\.?|eu)\s*(\d{2}(?:[.,]\d|\s+[12]\/[23])?|(?:xxs|xs|s|m|l|xl|xxl|2xl|3xl))\b/i);
  const decimalShoeSizeMatch = low.match(/(?<![\d.,])\b(3[5-9]|4[0-9])[.,](5)\b(?![\d.,])/);
  const asksMySize = /\b(la\s+mia\s+taglia|nella\s+mia\s+taglia|mia\s+taglia)\b/i.test(low);

  // 5. Gender
  let gender: string | null = null;
  if (/\b(unisex|tutti\s+i\s+generi|uomo\s+e\s+donna|sia\s+uomo\s+che\s+donna|qualsiasi\s+genere)\b/i.test(low)) gender = "Unisex";
  else if (/\b(donna|donne|femmin[aei]|ragazza|wmns?|women|woman)\b/i.test(low)) gender = "Donna";
  else if (/\b(uomo|uomini|maschil[ei]|ragazzo|mens?|men|man)\b/i.test(low)) gender = "Uomo";

  // 6. Color, Store, Exclusions, Sorting, Shipping, Discounts
  const color = detectColorConstraint(norm);
  const store = extractStoreFilter(norm);
  const excludedBrands = extractExcludedBrands(norm);
  const excludedStores = extractExcludedStores(norm);
  const excludedFeatures = extractExcludedFeaturesFromText(low);

  let sortBy: SortByMode | null = null;
  if (/\b(pi[uù]\s+(?:economic[hoaie]+|convenient[ei]|a\s+buon\s+mercato)|prezz[oi]\s+(?:pi[uù]\s+)?bass[oi]|dal\s+meno\s+caro|ordina(?:t[aeio])?\s+per\s+prezzo(?:\s+crescente)?|meno\s+costos[aeio]|cheapest|lowest\s+price)\b/i.test(low)) {
    sortBy = "price_asc";
  } else if (/\b(pi[uù]\s+(?:costos[aeio]|car[aeio])|prezz[oi]\s+(?:pi[uù]\s+)?alt[oi]|prezzo\s+decrescente|dal\s+pi[uù]\s+caro)\b/i.test(low)) {
    sortBy = "price_desc";
  } else if (/\b(scont[oi]\s+(?:pi[uù]\s+)?alt[oi]|maggior[ie]?\s+scont[oi]|pi[uù]\s+scontat[aeio]|ordina(?:t[aeio])?\s+per\s+sconto|miglior[ie]\s+scont[oi]|biggest\s+discount)\b/i.test(low)) {
    sortBy = "discount_desc";
  }

  const freeShipping = /\b(spedizione\s+(?:gratuita|gratis)|senza\s+spese\s+di\s+spedizione|free\s+shipping)\b/i.test(low);
  const discPctMatch = low.match(/(?:sconto\s*(?:almeno|minimo|di|del)?\s*|almeno\s+|-)(\d{1,2})\s*%/i);
  const minDiscount = discPctMatch ? Number(discPctMatch[1]) : null;
  const onSale = Boolean(
    (minDiscount != null && minDiscount > 0) ||
    sortBy === "discount_desc" ||
    /\b(in\s+sconto|scontat[aeio]|in\s+offerta|in\s+saldo|saldi|con\s+sconto|miglior[ie]\s+scont[oi]|solo\s+scont[oi]|solo\s+offert[ae])\b/i.test(low),
  );

  // 7. Explicit filter resets (also triggered when tapping ✕ on filter chips in iOS!)
  const resetAllFilters = /\b(rimuovi\s+tutti\s+i\s+filtri|azzera\s+(?:tutti\s+i\s+)?filtri|senza\s+filtri)\b/i.test(low);
  const resetPrice = resetAllFilters || /\b(rimuovi\s+(?:il\s+)?(?:limit[ei]|filtro)\s+(?:di\s+)?(?:prezzo|budget)|rimuovi\s+(?:il\s+)?(?:budget|prezzo)|senza\s+limit[ei]\s+di\s+(?:prezzo|budget)|senza\s+budget|qualsiasi\s+(?:prezzo|budget)|tutti\s+i\s+prezzi|togli\s+(?:il\s+)?(?:limit[ei]|filtro)\s+(?:di\s+)?(?:prezzo|budget))\b/i.test(low);
  const resetSize = resetAllFilters || /\b(tutte\s+le\s+taglie|qualsiasi\s+taglia|rimuovi\s+(?:il\s+)?filtro\s+taglia|togli\s+(?:la\s+)?taglia|senza\s+filtro\s+taglia)\b/i.test(low);
  const resetGender = resetAllFilters || gender === "Unisex";
  const resetColor = resetAllFilters || /\b(tutti\s+i\s+colori|qualsiasi\s+colore|di\s+ogni\s+colore)\b/i.test(low);
  const resetStore = resetAllFilters || /\b(tutti\s+gli\s+store|tutti\s+i\s+negozi|ovunque)\b/i.test(low);
  const resetBrand = resetAllFilters || /\b(tutti\s+i\s+brand|tutte\s+le\s+marche|altri\s+brand|altre\s+marche)\b/i.test(low);
  const resetFreeShipping = resetAllFilters || /\b(rimuovi\s+(?:il\s+)?filtro\s+spedizione|includi\s+spedizione\s+a\s+pagamento|qualsiasi\s+spedizione)\b/i.test(low);
  const resetOnSale = resetAllFilters || /\b(rimuovi\s+(?:il\s+)?filtro\s+scont[oi]|anche\s+non\s+scontat[aeio]|tutti\s+i\s+prodotti\s+anche\s+non\s+scontati)\b/i.test(low);
  const resetExclusions = resetAllFilters || /\b(rimuovi\s+(?:le\s+)?esclusion[ei]|includi\s+tutti\s+i\s+brand|senza\s+esclusioni)\b/i.test(low);
  const resetSort = resetAllFilters || /\b(ordine\s+consigliato|rimuovi\s+ordinamento|ordina\s+per\s+rilevanza)\b/i.test(low);

  let maxPrice: number | null = null;
  let minPrice: number | null = null;
  if (!resetPrice) {
    if (rangeMatch) {
      const a = Number(rangeMatch[1].replace(",", "."));
      const b = Number(rangeMatch[2].replace(",", "."));
      if (Number.isFinite(a) && Number.isFinite(b) && a > 0 && b > 0) {
        minPrice = Math.min(a, b);
        maxPrice = Math.max(a, b);
      }
    } else {
      if (maxPriceMatch) maxPrice = Number(maxPriceMatch[1].replace(",", "."));
      if (minPriceMatch) minPrice = Number(minPriceMatch[1].replace(",", "."));
    }
  }

  let size: string | null = null;
  if (!resetSize) {
    if (explicitSizeMatch) {
      size = explicitSizeMatch[1].replace(",", ".").replace(/\s+[12]\/[23]$/, ".5").toUpperCase();
    } else if (decimalShoeSizeMatch) {
      size = `${decimalShoeSizeMatch[1]}.${decimalShoeSizeMatch[2]}`;
    }
  }

  return {
    normalizedQuery: norm,
    max_price: maxPrice != null && Number.isFinite(maxPrice) && maxPrice > 0 ? maxPrice : null,
    min_price: minPrice != null && Number.isFinite(minPrice) && minPrice > 0 ? minPrice : null,
    size,
    asksMySize,
    gender,
    color: resetColor ? null : color,
    store: resetStore ? null : store,
    excluded_brands: resetExclusions ? [] : excludedBrands,
    excluded_stores: resetExclusions ? [] : excludedStores,
    excluded_features: resetExclusions ? [] : excludedFeatures,
    sort_by: resetSort ? null : sortBy,
    free_shipping: resetFreeShipping ? false : freeShipping,
    on_sale: resetOnSale ? false : onSale,
    min_discount: resetOnSale ? null : (minDiscount != null && Number.isFinite(minDiscount) ? minDiscount : null),
    features: extractFeaturesFromText(low, excludedFeatures),
    resetPrice,
    resetSize,
    resetGender,
    resetColor,
    resetStore,
    resetBrand,
    resetFreeShipping,
    resetOnSale,
    resetExclusions,
    resetSort,
    resetAllFilters,
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
    const clean = items.filter((p) => !usedIds.has(p.id)).slice(0, 14);
    if (clean.length === 0) return;
    for (const p of clean) usedIds.add(p.id);
    sections.push({ id, title, subtitle, products: clean });
  };

  const primaryItems = results.filter((p) => roleById[p.id] === "primary");
  const secondaryItems = results.filter((p) => roleById[p.id] !== "primary");

  if (productType === "long_sleeve_top") {
    const isFleece = (p: MatchedProductOut) =>
      /\b(therma|fleece|felpa|hoodie|pile\b|polar\b|wolf\s*grid|wolf\s*tree|wolf\s*lichen|tuff\s*fleece|girocollo|crewneck)\b/i.test(`${p.canonical_name} ${p.offers[0]?.title ?? ""}`);
    const isTrueLs = (p: MatchedProductOut) =>
      /\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)|l\/s\b|\bls\b|radical\s*airflow\s*nxt|base[\s-]*layer|strato\s*base)\b/i.test(`${p.canonical_name} ${p.offers[0]?.title ?? ""} ${p.offers[0]?.url ?? ""}`) && !isFleece(p);
    const isZip = (p: MatchedProductOut) =>
      /\b(half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip|1\s*[\/\s]\s*[24][\s-]*(?:di\s+)?zip|zip\s*(?:a\s*)?1\s*[\/\s]\s*[24]|zip\s*(?:a\s*)?met[aà]\s*lunghezza|top\s*zip)\b/i.test(`${p.canonical_name} ${p.offers[0]?.title ?? ""}`);

    const trueLongSleeves = results.filter((p) => isTrueLs(p));
    const zipTechnical = results.filter((p) => !trueLongSleeves.includes(p) && isZip(p));
    const warmFleece = results.filter((p) => !trueLongSleeves.includes(p) && !zipTechnical.includes(p));

    if (trueLongSleeves.length > 0) {
      addSection("sec_true_ls", `${brand ? brand + " " : ""}Maglie a manica lunga`.trim(), "Long sleeve tecniche e t-shirt a manica lunga", trueLongSleeves);
    }
    if (zipTechnical.length > 0) {
      addSection("sec_zip_tech", "Half-zip e strati tecnici", "Ventilazione regolabile per trail, corsa e outdoor", zipTechnical);
    }
    if (warmFleece.length > 0) {
      addSection("sec_warm", "Felpe, pile e strati caldi", "Fleece, Therma-FIT e strati termici per clima fresco", warmFleece);
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
      results.slice(0, 14),
    );
  }

  // Ensure ALL remaining relevant products are reachable in a section
  const leftovers = results.filter((p) => !usedIds.has(p.id));
  if (leftovers.length > 0) {
    if (sections.length < 3 && leftovers.length >= 2) {
      addSection("sec_more", "Altre opzioni da valutare", "Modelli aggiuntivi compatibili con la tua ricerca", leftovers);
    } else if (sections.length > 0) {
      const lastSec = sections[sections.length - 1];
      for (const p of leftovers) {
        if (lastSec.products.length < 16) {
          lastSec.products.push(p);
          usedIds.add(p.id);
        }
      }
    }
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
  excluded_brands: string[];
  category: string | null;
  gender: string | null;
  max_price: number | null;
  min_price: number | null;
  size: string | null;
  color: string | null;
  store: string | null;
  excluded_stores: Array<{ id: string; label: string }>;
  excluded_features: string[];
  sort_by: SortByMode | null;
  free_shipping: boolean;
  on_sale: boolean;
  min_discount: number | null;
}) {
  const chips: Array<{ id: string; label: string; param_key: string; value: string }> = [];
  if (intent.brand) chips.push({ id: "chip_brand", label: intent.brand, param_key: "brand", value: intent.brand });
  for (const eb of intent.excluded_brands) {
    chips.push({ id: `chip_ex_brand_${eb.toLowerCase()}`, label: `Escluso: ${eb}`, param_key: "excluded_brand", value: eb });
  }
  if (intent.gender && intent.gender !== "Unisex") {
    chips.push({ id: "chip_gender", label: intent.gender, param_key: "gender", value: intent.gender });
  }
  if (intent.size) chips.push({ id: "chip_size", label: `Taglia ${intent.size}`, param_key: "size", value: intent.size });
  if (intent.color) chips.push({ id: "chip_color", label: intent.color, param_key: "color", value: intent.color });
  if (intent.min_price != null && intent.max_price != null) {
    chips.push({
      id: "chip_price_range",
      label: `€${Math.round(intent.min_price)} – €${Math.round(intent.max_price)}`,
      param_key: "max_price",
      value: String(intent.max_price),
    });
  } else if (intent.max_price != null) {
    chips.push({ id: "chip_price", label: `Sotto €${Math.round(intent.max_price)}`, param_key: "max_price", value: String(intent.max_price) });
  } else if (intent.min_price != null) {
    chips.push({ id: "chip_min_price", label: `Oltre €${Math.round(intent.min_price)}`, param_key: "min_price", value: String(intent.min_price) });
  }
  if (intent.store) {
    const storeMeta = KNOWN_STORES.find((s) => s.id === intent.store || s.label.toLowerCase() === intent.store!.toLowerCase());
    chips.push({ id: "chip_store", label: storeMeta?.label ?? intent.store, param_key: "store", value: intent.store });
  }
  for (const es of intent.excluded_stores) {
    chips.push({ id: `chip_ex_store_${es.id}`, label: `Escluso: ${es.label}`, param_key: "excluded_store", value: es.id });
  }
  for (const ef of intent.excluded_features) {
    const lbl = ef === "no_carbon" ? "Senza carbonio" : ef === "no_waterproof" ? "Non impermeabile" : ef === "no_hood" ? "Senza cappuccio" : ef;
    chips.push({ id: `chip_ex_feat_${ef}`, label: lbl, param_key: "excluded_feature", value: ef });
  }
  if (intent.min_discount != null && intent.min_discount > 0) {
    chips.push({ id: "chip_discount", label: `Sconto ≥${Math.round(intent.min_discount)}%`, param_key: "min_discount", value: String(intent.min_discount) });
  } else if (intent.on_sale) {
    chips.push({ id: "chip_sale", label: "In sconto", param_key: "on_sale", value: "true" });
  }
  if (intent.free_shipping) {
    chips.push({ id: "chip_shipping", label: "Spedizione gratuita", param_key: "free_shipping", value: "true" });
  }
  if (intent.sort_by === "price_asc") {
    chips.push({ id: "chip_sort", label: "Prezzo crescente", param_key: "sort_by", value: "price_asc" });
  } else if (intent.sort_by === "price_desc") {
    chips.push({ id: "chip_sort", label: "Prezzo decrescente", param_key: "sort_by", value: "price_desc" });
  } else if (intent.sort_by === "discount_desc") {
    chips.push({ id: "chip_sort", label: "Sconto più alto", param_key: "sort_by", value: "discount_desc" });
  }
  return chips;
}

interface ReplayedContext {
  subjectQuery: string | null;
  productType: ProductType | null;
  brand: string | null;
  excludedBrands: string[];
  subBrand: [string, string] | null;
  entityTokens: string[];
  maxPrice: number | null;
  minPrice: number | null;
  size: string | null;
  gender: string | null;
  color: ColorConstraint | null;
  store: { id: string; label: string } | null;
  excludedStores: Array<{ id: string; label: string }>;
  excludedFeatures: string[];
  sortBy: SortByMode | null;
  freeShipping: boolean;
  onSale: boolean;
  minDiscount: number | null;
  features: string[];
  lastKeywords: string[];
}

/**
 * Deterministically reconstructs complete multi-turn conversation state from BOTH
 * persisted DB `context_state` + `chat_messages` AND the `context_query` chain ("t0 >> t1 >> t2").
 * This guarantees follow-ups NEVER lose brand, model, subject, or filters even if session_id
 * wasn't persisted yet or after a client cache hit / session restore!
 */
function reconstructPriorContext(opts: {
  prevContext: Record<string, unknown> | null;
  contextQuery: string | null;
  recentTurns: Array<{ query: string }>;
  preferredSize: string | null;
}): ReplayedContext {
  const res: ReplayedContext = {
    subjectQuery: null,
    productType: null,
    brand: null,
    excludedBrands: [],
    subBrand: null,
    entityTokens: [],
    maxPrice: null,
    minPrice: null,
    size: null,
    gender: null,
    color: null,
    store: null,
    excludedStores: [],
    excludedFeatures: [],
    sortBy: null,
    freeShipping: false,
    onSale: false,
    minDiscount: null,
    features: [],
    lastKeywords: [],
  };

  // Build ordered list of prior user utterances (prefer DB recentTurns if longer/richer, else contextQuery split on ">>")
  const ctxParts = (opts.contextQuery ?? "")
    .split(">>")
    .map((s) => s.trim())
    .filter(Boolean);
  const dbTurns = opts.recentTurns.map((t) => t.query.trim()).filter(Boolean);
  const orderedTurns = dbTurns.length >= ctxParts.length ? dbTurns : ctxParts;

  for (const turnText of orderedTurns) {
    const parsed = parseLocalConstraints(turnText);
    const norm = parsed.normalizedQuery;
    const explicitPt = detectExplicitProductType(norm);
    const singlePt = detectSingleProductType(norm);
    const sameGroupRefine = Boolean(
      !explicitPt && singlePt && res.productType &&
      normalizeProductTypeGroup(singlePt) === normalizeProductTypeGroup(res.productType),
    );
    const inferredPt = explicitPt ?? (sameGroupRefine || !res.productType ? singlePt : null);

    const switched = Boolean(
      explicitPt && res.productType &&
      normalizeProductTypeGroup(explicitPt) !== normalizeProductTypeGroup(res.productType),
    );
    if (switched) {
      res.brand = null;
      res.excludedBrands = [];
      res.subBrand = null;
      res.entityTokens = [];
      res.maxPrice = null;
      res.minPrice = null;
      res.size = null;
      res.gender = null;
      res.color = null;
      res.store = null;
      res.excludedStores = [];
      res.excludedFeatures = [];
      res.sortBy = null;
      res.freeShipping = false;
      res.onSale = false;
      res.minDiscount = null;
      res.features = [];
      res.subjectQuery = norm;
    }

    if (explicitPt) res.productType = explicitPt;
    else if (inferredPt && (sameGroupRefine || !res.productType)) res.productType = inferredPt;

    const tBrand = extractBrand(norm, null);
    const tSub = detectSubBrand(norm);
    const tEnts = extractSpecificEntityTokens(norm, tBrand);
    const tBroaden = isBroadeningFollowUp(norm);

    if (parsed.resetBrand || tBroaden) {
      if (parsed.resetBrand) res.brand = null;
      if (tBroaden) {
        res.entityTokens = [];
        res.subBrand = null;
      }
    }
    if (tBrand) {
      if (res.brand && res.brand.toLowerCase() !== tBrand.toLowerCase()) {
        res.entityTokens = [];
        res.subBrand = null;
      }
      res.brand = tBrand;
    }
    if (tSub) {
      res.subBrand = tSub;
      if (!res.brand) res.brand = tSub[0];
    }
    if (tEnts.length > 0 && !tBroaden) {
      res.entityTokens = tEnts;
    }

    // Update subjectQuery ONLY when the turn carries actual product/category/model intent (not pure filter/activity turns like "Uomo", "Sotto 100 euro", "Da corsa")
    const hasSubjectContent = Boolean(explicitPt || (!res.productType && inferredPt) || tEnts.length > 0 || (tBrand && !res.subjectQuery));
    if (hasSubjectContent && !isPureAdviceQuestion(norm, Boolean(res.subjectQuery))) {
      res.subjectQuery = norm;
    } else if (!res.subjectQuery) {
      res.subjectQuery = norm;
    }

    if (parsed.resetPrice) {
      res.maxPrice = null;
      res.minPrice = null;
    } else {
      if (parsed.max_price != null) res.maxPrice = parsed.max_price;
      if (parsed.min_price != null) res.minPrice = parsed.min_price;
    }
    if (parsed.resetSize) res.size = null;
    else if (parsed.size) res.size = parsed.size;
    else if (parsed.asksMySize && opts.preferredSize) res.size = opts.preferredSize;

    if (parsed.resetGender) res.gender = null;
    else if (parsed.gender && parsed.gender !== "Unisex") res.gender = parsed.gender;

    if (parsed.resetColor) res.color = null;
    else if (parsed.color) res.color = parsed.color;

    if (parsed.resetStore) res.store = null;
    else if (parsed.store) res.store = parsed.store;

    if (parsed.resetFreeShipping) res.freeShipping = false;
    else if (parsed.free_shipping) res.freeShipping = true;

    if (parsed.resetOnSale) {
      res.onSale = false;
      res.minDiscount = null;
    } else {
      if (parsed.on_sale) res.onSale = true;
      if (parsed.min_discount != null) res.minDiscount = parsed.min_discount;
    }

    if (parsed.resetExclusions) {
      res.excludedBrands = [];
      res.excludedStores = [];
      res.excludedFeatures = [];
    } else {
      for (const eb of parsed.excluded_brands) {
        if (!res.excludedBrands.includes(eb)) res.excludedBrands.push(eb);
        if (res.brand && res.brand.toLowerCase() === eb.toLowerCase()) res.brand = null;
      }
      for (const es of parsed.excluded_stores) {
        if (!res.excludedStores.some((x) => x.id === es.id)) res.excludedStores.push(es);
        if (res.store && res.store.id === es.id) res.store = null;
      }
      for (const ef of parsed.excluded_features) {
        if (!res.excludedFeatures.includes(ef)) res.excludedFeatures.push(ef);
      }
    }

    if (parsed.resetSort) res.sortBy = null;
    else if (parsed.sort_by) res.sortBy = parsed.sort_by;

    if (parsed.resetAllFilters) {
      res.freeShipping = false;
      res.onSale = false;
      res.minDiscount = null;
      res.excludedBrands = [];
      res.excludedStores = [];
      res.excludedFeatures = [];
      res.sortBy = null;
    }
    for (const f of parsed.features) {
      if (!res.features.includes(f)) res.features.push(f);
    }
  }

  // Overlay structured DB context_state where available (preserves LLM-resolved state from prior turn)
  const pc = opts.prevContext;
  if (pc) {
    if (typeof pc.subject_query === "string" && pc.subject_query.trim()) {
      res.subjectQuery = pc.subject_query.trim();
    }
    if (typeof pc.product_type === "string" && VALID_PRODUCT_TYPES.has(pc.product_type as ProductType)) {
      res.productType = pc.product_type as ProductType;
    }
    if (typeof pc.brand === "string" && pc.brand.trim() && !res.brand) {
      res.brand = pc.brand.trim();
    }
    if (Array.isArray(pc.excluded_brands) && res.excludedBrands.length === 0) {
      res.excludedBrands = pc.excluded_brands.map(String).filter(Boolean);
    }
    if (Array.isArray(pc.entity_tokens) && pc.entity_tokens.length > 0 && res.entityTokens.length === 0) {
      res.entityTokens = pc.entity_tokens.map(String).filter(Boolean);
    }
    if (!res.subBrand && typeof pc.sub_brand === "string" && pc.sub_brand.trim()) {
      const sb = detectSubBrand(pc.sub_brand);
      if (sb) res.subBrand = sb;
    }
    if (res.maxPrice == null) res.maxPrice = coercePositiveNumber(pc.max_price);
    if (res.minPrice == null) res.minPrice = coercePositiveNumber(pc.min_price);
    if (!res.size && typeof pc.size === "string" && pc.size.trim()) res.size = pc.size.trim();
    if (!res.gender && typeof pc.gender === "string" && ["Uomo", "Donna"].includes(pc.gender)) res.gender = pc.gender;
    if (!res.color && typeof pc.color === "string") res.color = getColorByKey(pc.color);
    if (!res.store && typeof pc.store === "string" && pc.store.trim()) {
      const st = extractStoreFilter(pc.store) ?? { id: pc.store.trim().toLowerCase(), label: pc.store.trim() };
      res.store = st;
    }
    if (Array.isArray(pc.excluded_stores) && res.excludedStores.length === 0) {
      for (const sid of pc.excluded_stores.map(String).filter(Boolean)) {
        const meta = KNOWN_STORES.find((s) => s.id === sid.toLowerCase());
        res.excludedStores.push({ id: sid.toLowerCase(), label: meta?.label ?? sid });
      }
    }
    if (Array.isArray(pc.excluded_features) && res.excludedFeatures.length === 0) {
      res.excludedFeatures = pc.excluded_features.map(String).filter(Boolean);
    }
    if (!res.sortBy && typeof pc.sort_by === "string" && ["price_asc", "price_desc", "discount_desc"].includes(pc.sort_by)) {
      res.sortBy = pc.sort_by as SortByMode;
    }
    if (pc.free_shipping === true) res.freeShipping = true;
    if (pc.on_sale === true) res.onSale = true;
    if (res.minDiscount == null) res.minDiscount = coercePositiveNumber(pc.min_discount);
    if (Array.isArray(pc.features)) {
      for (const f of pc.features.map(String).filter(Boolean)) {
        if (!res.features.includes(f)) res.features.push(f);
      }
    }
    if (Array.isArray(pc.last_keywords)) {
      res.lastKeywords = pc.last_keywords.map(String).filter(Boolean);
    }
  }

  return res;
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
  let loadMore = url.searchParams.get("load_more") === "1";
  let excludeIds: string[] = [];
  let clientContextState: Record<string, unknown> | null = null;
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
    if (body?.load_more === true || body?.load_more === "1") loadMore = true;
    if (Array.isArray(body?.exclude_ids)) {
      excludeIds = body.exclude_ids.map((x: unknown) => String(x ?? "").trim()).filter(Boolean).slice(0, 300);
    }
    if (body?.context_state && typeof body.context_state === "object" && !Array.isArray(body.context_state)) {
      clientContextState = body.context_state as Record<string, unknown>;
    }
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
      !loadMore &&
      excludeIds.length === 0 &&
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

    // Load full prior session history (context_state + last 5 turns + lastShownProducts)
    const historyCtx = await loadChatHistoryContext(supabase, sessionId);
    const prevContext = historyCtx.contextState ?? clientContextState;

    const local = parseLocalConstraints(q);
    const normalizedQ = local.normalizedQuery;
    const effectivePreferredSize = preferredSize && preferredSize.trim() ? preferredSize.trim() : null;
    const isFollowUp = Boolean(
      (contextQuery && contextQuery.trim()) ||
      (prevContext && Object.keys(prevContext).length > 0) ||
      historyCtx.recentTurns.length > 0,
    );
    const prior = isFollowUp
      ? reconstructPriorContext({
          prevContext,
          contextQuery,
          recentTurns: historyCtx.recentTurns,
          preferredSize: effectivePreferredSize,
        })
      : {
          subjectQuery: null,
          productType: null,
          brand: null,
          excludedBrands: [] as string[],
          subBrand: null,
          entityTokens: [] as string[],
          maxPrice: null,
          minPrice: null,
          size: null,
          gender: null,
          color: null,
          store: null,
          excludedStores: [] as Array<{ id: string; label: string }>,
          excludedFeatures: [] as string[],
          sortBy: null as SortByMode | null,
          freeShipping: false,
          onSale: false,
          minDiscount: null,
          features: [] as string[],
          lastKeywords: [] as string[],
        };

    const pureQuestion = isPureAdviceQuestion(normalizedQ, isFollowUp);

    // Deterministic analysis of current query & follow-up transition
    const currentBrand = extractBrand(normalizedQ, null);
    const currentSubBrand = detectSubBrand(normalizedQ);
    const currentExplicitPType = detectExplicitProductType(normalizedQ);
    const currentSinglePType = detectSingleProductType(normalizedQ);
    const prevPTypeRaw = prior.productType;

    // ONLY switch category when the current turn mentions an EXPLICIT product noun/model
    // from a different group (e.g. "fascia cardio" after "scarpe trail", or "pantaloncini" after "long sleeve").
    // Activity-only refinements like "Da corsa" or "Per trail" after "Long sleeve ACG" NEVER wipe the garment!
    const categorySwitched = Boolean(
      currentExplicitPType && prevPTypeRaw &&
      normalizeProductTypeGroup(currentExplicitPType) !== normalizeProductTypeGroup(prevPTypeRaw),
    );
    const sameGroupPTypeRefinement = Boolean(
      !currentExplicitPType && currentSinglePType && prevPTypeRaw &&
      normalizeProductTypeGroup(currentSinglePType) === normalizeProductTypeGroup(prevPTypeRaw),
    );
    const broadeningFollowUp = isFollowUp && (isBroadeningFollowUp(normalizedQ) || local.resetBrand);

    const currentEntities = extractSpecificEntityTokens(normalizedQ, currentBrand);
    const prevBrand = (!categorySwitched && !local.resetBrand) ? prior.brand : null;
    const brandSwitched = Boolean(currentBrand && prevBrand && currentBrand.toLowerCase() !== prevBrand.toLowerCase());

    const shouldInheritPrevEntities = isFollowUp &&
      currentEntities.length === 0 &&
      !categorySwitched &&
      !brandSwitched &&
      !broadeningFollowUp &&
      !local.resetBrand;

    const prevEntities = shouldInheritPrevEntities ? prior.entityTokens : [];
    const effectiveSubBrand = currentSubBrand ??
      (shouldInheritPrevEntities
        ? (prior.subBrand ?? (prior.subjectQuery ? detectSubBrand(prior.subjectQuery) : null))
        : null);

    const detProductType: ProductType | null = currentExplicitPType ??
      (sameGroupPTypeRefinement ? currentSinglePType : null) ??
      (!categorySwitched ? prevPTypeRaw : null) ??
      currentSinglePType;

    // Preserve clean subject query across pure filter/activity/Q&A follow-ups (NEVER leak ">>" or "Sotto 100 euro" as subject!)
    let effectiveSubjectQuery: string;
    if (!isFollowUp || categorySwitched) {
      effectiveSubjectQuery = normalizedQ;
    } else if (!pureQuestion && (currentExplicitPType || currentEntities.length > 0 || brandSwitched)) {
      effectiveSubjectQuery = (!currentBrand && prevBrand && !brandSwitched && currentEntities.length > 0)
        ? `${prevBrand} ${normalizedQ}`
        : normalizedQ;
    } else {
      effectiveSubjectQuery = prior.subjectQuery ?? normalizedQ;
    }

    // Build concise conversation history digest for Stage-1 Planner & Stage-2 Merchandiser
    const priorHistoryLines: string[] = [];
    if (isFollowUp && !categorySwitched) {
      const recentForPrompt = historyCtx.recentTurns.slice(-4);
      if (recentForPrompt.length > 0) {
        for (const t of recentForPrompt) {
          const prodSample = t.shown_products.slice(0, 3).map((p) =>
            p.price != null ? `${p.name} (€${Math.round(p.price)})` : p.name
          ).join(", ");
          priorHistoryLines.push(
            `- Turno ${t.turn_index + 1}: "${t.query}"${prodSample ? ` -> mostrati: ${prodSample}` : ""}`,
          );
        }
      } else if (contextQuery && contextQuery.trim()) {
        const parts = contextQuery.split(">>").map((s) => s.trim()).filter(Boolean).slice(-4);
        parts.forEach((p, i) => priorHistoryLines.push(`- Turno ${i + 1}: "${p}"`));
      }
    }
    const lastShownLines = (!categorySwitched && historyCtx.lastShownProducts.length > 0)
      ? historyCtx.lastShownProducts.slice(0, 6).map((p, i) =>
          `${i + 1}. ${p.name}${p.gender ? ` (${p.gender})` : ""}${p.price != null ? ` - €${p.price.toFixed(2)}` : ""}`
        )
      : [];

    const effectiveQueryForLLM = isFollowUp && !categorySwitched
      ? `Soggetto corrente: "${effectiveSubjectQuery}"\nNuovo messaggio utente (follow-up): "${normalizedQ}"`
      : normalizedQ;

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "openai/gpt-4o-mini";
    const plannerModels = ["google/gemini-2.5-flash-lite", "google/gemini-2.5-flash", primaryModel];
    const merchModels = ["google/gemini-2.5-flash", primaryModel, "meta-llama/llama-3.3-70b-instruct"];

    // =========================================================================
    // STAGE 1: QUERY UNDERSTANDING & MULTI-QUERY EXPANSION PLANNER
    // =========================================================================
    const plannerSystemPrompt =
      "Sei il Query Planner del motore di ricerca AI sportivo di FitMatch (stile Shopify Shop).\n" +
      "Capisci la richiesta dell'utente (e l'eventuale cronologia chat) e pianifica 2-4 sotto-ricerche mirate per interrogare il catalogo italiano/inglese.\n" +
      "REGOLE:\n" +
      "1. 'query_type': exact_model | category_brand | advisory | comparison | followup_filter | pure_question (pure_question SOLO per domande tecniche senza richiesta di cambiare/filtrare catalogo, es. 'Come calzano?', 'Qual è la più traspirante tra queste?').\n" +
      "2. 'product_type': leggings_tights, shorts, pants, long_sleeve_top, short_sleeve_top, singlet_top, top, jacket, socks, headwear, heart_rate_monitor, bike_computer, gps_watch, eyewear, hydration, swim, padel_racket, tennis_racket, football_boots, basketball_shoes, tennis_shoes, volleyball_shoes, trail_shoes, shoes, winter_sports, nutrition, smart_trainer, o null.\n" +
      "3. CONTINUITÀ FOLLOW-UP:\n" +
      "   - Se è un follow-up (es. 'Da corsa', 'Uomo', 'Sotto 100 euro', 'Solo nere', 'Rimuovi limite di prezzo'), MANTIENI sempre il soggetto, il brand, la linea (es. Nike ACG) e la categoria precedente a meno che l'utente non chieda esplicitamente un altro prodotto (es. 'E invece una fascia cardio?').\n" +
      "   - Se l'utente dice 'Da corsa' dopo 'Long sleeve ACG', resta SU MAGLIE MANICA LUNGA NIKE ACG adatte alla corsa/trail, NON cercare scarpe!\n" +
      "4. FILTRI PREZZO / BUDGET:\n" +
      "   - Il database filtra già i prezzi scontati reali in SQL! Quando c'è un budget (es. 'Nike Pegasus sotto 120€'), MAI limitare i terms a versioni vecchie (es. solo Pegasus 39/40): usa il nome linea pulito ('Nike Pegasus', 'Nike Pegasus 41', 'Nike Pegasus Plus') così troviamo tutte le offerte scontate sotto budget!\n" +
      "5. 'sub_queries' (2-4 voci): { \"label\": \"query di ricerca pulita mostrata all'utente\", \"terms\": [\"termine1\", \"termine2\"], \"role\": \"primary|variant|complementary\" }.\n" +
      "   - 'label' DEVE sembrare una vera ricerca prodotto concreta (es. 'Nike ACG manica lunga', 'Nike ACG strati caldi Therma-FIT', 'Nike Pegasus offerte sotto 120€'), MAI etichette meta come 'Specific models' o 'Alternative'!\n" +
      "   - Esempio 'Long sleeve nike acg': primary ['Nike ACG manica lunga', 'Nike ACG maniche lunghe', 'Nike ACG long sleeve', 'Nike ACG Radical AirFlow NXT'], variant ['Nike ACG Chinati', 'Nike ACG Wildsee zip', 'Nike ACG 1/4 zip', 'Nike ACG ls'], complementary ['Nike ACG Wolf Grid', 'Nike ACG Wolf Tree', 'Nike ACG Therma-FIT', 'Nike ACG Tuff Fleece'].\n" +
      "   - Esempio 'Adidas adizero dropset shoes': primary ['Adidas Adizero Dropset Pro', 'Adidas Adizero Dropset Elite'], variant ['Adidas Dropset 4', 'Adidas Dropset 4 Power'], variant ['Adidas Dropset 3', 'Adidas Dropset Control'].\n" +
      "   - Per query 'advisory' o di categoria generica con filtri (es. 'scarpe running sotto 150 euro' o 'scarpe ammortizzate 85kg'), inserisci nomi di modelli/linee reali di riferimento di BRAND DIVERSI divisi per 2-3 profili (es. ['Asics Cumulus', 'Brooks Ghost', 'Saucony Ride'], ['Hoka Clifton', 'Asics Novablast', 'Nike Pegasus']), MAI solo un singolo brand!\n" +
      "   - Per query 'comparison' (es. 'Confronta Asics Nimbus 26 vs Hoka Bondi 8'), crea una sub_query 'primary' SEPARATA per ciascun modello confrontato!\n" +
      "   - MAI inserire un nome di brand da solo nei terms!\n" +
      "6. Se query_type=='pure_question', compila SEMPRE 'direct_answer' (2-4 frasi tecniche concrete in italiano riferite ai MODELLI REALI mostrati nell'ultimo turno della chat).\n" +
      "Rispondi SOLO con JSON valido:\n" +
      '{"query_type":"...","corrected_query":"...","brand":null,"product_type":null,"gender":null,"max_price":null,"min_price":null,"size":null,"color":null,"model_tokens":[],"features":[],"sub_queries":[{"label":"...","terms":["..."],"role":"primary"}],"direct_answer":null}';

    const priorStateSummaryForLlm = isFollowUp && !categorySwitched
      ? {
          subject_query: prior.subjectQuery,
          brand: prior.brand,
          sub_brand: prior.subBrand?.[1] ?? null,
          product_type: prior.productType,
          entity_tokens: prior.entityTokens,
          gender: prior.gender,
          size: prior.size,
          max_price: prior.maxPrice,
          min_price: prior.minPrice,
          color: prior.color?.label ?? null,
          store: prior.store?.label ?? null,
          free_shipping: prior.freeShipping,
          on_sale: prior.onSale,
          min_discount: prior.minDiscount,
          features: prior.features,
        }
      : null;

    const plannerUserPromptParts: string[] = [];
    if (priorHistoryLines.length > 0) {
      plannerUserPromptParts.push(`Cronologia chat:\n${priorHistoryLines.join("\n")}`);
    }
    if (priorStateSummaryForLlm) {
      plannerUserPromptParts.push(`Stato filtri attivo prima di questo turno: ${JSON.stringify(priorStateSummaryForLlm)}`);
    }
    if (lastShownLines.length > 0) {
      plannerUserPromptParts.push(`Prodotti mostrati nell'ultimo turno:\n${lastShownLines.join("\n")}`);
    }
    plannerUserPromptParts.push(effectiveQueryForLLM);

    const llmPlan = loadMore
      ? null
      : await callOpenRouterJSON({
          systemPrompt: plannerSystemPrompt,
          userPrompt: plannerUserPromptParts.join("\n\n"),
          models: plannerModels,
          temperature: 0.1,
          maxTokens: 480,
          title: "FitMatch Query Planner",
          timeoutMs: 7_000,
          disableReasoning: true,
        });

    // Deterministic reconciliation over LLM plan (user query ALWAYS wins over stale UI params & LLM hallucinations!)
    const llmPTypeRaw = typeof llmPlan?.product_type === "string"
      ? llmPlan.product_type.trim().toLowerCase()
      : null;
    const llmPType = llmPTypeRaw && VALID_PRODUCT_TYPES.has(llmPTypeRaw as ProductType)
      ? (llmPTypeRaw as ProductType)
      : null;

    const productType: ProductType | null = detProductType ?? llmPType;

    // Price resolution (strictly respecting resets, ranges, and typed-query priority over stale UI params)
    const explicitMaxPrice = coercePositiveNumber(maxPriceParam);
    const llmMaxPrice = coercePositiveNumber(llmPlan?.max_price);
    const llmMinPrice = coercePositiveNumber(llmPlan?.min_price);

    let maxPrice: number | null = local.resetPrice
      ? null
      : (local.max_price ??
        (!categorySwitched ? explicitMaxPrice : null) ??
        (local.min_price == null ? llmMaxPrice : null) ??
        (!categorySwitched && isFollowUp ? prior.maxPrice : null));

    let minPrice: number | null = local.resetPrice
      ? null
      : (local.min_price ??
        (local.max_price == null ? llmMinPrice : null) ??
        (!categorySwitched && isFollowUp ? prior.minPrice : null));

    // Resolve incompatible inherited bounds (e.g. prior was "< 100" and user now says "sopra i 150 euro")
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      if (local.min_price != null && local.max_price == null) maxPrice = null;
      else if (local.max_price != null && local.min_price == null) minPrice = null;
      else {
        const lo = Math.min(minPrice, maxPrice);
        const hi = Math.max(minPrice, maxPrice);
        minPrice = lo;
        maxPrice = hi;
      }
    }

    // Size resolution (typed size or reset ALWAYS overrides stale UI sizeParam!)
    const cleanSizeParam = sizeParam && sizeParam.trim() ? sizeParam.trim() : null;
    const llmSize = llmPlan?.size && String(llmPlan.size).trim().toLowerCase() !== "null"
      ? String(llmPlan.size).trim()
      : null;
    const size: string | null = local.resetSize
      ? null
      : (local.size ??
        (local.asksMySize && effectivePreferredSize ? effectivePreferredSize : null) ??
        (!categorySwitched ? cleanSizeParam : null) ??
        llmSize ??
        (!categorySwitched && isFollowUp ? prior.size : null));

    // Gender resolution
    const llmGender = llmPlan?.gender && ["Uomo", "Donna"].includes(String(llmPlan.gender))
      ? String(llmPlan.gender)
      : null;
    const gender: string | null = local.resetGender
      ? null
      : (local.gender ??
        llmGender ??
        (!categorySwitched && isFollowUp ? prior.gender : null));

    // Color resolution
    const llmColor = typeof llmPlan?.color === "string" && llmPlan.color.trim() && llmPlan.color.trim().toLowerCase() !== "null"
      ? detectColorConstraint(llmPlan.color)
      : null;
    const colorConstraint: ColorConstraint | null = local.resetColor
      ? null
      : (local.color ??
        llmColor ??
        (!categorySwitched && isFollowUp ? prior.color : null));

    // Store resolution (supports both store id and display name in query OR URL param)
    const paramStore = storeParam && storeParam.trim()
      ? (extractStoreFilter(storeParam) ?? { id: storeParam.trim().toLowerCase(), label: storeParam.trim() })
      : null;
    const resolvedStore = local.resetStore
      ? null
      : (local.store ??
        (!categorySwitched ? paramStore : null) ??
        (!categorySwitched && isFollowUp ? prior.store : null));
    const effectiveStore = resolvedStore?.id ?? null;

    // Exclusions & sorting resolution (strictly respecting resets and positive overrides)
    const excludedBrands: string[] = [];
    if (!local.resetExclusions && !local.resetAllFilters) {
      if (isFollowUp && !categorySwitched) {
        for (const eb of prior.excludedBrands) {
          if (!excludedBrands.some((x) => x.toLowerCase() === eb.toLowerCase())) excludedBrands.push(eb);
        }
      }
      for (const eb of local.excluded_brands) {
        if (!excludedBrands.some((x) => x.toLowerCase() === eb.toLowerCase())) excludedBrands.push(eb);
      }
      // If user explicitly requests a brand now, remove it from excludedBrands
      if (currentBrand) {
        const idx = excludedBrands.findIndex((x) => x.toLowerCase() === currentBrand.toLowerCase());
        if (idx >= 0) excludedBrands.splice(idx, 1);
      }
    }
    const excludedBrandsLow = new Set(excludedBrands.map((b) => b.toLowerCase()));

    const excludedStores: Array<{ id: string; label: string }> = [];
    if (!local.resetExclusions && !local.resetAllFilters) {
      if (isFollowUp && !categorySwitched) {
        for (const es of prior.excludedStores) {
          if (!excludedStores.some((x) => x.id === es.id)) excludedStores.push(es);
        }
      }
      for (const es of local.excluded_stores) {
        if (!excludedStores.some((x) => x.id === es.id)) excludedStores.push(es);
      }
      if (resolvedStore) {
        const idx = excludedStores.findIndex((x) => x.id === resolvedStore.id);
        if (idx >= 0) excludedStores.splice(idx, 1);
      }
    }
    const excludedStoreIds = excludedStores.map((s) => s.id);

    const excludedFeatures: string[] = [];
    if (!local.resetExclusions && !local.resetAllFilters) {
      if (isFollowUp && !categorySwitched) {
        for (const ef of prior.excludedFeatures) {
          if (!excludedFeatures.includes(ef)) excludedFeatures.push(ef);
        }
      }
      for (const ef of local.excluded_features) {
        if (!excludedFeatures.includes(ef)) excludedFeatures.push(ef);
      }
    }

    const sortBy: SortByMode | null = (local.resetSort || local.resetAllFilters)
      ? null
      : (local.sort_by ?? (!categorySwitched && isFollowUp ? prior.sortBy : null));

    // Shipping, discount & feature filters
    const freeShipping = (local.resetAllFilters || local.resetFreeShipping)
      ? false
      : (local.free_shipping || (!categorySwitched && isFollowUp && prior.freeShipping));
    const minDiscount: number | null = (local.resetAllFilters || local.resetOnSale)
      ? null
      : (local.min_discount ?? (!categorySwitched && isFollowUp ? prior.minDiscount : null));
    const onSale = (local.resetAllFilters || local.resetOnSale)
      ? false
      : (local.on_sale || (minDiscount != null && minDiscount > 0) || (!categorySwitched && isFollowUp && prior.onSale));

    const activeFeatures: string[] = [];
    const addFeature = (f: string) => {
      const clean = f.trim().toLowerCase();
      if (!clean) return;
      if (excludedFeatures.includes("no_carbon") && /\b(carbon|piastra)\b/.test(clean) && !/\bsenza\b/.test(clean)) return;
      if (excludedFeatures.includes("no_waterproof") && /\b(waterproof|gtx|gore|impermeabil)\b/.test(clean) && !/\b(non|senza)\b/.test(clean)) return;
      if (!activeFeatures.includes(clean)) activeFeatures.push(clean);
    };
    if (isFollowUp && !categorySwitched && !local.resetAllFilters) {
      for (const f of prior.features) addFeature(f);
    }
    for (const f of local.features) addFeature(f);
    if (Array.isArray(llmPlan?.features)) {
      for (const f of llmPlan.features) addFeature(String(f ?? ""));
    }

    const allQueryBrands = extractAllBrands(normalizedQ);
    const queryType = String(llmPlan?.query_type ?? "").toLowerCase();
    const isComparison = queryType === "comparison" ||
      allQueryBrands.length >= 2 ||
      /\b(confronta|confronto|\bvs\b|versus|differenz[ae])\b/i.test(normalizedQ);

    const llmBrandRaw = llmPlan?.brand && String(llmPlan.brand).trim().toLowerCase() !== "null"
      ? String(llmPlan.brand).trim()
      : null;
    const llmBrandCandidate = llmBrandRaw && KNOWN_BRANDS.some((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())
      ? KNOWN_BRANDS.find((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())!
      : null;
    const llmBrand = llmBrandCandidate && !excludedBrandsLow.has(llmBrandCandidate.toLowerCase())
      ? llmBrandCandidate
      : null;

    const inheritedPrevBrand = (isFollowUp && !categorySwitched && prevBrand && !excludedBrandsLow.has(prevBrand.toLowerCase()))
      ? prevBrand
      : null;
    const brand = (isComparison && allQueryBrands.length >= 2)
      ? null
      : local.resetBrand
      ? (currentBrand ?? (currentSubBrand ? currentSubBrand[0] : null))
      : (currentBrand ??
        (effectiveSubBrand && !excludedBrandsLow.has(effectiveSubBrand[0].toLowerCase()) ? effectiveSubBrand[0] : null) ??
        inheritedPrevBrand ??
        (llmBrand && normalizedQ.toLowerCase().includes(llmBrand.toLowerCase()) ? llmBrand : null));

    const category = (categoryParam && categoryParam.trim() && categoryParam !== "all" && categoryParam !== "tutti")
      ? categoryParam.trim()
      : mapProductTypeToCategory(productType);

    const entityTokens: string[] = [...(currentEntities.length > 0 ? currentEntities : prevEntities)];
    if (entityTokens.length === 0 && !broadeningFollowUp && !local.resetBrand && Array.isArray(llmPlan?.model_tokens)) {
      const qLow = normalizedQ.toLowerCase();
      for (const mt of llmPlan.model_tokens) {
        const tok = normalizeQueryTypos(String(mt ?? "")).toLowerCase().trim();
        if (tok.length >= 2 && !/^\d+$/.test(tok) && !excludedBrandsLow.has(tok) && qLow.includes(tok) && !entityTokens.includes(tok)) {
          entityTokens.push(tok);
        }
      }
    }

    const hasExplicitFilterMutation = Boolean(
      local.max_price != null || local.min_price != null || local.size || local.asksMySize ||
      local.gender || local.color || local.store || local.free_shipping || local.on_sale ||
      local.excluded_brands.length > 0 || local.excluded_stores.length > 0 || local.excluded_features.length > 0 ||
      local.sort_by != null || local.resetPrice || local.resetSize || local.resetGender || local.resetColor ||
      local.resetStore || local.resetBrand || local.resetFreeShipping || local.resetOnSale ||
      local.resetExclusions || local.resetSort || local.resetAllFilters,
    );
    const isPureQA = pureQuestion || (
      queryType === "pure_question" && isFollowUp && currentEntities.length === 0 && !hasExplicitFilterMutation
    );
    const isAdvisory = !isPureQA && !isComparison && (
      queryType === "advisory" ||
      (currentEntities.length === 0 && /\b(miglior[ie]|consiglia|consigliami|\d+\s*kg|ginocchi|schiena|fascite|principiant|pronat)\b/i.test(normalizedQ))
    );
    const isExactModel = entityTokens.length > 0 && !broadeningFollowUp && !isComparison && !isAdvisory && !isPureQA;
    const effectiveEntityTokens = (isAdvisory || isPureQA) ? [] : entityTokens;
    const userSpecifiedDigits = effectiveEntityTokens.some((t) => /^\d+$/.test(t));

    // Build validated multi-query plan
    const plannedSubQueries: SubQuerySpec[] = [];
    const seenTermSigs = new Set<string>();

    const pushSubQuery = (sq: SubQuerySpec, prepend = false) => {
      const cleanTerms = sq.terms.map((t) => t.trim()).filter((t) => t.length >= 2);
      if (cleanTerms.length === 0 && sq.terms.length > 0) return;
      const sig = cleanTerms.map((t) => t.toLowerCase()).sort().join("|") + "|" + sq.role + "|" + (sq.brand ?? "");
      if (seenTermSigs.has(sig)) return;
      seenTermSigs.add(sig);
      const item = { ...sq, terms: cleanTerms.slice(0, 5) };
      if (prepend) plannedSubQueries.unshift(item);
      else plannedSubQueries.push(item);
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

      // Compute shared entity tokens safely — NEVER let LLM-invented version digits (like "39"/"40")
      // restrict a query when the user did NOT ask for a specific version!
      let sqEntities: string[];
      if (role === "primary" && !isComparison && !isAdvisory) {
        sqEntities = effectiveEntityTokens;
      } else {
        const perTermEnts = termsRaw.map((t) => new Set(extractSpecificEntityTokens(t, sqBrand)));
        const shared = perTermEnts.length > 0
          ? Array.from(perTermEnts[0]).filter((tok) =>
              perTermEnts.every((s) => s.has(tok)) && (userSpecifiedDigits || !/^\d+$/.test(tok))
            )
          : [];
        sqEntities = shared.slice(0, 2);
      }

      const cleanedTerms = buildCatalogSearchTerms({
        rawQuery: (role === "primary" && !isComparison && !isAdvisory) ? effectiveSubjectQuery : termsRaw[0],
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
          limit: role === "primary" ? 28 : 18,
        });
      }
    }

    // Build clean primary fallback / anchor terms using effectiveSubjectQuery (NEVER raw ">>" chains or filter text!)
    const prevKeywords = (shouldInheritPrevEntities || isPureQA) ? prior.lastKeywords : [];
    const qaEntities = currentEntities.length > 0 ? currentEntities : prevEntities;
    const qaRawForSearch = isPureQA
      ? (currentEntities.length > 0 || currentBrand ? normalizedQ : effectiveSubjectQuery)
      : effectiveSubjectQuery;

    // For exact model queries (e.g. "Nike Pegasus sotto 120€", "Nike long sleeve acg"),
    // ALWAYS anchor with the unversioned model/line name first so LLM version hallucinations cannot hide active discounted generations!
    const unversionedAnchor = (effectiveEntityTokens.length > 0 && !isComparison && !isAdvisory && !isPureQA)
      ? [brand, ...effectiveEntityTokens].filter(Boolean).join(" ").trim()
      : null;

    const primaryFallbackTerms = buildCatalogSearchTerms({
      rawQuery: qaRawForSearch,
      keywords: isPureQA
        ? (currentEntities.length > 0 ? rawPrimaryTermsFromLlm : prevKeywords)
        : [
            ...(unversionedAnchor ? [unversionedAnchor] : []),
            ...(rawPrimaryTermsFromLlm.length > 0 ? rawPrimaryTermsFromLlm : prevKeywords),
          ],
      brand,
      productType,
      entityTokens: isPureQA ? qaEntities : effectiveEntityTokens,
      isComparison,
    });

    if (isPureQA) {
      plannedSubQueries.length = 0;
      if (primaryFallbackTerms.length > 0 || brand || productType) {
        plannedSubQueries.push({
          label: primaryFallbackTerms[0] ?? effectiveSubjectQuery,
          terms: primaryFallbackTerms.slice(0, 4),
          role: "primary",
          brand,
          productType,
          entityTokens: qaEntities,
          allowSemantic: primaryFallbackTerms.length === 0 && !brand,
          limit: 8,
        });
      }
    } else {
      // Guarantee an unversioned primary anchor when the user asked for a specific model/line (e.g. "Nike Pegasus", "Nike ACG")
      if (unversionedAnchor && primaryFallbackTerms.length > 0) {
        const hasCleanUnversionedPrimary = plannedSubQueries.some((sq) =>
          sq.role === "primary" &&
          sq.terms.some((t) => {
            const tl = t.toLowerCase();
            return effectiveEntityTokens.every((e) => tl.includes(e)) && (userSpecifiedDigits || !/\b\d{2}\b/.test(tl));
          })
        );
        if (!hasCleanUnversionedPrimary) {
          pushSubQuery({
            label: primaryFallbackTerms[0],
            terms: primaryFallbackTerms,
            role: "primary",
            brand,
            productType,
            entityTokens: effectiveEntityTokens,
            allowSemantic: false,
            limit: 32,
          }, true);
        }
      } else if (!plannedSubQueries.some((sq) => sq.role === "primary") && primaryFallbackTerms.length > 0) {
        pushSubQuery({
          label: primaryFallbackTerms[0],
          terms: primaryFallbackTerms,
          role: "primary",
          brand,
          productType,
          entityTokens: effectiveEntityTokens,
          allowSemantic: !isExactModel,
          limit: 28,
        }, true);
      }

      // Direct SQL-filtered catalog browse for broad/category/brand queries with filters, exclusions, sorting (or empty plan):
      // Guarantees queries like "Scarpe running sotto i 150 euro", "Scarpe running più economiche",
      // "Scarpe running non Nike", "Scarpe Nike su Cisalfa", "Scarpe running con spedizione gratuita" scan ALL matching offers!
      const hasStructuredFilter = Boolean(
        maxPrice != null || minPrice != null || size || gender || colorConstraint ||
        effectiveStore || freeShipping || onSale || (minDiscount != null && minDiscount > 0) ||
        excludedBrands.length > 0 || excludedStoreIds.length > 0 || excludedFeatures.length > 0 ||
        sortBy != null,
      );
      // Also guarantee a brandless hybrid browse + pgvector safety net for broad conceptual queries
      // (e.g. "Scarpe maratona", "Giacca traspirante") so a narrow LLM sub-query can never collapse recall to 1 brand!
      const needsConceptualHybridBrowse = effectiveEntityTokens.length === 0 &&
        !isComparison &&
        (brand || productType) &&
        (hasStructuredFilter || hasExplicitFilterMutation || plannedSubQueries.length === 0 || loadMore || (!brand && productType != null));
      if (needsConceptualHybridBrowse) {
        const browseParts = [
          brand,
          productType === "trail_shoes" ? "scarpe trail" : productType === "shoes" ? "scarpe running" : null,
          colorConstraint ? colorConstraint.label.toLowerCase() : null,
          resolvedStore ? `su ${resolvedStore.label}` : null,
          maxPrice != null ? `sotto €${Math.round(maxPrice)}` : null,
          sortBy === "price_asc" ? "più economiche" : sortBy === "discount_desc" ? "sconti più alti" : null,
        ].filter(Boolean);
        const prioritizeBrowse = plannedSubQueries.length === 0 || sortBy != null || local.resetExclusions || local.resetAllFilters || loadMore;
        const browseSpec: SubQuerySpec = {
          label: browseParts.join(" ") || normalizedQ,
          terms: [], // Direct SQL-filtered catalog scan in search_products_catalog_v4 + parallel filtered pgvector RRF
          role: prioritizeBrowse ? "primary" : "variant",
          brand,
          productType,
          entityTokens: [],
          browseOnly: true,
          allowSemantic: !sortBy && !colorConstraint && !loadMore,
          limit: sortBy != null || loadMore ? 48 : 40,
        };
        if (prioritizeBrowse) {
          plannedSubQueries.unshift(browseSpec);
        } else {
          plannedSubQueries.push(browseSpec);
        }
      }
    }

    // Deterministic sibling expansion for compound model lines of a KNOWN brand (e.g. "adizero dropset" -> also fetch "dropset 4", "dropset 3")
    if (brand && effectiveEntityTokens.length >= 2 && !isComparison && !isPureQA) {
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
          limit: 16,
        });
      }
    }

    // Deterministic true long-sleeve + warm midlayer coverage for long_sleeve_top queries
    // Uses inherited effectiveSubBrand & effectiveEntityTokens so follow-ups ("Da uomo", "Da corsa") NEVER drop ACG or brand line!
    if (productType === "long_sleeve_top" && !isPureQA) {
      const subTag = effectiveSubBrand ? effectiveSubBrand[1] : null;
      const prefixTokens = [brand, ...(subTag ? [subTag] : effectiveEntityTokens.slice(0, 1))].filter(Boolean);
      const prefix = prefixTokens.join(" ").trim();

      // 1. Guarantee a dedicated TRUE long-sleeve primary sub-query (manica lunga / maniche lunghe / long sleeve / ls / 1/4 zip)
      const lsCoreTerms = prefix
        ? [`${prefix} manica lunga`, `${prefix} maniche lunghe`, `${prefix} long sleeve`, `${prefix} ls`, `${prefix} 1/4 zip`]
        : ["maglia manica lunga", "maglia maniche lunghe", "long sleeve running", "maglia 1/4 zip", "maglia termica manica lunga"];
      const hasTrueLsPrimary = plannedSubQueries.some((sq) =>
        sq.role === "primary" &&
        sq.terms.some((t) => /\b(manic[ae]\s+lung|long\s*sleeve|\bls\b|1\/4\s*zip)\b/i.test(t))
      );
      if (!hasTrueLsPrimary) {
        pushSubQuery({
          label: prefix ? `${prefix} manica lunga` : "Maglie a manica lunga",
          terms: lsCoreTerms,
          role: "primary",
          brand,
          productType: "long_sleeve_top",
          entityTokens: effectiveEntityTokens,
          allowSemantic: false,
          limit: 32,
        }, true);
      }

      // 2. Guarantee warm / Therma-FIT / half-zip / fleece complementary sub-query
      const hasWarmSubQuery = plannedSubQueries.some((sq) =>
        sq.terms.some((t) => /\b(therma|fleece|felpa|wolf|warm|termic|half\s*zip|pile)\b/i.test(t))
      );
      if (!hasWarmSubQuery) {
        const warmTerms = prefix
          ? [`${prefix} half zip`, `${prefix} therma fit`, `${prefix} fleece`, `${prefix} pile`, `${prefix} zip`]
          : ["maglia termica manica lunga", "half zip running", "therma fit", "pile tecnico"];
        pushSubQuery({
          label: prefix ? `${prefix} strati caldi e half-zip` : "Maglie termiche e half-zip",
          terms: warmTerms,
          role: "complementary",
          brand,
          productType: "long_sleeve_top",
          entityTokens: effectiveEntityTokens,
          allowSemantic: false,
          limit: 18,
        });
      }
    }

    // Guarantee always-on RRF Hybrid Semantic retrieval (FTS + filtered pgvector HNSW) on conceptual/non-SKU queries
    // so short intent queries like "scarpe maratona", "giacca traspirante", "scarpe ammortizzate" gain full vector recall!
    if (
      !isPureQA &&
      !isExactModel &&
      !isComparison &&
      !sortBy &&
      !colorConstraint &&
      !loadMore &&
      plannedSubQueries.length > 0 &&
      !plannedSubQueries.some((sq) => sq.allowSemantic)
    ) {
      plannedSubQueries[0].allowSemantic = true;
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

    const effectiveRawForSearch = (isFollowUp && !categorySwitched && !isPureQA && effectiveSubjectQuery !== normalizedQ)
      ? `${effectiveSubjectQuery} ${normalizedQ}`
      : effectiveSubjectQuery;

    const effectiveMaxPriceNum = maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null;
    const effectiveMinPriceNum = minPrice != null && Number.isFinite(minPrice) ? minPrice : null;
    const totalLimitRequested = loadMore
      ? Math.min(Math.max(limit, 24), 40)
      : Math.min(Math.max(limit, 38), 55);

    let multiRes = await searchCatalogMultiQuery(supabase, {
      rawQuery: effectiveRawForSearch,
      subQueries: plannedSubQueries,
      brand,
      excludedBrands: excludedBrands.length > 0 ? excludedBrands : null,
      category,
      productType,
      maxPrice: effectiveMaxPriceNum,
      minPrice: effectiveMinPriceNum,
      size,
      preferredSize: effectivePreferredSize,
      gender,
      store: effectiveStore,
      excludedStores: excludedStoreIds.length > 0 ? excludedStoreIds : null,
      excludedFeatures: excludedFeatures.length > 0 ? excludedFeatures : null,
      freeShipping,
      onSale,
      minDiscount,
      colorTokens: colorConstraint?.sqlTokens ?? null,
      requireColor: Boolean(colorConstraint),
      sortBy,
      excludeIds: excludeIds.length > 0 ? excludeIds : null,
      isComparison,
      diversifyModels: !isExactModel && !isComparison,
      relaxDiversity: loadMore,
      totalLimit: totalLimitRequested,
    });

    let finalResults = multiRes.products;
    const roleById: Record<string, "primary" | "variant" | "complementary"> = { ...multiRes.roleById };

    // Graceful color relaxation: if strict SQL color matching yielded 0 results, retry without requiring color
    // and inform the user transparently!
    let colorFilteredNote: string | null = null;
    if (colorConstraint && finalResults.length === 0 && !loadMore) {
      const noColorRes = await searchCatalogMultiQuery(supabase, {
        rawQuery: effectiveRawForSearch,
        subQueries: plannedSubQueries,
        brand,
        excludedBrands: excludedBrands.length > 0 ? excludedBrands : null,
        category,
        productType,
        maxPrice: effectiveMaxPriceNum,
        minPrice: effectiveMinPriceNum,
        size,
        preferredSize: effectivePreferredSize,
        gender,
        store: effectiveStore,
        excludedStores: excludedStoreIds.length > 0 ? excludedStoreIds : null,
        excludedFeatures: excludedFeatures.length > 0 ? excludedFeatures : null,
        freeShipping,
        onSale,
        minDiscount,
        colorTokens: colorConstraint.sqlTokens,
        requireColor: false,
        sortBy,
        isComparison,
        diversifyModels: !isExactModel && !isComparison,
        totalLimit: totalLimitRequested,
      });
      if (noColorRes.products.length > 0) {
        multiRes = noColorRes;
        finalResults = noColorRes.products;
        Object.assign(roleById, noColorRes.roleById);
        colorFilteredNote = `Non ho trovato varianti esplicitamente etichettate **${colorConstraint.label.toLowerCase()}** con questi filtri, quindi ti mostro comunque i modelli più vicini disponibili.`;
      }
    }

    // Relaxed fallback pass if strict search returned 0 results:
    // NEVER drop entityTokens + trigger open semantic search for exact non-existent SKUs/brands (e.g. "Scarpe NASA Turbo 9000"),
    // otherwise semantic search hallucinates unrelated shoes!
    if (finalResults.length === 0 && !loadMore) {
      if (!isExactModel) {
        const relaxed = await searchCatalogOffers(supabase, {
          rawQuery: effectiveRawForSearch,
          keywords: primaryFallbackTerms,
          brand,
          excludedBrands: excludedBrands.length > 0 ? excludedBrands : null,
          category,
          productType,
          entityTokens: [],
          maxPrice: effectiveMaxPriceNum,
          minPrice: effectiveMinPriceNum,
          size,
          preferredSize: effectivePreferredSize,
          gender,
          store: effectiveStore,
          excludedStores: excludedStoreIds.length > 0 ? excludedStoreIds : null,
          excludedFeatures: excludedFeatures.length > 0 ? excludedFeatures : null,
          freeShipping,
          onSale,
          minDiscount,
          colorTokens: colorConstraint?.sqlTokens ?? null,
          requireColor: Boolean(colorConstraint),
          sortBy,
          semanticQuery: normalizedQ,
          allowSemantic: !colorConstraint && !effectiveStore && excludedBrands.length === 0 && !sortBy,
          limit: 20,
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
            excludedBrands: excludedBrands.length > 0 ? excludedBrands : null,
            category,
            productType,
            entityTokens: nonDigit,
            maxPrice: effectiveMaxPriceNum,
            minPrice: effectiveMinPriceNum,
            size,
            preferredSize: effectivePreferredSize,
            gender,
            store: effectiveStore,
            excludedStores: excludedStoreIds.length > 0 ? excludedStoreIds : null,
            excludedFeatures: excludedFeatures.length > 0 ? excludedFeatures : null,
            freeShipping,
            onSale,
            minDiscount,
            colorTokens: colorConstraint?.sqlTokens ?? null,
            requireColor: Boolean(colorConstraint),
            sortBy,
            semanticQuery: null,
            allowSemantic: false,
            limit: 16,
          });
          finalResults = genRelaxed;
          for (const p of genRelaxed) roleById[p.id] = "primary";
        }
      }
    }

    // =========================================================================
    // STRICT FINAL FILTER ENFORCEMENT GUARD (zero-leak guarantee!)
    // Ensures EVERY returned offer & product satisfies all active structured constraints.
    // =========================================================================
    if (finalResults.length > 0 && (
      effectiveMaxPriceNum != null || effectiveMinPriceNum != null || effectiveStore != null ||
      excludedBrandsLow.size > 0 || excludedStoreIds.length > 0 ||
      freeShipping || onSale || (minDiscount != null && minDiscount > 0)
    )) {
      const storeLow = effectiveStore?.toLowerCase() ?? null;
      const exStoreSet = new Set(excludedStoreIds.map((s) => s.toLowerCase()));
      const guarded: MatchedProductOut[] = [];
      for (const p of finalResults) {
        if (excludedBrandsLow.size > 0) {
          const pb = (p.brand ?? "").toLowerCase();
          const pn = p.canonical_name.toLowerCase();
          const hitExcluded = Array.from(excludedBrandsLow).some((eb) => pb === eb || pn.includes(eb));
          if (hitExcluded) continue;
        }
        const validOffers = p.offers.filter((o) => {
          if (effectiveMaxPriceNum != null && o.price > effectiveMaxPriceNum + 0.01) return false;
          if (effectiveMinPriceNum != null && o.price < effectiveMinPriceNum - 0.01) return false;
          const sid = (o.store_id ?? "").toLowerCase();
          if (exStoreSet.size > 0 && exStoreSet.has(sid)) return false;
          if (storeLow) {
            const sname = (o.store_name ?? "").toLowerCase();
            if (sid !== storeLow && !sid.includes(storeLow) && !sname.includes(storeLow)) return false;
          }
          if (freeShipping && (o.shipping_cost == null || o.shipping_cost > 0.01)) return false;
          if (minDiscount != null && minDiscount > 0) {
            const effDisc = o.discount_pct ?? (
              o.original_price && o.original_price > o.price
                ? ((o.original_price - o.price) / o.original_price) * 100
                : 0
            );
            if (effDisc + 0.5 < minDiscount) return false;
          } else if (onSale) {
            const isDisc = (o.discount_pct != null && o.discount_pct >= 5) ||
              (o.original_price != null && o.original_price > o.price + 1);
            if (!isDisc) return false;
          }
          return true;
        });
        if (validOffers.length === 0) continue;
        validOffers.sort((a, b) => a.price - b.price);
        const bestP = validOffers[0].price;
        const maxP = validOffers[validOffers.length - 1].price;
        const storesSet = new Set(validOffers.map((o) => o.store_id));
        guarded.push({
          ...p,
          offers: validOffers,
          best_price: bestP,
          highest_price: maxP,
          cross_store_savings: storesSet.size > 1 && maxP > bestP ? Math.round((maxP - bestP) * 100) / 100 : null,
        });
      }
      finalResults = guarded;
    }

    // Fast-path return for Classic Mode pagination ("Carica altri"):
    // Skips Stage 2 LLM Merchandiser & chat_messages persistence so next page arrives in ~0.5-1s!
    if (loadMore) {
      const nextHasMore = finalResults.length > 0 && (
        multiRes.hasMore || finalResults.length >= totalLimitRequested
      );
      return {
        search_mode: "classic",
        is_deep_dive: false,
        is_conversational_advice: false,
        load_more: true,
        total_found: finalResults.length,
        has_more: nextHasMore,
        results: finalResults,
        session_id: sessionId ?? null,
        turn_id: null,
        user_image_url: null,
        cache_hit: false,
      };
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
      // Pure Q&A follow-up MUST always return a direct expert answer grounded on real shown models!
      const refSubject = finalResults[0]?.canonical_name ??
        historyCtx.lastShownProducts[0]?.name ??
        effectiveSubjectQuery ??
        "i modelli selezionati";
      header = `Risposta su ${refSubject}`;
      const llmAns = typeof llmPlan?.direct_answer === "string" ? llmPlan.direct_answer.trim() : "";
      if (llmAns.length >= 20) {
        summary = llmAns;
      } else if (/calzan|taglia|veston/i.test(normalizedQ)) {
        summary = `In generale per **${refSubject}** la calzata è regolare: se corri lunghe distanze o hai la pianta leggermente larga, conviene scegliere **mezza taglia EU in più** rispetto alle scarpe casual (oppure la tua taglia abituale per l'abbigliamento tecnico).`;
      } else if (/traspirant|legger|fresc/i.test(normalizedQ)) {
        const namesList = (finalResults.length > 0
          ? finalResults.slice(0, 3).map((p) => p.canonical_name)
          : historyCtx.lastShownProducts.slice(0, 3).map((p) => p.name)).join(", ");
        summary = `Tra i modelli in elenco (**${namesList || refSubject}**), i tessuti più traspiranti sono le maglie tecniche **Dri-FIT / AirFlow** in mesh leggero rispetto ai pile o strati **Therma-FIT** pensati invece per trattenere calore.`;
      } else {
        summary = `Per **${refSubject}**, i modelli mostrati offrono un ottimo equilibrio tecnico per l'uso richiesto. Se vuoi affinare la scelta, dimmi il tuo budget, la taglia o il terreno su cui ti alleni.`;
      }
      if (finalResults.length > 0) {
        curatedSections = [{
          id: "qa_related",
          title: "Modelli di riferimento",
          subtitle: "Offerte verificate nei negozi partner",
          products: finalResults.slice(0, 8),
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
      if (minPrice != null && maxPrice != null) filterNotes.push(`tra €${Math.round(minPrice)} e €${Math.round(maxPrice)}`);
      else if (maxPrice != null) filterNotes.push(`sotto €${Math.round(maxPrice)}`);
      else if (minPrice != null) filterNotes.push(`sopra €${Math.round(minPrice)}`);
      if (size) filterNotes.push(`taglia ${size}`);
      if (gender) filterNotes.push(gender);
      if (colorConstraint) filterNotes.push(colorConstraint.label.toLowerCase());
      if (resolvedStore) filterNotes.push(`su ${resolvedStore.label}`);
      if (freeShipping) filterNotes.push("spedizione gratuita");
      if (minDiscount != null && minDiscount > 0) filterNotes.push(`sconto >= ${minDiscount}%`);
      else if (onSale) filterNotes.push("in sconto");
      summary = filterNotes.length > 0
        ? `Non ho trovato offerte attive per **${effectiveSubjectQuery}** con i filtri selezionati (${filterNotes.join(", ")}). Prova ad ampliare il budget o rimuovere un filtro per vedere i modelli disponibili.`
        : `Al momento non ho trovato offerte attive in catalogo per **${effectiveSubjectQuery}**. Prova con un nome modello leggermente diverso o una ricerca più ampia.`;
      followUps = [
        brand ? `Tutti i modelli ${brand}` : "Mostrami modelli simili",
        maxPrice != null || minPrice != null ? "Rimuovi limite di prezzo" : "Mostrami le migliori offerte",
        size ? "Mostra tutte le taglie" : "Rimuovi tutti i filtri",
      ];
    } else {
      emitStep?.({
        id: "curate",
        status: "running",
        title: "Organizzo sezioni e confronto",
        detail: "Seleziono categorie e punti chiave tecnici",
        elapsed_ms: Date.now() - startedAt,
      });

      // Balanced role sampling so Stage-2 sees up to 30 primary + variant + complementary lines
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
            if (chosen.length >= 30 || maxCount <= 0) break;
            if (!chosen.includes(idx)) {
              chosen.push(idx);
              maxCount--;
            }
          }
        };
        take(prim, 14);
        take(vari, 8);
        take(comp, 8);
        for (let i = 0; i < finalResults.length && chosen.length < 30; i++) {
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
        "Ricevi la query dell'utente, eventuali filtri attivi/contesto chat e la lista REALE dei prodotti trovati (`indice|ruolo P/V/C|nome|genere|prezzo|sconto|store|titolo_offerta`).\n\n" +
        "REGOLE TASSATIVE:\n" +
        "1. 'summary' (2-3 frasi nitide in italiano, max 290 caratteri):\n" +
        "   - Stile editoriale diretto basato SOLO sui modelli presenti nella lista: spiega le famiglie/varianti trovate e conferma in modo naturale i filtri applicati (es. budget, taglia, colore, negozio, sconto), con **grassetto** su 2-4 nomi modello/tecnologie.\n" +
        "   - Esempio ottimo: 'Ho trovato diverse **Nike ACG a manica lunga**, dalle T-shirt tecniche **Radical AirFlow NXT** e **Dri-FIT ADV** per corsa e trail, fino alle maglie **1/4 zip** e agli strati caldi **Therma-FIT** e **Wolf Grid** per clima fresco.'\n" +
        "   - VIETA cliché vuoti ('Scopri la gamma', 'Offrono comfort e stile', 'Per ogni esigenza').\n" +
        "2. 'sections' (2-3 sezioni se ci sono >= 5 prodotti; 1-2 sezioni se < 5):\n" +
        "   - Raggruppa SEMPRE per **linea/modello, tipo capo, uso sportivo, tecnologia o clima** (es. per long sleeve: prima le vere **Maglie a manica lunga / T-shirt LS**, poi **Half-zip e strati tecnici**, poi **Pile e felpe calde**).\n" +
        "   - INCLUDI PIÙ PRODOTTI POSSIBILI dalla lista (fino a 12-14 per sezione, non solo 2-3!), così l'utente può esplorare tutta la selezione reale.\n" +
        "   - Titolo ultra-pulito (2-5 parole, SENZA due punti ':'), sottotitolo breve e chiaro (max 8 parole, senza punto finale).\n" +
        "   - VIETA ASSOLUTAMENTE sezioni divise per genere ('Per Uomo'/'Per Donna') o generiche ('Sconti più Alti', 'Miglior Prezzo', 'Varianti').\n" +
        "   - Ogni sezione DEVE avere almeno 2 prodotti (se il totale >= 4).\n" +
        "   - La prima sezione raccoglie i prodotti `P` più vicini alla query.\n" +
        "   - Ogni indice può comparire al massimo in UNA sezione (zero duplicati).\n" +
        "3. 'featured' (esattamente 2 schede se N >= 2, altrimenti 1):\n" +
        "   - Scegli 2 modelli CONTRASTANTI e con NOME MODELLO SPECIFICO.\n" +
        "   - Per ciascuno scrivi 3 'highlights' TECNICI REALI ultra-concisi (3-7 parole l'uno).\n" +
        "   - VIETA highlights banali su prezzo/sconto/stile ('Sconto del 40%', 'Stile versatile', 'Ottima vestibilità', 'Prezzo verificato')!\n" +
        "4. 'follow_ups' (esattamente 3 pillole brevi, 2-5 parole ciascuna):\n" +
        "   - Esempi perfetti: 'Mostrami la mia taglia', 'Solo modelli da trail', 'Sotto 110 €', 'Mostrami solo nere', 'Con spedizione gratuita', 'Rimuovi limite di prezzo'.\n" +
        "   - VIETA di ripetere parole o filtri già attivi e calcola un prezzo realistico rispetto alla lista.\n" +
        "   - Se l'utente non ha richiesto un singolo brand, varia i brand nella prima sezione evitando di mettere 5 modelli dello stesso brand di fila.\n\n" +
        "Rispondi SOLO con JSON valido:\n" +
        '{"summary":"...","sections":[{"title":"...","subtitle":"...","indices":[0,1]}],"featured":[{"index":0,"ideal_for":"...","highlights":["...","...","..."]}],"follow_ups":["...","...","..."]}';

      const activeFiltersSummary = {
        subject: effectiveSubjectQuery,
        brand,
        excluded_brands: excludedBrands.length > 0 ? excludedBrands : undefined,
        gender,
        size,
        preferred_size: effectivePreferredSize,
        max_price: maxPrice,
        min_price: minPrice,
        color: colorConstraint?.label ?? null,
        store: resolvedStore?.label ?? null,
        excluded_stores: excludedStores.length > 0 ? excludedStores.map((s) => s.label) : undefined,
        excluded_features: excludedFeatures.length > 0 ? excludedFeatures : undefined,
        sort_by: sortBy ?? undefined,
        free_shipping: freeShipping || undefined,
        on_sale: onSale || undefined,
        min_discount: minDiscount ?? undefined,
        features: activeFeatures.length > 0 ? activeFeatures : undefined,
      };

      const merchPrompt =
        `Query: "${q}"` +
        (priorHistoryLines.length > 0 ? `\nCronologia:\n${priorHistoryLines.join("\n")}` : "") +
        `\nFiltri attivi: ${JSON.stringify(activeFiltersSummary)}` +
        `\nProdotti (${manifestIndices.length} su ${finalResults.length} totali):\n${compactCatalogLines}`;

      const merchJson = await callOpenRouterJSON({
        systemPrompt: merchSystemPrompt,
        userPrompt: merchPrompt,
        models: merchModels,
        temperature: 0.2,
        maxTokens: 900,
        title: "FitMatch Merchandiser",
        timeoutMs: 8_500,
        disableReasoning: true,
      });

      const fallback = buildSmartFallbackMerchandising({
        query: effectiveSubjectQuery,
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

        // 2. Validated disjoint curated sections (up to 14 items/section + rescue ALL unplaced products!)
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
              products: secProds.slice(0, 14),
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

        // Rescue ALL remaining found products so Deep Dive NEVER silently drops half the catalog matches!
        if (builtSections.length > 0) {
          const warmRe = /\b(pile|fleece|felp[ae]|hoodie|therma[\s-]*fit|wolf\s*grid|wolf\s*tree|canwell|tuff|sweatshirt)\b/i;
          const warmSecIdx = productType === "long_sleeve_top"
            ? builtSections.findIndex((s) => /\b(cald|pile|fleece|therma|felp|fredd|invern)\b/i.test(`${s.title} ${s.subtitle}`))
            : -1;
          const overflowRemaining: MatchedProductOut[] = [];

          for (let idx = 0; idx < finalResults.length; idx++) {
            if (usedInSections.has(idx)) continue;
            const p = finalResults[idx];
            const role = roleById[p.id] ?? "primary";
            let targetSec: CuratedSection | null = null;

            if (productType === "long_sleeve_top") {
              if (warmRe.test(p.canonical_name)) {
                const candidate = warmSecIdx >= 0 ? builtSections[warmSecIdx] : builtSections[builtSections.length - 1];
                if (candidate.products.length < 14) targetSec = candidate;
              } else if (builtSections[0].products.length < 16) {
                targetSec = builtSections[0];
              }
            } else if (role === "primary" && builtSections[0].products.length < 14) {
              targetSec = builtSections[0];
            } else {
              const nonFirst = builtSections.slice(1).find((s) => s.products.length < 14);
              targetSec = nonFirst ?? (builtSections[0].products.length < 14 ? builtSections[0] : null);
            }

            if (targetSec) {
              targetSec.products.push(p);
              usedInSections.add(idx);
            } else {
              overflowRemaining.push(p);
              usedInSections.add(idx);
            }
          }

          if (overflowRemaining.length > 0 && builtSections.length < 4) {
            builtSections.push({
              id: "sec_more_matches",
              title: "Altre opzioni trovate",
              subtitle: "Altri modelli compatibili con la tua ricerca",
              products: overflowRemaining.slice(0, 14),
            });
          } else if (overflowRemaining.length > 0) {
            // Append remaining into last section up to 18 so nothing is lost
            const lastSec = builtSections[builtSections.length - 1];
            for (const p of overflowRemaining) {
              if (lastSec.products.length >= 18) break;
              lastSec.products.push(p);
            }
          }

          curatedSections = builtSections.slice(0, 4);
        } else {
          curatedSections = fallback.sections;
        }

        // 3. Validated featured highlight cards
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

    // Reorder finalResults cleanly: preserve explicit sortBy order (e.g. "più economiche") across sections & results!
    if (sortBy) {
      const sortProdList = (list: MatchedProductOut[]) => {
        if (sortBy === "price_asc") {
          list.sort((a, b) => (a.best_price ?? 99999) - (b.best_price ?? 99999));
        } else if (sortBy === "price_desc") {
          list.sort((a, b) => (b.best_price ?? 0) - (a.best_price ?? 0));
        } else if (sortBy === "discount_desc") {
          const maxD = (p: MatchedProductOut) => Math.max(
            0,
            ...p.offers.map((o) => o.discount_pct ?? (o.original_price && o.original_price > o.price ? ((o.original_price - o.price) / o.original_price) * 100 : 0)),
          );
          list.sort((a, b) => maxD(b) - maxD(a) || (a.best_price ?? 99999) - (b.best_price ?? 99999));
        }
      };
      sortProdList(finalResults);
      for (const sec of curatedSections) sortProdList(sec.products);
      if (sortBy === "price_asc" && curatedSections.length > 1) {
        curatedSections.sort((a, b) => (a.products[0]?.best_price ?? 99999) - (b.products[0]?.best_price ?? 99999));
      } else if (sortBy === "price_desc" && curatedSections.length > 1) {
        curatedSections.sort((a, b) => (b.products[0]?.best_price ?? 0) - (a.products[0]?.best_price ?? 0));
      }
    } else if (curatedSections.length > 0) {
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
      features: activeFeatures,
      explanation: summary,
      source: llmPlan ? "supabase_edge_v3_shop" : "supabase_edge_v3_heuristic",
      is_off_topic: false,
      is_unsafe: false,
      is_conversational_advice: isPureQA,
    };

    const chips = buildChips({
      brand,
      excluded_brands: excludedBrands,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
      color: colorConstraint?.label ?? null,
      store: resolvedStore?.label ?? null,
      excluded_stores: excludedStores,
      excluded_features: excludedFeatures,
      sort_by: sortBy,
      free_shipping: freeShipping,
      on_sale: onSale,
      min_discount: minDiscount,
    });

    const contextStateObj: Record<string, unknown> = {
      subject_query: effectiveSubjectQuery,
      last_query: normalizedQ,
      last_keywords: primaryFallbackTerms,
      entity_tokens: entityTokens,
      product_type: productType,
      brand,
      excluded_brands: excludedBrands,
      sub_brand: effectiveSubBrand ? effectiveSubBrand[1] : null,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
      color: colorConstraint?.key ?? null,
      store: resolvedStore?.id ?? null,
      excluded_stores: excludedStoreIds,
      excluded_features: excludedFeatures,
      sort_by: sortBy,
      free_shipping: freeShipping,
      on_sale: onSale,
      min_discount: minDiscount,
      features: activeFeatures,
    };

    const hasMoreResults = finalResults.length > 0 &&
      !isPureQA &&
      !isExactModel &&
      !isComparison &&
      (multiRes.hasMore || finalResults.length >= Math.min(totalLimitRequested, 30));

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
      has_more: hasMoreResults,
      context_state: contextStateObj,
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
