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

Install skills using the standard Agent Skills CLI:

```bash
# Install individual skills
npx skills add https://github.com/hkarpinen/agent-skills/tree/main/righting-software
npx skills add https://github.com/hkarpinen/agent-skills/tree/main/dotnet-webapi
npx skills add https://github.com/hkarpinen/agent-skills/tree/main/dotnet-testing

# Or install multiple at once
npx skills add \
  https://github.com/hkarpinen/agent-skills/tree/main/righting-software \
  https://github.com/hkarpinen/agent-skills/tree/main/dotnet-webapi \
  https://github.com/hkarpinen/agent-skills/tree/main/ddd-tactical-patterns \
  https://github.com/hkarpinen/agent-skills/tree/main/ddd-idesign-bridge
```

This creates a `.skills/` directory in your project:

```
your-project/
├── .skills/
│   ├── righting-software/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── dotnet-webapi/
│   │   ├── SKILL.md
│   │   └── references/
│   └── dotnet-testing/
│       ├── SKILL.md
│       └── references/
```

---

## Available Skills

### Architecture & Design
- **righting-software** — Juval Löwy's IDesign Method (volatility-based decomposition, layer discipline)
- **ddd-tactical-patterns** — Domain-Driven Design patterns (Entities, Aggregates, Value Objects, Domain Events)
- **ddd-idesign-bridge** — Bridge between DDD and IDesign Method

### Testing
- **testing** — Testing strategy and coverage requirements (layer-specific approaches, test types, organization)

### Backend
- **dotnet-webapi** — .NET Web API conventions (ASP.NET Core Controllers, DI patterns)
- **dotnet-testing** — Bridge between testing strategy and .NET (xUnit, Moq, FluentAssertions, Testcontainers)

### Database
- **db-postgres** — PostgreSQL conventions (schema design, naming, types, indexing)

### Bridge
- **dotnet-efcore-postgres** — Bridge between .NET and PostgreSQL (EF Core configuration, type mappings)
- **dotnet-webapi-docker** — Bridge between .NET Web API and Docker (containerization patterns)

### Infrastructure
- **docker** — Docker and Docker Compose patterns (multi-stage builds, layer caching, security)

---

## Skill Composition

Skills are designed to compose. Common combinations:

| Goal | Skills |
|---|---|
| Volatility-based architecture | `righting-software` |
| Domain modeling with DDD | `ddd-tactical-patterns` |
| DDD + IDesign architecture | `righting-software` + `ddd-tactical-patterns` + `ddd-idesign-bridge` |
| Testing strategy (any platform) | `testing` |
| .NET Web API + PostgreSQL | `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` |
| .NET testing | `testing` + `dotnet-testing` |
| Full .NET DDD project | `righting-software` + `ddd-tactical-patterns` + `ddd-idesign-bridge` + `dotnet-webapi` + `db-postgres` + `dotnet-efcore-postgres` + `testing` + `dotnet-testing` |
| Containerize .NET API | `dotnet-webapi` + `docker` + `dotnet-webapi-docker` |

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
