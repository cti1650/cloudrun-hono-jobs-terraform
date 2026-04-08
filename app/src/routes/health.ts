import { Hono } from "hono";

export const healthRoute = new Hono();

healthRoute.get("/", (c) => {
  return c.json({ status: "healthy", timestamp: new Date().toISOString() });
});
