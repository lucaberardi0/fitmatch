import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function createServiceClient(): SupabaseClient | null {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return null;
  return createClient(url, key);
}

export function extractJsonObject(raw: string): Record<string, unknown> | null {
  const match = raw.match(/(\{[\s\S]*\})/);
  let clean = (match ? match[1] : raw).trim();
  if (clean.startsWith("```json")) clean = clean.slice(7);
  else if (clean.startsWith("```")) clean = clean.slice(3);
  if (clean.endsWith("```")) clean = clean.slice(0, -3);
  try {
    const obj = JSON.parse(clean.trim());
    return obj && typeof obj === "object" && !Array.isArray(obj)
      ? (obj as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

export async function callOpenRouterJSON(opts: {
  systemPrompt: string;
  userPrompt: string;
  models: string[];
  temperature?: number;
  maxTokens?: number;
  title?: string;
  timeoutMs?: number;
  disableReasoning?: boolean;
}): Promise<Record<string, unknown> | null> {
  const apiKey = (Deno.env.get("OPENROUTER_API_KEY") ?? "").trim();
  if (!apiKey) return null;

  for (const model of opts.models) {
    if (!model) continue;
    const payload: Record<string, unknown> = {
      model,
      messages: [
        { role: "system", content: opts.systemPrompt },
        { role: "user", content: opts.userPrompt },
      ],
      temperature: opts.temperature ?? 0.1,
      max_tokens: opts.maxTokens ?? 800,
    };
    if (model.startsWith("openai/") || model.startsWith("google/gemini")) {
      payload.response_format = { type: "json_object" };
    }
    if (opts.disableReasoning && model.startsWith("google/gemini-2.5")) {
      payload.reasoning = { effort: "none" };
    }
    try {
      const resp = await fetch(OPENROUTER_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://fitmatch.it",
          "X-Title": opts.title ?? "FitMatch AI",
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(opts.timeoutMs ?? 15_000),
      });
      if (!resp.ok) continue;
      const data = await resp.json();
      const content = String(data?.choices?.[0]?.message?.content ?? "").trim();
      if (!content) continue;
      const parsed = extractJsonObject(content);
      if (parsed) return parsed;
    } catch {
      continue;
    }
  }
  return null;
}

const _embeddingCache = new Map<string, number[]>();

export async function getQueryEmbedding(text: string): Promise<number[] | null> {
  const apiKey = (Deno.env.get("OPENROUTER_API_KEY") ?? "").trim();
  const cleaned = text.trim();
  if (!apiKey || !cleaned) return null;
  const cacheKey = cleaned.toLowerCase();
  const hit = _embeddingCache.get(cacheKey);
  if (hit) return hit;
  try {
    const resp = await fetch("https://openrouter.ai/api/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: "text-embedding-3-small", input: cleaned }),
      signal: AbortSignal.timeout(6_000),
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    const emb = data?.data?.[0]?.embedding;
    if (Array.isArray(emb)) {
      if (_embeddingCache.size >= 64) {
        const firstKey = _embeddingCache.keys().next().value;
        if (firstKey) _embeddingCache.delete(firstKey);
      }
      _embeddingCache.set(cacheKey, emb);
      return emb;
    }
    return null;
  } catch {
    return null;
  }
}

// ============================================================================
// Domain Constants, Typo Normalization, Brand & Product-Type Intelligence
// ============================================================================

export type ProductType =
  | "leggings_tights"
  | "shorts"
  | "pants"
  | "long_sleeve_top"
  | "short_sleeve_top"
  | "singlet_top"
  | "top"
  | "jacket"
  | "socks"
  | "headwear"
  | "heart_rate_monitor"
  | "bike_computer"
  | "gps_watch"
  | "eyewear"
  | "hydration"
  | "swim"
  | "padel_racket"
  | "tennis_racket"
  | "football_boots"
  | "basketball_shoes"
  | "tennis_shoes"
  | "volleyball_shoes"
  | "trail_shoes"
  | "shoes"
  | "winter_sports"
  | "nutrition"
  | "smart_trainer";

export const KNOWN_BRANDS: string[] = [
  "The North Face", "New Balance", "Under Armour", "La Sportiva", "Rudy Project",
  "Nike", "Adidas", "Asics", "Hoka", "Brooks", "Saucony", "Mizuno", "Salomon",
  "Altra", "Puma", "Garmin", "Polar", "Suunto", "Coros", "Oakley", "Enervit",
  "Therabody", "Theragun", "CamelBak", "Scott", "Topo", "Karhu", "Diadora",
  "Joma", "Babolat", "Head", "Wilson", "Odlo", "Kiprun", "Craft", "Gorewear",
  "Compressport", "Uyn", "Cep", "Bullpadel", "Nox", "Siux", "Arena", "Speedo",
  "Wahoo", "Bryton", "iGPSPORT", "Amazfit", "Reebok", "Yonex", "Maurten",
  "Bliz", "Smith", "Atomic", "Rossignol", "Nordica", "Tecnica", "Kalenji",
  "On",
];

export const SUB_BRAND_TO_PARENT: Record<string, [string, string]> = {
  "acg": ["Nike", "acg"],
  "nikecourt": ["Nike", "nikecourt"],
  "nikelab": ["Nike", "nikelab"],
  "dri-fit": ["Nike", "dri-fit"],
  "drifit": ["Nike", "dri-fit"],
  "therma-fit": ["Nike", "therma-fit"],
  "aeroswift": ["Nike", "aeroswift"],
  "metcon": ["Nike", "metcon"],
  "solar chase": ["Nike", "solar chase"],
  "wolf grid": ["Nike", "wolf grid"],
  "wolf tree": ["Nike", "wolf tree"],
  "chinati": ["Nike", "chinati"],
  "terrex": ["Adidas", "terrex"],
  "adizero": ["Adidas", "adizero"],
  "dropset": ["Adidas", "dropset"],
  "s/lab": ["Salomon", "lab"],
  "s-lab": ["Salomon", "lab"],
  "slab": ["Salomon", "lab"],
  "bonatti": ["Salomon", "bonatti"],
  "fujitrail": ["Asics", "fujitrail"],
  "zeroweight": ["Odlo", "zeroweight"],
  "active warm": ["Odlo", "active warm"],
  "warmalite": ["Mizuno", "warmalite"],
  "heatgear": ["Under Armour", "heatgear"],
  "coldgear": ["Under Armour", "coldgear"],
  "forerunner": ["Garmin", "forerunner"],
  "fenix": ["Garmin", "fenix"],
};

const CASUAL_NON_SPORT_BRANDS = new Set([
  "only", "vero moda", "jack & jones", "woolrich", "armani", "ea7",
  "calvin klein", "tommy hilfiger", "guess", "desigual", "levi's",
  "levis", "ralph lauren", "hugo boss", "lacoste", "napapijri",
  "colmar", "timberland", "vans", "converse", "dr martens",
]);

const TYPO_SUBSTITUTIONS: Array<[RegExp, string]> = [
  [/\b(?:leggins|legins|legings|leggin)\b/gi, "leggings"],
  [/\b(?:calzamaglie)\b/gi, "calzamaglia"],
  [/\b(?:pantalonicini|pantaloncino)\b/gi, "pantaloncini"],
  [/\b(?:under\s*armor|underarmour|underarmor)\b/gi, "under armour"],
  [/\b(?:newbalance)\b/gi, "new balance"],
  [/\b(?:lasportiva)\b/gi, "la sportiva"],
  [/\b(?:thenorthface)\b/gi, "the north face"],
  [/\b(?:adiddas|addidas)\b/gi, "adidas"],
  [/\b(?:asiks|asiscs)\b/gi, "asics"],
  [/\b(?:sauconi|sacony)\b/gi, "saucony"],
  [/\b(?:salomom|salamon)\b/gi, "salomon"],
  [/\b(?:hokaa)\b/gi, "hoka"],
  [/\b(?:garmen|gamrin|garmn|garmmin)\b/gi, "garmin"],
  [/\b(?:forunner|fore\s*runner|forerun|forerunne)\b/gi, "forerunner"],
  [/\b(?:fennix|fenx)\b/gi, "fenix"],
  [/\b(?:garmin\s+forerunner|garmin|forerunner)\s*(165|265|965|55|255|955|570|970)\b/gi, "garmin forerunner $1"],
  [/\b(?:alpha\s*fl[yie]+|alphafly+)\b/gi, "alphafly"],
  [/\b(?:vapor\s*fl[yie]+|vaporfly+)\b/gi, "vaporfly"],
  [/\b(?:ultra\s*fl[yie]+|ultrafly+)\b/gi, "ultrafly"],
  [/\b(?:streak\s*fl[yie]+|streakfly+)\b/gi, "streakfly"],
  [/\b(?:zom\s*fli|zoomfly|zomfly|zoom\s*fli)\b/gi, "zoom fly"],
  [/\b(?:pegas|pegasuss)\b/gi, "pegasus"],
  [/\b(?:invincibl|invincibile|invinciblle)\b/gi, "invincible"],
  [/\b(?:vomerro)\b/gi, "vomero"],
  [/\b(?:speedgot|speed\s*got)\b/gi, "speedgoat"],
  [/\b(?:okley|oakly)\b/gi, "oakley"],
  [/\b(?:tshirt)\b/gi, "t-shirt"],
];

export function normalizeQueryTypos(text: string): string {
  let res = (text ?? "").trim();
  for (const [pat, repl] of TYPO_SUBSTITUTIONS) {
    res = res.replace(pat, repl);
  }
  return res.replace(/\s+/g, " ").trim();
}

export function detectSubBrand(text: string): [string, string] | null {
  const low = normalizeQueryTypos(text).toLowerCase();
  if (!low) return null;
  const keys = Object.keys(SUB_BRAND_TO_PARENT).sort((a, b) => b.length - a.length);
  for (const k of keys) {
    if (k === "s/lab" || k === "s-lab") {
      if (/\bs[/\-]lab\b/i.test(low)) return SUB_BRAND_TO_PARENT[k];
    } else if (new RegExp(`\\b${escapeRegExp(k)}\\b`, "i").test(low)) {
      return SUB_BRAND_TO_PARENT[k];
    }
  }
  return null;
}

const NEGATION_LEAD_RE = "(?:\\b(?:non|tranne|esclus[oiae]?|eccetto|senza|no|not|except|excluding|without)(?:\\s+(?:le|il|la|lo|i|gli|di|da|su|marche|brand|negozi|store))*)";

export function extractExcludedBrands(text: string): string[] {
  const norm = normalizeQueryTypos(text).toLowerCase();
  if (!norm) return [];
  const excluded: string[] = [];
  // Match negated spans like "non nike", "tranne nike e adidas", "escluso brooks o asics", "senza nike"
  const negSpanRe = /\b(?:non|tranne|esclus[oiae]?|eccetto|senza|no|not|except|excluding|without)\s+([^,.?!;]+)/gi;
  let m: RegExpExecArray | null;
  while ((m = negSpanRe.exec(norm)) !== null) {
    // Only inspect up to the first 6 words after the negation cue so unrelated later clauses aren't caught
    const span = m[1].trim().split(/\s+/).slice(0, 6).join(" ");
    for (const b of KNOWN_BRANDS) {
      const bLow = b.toLowerCase();
      if (bLow === "on") {
        if (/\bon\s+(?:running|cloud\w*)\b/i.test(span) && !excluded.includes("On")) excluded.push("On");
        continue;
      }
      if (new RegExp(`\\b${escapeRegExp(bLow)}\\b`, "i").test(span) && !excluded.includes(b)) {
        excluded.push(b);
      }
    }
  }
  return excluded;
}

function stripNegatedBrandMentions(norm: string, excludedBrands: string[]): string {
  if (excludedBrands.length === 0) return norm;
  let out = norm;
  for (const b of excludedBrands) {
    const bEsc = escapeRegExp(b.toLowerCase());
    out = out.replace(new RegExp(`${NEGATION_LEAD_RE}(?:\\s+(?:e|ed|o|od|n[eé]|,))?\\s+${bEsc}\\b`, "gi"), " ");
    out = out.replace(new RegExp(`\\b${bEsc}\\b`, "gi"), (match, offset) => {
      const before = out.slice(Math.max(0, offset - 35), offset);
      if (/\b(?:non|tranne|esclus[oiae]?|eccetto|senza|n[eé])\b/i.test(before)) return " ";
      return match;
    });
  }
  return out;
}

export function extractAllBrands(text: string): string[] {
  const rawNorm = normalizeQueryTypos(text).toLowerCase();
  const excluded = extractExcludedBrands(rawNorm);
  const norm = stripNegatedBrandMentions(rawNorm, excluded);
  const excludedLow = new Set(excluded.map((b) => b.toLowerCase()));
  const found: string[] = [];
  for (const b of KNOWN_BRANDS) {
    const bLow = b.toLowerCase();
    if (excludedLow.has(bLow)) continue;
    if (bLow === "on") {
      if (/\bon\s+(?:running|cloud\w*)\b/i.test(norm) && !found.includes("On")) found.push("On");
      continue;
    }
    if (new RegExp(`\\b${escapeRegExp(bLow)}\\b`, "i").test(norm) && !found.includes(b)) {
      found.push(b);
    }
  }
  const sub = detectSubBrand(norm);
  if (sub && !excludedLow.has(sub[0].toLowerCase()) && !found.includes(sub[0])) found.push(sub[0]);
  return found;
}

export function extractBrand(text: string, fallback?: string | null): string | null {
  const rawNorm = normalizeQueryTypos(text).toLowerCase();
  const excluded = extractExcludedBrands(rawNorm);
  const norm = stripNegatedBrandMentions(rawNorm, excluded);
  const excludedLow = new Set(excluded.map((b) => b.toLowerCase()));
  for (const b of KNOWN_BRANDS) {
    const bLow = b.toLowerCase();
    if (excludedLow.has(bLow)) continue;
    // Avoid matching short brand "on" inside ordinary words
    if (bLow === "on") {
      if (/\bon\s+(?:running|cloud\w*)\b/i.test(norm)) return "On";
      continue;
    }
    if (new RegExp(`\\b${escapeRegExp(bLow)}\\b`, "i").test(norm)) return b;
  }
  const sub = detectSubBrand(norm);
  if (sub && !excludedLow.has(sub[0].toLowerCase())) return sub[0];
  return fallback ?? null;
}

export function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const GENERIC_ENTITY_STOPWORDS = new Set([
  // Italian/English connectors & search verbs
  "il", "lo", "la", "i", "gli", "le", "un", "una", "uno", "di", "del", "della", "dei", "delle",
  "a", "al", "da", "dal", "in", "nel", "con", "su", "sul", "per", "tra", "fra", "e", "o", "ed", "od",
  "the", "of", "to", "from", "for", "with", "without", "and", "or", "in", "on", "at", "by",
  "cerca", "trova", "cerco", "vorrei", "mostrami", "mostramene", "fammi", "vedere", "filtra",
  "consiglia", "consigliami", "consiglio", "consigli", "migliori", "migliore", "miglior",
  "best", "good", "buona", "buone", "buono", "buoni", "ottimo", "ottima", "valide", "valido",
  "quale", "quali", "come", "cosa", "che", "chi", "dove", "quando", "perche", "perché", "quanto",
  "sono", "vanno", "bene", "posso", "puoi", "solo", "anche", "altri", "altre", "altro", "altra",
  "alternativa", "alternative", "opzioni", "esempi", "modelli", "modello", "offerta", "offerte",
  "prezzo", "prezzi", "sconto", "sconti", "economiche", "economici", "economico", "economica",
  "sotto", "sopra", "meno", "piu", "più", "fino", "max", "min", "massimo", "minimo", "entro",
  "budget", "euro", "eur", "taglia", "taglie", "numero", "misura", "size", "sizes", "eu", "us", "uk",
  "uomo", "uomini", "donna", "donne", "unisex", "men", "mens", "man", "women", "womens", "woman", "wmns",
  "ragazzo", "ragazza", "bambino", "bambini", "junior", "kids", "kid", "xs", "sm", "md", "lg", "xl", "xxl",
  "negozi", "negozio", "online", "confronta", "confronto", "differenza", "differenze", "vs", "versus",
  "invece", "quindi", "allora", "sempre", "ancora", "nuove", "nuova", "nuovo", "nuovi", "versione",
  // Sport & activity context words
  "running", "corsa", "correre", "trail", "allenamento", "allenamenti", "palestra", "fitness",
  "sport", "sportivo", "sportiva", "sportivi", "sportive", "gara", "maratona", "mezza", "10k", "5k", "21k", "42k",
  "strada", "asfalto", "sterrato", "montagna", "sentieri", "sentiero", "bosco", "pista", "campo",
  "principiante", "principianti", "iniziare", "intermedio", "avanzato", "livello", "runner", "runners",
  "ammortizzata", "ammortizzate", "ammortizzato", "ammortizzamento", "morbida", "morbide", "comoda", "comode",
  "reattiva", "reattive", "veloce", "veloci", "leggera", "leggere", "leggero", "leggeri", "stabile", "stabili",
  "traspirante", "traspiranti", "impermeabile", "impermeabili", "antipioggia", "pioggia", "waterproof",
  "termica", "termiche", "termico", "termici", "invernale", "invernali", "estivo", "estiva", "freddo", "caldo",
  "gtx", "gore", "tex", "carbonio", "piastra", "pronazione", "pronatori", "neutro", "neutra", "supporto",
  "ginocchia", "schiena", "fascite", "peso", "chili", "kg", "km", "tasche", "tasca", "zip", "mezza", "half",
  "hyrox", "crossfit", "pesi", "sollevamento", "funzionale", "triathlon", "ciclismo", "bici", "bicicletta",
  "calcio", "calcetto", "futsal", "tennis", "padel", "basket", "pallacanestro", "pallavolo", "volley",
  "nuoto", "nuotare", "piscina", "sci", "snowboard", "trekking", "hiking", "outdoor", "camminata",
  // Generic product-category nouns
  "scarpa", "scarpe", "shoe", "shoes", "sneaker", "sneakers", "calzature", "scarpini", "scarpino", "scarponi",
  "leggings", "legging", "leggins", "tights", "tight", "calzamaglia", "fuseaux", "pantacollant", "collant",
  "pantaloncini", "pantaloncino", "shorts", "short", "ciclisti", "bermuda", "sprinter",
  "pantaloni", "pantalone", "pants", "joggers",
  "maglia", "maglie", "maglietta", "magliette", "t-shirt", "shirt", "shirts", "tee", "top", "tops",
  "manica", "maniche", "lunga", "lunghe", "corta", "corte", "long", "sleeve", "sleeves", "longsleeve",
  "canotta", "canotte", "canottiera", "singlet", "tank", "smanicato", "smanicata", "sleeveless",
  "felpa", "felpe", "hoodie", "giacca", "giacche", "jacket", "jackets", "antivento", "windbreaker", "kway", "guscio",
  "calze", "calza", "calzini", "calzino", "calzettoni", "socks", "sock",
  "cappellino", "cappello", "berretto", "visiera", "scaldacollo", "guanti", "abbigliamento", "completo", "kit",
  "orologio", "orologi", "smartwatch", "sportwatch", "watch", "gps", "ciclocomputer", "computer",
  "fascia", "fasce", "cardio", "cardiofrequenzimetro", "sensore", "sensori", "toracica",
  "occhiali", "occhialini", "goggles", "costume", "costumi", "cuffia",
  "zaino", "zaini", "gilet", "borraccia", "borracce", "flask", "idratazione",
  "racchetta", "racchette", "pala", "rullo", "rulli", "gel", "barretta", "barrette", "integratori",
  // Descriptive / biomechanical / condition adjectives (never specific model names!)
  "delicata", "delicate", "delicato", "delicati", "sensibile", "sensibili", "pesante", "pesanti",
  "quotidiana", "quotidiane", "quotidiano", "quotidiani", "protettiva", "protettive", "protettivo", "protettivi",
  "ideale", "ideali", "perfetta", "perfette", "perfetto", "perfetti", "adatta", "adatte", "adatto", "adatti",
  "dolore", "dolori", "articolazione", "articolazioni", "tendinite", "tallonite", "plantare", "pianta", "larga", "largo", "stretta", "stretto", "piatto", "piatti", "appoggio",
  "esigenze", "livello", "cercando", "cerco", "voglio", "servono", "serve", "durata", "durano", "calzano", "vestono",
  // Filter / reset / store / promo filler words (never product entity tokens!)
  "rimuovi", "togli", "elimina", "azzera", "reset", "senza", "limite", "limiti", "filtro", "filtri",
  "tutti", "tutte", "qualsiasi", "spedizione", "gratuita", "gratis", "free", "shipping",
  "scontato", "scontata", "scontati", "scontate", "saldo", "saldi", "promo", "promozione",
  "cisalfa", "decathlon", "alltricks", "deporvillage", "misterrunning", "top4running",
  "maxisport", "sportspecialist", "tradeinn", "nencini", "intersport", "nonsolosport",
  "runningwarehouse", "sportler", "sportit", "bshopzone", "basketballstore",
  "store", "negozi", "negozio", "sito", "siti", "under", "below", "over", "above", "oltre",
  "almeno", "circa", "intorno", "fascia",
  // Colors
  "nero", "nera", "neri", "nere", "bianco", "bianca", "bianchi", "bianche", "blu", "azzurro", "azzurra",
  "rosso", "rossa", "rossi", "rosse", "verde", "verdi", "grigio", "grigia", "grigi", "grigie",
  "giallo", "gialla", "gialli", "gialle", "arancione", "arancioni", "rosa", "viola", "marrone", "marroni", "beige",
  "black", "white", "blue", "red", "green", "grey", "gray", "yellow", "orange", "pink", "purple", "brown",
  "lungo", "lunghi", "corto", "corti", "alto", "alta", "alti", "alte", "basso", "bassa",
  "compressione", "compression", "tecnica", "tecnico", "tecnici", "tecniche", "pro",
  "non", "tranne", "escluso", "esclusa", "esclusi", "escluse", "eccetto", "senza", "ne", "né",
  "economiche", "economici", "economico", "economica", "convenienti", "conveniente",
  "costose", "costosi", "costoso", "costosa", "care", "cari", "basso", "bassi", "alto", "alti",
  "ordina", "ordinate", "ordinati", "crescente", "decrescente", "piastra", "carbonio", "carbon", "cappuccio",
]);

export const KNOWN_STORES: Array<{ id: string; label: string; regex: RegExp }> = [
  { id: "cisalfa", label: "Cisalfa Sport", regex: /\b(?:cisalfa(?:\s+sport)?)\b/i },
  { id: "decathlon", label: "Decathlon", regex: /\b(?:decathlon)\b/i },
  { id: "alltricks", label: "Alltricks", regex: /\b(?:alltricks)\b/i },
  { id: "misterrunning", label: "Mister Running", regex: /\b(?:mister\s*running)\b/i },
  { id: "deporvillage", label: "Deporvillage", regex: /\b(?:deporvillage)\b/i },
  { id: "top4running", label: "Top4Running", regex: /\b(?:top\s*4\s*running|top4running)\b/i },
  { id: "maxisport", label: "Maxi Sport", regex: /\b(?:maxi\s*sport)\b/i },
  { id: "df_sportspecialist", label: "DF Sport Specialist", regex: /\b(?:df\s*sport(?:\s*specialist)?|sport\s*specialist)\b/i },
  { id: "tradeinn", label: "Tradeinn", regex: /\b(?:tradeinn|runnerinn|trekkinn|bikeinn)\b/i },
  { id: "nencini", label: "Nencini Sport", regex: /\b(?:nencini(?:\s+sport)?)\b/i },
  { id: "intersport", label: "Intersport", regex: /\b(?:intersport(?:\s+italia)?)\b/i },
  { id: "nonsolosport", label: "NonSoloSport", regex: /\b(?:non\s*solo\s*sport|nonsolosport)\b/i },
  { id: "runningwarehouse", label: "Running Warehouse", regex: /\b(?:running\s*warehouse)\b/i },
  { id: "sportler", label: "Sportler", regex: /\b(?:sportler)\b/i },
  { id: "sportit", label: "SportIT", regex: /\b(?:sportit|sport\s*it)\b/i },
  { id: "tennis_point", label: "Tennis-Point", regex: /\b(?:tennis[\s-]*point)\b/i },
  { id: "bshopzone", label: "Bshopzone", regex: /\b(?:bshopzone)\b/i },
  { id: "basketballstore", label: "Basketball Store", regex: /\b(?:basketball\s*store)\b/i },
];

export function extractExcludedStores(text: string): Array<{ id: string; label: string }> {
  const low = (text ?? "").toLowerCase();
  if (!low.trim()) return [];
  const excluded: Array<{ id: string; label: string }> = [];
  const negSpanRe = /\b(?:non|tranne|esclus[oiae]?|eccetto|senza|no|not|except|excluding)\s+([^,.?!;]+)/gi;
  let m: RegExpExecArray | null;
  while ((m = negSpanRe.exec(low)) !== null) {
    const span = m[1].trim().split(/\s+/).slice(0, 6).join(" ");
    for (const st of KNOWN_STORES) {
      if (st.regex.test(span) && !excluded.some((e) => e.id === st.id)) {
        excluded.push({ id: st.id, label: st.label });
      }
    }
  }
  return excluded;
}

export function extractStoreFilter(text: string): { id: string; label: string } | null {
  const low = (text ?? "").toLowerCase();
  if (!low.trim()) return null;
  const excludedIds = new Set(extractExcludedStores(low).map((s) => s.id));
  for (const st of KNOWN_STORES) {
    if (excludedIds.has(st.id)) continue;
    if (st.regex.test(low)) return { id: st.id, label: st.label };
  }
  return null;
}

/**
 * Extracts specific model / sub-brand / generation tokens from a query (e.g. ["forerunner", "165"] or ["zoom", "fly", "6"]).
 * Returns [] for pure category/brand queries like "leggins under armour da corsa".
 */
export function extractSpecificEntityTokens(query: string, brand?: string | null): string[] {
  if (!query || !query.trim()) return [];
  let t = normalizeQueryTypos(query)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  t = t.replace(/\bs[/\-]lab\b/g, " lab ");
  // Remove ALL price, budget, range, discount & measurement/unit constraints (including € before or after number!)
  t = t.replace(/\b(?:tra|da)\s*(?:€\s*)?\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?\s*(?:e|a|-)\s*(?:€\s*)?\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?/gi, " ");
  t = t.replace(/(?:sotto\s*(?:i|ai|gli|le|di|dei)?|al\s+di\s+sotto\s*(?:di|dei|degli)?|sopra\s*(?:i|ai|gli|le|di|dei)?|oltre\s*(?:i|ai|gli|le)?|meno\s*di|pi[uù]\s*di|non\s+(?:oltre|pi[uù]\s*di)|fino\s*a(?:i|gli|lle)?|entro\s*(?:i|ai|gli)?|budget\s*(?:massimo|max|di|sotto)?|prezzo\s*(?:massimo|max|minimo|min|sotto|sopra)?|al\s+massimo|massimo|max|minimo|min|almeno|under|below|over|above|<=?|>=?)\s*(?:€\s*)?\d+(?:[.,]\d+)?\s*(?:€|euro|eur|%)?/gi, " ");
  t = t.replace(/€\s*\d+(?:[.,]\d+)?/g, " ");
  t = t.replace(/\b\d+(?:[.,]\d+)?\s*(?:€|euro|eur|%)/gi, " ");
  t = t.replace(/\b\d+(?:[.,]\d+)?\s*(?:km|kg|chili|g|gr|mm|cm|l|lt|ml|min|h)\b/gi, " ");
  t = t.replace(/\b\d+(?:[.,]\d+)?(?:km|kg|ml|mm|cm|gr)\b/gi, " ");
  // Remove discount percentages like "-30%" or "sconto 20%"
  t = t.replace(/(?:sconto\s*(?:almeno|minimo|di|del)?\s*)?-?\d+(?:[.,]\d+)?\s*%/gi, " ");
  // Remove size constraints
  t = t.replace(/\b(?:taglia|taglie|numero|num\.?|n\.?|misura|misure|size|eu|us|uk|tg\.?)\s*(?:\d{2}(?:[.,]\d|\s+[12]\/[23])?|[23]?x?[sml]{1,2})\b/gi, " ");
  t = t.replace(/(?<![\d.,])\b(?:3[5-9]|4[0-9])[.,](?:5|3|7|2|8)\b/g, " ");
  t = t.replace(/\b(?:1\s*\/\s*[24]\s*(?:di\s+)?zip|2\s*in\s*1|2in1|calcio\s*a\s*[57])\b/g, " ");
  // Remove store names so "su Cisalfa" or "da Mister Running" never become model tokens
  for (const st of KNOWN_STORES) {
    t = t.replace(st.regex, " ");
  }

  const brandToks = new Set<string>();
  const subKeys = new Set(Object.keys(SUB_BRAND_TO_PARENT));
  if (brand) {
    for (const bt of brand.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
      if (bt !== "the" && !subKeys.has(bt)) brandToks.add(bt);
    }
  }
  for (const kb of KNOWN_BRANDS) {
    const kbLow = kb.toLowerCase();
    if (kbLow.length >= 3 && new RegExp(`\\b${escapeRegExp(kbLow)}\\b`, "i").test(t)) {
      for (const bt of kbLow.match(/[a-z0-9]+/g) ?? []) {
        if (bt !== "the" && !subKeys.has(bt)) brandToks.add(bt);
      }
    }
  }

  const rawTokens = t.match(/\b[a-z0-9]{2,}\b|\b\d+\b/g) ?? [];
  const out: string[] = [];
  for (const tok of rawTokens) {
    if (GENERIC_ENTITY_STOPWORDS.has(tok) || brandToks.has(tok)) continue;
    if (!out.includes(tok)) out.push(tok);
  }
  return out;
}

/**
 * Detects an EXPLICIT product type ONLY when the text contains a concrete garment, footwear,
 * device, equipment noun, or unmistakable model name — NEVER from standalone activity words
 * like "da corsa", "per running", "per trail", "per maratona" (which refine a previous product
 * type during follow-ups instead of switching categories!).
 */
export function detectExplicitProductType(rawText: string): ProductType | null {
  const t = normalizeQueryTypos(rawText).toLowerCase();
  if (!t) return null;

  // 1. Explicit apparel & accessories (most specific first!)
  if (/\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)+|magli[ae]\s*(?:a\s*)?manic(?:a|he)\s*lung(?:a|he)+|magli[ae]\s*termic(?:a|he)|intimo\s*termico|1\/2\s*zip|1\/4\s*zip|half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip|base[\s-]*layer|strato\s*base)\b/.test(t)) {
    return "long_sleeve_top";
  }
  if (/\b(canott[ae]|canottier[ae]|singlet|tank\s*top|sleeveless|smanicat[aoe])\b/.test(t)) {
    return "singlet_top";
  }
  if (/\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae]+|t[\s-]*shirt|magliett[ae]|magli[ae](?!\s*(?:cinturin|orolog)))\b/.test(t)) {
    return "short_sleeve_top";
  }
  if (/\b(felp[ae]|hoodie|sweatshirt|pile\b|fleece\b|maglion[ei]|pullover)\b/.test(t)) {
    return "long_sleeve_top";
  }
  if (/\b(giacc(?:a|he)|jacket|rain\s*jacket|antivento|windbreaker|windproof|k[\s-]*way|gilet\s*antivento|guscio|shell\s*jacket|anorak|antipioggia|piumin[oi])\b/.test(t)) {
    return "jacket";
  }
  // Leggings / Tights / Calzamaglia MUST be distinguished from Shorts & Long Pants!
  if (/\b(leggings?|leggins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant)\b/.test(t)) {
    return "leggings_tights";
  }
  if (!/\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae])\b/.test(t) &&
      /\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|ciclisti|sprinter|bermuda|coscial[ei])\b/.test(t)) {
    return "shorts";
  }
  if (/\b(pantalon[ie]|pants|joggers?|track\s*pants?)\b/.test(t)) {
    return "pants";
  }
  if (/\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b/.test(t)) {
    return "socks";
  }
  if (/\b(cappellin[oi]|cappell[oi]|berrett[oi]|visier[ae]|fascia\s*testa|scaldacollo|guant[oi]|beanie|visor|headband|gloves|neck\s*gaiter|running\s*cap|running\s*hat)\b/.test(t)) {
    return "headwear";
  }

  // 2. Tech & Hardgoods
  if (/\b(fasci[ae]\s*cardio(?:frequenzimetr[oi])?|fascia\s*hrm|fascia\s*toracica|sensore\s*(?:cardio|cardiaco|frequenza\s*cardiaca|hr)|heart\s*rate\s*(?:monitor|strap|sensor)|chest\s*strap|polar\s*(?:h10|h9|verity|oh1)|garmin\s*hrm|hrm[\s-]*(?:pro|dual|200|600|fit|swim)|wahoo\s*(?:trackr|tickr)|coros\s*(?:heart\s*rate|fascia\s*cardio))\b/.test(t)) {
    return "heart_rate_monitor";
  }
  if (/\b(ciclocomputer|bike\s*computer|contachilometri|contatore\s*(?:bici|gps)?|garmin\s*edge|\bedge\s*(?:130|530|540|830|840|1030|1040|1050|explore|mtb)\b|wahoo\s*elemnt|bryton|igpsport|hammerhead\s*karoo)\b/.test(t)) {
    return "bike_computer";
  }
  if (/\b(orologi[o]?|smartwatch|sportwatch|cardiofrequenzimetro|garmin|forerunner|fenix|instinct|epix|venu|vivoactive|coros|suunto|polar\s*(?:vantage|pacer|grit|ignite)|amazfit)\b/.test(t)) {
    return "gps_watch";
  }
  if (/\bgps\b/.test(t) && !/\b(bici|ciclismo|mtb|gravel|manubrio|ciclocomputer|edge)\b/.test(t)) {
    return "gps_watch";
  }
  if (/\b(occhialin[oi]|occhial[ie]\s*(?:da\s*)?nuoto|swim(?:ming)?\s*goggles|goggles|swimsuit|cuffi[ae]\s*(?:da\s*)?nuoto|costum[ei]\s*(?:da\s*)?(?:nuoto|bagno)|pinn[ae]\s*(?:da\s*)?nuoto)\b/.test(t)) {
    return "swim";
  }
  if (/\b(occhial[ie]|sunglasses|eyewear|oakley|sutro|radar\s*ev|jawbreaker|rudy\s*project|bliz)\b/.test(t)) {
    return "eyewear";
  }
  if (/\b(gilet\s*(?:idratazione|trail|running)|(?:trail|running|hydration)\s*vest|\bvest\b|zain[oi]|backpack|hydration\s*pack|soft\s*flask|flask|borracc(?:ia|e|ie)|water\s*bottle|sacca\s*idrica|active\s*skin|adv\s*skin|camelbak)\b/.test(t)) {
    return "hydration";
  }
  if (/\b((?:racchett[ae]|racket|racquet)\s*(?:da\s*)?tennis|tennis\s*(?:racket|racquet)|pure\s*drive|pure\s*aero|yonex\s*(?:ezone|vcore|percept)|wilson\s*(?:blade|pro\s*staff|clash|ultra)|head\s*(?:speed|radical|gravity|extreme\s*mp)|tecnifibre\s*t[\s-]*fight)\b/.test(t)) {
    return "tennis_racket";
  }
  if (/\b(scarpon[ei]\s*(?:da\s*)?sci|mascher[ae]\s*(?:da\s*)?sci|casc[oh]\s*(?:da\s*)?sci|tavol[ae]\s*snowboard|snowboard|scialpinismo|sci\s*alpino|atomic\s*(?:hawx|redster|bent)|nordica\s*(?:speedmachine|promachine)|rossignol\s*(?:hero|alltrack))\b/.test(t)) {
    return "winter_sports";
  }
  if (/\b(racchett[ae]|padel\s*(?:racket|racquet)|pala\s*padel|bullpadel|nox\s*at10)\b/.test(t) && !/\b(scarp[ae]|shoes?)\b/.test(t)) {
    return "padel_racket";
  }
  if (/\b(rull[oi]|smart\s*trainer|wahoo\s*kickr|tacx\s*(?:flux|neo))\b/.test(t)) {
    return "smart_trainer";
  }
  if (/\b(gel\s*(?:energetic[oi]|isotonic[oi]|enervit|maurten|sis)|energy\s*gels?|electrolytes?|maltodestrin[ae]|barrett[ae]|integrator[ei]|sali\s*minerali|enervit|maurten|namedsport)\b/.test(t)) {
    return "nutrition";
  }

  // 3. Sport-specific footwear (explicit footwear nouns or iconic shoe lines)
  if (/\b(scarp[ae]\s*(?:da\s*)?calcio|scarp[ae]\s*(?:da\s*)?calcetto|football\s*boots?|soccer\s*cleats?|scarpin[oi]|mercurial|superfly|predator|tiempo|phantom|copa\s*pure|top\s*sala|top\s*flex|magnetico)\b/.test(t)) {
    return "football_boots";
  }
  if (/\b(scarp[ae]\s*(?:da\s*)?basket|lebron|kobe|giannis|luka|caitlin|sabrina|kd\s*\d+|harden|dame)\b/.test(t) &&
      !/\b(magli[ae]|jersey|canott[ae]|pantaloncin[oi]|shorts?|calz[ae]|pallon[ei]|canestro)\b/.test(t)) {
    return "basketball_shoes";
  }
  if (/\b(scarp[ae]\s*(?:da\s*)?tennis|gel[\s-]*resolution|court\s*ff|dedicate|nikecourt|barricade)\b/.test(t) &&
      !/\b(racchett[ae]|racket|racquet|pallin[ae]|abbigliamento|pantaloncin[oi]|shorts?|magli[ae])\b/.test(t)) {
    return "tennis_shoes";
  }
  if (/\b(scarp[ae]\s*(?:da\s*)?(?:pallavolo|volley)|sky\s*elite|metarise|wave\s*lightning|wave\s*momentum|netburner)\b/.test(t) &&
      !/\b(ginocchier[ae]|pallon[ei]|magli[ae]|pantaloncin[oi]|manicotti)\b/.test(t)) {
    return "volleyball_shoes";
  }

  // 4. Explicit Trail or Road Shoe nouns / iconic shoe models
  if (/\b(scarp[ae]\s*(?:da\s*)?trail|trail\s*shoes?|speedgoat|cascadia|trabuco|speedcross|ultra\s*raptor|peregrine|bushido|hierro|mafate|tecton|zegama|wildhorse|terrex\s*agravic)\b/.test(t) &&
      !/\b(zain[oi]|gilet|vest|backpack|pack|flask|bottle|giacc[ae]|jacket|pantalon|pants|shorts?|tights?|magli|shirt|tee|orologi|watch|poles|bastoncini|gel|belt|marsupio|hat|cap|gloves|socks)\b/.test(t)) {
    return "trail_shoes";
  }
  if (/\b(scarp[ae]|shoes?|sneakers?|calzatur[ae]|zoom\s*fly|pegasus|vomero|alphafly|vaporfly|streakfly|invincible|structure|nimbus|kayano|cumulus|novablast|superblast|metaspeed|clifton|bondi|mach|cielo|rincon|glycerin|ghost|hyperion|adrenaline|endorphin|triumph|ride|tempus|deviate|velocity|magmax|adizero\s*(?:adios|boston|takumi|sl|evo|prime|dropset)|dropset|metcon|nano|ultraboost|supernova|cloudmonster|cloudsurfer|cloudboom|cloudrunner|cloudstratus|wave\s*rider|wave\s*rebellion|wave\s*sky|fresh\s*foam|fuelcell|1080|rebel|infinite\s*(?:elite|pro))\b/.test(t)) {
    return "shoes";
  }
  return null;
}

export function detectSingleProductType(rawText: string): ProductType | null {
  const explicit = detectExplicitProductType(rawText);
  if (explicit) return explicit;
  const t = normalizeQueryTypos(rawText).toLowerCase();
  if (!t) return null;

  // Activity-only fallback defaults (used ONLY for fresh queries with no prior product type!)
  if (/\b(nuot[ao]|nuotare|piscina)\b/.test(t)) return "swim";
  if (/\bpadel\b/.test(t) && !/\b(scarp[ae]|shoes?)\b/.test(t)) return "padel_racket";
  if (/\b(calcetto|futsal|calcio\s*a\s*[57])\b/.test(t) && !/\b(magli[ae]|kit|pantaloncin[oi]|pallon[ei]|guant[oi])\b/.test(t)) {
    return "football_boots";
  }
  if (/\b(basket|basketball|pallacanestro)\b/.test(t) && !/\b(magli[ae]|jersey|canott[ae]|pantaloncin[oi]|shorts?|calz[ae]|pallon[ei])\b/.test(t)) {
    return "basketball_shoes";
  }
  if (/\b(tennis|terra\s*battuta)\b/.test(t) && !/\b(racchett[ae]|racket|racquet|pallin[ae]|abbigliamento|pantaloncin[oi]|shorts?|magli[ae])\b/.test(t)) {
    return "tennis_shoes";
  }
  if (/\b(pallavolo|volley|volleyball)\b/.test(t) && !/\b(ginocchier[ae]|pallon[ei]|magli[ae]|pantaloncin[oi]|manicotti)\b/.test(t)) {
    return "volleyball_shoes";
  }
  if (/\b(trail|sterrato|montagna|sentier[oi])\b/.test(t) &&
      !/\b(zain[oi]|gilet|vest|backpack|pack|flask|bottle|giacc[ae]|jacket|pantalon|pants|shorts?|tights?|magli|shirt|tee|orologi|watch|poles|bastoncini|gel|belt|marsupio|hat|cap|gloves|socks)\b/.test(t)) {
    return "trail_shoes";
  }
  if (/\b(running|corsa|correre|maratona|mezza\s*maratona|ammortizzat[ae]|pronazione|supinazione|hyrox)\b/.test(t) &&
      !/\b(abbigliamento|completo|kit|accessori|orologi[o]?|smartwatch|watch|ciclocomputer|vest|backpack|pack|jacket|shirt|shorts|tights|gel|belt|marsupio|flask|bottle|poles)\b/.test(t)) {
    return "shoes";
  }
  return null;
}

export function detectProductType(query: string, contextQuery?: string | null): ProductType | null {
  const direct = detectSingleProductType(query);
  if (direct) return direct;
  if (contextQuery && contextQuery.trim()) {
    const turns = contextQuery.split(">>").map((s) => s.trim()).filter(Boolean).reverse();
    for (const turn of turns) {
      const pt = detectSingleProductType(turn);
      if (pt) return pt;
    }
  }
  return null;
}

export function normalizeProductTypeGroup(pt: ProductType | null): string | null {
  if (!pt) return null;
  if (pt === "long_sleeve_top" || pt === "short_sleeve_top" || pt === "singlet_top") return "top";
  if (pt === "trail_shoes") return "shoes";
  return pt;
}

export function isBroadeningFollowUp(query: string): boolean {
  const t = (query ?? "").trim().toLowerCase();
  if (!t) return false;
  return /\b(alternativ[aeio]|altri\s+modelli|altre\s+opzioni|altri\s+esempi|pi[uù]\s+esempi|mostramene\s+altr[ioe]|modelli\s+(?:di|per|con)|confronta|confronto|\bvs\b|differenz[ae]|top\s+di\s+gamma|fascia\s+(?:alta|superiore))\b/.test(t);
}

export function mapProductTypeToCategory(pt: ProductType | null): string | null {
  switch (pt) {
    case "leggings_tights":
    case "shorts":
    case "pants":
      return "pants";
    case "long_sleeve_top":
    case "short_sleeve_top":
    case "singlet_top":
    case "top":
      return "top";
    case "jacket":
      return "jacket";
    case "socks":
      return "socks";
    case "headwear":
      return "apparel";
    case "heart_rate_monitor":
      return "sensor";
    case "bike_computer":
    case "smart_trainer":
      return "cycling";
    case "gps_watch":
      return "gps_watch";
    case "eyewear":
      return "eyewear";
    case "hydration":
      return "hydration";
    case "swim":
      return "swim";
    case "padel_racket":
      return "padel";
    case "tennis_racket":
      return "tennis";
    case "football_boots":
      return "football_boots";
    case "basketball_shoes":
      return "basketball";
    case "tennis_shoes":
      return "tennis";
    case "volleyball_shoes":
    case "shoes":
      return "running_shoes";
    case "trail_shoes":
      return "trail_running";
    case "winter_sports":
      return "winter_sports";
    case "nutrition":
      return "nutrition";
    default:
      return null;
  }
}

export function getBlockedCategoriesForProductType(pt: ProductType | null): string[] | null {
  if (!pt) return null;
  switch (pt) {
    case "shoes":
    case "trail_shoes":
      return [
        "gps_watch", "eyewear", "hydration", "nutrition", "cycling",
        "top", "jacket", "pants", "socks", "underwear", "swim", "football_boots",
        "bag", "case", "gloves", "apparel", "strap", "mount", "sensor", "racket", "padel",
        "gear", "pack", "winter_sports", "trainer", "non_sport",
      ];
    case "leggings_tights":
    case "shorts":
    case "pants":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "top", "jacket", "socks",
        "strap", "mount", "case", "sensor", "racket", "padel", "swim", "winter_sports",
        "gear", "pack", "cycling", "trainer", "non_sport",
      ];
    case "long_sleeve_top":
    case "short_sleeve_top":
    case "singlet_top":
    case "top":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "padel", "cycling", "pants", "jacket",
        "socks", "underwear", "swim", "bag", "gloves", "strap", "mount", "case",
        "racket", "sensor", "winter_sports", "gear", "pack", "trainer", "non_sport",
      ];
    case "jacket":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "pants", "socks", "strap", "mount", "case", "sensor", "racket",
        "gear", "pack", "swim", "padel", "trainer", "non_sport",
      ];
    case "socks":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants",
        "gps_watch", "eyewear", "padel", "cycling", "hydration", "nutrition", "strap", "mount", "case",
        "gear", "racket", "swim", "trainer", "non_sport",
      ];
    case "headwear":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "top", "jacket", "pants", "socks",
        "gps_watch", "eyewear", "padel", "cycling", "hydration", "nutrition", "strap", "mount", "case",
        "racket", "sensor", "swim", "trainer", "non_sport",
      ];
    case "gps_watch":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks", "apparel",
        "eyewear", "nutrition", "padel", "case", "strap", "mount", "cycling",
        "bag", "hydration", "gloves", "underwear", "swim", "racket", "sensor",
        "gear", "pack", "football_boots", "winter_sports", "trainer", "non_sport",
      ];
    case "heart_rate_monitor":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "top", "jacket",
        "pants", "socks", "apparel", "eyewear", "nutrition", "padel", "hydration", "swim", "racket", "case", "mount",
        "gear", "pack", "winter_sports", "non_sport",
      ];
    case "bike_computer":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks", "apparel",
        "eyewear", "nutrition", "padel", "case", "strap", "mount", "gps_watch", "sensor",
        "gear", "pack", "swim", "football_boots", "winter_sports", "non_sport",
      ];
    case "eyewear":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "padel", "nutrition", "hydration", "strap", "mount", "sensor",
        "gear", "pack", "football_boots", "trainer", "non_sport",
      ];
    case "hydration":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "eyewear", "padel", "nutrition", "strap", "mount", "sensor",
        "football_boots", "racket", "swim", "trainer", "non_sport",
      ];
    case "padel_racket":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "eyewear", "gps_watch", "nutrition", "hydration", "strap", "mount", "sensor",
        "gear", "pack", "football_boots", "cycling", "swim", "winter_sports", "trainer", "non_sport",
      ];
    case "tennis_racket":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "eyewear", "gps_watch", "nutrition", "hydration", "strap", "mount", "sensor",
        "gear", "pack", "football_boots", "cycling", "swim", "winter_sports", "trainer", "non_sport",
      ];
    case "football_boots":
      return [
        "top", "jacket", "pants", "socks", "gps_watch", "eyewear", "hydration",
        "nutrition", "padel", "cycling", "swim", "case", "strap", "mount", "sensor",
        "gear", "racket", "winter_sports", "trainer", "non_sport",
      ];
    case "basketball_shoes":
    case "tennis_shoes":
    case "volleyball_shoes":
      return [
        "top", "jacket", "pants", "socks", "apparel", "gps_watch", "eyewear", "hydration",
        "nutrition", "padel", "cycling", "swim", "football_boots", "case", "strap", "mount", "sensor",
        "gear", "pack", "racket", "winter_sports", "trainer", "non_sport",
      ];
    case "swim":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "padel", "cycling", "nutrition", "hydration", "racket",
        "gear", "football_boots", "winter_sports", "trainer", "non_sport",
      ];
    case "winter_sports":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "swim", "padel", "racket",
        "cycling", "nutrition", "sensor", "gps_watch", "non_sport",
      ];
    case "nutrition":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "top", "jacket", "pants", "socks",
        "apparel", "gps_watch", "eyewear", "padel", "racket", "cycling", "swim", "winter_sports", "strap", "mount", "case", "non_sport",
      ];
    case "smart_trainer":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "top", "jacket", "pants", "socks",
        "apparel", "eyewear", "padel", "racket", "swim", "nutrition", "hydration", "winter_sports", "non_sport",
      ];
    default:
      return null;
  }
}

// ============================================================================
// Image & Size Sanitization
// ============================================================================

const PLACEHOLDER_IMAGE_RE = /(?:no[-_]?image|placeholder|default[-_]?img|missing[-_]?image|blank\.(?:jpg|png|gif)|\/1x1\.|spacer\.)/i;

export function isValidImageUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  const trimmed = url.trim();
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) return false;
  if (PLACEHOLDER_IMAGE_RE.test(trimmed)) return false;
  return true;
}

export function normalizeSize(raw: string): string {
  return raw
    .trim()
    .toUpperCase()
    .replace(",", ".")
    .replace(/^EU\s+/, "")
    .replace(/\s+EU$/, "")
    .replace(".1/2", ".5")
    .replace(" 1/2", ".5")
    .replace(" 2/3", ".5")
    .replace(" 1/3", ".5")
    .replace(".2/3", ".5")
    .replace(".1/3", ".5");
}

const EU_TO_US_MEN: Record<string, string> = {
  "39": "6.5", "40": "7", "40.5": "7.5", "41": "8", "42": "8.5", "42.5": "9",
  "43": "9.5", "44": "10", "44.5": "10.5", "45": "11", "45.5": "11.5", "46": "12", "47": "12.5", "47.5": "13",
};
const EU_TO_US_WOMEN: Record<string, string> = {
  "36": "5.5", "36.5": "6", "37.5": "6.5", "38": "7", "38.5": "7.5", "39": "8",
  "40": "8.5", "40.5": "9", "41": "9.5", "42": "10", "42.5": "10.5",
};

function buildSizeCandidates(required: string, isFemale: boolean): Set<string> {
  const norm = normalizeSize(required);
  const cands = new Set<string>([norm]);
  const map = isFemale ? EU_TO_US_WOMEN : EU_TO_US_MEN;
  if (map[norm]) cands.add(map[norm]);
  for (const [eu, us] of Object.entries(map)) {
    if (us === norm) cands.add(eu);
  }
  return cands;
}

/**
 * Generates raw jsonb string variants (dot/comma/fraction/EU/US/case) for fast GIN-indexed
 * `o.available_sizes ?| size_candidates` matching inside Postgres!
 */
export function buildSizeVariantsForSql(required: string | null | undefined, gender?: string | null): string[] | null {
  if (!required || !required.trim()) return null;
  const gLow = (gender ?? "").toLowerCase();
  const cands = new Set<string>();
  // When gender is unspecified/unisex, accept both Men & Women US mappings; JS sizeMatches refines per-product!
  if (gLow.includes("donna")) {
    for (const s of buildSizeCandidates(required, true)) cands.add(s);
  } else if (gLow.includes("uomo")) {
    for (const s of buildSizeCandidates(required, false)) cands.add(s);
  } else {
    for (const s of buildSizeCandidates(required, false)) cands.add(s);
    for (const s of buildSizeCandidates(required, true)) cands.add(s);
  }

  const expanded = new Set<string>();
  for (const s of cands) {
    expanded.add(s);
    expanded.add(s.toLowerCase());
    expanded.add(`EU ${s}`);
    expanded.add(`${s} EU`);
    if (s.endsWith(".5")) {
      const base = s.slice(0, -2);
      expanded.add(`${base},5`);
      expanded.add(`${base} 1/2`);
      expanded.add(`${base}.1/2`);
      expanded.add(`${base} 2/3`);
      expanded.add(`${base} 1/3`);
      expanded.add(`${base}.2/3`);
      expanded.add(`${base}.1/3`);
      expanded.add(`EU ${base},5`);
    } else if (/^\d+$/.test(s)) {
      expanded.add(`${s}.0`);
      expanded.add(`${s},0`);
    }
  }
  return Array.from(expanded);
}

function sizeMatches(
  available: string[] | null | undefined,
  required?: string | null,
  isFemale = false,
): boolean {
  if (!required || !required.trim()) return true;
  if (!available || available.length === 0) return false;
  const cands = buildSizeCandidates(required, isFemale);
  return available.some((s) => cands.has(normalizeSize(String(s))));
}

// ============================================================================
// Output Types
// ============================================================================

export interface OfferOut {
  store_id: string;
  store_name: string;
  product_id: string | null;
  title: string;
  brand: string | null;
  price: number;
  original_price: number | null;
  discount_pct: number | null;
  savings: number | null;
  url: string;
  image_url: string | null;
  gallery_images: string[] | null;
  available_sizes: string[];
  variant_name: string | null;
  in_stock: boolean;
  shipping_cost: number;
  total_price: number;
  is_free_shipping: boolean;
  shipping_label: string;
  free_shipping_threshold: number | null;
  courier: string | null;
}

export interface MatchedProductOut {
  id: string;
  canonical_name: string;
  brand: string | null;
  image_url: string | null;
  gallery_images: string[] | null;
  gender: string | null;
  offers: OfferOut[];
  best_price: number | null;
  highest_price: number | null;
  cross_store_savings: number | null;
}

interface InternalProduct extends MatchedProductOut {
  category: string | null;
  available_sizes: string[];
  lexical_score: number;
  semantic_similarity: number;
  rrf_score: number;
  relevance_score: number;
  matched_entity_count: number;
  matched_digit_exact: boolean;
}

interface RawOfferRow {
  id: string;
  product_id: string | null;
  store_id: string;
  store_name: string;
  raw_title: string;
  current_price: number;
  original_price: number | null;
  discount_pct: number | null;
  product_url: string;
  image_url: string | null;
  gallery_images: string[] | null;
  available_sizes: string[] | null;
  shipping_cost: number | null;
  free_shipping_threshold: number | null;
  courier: string | null;
  products?: {
    id?: string;
    canonical_name?: string;
    brand?: string | null;
    category?: string | null;
    gender?: string | null;
    image_url?: string | null;
    gallery_images?: string[] | null;
  } | null;
}

interface RpcProductRow {
  id: string;
  canonical_name: string;
  brand: string | null;
  category: string | null;
  gender: string | null;
  image_url: string | null;
  gallery_images: string[] | null;
  lexical_score: number;
  offers: Array<{
    id: string;
    product_id: string | null;
    store_id: string;
    store_name: string;
    raw_title: string;
    current_price: number;
    original_price: number | null;
    discount_pct: number | null;
    product_url: string;
    image_url: string | null;
    gallery_images: string[] | null;
    available_sizes: string[] | null;
    shipping_cost: number | null;
    free_shipping_threshold: number | null;
    courier: string | null;
  }>;
}

// ============================================================================
// Hard Product-Type & Quality Compatibility Gating
// ============================================================================

const GLOBAL_JUNK_RE = /\b(furygan|dainese|alpinestars|d3o\s*ghost|protezion[ei]\s+gomit|vetus|scambiatore\s+calore|garlando|calciobalilla|biliardino|barbie|bambol[ae]|panzerglass|vetro\s*temp[ea]?rato|pellicol[ae]|idrogel|hydrogel|screen\s*protector|protezion[ei]\s*(?:lo\s*)?schermo|sportenzia|second\s*hand|ricondizionat[ao]|trixie|pettorina\s+cani|cuccia|guinzagli[oi]|victorinox|invertika|birkenstock|chris\s*king|nothreadset|griplock|schwalbe)\b/i;

const KIDS_MARKER_RE = /(?:^|\s|\(|–|-)(?:junior|jr|bambin[oi]|kids?|youth|ragazz[oi](?:\/a)?)(?:\s|$|\)|\/)/i;

const BIKE_HARDWARE_RE = /\b(serie\s+sterzo|sistema\s+sterzo|headset|attacco\s+manubrio|supporto\s+manubrio|movimento\s+centrale|pignoni|guarnitura|pastiglie|disco\s+freno|forcella|tubeless|pedali?|copertone|pneumatic[oi]|cuffi[ae]\s+integrat[ae]|is42)\b/i;

function isApparelOnlySizes(sizes: string[]): boolean {
  if (!sizes || sizes.length === 0) return false;
  const hasShoeNum = sizes.some((s) => /\b(3[4-9]|4[0-9]|5[0-2])\b/.test(String(s)));
  if (hasShoeNum) return false;
  return sizes.every((s) =>
    /^(?:[23]?x?[sml]|unica|one\s*size|os|xs\/s|s\/m|m\/l|l\/xl)$/i.test(String(s).trim())
  );
}

export function isProductCompatible(
  prod: {
    canonical_name: string;
    brand: string | null;
    category?: string | null;
    gender?: string | null;
    best_price: number | null;
    available_sizes?: string[];
    offers: Array<{ title: string; url: string }>;
  },
  productType: ProductType | null,
  rawQuery = "",
): boolean {
  const cat = (prod.category ?? "").toLowerCase().trim();
  const brand = (prod.brand ?? "").toLowerCase().trim();
  const cname = (prod.canonical_name ?? "").toLowerCase();
  const pGender = (prod.gender ?? "").toLowerCase().trim();
  const offerText = prod.offers.slice(0, 4).map((o) => `${o.title} ${o.url}`).join(" ").toLowerCase();
  const fullText = `${cname} ${brand} ${offerText}`;
  const qLow = normalizeQueryTypos(rawQuery).toLowerCase();
  const bestPrice = prod.best_price ?? 0;

  // 1. Global junk & non-sport filter
  if (cat === "non_sport") return false;
  if (GLOBAL_JUNK_RE.test(fullText)) return false;

  // 2. Kids / Junior / Nike Youth ("Nike Y ...") filter unless explicitly requested
  if (!/\b(junior|jr|bambin[oi]|kids?|youth|ragazz[oi])\b/.test(qLow)) {
    if (pGender === "junior" || KIDS_MARKER_RE.test(cname)) return false;
    if (prod.offers.length > 0 && prod.offers.every((o) => KIDS_MARKER_RE.test((o.title ?? "").toLowerCase()))) {
      return false;
    }
  }

  // 3. Bike hardware filter unless cycling hardware query
  if (!/\b(bici|ciclismo|sterzo|headset|bike|freno|pedali|tubeless)\b/.test(qLow)) {
    if (BIKE_HARDWARE_RE.test(fullText)) return false;
  }

  if (!productType) return true;

  const blocked = getBlockedCategoriesForProductType(productType);
  // Category-resilience: for apparel tops/pants/jackets, if canonical_name or offer title/URL
  // unambiguously signals the target garment (e.g. "Maglia Manica Lunga" misclassified as trail_running),
  // let the switch below perform authoritative text-level gating instead of blind DB-category rejection.
  const hasExplicitLongSleeveSignal = /\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)|radical\s*airflow\s*nxt|l\/s\b|\bls\b)\b/.test(fullText);
  if (blocked && cat && blocked.includes(cat)) {
    const allowCategoryOverride = productType === "long_sleeve_top" &&
      hasExplicitLongSleeveSignal &&
      ["trail_running", "running_shoes", "shoes", "outdoor", "gear"].includes(cat);
    if (!allowCategoryOverride) return false;
  }

  switch (productType) {
    case "shoes":
    case "trail_shoes": {
      if (isApparelOnlySizes(prod.available_sizes ?? [])) return false;
      // Block apparel/tech/accessories/mats/insoles/bike racks & tires/headsets/non-shoe gear/slides/kids suffixes
      if (/\b(t[\s-]*rex|smartwatch|orologi[o]?|garmin|amazfit|polar|suunto|coros|igpsport|bsc\d+|ciclocomputer|bike\s*computer|portabici|biciclett[ae]|antifurto|tappetino|yogamat|yoga\s*mat|solett[ae]|insole|plantar[ei]|lacci\b|stringhe\b|deodorant|impermeabilizzant|asciugascarpe|telo\s*microfibra|asciugaman[oi]|towel|borracc(?:ia|e)|soft\s*flask|zain[oi]|backpack|calz[ae]|calzin[oi]|socks?|socquette|light\s*crew|mid\s*cut|t[\s-]*shirt|magli[ae]|magliett[ae]|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet|snglt|tank\b|crop\b|cropped|tee\b|jsy\b|jersey\b|top\s*ss\b|crew\s*top\b|trk\s*jkt\b|pant\s*kp\b|dry\s*park\d*|park\s*20\b|woven\b|felp[ae]|hoodie|hooded|polare|fleece|giacc(?:a|he)|jacket|jkt\b|piumin[oi]|tuta\b|completo\b|pantaloncin[oi]|shorts?|leggings?|tights?|calzamagli[ae]|fuseaux|pantalon[ie]|pants\b|coscial[ei]|gonn[ae]|skirt|2in1|2\s*in\s*1|cappellin[oi]|cappell[oi]|\bcap\b|berrett[oi]|beanie|besanie|visier[ae]|headband|scaldacollo|scaldamuscoli|balaclava|neck\s*gaiter|gaiter\b|bandana|manicott[oi]|marsupi[oi]|run\s*belt|borson[ei]|bors[ae]|sacca\b|tote\b|duffel|guant[oi]|gloves|occhial[ie]|adattatore\s*ottico|gel\s*energetico|barrett[ae]|isonam|rull[oi]|casc(?:o|hi)|helmet|racchett[ae]|pala\s*padel|reggisen[oi]|\bbra\b|slip\b|boxer\b|bikini|maillot|crankbrothers|cuffi[ae]|scarpin[oi]|calcio|calcetto|futsal|mercurial|predator|copertone|pneumatic|24x1|rig\s*24|pallon[ei]|playground\s*8p|panno\s*pulizia|cintura\s*porta|\bps\b|\btd\b|\bgs\b|infant|toddler)\b/.test(fullText)) {
        return false;
      }
      if (!/\b(ciabatt[ae]|slide|slides|recovery|recupero|sandal[oi]|infradito)\b/.test(qLow)) {
        if (/\b(ciabatt[ae]|adilette|slides?|infradito|klapki|sandal[oi])\b/.test(fullText)) return false;
      }
      if (!/\b(shox|air\s*force|force\s*1|dunk|cortez|blazer|lifestyle|casual|street|air\s*max\s*(?:90|95|97|plus|tn))\b/.test(qLow)) {
        if (/\b(shox|air\s*force|force\s*1|dunk\b|cortez|blazer\s*mid|blazer\s*low|air\s*max\s*(?:90|95|97|plus|tn)|street\s*jam|kappa\s*(?:kombat|kontroll))\b/.test(fullText)) return false;
      }
      if (!/\b(pista|chiodat|spike|atletica|campestre|cross\s*country|\bxcs\b|dragonfly|maxfly|avanti|ambition|rugby|pallamano|handball|golf|boxe|boxing|wrestling|baseball|cricket|sollevamento\s*pesi|weightlifting)\b/.test(qLow)) {
        if (/\b(chiodat[ae]|track\s*(?:and\s*)?field|\bxcs\b|adizero\s*(?:avanti|ambition|finesse|zg)|prime\s*sp|distancestar|sprintstar|throwstar|jumpstar|dragonfly|maxfly|zoom\s*rival|metaspeed\s*(?:md|sp|ld)|rugby|pallamano|handball|golf\b|boxing\b|wrestling\b|baseball\b|cricket\b|weightlifting\b|sollevamento\s*pesi)\b/.test(fullText)) {
          return false;
        }
      }
      // Require positive footwear category OR positive shoe/model signal OR EU shoe sizes (prevents random gear/food/racks leaking via semantic search!)
      const isShoeCategory = ["running_shoes", "shoes", "trail_running", "outdoor", "fitness"].includes(cat);
      if (!isShoeCategory) {
        const hasPositiveShoeCue = /\b(scarp[ae]|shoes?|sneakers?|running|trail|pegasus|vomero|vaporfly|alphafly|invincible|structure|nimbus|kayano|cumulus|novablast|superblast|metaspeed|clifton|bondi|speedgoat|mach|rincon|mafate|ghost|glycerin|cascadia|hyperion|adrenaline|endorphin|triumph|ride|peregrine|adizero|dropset|ultraboost|supernova|terrex|cloudmonster|cloudsurfer|cloudboom|cloudrunner|wave\s*(?:rider|sky|rebellion|inspire)|fresh\s*foam|fuelcell|1080|deviate\s*nitro|velocity\s*nitro|speedcross|ultra\s*raptor|bushido|lone\s*peak)\b/.test(fullText);
        const hasEuShoeSizes = (prod.available_sizes ?? []).some((s) => {
          const n = Number(normalizeSize(s));
          return Number.isFinite(n) && n >= 35 && n <= 49;
        });
        if (!hasPositiveShoeCue && !hasEuShoeSizes) return false;
      }
      if (bestPrice > 0 && bestPrice < 22) return false;
      return true;
    }

    case "leggings_tights": {
      if (/\b(scarp[ae]|shoe|shoes|sneakers?|calz[ae]|calzin[oi]|socks?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|jsy\b|jersey|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|felp[ae]|hoodie|orologi[o]?|zain[oi]|cappellin[oi]|reggisen[oi]|\bbra\b)\b/.test(fullText)) {
        return false;
      }
      // Require positive leggings/tights/calzamaglia/fuseaux signal — NEVER accept shoes, socks, or loose shorts!
      return /\b(leggings?|leggins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant)\b/.test(fullText);
    }

    case "shorts": {
      if (/\b(scarp[ae]|shoe|shoes|sneakers?|calz[ae]|calzin[oi]|socks?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|orologi[o]?|zain[oi]|cappellin[oi])\b/.test(fullText)) {
        return false;
      }
      return /\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|ciclisti|sprinter|bermuda|coscial[ei]|2in1|2\s*in\s*1|5in|7in|3in|4in|9in)\b/.test(fullText);
    }

    case "pants": {
      if (/\b(scarp[ae]|shoe|shoes|sneakers?|calz[ae]|calzin[oi]|socks?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|orologi[o]?|zain[oi]|cappellin[oi])\b/.test(fullText)) {
        return false;
      }
      return /\b(pantalon[ie]|pants?|joggers?|leggings?|tights?|calzamagli[ae]|fuseaux|pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|track\s*pant)\b/.test(fullText);
    }

    case "long_sleeve_top": {
      if (CASUAL_NON_SPORT_BRANDS.has(brand)) return false;
      if (/\b(scarp[ae]|shoe|sneaker|cappellin[oi]|cappell[oi]|\bcap\b|berr+ett[oi]|scaldacollo|scaldamuscoli|balaclava|neckwear|neckwarmer|calz[ae]|calzin[oi]|socks?|pantaloncin[oi]|shorts?|leggings?|tights?|calzamagli[ae]|pantalon[ie]|zain[oi]|bors[ae]|sacca\b|tote\b|orologi[o]?|occhial[ie]|piumin[oi]|giacc(?:a|he)|jacket|jkt\b|canott[ae]|singlet|sleeveless|smanicat[ao]|senza\s*maniche|gilet\b|vest\b|manic(?:a|he)\s*cort[ae]|short[\s-]*sleeve|reggiseno|\bbra\b|cooling\s*sleeve)\b/.test(fullText)) {
        return false;
      }
      if (!/\b(calcio|inter|squadra|replica|stadium|partita)\b/.test(qLow)) {
        if (/\b(calcio\s*replica|stadium\s*se|pre[\s-]*partita|maglia\s*(?:da\s*)?calcio)\b/.test(fullText)) {
          return false;
        }
      }
      // Note: "polar" matches fleece ONLY when brand is not Polar (watch brand)
      const isPolarFleece = /\bpolar\b/.test(fullText) && brand !== "polar" && !/\b(vantage|pacer|grit|ignite|h10|h9|verity|watch|orologi)\b/.test(fullText);
      return isPolarFleece || /\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)|l\/s\b|\bls\b|half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip|zip\s*(?:a\s*)?1\s*[\/\s]\s*[24]|1\s*[\/\s]\s*[24][\s-]*(?:di\s+)?zip|zip\s*(?:a\s*)?met[aà]\s*lunghezza|termic[aohe]|therma[\s-]*fit|active\s*warm|warmalite|warm\b|midlayer|mid[\s-]*layer|fleece|felp[ae]|pile\b|girocollo|crewneck|crew\s*neck|pullover|mock\b|first\s*layer|base\s*layer|strato\s*base|wolf\s*grid|wolf\s*tree|wolf\s*lichen|chinati|tuff\s*fleece|radical\s*airflow\s*nxt)\b/.test(fullText);
    }

    case "short_sleeve_top": {
      if (CASUAL_NON_SPORT_BRANDS.has(brand)) return false;
      if (/\b(scarp[ae]|shoe|sneaker|cappellin[oi]|\bcap\b|calz[ae]|calzin[oi]|pantaloncin[oi]|shorts?|leggings?|tights?|pantalon[ie]|zain[oi]|orologi[o]?|giacc(?:a|he)|jacket|canott[ae]|singlet|reggiseno|\bbra\b|long[\s-]*sleeve|manic(?:a|he)\s*lung(?:a|he))\b/.test(fullText)) {
        return false;
      }
      return /\b(t[\s-]*shirt|tshirt|magli[ae]|magliett[ae]|short[\s-]*sleeve|manic(?:a|he)\s*cort[ae]|top\s*ss|jsy\s*ss|tee\b|top\b)\b/.test(fullText);
    }

    case "singlet_top":
      return /\b(canott[ae]|canottier[ae]|singlet|tank\s*top|sleeveless|smanicat[ao])\b/.test(fullText);

    case "top": {
      if (CASUAL_NON_SPORT_BRANDS.has(brand)) return false;
      if (/\b(scarp[ae]|shoe|sneaker|cappellin[oi]|\bcap\b|calz[ae]|calzin[oi]|socks?|pantaloncin[oi]|shorts?|leggings?|tights?|calzamagli[ae]|pantalon[ie]|zain[oi]|orologi[o]?|occhial[ie]|giacc(?:a|he)|jacket)\b/.test(fullText)) {
        return false;
      }
      return cat === "top" || cat === "apparel" || /\b(t[\s-]*shirt|tshirt|magli[ae]|magliett[ae]|canott[ae]|singlet|long[\s-]*sleeve|short[\s-]*sleeve|manic(?:a|he)|felp[ae]|hoodie|zip|top|tee\b)\b/.test(fullText);
    }

    case "jacket": {
      if (/\b(scarp[ae]|shoe|sneaker|pantaloncin[oi]|shorts?|leggings?|calz[ae]|calzin[oi]|orologi[o]?|smartwatch)\b/.test(fullText)) return false;
      return /\b(giacc(?:a|he)|jacket|jkt\b|antivento|windbreaker|k[\s-]*way|gilet|vest|shell|guscio|impermeabil[ei]|rain)\b/.test(fullText);
    }

    case "socks": {
      if (/\b(scarp[ae]|shoe|sneaker|ghost|pegasus|nimbus|clifton|bondi|magli[ae]|t[\s-]*shirt|pantaloncin[oi]|giacc(?:a|he)|orologi[o]?)\b/.test(fullText)) return false;
      return /\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?|quarter\s*sock|crew\s*sock|ankle\s*sock|no\s*show)\b/.test(fullText);
    }

    case "headwear": {
      if (/\b(scarp[ae]|shoe|sneaker|magli[ae]|pantalon[ie]|giacc(?:a|he)|orologi[o]?|calz[ae])\b/.test(fullText)) return false;
      return /\b(cappellin[oi]|cappell[oi]|berrett[oi]|beanie|visier[ae]|visor|fascia\s*testa|headband|scaldacollo|neckwarmer|\bcap\b|guant[oi]|gloves)\b/.test(fullText);
    }

    case "heart_rate_monitor": {
      if (bestPrice <= 0) return false;
      if (/\b(forerunner|fenix|instinct|epix|venu|vivoactive|vantage|pacer|grit|ignite|suunto\s*(?:race|vertical|run)|coros\s*(?:pace|apex|vertix)|amazfit|smartwatch|orologi[o]?|ciclocomputer|garmin\s*edge|\bedge\s*\d+|bsc\d+|elemnt|calz[ae]|scarp[ae]|magli[ae]|pantalon[ie]|pellicol[ae]|cover|custodi[ae]|supporto|staff[ae])\b/.test(fullText)) {
        return false;
      }
      return /\b(fascia\s*cardio|fascia\s*hrm|hrm|h10|h9|verity|oh1|trackr\s*hr|tickr|heart\s*rate|frequenza\s*cardiaca|sensore\s*cardiaco|cardiofrequenzimetro)\b/.test(fullText);
    }

    case "gps_watch": {
      if (/\b(ciclocomputer|bike\s*computer|contachilometri|contatore|igpsport|bsc\d+|igs\d+|garmin\s*edge|\bedge\s*(?:130|530|540|830|840|1030|1040|1050|explore|mtb)\b|bryton|wahoo\s*elemnt|cinturin[oi]|strap|bracelet|bracciale|quickfit|pellicol[ae]|cover|custodi[ae]|cav[oi]|caricabatteri[ae]|staff[ae]|supporto|support\b|mount|protezion[ei]|idrogel|hydrogel|vetro\s*temp[ea]rato|screen\s*protector|sportenzia|\b(?:18|20|22|24|26)\s*mm\b|gilet|zaino|backpack|borracc|felp[ae]|pile\b|polo\b|t[\s-]*shirt|magli[ae]|giacc(?:a|he)|pantalon[ie]|scarp[ae]|fascia\s*cardio|\bhrm\b|\bh10\b|\bh9\b|\breel\b|fishing|mulinello|pesca)\b/.test(fullText)) {
        return false;
      }
      if (bestPrice > 0 && bestPrice < 65) return false;
      return /\b(garmin|forerunner|fenix|instinct|epix|venu|vivoactive|polar|vantage|pacer|grit|ignite|suunto|coros|pace\s*[234]|apex|vertix|amazfit|t[\s-]*rex|cheetah|orologi[o]?|smartwatch|sportwatch)\b/.test(fullText);
    }

    case "bike_computer": {
      if (/\b(supporto|staff[ae]|mount|custodi[ae]|cover|pellicol[ae]|cinturin[oi]|fascia\s*cardio|forerunner|fenix|instinct|venu|scarp[ae]|magli[ae]|casco)\b/.test(fullText)) return false;
      if (bestPrice > 0 && bestPrice < 38) return false;
      return /\b(garmin\s*edge|\bedge\s*(?:130|530|540|830|840|1030|1040|1050|explore|mtb)\b|ciclocomputer|bike\s*computer|contachilometri|wahoo\s*elemnt|bryton|igpsport|bsc\d+|hammerhead|karoo)\b/.test(fullText);
    }

    case "eyewear": {
      if (/\b(lenti\s*occhiali|lent[ei]\s*(?:di\s*)?ricambio|replacement\s*lens|custodi[ae]|astuccio|scarp[ae]|magli[ae]|cappellin[oi]|casco)\b/.test(fullText)) return false;
      if (cname.startsWith("oakley lenti ") || cname.startsWith("rudy project lenti ")) return false;
      return /\b(occhial[ie]|oakley|sutro|radar|jawbreaker|holbrook|encoder|bisphaera|sphaera|bliz|rudy\s*project|smith|sunglasses)\b/.test(fullText);
    }

    case "hydration": {
      if (/\b(scarp[ae]|shoe|sneaker|magli[ae]|t[\s-]*shirt|pantaloncin[oi]|giacc(?:a|he)|calz[ae]|orologi[o]?|cappellin[oi])\b/.test(fullText)) return false;
      return /\b(gilet|vest|active\s*skin|adv\s*skin|sense\s*pro|zain[oi]|backpack|pack|borracc(?:ia|e)|bottle|flask|camelbak|idratazione|hydration|quiver)\b/.test(fullText);
    }

    case "padel_racket": {
      if (/\b(scarp[ae]|shoe|magli[ae]|t[\s-]*shirt|pantaloncin[oi]|shorts?|calz[ae]|pallin[ae]|overgrip|\bgrip\b|bors[ae]|borson[ei]|zain[oi]|paletero|occhial[ie]|cappellin[oi]|telo\b)\b/.test(fullText)) return false;
      if (bestPrice > 0 && bestPrice < 38) return false;
      return /\b(bullpadel|nox|babolat|head|siux|starvie|kuikma|metalbone|adipower|racchett[ae]|pala|vertex|hack|at10|ml10|viper)\b/.test(fullText);
    }

    case "tennis_racket": {
      if (/\b(scarp[ae]|shoe|magli[ae]|pantaloncin[oi]|calz[ae]|overgrip|cord[ae]|pallin[ae])\b/.test(fullText)) return false;
      if (bestPrice > 0 && bestPrice < 40) return false;
      return /\b(racchett[ae]|pure\s*drive|pure\s*aero|ezone|vcore|percept|blade|pro\s*staff|clash|speed|radical|gravity|t[\s-]*fight|babolat|yonex|wilson|head|tecnifibre)\b/.test(fullText);
    }

    case "football_boots": {
      if (/\b(magli[ae]|jersey|jsy\b|t[\s-]*shirt|pantaloncin[oi]|shorts?|calz[ae]|calzetton[ei]|socks?|parastinch[oi]?|shin\s*guard|shinguard|flylite|superlock|guant[oi]|pallon[ei]|borson[ei]|zain[oi])\b/.test(fullText)) return false;
      return /\b(scarpin[oi]|calcio|calcetto|futsal|mercurial|superfly|vapor|tiempo|phantom|predator|copa|future|magnetico|f50|top\s*sala|top\s*flex|\bfg\b|\bag\b|\btf\b|\bmg\b|\bsg\b)\b/.test(fullText);
    }

    case "basketball_shoes": {
      if (/\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|speedgoat|magli[ae]|canott[ae]|pantaloncin[oi]|calz[ae]|pallon[ei])\b/.test(fullText)) return false;
      return /\b(basket|pallacanestro|lebron|kobe|giannis|luka|caitlin|sabrina|kd\s*\d+|harden|dame|jordan|curry|kyrie)\b/.test(fullText);
    }

    case "tennis_shoes": {
      if (/\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|pegasus|speedgoat|magli[ae]|pantaloncin[oi]|calz[ae]|racchett[ae]|pallin[ae])\b/.test(fullText)) return false;
      return /\b(tennis|terra\s*battuta|clay|resolution|court\s*ff|dedicate|nikecourt|barricade|vapor|challenger|rush\s*pro|jet\s*mach)\b/.test(fullText);
    }

    case "volleyball_shoes": {
      if (/\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|pegasus|speedgoat|magli[ae]|pantaloncin[oi]|calz[ae]|pallon[ei]|ginocchier[ae])\b/.test(fullText)) return false;
      return /\b(pallavolo|volley|spike|sky\s*elite|metarise|wave\s*lightning|wave\s*momentum|netburner|upcourt|gel[\s-]*task)\b/.test(fullText);
    }

    case "swim": {
      if (/\b(scarp[ae]|oakley|sutro|radar|jawbreaker|magli[ae]|pantaloncin[oi]|calz[ae]|orologi[o]?|ciclocomputer)\b/.test(fullText)) return false;
      return /\b(occhialin[oi]|goggles|nuot[ao]|piscina|arena|speedo|biofuse|futura|cobra|swipe|tyr|nabaiji|costum[ei]|cuffi[ae])\b/.test(fullText);
    }

    case "winter_sports":
      return /\b(sci|ski|snowboard|scarpon[ei]|mascher[ae]|attacch[oi]|atomic|rossignol|nordica|tecnica|dalbello|salomon)\b/.test(fullText);

    case "nutrition":
      return /\b(gel|barrett[ae]|integrator[ei]|sali|maltodestrin|enervit|maurten|sis|namedsport|carboidrati|isotonico|proteine)\b/.test(fullText);

    case "smart_trainer":
      return /\b(rull[oi]|trainer|kickr|tacx|elite|direto|suito|zwift)\b/.test(fullText);

    default:
      return true;
  }
}

// ============================================================================
// Bilingual Catalog Term Expansion & Sanitization
// ============================================================================

const CATEGORY_SYNONYMS: Partial<Record<ProductType, string[]>> = {
  leggings_tights: ["leggings", "tights", "calzamaglia", "fuseaux", "tight"],
  shorts: ["shorts", "pantaloncini", "ciclisti"],
  pants: ["pantaloni", "pants", "tights", "leggings"],
  long_sleeve_top: ["manica lunga", "maniche lunghe", "long sleeve", "ls", "1/4 zip", "half zip", "maglia termica"],
  short_sleeve_top: ["t-shirt", "maglietta", "maglia", "manica corta", "maniche corte", "short sleeve"],
  singlet_top: ["canotta", "singlet", "tank"],
  top: ["maglia", "t-shirt", "manica lunga", "long sleeve"],
  jacket: ["giacca", "jacket", "antivento"],
  socks: ["calze", "socks", "calzini"],
  headwear: ["cappellino", "cap", "berretto", "visiera"],
  heart_rate_monitor: ["fascia cardio", "hrm", "polar h10", "polar h9", "heart rate"],
  bike_computer: ["garmin edge", "ciclocomputer", "igpsport", "bryton", "wahoo elemnt"],
  gps_watch: ["forerunner", "garmin", "fenix", "coros", "suunto", "polar vantage"],
  eyewear: ["oakley", "occhiali", "sutro", "radar", "rudy project"],
  hydration: ["active skin", "adv skin", "zaino", "soft flask", "borraccia", "camelbak"],
  swim: ["occhialini", "arena", "speedo", "costume nuoto"],
  padel_racket: ["bullpadel", "nox", "racchetta padel", "babolat", "head"],
  tennis_racket: ["pure drive", "pure aero", "ezone", "wilson blade", "racchetta tennis"],
  football_boots: ["mercurial", "predator", "phantom", "tiempo", "top sala", "calcio"],
  basketball_shoes: ["lebron", "luka", "kobe", "giannis", "basket", "jordan"],
  tennis_shoes: ["tennis", "resolution", "court ff", "nikecourt", "barricade"],
  volleyball_shoes: ["volley", "pallavolo", "sky elite", "wave lightning"],
};

const APPAREL_SYNONYM_TYPES = new Set<ProductType>([
  "leggings_tights", "shorts", "pants", "long_sleeve_top", "short_sleeve_top",
  "singlet_top", "top", "jacket", "socks", "headwear",
]);

const CLEAN_FILLER_RE = /\b(da\s+corsa|per\s+correre|per\s+la\s+corsa|da\s+running|per\s+running|miglior[ie]?|offerte?|prezzo(?:\s+(?:massimo|max|minimo|min))?|sotto\s*(?:i|ai|gli|le|di)?\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|sopra\s*(?:i|ai|gli|le|di)?\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|meno\s*di\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|pi[uù]\s*di\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|fino\s*a(?:i|gli)?\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|entro\s*(?:i|ai|gli)?\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|non\s+(?:oltre|pi[uù]\s*di)\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|tra\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?\s*e\s*€?\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?|taglia\s*\S+|tg\.?\s*\S+|misura\s*\S+|numero\s*\S+|spedizione\s+(?:gratuita|gratis)|in\s+(?:sconto|offerta|saldo)|scontat[aeio]|saldi|uomo|donna|unisex|rimuovi\s+limite\s+di\s+prezzo|senza\s+limiti\s+di\s+budget)\b/gi;

export function buildCatalogSearchTerms(opts: {
  rawQuery?: string | null;
  keywords?: string[];
  brand?: string | null;
  productType?: ProductType | null;
  entityTokens?: string[];
  isComparison?: boolean;
}): string[] {
  const brand = opts.brand?.trim() || null;
  const brandLow = brand?.toLowerCase() ?? "";
  const pt = opts.productType ?? null;
  const entityTokens = opts.entityTokens ?? [];
  const isComparison = Boolean(opts.isComparison);
  const out: string[] = [];
  const seen = new Set<string>();

  const add = (term: string) => {
    let clean = normalizeQueryTypos(term)
      .replace(/>>+/g, " ")
      .replace(/€\s*\d+(?:[.,]\d+)?|\b\d+(?:[.,]\d+)?\s*€|\b(?:<=?|>=?)\s*\d+(?:[.,]\d+)?/g, " ")
      .replace(CLEAN_FILLER_RE, " ");
    for (const st of KNOWN_STORES) {
      clean = clean.replace(new RegExp(`\\b(?:su|da|in|negli|nel)?\\s*${st.regex.source}`, "gi"), " ");
    }
    clean = clean.replace(/\s+/g, " ").trim();
    // For shoe queries, strip generic "scarpe"/"scarpa"/"shoes" so canonical names like "Hoka Clifton 9" match
    if (pt === "shoes" || pt === "trail_shoes") {
      clean = clean.replace(/\b(scarp[ae]|shoes?|running|corsa)\b/gi, " ").replace(/\s+/g, " ").trim();
    }
    if (!clean || clean.length < 2) return;
    const low = clean.toLowerCase();
    // NEVER allow bare brand name alone when we know the productType or specific entityTokens!
    if ((pt || entityTokens.length > 0) && brandLow && low === brandLow) return;
    if ((pt || entityTokens.length > 0) && KNOWN_BRANDS.some((b) => b.toLowerCase() === low)) return;
    if (!seen.has(low)) {
      seen.add(low);
      out.push(clean);
    }
  };

  // 1. When BOTH an entity/sub-brand (e.g. "acg") AND an apparel productType (e.g. "long_sleeve_top") exist,
  // put SPECIFIC entity + apparel-synonym terms FIRST so hats/caps/bags matching bare "Nike acg" NEVER crowd them out!
  const entityPhrase = entityTokens.join(" ");
  if (entityTokens.length > 0 && !isComparison && pt && APPAREL_SYNONYM_TYPES.has(pt) && CATEGORY_SYNONYMS[pt]) {
    for (const syn of CATEGORY_SYNONYMS[pt]!.slice(0, 6)) {
      add(brand ? `${brand} ${entityPhrase} ${syn}` : `${entityPhrase} ${syn}`);
    }
  }

  // 2. Clean LLM/caller keywords
  for (const kw of opts.keywords ?? []) {
    const cleaned = normalizeQueryTypos(kw)
      .replace(/>>+/g, " ")
      .replace(CLEAN_FILLER_RE, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (!cleaned) continue;
    // If exact model tokens exist (non-comparison), skip LLM keywords that don't share at least one entity token
    if (entityTokens.length > 0 && !isComparison) {
      const cLow = cleaned.toLowerCase();
      const sharesEntity = entityTokens.some((et) => new RegExp(`\\b${escapeRegExp(et)}\\b`).test(cLow));
      if (!sharesEntity) continue;
    }
    add(cleaned);
  }

  // 3. Exact entity / model query anchor (placed BEFORE generic synonyms for non-apparel,
  //    or AFTER specific entity+apparel terms so bare sub-brand never drowns out garment matches!)
  if (entityTokens.length > 0 && !isComparison) {
    if (brand) add(`${brand} ${entityPhrase}`);
    add(entityPhrase);
  }

  // 4. For category + brand (or pure category) queries without specific model tokens, expand bilingual synonyms!
  if (entityTokens.length === 0 && pt && CATEGORY_SYNONYMS[pt] && (APPAREL_SYNONYM_TYPES.has(pt) || out.length < 2)) {
    for (const syn of CATEGORY_SYNONYMS[pt]!) {
      if (brand) {
        add(`${brand} ${syn}`);
      } else {
        add(syn);
      }
    }
  }

  // 5. Fallback to cleaned raw query only if we have no brand+category query (brand+shoes works directly via brand_filter!)
  if (out.length === 0 && opts.rawQuery && !(brand && (pt === "shoes" || pt === "trail_shoes"))) {
    add(opts.rawQuery);
  }

  return out.slice(0, 10);
}

// ============================================================================
// Offer Grouping, Filtering, Relevance Scoring & Deduplication
// ============================================================================

function checkGenderMatch(
  prodGender: string | null,
  canonicalName: string,
  offerMeta: string,
  reqGender: string | null,
): boolean {
  if (!reqGender) return true;
  const gReq = reqGender.trim().toLowerCase();
  if (!gReq || gReq === "unisex" || gReq === "all" || gReq === "tutti") return true;

  const pg = (prodGender ?? "unisex").toLowerCase();
  const isDual = pg.includes("uomo") && pg.includes("donna");
  if (pg !== "unisex" && pg !== "" && !isDual) {
    if (gReq === "donna" && !pg.includes("donna")) return false;
    if (gReq === "uomo" && !pg.includes("uomo")) return false;
  }

  const probe = `${canonicalName} ${offerMeta}`.toLowerCase();
  const hasF = /(?:\b(?:donna|donne|wmns|woman|women|womens|femme|lady|ladies|damen|mujer)\b|\/(?:donna|woman|women|womens|wmns|femme)\/)/.test(probe);
  const hasM = /(?:\b(?:uomo|uomini|men|mens|homme|herren|hombre)\b|\/(?:uomo|men|mens|homme)\/)/.test(probe);
  if (gReq === "uomo" && hasF && !hasM) return false;
  if (gReq === "donna" && hasM && !hasF) return false;
  return true;
}

function buildInternalProductFromOffers(
  prodMeta: {
    id: string;
    canonical_name: string;
    brand: string | null;
    category: string | null;
    gender: string | null;
    image_url: string | null;
    gallery_images: string[] | null;
  },
  rawOffers: Array<{
    store_id: string;
    store_name: string;
    product_id: string | null;
    raw_title: string;
    current_price: number;
    original_price: number | null;
    discount_pct: number | null;
    product_url: string;
    image_url: string | null;
    gallery_images: string[] | null;
    available_sizes: string[] | null;
    shipping_cost: number | null;
    free_shipping_threshold: number | null;
    courier: string | null;
  }>,
  opts: {
    maxPrice?: number | null;
    minPrice?: number | null;
    size?: string | null;
    gender?: string | null;
    store?: string | null;
    excludedStores?: string[] | null;
    freeShipping?: boolean;
    onSale?: boolean;
    minDiscount?: number | null;
  },
  lexicalScore: number,
  semanticSim: number,
): InternalProduct | null {
  const storeFilter = opts.store?.trim().toLowerCase() || null;
  const excludedStoresLow = new Set((opts.excludedStores ?? []).map((s) => s.trim().toLowerCase()).filter(Boolean));
  const reqFemale = (opts.gender ?? "").toLowerCase().includes("donna") ||
    (prodMeta.gender ?? "").toLowerCase().includes("donna");

  const validOffers: OfferOut[] = [];
  const seenOfferKeys = new Set<string>();
  const allSizes = new Set<string>();
  const gallery: string[] = [];

  const pushGallery = (u: string | null | undefined) => {
    if (isValidImageUrl(u) && !gallery.includes(u!)) {
      gallery.push(u!);
    }
  };

  for (const r of rawOffers) {
    const price = Number(r.current_price ?? 0);
    if (!Number.isFinite(price) || price <= 0) continue;
    if (opts.maxPrice != null && price > opts.maxPrice) continue;
    if (opts.minPrice != null && price < opts.minPrice) continue;
    if (storeFilter && r.store_id.toLowerCase() !== storeFilter && !r.store_name.toLowerCase().includes(storeFilter)) {
      continue;
    }
    if (excludedStoresLow.size > 0 && excludedStoresLow.has(r.store_id.toLowerCase())) {
      continue;
    }
    if (!sizeMatches(r.available_sizes, opts.size, reqFemale)) continue;
    const ship = Number(r.shipping_cost ?? 0);
    if (opts.freeShipping && ship > 0) continue;
    const orig = r.original_price != null ? Number(r.original_price) : null;
    const computedDisc = r.discount_pct != null
      ? Number(r.discount_pct)
      : (orig && orig > price ? Math.round(((orig - price) / orig) * 1000) / 10 : 0);
    if (opts.minDiscount != null && opts.minDiscount > 0) {
      if (computedDisc < opts.minDiscount) continue;
    } else if (opts.onSale) {
      if (!(computedDisc >= 5 || (orig != null && orig > price + 1))) continue;
    }

    const dedupKey = `${r.store_id.toLowerCase()}|${r.product_url}`;
    if (seenOfferKeys.has(dedupKey)) continue;
    seenOfferKeys.add(dedupKey);

    const total = Math.round((price + ship) * 100) / 100;
    const isFree = ship === 0;
    const offerImg = isValidImageUrl(r.image_url)
      ? r.image_url!
      : (isValidImageUrl(prodMeta.image_url) ? prodMeta.image_url! : null);

    const offerGallery: string[] = [];
    if (offerImg) offerGallery.push(offerImg);
    for (const g of r.gallery_images ?? []) {
      if (isValidImageUrl(g) && !offerGallery.includes(g)) offerGallery.push(g);
    }
    pushGallery(offerImg);
    for (const g of offerGallery) pushGallery(g);

    const availSizes = (r.available_sizes ?? []).map(String).filter(Boolean);
    for (const s of availSizes) allSizes.add(s);

    validOffers.push({
      store_id: r.store_id,
      store_name: r.store_name,
      product_id: r.product_id ?? prodMeta.id,
      title: r.raw_title,
      brand: extractBrand(r.raw_title, prodMeta.brand),
      price,
      original_price: orig,
      discount_pct: r.discount_pct != null ? Number(r.discount_pct) : null,
      savings: orig && orig > price ? Math.round((orig - price) * 100) / 100 : null,
      url: r.product_url,
      image_url: offerImg,
      gallery_images: offerGallery.length > 0 ? offerGallery : null,
      available_sizes: availSizes,
      variant_name: null,
      in_stock: true,
      shipping_cost: ship,
      total_price: total,
      is_free_shipping: isFree,
      shipping_label: isFree ? "Spedizione Gratuita" : `+${ship.toFixed(2)} € sped.`,
      free_shipping_threshold: r.free_shipping_threshold != null ? Number(r.free_shipping_threshold) : null,
      courier: r.courier ?? null,
    });
  }

  if (validOffers.length === 0) return null;

  pushGallery(prodMeta.image_url);
  for (const g of prodMeta.gallery_images ?? []) pushGallery(g);

  validOffers.sort((a, b) => a.price - b.price);
  const prices = validOffers.map((o) => o.price);
  const best = Math.min(...prices);
  const high = Math.max(...prices);
  const savings = high > best ? Math.round((high - best) * 100) / 100 : null;

  // Pick the best valid image (prefer cheapest offer's valid image, then any offer's valid image, then product image)
  const bestImage = validOffers.find((o) => isValidImageUrl(o.image_url))?.image_url ??
    (isValidImageUrl(prodMeta.image_url) ? prodMeta.image_url : null) ??
    gallery[0] ??
    null;

  // Ensure every offer also gets a fallback valid image if its own was a placeholder
  if (bestImage) {
    for (const o of validOffers) {
      if (!isValidImageUrl(o.image_url)) o.image_url = bestImage;
    }
  }

  const offerMeta = validOffers.slice(0, 4).map((o) => `${o.title} ${o.url}`).join(" ");
  if (!checkGenderMatch(prodMeta.gender, prodMeta.canonical_name, offerMeta, opts.gender ?? null)) {
    return null;
  }

  const resolvedBrand = prodMeta.brand ?? extractBrand(prodMeta.canonical_name, validOffers[0]?.brand ?? null);

  return {
    id: prodMeta.id,
    canonical_name: prodMeta.canonical_name,
    brand: resolvedBrand,
    category: prodMeta.category,
    image_url: bestImage,
    gallery_images: gallery.length > 0 ? gallery : null,
    gender: prodMeta.gender,
    offers: validOffers,
    best_price: best,
    highest_price: high,
    cross_store_savings: savings,
    available_sizes: Array.from(allSizes),
    lexical_score: lexicalScore,
    semantic_similarity: semanticSim,
    rrf_score: 0,
    relevance_score: 0,
    matched_entity_count: 0,
    matched_digit_exact: false,
  };
}

export function groupOffersToMatchedProducts(
  rows: RawOfferRow[],
  opts?: {
    maxPrice?: number | null;
    minPrice?: number | null;
    size?: string | null;
    gender?: string | null;
    store?: string | null;
    limit?: number;
  },
): MatchedProductOut[] {
  const byProd = new Map<string, { meta: NonNullable<RawOfferRow["products"]> & { id: string; canonical_name: string }; offers: RawOfferRow[] }>();
  for (const r of rows) {
    const p = r.products;
    if (p?.category === "non_sport") continue;
    const key = r.product_id || (p?.canonical_name ?? r.raw_title).toLowerCase();
    let entry = byProd.get(key);
    if (!entry) {
      entry = {
        meta: {
          id: key,
          canonical_name: p?.canonical_name || r.raw_title,
          brand: p?.brand ?? null,
          category: p?.category ?? null,
          gender: p?.gender ?? null,
          image_url: p?.image_url ?? null,
          gallery_images: p?.gallery_images ?? null,
        },
        offers: [],
      };
      byProd.set(key, entry);
    }
    entry.offers.push(r);
  }

  const out: MatchedProductOut[] = [];
  for (const { meta, offers } of byProd.values()) {
    const built = buildInternalProductFromOffers(
      {
        id: meta.id,
        canonical_name: meta.canonical_name,
        brand: meta.brand ?? null,
        category: meta.category ?? null,
        gender: meta.gender ?? null,
        image_url: meta.image_url ?? null,
        gallery_images: meta.gallery_images ?? null,
      },
      offers,
      opts ?? {},
      0,
      0,
    );
    if (built) out.push(stripInternalFields(built));
  }
  out.sort((a, b) => {
    if (b.offers.length !== a.offers.length) return b.offers.length - a.offers.length;
    return (a.best_price ?? 9999) - (b.best_price ?? 9999);
  });
  return out.slice(0, opts?.limit ?? 35);
}

function stripInternalFields(p: InternalProduct): MatchedProductOut {
  return {
    id: p.id,
    canonical_name: p.canonical_name,
    brand: p.brand,
    image_url: p.image_url,
    gallery_images: p.gallery_images,
    gender: p.gender,
    offers: p.offers,
    best_price: p.best_price,
    highest_price: p.highest_price,
    cross_store_savings: p.cross_store_savings,
  };
}

export type SortByMode = "price_asc" | "price_desc" | "discount_desc";

const CARBON_PLATE_SHOE_RE = /\b(vaporfly|alphafly|adios\s*pro|prime\s*x\d*|takumi\s*sen|metaspeed|magic\s*speed|endorphin\s*(?:pro|elite)|supercomp\s*elite|sc\s*elite|cielo\s*x\d*|rocket\s*x\d*|carbon\s*x\d*|skyward\s*x\d*|tecton\s*x\d*|deviate\s*nitro\s*elite|fast[\s-]*r|cloudboom|wave\s*rebellion\s*pro|hyperion\s*elite|carbon|piastra)\b/i;

function scoreAndGateProducts(
  candidates: InternalProduct[],
  opts: {
    rawQuery: string;
    searchTerms: string[];
    brand: string | null;
    excludedBrands?: string[] | null;
    excludedFeatures?: string[] | null;
    productType: ProductType | null;
    entityTokens: string[];
    isComparison?: boolean;
    gender: string | null;
    preferredSize?: string | null;
    sortBy?: SortByMode | null;
  },
): InternalProduct[] {
  const qLow = normalizeQueryTypos(opts.rawQuery).toLowerCase();
  const brandLow = opts.brand?.trim().toLowerCase() ?? null;
  const excludedBrandsLow = (opts.excludedBrands ?? []).map((b) => b.trim().toLowerCase()).filter(Boolean);
  const excludedFeats = new Set((opts.excludedFeatures ?? []).map((f) => f.trim().toLowerCase()));
  const entityTokens = opts.entityTokens;
  const isComparison = Boolean(opts.isComparison);

  // Extract model digits from entity tokens (e.g. "165" in Forerunner 165, "6" in Zoom Fly 6)
  const queryModelDigits = new Set<string>(
    entityTokens.filter((t) => /^\d+$/.test(t)),
  );
  const wantsTrail = /\b(trail|sterrato|montagna|sentier[oi]|fango|bosco)\b/.test(qLow);
  const wantsWaterproof = !excludedFeats.has("no_waterproof") && /\b(gtx|gore[\s-]*tex|impermeabil[ei]|pioggia|waterproof|shield)\b/.test(qLow);
  const wantsHalfZip = /\b(half[\s-]*zip|mezza[\s-]*zip|1\/2[\s-]*zip|quarter[\s-]*zip)\b/.test(qLow);
  const wantsThermal = /\b(termic[aohe]+|invern[aoei]+|warm|merino|freddo|cold\s*gear|coldgear)\b/.test(qLow);
  const wantsPockets = /\b(tasc[ah]e?|telefono|smartphone|2[\s-]*in[\s-]*1|pockets?|speedpocket)\b/.test(qLow);
  const wantsCushion = /\b(ammortizzat[aoei]*|max\s*cushion|morbide?|ginocch|schiena)\b/.test(qLow);
  const reqGenderLow = opts.gender && !["unisex", "all", "tutti"].includes(opts.gender.toLowerCase())
    ? opts.gender.toLowerCase()
    : null;
  const prefSizeNorm = opts.preferredSize ? normalizeSize(opts.preferredSize) : null;

  const gated: InternalProduct[] = [];

  for (const prod of candidates) {
    // 1. Hard product-type & quality compatibility gate
    if (!isProductCompatible(prod, opts.productType, opts.rawQuery)) continue;

    const pname = prod.canonical_name.toLowerCase();
    const pbrand = (prod.brand ?? "").toLowerCase();
    const offTitles = prod.offers.slice(0, 4).map((o) => o.title.toLowerCase()).join(" ");
    const combined = `${pname} ${pbrand} ${offTitles}`;

    // 2. Strict brand & excluded-brand gates
    if (brandLow) {
      const variants = [brandLow, brandLow.replace(/-/g, " "), brandLow.replace(/\s+/g, "-")];
      const matchesBrand = variants.some((v) => pbrand.includes(v) || pname.includes(v));
      if (!matchesBrand) continue;
    }
    if (excludedBrandsLow.length > 0) {
      const isExcludedBrand = excludedBrandsLow.some((eb) => {
        const re = new RegExp(`\\b${escapeRegExp(eb)}\\b`, "i");
        return re.test(pbrand) || re.test(pname);
      });
      if (isExcludedBrand) continue;
    }
    // 2b. Excluded features gate (e.g. "senza piastra in carbonio", "non impermeabili", "senza cappuccio")
    if (excludedFeats.has("no_carbon") && CARBON_PLATE_SHOE_RE.test(combined)) continue;
    if (excludedFeats.has("no_waterproof") && /\b(gtx|gore[\s-]*tex|waterproof|impermeabil)\b/i.test(combined)) continue;
    if (excludedFeats.has("no_hood") && /\b(hoodie|hooded|cappuccio)\b/i.test(combined)) continue;

    // 3. Entity token matching
    let matchedEntities = 0;
    for (const et of entityTokens) {
      if (new RegExp(`\\b${escapeRegExp(et)}\\b`, "i").test(combined)) {
        matchedEntities += 1;
      }
    }
    prod.matched_entity_count = matchedEntities;

    const pDigits = new Set<string>(pname.match(/\b\d+\b/g) ?? []);
    const digitMatches = queryModelDigits.size > 0
      ? (isComparison
        ? Array.from(queryModelDigits).some((d) => pDigits.has(d))
        : Array.from(queryModelDigits).every((d) => pDigits.has(d)))
      : false;
    prod.matched_digit_exact = digitMatches;

    // 4. Principled Relevance Scoring
    let score = prod.lexical_score * 0.6;

    if (entityTokens.length > 0) {
      if (matchedEntities > 0) {
        score += matchedEntities * 180;
        if (matchedEntities === entityTokens.length) {
          score += 240;
        }
      } else {
        score -= 300;
      }
    }

    if (queryModelDigits.size > 0) {
      if (digitMatches) {
        score += 260;
      } else if (pDigits.size > 0) {
        // Strong penalty for wrong generation/model number (e.g. Forerunner 570 or 55 when user asked 165!)
        score -= 240;
      } else {
        score -= 100;
      }
    }

    // Search term phrase & token overlap (avoid Term-0 dominating multi-brand advisory queries!)
    for (let i = 0; i < opts.searchTerms.length; i++) {
      const term = opts.searchTerms[i].toLowerCase().trim();
      if (!term) continue;
      const mult = entityTokens.length > 0
        ? (i === 0 ? 1.15 : (i < 4 ? 1.08 : 1.0))
        : 1.0;
      if (pname === term) score += 160 * mult;
      else if (pname.includes(term)) score += 95 * mult;
      else if (combined.includes(term)) score += 55 * mult;
    }

    // Product-type & feature boosts
    if (opts.productType === "long_sleeve_top") {
      const wantsHeavyFleece = /\b(felp[ae]|hoodie|pile|fleece|polar|maglion[ei]|calda|calde|caldo|termic[aohe]|invern)\b/.test(qLow);
      const isTrueLongSleeve = /\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)|l\/s\b|\bls\b|base[\s-]*layer|strato\s*base|first\s*layer|radical\s*airflow\s*nxt)\b/.test(combined);
      const isZipTop = /\b(half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip|1\s*[\/\s]\s*[24][\s-]*(?:di\s+)?zip|zip\s*(?:a\s*)?1\s*[\/\s]\s*[24]|zip\s*(?:a\s*)?met[aà]\s*lunghezza|top\s*zip)\b/.test(combined);
      const isFleeceOrHoodie = /\b(felp[ae]|hoodie|tuff\s*fleece|pile\b|polar\b|fleece|wolf\s*lichen|girocollo|crewneck)\b/.test(combined);
      if (!wantsHeavyFleece) {
        // User asked for "long sleeve" / "manica lunga": prioritize true long-sleeve tops FIRST,
        // then technical zip/base layers, then fleece/hoodies as secondary warm alternatives!
        if (isTrueLongSleeve && !isFleeceOrHoodie) score += 145;
        else if (isTrueLongSleeve) score += 110;
        else if (isZipTop && !isFleeceOrHoodie) score += 80;
        else if (isZipTop) score += 55;
        else if (isFleeceOrHoodie) score -= 20;
      } else {
        if (isFleeceOrHoodie) score += 80;
        if (isZipTop) score += 45;
      }
      if (/\b(running|corsa)\b/.test(qLow) && /\b(run|running|corsa|trail|dri[\s-]*fit|adv|aeroready|airflow|miler|pacer|strider)\b/.test(combined)) {
        score += 45;
      }
    } else if (opts.productType === "leggings_tights") {
      if (/\b(leggings?|tights?|calzamagli[ae]|fuseaux)\b/.test(pname)) score += 90;
      if (/\b(corsa|run|running|velociti|launch|fly\s*fast|qualifier|speedpocket|coldgear|heatgear)\b/.test(combined)) score += 40;
    } else if (opts.productType === "shorts") {
      if (/\b(running|corsa)\b/.test(qLow) && !/\b(calcio|football|soccer|basket|tennis)\b/.test(qLow)) {
        if (/\b(stride|challenger|swift|tempo|aeroswift|adizero|run|running|corsa|launch)\b/.test(combined)) score += 65;
        if (/\b(calcio|football|soccer|academy|strike|park\s*20|basket|tennis)\b/.test(combined)) score -= 90;
      }
    } else if (opts.productType === "gps_watch") {
      if ((prod.category ?? "").toLowerCase() === "gps_watch") score += 70;
      if (/\b(forerunner|coros\s*pace|polar\s*pacer|suunto\s*run|suunto\s*race)\b/.test(pname)) score += 50;
    } else if (opts.productType === "shoes" || opts.productType === "trail_shoes") {
      const pcat = (prod.category ?? "").toLowerCase();
      if (pcat === "running_shoes" || pcat === "shoes" || pcat === "trail_running") score += 45;
      if (wantsTrail || opts.productType === "trail_shoes") {
        if (pcat === "trail_running" || /\b(trail|speedcross|trabuco|speedgoat|cascadia|ultra\s*raptor|peregrine|hierro)\b/.test(pname)) {
          score += 85;
        }
      } else {
        if (pcat === "trail_running" || /\b(trail|speedcross|trabuco|speedgoat|cascadia)\b/.test(pname)) {
          score -= 60;
        }
      }
      if (wantsCushion && /\b(nimbus|bondi|invincible|glycerin|1080|triumph|cloudmonster|superblast|magmax)\b/.test(pname)) {
        score += 80;
      }
      if (/\b(maraton[ae]|marathon|gara|racing|veloci|competitiv[ae]|tempo\s*run|record|pb)\b/.test(qLow)) {
        if (/\b(vaporfly|alphafly|adios\s*pro|metaspeed|endorphin\s*(?:pro|elite|speed)|deviate\s*nitro|fast[\s-]*r|cielo\s*x|rocket\s*x|sc\s*elite|supercomp\s*elite|cloudboom|hyperion\s*(?:elite|max)|wave\s*rebellion|superblast|zoom\s*fly|magic\s*speed|takumi\s*sen|boston\s*1[23])\b/.test(pname)) {
          score += 95;
        }
      }
    }

    if (wantsWaterproof) {
      if (/\b(gtx|gore[\s-]*tex|waterproof|impermeabil|shield|storm|rain)\b/.test(combined)) score += 90;
    } else if (opts.productType === "shoes" && /\b(gtx|gore[\s-]*tex)\b/.test(pname)) {
      score -= 25;
    }
    if (wantsHalfZip) {
      score += /\b(half[\s-]*zip|mezza[\s-]*zip|1\/2[\s-]*zip|quarter[\s-]*zip)\b/.test(combined) ? 140 : -50;
    }
    if (wantsThermal && /\b(termic|warm|merino|coldgear|winter|invern|fleece)\b/.test(combined)) {
      score += 90;
    }
    if (wantsPockets && /\b(tasc|pocket|speedpocket|2[\s-]*in[\s-]*1|2in1|cargo)\b/.test(combined)) {
      score += 90;
    }

    // Exact gender preference boost
    if (reqGenderLow) {
      const pgLow = (prod.gender ?? "unisex").toLowerCase();
      const isDual = pgLow.includes("uomo") && pgLow.includes("donna");
      if (pgLow.includes(reqGenderLow) && !isDual) score += 70;
      else if (pgLow === "unisex") score -= 15;
    }

    // Hybrid Reciprocal Rank Fusion (RRF) + semantic similarity bonus (moderate so it never overrides exact SKU match!)
    if (prod.rrf_score > 0) {
      score += prod.rrf_score;
    }
    if (prod.semantic_similarity > 0.38) {
      score += prod.semantic_similarity * 58;
    }

    // Preferred size soft boost
    if (prefSizeNorm && prod.available_sizes.some((s) => normalizeSize(s) === prefSizeNorm)) {
      score += 18;
    }

    // Valid image bonus
    if (isValidImageUrl(prod.image_url)) {
      score += 20;
    }

    // Penalize ultra-generic bucket product titles (e.g. "Acg", "Nike Acg", "Nike Acg Trail")
    // when richer model-named products exist
    const cleanNameTokens = pname
      .replace(/[^a-z0-9àèéìòù\s]+/g, " ")
      .trim()
      .split(/\s+/)
      .filter((t) => t.length >= 2);
    const nonGenericTokens = cleanNameTokens.filter((t) =>
      t !== brandLow &&
      !["acg", "trail", "running", "corsa", "nike", "adidas", "asics", "hoka", "salomon", "garmin"].includes(t)
    );
    if (nonGenericTokens.length === 0) {
      score -= 85;
    }

    // Multi-store & savings tie-breakers (kept modest so relevance ALWAYS dominates!)
    const nOffers = prod.offers.length;
    if (nOffers >= 4) score += 28;
    else if (nOffers >= 2) score += 16;
    score += Math.min((prod.cross_store_savings ?? 0) * 0.12, 16);

    prod.relevance_score = score;
    gated.push(prod);
  }

  if (gated.length === 0) return [];

  // 5. HARD ENTITY & MODEL-NUMBER CUTOFF
  // If user asked for a specific model (e.g. "Garmin Forerunner 165" or "Nike Zoom Fly 6") and we have exact matches,
  // KEEP ONLY THE EXACT MODEL MATCHES so unrelated models (Forerunner 570 / 55) NEVER pollute results!
  let finalList = gated;
  if (entityTokens.length > 0) {
    if (isComparison) {
      const compMatches = queryModelDigits.size > 0
        ? finalList.filter((p) => p.matched_digit_exact)
        : finalList.filter((p) => p.matched_entity_count > 0);
      if (compMatches.length > 0) finalList = compMatches;
    } else {
      const exactAll = finalList.filter((p) =>
        p.matched_entity_count === entityTokens.length &&
        (queryModelDigits.size === 0 || p.matched_digit_exact)
      );
      if (exactAll.length > 0) {
        finalList = exactAll;
      } else {
        const anyEntity = finalList.filter((p) => p.matched_entity_count > 0);
        if (anyEntity.length > 0) {
          const maxMatched = Math.max(...anyEntity.map((p) => p.matched_entity_count));
          if (maxMatched >= 2) {
            finalList = anyEntity.filter((p) => p.matched_entity_count >= maxMatched);
          } else {
            finalList = anyEntity;
          }
        }
      }
    }
  }

  // 6. Relative relevance score cutoff (drop weak noise tail while NEVER dropping items that matched all required entity tokens!)
  const topScore = Math.max(...finalList.map((p) => p.relevance_score));
  if (topScore >= 120) {
    const minKeep = Math.max(20, topScore * (entityTokens.length > 0 ? 0.25 : 0.18));
    const trimmed = finalList.filter((p) =>
      p.relevance_score >= minKeep ||
      (entityTokens.length > 0 && p.matched_entity_count === entityTokens.length && p.relevance_score > 0)
    );
    if (trimmed.length > 0) finalList = trimmed;
  }

  // 7. Sort by explicit sortBy when requested, else by relevance -> offer count -> best price
  const maxDiscountOf = (p: InternalProduct): number => {
    let bestD = 0;
    for (const o of p.offers) {
      const d = o.discount_pct ?? (o.original_price && o.original_price > o.price ? ((o.original_price - o.price) / o.original_price) * 100 : 0);
      if (d > bestD) bestD = d;
    }
    return bestD;
  };
  if (opts.sortBy === "price_asc") {
    finalList.sort((a, b) => (a.best_price ?? 99999) - (b.best_price ?? 99999) || b.relevance_score - a.relevance_score);
  } else if (opts.sortBy === "price_desc") {
    finalList.sort((a, b) => (b.best_price ?? 0) - (a.best_price ?? 0) || b.relevance_score - a.relevance_score);
  } else if (opts.sortBy === "discount_desc") {
    finalList.sort((a, b) => maxDiscountOf(b) - maxDiscountOf(a) || (a.best_price ?? 99999) - (b.best_price ?? 99999));
  } else {
    finalList.sort((a, b) => {
      if (Math.abs(b.relevance_score - a.relevance_score) > 1.0) {
        return b.relevance_score - a.relevance_score;
      }
      if (b.offers.length !== a.offers.length) return b.offers.length - a.offers.length;
      return (a.best_price ?? 9999) - (b.best_price ?? 9999);
    });
  }

  // 8. Deduplicate / merge identical canonical models (including noisy scraper prefixes like "Sneaker " / "Sollevamento Pesi ")
  const normalizeMergeKey = (name: string): string =>
    name
      .trim()
      .toLowerCase()
      .replace(/\s*\((uomo|donna)\)$/i, "")
      .replace(/\b(sneakers?|scarpe|scarpa|sollevamento\s+pesi|trainer)\b/g, " ")
      .replace(/\s+/g, " ")
      .trim();

  const isNoisyName = (name: string): boolean =>
    /\b(sneakers?|sollevamento\s+pesi)\b/i.test(name);

  const deduped: InternalProduct[] = [];
  for (const prod of finalList) {
    const cnameKey = normalizeMergeKey(prod.canonical_name);
    const pGender = (prod.gender ?? "Unisex").trim();

    let merged = false;
    for (const ex of deduped) {
      const exBase = normalizeMergeKey(ex.canonical_name);
      if (exBase !== cnameKey) continue;
      const exGender = (ex.gender ?? "Unisex").trim();
      const sameGender = exGender.toLowerCase() === pGender.toLowerCase() ||
        exGender.toLowerCase() === "unisex" ||
        pGender.toLowerCase() === "unisex";

      if (sameGender) {
        // Prefer the cleaner canonical name (without noisy "Sneaker " prefix)
        if (isNoisyName(ex.canonical_name) && !isNoisyName(prod.canonical_name)) {
          ex.canonical_name = prod.canonical_name;
        }
        // Merge unique offers into the primary card
        const exKeys = new Set(ex.offers.map((o) => `${o.store_id}|${o.url}`));
        for (const o of prod.offers) {
          const k = `${o.store_id}|${o.url}`;
          if (!exKeys.has(k)) {
            ex.offers.push(o);
            exKeys.add(k);
          }
        }
        ex.offers.sort((a, b) => a.price - b.price);
        const prices = ex.offers.map((o) => o.price);
        ex.best_price = Math.min(...prices);
        ex.highest_price = Math.max(...prices);
        ex.cross_store_savings = ex.highest_price > ex.best_price
          ? Math.round((ex.highest_price - ex.best_price) * 100) / 100
          : null;
        if (!isValidImageUrl(ex.image_url) && isValidImageUrl(prod.image_url)) {
          ex.image_url = prod.image_url;
        }
        // Merge gallery images
        if (prod.gallery_images && prod.gallery_images.length > 0) {
          const g = ex.gallery_images ? [...ex.gallery_images] : [];
          for (const img of prod.gallery_images) {
            if (isValidImageUrl(img) && !g.includes(img)) g.push(img);
          }
          ex.gallery_images = g.length > 0 ? g.slice(0, 6) : null;
        }
        merged = true;
        break;
      } else {
        // Different explicit gender variants (Uomo vs Donna): disambiguate titles cleanly
        if ((exGender === "Uomo" || exGender === "Donna") && !ex.canonical_name.endsWith(`(${exGender})`)) {
          ex.canonical_name = `${ex.canonical_name} (${exGender})`;
        }
        if ((pGender === "Uomo" || pGender === "Donna") && !prod.canonical_name.endsWith(`(${pGender})`)) {
          prod.canonical_name = `${prod.canonical_name} (${pGender})`;
        }
      }
    }
    if (!merged) deduped.push(prod);
  }

  return deduped;
}

// ============================================================================
// Main Hybrid Catalog Search Engine
// ============================================================================

const OFFER_SELECT =
  "id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,gallery_images,available_sizes,shipping_cost,free_shipping_threshold,courier,products(id,canonical_name,brand,category,gender,image_url,gallery_images)";

export interface SearchCatalogOptions {
  rawQuery?: string | null;
  keywords?: string[];
  brand?: string | null;
  excludedBrands?: string[] | null;
  category?: string | null;
  productType?: ProductType | null;
  entityTokens?: string[];
  isComparison?: boolean;
  maxPrice?: number | null;
  minPrice?: number | null;
  size?: string | null;
  preferredSize?: string | null;
  gender?: string | null;
  store?: string | null;
  excludedStores?: string[] | null;
  excludedFeatures?: string[] | null;
  freeShipping?: boolean;
  onSale?: boolean;
  minDiscount?: number | null;
  colorTokens?: string[] | null;
  requireColor?: boolean;
  sortBy?: SortByMode | null;
  browseOnly?: boolean;
  excludeIds?: string[] | null;
  semanticQuery?: string | null;
  allowSemantic?: boolean;
  limit?: number;
}

interface SemanticRpcRow extends Omit<RpcProductRow, "lexical_score"> {
  similarity: number;
}

export async function searchCatalogOffers(
  supabase: SupabaseClient,
  opts: SearchCatalogOptions,
): Promise<MatchedProductOut[]> {
  const limit = Math.min(Math.max(opts.limit ?? 35, 1), 80);
  const rawQuery = normalizeQueryTypos(opts.rawQuery ?? (opts.keywords ?? []).join(" "));
  const brand = opts.brand !== undefined ? (opts.brand?.trim() || null) : extractBrand(rawQuery, null);
  const excludedBrands = opts.excludedBrands && opts.excludedBrands.length > 0 ? opts.excludedBrands : null;
  const excludedStores = opts.excludedStores && opts.excludedStores.length > 0
    ? opts.excludedStores.map((s) => s.trim().toLowerCase()).filter(Boolean)
    : null;
  const excludeIds = opts.excludeIds && opts.excludeIds.length > 0
    ? Array.from(new Set(opts.excludeIds.map((id) => id.trim()).filter(Boolean))).slice(0, 300)
    : null;
  const excludeIdSet = excludeIds ? new Set(excludeIds) : null;
  const productType = opts.productType ?? detectSingleProductType(rawQuery);
  const entityTokens = opts.browseOnly ? [] : (opts.entityTokens ?? extractSpecificEntityTokens(rawQuery, brand));
  const isComparison = Boolean(opts.isComparison);

  const searchTerms = opts.browseOnly
    ? []
    : buildCatalogSearchTerms({
        rawQuery,
        keywords: opts.keywords,
        brand,
        productType,
        entityTokens,
        isComparison,
      });

  const blockedCategories = getBlockedCategoriesForProductType(productType);
  const sizeVariantsSql = buildSizeVariantsForSql(opts.size, opts.gender);
  const candidateMap = new Map<string, InternalProduct>();

  const offerBuildOpts = {
    maxPrice: opts.maxPrice,
    minPrice: opts.minPrice,
    size: opts.size,
    gender: opts.gender,
    store: opts.store,
    excludedStores,
    freeShipping: opts.freeShipping,
    onSale: opts.onSale,
    minDiscount: opts.minDiscount,
  };

  const ingestRpcRows = (rows: RpcProductRow[] | null | undefined) => {
    if (!Array.isArray(rows)) return;
    for (const row of rows) {
      if (excludeIdSet?.has(row.id)) continue;
      const built = buildInternalProductFromOffers(
        {
          id: row.id,
          canonical_name: row.canonical_name,
          brand: row.brand,
          category: row.category,
          gender: row.gender,
          image_url: row.image_url,
          gallery_images: row.gallery_images,
        },
        row.offers ?? [],
        offerBuildOpts,
        Number(row.lexical_score ?? 0),
        0,
      );
      if (!built) continue;
      const existing = candidateMap.get(built.id);
      if (!existing) {
        candidateMap.set(built.id, built);
      } else {
        existing.lexical_score = Math.max(existing.lexical_score, built.lexical_score);
      }
    }
  };

  const ingestSemanticRows = (rows: SemanticRpcRow[] | null | undefined) => {
    if (!Array.isArray(rows)) return;
    for (const row of rows) {
      if (excludeIdSet?.has(row.id)) continue;
      const sim = Number(row.similarity ?? 0);
      const existing = candidateMap.get(row.id);
      if (existing) {
        existing.semantic_similarity = Math.max(existing.semantic_similarity, sim);
        continue;
      }
      const built = buildInternalProductFromOffers(
        {
          id: row.id,
          canonical_name: row.canonical_name,
          brand: row.brand,
          category: row.category,
          gender: row.gender,
          image_url: row.image_url,
          gallery_images: row.gallery_images,
        },
        row.offers ?? [],
        offerBuildOpts,
        0,
        sim,
      );
      if (built) candidateMap.set(built.id, built);
    }
  };

  // 1. Primary Product-Level Hybrid Lexical RPC v4 + Parallel Filtered pgvector v2 (RRF)
  const mappedCategory = mapProductTypeToCategory(productType);
  const categoryAllowedForProductType = mappedCategory
    ? (mappedCategory === "running_shoes"
      ? (opts.sortBy === "price_asc" ? ["running_shoes"] : ["running_shoes", "shoes"])
      : mappedCategory === "trail_running"
        ? (opts.sortBy === "price_asc" ? ["trail_running", "running_shoes"] : ["trail_running", "running_shoes", "shoes"])
        : mappedCategory === "top"
          ? ["top", "apparel"]
          : mappedCategory === "pants"
            ? ["pants", "apparel"]
            : mappedCategory === "jacket"
              ? ["jacket", "apparel"]
              : [mappedCategory])
    : null;
  const browseAllowedCategories = searchTerms.length === 0 ? categoryAllowedForProductType : null;

  // When browsing cheapest-first (price_asc), apply realistic category floor prices in SQL so
  // €5 laces / €15 slides / €20 kids shoes don't exhaust the SQL LIMIT before reaching real adult products!
  let effectiveSqlMinPrice = opts.minPrice ?? null;
  if (opts.sortBy === "price_asc") {
    const shoeTypes: ProductType[] = ["shoes", "trail_shoes", "basketball_shoes", "tennis_shoes", "volleyball_shoes", "football_boots"];
    if (productType && shoeTypes.includes(productType)) {
      effectiveSqlMinPrice = Math.max(effectiveSqlMinPrice ?? 0, 35);
    } else if (productType === "gps_watch") {
      effectiveSqlMinPrice = Math.max(effectiveSqlMinPrice ?? 0, 65);
    } else if (productType === "padel_racket" || productType === "tennis_racket") {
      effectiveSqlMinPrice = Math.max(effectiveSqlMinPrice ?? 0, 38);
    }
  }

  const rpcBaseParams = {
    blocked_categories: blockedCategories,
    gender_filter: opts.gender ?? null,
    max_price_filter: opts.maxPrice ?? null,
    min_price_filter: effectiveSqlMinPrice,
    store_filter: opts.store ?? null,
    size_candidates: sizeVariantsSql,
    free_shipping_only: Boolean(opts.freeShipping),
    on_sale_only: Boolean(opts.onSale),
    min_discount_filter: opts.minDiscount ?? null,
    color_tokens: opts.colorTokens && opts.colorTokens.length > 0 ? opts.colorTokens : null,
    require_color: Boolean(opts.requireColor && opts.colorTokens && opts.colorTokens.length > 0),
    excluded_brands: excludedBrands,
    excluded_stores: excludedStores,
    sort_mode: opts.sortBy ?? null,
    exclude_product_ids: excludeIds,
  };

  // Run filtered pgvector semantic search IN PARALLEL with lexical RPC for conceptual / non-SKU queries
  // (e.g. "scarpe maratona", "giacca traspirante", "scarpe ammortizzate ginocchia", "maglia termica inverno")
  const hasDigitEntity = entityTokens.some((t) => /^\d+$/.test(t));
  const semanticQueryStr = opts.semanticQuery?.trim() ? normalizeQueryTypos(opts.semanticQuery) : "";
  const isParallelHybrid = opts.allowSemantic !== false &&
    semanticQueryStr.length >= 3 &&
    !isComparison &&
    !opts.sortBy &&
    !opts.requireColor &&
    entityTokens.length === 0;

  const runFilteredSemantic = async (queryText: string, threshold: number, count: number): Promise<SemanticRpcRow[]> => {
    const emb = await getQueryEmbedding(queryText);
    if (!emb) return [];
    const { data: semRows } = await supabase.rpc("match_products_semantic_v2", {
      query_embedding: emb,
      match_threshold: threshold,
      match_count: count,
      brand_filter: brand,
      excluded_brands: excludedBrands,
      allowed_categories: categoryAllowedForProductType,
      blocked_categories: blockedCategories,
      gender_filter: opts.gender ?? null,
      max_price_filter: opts.maxPrice ?? null,
      min_price_filter: effectiveSqlMinPrice,
      store_filter: opts.store ?? null,
      excluded_stores: excludedStores,
      size_candidates: sizeVariantsSql,
      free_shipping_only: Boolean(opts.freeShipping),
      on_sale_only: Boolean(opts.onSale),
      min_discount_filter: opts.minDiscount ?? null,
      exclude_product_ids: excludeIds,
    });
    return Array.isArray(semRows) ? (semRows as SemanticRpcRow[]) : [];
  };

  const lexicalPromise = (searchTerms.length > 0 || brand || browseAllowedCategories)
    ? supabase.rpc("search_products_catalog_v4", {
        ...rpcBaseParams,
        search_terms: searchTerms.length > 0 ? searchTerms : null,
        brand_filter: brand,
        allowed_categories: browseAllowedCategories,
        result_limit: opts.sortBy === "price_asc" ? 180 : 130,
      }).then((r) => (r.data as RpcProductRow[] | null) ?? null)
    : Promise.resolve<RpcProductRow[] | null>(null);

  const parallelSemanticPromise = isParallelHybrid
    ? runFilteredSemantic(semanticQueryStr, 0.36, 45)
    : Promise.resolve<SemanticRpcRow[]>([]);

  const [primaryLexRows, parallelSemRows] = await Promise.all([lexicalPromise, parallelSemanticPromise]);
  ingestRpcRows(primaryLexRows);
  ingestSemanticRows(parallelSemRows);

  // Fallback for price_asc on running_shoes if narrow filters (e.g. store + size) returned < 10 in running_shoes alone
  if (opts.sortBy === "price_asc" && searchTerms.length === 0 && mappedCategory === "running_shoes" && candidateMap.size < 10) {
    const { data: rpcRows } = await supabase.rpc("search_products_catalog_v4", {
      ...rpcBaseParams,
      search_terms: null,
      brand_filter: brand,
      allowed_categories: ["running_shoes", "shoes"],
      result_limit: 160,
    });
    ingestRpcRows(rpcRows as RpcProductRow[] | null);
  }

  // 2. If brand + exact entity tokens returned 0 (e.g. brand spelled differently in DB), retry without brand_filter
  if (candidateMap.size === 0 && entityTokens.length > 0 && brand) {
    const { data: rpcRows } = await supabase.rpc("search_products_catalog_v4", {
      ...rpcBaseParams,
      search_terms: searchTerms,
      brand_filter: null,
      allowed_categories: null,
      result_limit: 80,
    });
    ingestRpcRows(rpcRows as RpcProductRow[] | null);
  }

  // 3. Fallback Semantic pgvector Search when parallel hybrid didn't run (e.g. non-digit entity query with < 6 lexical hits)
  if (!isParallelHybrid && opts.allowSemantic !== false && semanticQueryStr.length >= 3 && !opts.sortBy && !hasDigitEntity) {
    const lexicalValues = Array.from(candidateMap.values());
    const hasStrongEntityLexical = entityTokens.length > 0 && lexicalValues.some((p) => {
      const probe = `${p.canonical_name} ${p.brand ?? ""}`.toLowerCase();
      return entityTokens.every((et) => new RegExp(`\\b${escapeRegExp(et)}\\b`, "i").test(probe));
    });
    if (!hasStrongEntityLexical && candidateMap.size < 6) {
      const fallbackSemRows = await runFilteredSemantic(semanticQueryStr, entityTokens.length > 0 ? 0.48 : 0.38, 35);
      ingestSemanticRows(fallbackSemRows);
    }
  }

  // 3b. Reciprocal Rank Fusion (RRF) across lexical & semantic candidate lists (k = 40)
  // Items surfaced by BOTH FTS/trigram and pgvector embeddings receive a decisive combined rank boost!
  const allCandidates = Array.from(candidateMap.values());
  const lexRanked = allCandidates
    .filter((p) => p.lexical_score > 0)
    .sort((a, b) => b.lexical_score - a.lexical_score);
  const semRanked = allCandidates
    .filter((p) => p.semantic_similarity > 0)
    .sort((a, b) => b.semantic_similarity - a.semantic_similarity);

  if (semRanked.length > 0) {
    const lexRankById = new Map<string, number>();
    lexRanked.forEach((p, idx) => lexRankById.set(p.id, idx + 1));
    const semRankById = new Map<string, number>();
    semRanked.forEach((p, idx) => semRankById.set(p.id, idx + 1));

    for (const p of allCandidates) {
      const lr = lexRankById.get(p.id) ?? 0;
      const sr = semRankById.get(p.id) ?? 0;
      const lexPart = lr > 0 ? 1 / (40 + lr) : 0;
      const semPart = sr > 0 ? 0.88 / (40 + sr) : 0;
      p.rrf_score = (lexPart + semPart) * 2400;
    }
  }

  // 4. Score, hard-gate, deduplicate, and rank!
  const ranked = scoreAndGateProducts(allCandidates, {
    rawQuery,
    searchTerms,
    brand,
    excludedBrands,
    excludedFeatures: opts.excludedFeatures ?? null,
    productType,
    entityTokens,
    isComparison,
    gender: opts.gender ?? null,
    preferredSize: opts.preferredSize ?? null,
    sortBy: opts.sortBy ?? null,
  });

  return ranked.slice(0, limit).map(stripInternalFields);
}

// ============================================================================
// Multi-Query Parallel Fan-Out Search (Shop-Style Sub-Queries)
// ============================================================================

export interface SubQuerySpec {
  label: string;
  terms: string[];
  role: "primary" | "variant" | "complementary";
  brand?: string | null;
  productType?: ProductType | null;
  entityTokens?: string[];
  browseOnly?: boolean;
  allowSemantic?: boolean;
  limit?: number;
}

export interface MultiQuerySearchResult {
  products: MatchedProductOut[];
  primaryIds: Set<string>;
  roleById: Record<string, "primary" | "variant" | "complementary">;
  executedLabels: string[];
  hasMore: boolean;
}

export function modelFamilyKey(p: MatchedProductOut): string {
  const clean = p.canonical_name
    .toLowerCase()
    .replace(/\s*\((uomo|donna|unisex)\)$/i, "")
    .replace(/\b(scarpe?|sneakers?|su\s+strada|impermeabil[ei]|gore\s*tex|gtx|trail|running|corsa|uomo|donna|se|pro|plus|premium|adv|ess|nn|wp|tr|max|amp|wide|large|narrow|lite|gel|fresh|foam|wave|air|zoom|gts)\b/g, " ")
    .replace(/\b\d+\b/g, " ")
    .replace(/[^a-zàèéìòù\s]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const toks = clean.split(" ").filter((t) => t.length >= 2);
  return toks.slice(0, 2).join(" ") || p.canonical_name.toLowerCase();
}

export async function searchCatalogMultiQuery(
  supabase: SupabaseClient,
  opts: {
    rawQuery: string;
    subQueries: SubQuerySpec[];
    brand?: string | null;
    excludedBrands?: string[] | null;
    category?: string | null;
    productType?: ProductType | null;
    maxPrice?: number | null;
    minPrice?: number | null;
    size?: string | null;
    preferredSize?: string | null;
    gender?: string | null;
    store?: string | null;
    excludedStores?: string[] | null;
    excludedFeatures?: string[] | null;
    freeShipping?: boolean;
    onSale?: boolean;
    minDiscount?: number | null;
    colorTokens?: string[] | null;
    requireColor?: boolean;
    sortBy?: SortByMode | null;
    excludeIds?: string[] | null;
    isComparison?: boolean;
    diversifyModels?: boolean;
    relaxDiversity?: boolean;
    totalLimit?: number;
  },
): Promise<MultiQuerySearchResult> {
  const specs = opts.subQueries.slice(0, 6);
  const totalLimit = Math.min(Math.max(opts.totalLimit ?? 42, 1), 65);
  const excludeIds = opts.excludeIds && opts.excludeIds.length > 0 ? opts.excludeIds : null;
  const excludeIdSet = excludeIds ? new Set(excludeIds) : null;

  // Ensure at most ONE sub-query fires the pgvector embedding call per multi-query fan-out,
  // and ONLY on a sub-query matching the user's brand scope (never restricting a brandless query's vector search to 1 LLM-picked brand!)
  let semanticAssigned = false;
  const perQueryResults = await Promise.all(
    specs.map(async (sq) => {
      const sqBrand = sq.brand !== undefined ? sq.brand : (opts.brand ?? null);
      const sqPType = sq.productType !== undefined ? sq.productType : (opts.productType ?? null);
      const sqEntities = sq.entityTokens ?? [];
      const brandMatchesUserScope = (sqBrand ?? "").toLowerCase() === (opts.brand ?? "").toLowerCase();
      const shouldUseSemantic = Boolean(sq.allowSemantic) && brandMatchesUserScope && !semanticAssigned;
      if (shouldUseSemantic) semanticAssigned = true;

      let items = await searchCatalogOffers(supabase, {
        rawQuery: sq.role === "primary" ? opts.rawQuery : (sq.terms[0] ?? opts.rawQuery),
        keywords: sq.terms,
        brand: sqBrand,
        excludedBrands: opts.excludedBrands ?? null,
        category: opts.category ?? null,
        productType: sqPType,
        entityTokens: sqEntities,
        isComparison: opts.isComparison,
        maxPrice: opts.maxPrice ?? null,
        minPrice: opts.minPrice ?? null,
        size: opts.size ?? null,
        preferredSize: opts.preferredSize ?? null,
        gender: opts.gender ?? null,
        store: opts.store ?? null,
        excludedStores: opts.excludedStores ?? null,
        excludedFeatures: opts.excludedFeatures ?? null,
        freeShipping: opts.freeShipping,
        onSale: opts.onSale,
        minDiscount: opts.minDiscount ?? null,
        colorTokens: opts.colorTokens ?? null,
        requireColor: opts.requireColor,
        sortBy: opts.sortBy ?? null,
        browseOnly: sq.browseOnly ?? false,
        excludeIds,
        semanticQuery: shouldUseSemantic ? (opts.rawQuery || sq.terms.slice(0, 2).join(" ")) : null,
        allowSemantic: shouldUseSemantic,
        limit: sq.limit ?? (sq.role === "primary" ? 28 : 18),
      });

      // Graceful generation fallback: if an exact known-brand version is sold out (e.g. "Asics Nimbus 26"),
      // strip ONLY numeric version tokens and fetch the active line (e.g. "Asics Gel-Nimbus 27/28") strictly without semantic drift.
      if (items.length === 0 && sqBrand && sqEntities.length >= 2) {
        const hasDigit = sqEntities.some((t) => /^\d+$/.test(t));
        const nonDigit = sqEntities.filter((t) => !/^\d+$/.test(t) && t.length >= 3);
        if (hasDigit && nonDigit.length > 0) {
          const relaxedTerms = Array.from(new Set(
            sq.terms
              .map((t) => t.replace(/\b\d+\b/g, " ").replace(/\s+/g, " ").trim())
              .filter((t) => t.length >= 3)
              .concat([`${sqBrand} ${nonDigit.join(" ")}`]),
          ));
          items = await searchCatalogOffers(supabase, {
            rawQuery: `${sqBrand} ${nonDigit.join(" ")}`,
            keywords: relaxedTerms,
            brand: sqBrand,
            excludedBrands: opts.excludedBrands ?? null,
            category: opts.category ?? null,
            productType: sqPType,
            entityTokens: nonDigit,
            isComparison: opts.isComparison,
            maxPrice: opts.maxPrice ?? null,
            minPrice: opts.minPrice ?? null,
            size: opts.size ?? null,
            preferredSize: opts.preferredSize ?? null,
            gender: opts.gender ?? null,
            store: opts.store ?? null,
            excludedStores: opts.excludedStores ?? null,
            excludedFeatures: opts.excludedFeatures ?? null,
            freeShipping: opts.freeShipping,
            onSale: opts.onSale,
            minDiscount: opts.minDiscount ?? null,
            colorTokens: opts.colorTokens ?? null,
            requireColor: opts.requireColor,
            sortBy: opts.sortBy ?? null,
            excludeIds,
            semanticQuery: null,
            allowSemantic: false,
            limit: sq.limit ?? 14,
          });
        }
      }

      return { spec: sq, items };
    }),
  );

  // Merge in strict priority order: primary -> variant -> complementary
  // For broad/category queries (diversifyModels=true), round-robin across sub-queries & cap single model-family/brand flooding
  // so 6 Brooks Ghost variants never crowd out Asics, Hoka, Saucony, New Balance, Adidas!
  const roleOrder: Array<"primary" | "variant" | "complementary"> = ["primary", "variant", "complementary"];
  const merged: MatchedProductOut[] = [];
  const overflow: Array<{ prod: MatchedProductOut; role: "primary" | "variant" | "complementary" }> = [];
  const seenIds = new Set<string>(excludeIdSet ?? []);
  const seenNames = new Set<string>();
  const familyCounts = new Map<string, number>();
  const brandCounts = new Map<string, number>();
  const primaryIds = new Set<string>();
  const roleById: Record<string, "primary" | "variant" | "complementary"> = {};
  const executedLabels: string[] = [];

  for (const r of perQueryResults) {
    if (r.spec.label && !executedLabels.includes(r.spec.label)) {
      executedLabels.push(r.spec.label);
    }
  }

  const maxPerFamily = opts.diversifyModels ? (opts.relaxDiversity ? 4 : 2) : 999;
  const maxPerBrand = (opts.diversifyModels && !opts.brand && !opts.sortBy) ? (opts.relaxDiversity ? 8 : 4) : 999;

  const tryPush = (prod: MatchedProductOut, role: "primary" | "variant" | "complementary") => {
    const nameKey = prod.canonical_name
      .trim()
      .toLowerCase()
      .replace(/\b(sneakers?|scarpe|scarpa|sollevamento\s+pesi)\b/g, " ")
      .replace(/\s+/g, " ")
      .trim() + "|" + (prod.gender ?? "Unisex").toLowerCase();
    if (seenIds.has(prod.id) || seenNames.has(nameKey)) return;
    seenIds.add(prod.id);
    seenNames.add(nameKey);

    const fam = modelFamilyKey(prod);
    const bKey = (prod.brand ?? "unknown").toLowerCase();
    const curFam = familyCounts.get(fam) ?? 0;
    const curBrand = brandCounts.get(bKey) ?? 0;
    if (curFam >= maxPerFamily || curBrand >= maxPerBrand) {
      overflow.push({ prod, role });
      return;
    }
    familyCounts.set(fam, curFam + 1);
    brandCounts.set(bKey, curBrand + 1);
    if (role === "primary") primaryIds.add(prod.id);
    roleById[prod.id] = role;
    merged.push(prod);
  };

  for (const role of roleOrder) {
    const roleGroups = perQueryResults.filter((r) => r.spec.role === role);
    if (opts.diversifyModels && roleGroups.length > 1) {
      const maxLen = Math.max(...roleGroups.map((g) => g.items.length), 0);
      for (let i = 0; i < maxLen && merged.length < totalLimit; i++) {
        for (const g of roleGroups) {
          if (i < g.items.length && merged.length < totalLimit) {
            tryPush(g.items[i], role);
          }
        }
      }
    } else {
      for (const { items } of roleGroups) {
        for (const prod of items) {
          if (merged.length >= totalLimit) break;
          tryPush(prod, role);
        }
        if (merged.length >= totalLimit) break;
      }
    }
    if (merged.length >= totalLimit) break;
  }

  let unusedOverflow = 0;
  for (const { prod, role } of overflow) {
    if (merged.length >= totalLimit) {
      unusedOverflow++;
      continue;
    }
    if (role === "primary") primaryIds.add(prod.id);
    roleById[prod.id] = role;
    merged.push(prod);
  }

  // Determine whether more catalog items are likely available for pagination ("Carica altri")
  const anySubQueryHitLimit = perQueryResults.some((r) => r.items.length >= ((r.spec.limit ?? 20) - 2));
  const hasMore = unusedOverflow > 0 || merged.length >= totalLimit || anySubQueryHitLimit;

  // Apply explicit global sorting across merged sub-queries when requested (e.g. "le più economiche", "sconti più alti")
  if (opts.sortBy === "price_asc") {
    merged.sort((a, b) => (a.best_price ?? 99999) - (b.best_price ?? 99999));
  } else if (opts.sortBy === "price_desc") {
    merged.sort((a, b) => (b.best_price ?? 0) - (a.best_price ?? 0));
  } else if (opts.sortBy === "discount_desc") {
    const maxDisc = (p: MatchedProductOut) => Math.max(
      0,
      ...p.offers.map((o) => o.discount_pct ?? (o.original_price && o.original_price > o.price ? ((o.original_price - o.price) / o.original_price) * 100 : 0)),
    );
    merged.sort((a, b) => maxDisc(b) - maxDisc(a) || (a.best_price ?? 99999) - (b.best_price ?? 99999));
  }

  return {
    products: merged,
    primaryIds,
    roleById,
    executedLabels,
    hasMore,
  };
}

// ============================================================================
// Chat History Loader & Persistence
// ============================================================================

export interface LoadedChatTurn {
  turn_index: number;
  query: string;
  is_follow_up: boolean;
  summary: string | null;
  intent: Record<string, unknown> | null;
  shown_products: Array<{ name: string; price: number | null; brand: string | null; gender: string | null }>;
}

export interface LoadedChatHistory {
  contextState: Record<string, unknown> | null;
  recentTurns: LoadedChatTurn[];
  lastShownProducts: Array<{ name: string; price: number | null; brand: string | null; gender: string | null }>;
}

export async function loadChatHistoryContext(
  supabase: SupabaseClient,
  sessionId: string | null | undefined,
): Promise<LoadedChatHistory> {
  if (!sessionId || !UUID_RE.test(sessionId.trim())) {
    return { contextState: null, recentTurns: [], lastShownProducts: [] };
  }
  const sid = sessionId.trim().toLowerCase();
  try {
    const [sessRes, msgsRes] = await Promise.all([
      supabase
        .from("chat_sessions")
        .select("context_state")
        .eq("id", sid)
        .maybeSingle(),
      supabase
        .from("chat_messages")
        .select("turn_index,query,is_follow_up,conversational_summary,intent_json,results_snapshot_json")
        .eq("session_id", sid)
        .order("turn_index", { ascending: false })
        .limit(5),
    ]);

    const contextState = (sessRes.data?.context_state && typeof sessRes.data.context_state === "object")
      ? (sessRes.data.context_state as Record<string, unknown>)
      : null;

    const rawMsgs = Array.isArray(msgsRes.data) ? [...msgsRes.data].reverse() : [];
    const recentTurns: LoadedChatTurn[] = [];
    let lastShownProducts: Array<{ name: string; price: number | null; brand: string | null; gender: string | null }> = [];

    for (const m of rawMsgs) {
      const snap = m.results_snapshot_json as { results?: Array<Record<string, unknown>> } | null;
      const prods = Array.isArray(snap?.results)
        ? snap!.results.slice(0, 10).map((r) => ({
            name: String(r.canonical_name ?? "").trim(),
            price: r.best_price != null ? Number(r.best_price) : null,
            brand: r.brand ? String(r.brand) : null,
            gender: r.gender ? String(r.gender) : null,
          })).filter((p) => p.name.length > 0)
        : [];
      if (prods.length > 0) {
        lastShownProducts = prods;
      }
      recentTurns.push({
        turn_index: Number(m.turn_index ?? 0),
        query: String(m.query ?? "").trim(),
        is_follow_up: Boolean(m.is_follow_up),
        summary: typeof m.conversational_summary === "string" ? m.conversational_summary.slice(0, 260) : null,
        intent: (m.intent_json && typeof m.intent_json === "object")
          ? (m.intent_json as Record<string, unknown>)
          : null,
        shown_products: prods.slice(0, 6),
      });
    }

    return { contextState, recentTurns, lastShownProducts };
  } catch {
    return { contextState: null, recentTurns: [], lastShownProducts: [] };
  }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function saveChatTurn(
  supabase: SupabaseClient,
  opts: {
    sessionId?: string | null;
    deviceId?: string | null;
    userId?: string | null;
    chatType: string;
    query: string;
    isFollowUp: boolean;
    payload: {
      conversational_header?: string | null;
      conversational_summary?: string | null;
      is_conversational_advice?: boolean;
      intent?: unknown;
      chips?: unknown[];
      results?: MatchedProductOut[];
      curated_sections?: unknown[];
      comparative_cards?: unknown[];
      featured_cards?: unknown[];
      searched_queries?: string[];
      spotlight?: unknown;
      follow_up_suggestions?: string[];
      is_off_topic?: boolean;
      is_unsafe?: boolean;
    };
    contextState?: Record<string, unknown>;
    userImageUrl?: string | null;
  },
): Promise<{ session_id: string; turn_id: string } | null> {
  try {
    const sid = opts.sessionId && UUID_RE.test(opts.sessionId.trim())
      ? opts.sessionId.trim().toLowerCase()
      : crypto.randomUUID().toLowerCase();
    const did = (opts.deviceId ?? "").trim() || "default_device";
    const uid = opts.userId && UUID_RE.test(opts.userId.trim()) ? opts.userId.trim().toLowerCase() : null;
    const nowIso = new Date().toISOString();

    const { data: existing } = await supabase
      .from("chat_sessions")
      .select("id,title,turn_count,preview_image_url,user_id")
      .eq("id", sid)
      .maybeSingle();

    const turnIdx = existing?.turn_count ?? 0;
    const results = opts.payload.results ?? [];
    const previewUrl = results[0]?.image_url ?? opts.userImageUrl ?? existing?.preview_image_url ?? null;

    await supabase.from("chat_sessions").upsert({
      id: sid,
      device_id: did,
      user_id: uid ?? existing?.user_id ?? null,
      chat_type: opts.chatType,
      title: existing?.title ?? opts.query.slice(0, 100),
      subtitle: opts.payload.conversational_header ?? opts.query,
      preview_image_url: previewUrl,
      turn_count: turnIdx + 1,
      context_state: opts.contextState ?? {},
      updated_at: nowIso,
    }, { onConflict: "id" });

    const turnId = crypto.randomUUID().toLowerCase();
    await supabase.from("chat_messages").insert({
      id: turnId,
      session_id: sid,
      turn_index: turnIdx,
      query: opts.query,
      is_follow_up: opts.isFollowUp,
      is_conversational_advice: opts.payload.is_conversational_advice ?? false,
      conversational_header: opts.payload.conversational_header ?? null,
      conversational_summary: opts.payload.conversational_summary ?? null,
      intent_json: opts.payload.intent ?? null,
      chips_json: opts.payload.chips ?? [],
      results_snapshot_json: {
        results: results.slice(0, 35),
        curated_sections: (opts.payload.curated_sections ?? []).slice(0, 5),
        comparative_cards: (opts.payload.comparative_cards ?? []).slice(0, 5),
        featured_cards: (opts.payload.featured_cards ?? []).slice(0, 4),
        searched_queries: (opts.payload.searched_queries ?? []).slice(0, 6),
        spotlight: opts.payload.spotlight ?? null,
      },
      follow_up_suggestions_json: opts.payload.follow_up_suggestions ?? [],
      is_off_topic: opts.payload.is_off_topic ?? false,
      is_unsafe: opts.payload.is_unsafe ?? false,
      user_image_url: opts.userImageUrl ?? null,
      created_at: nowIso,
    });

    return { session_id: sid, turn_id: turnId };
  } catch {
    return null;
  }
}
