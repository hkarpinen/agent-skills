---
name: nextjs-docker
description: Bridge between a Next.js App Router application and Docker — multi-stage Dockerfile with standalone output, layer caching for node_modules, environment variable conventions, and Docker Compose wiring for a Next.js frontend alongside backend services. Use when containerizing a Next.js application. Compose with `nextjs-app` for framework conventions and `docker` for general container patterns.
---

## Base Images

Use official Node.js images from Docker Hub. Pin to a specific version tag with an OS variant.

| Stage | Image | Purpose |
|---|---|---|
| Install + Build | `node:<version>-alpine` | Full Node.js for `npm ci` and `next build` |
| Runtime (final) | `node:<version>-alpine` | Minimal runtime for `node server.js` |

Rules:
- Pin to a specific Node.js LTS version: `node:22-alpine`, not `node:latest`.
- Match the Node.js version across all stages.
- Alpine is the default. Use `-slim` (Debian) only if native dependencies require glibc.

---

## Standalone Output Mode

Configure Next.js to produce a standalone output bundle that includes only the dependencies needed at runtime — no `node_modules` copying required.

```ts
// next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
};

export default nextConfig;
```

The standalone output lands in `.next/standalone/` and includes a `server.js` entry point. The final Docker image runs `node server.js` — no `next start` or `npm` needed.

---

## Multi-stage Build Pattern

```dockerfile
# ──────────────────────────────────────────
# Stage 1 — install dependencies
# ──────────────────────────────────────────
FROM node:22-alpine AS deps
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

# ──────────────────────────────────────────
# Stage 2 — build
# ──────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build-time env vars (non-secret NEXT_PUBLIC_* only)
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN npm run build

# ──────────────────────────────────────────
# Stage 3 — runtime (standalone)
# ──────────────────────────────────────────
FROM node:22-alpine AS final
WORKDIR /app

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

# Copy standalone server + static assets
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

# Run as non-root
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser

EXPOSE 3000

CMD ["node", "server.js"]
```

Rules:
- **Stage 1 (deps)**: Copy only `package.json` and `package-lock.json`. The `npm ci` layer is cached until the lockfile changes.
- **Stage 2 (build)**: Copy `node_modules` from deps, then copy source. `next build` produces the standalone output.
- **Stage 3 (final)**: Copy only `.next/standalone`, `.next/static`, and `public`. No source code, no `node_modules`, no dev dependencies.
- `NEXT_PUBLIC_*` variables are baked in at build time (they are inlined into the JavaScript bundle by `next build`). Pass them as `ARG` in the build stage.
- Server-only environment variables (`API_URL`, secrets) are injected at runtime via `environment` or `env_file` in Compose — never baked into the image.

---

## Layer Caching

| Layer | Invalidated when |
|---|---|
| `npm ci` | `package.json` or `package-lock.json` changes |
| `next build` | Any source file changes |

Rules:
- Never `COPY . .` before `npm ci` — it defeats caching.
- If you use a monorepo with workspace dependencies, copy only the relevant `package.json` files first before `npm ci`.

---

## Environment Variables

| Variable | Scope | Set in | Purpose |
|---|---|---|---|
| `NEXT_PUBLIC_API_URL` | Client bundle | Build `ARG` | API URL exposed to the browser |
| `NEXT_PUBLIC_*` | Client bundle | Build `ARG` | Any value the browser needs |
| `API_URL` | Server only | Runtime `env_file` | Internal API URL for Server Components |
| `NODE_ENV` | Runtime | Dockerfile `ENV` | Always `production` in the final image |
| `HOSTNAME` | Runtime | Dockerfile `ENV` | Bind address — `0.0.0.0` for container networking |
| `PORT` | Runtime | Dockerfile `ENV` | Listener port — default `3000` |

Rules:
- `NEXT_PUBLIC_*` values are compiled into the JavaScript bundle. They cannot be changed at runtime. Pass them as build arguments.
- Server-only variables are available in Server Components, Route Handlers, and Server Actions at runtime.
- Never put secrets in `NEXT_PUBLIC_*` or `ARG`.

---

## Docker Compose Integration

```yaml
services:
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        NEXT_PUBLIC_API_URL: http://localhost:5001
    ports:
      - "3000:3000"
    environment:
      API_URL: http://api:8080          # server-only, internal network
    env_file:
      - .env
    depends_on:
      api:
        condition: service_started
    restart: unless-stopped
```

Rules:
- `build.args` passes `NEXT_PUBLIC_*` values at build time.
- `environment` and `env_file` inject server-only variables at runtime.
- Use the Compose service name (`api`) as the hostname for server-side fetches — Compose networking resolves it.
- The frontend depends on the API service but does not require a health check — if the API is down, the frontend shows error states gracefully.

---

## .dockerignore

```
.git
.gitignore
**/*.md
**/node_modules
.next
.env*
```

Rules:
- Exclude `node_modules` — they are installed fresh via `npm ci` in the deps stage.
- Exclude `.next` — it is rebuilt in the build stage.
- Exclude `.env*` — secrets must never enter the build context.

---

## Health Check

```yaml
# In compose.yaml
frontend:
  healthcheck:
    test: ["CMD-SHELL", "wget -qO- http://localhost:3000/ || exit 1"]
    interval: 10s
    timeout: 5s
    retries: 3
```

Alpine images include `wget` but not `curl`. Use `wget -qO-` for healthchecks.

---

## Companion Skills

| When you need | Skill |
|---|---|
| Next.js framework conventions (App Router, Server Components, auth) | `nextjs-app` |
| General Docker and Compose conventions | `docker` |
| Backend API containerization | The backend Docker bridge (e.g. `dotnet-webapi-docker`) |
