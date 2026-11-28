import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Server configuration missing" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt || jwt.split(".").length !== 3) {
    return jsonResponse({ error: "Missing or invalid authorization token" }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Verify the caller's identity strictly from the JWT (never trust user_id from body)
  const { data: userData, error: userErr } = await adminClient.auth.getUser(jwt);
  if (userErr || !userData?.user?.id) {
    return jsonResponse({ error: "Unauthorized or expired session" }, 401);
  }

  const userId = userData.user.id;

  let deviceId: string | null = null;
  try {
    const body = await req.json();
    if (body && typeof body.device_id === "string") {
      const cleaned = body.device_id.trim();
      if (cleaned.length >= 8 && cleaned.length <= 128) {
        deviceId = cleaned;
      }
    }
  } catch {
    // Empty body is valid
  }

  // All tables holding personal or behavioral user data (GDPR Art. 17 & App Store 5.1.1(v))
  const userOwnedTables = [
    "wishlists",
    "collections",
    "followed_stores",
    "hidden_stores",
    "recent_activity",
    "user_preferences",
    "chat_sessions", // cascades chat_messages via FK
    "device_tokens",
    "notifications",
    "store_reports",
    "search_feedback",
    "store_reviews",
  ];

  const errors: string[] = [];
  const cleanedTables: string[] = [];

  for (const table of userOwnedTables) {
    const { error: uidDelErr } = await adminClient
      .from(table)
      .delete()
      .eq("user_id", userId);

    if (uidDelErr) {
      errors.push(`${table}(user_id): ${uidDelErr.message}`);
    } else {
      cleanedTables.push(table);
    }

    // Also remove any legacy unowned rows for this device_id (never touching another user_id!)
    if (deviceId) {
      const { error: devDelErr } = await adminClient
        .from(table)
        .delete()
        .is("user_id", null)
        .eq("device_id", deviceId);

      if (devDelErr) {
        errors.push(`${table}(device_id): ${devDelErr.message}`);
      }
    }
  }

  // Permanently delete the auth user (revokes sessions, identities, and login capability)
  const { error: authDelErr } = await adminClient.auth.admin.deleteUser(userId);
  if (authDelErr) {
    return jsonResponse(
      {
        deleted: false,
        error: `Failed to delete auth account: ${authDelErr.message}`,
        partial_errors: errors,
      },
      500
    );
  }

  return jsonResponse({
    deleted: true,
    user_id: userId,
    tables_cleaned: cleanedTables,
    warnings: errors.length > 0 ? errors : undefined,
  });
});
