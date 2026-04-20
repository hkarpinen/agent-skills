---
name: react-testing
description: Testing conventions for React applications — Vitest setup, Testing Library patterns, MSW for API mocking, component testing strategies, and hook testing. Use when writing or reviewing tests for React components, hooks, or pages in a React SPA or Next.js application.
---

## Test Stack

| Purpose | Package |
|---|---|
| Test runner | `vitest` |
| Component rendering | `@testing-library/react` |
| DOM assertions | `@testing-library/jest-dom` |
| User interaction | `@testing-library/user-event` |
| DOM environment | `jsdom` |
| API mocking | `msw` (Mock Service Worker) |

---

## Vitest Configuration

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: true,
    coverage: {
      provider: "v8",
      reporter: ["text", "cobertura"],
      thresholds: { lines: 80, branches: 80, functions: 80 },
    },
  },
  resolve: {
    alias: { "@": "." },
  },
});
```

```ts
// src/test/setup.ts
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";
import { server } from "./mocks/server";

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
});
afterAll(() => server.close());
```

---

## Component Testing — Core Pattern

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { OrderCard } from "@/components/OrderCard";

describe("OrderCard", () => {
  it("displays the order ID and status", () => {
    render(<OrderCard id="abc-123" status="confirmed" />);

    expect(screen.getByText("abc-123")).toBeInTheDocument();
    expect(screen.getByText("confirmed")).toBeInTheDocument();
  });

  it("calls onDelete when delete button is clicked", async () => {
    const user = userEvent.setup();
    const onDelete = vi.fn();

    render(<OrderCard id="abc-123" status="confirmed" onDelete={onDelete} />);

    await user.click(screen.getByRole("button", { name: /delete/i }));
    expect(onDelete).toHaveBeenCalledWith("abc-123");
  });
});
```

Rules:
- Use `userEvent.setup()` for all interactions — never `fireEvent`.
- Query by role, label, or text — never by test ID unless no semantic query exists.
- One assertion focus per test. Multiple `expect` statements are fine when they verify the same behavior.
- Use `screen` to query — never destructure from `render()`.

---

## Query Priority

Follow Testing Library's query priority:

| Priority | Query | When |
|---|---|---|
| 1 | `getByRole` | Buttons, headings, links, inputs — anything with an ARIA role |
| 2 | `getByLabelText` | Form inputs with associated labels |
| 3 | `getByPlaceholderText` | Inputs without visible labels |
| 4 | `getByText` | Non-interactive content |
| 5 | `getByDisplayValue` | Input current value |
| Last resort | `getByTestId` | Only when no semantic query works |

Rules:
- Never start with `getByTestId`. It tests implementation, not behavior.
- If you cannot find an element by role, the component likely has an accessibility problem — fix the component, not the test.

---

## MSW — API Mocking

Mock at the network level with Mock Service Worker. Never mock `fetch` or `axios` directly — MSW intercepts at the service-worker level for realistic behavior.

```ts
// src/test/mocks/handlers.ts
import { http, HttpResponse } from "msw";

export const handlers = [
  http.get("/api/orders", () =>
    HttpResponse.json([
      { id: "abc-123", status: "confirmed", customerId: "cust-1" },
    ]),
  ),

  http.post("/api/orders", async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json(
      { id: "new-456", ...body, status: "draft" },
      { status: 201 },
    );
  }),
];
```

```ts
// src/test/mocks/server.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";

export const server = setupServer(...handlers);
```

Override handlers per test when needed:

```ts
it("shows error when API fails", async () => {
  server.use(
    http.get("/api/orders", () => HttpResponse.json(null, { status: 500 })),
  );

  render(<OrdersPage />);
  expect(await screen.findByText(/failed/i)).toBeInTheDocument();
});
```

Rules:
- Define default happy-path handlers in `handlers.ts`.
- Override per test for error/edge cases using `server.use()`.
- Set `onUnhandledRequest: "error"` in setup to catch unmocked API calls.
- Never mock `useQuery` or `useMutation` directly — mock the underlying HTTP call with MSW.

---

## Testing with TanStack Query

Wrap components that use TanStack Query in a test-specific `QueryClientProvider`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });
}

export function renderWithQuery(ui: React.ReactElement) {
  const client = createTestQueryClient();
  return render(
    <QueryClientProvider client={client}>{ui}</QueryClientProvider>,
  );
}
```

Rules:
- Disable retries in tests — retries hide failures and slow the suite.
- Set `gcTime: 0` so queries are garbage-collected immediately between tests.
- Create a new `QueryClient` per test to prevent state leakage.

---

## Testing Forms (React Hook Form + Zod)

```tsx
import { renderWithQuery } from "@/test/helpers";
import { PlaceOrderForm } from "@/components/PlaceOrderForm";

it("shows validation error for empty customer ID", async () => {
  const user = userEvent.setup();
  renderWithQuery(<PlaceOrderForm />);

  await user.click(screen.getByRole("button", { name: /place order/i }));

  expect(await screen.findByText(/required/i)).toBeInTheDocument();
});

it("submits valid form data", async () => {
  const user = userEvent.setup();
  renderWithQuery(<PlaceOrderForm />);

  await user.type(
    screen.getByPlaceholderText(/customer id/i),
    "11111111-1111-1111-1111-111111111111",
  );
  await user.click(screen.getByRole("button", { name: /place order/i }));

  // MSW handler catches the POST — assert on navigation or success message
  expect(await screen.findByText(/success/i)).toBeInTheDocument();
});
```

---

## Server Component Testing (Next.js)

Server Components cannot be rendered with Testing Library (they are async functions, not React components in the traditional sense). Test them by testing their data-fetching functions directly.

```ts
// Unit test the API client function
import { getOrders } from "@/lib/api-client";

it("parses orders response correctly", async () => {
  // MSW returns the mock response
  const orders = await getOrders();
  expect(orders).toHaveLength(1);
  expect(orders[0].id).toBe("abc-123");
});
```

For full integration testing of Server Components, use Playwright or Cypress end-to-end tests.


