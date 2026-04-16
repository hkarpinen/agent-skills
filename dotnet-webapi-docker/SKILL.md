---
name: dotnet-webapi-docker
description: Connects a .NET Web API project to Docker, implementing general Docker conventions for the .NET SDK and ASP.NET Core runtime. Use when writing a Dockerfile for a .NET Web API project, structuring the multi-stage .NET build pipeline, configuring Docker Compose for a .NET API, or applying .NET-specific container conventions.
---

## Base Images

Use Microsoft's official .NET images from `mcr.microsoft.com`. The ASP.NET runtime image ships
a non-root `app` user by convention — use it instead of creating your own.

| Stage | Image | Purpose |
|---|---|---|
| Restore / Build / Publish | `mcr.microsoft.com/dotnet/sdk:<version>` | Full SDK for `dotnet restore`, `dotnet build`, `dotnet publish` |
| Runtime (final) | `mcr.microsoft.com/dotnet/aspnet:<version>` | ASP.NET Core runtime only — no SDK, no build tools |

Rules:
- Pin to a specific version tag that includes the OS variant. Prefer `-noble` (Ubuntu 24.04) for
  compatibility or `-alpine` for a smaller footprint.
- The SDK image is build-stage-only — it must never be the final stage.
- Match SDK and runtime versions exactly. Never mix e.g. SDK 9 with an ASP.NET 8 runtime image.

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS restore
# ...
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble AS final
```

---

## Multi-stage Build Pattern

The .NET build pipeline maps to four named stages: restore → build → publish → final.

```dockerfile
# ─────────────────────────────────────────
# Stage 1 — restore (NuGet cache layer)
# ─────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS restore
WORKDIR /src

# Copy only project files first — NuGet restore layer is cached until .csproj files change.
# List projects from least-volatile to most-volatile so a change to the
# host project does not bust the cache for shared libraries.
# The architecture bridge specifies the actual project
# names and their volatility order.
COPY ["src/<SharedLib>/<SharedLib>.csproj",       "src/<SharedLib>/"]
COPY ["src/<DomainProject>/<DomainProject>.csproj", "src/<DomainProject>/"]
COPY ["src/<AppProject>/<AppProject>.csproj",     "src/<AppProject>/"]
COPY ["src/<DataProject>/<DataProject>.csproj",   "src/<DataProject>/"]
COPY ["src/<HostProject>/<HostProject>.csproj",   "src/<HostProject>/"]

RUN dotnet restore "src/<HostProject>/<HostProject>.csproj"

# ─────────────────────────────────────────
# Stage 2 — build
# ─────────────────────────────────────────
FROM restore AS build
COPY . .
RUN dotnet build "src/<HostProject>/<HostProject>.csproj" \
    --configuration Release \
    --no-restore

# ─────────────────────────────────────────
# Stage 3 — publish
# ─────────────────────────────────────────
FROM build AS publish
RUN dotnet publish "src/<HostProject>/<HostProject>.csproj" \
    --configuration Release \
    --no-build \
    --output /app/publish

# ─────────────────────────────────────────
# Stage 4 — final (runtime only)
# ─────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Use Microsoft's built-in non-root user — do not create a new one
USER app

ENTRYPOINT ["dotnet", "<HostProject>.dll"]
```

Rules:
- The restore stage copies `.csproj` files only — not source. This is the NuGet cache layer.
  It is invalidated only when project file references change, not on source edits.
- Pass `--no-restore` to `dotnet build` and `--no-build` to `dotnet publish` to prevent redundant
  package restore and compilation during the pipeline.
- The final stage contains only the published output from the publish stage. No source, no SDK,
  no test projects are present.
- Use `USER app` in the final stage. `mcr.microsoft.com/dotnet/aspnet` ships this user — do not
  define a new user.

---

## NuGet Layer Caching

The order of individual `COPY` instructions for project files determines cache sensitivity.
List projects from least-volatile to most-volatile (shared libraries → domain → application → data-access → host)
so that a change to the host project does not bust the cache for shared library projects.
The architecture bridge specifies the actual project names and their volatility order.

Rules:
- Copy each `.csproj` individually with its destination path mirroring the source tree structure.
- Never use `COPY . .` before `dotnet restore` — it defeats layer caching by invalidating on any
  source file change.
- When a new project is added to the solution, add its `COPY` line to the restore stage.
- The `Tests` project is not included. It is never built in the production Docker image.

---

## Environment Variables

Configure ASP.NET Core via environment variables at runtime. Do not bake environment-specific
values into the image with `ENV` instructions.

| Variable | Purpose | Example value |
|---|---|---|
| `ASPNETCORE_ENVIRONMENT` | Selects `appsettings.{env}.json` and framework behavior | `Development`, `Production` |
| `ASPNETCORE_URLS` | Binds the Kestrel listener | `http://+:8080` |
| `ConnectionStrings__Default` | Overrides the `Default` connection string from `appsettings.json` | `Host=db;Port=5432;...` or `Server=db;...` |

Rules:
- Never put `ASPNETCORE_ENVIRONMENT=Development` in the Dockerfile — that bakes dev behavior into
  the image. Inject it at runtime via Compose or the container host.
- For .NET 8+, Kestrel defaults to port 8080 in container environments. For earlier versions the
  default is port 80. Confirm your `ASPNETCORE_URLS` value matches your Compose port mapping.
- Use the double-underscore `__` separator to override nested `appsettings.json` keys via
  environment variables (`ConnectionStrings__Default` maps to `ConnectionStrings.Default`).
- Do not terminate TLS inside the container for local development. Use Docker Compose networking
  unencrypted internally and terminate TLS at a reverse proxy or load balancer.

---

## Running EF Core Migrations in Containers

`dotnet-webapi` forbids applying migrations at application startup: a crashing
replica that auto-migrates is a destructive operation disguised as a health
issue. The container image therefore must not run `dotnet ef database update`
from `Program.cs`. Pick one of the following strategies instead:

| Strategy | Approach | When to use |
|---|---|---|
| **SQL script from CI/CD** | `dotnet ef migrations script --idempotent` in CI; apply the `.sql` from the deployment pipeline (Flyway, psql, Helm hook, etc.) | **Default for production**. Migration is reviewed, auditable, and decoupled from the runtime image. |
| **Migration bundle binary** | `dotnet ef migrations bundle --self-contained`; ship the bundle as a separate image; run it as an init container / Compose `depends_on` service before the API | Kubernetes / Compose deployments that want migration-as-code without shipping the full SDK to production |
| **`dotnet ef` in a one-shot container** | Build a side image `FROM sdk` with the source mounted; run `dotnet ef database update` once per deploy | Local dev and CI test environments only — never production |

Rules:
- Never apply migrations from the API container's startup path. Rolling
  deployments will race multiple replicas against one schema.
- The production runtime image (ASP.NET runtime, not SDK) cannot run
  `dotnet ef` — the EF Core tools require the SDK. Either emit SQL from CI or
  build a dedicated migrations image from the SDK base.
- The migrations image is never the same as the API image. Do not add the SDK
  to the API image just to get `dotnet ef`.

### Compose pattern — one-shot migrations service

For local dev parity with production, run migrations as a separate Compose
service that runs to completion before the API starts.

```yaml
services:
  migrate:
    image: your-api-migrations:latest   # built from the migrations bundle
    depends_on:
      db:
        condition: service_healthy
    environment:
      ConnectionStrings__Default: Host=db;Port=5432;Database=yourapp;Username=app_user;Password=dev_password
    restart: "no"                       # run once, exit

  api:
    build:
      context: .
      target: final
    depends_on:
      migrate:
        condition: service_completed_successfully
      db:
        condition: service_healthy
```

`condition: service_completed_successfully` (Compose V2) gates the API on a
clean migration exit. A non-zero migration exit blocks API startup — which is
the behaviour you want.

---

## Docker Compose for .NET API

```yaml
# compose.yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
      target: final
    ports:
      - "8080:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ASPNETCORE_URLS: http://+:8080
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    # Image, environment, healthcheck, and volumes depend on your database.
    # The DB bridge skill (e.g. dotnet-efcore-postgres) specifies the
    # database-specific Compose service definition.
    image: <database-image>
    env_file:
      - .env
    healthcheck:
      test: ["CMD-SHELL", "<db-ready-check>"]
      interval: 5s
      timeout: 5s
      retries: 5
    volumes:
      - db_data:<db-data-path>

volumes:
  db_data:
```

Place secrets in `.env` (never committed to version control):

```env
# .env
ConnectionStrings__Default=<connection-string-using-db-as-hostname>
```

Rules:
- Reference the Compose service name (`db`) as the hostname in the connection string, not
  `localhost`. Compose networking routes the service name to the database container's IP.
- Use `depends_on` with `condition: service_healthy` so the API waits for the database
  health check before starting — not just for the container to exist.
- Never hard-code passwords or the connection string in `compose.yaml`. Provide them
  via `.env` and document placeholders in `.env.example`.
- `ASPNETCORE_ENVIRONMENT` and `ASPNETCORE_URLS` are safe to set directly in `compose.yaml` —
  they are not secrets and are environment-specific by design.
