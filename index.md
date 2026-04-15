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
| `righting-software` | `architecture/righting-software.md` | Designing systems, decomposing services, naming components, reviewing architecture, writing contracts, discussing domain models, planning project structure, refactoring. Apply whenever entity-named services appear (e.g. `UserService`, `OrderService`). Language and stack agnostic. |

### Backend

| Skill | File | When to use |
|---|---|---|
| `dotnet-webapi` | `backend/dotnet-webapi.md` | Building or scaffolding a .NET Web API project. Package selection, project structure, DI wiring, EF Core, Serilog, FluentValidation, ASP.NET Core Identity, OpenTelemetry, HTTP resiliency. |
| `dotnet-testing` | `backend/dotnet-testing.md` | Writing or generating tests in .NET. xUnit, Moq, FluentAssertions, Testcontainers, coverage rules, test project structure. |

### Database

| Skill | File | When to use |
|---|---|---|
| `db-postgres` | `database/db-postgres.md` | Designing a PostgreSQL database schema. Naming conventions, data types, indexing, constraints, normalization. Stack agnostic. |

### Bridge

| Skill | File | When to use |
|---|---|---|
| `dotnet-efcore-postgres` | `bridge/dotnet-efcore-postgres.md` | Connecting a .NET Infrastructure layer to PostgreSQL — Npgsql provider config, snake_case mapping, entity configuration, PostgreSQL type mappings, migrations, Testcontainers integration tests. |

---

## Common Pipelines

Skills in a pipeline are applied in order — earlier skills produce output that later
skills depend on. `→` separates sequential stages; `+` within a stage means those
skills are independent and can be loaded in parallel.

| Task | Ordered skill sequence |
|---|---|
| Design a new system | `righting-software` |
| Build a .NET Web API with PostgreSQL | `righting-software` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` |
| Add tests to a .NET project | `righting-software` → `dotnet-webapi` → `dotnet-testing` |
| Review an existing codebase | `righting-software` |
| Full greenfield .NET project | `righting-software` → `dotnet-webapi` + `db-postgres` → `dotnet-efcore-postgres` → `dotnet-testing` |
| Refactor existing .NET project | `righting-software` → `dotnet-webapi` |
