import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callOpenRouterJSON,
  corsHeaders,
  createServiceClient,
  detectSingleProductType,
  extractBrand,
  extractExcludedBrands,
  jsonResponse,
  loadChatHistoryContext,
  normalizeQueryTypos,
  ProductType,
  saveChatTurn,
  searchCatalogOffers,
} from "../_shared/catalog.ts";

const KNOWLEDGE_BASE: Record<string, { name: string; description: string; models: string[] }> = {
  max_cushion: {
    name: "Massimo Ammortizzamento & Protezione",
    description: "Suola ad alto assorbimento d'impatto, ideale per runner sopra i 75-80kg, lunghe distanze su asfalto o per chi vuole proteggere ginocchia e schiena.",
    models: ["hoka bondi", "asics gel nimbus", "brooks glycerin", "hoka clifton"],
  },
  daily_trainer: {
    name: "Daily Trainer Polivalente",
    description: "Scarpa equilibrata, resistente e versatile per allenamenti quotidiani di qualsiasi distanza a ritmo medio.",
    models: ["nike pegasus", "brooks ghost", "asics cumulus"],
  },
  speed_race: {
    name: "Velocità, Reattività & Gara",
    description: "Leggere e scattanti, con schiume reattive e/o piastra per migliorare il ritorno energetico in mezza maratona o ripetute veloci.",
    models: ["adidas adizero", "asics magic speed", "nike vaporfly", "brooks hyperion"],
  },
  trail_offroad: {
    name: "Trail Running & Sterrato",
    description: "Battistrada tassellato e tomaia rinforzata per trazione e stabilità su rocce, fango e sentieri irregolari.",
    models: ["hoka speedgoat", "brooks cascadia", "salomon xa pro", "asics trabuco"],
  },
  gps_watch: {
    name: "GPS Smartwatch & Cardiofrequenzimetri",
    description: "Dispositivi GPS per monitorare frequenza cardiaca, passo al chilometro, VO2 max, navigazione percorsi e tempi di recupero.",
    models: ["garmin forerunner", "garmin fenix", "garmin edge", "polar vantage", "suunto"],
  },
  hydration_gear: {
    name: "Zaini Idratazione & Gilet Trail",
    description: "Gilet ergonomici traspiranti con borracce morbide (soft flask) integrate per correre in autosufficienza fino alle lunghe distanze.",
    models: ["salomon active skin", "salomon adv skin", "camelbak"],
  },
  eyewear: {
    name: "Occhiali Sportivi Tecnici",
    description: "Lenti ad alto contrasto (Prizm/fotocromatiche) e montature ultraleggere che non scivolano col sudore.",
    models: ["oakley radar", "oakley sutro", "bliz"],
  },
  fitness_recovery: {
    name: "Fitness & Recupero Muscolare",
    description: "Dispositivi per massaggio a percussione, allentamento contratture e riscaldamento muscolare rapido.",
    models: ["theragun", "therabody"],
  },
  nutrition: {
    name: "Nutrizione Sportiva & Energetici",
    description: "Carboidrati a rilascio graduale o istantaneo, gel isotonici e sali minerali per prevenire crampi e cali di glicogeno.",
    models: ["enervit gel", "enervit", "isocarb"],
  },
};

function parseHeuristicProfile(userQuery: string) {
  const norm = normalizeQueryTypos(userQuery);
  const text = norm.toLowerCase();
  const nonPriceUnit = /^\s*(?:kg|chili|g\b|gr\b|grammi|km|mm|cm|ore|minuti|%)/i;
  const priceMatch = text.match(/(?:al\s+di\s+sotto\s*(?:di)?|sotto\s*(?:i|ai|gli)?|meno\s*di|fino\s*a(?:i)?|entro\s*(?:i|ai)?|max|massimo|budget\s*(?:di|massimo|max)?|<=|<)\s*(?:€\s*)?(\d+(?:[.,]\d+)?)\s*(?:€|euro|eur)?/i);
  let max_price: number | null = null;
  if (priceMatch && priceMatch.index != null) {
    const after = text.slice(priceMatch.index + priceMatch[0].length);
    const val = Number(priceMatch[1].replace(",", "."));
    if (!nonPriceUnit.test(after) && Number.isFinite(val) && (val >= 15 || /€|euro|eur/i.test(priceMatch[0]))) {
      max_price = val;
    }
  }
  const sizeMatch = text.match(/\b(?:tagli[ae]|numero|num\.?|misur[ae]|porto\s*(?:il|la)?|size|eu)\s*(\d{2}(?:[.,]\d)?|(?:xxs|xs|s|m|l|xl|xxl))\b/i);
  const size = sizeMatch ? sizeMatch[1].replace(",", ".").toUpperCase() : null;

  let gender: string | null = null;
  if (/\b(donna|donne|ragazza|femmin[eia]|wmns?|women|woman)\b/i.test(text)) gender = "Donna";
  else if (/\b(uomo|uomini|ragazzo|maschil[eia]|mens?|men|man)\b/i.test(text)) gender = "Uomo";

  const weightMatch = text.match(/(\d{2,3})\s*(?:kg|chili)/);
  const weight_kg = weightMatch ? Number(weightMatch[1]) : null;

  let surface = "asfalto";
  if (/\b(trail|sterrato|fango|montagna|sentier[oi]|bosco)\b/i.test(text)) surface = "trail";
  else if (/\b(pista|tartan)\b/i.test(text)) surface = "pista";

  const is_waterproof = /\b(impermeabil[ei]|gtx|gore[\s-]tex|pioggia)\b/i.test(text);
  const is_speed = /\b(veloc[ei]|reattiv[ae]|gara|maratona|mezza|ripetute|piastra)\b/i.test(text);
  const is_cushion = /\b(ammortizzat[ae]|morbida?|comod[ae]|protettiv[ae]|ginocchi[ao]|schiena|tendin[ei]|fascite)\b/i.test(text);

  let category = "daily_trainer";
  if (/\b(orolog[io]|smartwatch|gps|cardio|garmin|polar|suunto|coros|ciclocomputer)\b/i.test(text)) category = "gps_watch";
  else if (/\b(occhial[ie]|lenti|oakley|sole|prizm)\b/i.test(text)) category = "eyewear";
  else if (/\b(zain[oi]|gilet|flask|borracci[ae]|idratazione|camelbak)\b/i.test(text)) category = "hydration_gear";
  else if (/\b(theragun|pistola|massaggi[ao]|recupero|contrattur[ae]|massaggiante)\b/i.test(text)) category = "fitness_recovery";
  else if (/\b(gel|barrett[ae]|integrator[ei]|enervit|sali|maltodestrin[ae]|nutrizione)\b/i.test(text)) category = "nutrition";
  else if (surface === "trail") category = "trail_offroad";
  else if (is_speed && !(weight_kg && weight_kg > 82)) category = "speed_race";
  else if (is_cushion || (weight_kg && weight_kg >= 78)) category = "max_cushion";

  return { raw_query: norm, max_price, size, gender, weight_kg, surface, is_waterproof, category };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    let prompt = url.searchParams.get("prompt") ?? "";
    let sessionId = url.searchParams.get("session_id");
    let deviceId = url.searchParams.get("device_id");
    let userId = url.searchParams.get("user_id");

    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      prompt = String(body?.prompt ?? prompt);
      sessionId = body?.session_id ?? sessionId;
      deviceId = body?.device_id ?? deviceId;
      userId = body?.user_id ?? userId;
    }

    prompt = prompt.trim();
    if (prompt.length < 4) {
      return jsonResponse({ detail: "Prompt troppo breve (minimo 4 caratteri)." }, 400);
    }

    const supabase = createServiceClient();
    if (!supabase) {
      return jsonResponse({ detail: "Configurazione Supabase mancante." }, 500);
    }

    // Load prior session profile & turns so follow-ups in AI Advisor keep context!
    const historyCtx = await loadChatHistoryContext(supabase, sessionId);
    const prevProfile = (historyCtx.contextState?.user_profile && typeof historyCtx.contextState.user_profile === "object")
      ? (historyCtx.contextState.user_profile as Record<string, unknown>)
      : null;
    const localH = parseHeuristicProfile(prompt);
    const reqBrand = extractBrand(prompt, null);
    const excludedBrands = extractExcludedBrands(prompt);
    const noCarbon = /\b(?:senza|no|non)\s+(?:la\s+|una\s+)?(?:piastra(?:\s+(?:in|di)\s+carbonio)?|carbonio|carbon)\b/i.test(prompt);

    const primaryModel = (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() || "meta-llama/llama-3.3-70b-instruct";
    const systemPrompt =
      "Sei un Coach e Biomeccanico sportivo d'élite per 'FitMatch'. " +
      "L'utente ti spiega le sue caratteristiche fisiche (peso, altezza, appoggio, eventuali patologie come fascite plantare, tendinite, dolori alle ginocchia), " +
      "i suoi obiettivi sportivi, esclusioni (es. 'non Nike', 'senza carbonio') e il budget.\n" +
      "Se esiste un profilo/contesto precedente della chat, integralo e aggiorna solo i parametri modificati.\n" +
      "Rispondi ESCLUSIVAMENTE con un JSON valido con questa struttura:\n" +
      "{\n" +
      '  "category_name": "es. Massimo Ammortizzamento & Protezione Articolare",\n' +
      '  "category_description": "descrizione chiara della categoria tecnica",\n' +
      '  "biomechanical_reasoning": "Spiegazione biomeccanica dettagliata e cordiale in 2-3 frasi, evidenziando il carico articolare e la motivazione delle scelte tecniche.",\n' +
      '  "recommended_models": ["modello 1 (es. asics gel nimbus)", "modello 2 (es. hoka bondi)", "modello 3 (es. brooks glycerin)"],\n' +
      '  "parsed_profile": {\n' +
      '    "weight_kg": int o null,\n' +
      '    "surface": "asfalto | trail | pista",\n' +
      '    "gender": "Uomo | Donna | Unisex",\n' +
      '    "size": "taglia stringa o null (es. 43)",\n' +
      '    "max_price": float o null\n' +
      "  }\n" +
      "}";

    const advisorUserPrompt = prevProfile
      ? `Profilo precedente: ${JSON.stringify(prevProfile)}\nTurni precedenti: ${historyCtx.recentTurns.slice(-3).map((t) => `"${t.query}"`).join(" -> ")}\nNuova richiesta utente: ${prompt}`
      : prompt;

    const llmParsed = await callOpenRouterJSON({
      systemPrompt,
      userPrompt: advisorUserPrompt,
      models: [primaryModel, "meta-llama/llama-3.3-70b-instruct", "openai/gpt-4o-mini"],
      temperature: 0.1,
      maxTokens: 800,
      title: "FitMatch AI Advisor",
      timeoutMs: 14_000,
    });

    let categoryName = "";
    let categoryDesc = "";
    let reasoning = "";
    let source = "openrouter_llama_70b";
    let targetModels: string[] = [];
    let profile: Record<string, unknown> = {};

    if (llmParsed && Array.isArray(llmParsed.recommended_models) && llmParsed.recommended_models.length > 0) {
      categoryName = String(llmParsed.category_name ?? "Consulenza Biomeccanica IA");
      categoryDesc = String(llmParsed.category_description ?? "");
      reasoning = String(llmParsed.biomechanical_reasoning ?? "");
      targetModels = llmParsed.recommended_models.map((m) => String(m ?? "").trim()).filter(Boolean).slice(0, 4);
      profile = (llmParsed.parsed_profile as Record<string, unknown>) ?? {};
    } else {
      source = "local_heuristic";
      const h = localH;
      const catInfo = KNOWLEDGE_BASE[h.category] ?? KNOWLEDGE_BASE.daily_trainer;
      categoryName = catInfo.name;
      categoryDesc = catInfo.description;
      targetModels = h.is_waterproof ? catInfo.models.map((m) => `${m} gtx`) : [...catInfo.models];
      profile = h;

      const reasons: string[] = [];
      if (h.weight_kg) {
        reasons.push(`Per un peso di **${h.weight_kg} kg**, il carico articolare all'impatto supera i ${h.weight_kg * 3} kg: occorre un'intersuola protettiva con elevato assorbimento dello shock.`);
      }
      if (h.surface === "asfalto") {
        reasons.push("L'asfalto è la superficie più traumatica per i tendini: abbiamo selezionato schiume tecniche ad alto smorzamento.");
      } else if (h.surface === "trail") {
        reasons.push("Per lo sterrato abbiamo privilegiato suole artigliate e protezione dell'avampiede.");
      }
      if (h.max_price) reasons.push(`Tutti i modelli rispettano il budget di **${Math.round(h.max_price)} €**.`);
      if (h.size) reasons.push(`Le offerte mostrate verificano la presenza della taglia **${h.size}** in magazzino.`);
      reasoning = reasons.join(" ") || catInfo.description;
    }

    // Reconcile constraints deterministically (current prompt > LLM > prior session profile!)
    const resetPrice = /\b(rimuovi\s+(?:il\s+)?limite\s+di\s+prezzo|senza\s+limit[ei]\s+di\s+prezzo|qualsiasi\s+prezzo)\b/i.test(prompt);
    const llmPriceRaw = profile.max_price != null ? Number(profile.max_price) : null;
    const prevPriceRaw = prevProfile?.max_price != null ? Number(prevProfile.max_price) : null;
    const maxPriceVal = resetPrice
      ? null
      : (localH.max_price ??
        (llmPriceRaw != null && Number.isFinite(llmPriceRaw) && llmPriceRaw > 0 ? llmPriceRaw : null) ??
        (prevPriceRaw != null && Number.isFinite(prevPriceRaw) && prevPriceRaw > 0 ? prevPriceRaw : null));

    const sizeVal = localH.size ??
      (profile.size && String(profile.size).trim().toLowerCase() !== "null" ? String(profile.size).trim() : null) ??
      (prevProfile?.size ? String(prevProfile.size) : null);

    const genderVal = localH.gender ??
      (profile.gender && ["Uomo", "Donna"].includes(String(profile.gender)) ? String(profile.gender) : null) ??
      (prevProfile?.gender && ["Uomo", "Donna"].includes(String(prevProfile.gender)) ? String(prevProfile.gender) : null);

    const prevExcluded = Array.isArray(prevProfile?.excluded_brands) ? prevProfile!.excluded_brands.map(String) : [];
    const effectiveExcludedBrands = Array.from(new Set([...prevExcluded, ...excludedBrands]));
    const detectedPType: ProductType | null = detectSingleProductType(prompt) ??
      (prevProfile?.product_type ? (prevProfile.product_type as ProductType) : null) ??
      (localH.surface === "trail" ? "trail_shoes" : "shoes");

    const matched = await searchCatalogOffers(supabase, {
      rawQuery: prompt,
      keywords: targetModels,
      brand: reqBrand,
      excludedBrands: effectiveExcludedBrands.length > 0 ? effectiveExcludedBrands : null,
      excludedFeatures: noCarbon ? ["no_carbon"] : null,
      productType: detectedPType,
      entityTokens: [],
      maxPrice: maxPriceVal,
      size: sizeVal,
      gender: genderVal,
      semanticQuery: `${prompt} ${targetModels.join(" ")}`,
      allowSemantic: effectiveExcludedBrands.length === 0,
      limit: 16,
    });

    const mergedProfile = {
      raw_query: prompt,
      max_price: maxPriceVal,
      size: sizeVal,
      gender: genderVal ?? "Unisex",
      weight_kg: localH.weight_kg ?? profile.weight_kg ?? prevProfile?.weight_kg ?? null,
      surface: (profile.surface ?? localH.surface ?? prevProfile?.surface ?? "asfalto"),
      product_type: detectedPType,
      excluded_brands: effectiveExcludedBrands,
      category: categoryName,
    };

    const recommendations = matched
      .filter((g) => (g.best_price ?? 0) >= 20)
      .slice(0, 5)
      .map((g) => {
        const best = g.offers[0];
        return {
          product_name: g.canonical_name,
          brand: g.brand,
          best_price: g.best_price,
          best_store: best?.store_name ?? null,
          original_price: best?.original_price ?? null,
          discount_pct: best?.discount_pct ?? null,
          link: best?.url ?? null,
          image_url: g.image_url,
          cross_store_savings: g.cross_store_savings,
          all_offers: g.offers.map((o) => ({ store: o.store_name, price: o.price, url: o.url })),
        };
      });

    let savedIds: { session_id: string; turn_id: string } | null = null;
    if (sessionId || deviceId || userId) {
      savedIds = await saveChatTurn(supabase, {
        sessionId,
        deviceId,
        userId,
        chatType: "ai_advisor",
        query: prompt,
        isFollowUp: Boolean(sessionId && sessionId.trim()),
        payload: {
          conversational_header: categoryName || "Consulenza IA",
          conversational_summary: reasoning || categoryDesc,
          is_conversational_advice: true,
          results: matched.slice(0, 5),
        },
        contextState: { user_profile: mergedProfile },
      });
    }

    return jsonResponse({
      user_profile: mergedProfile,
      category_name: categoryName,
      category_description: categoryDesc,
      biomechanical_reasoning: reasoning,
      recommendations,
      source,
      session_id: savedIds?.session_id ?? null,
      turn_id: savedIds?.turn_id ?? null,
    });
  } catch (err) {
    return jsonResponse({ detail: err instanceof Error ? err.message : "Errore interno" }, 500);
  }
});
