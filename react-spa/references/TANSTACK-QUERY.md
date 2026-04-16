# TanStack Query — Server State

```ts
// src/api/orders.ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "./client";
import { orderSchema, type Order } from "@/schemas/order";
import { z } from "zod";

const ordersSchema = z.array(orderSchema);

export function useOrders() {
  return useQuery({
    queryKey: ["orders"],
    queryFn: async () => {
      const { data } = await api.get("/orders");
      return ordersSchema.parse(data);
    },
  });
}

export function useOrder(id: string) {
  return useQuery({
    queryKey: ["orders", id],
    queryFn: async () => {
      const { data } = await api.get(`/orders/${id}`);
      return orderSchema.parse(data);
    },
    enabled: !!id,
  });
}

export function usePlaceOrder() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: PlaceOrderPayload) => {
      const { data } = await api.post("/orders", payload);
      return orderSchema.parse(data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["orders"] });
    },
  });
}
```

Rules:
- Every query/mutation is a named hook exported from `api/`. Components never
  import `useQuery` directly.
- Parse API responses through Zod schemas — never trust the wire shape.
- `queryKey` is a hierarchical array: `["orders"]` → `["orders", id]`.
  Invalidate the parent key to refetch all related queries.
- Use `enabled` to prevent queries from firing before dependencies are ready.
- Set default `staleTime` and `gcTime` on the `QueryClient`, not per-query,
  unless the query has a specific caching need.

---

## Provider Setup

```tsx
// src/app.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { RouterProvider, createRouter } from "@tanstack/react-router";
import { routeTree } from "./routeTree.gen";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60,      // 1 minute
      gcTime: 1000 * 60 * 5,     // 5 minutes
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

const router = createRouter({ routeTree });

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```
