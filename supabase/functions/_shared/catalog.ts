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

export async function getQueryEmbedding(text: string): Promise<number[] | null> {
  const apiKey = (Deno.env.get("OPENROUTER_API_KEY") ?? "").trim();
  const cleaned = text.trim();
  if (!apiKey || !cleaned) return null;
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
    return Array.isArray(emb) ? emb : null;
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

export function extractAllBrands(text: string): string[] {
  const norm = normalizeQueryTypos(text).toLowerCase();
  const found: string[] = [];
  for (const b of KNOWN_BRANDS) {
    const bLow = b.toLowerCase();
    if (bLow === "on") {
      if (/\bon\s+(?:running|cloud\w*)\b/i.test(norm) && !found.includes("On")) found.push("On");
      continue;
    }
    if (new RegExp(`\\b${escapeRegExp(bLow)}\\b`, "i").test(norm) && !found.includes(b)) {
      found.push(b);
    }
  }
  const sub = detectSubBrand(norm);
  if (sub && !found.includes(sub[0])) found.push(sub[0]);
  return found;
}

export function extractBrand(text: string, fallback?: string | null): string | null {
  const norm = normalizeQueryTypos(text).toLowerCase();
  for (const b of KNOWN_BRANDS) {
    const bLow = b.toLowerCase();
    // Avoid matching short brand "on" inside ordinary words
    if (bLow === "on") {
      if (/\bon\s+(?:running|cloud\w*)\b/i.test(norm)) return "On";
      continue;
    }
    if (new RegExp(`\\b${escapeRegExp(bLow)}\\b`, "i").test(norm)) return b;
  }
  const sub = detectSubBrand(norm);
  if (sub) return sub[0];
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
  // Colors
  "nero", "nera", "neri", "nere", "bianco", "bianca", "bianchi", "bianche", "blu", "rosso", "rossa",
  "rossi", "rosse", "verde", "verdi", "grigio", "grigia", "giallo", "gialla", "arancione", "rosa", "viola",
  "black", "white", "blue", "red", "green", "grey", "gray", "yellow", "orange", "pink", "purple",
  "lungo", "lunghi", "corto", "corti", "alto", "alta", "alti", "alte", "basso", "bassa",
  "compressione", "compression", "tecnica", "tecnico", "tecnici", "tecniche", "pro",
]);

/**
 * Extracts specific model / sub-brand / generation tokens from a query (e.g. ["forerunner", "165"] or ["zoom", "fly", "6"]).
 * Returns [] for pure category/brand queries like "leggins under armour da corsa".
 */
export function extractSpecificEntityTokens(query: string, brand?: string | null): string[] {
  if (!query || !query.trim()) return [];
  let t = normalizeQueryTypos(query).toLowerCase();
  t = t.replace(/\bs[/\-]lab\b/g, " lab ");
  // Remove price constraints & measurement/unit tokens (e.g. "85kg", "10km", "500ml", "150€")
  t = t.replace(/\b(?:sotto\s*i?|sopra\s*i?|meno\s*di|pi[uù]\s*di|fino\s*a|budget\s*(?:di)?|max|min|massimo|minimo|entro\s*i?)\s*\d+(?:[.,]\d+)?\s*(?:€|euro|eur)?\b/g, " ");
  t = t.replace(/\b\d+(?:[.,]\d+)?\s*(?:€|euro|eur|km|kg|chili|g|gr|mm|cm|l|lt|ml|%|min|h)\b/g, " ");
  t = t.replace(/\b\d+(?:[.,]\d+)?(?:km|kg|ml|mm|cm|gr)\b/g, " ");
  // Remove size constraints
  t = t.replace(/\b(?:taglia|taglie|numero|misura|size|eu|us|uk|tg\.?)\s*(?:\d{2}(?:[.,]\d)?|[xsml]{1,3})\b/g, " ");
  t = t.replace(/(?<![\d.,])\b(?:3[5-9]|4[0-9])[.,](?:5|3|7|2|8)\b/g, " ");
  t = t.replace(/\b(?:1\s*\/\s*[24]\s*(?:di\s+)?zip|2\s*in\s*1|2in1|calcio\s*a\s*[57])\b/g, " ");

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

export function detectSingleProductType(rawText: string): ProductType | null {
  const t = normalizeQueryTypos(rawText).toLowerCase();
  if (!t) return null;

  // 1. Explicit apparel & accessories (most specific first!)
  if (/\b(long[\s-]*sleeve|manic(?:a|he)\s*lung(?:a|he)+|magli[ae]\s*(?:a\s*)?manic(?:a|he)\s*lung(?:a|he)+|magli[ae]\s*termic(?:a|he)|intimo\s*termico|1\/2\s*zip|1\/4\s*zip|half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip)\b/.test(t)) {
    return "long_sleeve_top";
  }
  if (/\b(canott[ae]|canottier[ae]|singlet|tank\s*top|sleeveless|smanicat[aoe])\b/.test(t)) {
    return "singlet_top";
  }
  if (/\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae]+|t[\s-]*shirt|magliett[ae]|magli[ae](?!\s*(?:cinturin|orolog)))\b/.test(t)) {
    return "short_sleeve_top";
  }
  if (/\b(felp[ae]|hoodie|sweatshirt)\b/.test(t)) {
    return "top";
  }
  if (/\b(giacc(?:a|he)|jacket|rain\s*jacket|antivento|windbreaker|windproof|k[\s-]*way|gilet\s*antivento|guscio|shell\s*jacket|anorak|antipioggia)\b/.test(t)) {
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
  if (/\b(occhialin[oi]|occhial[ie]\s*(?:da\s*)?nuoto|swim(?:ming)?\s*goggles|goggles|swimsuit|nuot[ao]|nuotare|piscina|cuffi[ae]\s*(?:da\s*)?nuoto|costum[ei]\s*(?:da\s*)?(?:nuoto|bagno)|pinn[ae]\s*(?:da\s*)?nuoto)\b/.test(t)) {
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
  if (/\b(racchett[ae]|padel\s*(?:racket|racquet)|pala\s*padel|bullpadel|nox\s*at10|padel)\b/.test(t) && !/\b(scarp[ae]|shoes?)\b/.test(t)) {
    return "padel_racket";
  }
  if (/\b(rull[oi]|smart\s*trainer|wahoo\s*kickr|tacx\s*(?:flux|neo))\b/.test(t)) {
    return "smart_trainer";
  }
  if (/\b(gel\s*(?:energetic[oi]|isotonic[oi]|enervit|maurten|sis)|energy\s*gels?|electrolytes?|maltodestrin[ae]|barrett[ae]|integrator[ei]|sali\s*minerali|enervit|maurten|namedsport)\b/.test(t)) {
    return "nutrition";
  }

  // 3. Sport-specific footwear
  if (/\b(scarp[ae]\s*(?:da\s*)?calcio|scarp[ae]\s*(?:da\s*)?calcetto|football\s*boots?|soccer\s*cleats?|scarpin[oi]|calcetto|futsal|mercurial|superfly|predator|tiempo|phantom|copa\s*pure|top\s*sala|top\s*flex|magnetico)\b/.test(t) ||
      (/\bcalcio\s*a\s*[57]\b/.test(t) && !/\b(magli[ae]|kit|pantaloncin[oi]|pallon[ei]|guant[oi])\b/.test(t))) {
    return "football_boots";
  }
  if (/\b(basket|basketball|pallacanestro|lebron|kobe|giannis|luka|caitlin|sabrina|kd\s*\d+|harden|dame)\b/.test(t) &&
      !/\b(magli[ae]|jersey|canott[ae]|pantaloncin[oi]|shorts?|calz[ae]|pallon[ei]|canestro)\b/.test(t)) {
    return "basketball_shoes";
  }
  if (/\b(tennis|terra\s*battuta|gel[\s-]*resolution|court\s*ff|dedicate|nikecourt|barricade)\b/.test(t) &&
      !/\b(racchett[ae]|racket|racquet|pallin[ae]|abbigliamento|pantaloncin[oi]|shorts?|magli[ae])\b/.test(t)) {
    return "tennis_shoes";
  }
  if (/\b(pallavolo|volley|volleyball|sky\s*elite|metarise|wave\s*lightning|wave\s*momentum|netburner)\b/.test(t) &&
      !/\b(ginocchier[ae]|pallon[ei]|magli[ae]|pantaloncin[oi]|manicotti)\b/.test(t)) {
    return "volleyball_shoes";
  }

  // 4. Trail vs Road Shoes
  if (/\b(trail|sterrato|montagna|sentier[oi]|speedgoat|cascadia|trabuco|speedcross|ultra\s*raptor|peregrine|bushido|hierro|mafate|tecton)\b/.test(t) &&
      !/\b(zain[oi]|gilet|vest|backpack|pack|flask|bottle|giacc[ae]|jacket|pantalon|pants|shorts?|tights?|magli|shirt|tee|orologi|watch|poles|bastoncini|gel|belt|marsupio|hat|cap|gloves|socks)\b/.test(t)) {
    return "trail_shoes";
  }
  if (/\b(scarp[ae]|sneakers?|calzatur[ae]|zoom\s*fly|pegasus|vomero|alphafly|vaporfly|streakfly|invincible|structure|nimbus|kayano|cumulus|novablast|superblast|metaspeed|clifton|bondi|mach|cielo|rincon|glycerin|ghost|hyperion|adrenaline|endorphin|triumph|ride|tempus|deviate|velocity|magmax|adizero\s*(?:adios|boston|takumi|sl|evo|prime|dropset)|dropset|metcon|nano|ultraboost|supernova|cloudmonster|cloudsurfer|cloudboom|cloudrunner|cloudstratus|wave\s*rider|wave\s*rebellion|wave\s*sky|fresh\s*foam|fuelcell|1080|rebel|hyrox|infinite\s*(?:elite|pro))\b/.test(t)) {
    return "shoes";
  }
  if (/\b(running|corsa|correre|maratona|mezza\s*maratona|ammortizzat[ae]|pronazione|supinazione)\b/.test(t) &&
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
      ];
    case "leggings_tights":
    case "shorts":
    case "pants":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "top", "jacket", "socks",
        "strap", "mount", "case", "sensor", "racket", "padel", "swim", "winter_sports",
      ];
    case "long_sleeve_top":
    case "short_sleeve_top":
    case "singlet_top":
    case "top":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "padel", "cycling", "pants", "jacket",
        "socks", "underwear", "swim", "bag", "gloves", "strap", "mount", "case",
        "racket", "sensor", "winter_sports",
      ];
    case "jacket":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "gps_watch",
        "eyewear", "hydration", "nutrition", "pants", "socks", "strap", "mount", "case", "sensor", "racket",
      ];
    case "socks":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants",
        "gps_watch", "eyewear", "padel", "cycling", "hydration", "nutrition", "strap", "mount", "case",
      ];
    case "gps_watch":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks", "apparel",
        "eyewear", "nutrition", "padel", "case", "strap", "mount", "cycling",
        "bag", "hydration", "gloves", "underwear", "swim", "racket", "sensor",
      ];
    case "heart_rate_monitor":
      return [
        "running_shoes", "trail_running", "shoes", "football_boots", "top", "jacket",
        "pants", "socks", "apparel", "eyewear", "nutrition", "padel", "hydration", "swim", "racket", "case", "mount",
      ];
    case "bike_computer":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks", "apparel",
        "eyewear", "nutrition", "padel", "case", "strap", "mount", "gps_watch", "sensor",
      ];
    case "eyewear":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "padel", "nutrition", "hydration", "strap", "mount", "sensor",
      ];
    case "hydration":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "eyewear", "padel", "nutrition", "strap", "mount", "sensor",
      ];
    case "padel_racket":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "eyewear", "gps_watch", "nutrition", "hydration", "strap", "mount", "sensor",
      ];
    case "football_boots":
      return [
        "top", "jacket", "pants", "socks", "gps_watch", "eyewear", "hydration",
        "nutrition", "padel", "cycling", "swim", "case", "strap", "mount", "sensor",
      ];
    case "swim":
      return [
        "running_shoes", "trail_running", "shoes", "top", "jacket", "pants", "socks",
        "gps_watch", "padel", "cycling", "nutrition", "hydration", "racket",
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
  if (blocked && cat && blocked.includes(cat)) return false;

  switch (productType) {
    case "shoes":
    case "trail_shoes": {
      if (isApparelOnlySizes(prod.available_sizes ?? [])) return false;
      // Block apparel/tech/accessories/mats/insoles/bike tires/headsets including French & Italian store abbreviations
      if (/\b(t[\s-]*rex|smartwatch|orologi[o]?|garmin|amazfit|polar|suunto|coros|igpsport|bsc\d+|ciclocomputer|bike\s*computer|tappetino|yogamat|yoga\s*mat|solett[ae]|insole|plantar[ei]|lacci\b|stringhe\b|deodorant|impermeabilizzant|asciugascarpe|telo\s*microfibra|asciugaman[oi]|towel|borracc(?:ia|e)|soft\s*flask|zain[oi]|backpack|calz[ae]|calzin[oi]|socks?|socquette|light\s*crew|t[\s-]*shirt|magli[ae]|magliett[ae]|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet|snglt|tank\b|crop\b|cropped|tee\b|jsy\b|jersey\b|top\s*ss\b|crew\s*top\b|trk\s*jkt\b|pant\s*kp\b|dry\s*park\d*|park\s*20\b|woven\b|felp[ae]|hoodie|hooded|polare|fleece|giacc(?:a|he)|jacket|jkt\b|piumin[oi]|tuta\b|pantaloncin[oi]|shorts?|leggings?|tights?|calzamagli[ae]|fuseaux|pantalon[ie]|pants\b|coscial[ei]|gonn[ae]|skirt|2in1|2\s*in\s*1|cappellin[oi]|cappell[oi]|\bcap\b|berrett[oi]|beanie|visier[ae]|scaldacollo|scaldamuscoli|balaclava|neck\s*gaiter|gaiter\b|bandana|manicott[oi]|marsupi[oi]|run\s*belt|borson[ei]|bors[ae]|sacca\b|tote\b|duffel|guant[oi]|gloves|occhial[ie]|gel\s*energetico|barrett[ae]|rull[oi]|casc(?:o|hi)|helmet|racchett[ae]|pala\s*padel|reggisen[oi]|\bbra\b|slip\b|boxer\b|crankbrothers|cuffi[ae]|scarpin[oi]|calcio|calcetto|futsal|mercurial|predator|copertone|pneumatic|24x1|rig\s*24)\b/.test(fullText)) {
        return false;
      }
      if (!/\b(ciabatt[ae]|slide|recovery|recupero|sandal[oi]|infradito)\b/.test(qLow)) {
        if (/\b(ciabatt[ae]|adilette|infradito|klapki|sandal[oi])\b/.test(fullText)) return false;
      }
      if (!/\b(shox|air\s*force|force\s*1|dunk|cortez|blazer|lifestyle|casual|street|air\s*max\s*(?:90|95|97|plus|tn))\b/.test(qLow)) {
        if (/\b(shox|air\s*force|force\s*1|dunk\b|cortez|blazer\s*mid|blazer\s*low|air\s*max\s*(?:90|95|97|plus|tn)|street\s*jam|kappa\s*(?:kombat|kontroll))\b/.test(fullText)) return false;
      }
      if (!/\b(pista|chiodat|spike|atletica|campestre|cross\s*country|\bxcs\b|dragonfly|maxfly|avanti|ambition|rugby|pallamano|handball)\b/.test(qLow)) {
        if (/\b(chiodat[ae]|track\s*(?:and\s*)?field|\bxcs\b|adizero\s*(?:avanti|ambition|finesse)|prime\s*sp|distancestar|sprintstar|throwstar|jumpstar|dragonfly|maxfly|zoom\s*rival|metaspeed\s*(?:md|sp|ld)|rugby|pallamano|handball)\b/.test(fullText)) {
          return false;
        }
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
      if (/\b(scarp[ae]|shoe|sneaker|cappellin[oi]|cappell[oi]|\bcap\b|berrett[oi]|scaldacollo|scaldamuscoli|balaclava|calz[ae]|calzin[oi]|socks?|pantaloncin[oi]|shorts?|leggings?|tights?|calzamagli[ae]|pantalon[ie]|zain[oi]|bors[ae]|sacca\b|tote\b|orologi[o]?|occhial[ie]|piumin[oi]|giacc(?:a|he)|jacket|jkt\b|canott[ae]|singlet|sleeveless|smanicat[ao]|senza\s*maniche|gilet\b|vest\b|manic(?:a|he)\s*cort[ae]|short[\s-]*sleeve|reggiseno|\bbra\b)\b/.test(fullText)) {
        return false;
      }
      if (!/\b(calcio|inter|squadra|replica|stadium|partita)\b/.test(qLow)) {
        if (/\b(calcio\s*replica|stadium\s*se|pre[\s-]*partita|maglia\s*(?:da\s*)?calcio)\b/.test(fullText)) {
          return false;
        }
      }
      return /\b(long[\s-]*sleeve|longsleeve|manic(?:a|he)\s*lung(?:a|he)|l\/s\b|\bls\b|half[\s-]*zip|quarter[\s-]*zip|mezza\s*zip|zip\s*(?:a\s*)?1\s*[\/\s]\s*[24]|1\s*[\/\s]\s*[24][\s-]*(?:di\s+)?zip|zip\s*(?:a\s*)?met[aà]\s*lunghezza|termic[aohe]|therma[\s-]*fit|active\s*warm|warmalite|warm\b|midlayer|mid[\s-]*layer|fleece|felp[ae]|pile\b|polar\b|girocollo|crewneck|crew\s*neck|pullover|mock\b|first\s*layer|base\s*layer|wolf\s*grid|wolf\s*tree|wolf\s*lichen|chinati|tuff\s*fleece)\b/.test(fullText);
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
  long_sleeve_top: ["long sleeve", "manica lunga", "half zip", "maglia termica"],
  short_sleeve_top: ["t-shirt", "maglia", "short sleeve", "manica corta"],
  singlet_top: ["canotta", "singlet", "tank"],
  top: ["maglia", "t-shirt", "long sleeve"],
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

const CLEAN_FILLER_RE = /\b(da\s+corsa|per\s+correre|per\s+la\s+corsa|da\s+running|per\s+running|miglior[ie]?|offerte?|prezzo|sotto\s+i?\s*\d+\s*(?:€|euro)?|meno\s+di\s*\d+\s*(?:€|euro)?|taglia\s*\S+|uomo|donna|unisex)\b/gi;

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
      .replace(CLEAN_FILLER_RE, " ")
      .replace(/\s+/g, " ")
      .trim();
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

  // 1. Exact entity / model query (non-comparison): anchor with exact model phrase first!
  if (entityTokens.length > 0 && !isComparison) {
    const entityPhrase = entityTokens.join(" ");
    if (brand) add(`${brand} ${entityPhrase}`);
    add(entityPhrase);
  }

  // 2. Clean LLM/caller keywords
  for (const kw of opts.keywords ?? []) {
    const cleaned = normalizeQueryTypos(kw)
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

  // 3. For category + brand (or pure category) queries without specific model tokens, expand bilingual synonyms!
  // Always expand apparel synonyms (leggings/tights/calzamaglia/fuseaux); expand other categories when < 2 terms.
  if (entityTokens.length === 0 && pt && CATEGORY_SYNONYMS[pt] && (APPAREL_SYNONYM_TYPES.has(pt) || out.length < 2)) {
    for (const syn of CATEGORY_SYNONYMS[pt]!) {
      if (brand) {
        add(`${brand} ${syn}`);
      } else {
        add(syn);
      }
    }
  }

  // 4. Fallback to cleaned raw query only if we have no brand+category query (brand+shoes works directly via brand_filter!)
  if (out.length === 0 && opts.rawQuery && !(brand && (pt === "shoes" || pt === "trail_shoes"))) {
    add(opts.rawQuery);
  }

  return out.slice(0, 8);
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
  },
  lexicalScore: number,
  semanticSim: number,
): InternalProduct | null {
  const storeFilter = opts.store?.trim().toLowerCase() || null;
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
    if (!sizeMatches(r.available_sizes, opts.size, reqFemale)) continue;

    const dedupKey = `${r.store_id.toLowerCase()}|${r.product_url}`;
    if (seenOfferKeys.has(dedupKey)) continue;
    seenOfferKeys.add(dedupKey);

    const ship = Number(r.shipping_cost ?? 0);
    const total = Math.round((price + ship) * 100) / 100;
    const isFree = ship === 0;
    const orig = r.original_price != null ? Number(r.original_price) : null;
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

function scoreAndGateProducts(
  candidates: InternalProduct[],
  opts: {
    rawQuery: string;
    searchTerms: string[];
    brand: string | null;
    productType: ProductType | null;
    entityTokens: string[];
    isComparison?: boolean;
    gender: string | null;
    preferredSize?: string | null;
  },
): InternalProduct[] {
  const qLow = normalizeQueryTypos(opts.rawQuery).toLowerCase();
  const brandLow = opts.brand?.trim().toLowerCase() ?? null;
  const entityTokens = opts.entityTokens;
  const isComparison = Boolean(opts.isComparison);

  // Extract model digits from entity tokens (e.g. "165" in Forerunner 165, "6" in Zoom Fly 6)
  const queryModelDigits = new Set<string>(
    entityTokens.filter((t) => /^\d+$/.test(t)),
  );
  const wantsTrail = /\b(trail|sterrato|montagna|sentier[oi]|fango|bosco)\b/.test(qLow);
  const wantsWaterproof = /\b(gtx|gore[\s-]*tex|impermeabil[ei]|pioggia|waterproof|shield)\b/.test(qLow);
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

    // 2. Strict brand gate when user requested a brand
    if (brandLow) {
      const variants = [brandLow, brandLow.replace(/-/g, " "), brandLow.replace(/\s+/g, "-")];
      const matchesBrand = variants.some((v) => pbrand.includes(v) || pname.includes(v));
      if (!matchesBrand) continue;
    }

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

    // Search term phrase & token overlap
    for (let i = 0; i < opts.searchTerms.length; i++) {
      const term = opts.searchTerms[i].toLowerCase().trim();
      if (!term) continue;
      const mult = i === 0 ? 1.4 : (i < 3 ? 1.15 : 1.0);
      if (pname === term) score += 200 * mult;
      else if (pname.includes(term)) score += 120 * mult;
      else if (combined.includes(term)) score += 70 * mult;
    }

    // Product-type & feature boosts
    if (opts.productType === "leggings_tights") {
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

    // Semantic similarity bonus (moderate so it never overrides exact model match!)
    if (prod.semantic_similarity > 0.40) {
      score += prod.semantic_similarity * 50;
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

  // 6. Relative relevance score cutoff (drop weak noise tail)
  const topScore = Math.max(...finalList.map((p) => p.relevance_score));
  if (topScore >= 120) {
    const minKeep = Math.max(20, topScore * (entityTokens.length > 0 ? 0.35 : 0.20));
    const trimmed = finalList.filter((p) => p.relevance_score >= minKeep);
    if (trimmed.length > 0) finalList = trimmed;
  }

  // 7. Sort by relevance FIRST, then multi-store offers, then best price
  finalList.sort((a, b) => {
    if (Math.abs(b.relevance_score - a.relevance_score) > 1.0) {
      return b.relevance_score - a.relevance_score;
    }
    if (b.offers.length !== a.offers.length) return b.offers.length - a.offers.length;
    return (a.best_price ?? 9999) - (b.best_price ?? 9999);
  });

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
  semanticQuery?: string | null;
  allowSemantic?: boolean;
  limit?: number;
}

export async function searchCatalogOffers(
  supabase: SupabaseClient,
  opts: SearchCatalogOptions,
): Promise<MatchedProductOut[]> {
  const limit = Math.min(Math.max(opts.limit ?? 35, 1), 60);
  const rawQuery = normalizeQueryTypos(opts.rawQuery ?? (opts.keywords ?? []).join(" "));
  const brand = opts.brand?.trim() || extractBrand(rawQuery, null);
  const productType = opts.productType ?? detectSingleProductType(rawQuery);
  const entityTokens = opts.entityTokens ?? extractSpecificEntityTokens(rawQuery, brand);
  const isComparison = Boolean(opts.isComparison);

  const searchTerms = buildCatalogSearchTerms({
    rawQuery,
    keywords: opts.keywords,
    brand,
    productType,
    entityTokens,
    isComparison,
  });

  const blockedCategories = getBlockedCategoriesForProductType(productType);
  const candidateMap = new Map<string, InternalProduct>();

  const ingestRpcRows = (rows: RpcProductRow[] | null | undefined) => {
    if (!Array.isArray(rows)) return;
    for (const row of rows) {
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
        {
          maxPrice: opts.maxPrice,
          minPrice: opts.minPrice,
          size: opts.size,
          gender: opts.gender,
          store: opts.store,
        },
        Number(row.lexical_score ?? 0),
        0,
      );
      if (!built) continue;
      const existing = candidateMap.get(built.id);
      if (!existing || built.lexical_score > existing.lexical_score) {
        candidateMap.set(built.id, built);
      }
    }
  };

  // 1. Primary Product-Level Hybrid Lexical RPC (single fast roundtrip!)
  // For pure category+filter queries (e.g. "scarpe running taglia 43 sotto 120 euro") where searchTerms & brand are empty,
  // browse the mapped DB category directly so Postgres returns all brands matching the size/price/gender filters.
  const mappedCategory = mapProductTypeToCategory(productType);
  const browseAllowedCategories = (searchTerms.length === 0 && !brand && mappedCategory)
    ? (mappedCategory === "running_shoes" ? ["running_shoes", "shoes"] : [mappedCategory])
    : null;

  if (searchTerms.length > 0 || brand || browseAllowedCategories) {
    const { data: rpcRows } = await supabase.rpc("search_products_catalog", {
      search_terms: searchTerms.length > 0 ? searchTerms : null,
      brand_filter: brand,
      allowed_categories: browseAllowedCategories,
      blocked_categories: blockedCategories,
      gender_filter: opts.gender ?? null,
      max_price_filter: opts.maxPrice ?? null,
      min_price_filter: opts.minPrice ?? null,
      store_filter: opts.store ?? null,
      result_limit: 80,
    });
    ingestRpcRows(rpcRows as RpcProductRow[] | null);
  }

  // 2. If brand + exact entity tokens returned 0 (e.g. brand spelled differently in DB), retry without brand_filter
  if (candidateMap.size === 0 && entityTokens.length > 0 && brand) {
    const { data: rpcRows } = await supabase.rpc("search_products_catalog", {
      search_terms: searchTerms,
      brand_filter: null,
      allowed_categories: null,
      blocked_categories: blockedCategories,
      gender_filter: opts.gender ?? null,
      max_price_filter: opts.maxPrice ?? null,
      min_price_filter: opts.minPrice ?? null,
      store_filter: opts.store ?? null,
      result_limit: 60,
    });
    ingestRpcRows(rpcRows as RpcProductRow[] | null);
  }

  // 3. Conditional Semantic pgvector Search:
  // ONLY run semantic search when lexical results are sparse (< 6) OR query is descriptive/advisory
  // (no exact entity tokens matched). NEVER run semantic search to pollute exact SKU matches!
  const lexicalValues = Array.from(candidateMap.values());
  const hasStrongEntityLexical = entityTokens.length > 0 && lexicalValues.some((p) => {
    const probe = `${p.canonical_name} ${p.brand ?? ""}`.toLowerCase();
    return entityTokens.every((et) => new RegExp(`\\b${escapeRegExp(et)}\\b`, "i").test(probe));
  });

  const isDescriptive = entityTokens.length === 0 && rawQuery.split(/\s+/).length >= 4;
  const shouldRunSemantic = opts.allowSemantic !== false &&
    Boolean(opts.semanticQuery && opts.semanticQuery.trim().length >= 3) &&
    !hasStrongEntityLexical &&
    (candidateMap.size < 6 || isDescriptive);

  if (shouldRunSemantic && opts.semanticQuery) {
    const emb = await getQueryEmbedding(normalizeQueryTypos(opts.semanticQuery));
    if (emb) {
      const threshold = entityTokens.length > 0 ? 0.50 : 0.42;
      const { data: semMatches } = await supabase.rpc("match_products_semantic", {
        query_embedding: emb,
        match_threshold: threshold,
        match_count: 30,
      });
      if (Array.isArray(semMatches) && semMatches.length > 0) {
        const simById = new Map<string, number>();
        for (const m of semMatches as Array<{ id: string; similarity?: number }>) {
          if (m.id) simById.set(m.id, Number(m.similarity ?? 0));
        }
        const missingIds = Array.from(simById.keys()).filter((id) => !candidateMap.has(id));
        // Update similarity on already-fetched lexical hits
        for (const [id, sim] of simById.entries()) {
          const ex = candidateMap.get(id);
          if (ex) ex.semantic_similarity = Math.max(ex.semantic_similarity, sim);
        }
        if (missingIds.length > 0) {
          let q = supabase
            .from("store_offers")
            .select(OFFER_SELECT)
            .in("product_id", missingIds.slice(0, 25))
            .limit(180);
          if (opts.maxPrice != null) q = q.lte("current_price", opts.maxPrice);
          if (opts.minPrice != null) q = q.gte("current_price", opts.minPrice);
          const { data: offerRows } = await q;
          if (Array.isArray(offerRows) && offerRows.length > 0) {
            const grouped = new Map<string, { meta: NonNullable<RawOfferRow["products"]> & { id: string; canonical_name: string }; offers: RawOfferRow[] }>();
            for (const r of offerRows as RawOfferRow[]) {
              const pid = r.product_id;
              if (!pid || r.products?.category === "non_sport") continue;
              let entry = grouped.get(pid);
              if (!entry) {
                entry = {
                  meta: {
                    id: pid,
                    canonical_name: r.products?.canonical_name || r.raw_title,
                    brand: r.products?.brand ?? null,
                    category: r.products?.category ?? null,
                    gender: r.products?.gender ?? null,
                    image_url: r.products?.image_url ?? null,
                    gallery_images: r.products?.gallery_images ?? null,
                  },
                  offers: [],
                };
                grouped.set(pid, entry);
              }
              entry.offers.push(r);
            }
            for (const [pid, { meta, offers }] of grouped.entries()) {
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
                {
                  maxPrice: opts.maxPrice,
                  minPrice: opts.minPrice,
                  size: opts.size,
                  gender: opts.gender,
                  store: opts.store,
                },
                0,
                simById.get(pid) ?? 0,
              );
              if (built) candidateMap.set(pid, built);
            }
          }
        }
      }
    }
  }

  // 4. Score, hard-gate, deduplicate, and rank!
  const ranked = scoreAndGateProducts(Array.from(candidateMap.values()), {
    rawQuery,
    searchTerms,
    brand,
    productType,
    entityTokens,
    isComparison,
    gender: opts.gender ?? null,
    preferredSize: opts.preferredSize ?? null,
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
  allowSemantic?: boolean;
  limit?: number;
}

export interface MultiQuerySearchResult {
  products: MatchedProductOut[];
  primaryIds: Set<string>;
  roleById: Record<string, "primary" | "variant" | "complementary">;
  executedLabels: string[];
}

export async function searchCatalogMultiQuery(
  supabase: SupabaseClient,
  opts: {
    rawQuery: string;
    subQueries: SubQuerySpec[];
    brand?: string | null;
    category?: string | null;
    productType?: ProductType | null;
    maxPrice?: number | null;
    minPrice?: number | null;
    size?: string | null;
    preferredSize?: string | null;
    gender?: string | null;
    store?: string | null;
    isComparison?: boolean;
    totalLimit?: number;
  },
): Promise<MultiQuerySearchResult> {
  const specs = opts.subQueries.slice(0, 5);
  const totalLimit = Math.min(Math.max(opts.totalLimit ?? 36, 1), 60);

  const perQueryResults = await Promise.all(
    specs.map(async (sq) => {
      const sqBrand = sq.brand !== undefined ? sq.brand : (opts.brand ?? null);
      const sqPType = sq.productType !== undefined ? sq.productType : (opts.productType ?? null);
      const sqEntities = sq.entityTokens ?? [];
      let items = await searchCatalogOffers(supabase, {
        rawQuery: sq.role === "primary" ? opts.rawQuery : (sq.terms[0] ?? opts.rawQuery),
        keywords: sq.terms,
        brand: sqBrand,
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
        semanticQuery: sq.allowSemantic ? (sq.terms.slice(0, 2).join(" ") || opts.rawQuery) : null,
        allowSemantic: sq.allowSemantic ?? false,
        limit: sq.limit ?? (sq.role === "primary" ? 20 : 12),
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
            semanticQuery: null,
            allowSemantic: false,
            limit: sq.limit ?? 12,
          });
        }
      }

      return { spec: sq, items };
    }),
  );

  // Merge in strict priority order: primary -> variant -> complementary
  const roleOrder: Array<"primary" | "variant" | "complementary"> = ["primary", "variant", "complementary"];
  const merged: MatchedProductOut[] = [];
  const seenIds = new Set<string>();
  const seenNames = new Set<string>();
  const primaryIds = new Set<string>();
  const roleById: Record<string, "primary" | "variant" | "complementary"> = {};
  const executedLabels: string[] = [];

  for (const r of perQueryResults) {
    if (r.spec.label && !executedLabels.includes(r.spec.label)) {
      executedLabels.push(r.spec.label);
    }
  }

  for (const role of roleOrder) {
    for (const { spec, items } of perQueryResults) {
      if (spec.role !== role) continue;
      for (const prod of items) {
        const nameKey = prod.canonical_name
          .trim()
          .toLowerCase()
          .replace(/\b(sneakers?|scarpe|scarpa|sollevamento\s+pesi)\b/g, " ")
          .replace(/\s+/g, " ")
          .trim() + "|" + (prod.gender ?? "Unisex").toLowerCase();
        if (seenIds.has(prod.id) || seenNames.has(nameKey)) continue;
        seenIds.add(prod.id);
        seenNames.add(nameKey);
        if (role === "primary") primaryIds.add(prod.id);
        roleById[prod.id] = role;
        merged.push(prod);
        if (merged.length >= totalLimit) break;
      }
      if (merged.length >= totalLimit) break;
    }
    if (merged.length >= totalLimit) break;
  }

  return {
    products: merged,
    primaryIds,
    roleById,
    executedLabels,
  };
}

// ============================================================================
// Chat Persistence
// ============================================================================

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
        results: results.slice(0, 18),
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
