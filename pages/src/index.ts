import { serve } from "@hono/node-server";
import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => {
  // IAP passes the authenticated user's email in this header
  const rawEmail = c.req.header("x-goog-authenticated-user-email") ?? "unknown";
  const email = rawEmail.replace(/^accounts\.google\.com:/, "");

  const html = `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>IAP Protected Page</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      max-width: 640px;
      margin: 3rem auto;
      padding: 0 1.5rem;
      line-height: 1.6;
      color: #222;
    }
    h1 { color: #1a73e8; }
    code {
      background: #f4f4f4;
      padding: 0.2rem 0.4rem;
      border-radius: 4px;
      font-size: 0.9em;
    }
    .card {
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      padding: 1.5rem;
      margin-top: 1.5rem;
      background: #fafafa;
    }
  </style>
</head>
<body>
  <h1>🔒 IAP Protected Page</h1>
  <p>このページは Identity-Aware Proxy で保護されています。</p>
  <div class="card">
    <p><strong>Authenticated user:</strong></p>
    <p><code>${email}</code></p>
  </div>
</body>
</html>`;

  return c.html(html);
});

const port = Number(process.env.PORT) || 8080;
console.log(`Pages server is running on port ${port}`);
serve({ fetch: app.fetch, port });
