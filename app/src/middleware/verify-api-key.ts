import type { MiddlewareHandler } from "hono";

/**
 * Verify API key from x-api-key header against WEBHOOK_API_KEY env var.
 */
export const verifyApiKey: MiddlewareHandler = async (c, next) => {
  const apiKey = c.req.header("x-api-key");
  const expected = process.env.WEBHOOK_API_KEY;

  if (!expected) {
    console.error("WEBHOOK_API_KEY is not set");
    return c.json({ error: "Server configuration error" }, 500);
  }

  if (!apiKey || apiKey !== expected) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  await next();
};
