---
name: react-spa
description: React single-page application stack — Vite, TanStack Query, TanStack Router, Tailwind CSS, Radix UI, React Hook Form + Zod, and Axios. Use when building or scaffolding a React SPA, setting up routing, managing server state, creating forms with validation, styling components, or structuring a frontend project. Architecture agnostic — does not prescribe how the backend is organized. Does NOT cover SSR/SSG (Next.js) or native mobile (React Native).
---

---

## Core Package Stack

## Core Package Stack

| Concern | Packages |
|---|---|
| Build + dev server | `vite`, `@vitejs/plugin-react` |
| Routing | `@tanstack/react-router`, `@tanstack/router-devtools` |
| Server state | `@tanstack/react-query`, `@tanstack/react-query-devtools` |
| HTTP client | `axios` |
| Forms | `react-hook-form`, `@hookform/resolvers`, `zod` |
| Styling | `tailwindcss`, `@tailwindcss/vite` |
| Headless UI | `@radix-ui/react-dialog`, `@radix-ui/react-dropdown-menu`, `@radix-ui/react-tooltip`, (add primitives as needed) |
| Testing | `vitest`, `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event`, `jsdom` |
| Linting | `eslint`, `@eslint/js`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`, `typescript-eslint` |

Install only the Radix primitives you actually use — do not install the full
monorepo.

---

## Project Structure

```
src/
├── main.tsx                ← entry point — mounts <App />
├── app.tsx                 ← providers (QueryClient, Router)
├── routes/                 ← route tree (TanStack Router file-based or manual)
│   ├── __root.tsx          ← root layout (nav, error boundary)
│   ├── index.tsx           ← home route
│   └── orders/
│       ├── index.tsx       ← /orders list
│       └── $orderId.tsx    ← /orders/:orderId detail
├── api/                    ← Axios instance + query/mutation hooks
│   ├── client.ts           ← configured Axios instance
│   ├── orders.ts           ← useOrders(), useOrder(id), usePlaceOrder()
│   └── auth.ts             ← useLogin(), useLogout(), useCurrentUser()
├── components/             ← shared UI components
│   ├── ui/                 ← Radix-based primitives (Button, Dialog, Input)
│   └── layout/             ← Shell, Sidebar, Header
├── hooks/                  ← app-wide custom hooks
├── lib/                    ← utilities (cn(), date formatting, constants)
├── schemas/                ← Zod schemas shared between forms and API
└── types/                  ← shared TypeScript types / interfaces
```

Rules:
- Colocate route-specific components inside `routes/`. Move to `components/`
  only when reused across routes.
- Every file in `api/` exports hooks, not raw functions. Components never call
  Axios directly.
- Zod schemas in `schemas/` are the single source of truth for both form
  validation and API response parsing.

---

## Vite Configuration

```ts
// vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:5000",
        changeOrigin: true,
      },
    },
  },
  resolve: {
    alias: { "@": "/src" },
  },
});
```

Rules:
- Proxy `/api` to the backend in dev. In production, serve through a reverse
  proxy (nginx, CDN) — never hard-code the backend URL in client code.
- Use `@/` path alias for all imports from `src/`.

---

## TypeScript Configuration

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
```

Rules:
- `strict: true` is non-negotiable.
- `noUncheckedIndexedAccess` catches undefined-access bugs before runtime.
- Never use `any`. Use `unknown` + type guard if the type is truly unknown.

---

## Axios — API Client

```ts
// src/api/client.ts
import axios from "axios";

export const api = axios.create({
  baseURL: "/api",
  headers: { "Content-Type": "application/json" },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem("access_token");
      window.location.href = "/login";
    }
    return Promise.reject(error);
  },
);
```

Rules:
- One shared `api` instance — never create Axios instances per file.
- Attach the JWT via request interceptor, not per-call.
- Handle 401 globally — redirect to login and clear stale tokens.
- Never store secrets or API keys in frontend code.

---

## TanStack Query — Server State

All data fetching goes through TanStack Query hooks exported from `api/`. Components never import `useQuery` directly. Parse API responses through Zod schemas. See `references/TANSTACK-QUERY.md` for hook patterns and provider setup.

---

## TanStack Router

Use file-based routing. Each file in `src/routes/` becomes a route segment.

```tsx
// src/routes/__root.tsx
import { createRootRoute, Outlet } from "@tanstack/react-router";
import { TanStackRouterDevtools } from "@tanstack/router-devtools";

export const Route = createRootRoute({
  component: () => (
    <>
      <header>{/* nav */}</header>
      <main>
        <Outlet />
      </main>
      <TanStackRouterDevtools />
    </>
  ),
});

// src/routes/orders/$orderId.tsx
import { createFileRoute } from "@tanstack/react-router";
import { useOrder } from "@/api/orders";

export const Route = createFileRoute("/orders/$orderId")({
  component: OrderDetailPage,
});

function OrderDetailPage() {
  const { orderId } = Route.useParams();
  const { data: order, isLoading } = useOrder(orderId);

  if (isLoading) return <p>Loading…</p>;
  if (!order) return <p>Order not found.</p>;

  return <h1>Order {order.id}</h1>;
}
```

Rules:
- Use `$paramName` for dynamic segments, `_layout` for layout routes.
- Access params via `Route.useParams()` — fully type-safe.
- Use `Route.useSearch()` for search-param state (pagination, filters).
  Define the search schema with Zod in the route's `validateSearch`.
- Devtools are tree-shaken in production — leave them wired up.

---

## Zod Schemas and React Hook Form

Zod schemas are the single source of truth for both form validation and API response parsing. Derive TypeScript types with `z.infer<>`. Forms use `react-hook-form` with `zodResolver`. See `references/FORMS.md` for schema definitions, form patterns, and rules.

---

## Tailwind CSS

```css
/* src/index.css */
@import "tailwindcss";
```

Rules:
- Use utility classes for all styling. Avoid custom CSS unless Tailwind cannot
  express the rule.
- Extract repeated patterns into components, not into `@apply` directives.
  `@apply` defeats the utility-first workflow.
- Use `cn()` from `clsx` + `tailwind-merge` for conditional class composition:

```ts
// src/lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

---

## Radix UI — Headless Components

Radix provides accessible, unstyled primitives. Style them with Tailwind.

```tsx
import * as Dialog from "@radix-ui/react-dialog";
import { cn } from "@/lib/utils";

export function ConfirmDialog({
  open,
  onOpenChange,
  onConfirm,
  title,
  description,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
  title: string;
  description: string;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/40" />
        <Dialog.Content
          className={cn(
            "fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2",
            "w-full max-w-md rounded-lg bg-white p-6 shadow-lg",
          )}
        >
          <Dialog.Title className="text-lg font-semibold">{title}</Dialog.Title>
          <Dialog.Description className="mt-2 text-sm text-gray-600">
            {description}
          </Dialog.Description>
          <div className="mt-4 flex justify-end gap-2">
            <Dialog.Close asChild>
              <button className="rounded px-4 py-2 text-sm">Cancel</button>
            </Dialog.Close>
            <button
              onClick={onConfirm}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white"
            >
              Confirm
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
```

Rules:
- Always use `Dialog.Portal` so overlays render above the stacking context.
- Always include `Dialog.Title` and `Dialog.Description` for accessibility.
- Wrap each Radix primitive in a project-level component (in `components/ui/`)
  that applies your Tailwind styling. Consumers import from `@/components/ui`,
  never from `@radix-ui` directly.

---

## Component Conventions

- One component per file. File name matches the export: `OrderCard.tsx` →
  `export function OrderCard`.
- Use function declarations, not arrow-function assignments:
  `export function OrderCard()` not `export const OrderCard = () =>`.
- Props are an inline type or a named `type` — never an `interface` unless it
  extends another type.
- Prefer composition over configuration — pass children or render props rather
  than adding boolean flags.
- Never use `useEffect` for derived state. Compute it inline or with `useMemo`.
- Keep components small. If a component exceeds ~150 lines, extract sub-components.

---

## Error Handling

```tsx
// src/routes/__root.tsx — global error boundary
import { createRootRoute, Outlet, ErrorComponent } from "@tanstack/react-router";

export const Route = createRootRoute({
  component: RootLayout,
  errorComponent: ({ error }) => (
    <div className="p-8 text-center">
      <h1 className="text-xl font-bold">Something went wrong</h1>
      <p className="mt-2 text-gray-600">{error.message}</p>
    </div>
  ),
});
```

Rules:
- Use TanStack Router's `errorComponent` per route for granular error UI.
- Use TanStack Query's `error` return value for API errors — show inline, not
  via a global handler.
- For mutation errors, display the message near the form, not as a page-level
  error.
- Never expose raw server error details to the user in production.

---

## Environment Variables

```bash
# .env
VITE_API_BASE_URL=/api
```

Rules:
- Prefix all env vars with `VITE_` or they are not exposed to the client.
- Never put secrets in `VITE_*` variables — they are embedded in the build
  output.
- Access via `import.meta.env.VITE_API_BASE_URL`.

