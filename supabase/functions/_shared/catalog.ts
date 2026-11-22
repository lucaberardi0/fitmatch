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
    if (model.startsWith("openai/")) {
      payload.response_format = { type: "json_object" };
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

const KNOWN_BRANDS = [
  "The North Face", "New Balance", "Under Armour", "La Sportiva", "Nike", "Adidas",
  "Asics", "Hoka", "Brooks", "Saucony", "Mizuno", "Salomon", "On", "Altra", "Puma",
  "Garmin", "Polar", "Suunto", "Coros", "Oakley", "Enervit", "Therabody", "Theragun",
  "CamelBak", "Scott", "Topo", "Karhu", "Diadora", "Joma", "Babolat", "Head", "Wilson",
];

export function extractBrand(title: string, fallback?: string | null): string | null {
  const low = title.toLowerCase();
  for (const b of KNOWN_BRANDS) {
    if (low.includes(b.toLowerCase())) return b;
  }
  return fallback ?? null;
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

function sizeMatches(available: string[] | null | undefined, required?: string | null): boolean {
  if (!required || !required.trim()) return true;
  if (!available || available.length === 0) return false;
  const target = normalizeSize(required);
  return available.some((s) => normalizeSize(s) === target);
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
  const groups = new Map<string, {
    id: string;
    canonical_name: string;
    brand: string | null;
    image_url: string | null;
    gallery_images: string[];
    gender: string | null;
    offers: OfferOut[];
  }>();

  const storeFilter = opts?.store?.trim().toLowerCase() || null;
  const genderFilter = opts?.gender?.trim().toLowerCase() || null;

  for (const r of rows) {
    const price = Number(r.current_price ?? 0);
    if (price <= 0) continue;
    if (opts?.maxPrice != null && price > opts.maxPrice) continue;
    if (opts?.minPrice != null && price < opts.minPrice) continue;
    if (storeFilter && r.store_id.toLowerCase() !== storeFilter && !r.store_name.toLowerCase().includes(storeFilter)) {
      continue;
    }
    if (!sizeMatches(r.available_sizes, opts?.size)) continue;

    const prod = r.products ?? null;
    if (prod?.category === "non_sport") continue;

    const canonical = prod?.canonical_name || r.raw_title;
    const prodGender = prod?.gender || null;
    if (genderFilter && genderFilter !== "unisex") {
      const gLow = (prodGender || "").toLowerCase();
      const titleLow = `${canonical} ${r.raw_title}`.toLowerCase();
      if (genderFilter === "donna" || genderFilter === "women") {
        if (gLow.includes("uomo") && !gLow.includes("donna")) continue;
        if (!gLow.includes("donna") && /\b(uomo|men|mens)\b/i.test(titleLow) && !/\b(donna|women|wmns)\b/i.test(titleLow)) continue;
      } else if (genderFilter === "uomo" || genderFilter === "men") {
        if (gLow.includes("donna") && !gLow.includes("uomo")) continue;
        if (!gLow.includes("uomo") && /\b(donna|women|wmns)\b/i.test(titleLow) && !/\b(uomo|men|mens)\b/i.test(titleLow)) continue;
      }
    }

    const ship = Number(r.shipping_cost ?? 0);
    const total = Math.round((price + ship) * 100) / 100;
    const isFree = ship === 0;
    const orig = r.original_price != null ? Number(r.original_price) : null;
    const brand = extractBrand(r.raw_title, prod?.brand ?? null);
    const gallery: string[] = [];
    if (r.image_url) gallery.push(r.image_url);
    for (const g of r.gallery_images ?? []) {
      if (g && !gallery.includes(g)) gallery.push(g);
    }
    for (const g of prod?.gallery_images ?? []) {
      if (g && !gallery.includes(g)) gallery.push(g);
    }

    const offer: OfferOut = {
      store_id: r.store_id,
      store_name: r.store_name,
      product_id: r.product_id,
      title: r.raw_title,
      brand,
      price,
      original_price: orig,
      discount_pct: r.discount_pct != null ? Number(r.discount_pct) : null,
      savings: orig && orig > price ? Math.round((orig - price) * 100) / 100 : null,
      url: r.product_url,
      image_url: r.image_url ?? prod?.image_url ?? null,
      gallery_images: gallery.length > 0 ? gallery : null,
      available_sizes: r.available_sizes ?? [],
      variant_name: null,
      in_stock: true,
      shipping_cost: ship,
      total_price: total,
      is_free_shipping: isFree,
      shipping_label: isFree ? "Spedizione Gratuita" : `+${ship.toFixed(2)} € sped.`,
      free_shipping_threshold: r.free_shipping_threshold != null ? Number(r.free_shipping_threshold) : null,
      courier: r.courier ?? null,
    };

    const gKey = r.product_id || canonical.toLowerCase();
    let grp = groups.get(gKey);
    if (!grp) {
      grp = {
        id: gKey,
        canonical_name: canonical,
        brand,
        image_url: offer.image_url,
        gallery_images: [...gallery],
        gender: prodGender,
        offers: [],
      };
      groups.set(gKey, grp);
    }
    if (!grp.offers.some((o) => o.store_id === offer.store_id && o.url === offer.url)) {
      grp.offers.push(offer);
    }
    if (!grp.image_url && offer.image_url) grp.image_url = offer.image_url;
  }

  const results: MatchedProductOut[] = [];
  for (const grp of groups.values()) {
    grp.offers.sort((a, b) => a.price - b.price);
    const prices = grp.offers.map((o) => o.price);
    const best = prices.length ? Math.min(...prices) : null;
    const high = prices.length ? Math.max(...prices) : null;
    const savings = best != null && high != null && high > best
      ? Math.round((high - best) * 100) / 100
      : null;

    results.push({
      id: grp.id,
      canonical_name: grp.canonical_name,
      brand: grp.brand,
      image_url: grp.image_url,
      gallery_images: grp.gallery_images.length ? grp.gallery_images : null,
      gender: grp.gender,
      offers: grp.offers,
      best_price: best,
      highest_price: high,
      cross_store_savings: savings,
    });
  }

  results.sort((a, b) => {
    if (b.offers.length !== a.offers.length) return b.offers.length - a.offers.length;
    return (a.best_price ?? 9999) - (b.best_price ?? 9999);
  });

  return results.slice(0, opts?.limit ?? 35);
}

const OFFER_SELECT =
  "id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,gallery_images,available_sizes,shipping_cost,free_shipping_threshold,courier,products(id,canonical_name,brand,category,gender,image_url,gallery_images)";

export async function searchCatalogOffers(
  supabase: SupabaseClient,
  opts: {
    keywords?: string[];
    brand?: string | null;
    category?: string | null;
    maxPrice?: number | null;
    minPrice?: number | null;
    size?: string | null;
    gender?: string | null;
    store?: string | null;
    semanticQuery?: string | null;
    limit?: number;
  },
): Promise<MatchedProductOut[]> {
  const allRows: RawOfferRow[] = [];
  const seenOfferIds = new Set<string>();

  const pushRows = (rows: unknown[] | null | undefined) => {
    if (!rows) return;
    for (const row of rows as RawOfferRow[]) {
      if (!seenOfferIds.has(row.id)) {
        seenOfferIds.add(row.id);
        allRows.push(row);
      }
    }
  };

  // 1. Semantic pgvector lookup when semanticQuery is provided
  if (opts.semanticQuery && opts.semanticQuery.trim().length >= 3) {
    const emb = await getQueryEmbedding(opts.semanticQuery);
    if (emb) {
      const { data: semMatches } = await supabase.rpc("match_products_semantic", {
        query_embedding: emb,
        match_threshold: 0.35,
        match_count: 25,
      });
      if (Array.isArray(semMatches) && semMatches.length > 0) {
        const ids = semMatches.map((m: { id: string }) => m.id).filter(Boolean).slice(0, 25);
        if (ids.length > 0) {
          let q = supabase
            .from("store_offers")
            .select(OFFER_SELECT)
            .in("product_id", ids)
            .limit(120);
          if (opts.maxPrice != null) q = q.lte("current_price", opts.maxPrice);
          const { data } = await q;
          pushRows(data);
        }
      }
    }
  }

  // 2. Keyword + brand queries on store_offers
  const cleanKeywords = (opts.keywords ?? [])
    .map((k) => k.trim())
    .filter((k) => k.length >= 2);

  for (const kw of cleanKeywords.slice(0, 3)) {
    const tokens = kw.split(/\s+/).filter((t) => t.length >= 2).slice(0, 4);
    if (tokens.length === 0) continue;
    let q = supabase.from("store_offers").select(OFFER_SELECT).limit(80);
    for (const tok of tokens) {
      q = q.ilike("raw_title", `%${tok}%`);
    }
    if (opts.maxPrice != null) q = q.lte("current_price", opts.maxPrice);
    if (opts.store) q = q.eq("store_id", opts.store.toLowerCase());
    q = q.order("discount_pct", { ascending: false, nullsFirst: false });
    const { data } = await q;
    pushRows(data);

    // Relaxed single-token fallback if multi-token returned nothing
    if ((!data || data.length === 0) && tokens.length > 1) {
      const primary = tokens.find((t) => t.length >= 4) ?? tokens[0];
      let fq = supabase
        .from("store_offers")
        .select(OFFER_SELECT)
        .ilike("raw_title", `%${primary}%`)
        .limit(60);
      if (opts.maxPrice != null) fq = fq.lte("current_price", opts.maxPrice);
      const { data: fData } = await fq;
      pushRows(fData);
    }
  }

  // 3. Brand/category fallback if still empty
  if (allRows.length === 0 && (opts.brand || opts.category)) {
    let q = supabase.from("store_offers").select(OFFER_SELECT).limit(60);
    if (opts.brand) q = q.ilike("raw_title", `%${opts.brand}%`);
    if (opts.maxPrice != null) q = q.lte("current_price", opts.maxPrice);
    q = q.order("discount_pct", { ascending: false, nullsFirst: false });
    const { data } = await q;
    pushRows(data);
  }

  return groupOffersToMatchedProducts(allRows, {
    maxPrice: opts.maxPrice,
    minPrice: opts.minPrice,
    size: opts.size,
    gender: opts.gender,
    store: opts.store,
    limit: opts.limit ?? 35,
  });
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
        results: results.slice(0, 12),
        curated_sections: (opts.payload.curated_sections ?? []).slice(0, 4),
        comparative_cards: (opts.payload.comparative_cards ?? []).slice(0, 5),
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
