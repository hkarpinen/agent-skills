# API Client — Server and Client Fetch

One typed fetch wrapper used by both Server Components and Client Components.
Server Components call it directly; Client Components call it through TanStack
Query hooks.

```ts
// lib/api-client.ts
import { orderSchema, ordersSchema, type Order } from "@/schemas/order";

const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "";

async function apiFetch<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const { getAccessToken } = await import("@/lib/auth");
  const token = await getAccessToken();

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });

  if (!res.ok) {
    throw new Error(`API ${res.status}: ${res.statusText}`);
  }

  return res.json() as Promise<T>;
}

export async function getOrders(): Promise<Order[]> {
  const data = await apiFetch("/api/orders");
  return ordersSchema.parse(data);
}

export async function getOrder(id: string): Promise<Order> {
  const data = await apiFetch(`/api/orders/${id}`);
  return orderSchema.parse(data);
}

export async function placeOrder(payload: unknown): Promise<Order> {
  const data = await apiFetch("/api/orders", {
    method: "POST",
    body: JSON.stringify(payload),
  });
  return orderSchema.parse(data);
}
```

Rules:
- Parse all API responses through Zod schemas — never trust the wire shape.
- Token retrieval is async to support both server-side (cookie/header
  forwarding) and client-side (localStorage) contexts.
- Never hardcode the backend URL. Use `NEXT_PUBLIC_API_URL` for the client
  bundle; use a server-only env var for Server Component fetches when the
  backend is internal.
