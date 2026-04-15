# docker

> Language-agnostic conventions for authoring Dockerfiles and Docker Compose files.

**When to use this skill**: writing or reviewing Dockerfiles, structuring multi-stage builds,
selecting base images, hardening containers, or setting up Docker Compose for local development.
Stack agnostic — applies to any language or framework.

**Scope**: this skill covers authoring Dockerfiles and Compose files. It does not cover deploying
or pushing images to registries, CI/CD pipeline integration, or container orchestration
(Kubernetes, Swarm). A stack-specific bridge skill (e.g. `dotnet-webapi-docker`) owns the
language-specific implementation of these conventions.

---

## Multi-stage Builds

Always use multi-stage builds to separate build-time dependencies from the runtime image.
Compilers, SDKs, and dev tools installed in a build stage must never land in the final image.

```dockerfile
# Stage 1 — build
FROM build-image AS build
WORKDIR /src
# ... install deps, compile

# Stage 2 — runtime
FROM runtime-image AS final
WORKDIR /app
COPY --from=build /src/output .
```

Rules:
- Name every stage with `AS <name>`. Anonymous stages cannot be referenced or targeted by `--target`.
- The final stage must contain only what is needed at runtime: compiled output, runtime, and config.
- Build tools, source code, test dependencies, and intermediate artifacts must not appear in the
  final stage.
- Use `COPY --from=<stage>` to selectively promote artifacts between stages.

---

## Base Image Selection

Choose the smallest image that satisfies the runtime requirements.

| Option | Use when |
|---|---|
| Distroless | No shell access needed; smallest possible attack surface |
| Alpine-based | Shell access needed for debugging; very small footprint |
| Slim (Debian) | Compatibility required; broader base library support needed |
| Full Debian/Ubuntu | Last resort; only for highly unusual native dependency requirements |

Rules:
- Always pin base images to a specific version tag. Never use `latest`.
- For production runtime stages, prefer distroless or slim variants over full OS images.
- In build stages, use the full SDK or toolchain image — size doesn't matter here; it's never shipped.
- Use only official or verified publisher images from Docker Hub or vendor registries.

```dockerfile
# Pinned — correct
FROM node:22.4-alpine3.20 AS build

# Unpinned — wrong
FROM node:latest AS build
```

---

## Layer Caching

Order Dockerfile instructions from least-changing to most-changing. Docker invalidates all layers
from the first changed instruction onward — so volatile instructions placed early destroy cache
reuse for everything below them.

Rules:
- Copy dependency manifests (`package.json`, `*.csproj`, `requirements.txt`, `go.mod`) before
  copying application source.
- Run the dependency install command immediately after copying manifests. This layer is cached
  until the manifests change, even when source code changes.
- Copy application source after installing dependencies.
- Group setup steps that never change (installing OS packages, creating users) at the top of each
  stage — above any `COPY` instructions.

```dockerfile
WORKDIR /app

# Step 1 — dependency manifest only (cached unless lockfile changes)
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Step 2 — source code (cache invalidated only on source changes)
COPY src/ ./src/
RUN npm run build
```

Minimizing layer count matters less than cache hit rate. Prioritize cache topology over
consolidating `RUN` commands.

---

## Security Hardening

### Non-root User

Never run a container process as root. Create a dedicated non-privileged user in the final stage.

```dockerfile
FROM runtime-image AS final

RUN addgroup --system appgroup \
 && adduser --system --ingroup appgroup appuser

WORKDIR /app
COPY --from=build /app/output .

USER appuser
```

Rules:
- Create the user and group before `COPY` so ownership is correct at container start.
- Do not use `USER root` in the final stage for any reason.
- If the base image ships a non-root user convention (e.g. Microsoft's `app` user in .NET images,
  or `node` in Node.js images), prefer it over creating a new one.

### Secrets

Never put secrets into a Dockerfile instruction or a layer. Secrets written to a layer persist in
image history even if a later `RUN` deletes them.

| Scenario | Correct approach |
|---|---|
| Secret needed only at build time (e.g. private registry token) | `docker build --secret id=token,src=.token` + `RUN --mount=type=secret,...` |
| Secret consumed at runtime | Environment variable injected at `docker run` or via Compose `env_file` |
| Connection strings, API keys | Runtime environment variable; never a `ENV` instruction in the Dockerfile |

Rules:
- Never use `ARG` or `ENV` to pass secrets — both are visible in `docker history`.
- Never commit `.env` files to version control. Add them to `.gitignore` and `.dockerignore`.
- Provide a `.env.example` file documenting required variable names with placeholder values.

### .dockerignore

Always provide a `.dockerignore` file. An oversized build context is slower and risks leaking
secrets or source control data into image layers.

```
.git
.gitignore
**/*.md
**/*.log
**/tests
**/node_modules
**/.env
**/obj
**/bin
```

Rules:
- Exclude source control directories (`.git`).
- Exclude local dev artifacts (`node_modules`, `bin`, `obj`, `.DS_Store`).
- Exclude secrets and local config (`.env`, `*.key`, `*.pem`).

---

## Docker Compose

Use Docker Compose for local development orchestration. Compose files define the full local
environment: the application, its dependencies (databases, queues, caches), and their wiring.

### File Name and Structure

Use `compose.yaml` as the filename — the canonical name as of Compose V2. Reserve
`docker-compose.yml` only for tooling that does not support the V2 spec.

```yaml
# compose.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: final
    ports:
      - "8080:8080"
    environment:
      - APP_ENV=development
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16.3-alpine3.20
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: app_user
      POSTGRES_PASSWORD: dev_password
    ports:
      - "5432:5432"
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app_user -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  db_data:
```

### Health Checks and Dependencies

Rules:
- Use `depends_on` with `condition: service_healthy` — not bare `depends_on`. Bare `depends_on`
  only waits for the container to start, not for the service inside it to be ready.
- Define a `healthcheck` on every stateful service (database, cache, queue).
- If a service does not ship a built-in healthcheck command, write one using the service's own
  readiness probe (e.g. `pg_isready`, `redis-cli ping`, an HTTP `/health` endpoint).

### Volumes

Rules:
- Use named volumes for persistent data. Never rely on anonymous volumes for stateful services —
  named volumes are explicit and reproducible.
- Bind mounts (`./local/path:/container/path`) are acceptable for development hot-reload scenarios
  but must not be used for database data directories.

### Environment Files

`.env` is loaded by `env_file` in Compose. Every project must have:

| File | Purpose | Committed? |
|---|---|---|
| `.env` | Real values for local dev | No — add to `.gitignore` |
| `.env.example` | Variable names with placeholder/doc values | Yes |

Rules:
- Do not duplicate variables between `env_file` and `environment:` in the same service — it causes
  confusion about which value takes precedence (`environment:` wins).
- Expose ports only when needed for local debugging. Internal service-to-service traffic uses the
  Compose network by default — no port exposure required.
