# Skill Index

This file is the entry point for agents. Read it first, select only the skills
relevant to the current task, then load those skill files on demand.
Do not load all skills upfront — load only what the task requires.

---

## How to Select Skills

1. Read the **When to use** column for each skill.
2. Load only the skills that match the current task.
3. Prefer more specific skills over general ones when both apply.

---

## Available Skills

### Discovery

| Skill | File | When to use |
|---|---|---|
| `requirements-discovery` | `requirements-discovery/SKILL.md` | A user requests building an application or feature without specifying user roles, workflows, MVP scope, or non-functional requirements. Run BEFORE architecture or implementation skills. |

### Architecture

| Skill | File | When to use |
|---|---|---|
| `righting-software` | `righting-software/SKILL.md` | Designing systems, decomposing services, naming components, reviewing architecture, writing contracts, discussing domain models, planning project structure, refactoring. Apply whenever entity-named services appear (e.g. `UserService`, `OrderService`). Language and stack agnostic. |
| `ddd-strategic-patterns` | `ddd-strategic-patterns/SKILL.md` | Splitting a system into bounded contexts, designing cross-context integration (events, APIs, shared-DB with separate schemas), context mapping, identity as upstream context. Use when multiple apps or services need to coexist. Language and stack agnostic. |
| `authorization` | `authorization/SKILL.md` | Controlling who can do what — RBAC, resource ownership, role hierarchies, permission models, where authorization lives in layered architectures. Use whenever an application has roles, ownership checks, or moderation. Language and stack agnostic. |

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
| `react-testing` | `react-testing/SKILL.md` | Writing tests for React components, hooks, or pages. Vitest, Testing Library, MSW. |

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
| `ci-cd` | `ci-cd/SKILL.md` | Setting up CI/CD pipelines with GitHub Actions for .NET and Next.js projects — build/test/deploy stages, migration script generation, Docker image publishing, environment promotion. Examples use GitHub Actions with .NET and Next.js. |

### Notifications & Real-Time

| Skill | File | When to use |
|---|---|---|
| `notifications` | `notifications/SKILL.md` | Implementing user notifications (in-app, email, push) — notification domain model, storage, delivery channels, read/unread tracking, aggregation, and preferences. Stack agnostic. |
| `realtime` | `realtime/SKILL.md` | Implementing live updates (vote counts, new replies, typing indicators, notification badges) — SSE and WebSocket transport patterns, scaling persistent connections, reverse proxy configuration. Stack agnostic. |

### Media

| Skill | File | When to use |
|---|---|---|
| `media-storage` | `media-storage/SKILL.md` | Implementing file uploads, object storage (S3/MinIO), presigned URLs, image processing, and CDN integration. Stack agnostic. |

### Frontend

| Skill | File | When to use |
|---|---|---|
| `react-spa` | `react-spa/SKILL.md` | Building or scaffolding a React SPA. Vite, TanStack Query, TanStack Router, Tailwind CSS, Radix UI, React Hook Form + Zod, Axios. Architecture and backend agnostic. |
| `nextjs-app` | `nextjs-app/SKILL.md` | Building or scaffolding a Next.js App Router application. RSC-first, Server Actions, TanStack Query for client state, Tailwind CSS, Radix UI, React Hook Form + Zod. Architecture and backend agnostic. |

### Bridge

| Skill | File | When to use |
|---|---|---|
| `dotnet-idesign` | `dotnet-idesign/SKILL.md` | Mapping IDesign's Client/Application/Domain/Infrastructure layer model to a .NET solution — project structure, csproj reference graph, ServiceExtensions chain, DI lifetimes per layer role, Manager/Engine/Resource Access conventions. |
| `ddd-idesign-bridge` | `ddd-idesign-bridge/SKILL.md` | Bridging DDD tactical patterns with IDesign Method layers. Use when implementing DDD within an IDesign architecture. |
| `dotnet-efcore-postgres` | `dotnet-efcore-postgres/SKILL.md` | Connecting a .NET Infrastructure layer to PostgreSQL — Npgsql provider config, snake_case mapping, entity configuration, PostgreSQL type mappings, migrations, Testcontainers integration tests. |
| `dotnet-webapi-docker` | `dotnet-webapi-docker/SKILL.md` | Containerizing a .NET Web API — multi-stage Dockerfile, NuGet layer caching, base image selection, ASP.NET Core environment variables, and Docker Compose wiring for a .NET API with PostgreSQL. |
| `dotnet-messaging` | `dotnet-messaging/SKILL.md` | Implementing outbox + MassTransit consumers in .NET. |
| `nextjs-docker` | `nextjs-docker/SKILL.md` | Containerizing a Next.js application — standalone output, multi-stage Dockerfile, environment variable conventions, Compose wiring. |
| `dotnet-realtime` | `dotnet-realtime/SKILL.md` | Implementing real-time updates in .NET with SignalR — hub definition, IHubContext broadcasting, group management, Redis backplane, frontend client. |
| `dotnet-authorization` | `dotnet-authorization/SKILL.md` | ASP.NET Core authorization — policy definitions, `[Authorize]`, `IAuthorizationHandler` for resource-based authorization, claims mapping. |

