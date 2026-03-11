const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

// Rate limit: max unique sessions per day (0 = unlimited)
const DAILY_SESSION_LIMIT = parseInt(process.env.DAILY_LIMIT || "0", 10);

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "API key not configured" });
  }

  const sessionId = req.headers["x-session-id"];

  // --- Rate limiting (session-based via Upstash Redis) ---
  if (DAILY_SESSION_LIMIT > 0 && process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN) {
    try {
      const { Redis } = await import("@upstash/redis");
      const redis = new Redis({
        url: process.env.KV_REST_API_URL,
        token: process.env.KV_REST_API_TOKEN,
      });

      const today = new Date().toISOString().slice(0, 10);

      if (!sessionId) {
        return res.status(401).json({ error: "Missing session identifier" });
      }

      // Session-based: count unique session IDs per day
      const sessionsKey = `sessions:${today}`;
      const sessionCount = await redis.scard(sessionsKey);

      // Check if this session is already tracked
      const isExisting = await redis.sismember(sessionsKey, sessionId);

      if (!isExisting && sessionCount >= DAILY_SESSION_LIMIT) {
        return res.status(429).json({
          error: "Daily limit reached",
          limit: DAILY_SESSION_LIMIT,
          resetAt: `${today}T23:59:59Z`,
        });
      }

      // Track this session ID
      if (!isExisting) {
        await redis.sadd(sessionsKey, sessionId);
        await redis.expire(sessionsKey, 86400);
      }

      const currentCount = isExisting ? sessionCount : sessionCount + 1;
      res.setHeader("X-RateLimit-Limit", DAILY_SESSION_LIMIT);
      res.setHeader("X-RateLimit-Remaining", Math.max(0, DAILY_SESSION_LIMIT - currentCount));
    } catch (e) {
      // Redis unavailable — allow request through
      console.error("Rate limit check failed:", e.message);
    }
  }

  // --- Proxy to OpenAI ---
  try {
    const { model, messages, temperature, max_tokens } = req.body;

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: "Invalid request body" });
    }

    const openaiRes = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: model || "gpt-4o",
        messages,
        temperature: temperature ?? 0.4,
        max_tokens: max_tokens || 4096,
      }),
    });

    const data = await openaiRes.json();

    if (!openaiRes.ok) {
      return res.status(openaiRes.status).json(data);
    }

    return res.status(200).json(data);
  } catch (e) {
    console.error("Proxy error:", e);
    return res.status(502).json({ error: "Failed to reach OpenAI" });
  }
}
