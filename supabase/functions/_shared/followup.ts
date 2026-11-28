import {
  detectExplicitProductType,
  detectSingleProductType,
  detectSubBrand,
  escapeRegExp,
  extractAllBrands,
  extractBrand,
  extractExcludedBrands,
  extractExcludedStores,
  extractSpecificEntityTokens,
  extractStoreFilter,
  isBroadeningFollowUp,
  KNOWN_BRANDS,
  KNOWN_STORES,
  normalizeProductTypeGroup,
  normalizeQueryTypos,
  ProductType,
  sanitizeEntityTokens,
  SortByMode,
} from "./catalog.ts";

export const VALID_PRODUCT_TYPES = new Set<ProductType>([
  "leggings_tights", "shorts", "pants", "long_sleeve_top", "short_sleeve_top",
  "singlet_top", "top", "jacket", "socks", "headwear", "heart_rate_monitor",
  "bike_computer", "gps_watch", "eyewear", "hydration", "swim", "padel_racket", "padel_shoes",
  "tennis_racket", "football_boots", "basketball_shoes", "tennis_shoes",
  "volleyball_shoes", "trail_shoes", "shoes", "winter_sports", "nutrition",
  "smart_trainer",
]);

export interface ColorConstraint {
  key: string;
  label: string;
  matchRegex: RegExp;
  sqlTokens: string[];
}

export const COLOR_MAP: Array<{ key: string; label: string; regex: RegExp; matchRegex: RegExp; sqlTokens: string[] }> = [
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

export function detectColorConstraint(q: string): ColorConstraint | null {
  const low = q.toLowerCase();
  for (const c of COLOR_MAP) {
    if (c.regex.test(low)) return { key: c.key, label: c.label, matchRegex: c.matchRegex, sqlTokens: c.sqlTokens };
  }
  return null;
}

export function getColorByKey(key: string | null | undefined): ColorConstraint | null {
  if (!key) return null;
  const k = key.trim().toLowerCase();
  const found = COLOR_MAP.find((c) => c.key === k || c.label.toLowerCase() === k);
  return found ? { key: found.key, label: found.label, matchRegex: found.matchRegex, sqlTokens: found.sqlTokens } : null;
}

export function coercePositiveNumber(val: unknown): number | null {
  if (typeof val === "number" && Number.isFinite(val) && val > 0) return val;
  if (typeof val === "string") {
    const cleaned = val.replace(/[€$\s]/g, "").replace(",", ".").trim();
    if (!cleaned) return null;
    const n = Number(cleaned);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return null;
}

export interface ParsedLocalConstraints {
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

export function isAnyFilterReset(local: ParsedLocalConstraints): boolean {
  return Boolean(
    local.resetAllFilters ||
    local.resetPrice ||
    local.resetSize ||
    local.resetGender ||
    local.resetColor ||
    local.resetStore ||
    local.resetBrand ||
    local.resetFreeShipping ||
    local.resetOnSale ||
    local.resetExclusions ||
    local.resetSort,
  );
}

export function extractExcludedFeaturesFromText(low: string): string[] {
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

export function extractFeaturesFromText(low: string, excludedFeats: string[]): string[] {
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

export function parseLocalConstraints(q: string): ParsedLocalConstraints {
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

  // 3b. Approximate budget ("sui 90 euro", "intorno ai 100€", "circa 80 euro") -> gentle +15% cap rounded up to €5
  let approxMaxPrice: number | null = null;
  if (!rangeMatch && !maxPriceMatch && !minPriceMatch) {
    const approxMatch = low.match(/\b(?:sui|intorno\s+a(?:i|gli|lle)?|attorno\s+a(?:i|gli|lle)?|circa|verso\s+i)\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?/i);
    if (approxMatch && approxMatch.index != null) {
      const after = low.slice(approxMatch.index + approxMatch[0].length);
      const val = Number(approxMatch[1].replace(",", "."));
      const hasCurr = CURRENCY_HINT_RE.test(approxMatch[0]) || CURRENCY_HINT_RE.test(low);
      if (!NON_PRICE_UNIT_RE.test(after) && hasCurr && Number.isFinite(val) && val >= 15) {
        approxMaxPrice = Math.ceil((val * 1.15) / 5) * 5;
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
  if (/\b(pi[uù]\s+(?:economic[hoaie]+|convenient[ei]|accessibil[ei]|a\s+buon\s+mercato)|prezz[oi]\s+(?:pi[uù]\s+)?(?:bass[oi]|minor[ei]|inferior[ei]|ridott[oi]|contenut[oi]|accessibil[ei])|dal\s+meno\s+caro|meno\s+(?:costos[aeio]|car[aeio])|(?:che\s+)?costa(?:no)?\s+(?:di\s+)?meno|spendere\s+(?:di\s+)?meno|fascia\s+bassa|entry[\s-]*level|ordina(?:t[aeio])?\s+per\s+prezzo(?:\s+crescente)?|cheapest|lowest\s+price)\b/i.test(low)) {
    sortBy = "price_asc";
  } else if (/\b(pi[uù]\s+(?:costos[aeio]|car[aeio])|prezz[oi]\s+(?:pi[uù]\s+)?(?:alt[oi]|maggior[ei]|superior[ei])|(?:che\s+)?costa(?:no)?\s+di\s+pi[uù]|prezzo\s+decrescente|dal\s+pi[uù]\s+caro)\b/i.test(low)) {
    sortBy = "price_desc";
  } else if (/\b(scont[oi]\s+(?:pi[uù]\s+)?(?:alt[oi]|elevat[oi]|fort[ei]|grand[ei]|important[ei]|interessant[ei])|(?:maggior[ie]?|fort[ei]|grand[ei]|miglior[ie])\s+scont[oi]|pi[uù]\s+scontat[aeio]|ordina(?:t[aeio])?\s+per\s+sconto|biggest\s+discount)\b/i.test(low)) {
    sortBy = "discount_desc";
  }

  const freeShipping = /\b(spedizione\s+(?:gratuita|gratis)|senza\s+spese\s+di\s+spedizione|free\s+shipping)\b/i.test(low);
  const discPctMatch = low.match(/(?:sconto\s*(?:almeno|minimo|di|del)?\s*|almeno\s+|-)(\d{1,2})\s*%/i);
  const minDiscount = discPctMatch ? Number(discPctMatch[1]) : null;
  const onSale = Boolean(
    (minDiscount != null && minDiscount > 0) ||
    sortBy === "discount_desc" ||
    /\b(in\s+(?:sconto|offerta|saldo|promo|promozione)|scontat[aeio]|saldi|con\s+scont[oi]|miglior[ie]\s+scont[oi]|solo\s+scont[oi]|solo\s+offert[ae])\b/i.test(low),
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
      else if (approxMaxPrice != null) maxPrice = approxMaxPrice;
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

export function isPureAdviceQuestion(
  q: string,
  isFollowUp: boolean,
  parsedLocal?: ParsedLocalConstraints,
): boolean {
  const low = q.trim().toLowerCase();
  const parsed = parsedLocal ?? parseLocalConstraints(q);

  // Any explicit shopping/sorting/filtering/reset mutation MUST execute a catalog search, NEVER a pure Q&A card!
  if (
    parsed.sort_by != null ||
    parsed.max_price != null ||
    parsed.min_price != null ||
    parsed.size != null ||
    parsed.asksMySize ||
    parsed.gender != null ||
    parsed.color != null ||
    parsed.store != null ||
    parsed.free_shipping ||
    parsed.on_sale ||
    parsed.excluded_brands.length > 0 ||
    parsed.excluded_stores.length > 0 ||
    parsed.excluded_features.length > 0 ||
    isAnyFilterReset(parsed)
  ) {
    return false;
  }

  // Explicit shopping / filtering triggers are NEVER pure Q&A advice cards
  if (/\b(mostram|mostran|cerca|trovam|fammi\s+vedere|solo\s+|filtra|alternative|altri\s+modelli|mia\s+taglia|taglia\s+\S|marca\s+|brand\s+|sotto\s*(?:i|ai|gli)?\s*€?\s*\d|meno\s+di\s*€?\s*\d|fino\s+a\s*€?\s*\d|su\s+(?:cisalfa|decathlon|alltricks|deporvillage|mister\s*running|top4running|maxisport))\b/i.test(low)) {
    return false;
  }
  if (isFollowUp) {
    return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?|vanno|funzion(?:a|ano)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?|costa(?:no)?)|qual\s+[eè]\s+(?:il\s+(?:drop|peso)|la\s+pi[uù]\s+\w+|il\s+pi[uù]\s+\w+|la\s+miglior|il\s+miglior|la\s+differenza)|quale\s+(?:mi\s+consigli|conviene|tiene\s+pi[uù]|sceglieresti|[eè]\s+meglio)|vanno\s+bene\s+per|va\s+bene\s+per|sono\s+(?:comode?|buone?|adatte?|impermeabili?|neutre?|traspiranti?|calde?)|hanno\s+(?:le\s+tasche|la\s+piastra|il\s+liner|il\s+boxer)|che\s+differenza\s+c['’][eè]|differenza\s+tra)/i.test(low) ||
      (low.endsWith("?") && /\b(calza(?:no|re)?|vest(?:e|ono|ire)?|drop|peso|dura(?:no)?|tasche|pronat|supinat|mezza\s+maratona|maratona|palestra|pioggia|comfort|comodi|comode|differenza|traspirant|pi[uù]\s+legger|pi[uù]\s+cald|tra\s+quest[aeio])\b/i.test(low));
  }
  return /^(?:come\s+(?:calza(?:no|re)?|vest(?:e|ono|ire)?)|quanto\s+(?:dura(?:no)?|pesa(?:no)?)|qual\s+[eè]\s+il\s+(?:drop|peso)|vanno\s+bene\s+per)\b/i.test(low);
}

export interface ReplayedContext {
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

export function emptyReplayedContext(): ReplayedContext {
  return {
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
}

function replaceOrStripBrandInSubject(subject: string, oldBrand: string | null, newBrand: string | null): string {
  if (!oldBrand) return subject;
  const re = new RegExp(`\\b${escapeRegExp(oldBrand)}\\b`, "gi");
  if (!re.test(subject)) return subject;
  const replaced = subject.replace(re, newBrand ?? " ").replace(/\s+/g, " ").trim();
  return replaced.length >= 2 ? replaced : subject;
}

/**
 * Deterministically reconstructs complete multi-turn conversation state from BOTH
 * persisted DB `context_state` + `chat_messages` AND the `context_query` chain ("t0 >> t1 >> t2").
 * This guarantees follow-ups NEVER lose brand, model, subject, or filters even if session_id
 * wasn't persisted yet or after a client cache hit / session restore, and auto-heals legacy poisoned DB state!
 */
export function reconstructPriorContext(opts: {
  prevContext: Record<string, unknown> | null;
  contextQuery: string | null;
  recentTurns: Array<{ query: string }>;
  preferredSize: string | null;
}): ReplayedContext {
  const res = emptyReplayedContext();

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
    const isPureReset = isAnyFilterReset(parsed) && !explicitPt && !tBrand && !tSub;
    const rawTEnts = isPureReset ? [] : extractSpecificEntityTokens(norm, tBrand);
    const tBroaden = isBroadeningFollowUp(norm);

    const prevTurnBrand = res.brand;
    const isDigitOnlyRefinement = !switched &&
      rawTEnts.length > 0 &&
      rawTEnts.every((t) => /^\d+$/.test(t)) &&
      res.entityTokens.some((t) => !/^\d+$/.test(t)) &&
      !(tBrand && prevTurnBrand && tBrand.toLowerCase() !== prevTurnBrand.toLowerCase());
    const tEnts = isDigitOnlyRefinement
      ? [...res.entityTokens.filter((t) => !/^\d+$/.test(t)), ...rawTEnts]
      : rawTEnts;

    if (parsed.resetBrand || tBroaden) {
      if (parsed.resetBrand) {
        if (!tBrand && res.brand && res.subjectQuery) {
          res.subjectQuery = replaceOrStripBrandInSubject(res.subjectQuery, res.brand, null);
        }
        res.brand = null;
      }
      if (tBroaden) {
        res.entityTokens = [];
        res.subBrand = null;
      }
    }
    if (tBrand) {
      if (res.brand && res.brand.toLowerCase() !== tBrand.toLowerCase()) {
        if (res.subjectQuery && !explicitPt && tEnts.length === 0) {
          res.subjectQuery = replaceOrStripBrandInSubject(res.subjectQuery, res.brand, tBrand);
        }
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

    // Update subjectQuery ONLY when the turn carries actual product/category/model intent (never pure filter/reset/brand-only turns!)
    const hasSubjectContent = Boolean(
      explicitPt ||
      (!res.productType && inferredPt) ||
      tEnts.length > 0 ||
      (tBrand && !res.subjectQuery),
    );
    if (!isPureReset && !tBroaden && hasSubjectContent && !isPureAdviceQuestion(norm, Boolean(res.subjectQuery), parsed)) {
      if (isDigitOnlyRefinement) {
        res.subjectQuery = [res.brand, ...tEnts].filter(Boolean).join(" ");
      } else {
        res.subjectQuery = norm;
      }
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

  // Overlay structured DB context_state where available & up-to-date (without letting stale/poisoned DB state
  // override clean deterministic turn replay!)
  const pc = opts.prevContext;
  const dbContextIsCurrent = dbTurns.length >= ctxParts.length;
  if (pc && dbContextIsCurrent) {
    if (!res.subjectQuery && typeof pc.subject_query === "string" && pc.subject_query.trim()) {
      res.subjectQuery = pc.subject_query.trim();
    }
    if (!res.productType && typeof pc.product_type === "string" && VALID_PRODUCT_TYPES.has(pc.product_type as ProductType)) {
      res.productType = pc.product_type as ProductType;
    }
    if (typeof pc.brand === "string" && pc.brand.trim() && !res.brand) {
      // Only adopt DB brand if the last replayed turn did NOT explicitly reset the brand
      const lastTurnParsed = orderedTurns.length > 0 ? parseLocalConstraints(orderedTurns[orderedTurns.length - 1]) : null;
      if (!lastTurnParsed?.resetBrand) {
        res.brand = pc.brand.trim();
      }
    }
    if (Array.isArray(pc.excluded_brands) && res.excludedBrands.length === 0) {
      res.excludedBrands = pc.excluded_brands.map(String).filter(Boolean);
    }
    if (Array.isArray(pc.entity_tokens) && pc.entity_tokens.length > 0 && res.entityTokens.length === 0) {
      // Scrub legacy poisoned entity tokens (e.g. ["marca", "minore"], ["brand"]) automatically!
      const cleanedDbTokens = sanitizeEntityTokens(pc.entity_tokens.map(String), res.brand);
      if (cleanedDbTokens.length > 0) {
        res.entityTokens = cleanedDbTokens;
      }
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

export interface FollowUpTransitionResult {
  normalizedQ: string;
  pureQuestion: boolean;
  isPureResetTurn: boolean;
  currentBrand: string | null;
  currentSubBrand: [string, string] | null;
  currentExplicitPType: ProductType | null;
  currentSinglePType: ProductType | null;
  prevPTypeRaw: ProductType | null;
  categorySwitched: boolean;
  sameGroupPTypeRefinement: boolean;
  broadeningFollowUp: boolean;
  currentEntities: string[];
  prevBrand: string | null;
  brandSwitched: boolean;
  shouldInheritPrevEntities: boolean;
  prevEntities: string[];
  effectiveSubBrand: [string, string] | null;
  detProductType: ProductType | null;
  effectiveSubjectQuery: string;
  allQueryBrands: string[];
  hasExplicitFilterMutation: boolean;
}

export function resolveFollowUpTransition(opts: {
  local: ParsedLocalConstraints;
  isFollowUp: boolean;
  prior: ReplayedContext;
}): FollowUpTransitionResult {
  const { local, isFollowUp, prior } = opts;
  const normalizedQ = local.normalizedQuery;
  const pureQuestion = isPureAdviceQuestion(normalizedQ, isFollowUp, local);

  const currentBrand = extractBrand(normalizedQ, null);
  const currentSubBrand = detectSubBrand(normalizedQ);
  const currentExplicitPType = detectExplicitProductType(normalizedQ);
  const currentSinglePType = detectSingleProductType(normalizedQ);
  const prevPTypeRaw = prior.productType;

  // ONLY switch category when the current turn mentions an EXPLICIT product noun/model
  // from a different group (e.g. "fascia cardio" after "scarpe trail", or "orologio Garmin" after "fascia cardio").
  // Activity-only refinements ("Da corsa", "Per trail") AND bare multi-category brand follow-ups ("Marca Garmin")
  // NEVER wipe the active product category!
  const categorySwitched = Boolean(
    currentExplicitPType && prevPTypeRaw &&
    normalizeProductTypeGroup(currentExplicitPType) !== normalizeProductTypeGroup(prevPTypeRaw),
  );
  const sameGroupPTypeRefinement = Boolean(
    !currentExplicitPType && currentSinglePType && prevPTypeRaw &&
    normalizeProductTypeGroup(currentSinglePType) === normalizeProductTypeGroup(prevPTypeRaw),
  );
  const broadeningFollowUp = isFollowUp && (isBroadeningFollowUp(normalizedQ) || local.resetBrand);
  const isPureResetTurn = isFollowUp && isAnyFilterReset(local) && !currentExplicitPType && !currentBrand && !currentSubBrand;

  const prevBrand = (!categorySwitched && !local.resetBrand) ? prior.brand : null;
  const brandSwitched = Boolean(currentBrand && prevBrand && currentBrand.toLowerCase() !== prevBrand.toLowerCase());

  const rawCurrentEntities = isPureResetTurn ? [] : extractSpecificEntityTokens(normalizedQ, currentBrand);
  // Digit-only model version follow-up (e.g. "Garmin Forerunner" -> "165" or "Garmin HRM" -> "200")
  const isDigitOnlyRefinement = isFollowUp &&
    !categorySwitched &&
    !brandSwitched &&
    !broadeningFollowUp &&
    rawCurrentEntities.length > 0 &&
    rawCurrentEntities.every((t) => /^\d+$/.test(t)) &&
    prior.entityTokens.some((t) => !/^\d+$/.test(t));
  const currentEntities = isDigitOnlyRefinement
    ? [...prior.entityTokens.filter((t) => !/^\d+$/.test(t)), ...rawCurrentEntities]
    : rawCurrentEntities;

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

  // Preserve clean subject query across pure filter/reset/brand-switch/activity/Q&A follow-ups!
  let effectiveSubjectQuery: string;
  if (!isFollowUp || categorySwitched) {
    effectiveSubjectQuery = normalizedQ;
  } else if (isPureResetTurn) {
    const baseSub = prior.subjectQuery ?? normalizedQ;
    effectiveSubjectQuery = (local.resetBrand && prior.brand)
      ? replaceOrStripBrandInSubject(baseSub, prior.brand, null)
      : baseSub;
  } else if (brandSwitched && !currentExplicitPType && currentEntities.length === 0) {
    effectiveSubjectQuery = prior.subjectQuery
      ? replaceOrStripBrandInSubject(prior.subjectQuery, prevBrand, currentBrand)
      : normalizedQ;
  } else if (isDigitOnlyRefinement) {
    effectiveSubjectQuery = [currentBrand ?? prevBrand, ...currentEntities].filter(Boolean).join(" ");
  } else if (!pureQuestion && (currentExplicitPType || currentEntities.length > 0)) {
    effectiveSubjectQuery = (!currentBrand && prevBrand && !brandSwitched && currentEntities.length > 0)
      ? `${prevBrand} ${normalizedQ}`
      : normalizedQ;
  } else {
    effectiveSubjectQuery = prior.subjectQuery ?? normalizedQ;
  }

  const allQueryBrands = extractAllBrands(normalizedQ);
  const hasExplicitFilterMutation = Boolean(
    local.max_price != null || local.min_price != null || local.size || local.asksMySize ||
    local.gender || local.color || local.store || local.free_shipping || local.on_sale ||
    local.excluded_brands.length > 0 || local.excluded_stores.length > 0 || local.excluded_features.length > 0 ||
    local.sort_by != null || isAnyFilterReset(local),
  );

  return {
    normalizedQ,
    pureQuestion,
    isPureResetTurn,
    currentBrand,
    currentSubBrand,
    currentExplicitPType,
    currentSinglePType,
    prevPTypeRaw,
    categorySwitched,
    sameGroupPTypeRefinement,
    broadeningFollowUp,
    currentEntities,
    prevBrand,
    brandSwitched,
    shouldInheritPrevEntities,
    prevEntities,
    effectiveSubBrand,
    detProductType,
    effectiveSubjectQuery,
    allQueryBrands,
    hasExplicitFilterMutation,
  };
}

export interface GuardedLlmFilters {
  llmPType: ProductType | null;
  llmMaxPrice: number | null;
  llmMinPrice: number | null;
  llmSize: string | null;
  llmGender: string | null;
  llmColor: ColorConstraint | null;
  llmBrandCandidate: string | null;
}

/**
 * Guards Stage-1 LLM filter outputs so the model can NEVER hallucinate filters (e.g. inventing
 * `gender: "Uomo"` on `"Tutti i brand"`) when the user's current utterance has zero matching signal!
 */
export function guardLlmPlanFilters(
  normalizedQ: string,
  llmPlan: Record<string, unknown> | null,
): GuardedLlmFilters {
  if (!llmPlan) {
    return {
      llmPType: null,
      llmMaxPrice: null,
      llmMinPrice: null,
      llmSize: null,
      llmGender: null,
      llmColor: null,
      llmBrandCandidate: null,
    };
  }

  const llmPTypeRaw = typeof llmPlan.product_type === "string"
    ? llmPlan.product_type.trim().toLowerCase()
    : null;
  const llmPType = llmPTypeRaw && VALID_PRODUCT_TYPES.has(llmPTypeRaw as ProductType)
    ? (llmPTypeRaw as ProductType)
    : null;

  const hasDigits = /\d/.test(normalizedQ);
  const llmMaxPrice = hasDigits ? coercePositiveNumber(llmPlan.max_price) : null;
  const llmMinPrice = hasDigits ? coercePositiveNumber(llmPlan.min_price) : null;

  const hasSizeCue = /\b(tagli[ae]|numero|misur[ae]|size|eu|us|uk|tg\.?|xxs|xs|xl|xxl|2xl|3xl|\d{2}(?:[.,]\d)?)\b/i.test(normalizedQ);
  const llmSize = hasSizeCue && llmPlan.size && String(llmPlan.size).trim().toLowerCase() !== "null"
    ? String(llmPlan.size).trim()
    : null;

  const hasGenderCue = /\b(uomo|uomini|maschil[ei]|ragazzo|mens?|men|man|lui|marito|fidanzato|pap[aà]|donna|donne|femmin[aei]|ragazza|wmns?|women|woman|lei|moglie|fidanzata|mamma)\b/i.test(normalizedQ);
  const llmGender = hasGenderCue && llmPlan.gender && ["Uomo", "Donna"].includes(String(llmPlan.gender))
    ? String(llmPlan.gender)
    : null;

  const hasColorCue = detectColorConstraint(normalizedQ) != null ||
    /\b(color[ei]|scur[oaie]|chiar[oaie]|fluo|pastello|total\s*black|tinta)\b/i.test(normalizedQ);
  const llmColor = hasColorCue && typeof llmPlan.color === "string" && llmPlan.color.trim() && llmPlan.color.trim().toLowerCase() !== "null"
    ? detectColorConstraint(llmPlan.color)
    : null;

  const llmBrandRaw = llmPlan.brand && String(llmPlan.brand).trim().toLowerCase() !== "null"
    ? String(llmPlan.brand).trim()
    : null;
  const llmBrandCandidate = llmBrandRaw && KNOWN_BRANDS.some((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())
    ? KNOWN_BRANDS.find((kb) => kb.toLowerCase() === llmBrandRaw.toLowerCase())!
    : null;

  return {
    llmPType,
    llmMaxPrice,
    llmMinPrice,
    llmSize,
    llmGender,
    llmColor,
    llmBrandCandidate,
  };
}
