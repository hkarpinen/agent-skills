# TanStack Query — Client Components Only

TanStack Query is used exclusively in Client Components for interactive
scenarios: polling, optimistic updates, or paginated lists with client-side
state.

```tsx
// hooks/use-orders.ts
"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getOrders, getOrder, placeOrder } from "@/lib/api-client";

export function useOrders() {
  return useQuery({
    queryKey: ["orders"],
    queryFn: getOrders,
  });
}

export function useOrder(id: string) {
  return useQuery({
    queryKey: ["orders", id],
    queryFn: () => getOrder(id),
    enabled: !!id,
  });
}

export function usePlaceOrder() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: placeOrder,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["orders"] });
    },
  });
}
```

Rules:
- Query hooks live in `hooks/` and are always `"use client"`.
- Query hooks reuse the same `api-client` functions as Server Components —
  the fetch wrapper works in both contexts.
- If a page only needs to display data on load, use a Server Component with
  direct fetch — do not reach for TanStack Query.
- Reserve TanStack Query for: optimistic mutations, polling (`refetchInterval`),
  infinite scroll, or client-side cache management.

---

## Provider Setup

```tsx
// app/providers.tsx
"use client";

import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 1000 * 60,
            gcTime: 1000 * 60 * 5,
            retry: 1,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

```tsx
// app/layout.tsx
import { Providers } from "./providers";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
```

Rules:
- Instantiate `QueryClient` inside `useState` — never at module scope. Module
  scope would share state across requests on the server.
- `Providers` is the only `"use client"` component in the root layout chain.
- Devtools are tree-shaken in production.
