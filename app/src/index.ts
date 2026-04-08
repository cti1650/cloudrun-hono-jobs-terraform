import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { healthRoute } from "./routes/health.js";
import { apiRoute } from "./routes/api.js";
import { webhookRoute } from "./routes/webhook.js";

const app = new Hono();

app.use("*", cors());

app.route("/health", healthRoute);
app.route("/api", apiRoute);
app.route("/webhook", webhookRoute);

app.notFound((c) => c.json({ error: "Not Found" }, 404));

const port = Number(process.env.PORT) || 8080;
console.log(`Server is running on port ${port}`);
serve({ fetch: app.fetch, port });
