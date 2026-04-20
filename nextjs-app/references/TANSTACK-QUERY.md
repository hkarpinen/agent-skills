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

---

## Infinite Queries — Cursor-Based Pagination

Use `useInfiniteQuery` for paginated lists with "load more" or infinite scroll.
The backend returns a cursor for the next page.

```tsx
// hooks/use-threads.ts
"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { getThreads } from "@/lib/api-client";
import type { ThreadSummary, PagedResponse } from "@/types";

export function useThreads(subforumId: string, sort: string) {
  return useInfiniteQuery<PagedResponse<ThreadSummary>>({
    queryKey: ["threads", subforumId, sort],
    queryFn: ({ pageParam }) => getThreads(subforumId, sort, pageParam as string | undefined),
    initialPageParam: undefined,
    getNextPageParam: (lastPage) => lastPage.nextCursor ?? undefined,
  });
}
```

### API Client Function

```ts
// lib/api-client.ts
export async function getThreads(
  subforumId: string,
  sort: string,
  cursor?: string,
): Promise<PagedResponse<ThreadSummary>> {
  const params = new URLSearchParams({ sort });
  if (cursor) params.set("cursor", cursor);
  return apiFetch(`/api/subforums/${subforumId}/threads?${params}`);
}
```

### Load More Button

```tsx
"use client";

import { useThreads } from "@/hooks/use-threads";

export function ThreadList({ subforumId, sort }: { subforumId: string; sort: string }) {
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useThreads(subforumId, sort);

  return (
    <div>
      {data?.pages.flatMap((page) => page.items).map((thread) => (
        <ThreadCard key={thread.id} thread={thread} />
      ))}

      {hasNextPage && (
        <button onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
          {isFetchingNextPage ? "Loading…" : "Load more"}
        </button>
      )}
    </div>
  );
}
```

### Intersection Observer (Infinite Scroll)

```tsx
import { useEffect, useRef } from "react";

export function useIntersectionObserver(
  onIntersect: () => void,
  enabled: boolean,
) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!enabled || !ref.current) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) onIntersect(); },
      { rootMargin: "200px" },
    );
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [onIntersect, enabled]);

  return ref;
}
```

Usage: place `<div ref={sentinelRef} />` after the list. When visible, it triggers `fetchNextPage()`.

Rules:
- `getNextPageParam` returns `undefined` when there are no more pages. This signals
  `hasNextPage = false` to the component.
- Flatten pages with `data.pages.flatMap(page => page.items)` for rendering.
- For infinite scroll, use an intersection observer on a sentinel element — not
  scroll event listeners (which are expensive and unreliable).
- Set `rootMargin: "200px"` on the observer to start fetching before the user
  reaches the bottom.

---

## SSR Hydration — Prefetching on the Server

Prefetch the first page of data in a Server Component and pass it to the
client via TanStack Query's hydration. This gives instant first paint
while enabling client-side infinite scroll.

```tsx
// app/f/[subforumName]/page.tsx — Server Component
import { dehydrate, HydrationBoundary, QueryClient } from "@tanstack/react-query";
import { getThreads } from "@/lib/api-client";
import { ThreadList } from "./thread-list";

export default async function SubforumPage({
  params,
  searchParams,
}: {
  params: Promise<{ subforumName: string }>;
  searchParams: Promise<{ sort?: string }>;
}) {
  const { subforumName } = await params;
  const { sort = "hot" } = await searchParams;
  const queryClient = new QueryClient();

  await queryClient.prefetchInfiniteQuery({
    queryKey: ["threads", subforumName, sort],
    queryFn: () => getThreads(subforumName, sort),
    initialPageParam: undefined,
  });

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <ThreadList subforumId={subforumName} sort={sort} />
    </HydrationBoundary>
  );
}
```

Rules:
- Create a new `QueryClient` per request in the Server Component. Never reuse
  across requests — that would leak data between users.
- Use `prefetchInfiniteQuery` (not `prefetchQuery`) for queries that use
  `useInfiniteQuery` on the client. The cache structures must match.
- Wrap the Client Component in `<HydrationBoundary>` with the dehydrated state.
  TanStack Query picks up the prefetched data without a loading flash.
- The `queryKey` and `initialPageParam` must match exactly between the server
  prefetch and the client `useInfiniteQuery`. Mismatches cause a refetch.
