# Skills

A versioned library of AI agent skills for building maintainable software systems.
Compliant with the [Agent Skills specification](https://agentskills.io/specification).

---

## What is a skill?

A skill is a self-contained guide that gives an AI agent focused, opinionated
guidance for a specific concern. Skills compose — a typical project loads 3-5 skills
that each own a distinct concern and never duplicate each other.

---

## Installation

Install skills using the [Agent Skills CLI](https://github.com/vercel-labs/skills):

```bash
# List available skills
npx skills add hkarpinen/agent-skills --list

# Install specific skills by name
npx skills add hkarpinen/agent-skills --skill righting-software --skill dotnet-webapi

# Install all skills
npx skills add hkarpinen/agent-skills --all
```

### Presets

Copy-paste the command for your project shape:

**Full .NET DDD + IDesign + PostgreSQL + Docker**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill ddd-tactical-patterns \
  --skill ddd-idesign-bridge \
  --skill dotnet-idesign \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill docker \
  --skill dotnet-webapi-docker \
  --skill testing \
  --skill dotnet-testing
```

**Full .NET DDD + IDesign + PostgreSQL (no Docker)**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill ddd-tactical-patterns \
  --skill ddd-idesign-bridge \
  --skill dotnet-idesign \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill testing \
  --skill dotnet-testing
```

**.NET Web API + PostgreSQL (no DDD)**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill testing \
  --skill dotnet-testing
```

**Full-stack .NET + React SPA + PostgreSQL**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill react-spa \
  --skill testing \
  --skill dotnet-testing
```

**Full-stack .NET + Next.js + PostgreSQL**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill nextjs-app \
  --skill testing \
  --skill dotnet-testing
```

**Multi-context .NET + Next.js + PostgreSQL + Docker + Messaging**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill ddd-strategic-patterns \
  --skill ddd-tactical-patterns \
  --skill ddd-idesign-bridge \
  --skill dotnet-idesign \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill messaging \
  --skill dotnet-messaging \
  --skill nextjs-app \
  --skill nextjs-docker \
  --skill docker \
  --skill dotnet-webapi-docker \
  --skill reverse-proxy \
  --skill testing \
  --skill dotnet-testing \
  --skill react-testing
```

**Multi-context system (.NET + PostgreSQL + DDD Strategic)**
```bash
npx skills add hkarpinen/agent-skills \
  --skill righting-software \
  --skill ddd-strategic-patterns \
  --skill ddd-tactical-patterns \
  --skill ddd-idesign-bridge \
  --skill dotnet-idesign \
  --skill dotnet-webapi \
  --skill db-postgres \
  --skill dotnet-efcore-postgres \
  --skill testing \
  --skill dotnet-testing
```

**React SPA only**
```bash
npx skills add hkarpinen/agent-skills --skill react-spa --skill testing
```

**Next.js only**
```bash
npx skills add hkarpinen/agent-skills --skill nextjs-app --skill testing
```

---

## Available Skills

### Architecture & Design
- **righting-software** — Juval Löwy's IDesign Method (volatility-based decomposition, layer discipline)
- **ddd-tactical-patterns** — Domain-Driven Design patterns (Entities, Aggregates, Value Objects, Domain Events)
- **ddd-strategic-patterns** — Bounded Contexts, Context Maps, cross-context integration for multi-app systems

### Testing
- **testing** — Testing strategy and coverage requirements (layer-specific approaches, test types, organization)
- **react-testing** — React testing conventions (Vitest, Testing Library, MSW, component and hook testing)

### Messaging
- **messaging** — Asynchronous messaging patterns (outbox, event envelopes, idempotent consumers, dead-letter handling)

### Backend
- **dotnet-webapi** — .NET Web API conventions (ASP.NET Core Controllers, DI patterns)
- **dotnet-testing** — Bridge between testing strategy and .NET (xUnit, Moq, FluentAssertions, Testcontainers)

### Database
- **db-postgres** — PostgreSQL conventions (schema design, naming, types, indexing)

### Frontend
- **react-spa** — React SPA stack (Vite, TanStack Query/Router, Tailwind CSS, Radix UI, RHF + Zod)
- **nextjs-app** — Next.js App Router stack (RSC-first, Server Actions, TanStack Query, Tailwind CSS, Radix UI)

### Bridge
- **dotnet-idesign** — Bridge between IDesign Method and .NET solution structure
- **ddd-idesign-bridge** — Bridge between DDD tactical patterns and IDesign Method
- **dotnet-efcore-postgres** — Bridge between .NET and PostgreSQL (EF Core configuration, type mappings)
- **dotnet-webapi-docker** — Bridge between .NET Web API and Docker (containerization patterns)
- **dotnet-messaging** — Bridge between messaging patterns and .NET (MassTransit, outbox with EF Core)
- **nextjs-docker** — Bridge between Next.js and Docker (standalone output, multi-stage build)

### Infrastructure
- **docker** — Docker and Docker Compose patterns (multi-stage builds, layer caching, security)
- **reverse-proxy** — Reverse proxy patterns (Nginx, Traefik, path-based routing, TLS termination)
- **scalability** — Scalability patterns (connection pooling, read replicas, caching, CDN, horizontal scaling)

---

## Skill Composition

Skills are designed to compose. Common combinations:

| Goal | Skills |
|---|---|
| Volatility-based architecture | `righting-software` |
| Domain modeling with DDD | `ddd-tactical-patterns` |
| DDD + IDesign architecture | `righting-software` + `ddd-tactical-patterns` + `ddd-idesign-bridge` + `dotnet-idesign` |
| Multi-context system design | `righting-software` + `ddd-strategic-patterns` |
| Testing strategy (any platform) | `testing` |
| .NET Web API + PostgreSQL | `righting-software` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` |
| .NET testing | `testing` + `dotnet-testing` |
| React SPA | `react-spa` + `testing` |
| Next.js app | `nextjs-app` + `testing` |
| Full-stack .NET + React + PostgreSQL | `righting-software` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` + `react-spa` + `testing` + `dotnet-testing` |
| Full-stack .NET + Next.js + PostgreSQL | `righting-software` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` + `nextjs-app` + `testing` + `dotnet-testing` |
| Multi-context .NET + Next.js + Messaging | `righting-software` + `ddd-strategic-patterns` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` + `messaging` + `dotnet-messaging` + `nextjs-app` + `testing` + `dotnet-testing` + `react-testing` |
| Containerize .NET API | `dotnet-webapi` + `docker` + `dotnet-webapi-docker` |
| Full .NET DDD project | `righting-software` + `ddd-tactical-patterns` + `ddd-idesign-bridge` + `dotnet-idesign` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` + `testing` + `dotnet-testing` |

---

## For AI Agents

Skills follow the [Agent Skills specification](https://agentskills.io/specification). Each skill has:
- `SKILL.md` — Main skill content (concise, <500 lines)
- `references/*.md` — Detailed examples and patterns (loaded on demand)

Load skills progressively: start with `SKILL.md`, load reference files only when needed for specific details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding or updating skills.

1. Create or edit the `.md` file in the appropriate directory.
2. Update `index.md` with the skill entry.
3. Open a PR — skill changes are reviewed like code changes.
4. On merge to `main`, a release is tagged and `.skill` artifacts are built by CI.
