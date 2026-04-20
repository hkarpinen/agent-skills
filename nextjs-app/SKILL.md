---
name: nextjs-app
description: Next.js App Router stack — RSC-first rendering, Server Actions, Tailwind CSS, Radix UI, React Hook Form + Zod, TanStack Query for interactive client state, and server-side markdown rendering with sanitization. Use when building or scaffolding a Next.js application with the App Router, implementing server components, creating API route handlers, managing server/client component boundaries, rendering user-generated markdown content, or structuring a full-stack Next.js project. Architecture and backend agnostic — auth tokens are issued by an external identity bounded context. Does NOT cover Pages Router, React Native, or SPA-only setups.
---

---

## Core Package Stack

## Core Package Stack

| Concern | Packages |
|---|---|
| Framework | `next`, `react`, `react-dom` |
| Server state (client components) | `@tanstack/react-query`, `@tanstack/react-query-devtools` |
| Forms | `react-hook-form`, `@hookform/resolvers`, `zod` |
| Styling | `tailwindcss`, `@tailwindcss/postcss` |
| Headless UI | `@radix-ui/react-dialog`, `@radix-ui/react-dropdown-menu`, `@radix-ui/react-tooltip` (add primitives as needed) |
| Testing | `vitest`, `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event`, `jsdom` |
| Linting | `eslint`, `eslint-config-next` |

Install only the Radix primitives you actually use.

---

## Project Structure

```
app/
├── layout.tsx              ← root layout (html, body, providers)
├── page.tsx                ← home route (/)
├── error.tsx               ← root error boundary
├── not-found.tsx           ← 404 page
├── (auth)/                 ← route group — no URL segment
│   ├── login/
│   │   └── page.tsx
│   └── layout.tsx          ← auth-specific layout (centered card)
├── orders/
│   ├── page.tsx            ← /orders list (Server Component)
│   ├── [orderId]/
│   │   └── page.tsx        ← /orders/:orderId detail
│   └── new/
│       └── page.tsx        ← /orders/new form (Client Component)
├── api/                    ← Route Handlers (webhooks, BFF proxy, callbacks)
│   └── webhooks/
│       └── route.ts
lib/
├── api-client.ts           ← configured fetch wrapper for server + client
├── auth.ts                 ← token storage, getAccessToken(), auth helpers
├── utils.ts                ← cn(), date formatting, constants
schemas/
├── order.ts                ← Zod schemas (shared between forms + API parsing)
components/
├── ui/                     ← Radix-based primitives (Button, Dialog, Input)
└── layout/                 ← Shell, Sidebar, Header
hooks/                      ← client-side custom hooks
├── use-orders.ts           ← TanStack Query hooks (client components only)
types/                      ← shared TypeScript types
```

Rules:
- `app/` owns routing and page-level components only. Shared components live
  in `components/`.
- Server Components are the default. Add `"use client"` only for components
  that need browser APIs, event handlers, hooks, or TanStack Query.
- Route Handlers (`app/api/`) are for webhooks, external callbacks, and BFF
  proxy endpoints (e.g. token exchange, cookie-based auth proxy to backend APIs)
  — not for internal data fetching. Use Server Components or Server Actions
  for data that can be fetched at request time on the server.
- Colocate route-specific components inside the route folder. Move to
  `components/` only when reused across routes.

---

## TypeScript Configuration

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"]
}
```

Rules:
- `strict: true` is non-negotiable.
- `noUncheckedIndexedAccess` catches undefined-access bugs before runtime.
- Never use `any`. Use `unknown` + type guard if the type is truly unknown.

---

## Server Components — Data Fetching

Server Components fetch data directly — no hooks, no client-side state. This
is the default for all `page.tsx` and `layout.tsx` files.

```tsx
// app/orders/page.tsx — Server Component (no "use client")
import { getOrders } from "@/lib/api-client";

export default async function OrdersPage() {
  const orders = await getOrders();

  return (
    <div>
      <h1>Orders</h1>
      <ul>
        {orders.map((order) => (
          <li key={order.id}>{order.id} — {order.status}</li>
        ))}
      </ul>
    </div>
  );
}
```

Rules:
- Server Components are `async` functions — `await` fetch calls directly.
- Never import `"use client"` hooks (`useState`, `useEffect`, `useQuery`) in
  Server Components.
- Pass data down to Client Components via props when interactivity is needed.
- Use `loading.tsx` alongside `page.tsx` for streaming/Suspense loading states.

---

## API Client — Server and Client Fetch

One typed fetch wrapper in `lib/api-client.ts` used by both Server and Client Components. Parse all responses through Zod schemas. See `references/FETCHING.md` for the full implementation pattern and rules.

---

## Authentication — External Identity Bounded Context

The backend's identity bounded context issues JWTs. This skill owns how the
Next.js app stores, forwards, and refreshes that token — not how it is issued.

```ts
// lib/auth.ts
import { cookies } from "next/headers";

// Server-side — read token from HTTP-only cookie
export async function getAccessToken(): Promise<string | null> {
  if (typeof window === "undefined") {
    const cookieStore = await cookies();
    return cookieStore.get("access_token")?.value ?? null;
  }
  // Client-side — read from cookie (set as non-httpOnly for client reads)
  // or from memory if using an in-memory token strategy
  return document.cookie
    .split("; ")
    .find((c) => c.startsWith("access_token="))
    ?.split("=")[1] ?? null;
}
```

Rules:
- Store JWTs in HTTP-only cookies when possible — safer than localStorage.
- The login page POSTs credentials to the backend's identity endpoint and
  the response sets the cookie. The Next.js app does not issue tokens.
- Protect routes with middleware:

```ts
// middleware.ts
import { NextRequest, NextResponse } from "next/server";

export function middleware(request: NextRequest) {
  const token = request.cookies.get("access_token")?.value;

  if (!token && !request.nextUrl.pathname.startsWith("/login")) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|login).*)"],
};
```

---

## Server vs Client Component Decision

```
                    Need browser APIs, event handlers,
                    hooks, or TanStack Query?
                           │
                    ┌──────┴──────┐
                    │ Yes          │ No
                    ▼              ▼
              "use client"    Server Component
              (interactive)   (default — no directive)
```

Rules:
- Server Components are the default. Never add `"use client"` preemptively.
- Push `"use client"` to the **leaf** — wrap only the interactive part, not
  the whole page. A page can be a Server Component that renders a Client
  Component child.
- Server Components can import Client Components. Client Components cannot
  import Server Components (but can accept them as `children` props).
- Data that requires interactivity (optimistic updates, polling, real-time)
  uses TanStack Query in a Client Component. Everything else fetches in
  Server Components.

---

## TanStack Query — Client Components Only

Used exclusively in Client Components for interactive scenarios: polling, optimistic updates, paginated lists. If a page only needs data on load, use a Server Component with direct fetch instead. See `references/TANSTACK-QUERY.md` for hook patterns and provider setup.

---

## Zod Schemas and React Hook Form

Zod schemas are the single source of truth for both form validation and API response parsing. Derive TypeScript types with `z.infer<>`. Forms use `react-hook-form` with `zodResolver`. See `references/FORMS.md` for schema definitions, form patterns, and rules.

---

## Server Actions — Mutations Without Client State

For mutations that don't need optimistic updates or client-side cache
management, use Server Actions. They run on the server and revalidate data
automatically.

```tsx
// app/orders/[orderId]/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { placeOrder } from "@/lib/api-client";
import { placeOrderSchema } from "@/schemas/order";

export async function placeOrderAction(formData: FormData) {
  const raw = Object.fromEntries(formData);
  const parsed = placeOrderSchema.safeParse(raw);

  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  await placeOrder(parsed.data);
  revalidatePath("/orders");
}
```

Rules:
- Server Actions are `"use server"` functions — they run on the server only.
- Always validate input with Zod. Server Actions receive untrusted data.
- Call `revalidatePath` or `revalidateTag` to refresh cached data after mutation.
- Choose Server Actions for simple form submissions. Choose React Hook Form +
  TanStack Query for forms that need client-side validation UX, optimistic
  updates, or complex field state.

---

## Tailwind CSS

```css
/* app/globals.css */
@import "tailwindcss";
```

```ts
// next.config.ts — no Tailwind config needed; v4 uses CSS-first configuration
```

Rules:
- Use utility classes for all styling. Avoid custom CSS unless Tailwind cannot
  express the rule.
- Extract repeated patterns into components, not into `@apply` directives.
- Use `cn()` from `clsx` + `tailwind-merge` for conditional class composition:

```ts
// lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

---

## Radix UI — Headless Components

Radix provides accessible, unstyled primitives.
Style them with Tailwind.

Rules:
- Radix components require `"use client"` — they use browser APIs internally.
- Wrap each Radix primitive in a project-level component (in `components/ui/`)
  that applies Tailwind styling. Consumers import from `@/components/ui`,
  never from `@radix-ui` directly.
- Always use `Dialog.Portal` so overlays render above the stacking context.
- Always include `Dialog.Title` and `Dialog.Description` for accessibility.

---

## Component Conventions

- One component per file. File name matches the export: `OrderCard.tsx` →
  `export function OrderCard`.
- Use function declarations: `export function OrderCard()` not
  `export const OrderCard = () =>`.
- Props are an inline `type` — never an `interface` unless it extends another.
- Prefer composition over configuration — pass `children` or render props
  rather than adding boolean flags.
- Never use `useEffect` for derived state. Compute inline or with `useMemo`.
- Keep components under ~150 lines. Extract sub-components when exceeded.

---

## Loading and Error States

Each route segment can define `loading.tsx` and `error.tsx` for granular
streaming and error handling.

```tsx
// app/orders/loading.tsx
export default function OrdersLoading() {
  return <div className="animate-pulse">Loading orders…</div>;
}
```

```tsx
// app/orders/error.tsx
"use client";

export default function OrdersError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="p-8 text-center">
      <h2 className="text-xl font-bold">Failed to load orders</h2>
      <p className="mt-2 text-gray-600">{error.message}</p>
      <button onClick={reset} className="mt-4 rounded bg-blue-600 px-4 py-2 text-white">
        Retry
      </button>
    </div>
  );
}
```

Rules:
- `error.tsx` must be a Client Component (`"use client"`).
- `loading.tsx` enables React Suspense streaming — the page shell renders
  immediately while the async Server Component streams in.
- Place `loading.tsx` and `error.tsx` at each route segment that fetches data.
- Never expose raw server error details to the user in production.

---

## Metadata and SEO

```tsx
// app/orders/[orderId]/page.tsx
import type { Metadata } from "next";
import { getOrder } from "@/lib/api-client";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ orderId: string }>;
}): Promise<Metadata> {
  const { orderId } = await params;
  const order = await getOrder(orderId);
  return {
    title: `Order ${order.id}`,
    description: `Details for order ${order.id}`,
  };
}
```

Rules:
- Use `generateMetadata` for dynamic titles/descriptions — never set
  `<title>` manually in the component body.
- Define static metadata via the `metadata` export for pages with fixed titles.
- `params` is a Promise — always `await` it.

---

## Environment Variables

```bash
# .env.local
NEXT_PUBLIC_API_URL=http://localhost:5000   # exposed to client bundle
API_URL=http://backend:5000                 # server-only (internal network)
```

Rules:
- `NEXT_PUBLIC_` prefix exposes the variable to the client bundle. Use for
  values the browser needs.
- Server-only variables (no prefix) are available in Server Components, Route
  Handlers, and Server Actions. Use for internal service URLs and secrets.
- Never put secrets in `NEXT_PUBLIC_*` variables.

---

## Markdown Rendering

For user-generated markdown content (forum posts, comments, articles), render on the server using `remark`/`rehype` and sanitize to prevent XSS.

### Package Stack

| Package | Purpose |
|---|---|
| `remark` | Parse markdown to AST |
| `remark-parse` | Markdown parser plugin |
| `remark-gfm` | GitHub Flavored Markdown (tables, strikethrough, task lists) |
| `remark-rehype` | Convert remark AST to rehype (HTML) AST |
| `rehype-stringify` | Serialize rehype AST to HTML string |
| `rehype-sanitize` | Sanitize HTML output (XSS prevention) |
| `rehype-highlight` | Syntax highlighting for code blocks (optional) |

### Server-Side Rendering Function

```ts
// lib/markdown.ts
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkRehype from "remark-rehype";
import rehypeSanitize, { defaultSchema } from "rehype-sanitize";
import rehypeStringify from "rehype-stringify";
import rehypeHighlight from "rehype-highlight";

const processor = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkRehype)
  .use(rehypeSanitize, {
    ...defaultSchema,
    // Extend schema to allow code highlighting classes
    attributes: {
      ...defaultSchema.attributes,
      code: [...(defaultSchema.attributes?.code ?? []), "className"],
      span: [...(defaultSchema.attributes?.span ?? []), "className"],
    },
  })
  .use(rehypeHighlight)
  .use(rehypeStringify);

export async function renderMarkdown(raw: string): Promise<string> {
  const result = await processor.process(raw);
  return String(result);
}
```

### Usage in Server Components

```tsx
// app/threads/[threadId]/page.tsx — Server Component
import { renderMarkdown } from "@/lib/markdown";

export default async function ThreadPage({ params }: { params: Promise<{ threadId: string }> }) {
  const { threadId } = await params;
  const thread = await getThread(threadId);
  const bodyHtml = await renderMarkdown(thread.body);

  return (
    <article>
      <h1>{thread.title}</h1>
      <div
        className="prose prose-neutral dark:prose-invert max-w-none"
        dangerouslySetInnerHTML={{ __html: bodyHtml }}
      />
    </article>
  );
}
```

### Tailwind Typography Plugin

Use `@tailwindcss/typography` for styling rendered HTML with the `prose` class:

```bash
npm install @tailwindcss/typography
```

```css
/* app/globals.css */
@import "tailwindcss";
@plugin "@tailwindcss/typography";
```

Rules:
- **Always sanitize** markdown output with `rehype-sanitize`. User-generated markdown is untrusted input — raw HTML injection is the most common XSS vector in markdown renderers.
- Render markdown in **Server Components** only. The `unified` pipeline is async and should not run in the browser.
- Store markdown as **raw text** in the database. Render to HTML on read, not on write. This allows changing the rendering pipeline without migrating stored content.
- Use the `prose` class from `@tailwindcss/typography` to style rendered HTML. Do not write custom CSS for headings, lists, code blocks, etc.
- For **Client Components** that need a markdown preview (e.g., live preview in a post editor), use a lightweight client-side library like `react-markdown` with `rehype-sanitize`. Do not ship the full `unified` pipeline to the browser.
- Never use `dangerouslySetInnerHTML` without prior sanitization. The `rehype-sanitize` step is non-negotiable.

