import { Hono } from "hono";

export const apiRoute = new Hono();

apiRoute.get("/hello", (c) => {
  console.log("GET /api/hello");
  return c.json({ message: "Hello, World!" });
});

apiRoute.post("/hello", async (c) => {
  const body = await c.req.json();
  console.log("POST /api/hello", JSON.stringify(body));
  return c.json({ message: `Hello, ${body.name || "Guest"}!` });
});

apiRoute.get("/users", (c) => {
  console.log("GET /api/users");
  return c.json({
    users: [
      { id: 1, name: "Alice" },
      { id: 2, name: "Bob" },
      { id: 3, name: "Charlie" },
    ],
  });
});
