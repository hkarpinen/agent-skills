# Skill Index

This file is the entry point for agents. Read it first, select only the skills
relevant to the current task, then load those skill files on demand.
Do not load all skills upfront — load only what the task requires.

---

## How to Select Skills

1. Read the **When to use** column for each skill.
2. Load only the skills that match the current task.
3. If skills compose (e.g. `righting-software` + `dotnet-webapi`), load both.
4. Prefer more specific skills over general ones when both apply.

---

## Available Skills

### Architecture

| Skill | File | When to use |
|---|---|---|
| `righting-software` | `righting-software/SKILL.md` | Designing systems, decomposing services, naming components, reviewing architecture, writing contracts, discussing domain models, planning project structure, refactoring. Apply whenever entity-named services appear (e.g. `UserService`, `OrderService`). Language and stack agnostic. |
| `ddd-strategic-patterns` | `ddd-strategic-patterns/SKILL.md` | Splitting a system into bounded contexts, designing cross-context integration (events, APIs, shared-DB with separate schemas), context mapping, identity as upstream context. Use when multiple apps or services need to coexist. Language and stack agnostic. |

### Backend

| Skill | File | When to use |
|---|---|---|
| `dotnet-webapi` | `dotnet-webapi/SKILL.md` | Building or scaffolding a .NET Web API project. Package selection, project structure, DI wiring, EF Core, Serilog, FluentValidation, ASP.NET Core Identity, OpenTelemetry, HTTP resiliency. |
| `dotnet-testing` | `dotnet-testing/SKILL.md` | Writing or generating tests in .NET. xUnit, Moq, FluentAssertions, Testcontainers, coverage rules, test project structure. |

### Messaging

| Skill | File | When to use |
|---|---|---|
| `messaging` | `messaging/SKILL.md` | Implementing cross-context integration via domain events — outbox pattern, event envelopes, idempotent consumers, at-least-once delivery, dead-letter handling. Language, stack, and broker agnostic. |

### Testing

| Skill | File | When to use |
|---|---|---|
| `testing` | `testing/SKILL.md` | Planning test strategy, determining test types, setting coverage goals, organizing test projects. Platform, language, and architecture agnostic. |
| `react-testing` | `react-testing/SKILL.md` | Writing tests for React components, hooks, or pages. Vitest, Testing Library, MSW. Applies to both `react-spa` and `nextjs-app` projects. |

### Domain Modeling

| Skill | File | When to use |
|---|---|---|
| `ddd-tactical-patterns` | `ddd-tactical-patterns/SKILL.md` | Modeling domain logic with DDD patterns — Entities, Aggregates, Value Objects, Domain Events, Repositories. Language agnostic. |

### Database

| Skill | File | When to use |
|---|---|---|
| `db-postgres` | `db-postgres/SKILL.md` | Designing a PostgreSQL database schema. Naming conventions, data types, indexing, constraints, normalization. Stack agnostic. |

### Infrastructure

| Skill | File | When to use |
|---|---|---|
| `docker` | `docker/SKILL.md` | Writing or reviewing Dockerfiles, structuring multi-stage builds, selecting base images, hardening containers, or setting up Docker Compose for local development. Stack agnostic. Does not cover image deployment, CI/CD pipelines, or Kubernetes. |
| `reverse-proxy` | `reverse-proxy/SKILL.md` | Setting up Nginx or Traefik as a unified entry point for multiple services behind one domain. Path-based routing, TLS termination, Compose integration. |
| `scalability` | `scalability/SKILL.md` | Planning for production scale — connection pooling, PgBouncer, read replicas, caching (Redis), CDN, horizontal scaling checklist, database partitioning. |

### Frontend

| Skill | File | When to use |
|---|---|---|
| `react-spa` | `react-spa/SKILL.md` | Building or scaffolding a React SPA. Vite, TanStack Query, TanStack Router, Tailwind CSS, Radix UI, React Hook Form + Zod, Axios. Architecture and backend agnostic. |
| `nextjs-app` | `nextjs-app/SKILL.md` | Building or scaffolding a Next.js App Router application. RSC-first, Server Actions, TanStack Query for client state, Tailwind CSS, Radix UI, React Hook Form + Zod. Architecture and backend agnostic. Alternative to `react-spa`. |

### Bridge

| Skill | File | When to use |
|---|---|---|
| `dotnet-idesign` | `dotnet-idesign/SKILL.md` | Mapping IDesign's Client/Application/Domain/Infrastructure layer model to a .NET solution — project structure, csproj reference graph, ServiceExtensions chain, DI lifetimes per layer role, Manager/Engine/Resource Access conventions. Use alongside `righting-software` and `dotnet-webapi`. Swap for a different architecture bridge without touching `dotnet-webapi`. |
| `ddd-idesign-bridge` | `ddd-idesign-bridge/SKILL.md` | Bridging DDD tactical patterns with IDesign Method layers. Use when implementing DDD within an IDesign architecture. |
| `dotnet-efcore-postgres` | `dotnet-efcore-postgres/SKILL.md` | Connecting a .NET Infrastructure layer to PostgreSQL — Npgsql provider config, snake_case mapping, entity configuration, PostgreSQL type mappings, migrations, Testcontainers integration tests. |
| `dotnet-webapi-docker` | `dotnet-webapi-docker/SKILL.md` | Containerizing a .NET Web API — multi-stage Dockerfile, NuGet layer caching, base image selection, ASP.NET Core environment variables, and Docker Compose wiring for a .NET API with PostgreSQL. Use alongside `dotnet-webapi` and `docker`. |
| `dotnet-messaging` | `dotnet-messaging/SKILL.md` | Implementing outbox + MassTransit consumers in .NET. Bridges `messaging` patterns to EF Core + MassTransit. |
| `nextjs-docker` | `nextjs-docker/SKILL.md` | Containerizing a Next.js application — standalone output, multi-stage Dockerfile, environment variable conventions, Compose wiring. Bridges `nextjs-app` and `docker`. |

---

## Common Pipelines

Skills in a pipeline are applied in order — earlier skills produce output that later
skills depend on. `→` separates sequential stages; `+` within a stage means those
skills are independent and can be loaded in parallel.

| Task | Ordered skill sequence |
|---|---|
| Design a new system | `righting-software` |
| Build a .NET Web API with PostgreSQL | `righting-software` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` |
| Add tests to a .NET project | `testing` → `dotnet-testing` |
| Review an existing codebase | `righting-software` |
| Full greenfield .NET project | `righting-software` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` → `testing` + `dotnet-testing` |
| Refactor existing .NET project | `righting-software` → `dotnet-webapi` |
| Multi-context .NET + Next.js + Docker | `righting-software` + `ddd-strategic-patterns` → `ddd-tactical-patterns` + `ddd-idesign-bridge` → `dotnet-idesign` + `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` + `dotnet-messaging` + `messaging` → `nextjs-app` + `nextjs-docker` + `docker` + `dotnet-webapi-docker` + `reverse-proxy` → `scalability` → `testing` + `dotnet-testing` + `react-testing` |
| Containerize a .NET Web API | `dotnet-webapi` + `docker` → `dotnet-webapi-docker` |
| Containerize a .NET Web API with PostgreSQL | `dotnet-webapi` + `docker` + `db-postgres` → `dotnet-efcore-postgres` + `dotnet-webapi-docker` |
| Build a React SPA | `react-spa` |
| Build a Next.js app | `nextjs-app` |
| Full-stack .NET + React + PostgreSQL | `righting-software` → `dotnet-webapi` + `db-postgres` + `react-spa` → `dotnet-efcore-postgres` → `testing` + `dotnet-testing` |
| Full-stack .NET + Next.js + PostgreSQL | `righting-software` → `dotnet-webapi` + `db-postgres` + `nextjs-app` → `dotnet-efcore-postgres` → `testing` + `dotnet-testing` |
| Multi-context system design | `righting-software` + `ddd-strategic-patterns` |
| Multi-context .NET + PostgreSQL | `righting-software` + `ddd-strategic-patterns` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` → `testing` + `dotnet-testing` (per context) |
| Add messaging between contexts | `messaging` → `dotnet-messaging` |
| Containerize a Next.js app | `nextjs-app` + `docker` → `nextjs-docker` |
| Multi-context .NET + Next.js + Docker + Messaging | `righting-software` + `ddd-strategic-patterns` → `dotnet-webapi` + `db-postgres` + `messaging` → `dotnet-efcore-postgres` + `dotnet-messaging` → `nextjs-app` + `docker` → `nextjs-docker` + `dotnet-webapi-docker` → `reverse-proxy` → `testing` + `dotnet-testing` + `react-testing` |
| Add React/Next.js testing | `testing` → `react-testing` |
