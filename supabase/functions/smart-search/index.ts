import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  jsonResponse,
  MatchedProductOut,
  saveChatTurn,
  searchCatalogOffers,
} from "./catalog.ts";

function evaluateGuardrail(q: string): { isOffTopic: boolean; isUnsafe: boolean; reason?: string } {
  const low = q.toLowerCase();
  if (/(ignore\s+previous|system\s+prompt|jailbreak|drop\s+table|<script|exec\s*\()/i.test(low)) {
    return {
      isOffTopic: true,
      isUnsafe: true,
      reason: "Posso aiutarti solo con ricerche su scarpe e attrezzatura sportiva su FitMatch.",
    };
  }
  if (/\b(ricetta|cucina|politica|elezioni|oroscopo|meteo|bitcoin|crypto|codice\s+python|scrivi\s+un\s+programma|compiti\s+di\s+storia)\b/i.test(low)) {
    return {
      isOffTopic: true,
      isUnsafe: false,
      reason: "Sono l'assistente sportivo di FitMatch: chiedimi scarpe da running, smartwatch GPS, abbigliamento o attrezzatura sportiva!",
    };
  }
  return { isOffTopic: false, isUnsafe: false };
}

function parseLocalConstraints(q: string) {
  const low = q.toLowerCase();
  const maxPriceMatch = low.match(/(?:sotto\s*i?|meno\s*di|max|massimo|entro\s*i?|budget\s*(?:di)?)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)?/);
  const minPriceMatch = low.match(/(?:sopra\s*i?|almeno|da|minimo)\s*(\d+(?:[.,]\d+)?)\s*(?:€|euro)/);
  const sizeMatch = low.match(/(?:taglia|numero|misura|eu)\s*([0-9]{2}(?:[.,][0-9])?|[xsml]{1,3})/i);

  let gender: string | null = null;
  if (/\b(donna|femmin[aei]|ragazza|wmns|women)\b/i.test(low)) gender = "Donna";
  else if (/\b(uomo|maschil[ei]|ragazzo|men|mens)\b/i.test(low)) gender = "Uomo";

  const isDeepDive = q.trim().split(/\s+/).length >= 4 ||
    /\b(consiglia|miglior[ie]|quale|confronta|differenza|per\s+(?:correre|maratona|trail|ginocchia|peso)|fascite|ammortizzat|principiant)\b/i.test(low);

  return {
    max_price: maxPriceMatch ? Number(maxPriceMatch[1].replace(",", ".")) : null,
    min_price: minPriceMatch ? Number(minPriceMatch[1].replace(",", ".")) : null,
    size: sizeMatch ? sizeMatch[1].replace(",", ".").toUpperCase() : null,
    gender,
    is_deep_dive: isDeepDive,
  };
}

function buildCuratedSections(results: MatchedProductOut[]) {
  if (results.length === 0) return [];
  const sections: Array<{ id: string; title: string; subtitle: string; products: MatchedProductOut[] }> = [];

  const multiStore = results.filter((p) => p.offers.length > 1);
  if (multiStore.length > 0) {
    sections.push({
      id: "best_comparison",
      title: "Migliori Confronti Multi-Store",
      subtitle: "Modelli disponibili su più negozi per risparmiare subito",
      products: multiStore.slice(0, 8),
    });
  }

  const discounted = [...results]
    .filter((p) => (p.offers[0]?.discount_pct ?? 0) >= 15)
    .sort((a, b) => (b.offers[0]?.discount_pct ?? 0) - (a.offers[0]?.discount_pct ?? 0));
  if (discounted.length > 0) {
    sections.push({
      id: "top_discounts",
      title: "Sconti più Alti",
      subtitle: "Ribassi verificati nei negozi partner",
      products: discounted.slice(0, 8),
    });
  }

  const lowestPrice = [...results].sort((a, b) => (a.best_price ?? 9999) - (b.best_price ?? 9999));
  sections.push({
    id: "best_value",
    title: "Miglior Prezzo Finale",
    subtitle: "Offerte ordinate dal prezzo più basso",
    products: lowestPrice.slice(0, 8),
  });

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
  if (intent.gender) chips.push({ id: "chip_gender", label: intent.gender, param_key: "gender", value: intent.gender });
  if (intent.size) chips.push({ id: "chip_size", label: `Taglia ${intent.size}`, param_key: "size", value: intent.size });
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
        follow_up_suggestions: ["Nike Pegasus 41", "Scarpe running ammortizzate", "Garmin Forerunner 265"],
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
      detail: contextQuery ? "Collego il contesto della conversazione" : "Interpreto modello, filtri e necessità tecniche",
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
    const effectiveQuery = contextQuery && contextQuery.trim()
      ? `${contextQuery.trim()} -> follow-up: ${q}`
      : q;

    const systemPrompt =
      "Sei il motore di ricerca AI sportivo di FitMatch (comparatore prezzi di scarpe da running, trail, smartwatch GPS, abbigliamento e accessori sportivi).\n" +
      "Analizza la query dell'utente (e l'eventuale contesto precedente) ed estrai l'intent strutturato.\n" +
      "Rispondi ESCLUSIVAMENTE con JSON valido:\n" +
      "{\n" +
      '  "search_mode": "deep_dive" | "classic",\n' +
      '  "is_deep_dive": true | false,\n' +
      '  "target_keywords": ["parola o modello 1", "modello 2"],\n' +
      '  "brand": string | null,\n' +
      '  "category": "running_shoes|trail_running|gps_watch|eyewear|hydration|fitness|nutrition|apparel|null",\n' +
      '  "gender": "Uomo" | "Donna" | null,\n' +
      '  "max_price": number | null,\n' +
      '  "min_price": number | null,\n' +
      '  "size": string | null,\n' +
      '  "features": ["es. ammortizzata", "piastra carbonio"],\n' +
      '  "conversational_header": "Titolo breve (max 6 parole)",\n' +
      '  "conversational_summary": "Consiglio tecnico sintetico e chiaro in 2 frasi in italiano",\n' +
      '  "follow_up_suggestions": ["Follow-up 1", "Follow-up 2", "Follow-up 3"]\n' +
      "}";

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "openai/gpt-4o-mini";
    const llmIntent = await callOpenRouterJSON({
      systemPrompt,
      userPrompt: prevContext
        ? `Contesto sessione precedente: ${JSON.stringify(prevContext)}\nRichiesta attuale: ${effectiveQuery}`
        : effectiveQuery,
      models: [primaryModel, "meta-llama/llama-3.3-70b-instruct"],
      temperature: 0.1,
      maxTokens: 550,
      title: "FitMatch Smart Search",
      timeoutMs: 9_000,
    });

    const explicitMaxPrice = maxPriceParam != null && maxPriceParam !== "" ? Number(maxPriceParam) : null;
    const maxPrice = explicitMaxPrice ?? (typeof llmIntent?.max_price === "number" ? llmIntent.max_price : local.max_price);
    const minPrice = typeof llmIntent?.min_price === "number" ? llmIntent.min_price : local.min_price;
    const size = (sizeParam && sizeParam.trim()) ||
      (llmIntent?.size ? String(llmIntent.size) : local.size) ||
      (preferredSize && preferredSize.trim() ? preferredSize.trim() : null);
    const gender = (llmIntent?.gender ? String(llmIntent.gender) : null) ?? local.gender ??
      (prevContext?.gender ? String(prevContext.gender) : null);
    const brand = llmIntent?.brand ? String(llmIntent.brand) : null;
    const category = (categoryParam && categoryParam.trim()) ||
      (llmIntent?.category && llmIntent.category !== "null" ? String(llmIntent.category) : null);

    let targetKeywords = Array.isArray(llmIntent?.target_keywords)
      ? llmIntent.target_keywords.map((k) => String(k ?? "").trim()).filter(Boolean)
      : [];
    if (targetKeywords.length === 0) {
      targetKeywords = [q];
    }

    const isDeepDive = mode === "deep_dive" ||
      (mode !== "classic" && (Boolean(llmIntent?.is_deep_dive) || local.is_deep_dive));

    emitStep?.({
      id: "intent",
      status: "done",
      title: "Richiesta compresa",
      detail: targetKeywords.slice(0, 3).join(", "),
      elapsed_ms: Date.now() - startedAt,
    });

    emitStep?.({
      id: "catalog",
      status: "running",
      title: "Ricerca semantica e prezzi nei negozi",
      detail: "Confronto catalogo multi-store su Supabase",
      elapsed_ms: Date.now() - startedAt,
    });

    const results = await searchCatalogOffers(supabase, {
      keywords: targetKeywords,
      brand,
      category,
      maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
      minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
      size,
      gender,
      store: storeParam,
      semanticQuery: `${q} ${targetKeywords.join(" ")}`,
      limit: Math.min(Math.max(limit, 1), 60),
    });

    emitStep?.({
      id: "catalog",
      status: "done",
      title: `${results.length} modelli trovati`,
      detail: "Offerte ordinate per disponibilità multi-store e miglior prezzo",
      elapsed_ms: Date.now() - startedAt,
    });

    const header = String(llmIntent?.conversational_header ?? "").trim() ||
      (results.length > 0 ? `Migliori offerte per "${q}"` : `Nessuna offerta esatta per "${q}"`);
    const summary = String(llmIntent?.conversational_summary ?? "").trim() ||
      (results.length > 0
        ? `Ho trovato ${results.length} modelli compatibili confrontando i negozi partner.`
        : "Prova con parole chiave più ampie o rimuovi alcuni filtri.");

    const curatedSections = buildCuratedSections(results);
    const spotlight = results[0]
      ? {
          product: results[0],
          badge_text: results[0].offers.length > 1 ? `Confrontato su ${results[0].offers.length} negozi` : "Miglior Prezzo",
          highlights: [
            results[0].best_price != null ? `Da €${results[0].best_price.toFixed(2)}` : "Prezzo verificato",
            results[0].cross_store_savings != null && results[0].cross_store_savings > 1
              ? `Risparmi fino a €${results[0].cross_store_savings.toFixed(2)}`
              : "Spedizione trasparente",
          ],
        }
      : null;

    const comparativeCards = isDeepDive
      ? results.slice(0, 3).map((p) => ({
          product: p,
          model_name: p.canonical_name,
          ideal_for: p.brand ? `Selezione ${p.brand}` : "Uso sportivo tecnico",
          strengths: p.best_price != null ? `Miglior prezzo €${p.best_price.toFixed(2)} (${p.offers.length} offerte)` : `${p.offers.length} offerte`,
          section_title: "Confronto rapido",
        }))
      : [];

    const followUps = Array.isArray(llmIntent?.follow_up_suggestions) && llmIntent.follow_up_suggestions.length > 0
      ? llmIntent.follow_up_suggestions.map(String).slice(0, 3)
      : ["Solo sotto 120€", "Mostra più sconti", "Alternative simili"];

    const intentObj = {
      raw_query: q,
      search_mode: isDeepDive ? "deep_dive" : "classic",
      is_deep_dive: isDeepDive,
      target_keywords: targetKeywords,
      brand,
      category,
      gender,
      max_price: maxPrice,
      min_price: minPrice,
      size,
      features: Array.isArray(llmIntent?.features) ? llmIntent.features.map(String) : [],
      explanation: summary,
      source: llmIntent ? "supabase_edge_openrouter" : "supabase_edge_heuristic",
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
        isFollowUp: Boolean(contextQuery && contextQuery.trim()),
        payload: {
          conversational_header: header,
          conversational_summary: summary,
          is_conversational_advice: isDeepDive,
          intent: intentObj,
          chips,
          results,
          curated_sections: curatedSections,
          comparative_cards: comparativeCards,
          spotlight,
          follow_up_suggestions: followUps,
          is_off_topic: false,
          is_unsafe: false,
        },
        contextState: {
          last_query: q,
          last_keywords: targetKeywords,
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
      total_found: results.length,
      results,
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
