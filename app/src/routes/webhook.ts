import { Hono } from "hono";
import { verifyApiKey } from "../middleware/verify-api-key.js";

export const webhookRoute = new Hono();

// All webhook routes require API key
webhookRoute.use("*", verifyApiKey);

webhookRoute.post("/example", async (c) => {
  const body = await c.req.json();
  console.log("POST /webhook/example", JSON.stringify(body));
  return c.json({ ok: true, received: body });
});
