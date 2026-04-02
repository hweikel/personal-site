// Cloudflare Worker — Aleph tag suggestion endpoint
// Bindings required: SUGGESTIONS_KV (KV namespace)

const VALID_TOKEN = "theproofinthepudding";

const ALLOWED_ORIGINS = [
  "https://henryweikel.net",
  "https://www.henryweikel.net",
];

function corsHeaders(origin) {
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Aleph-Token",
  };
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    const url = new URL(request.url);

    if (url.pathname === "/api/suggest" && request.method === "POST") {
      return handleSuggest(request, env, origin);
    }

    return json({ error: "Not found" }, 404, origin);
  },
};

async function handleSuggest(request, env, origin) {
  // Token validation
  const token = request.headers.get("X-Aleph-Token");
  if (token !== VALID_TOKEN) {
    return json({ error: "Unauthorized" }, 401, origin);
  }

  // Parse body
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const { photo, tag, website } = body;

  // Honeypot: if present and non-empty, silently accept but do not store
  if (website) {
    return json({ ok: true }, 200, origin);
  }

  // Validation
  if (!photo || typeof photo !== "string" || photo.length === 0 || photo.length > 100) {
    return json({ error: "Invalid photo" }, 400, origin);
  }
  if (!tag || typeof tag !== "string" || tag.length === 0 || tag.length > 100) {
    return json({ error: "Invalid tag" }, 400, origin);
  }

  // Rate limiting: max 10 suggestions per IP per minute
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const rateKey = `rate:${ip}`;
  const countStr = await env.SUGGESTIONS_KV.get(rateKey);
  const count = countStr ? parseInt(countStr, 10) : 0;

  if (count >= 10) {
    return json({ error: "Rate limit exceeded" }, 429, origin);
  }

  // Increment counter with 60-second TTL
  await env.SUGGESTIONS_KV.put(rateKey, String(count + 1), { expirationTtl: 60 });

  // Store suggestion
  const ts = Date.now();
  const key = `suggestion:${ts}:${photo}`;
  const value = JSON.stringify({ photo, tag, ts, ip });
  await env.SUGGESTIONS_KV.put(key, value);

  return json({ ok: true }, 200, origin);
}

function json(data, status = 200, origin = "") {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
    },
  });
}
