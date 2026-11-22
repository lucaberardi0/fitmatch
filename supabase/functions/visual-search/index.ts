import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

const VISION_SYSTEM = `Sei il sistema di riconoscimento visivo sportivo di FitMatch.
Analizza la foto caricata dall'utente e identifica l'articolo sportivo principale (scarpe da running/trail/calcio/padel/tennis/basket/sneakers, abbigliamento sportivo, smartwatch GPS, occhiali sportivi, zaini/idratazione, bici/accessori).
REGOLE TASSATIVE:
1. Se la foto NON mostra articoli sportivi/abbigliamento/calzature/accessori atletici (es. cibo, auto, documenti, selfie senza capi sportivi, animali, paesaggi), imposta "is_sport_product": false e spiega brevemente in "note" in italiano.
2. Se è un articolo sportivo, indica il modello più probabile ("recognized_model", es. "Nike Pegasus 41", "Hoka Clifton 9", "Garmin Forerunner 265"), il brand, la categoria, il colore principale e una "search_query" pulita e ottimizzata per trovare offerte reali in un comparatore prezzi (2-4 parole chiave sul prodotto, più eventuali vincoli espliciti indicati dall'utente come genere Uomo/Donna, taglia o budget max).
3. Se l'utente fornisce una descrizione aggiuntiva, usala per disambiguare su quale oggetto concentrarti (es. se ci sono più articoli nella foto), distinguere la versione/edizione o applicare i filtri richiesti in "search_query".
4. In "confidence" usa SOLO "high", "medium" o "low". Se non sei sicuro del numero esatto di versione (es. Clifton 8 vs 9, Pegasus 40 vs 41), metti le varianti possibili in "alternatives" (max 3 stringhe brevi).
5. In "note" scrivi 1 frase sintetica e utile in italiano sul prodotto riconosciuto.
Rispondi ESCLUSIVAMENTE con JSON valido:
{
  "is_sport_product": true,
  "recognized_model": "Nome modello preciso",
  "brand": "Brand o null",
  "category": "Running|Trail|Fitness|Calcio|Padel|Tennis|Basket|Outdoor|Ciclismo|Smartwatch|Abbigliamento|Accessori",
  "color": "Colore principale",
  "search_query": "Query pulita per il catalogo",
  "confidence": "high|medium|low",
  "alternatives": ["Alternativa 1", "Alternativa 2"],
  "note": "Breve descrizione in italiano"
}`;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function decodeBase64Bytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) {
    bytes[i] = bin.charCodeAt(i);
  }
  return bytes;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ detail: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const rawB64Input = String(body?.image_base64 ?? "").trim();
    if (!rawB64Input) {
      return jsonResponse({ detail: "Immagine mancante." }, 400);
    }
    if (rawB64Input.length > 6_000_000) {
      return jsonResponse({ detail: "Immagine troppo pesante (max 4 MB)." }, 400);
    }

    const openRouterKey = (Deno.env.get("OPENROUTER_API_KEY") ?? "").trim();
    if (!openRouterKey) {
      return jsonResponse({ detail: "Servizio di riconoscimento visivo non configurato." }, 503);
    }

    let mimeType = String(body?.mime_type ?? "image/jpeg").trim() || "image/jpeg";
    let cleanB64 = rawB64Input;
    if (cleanB64.startsWith("data:") && cleanB64.includes(",")) {
      const [header, rest] = cleanB64.split(",", 2);
      cleanB64 = rest ?? "";
      if (header.includes(";") && header.includes(":")) {
        const extracted = header.split(":", 2)[1]?.split(";", 1)[0]?.trim();
        if (extracted) mimeType = extracted;
      }
    }
    cleanB64 = cleanB64.replace(/\s+/g, "");
    if (!cleanB64) {
      return jsonResponse({ detail: "Immagine non valida." }, 400);
    }

    const safeMime = mimeType === "image/png" || mimeType === "image/webp" ? mimeType : "image/jpeg";
    const description = String(body?.description ?? "").trim();
    const deviceId = String(body?.device_id ?? "default_device").trim() || "default_device";

    let userPromptText = "Identifica questo articolo sportivo per cercarlo su FitMatch.";
    if (description) {
      userPromptText += `\nDescrizione / preferenza aggiuntiva dell'utente: ${description}`;
    }

    const primaryModel = (Deno.env.get("OPENROUTER_VISION_MODEL") ?? "").trim() ||
      (Deno.env.get("OPENROUTER_MODEL") ?? "").trim() ||
      "openai/gpt-4o-mini";
    const modelsToTry = primaryModel === "google/gemini-2.0-flash-001"
      ? [primaryModel]
      : [primaryModel, "google/gemini-2.0-flash-001"];

    let parsed: Record<string, unknown> | null = null;
    for (const model of modelsToTry) {
      const payload: Record<string, unknown> = {
        model,
        messages: [
          { role: "system", content: VISION_SYSTEM },
          {
            role: "user",
            content: [
              { type: "text", text: userPromptText },
              { type: "image_url", image_url: { url: `data:${safeMime};base64,${cleanB64}` } },
            ],
          },
        ],
        temperature: 0.1,
        max_tokens: 450,
      };
      if (model.startsWith("openai/")) {
        payload.response_format = { type: "json_object" };
      }

      try {
        const resp = await fetch(OPENROUTER_URL, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${openRouterKey}`,
            "HTTP-Referer": "https://fitmatch.it",
            "X-Title": "FitMatch Visual Search",
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(20_000),
        });
        if (!resp.ok) continue;
        const data = await resp.json();
        const content = String(data?.choices?.[0]?.message?.content ?? "").trim();
        if (!content) continue;
        const match = content.match(/(\{[\s\S]*\})/);
        let cleanJson = (match ? match[1] : content).trim();
        if (cleanJson.startsWith("```json")) cleanJson = cleanJson.slice(7);
        else if (cleanJson.startsWith("```")) cleanJson = cleanJson.slice(3);
        if (cleanJson.endsWith("```")) cleanJson = cleanJson.slice(0, -3);
        const obj = JSON.parse(cleanJson.trim());
        if (obj && typeof obj === "object" && !Array.isArray(obj)) {
          parsed = obj as Record<string, unknown>;
          break;
        }
      } catch {
        continue;
      }
    }

    if (!parsed) {
      return jsonResponse({ detail: "Impossibile analizzare la foto in questo momento." }, 502);
    }

    const isSport = Boolean(parsed.is_sport_product ?? true);
    const recognizedModel = String(parsed.recognized_model ?? "").trim();
    const searchQuery = String(parsed.search_query ?? recognizedModel).trim() || recognizedModel;
    const rawConf = String(parsed.confidence ?? "medium").trim().toLowerCase();
    const confidence = rawConf === "high" || rawConf === "low" ? rawConf : "medium";
    const brand = parsed.brand ? String(parsed.brand).trim() || null : null;
    const category = parsed.category ? String(parsed.category).trim() || null : null;
    const color = parsed.color ? String(parsed.color).trim() || null : null;
    const note = parsed.note ? String(parsed.note).trim() || null : null;
    const rawAlts = Array.isArray(parsed.alternatives) ? parsed.alternatives : [];
    const alternatives = rawAlts
      .map((a) => String(a ?? "").trim())
      .filter((a) => a.length > 0 && a.toLowerCase() !== searchQuery.toLowerCase())
      .slice(0, 3);

    let uploadedImageUrl: string | null = null;
    let catalogMatchesCount = 0;

    if (isSport) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      if (supabaseUrl && serviceRoleKey) {
        const supabase = createClient(supabaseUrl, serviceRoleKey);

        try {
          const imgBytes = decodeBase64Bytes(cleanB64);
          const safeDev = deviceId.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) || "default";
          const ext = safeMime === "image/png" ? "png" : safeMime === "image/webp" ? "webp" : "jpg";
          const objPath = `${safeDev}/${crypto.randomUUID().replace(/-/g, "")}.${ext}`;
          const { error: upErr } = await supabase.storage
            .from("chat-images")
            .upload(objPath, imgBytes, { contentType: safeMime, upsert: true });
          if (!upErr) {
            const { data: pub } = supabase.storage.from("chat-images").getPublicUrl(objPath);
            uploadedImageUrl = pub?.publicUrl ?? null;
          }
        } catch {
          // Non-fatal: continue even if image upload fails
        }

        try {
          const words = searchQuery.split(/\s+/).filter((w) => w.length > 1).slice(0, 4);
          if (words.length > 0) {
            let qBuilder = supabase
              .from("products")
              .select("id", { count: "exact", head: true })
              .neq("category", "non_sport");
            for (const w of words) {
              qBuilder = qBuilder.ilike("canonical_name", `%${w}%`);
            }
            const { count } = await qBuilder;
            catalogMatchesCount = count ?? 0;
          }
          if (catalogMatchesCount === 0 && brand) {
            const { count } = await supabase
              .from("products")
              .select("id", { count: "exact", head: true })
              .ilike("brand", `%${brand}%`)
              .neq("category", "non_sport");
            catalogMatchesCount = count ?? 0;
          }
        } catch {
          // Non-fatal
        }
      }
    }

    return jsonResponse({
      is_sport_product: isSport,
      recognized_model: recognizedModel || searchQuery,
      brand,
      category,
      color,
      search_query: searchQuery,
      confidence,
      alternatives,
      note,
      catalog_matches_count: catalogMatchesCount,
      uploaded_image_url: uploadedImageUrl,
    });
  } catch (err) {
    return jsonResponse({ detail: err instanceof Error ? err.message : "Errore interno" }, 500);
  }
});
