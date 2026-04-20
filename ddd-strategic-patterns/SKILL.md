---
name: ddd-strategic-patterns
description: Domain-Driven Design strategic patterns — Bounded Contexts, Context Maps, integration patterns, and shared infrastructure conventions for multi-app systems. Use when splitting a system into multiple applications or services, deciding what belongs in which bounded context, designing cross-context integration (events, APIs, shared database schemas), or planning a multi-app architecture. Language, stack, and architecture agnostic. Does NOT cover tactical patterns within a single context or single-app layer decomposition.
---

## Scope

This skill owns **system-level boundary decisions** — how multiple bounded contexts relate, integrate, and share infrastructure without coupling.

---

## Identifying Bounded Contexts

A bounded context is a boundary within which a domain model is consistent and a ubiquitous language applies. Each context is deployed, developed, and migrated independently.

### How to Find Boundaries

Apply these heuristics in order:

1. **Different ubiquitous language** — If two teams (or two features) use the same word to mean different things, that's a boundary. "User" in Identity means credentials + roles. "User" in Forum means display name + avatar. They are different models.

2. **Different volatility profiles** — If two areas change at different rates, for different reasons, or by different stakeholders, they belong in separate contexts. This aligns with IDesign's volatility principle — applied at the system level.

3. **Different business capabilities** — Authentication, billing, discussion, household management are distinct capabilities. Each gets its own context.

4. **Independent deployability** — If you need to deploy X without touching Y, they are separate contexts.

### Naming Rules

Name contexts after the business capability they encapsulate — not after the entity they store.

| ✅ Capability-named | ❌ Entity-named |
|---|---|
| Identity | UserService |
| Forum | PostService |
| Billing | InvoiceService |
| Household Bills | BillService |

---

## Context Map — Relationships

Every pair of contexts that communicates has a defined relationship. Document it explicitly.

### Relationship Types

| Relationship | Description | When to use |
|---|---|---|
| **Upstream / Downstream** | Upstream publishes; downstream consumes. Upstream sets the contract. | Default for most integrations. |
| **Conformist** | Downstream adopts upstream's model as-is. | When the upstream model is stable and close enough to what you need. |
| **Anti-Corruption Layer (ACL)** | Downstream translates upstream's model into its own. | When upstream's model would pollute your domain. |
| **Published Language** | Shared schema (e.g., OpenAPI spec, event schema) that both sides agree on. | APIs and events exposed to multiple consumers. |
| **Shared Kernel** | Two contexts share a small, explicitly defined set of code or schema. | Use sparingly — shared kernel is shared coupling. |
| **Separate Ways** | No integration. Contexts are fully independent. | When the cost of integration exceeds the benefit. |

Rules:
- Every integration between contexts must be classified into one of these relationships.
- Prefer Upstream/Downstream with an ACL over Shared Kernel. Shared Kernel is coupling by another name.
- Document the context map in a single place (diagram or table) that everyone on the team can read.

### Example Context Map

```
┌──────────┐   upstream    ┌──────────┐
│ Identity │──────────────→│  Forum   │  (conformist — Forum trusts Identity's user ID)
└──────────┘               └──────────┘
      │                          │
      │ upstream                 │ upstream
      ▼                          ▼
┌──────────────┐          ┌──────────┐
│ Household    │          │  Audit   │  (conformist — consumes events from all contexts)
│ Bills        │          └──────────┘
└──────────────┘
```

---

## The Golden Rule: Reference by ID Only

Contexts never hold object references to another context's entities. They hold an ID — a UUID that means "this thing exists over there."

```
// Forum context stores:
forum.posts.author_id  →  UUID (matches identity.users.id by convention)

// Forum does NOT:
- JOIN to identity.users
- Import Identity's User entity
- Hold a foreign key to identity.users.id
```

This is the single most important rule for context independence. Violating it couples deployment, migration, and schema evolution across contexts.

---

## Shared Database — Isolation Strategy

Multiple contexts can share a single database server. Each context owns exactly one isolated unit — either a separate **database** or a separate **schema** within the same database.

### Database-per-Context vs Schema-per-Context

Choose one approach per system; do not mix them.

| Approach | Isolation level | When to use |
|---|---|---|
| **Database-per-context** | Strongest — cross-database queries are impossible in most RDBMS | Default for microservice deployments. Each context gets its own connection string. Simplest to reason about. |
| **Schema-per-context** | Moderate — cross-schema queries are possible but forbidden by convention | Acceptable when running a single database instance in development or when operational cost of multiple databases is prohibitive. Requires discipline. |

**Database-per-context** (separate databases on one server):
```
PostgreSQL server
 ├── identity (database)   → owned exclusively by Identity context
 ├── forum (database)      → owned exclusively by Forum context
 └── billing (database)    → owned exclusively by Billing context
```

**Schema-per-context** (separate schemas in one database):
```
Database: myapp
 ├── identity.*     → owned exclusively by Identity context
 ├── forum.*        → owned exclusively by Forum context
 ├── billing.*      → owned exclusively by Billing context
 └── public.*       → shared extensions only
```

Rules:
- When using **database-per-context**, each context's connection string points to a different database. Cross-database queries are structurally impossible.
- When using **schema-per-context**, each context's persistence layer targets its own schema via the ORM's default schema configuration. Cross-schema queries are possible but forbidden — enforce by code review and CI checks.
- In **Docker Compose** local development with database-per-context, use an init script mounted into the database container's entrypoint directory to create the databases on first run.

Principles:
- **One schema per context, one context per schema.** No exceptions.
- **No cross-schema referential constraints.** Foreign key enforcement across schemas couples migration ordering. Use UUID references and verify at the application layer.
- **No cross-schema queries in production code.** If you need data from another context, use an integration pattern (see below). Ad-hoc cross-schema queries in analytics tooling are acceptable.
- **Migrations run per context.** Each app runs its own migration tool targeting only its schema. Never run another context's migrations.
- **Connection credentials**: in production, each context gets its own database role scoped to its schema only. In development, a shared superuser is acceptable.

---

## Integration Patterns

When Context A needs data or behavior from Context B, choose one of these patterns. Never bypass the boundary by sharing database access.

### 1. Synchronous — API Call

Context A calls Context B's HTTP API at request time.

```
Forum needs to verify a user exists
→ Forum calls GET /api/users/{userId} on Identity's API
→ Identity returns 200 or 404
→ Forum proceeds or rejects
```

**Use when**:
- The data must be current (not stale)
- The call is infrequent or latency is acceptable
- Context B is highly available

**Risks**: Runtime coupling — if Identity is down, Forum's write fails. Mitigate with retries and circuit breakers.

### 2. Asynchronous — Domain Events

Context A publishes a domain event. Context B subscribes and reacts.

```
Identity publishes: UserRegistered { userId, username, email }
Forum subscribes:   → inserts into forum.users (userId, displayName)
Bills subscribes:   → inserts into bills.members (userId, displayName)
```

**Use when**:
- Eventual consistency is acceptable (seconds, not transactions)
- Multiple downstream contexts need to react to the same event
- You want to decouple deployment and availability

**Event rules** (tactical DDD patterns applied at the system level):
- Events are immutable facts — named in past tense
- Events carry IDs and relevant data — never the full entity
- The publisher defines the event schema (Published Language)
- Subscribers maintain their own local projection of the data they need

### 3. Local Projection — Replicated Read Model

A downstream context subscribes to upstream events and maintains a **local copy** of the data it needs for reads. This eliminates runtime API calls for common queries.

```
Identity publishes → UserRegistered { userId, username, avatarUrl }
Identity publishes → UserProfileUpdated { userId, username, avatarUrl }

Forum subscribes → upserts into its own schema:
  forum.users (id, display_name, avatar_url)

Forum's post query joins within its own schema:
  posts + forum.users  (joined on author_id = id)
  — this query is within Forum's schema — legal and fast
```

Rules:
- The local projection table lives in the **downstream context's schema** — it is owned, migrated, and indexed by the downstream.
- The projection is eventually consistent. Display "Unknown user" if the event hasn't arrived yet — never fail the request.
- Project only what you need — IDs, display names, status. Never project the full upstream entity.
- On schema change, the downstream updates its projection consumer — not the upstream's event schema.

### Choosing a Pattern

| Situation | Pattern |
|---|---|
| Need to verify state before a write (e.g., "does this user exist?") | Synchronous API call |
| Need to display data from another context in read-heavy UI | Local projection |
| Need to react to something that happened in another context | Async domain event |
| Need transactional consistency across contexts | **Redesign** — you have the boundary wrong |

If you need transactional consistency between two things, they belong in the same bounded context. Cross-context transactions (two-phase commit, sagas for consistency) are a last resort at this scale — prefer redesigning the boundary.

---

## Identity as the Upstream Context

In most systems, Identity is a natural upstream context — it publishes user lifecycle events and issues authentication tokens. All other contexts are downstream.

Rules:
- Identity issues tokens (e.g. JWTs). Downstream contexts **verify** tokens — they never query Identity's database or call Identity's internal APIs for auth checks. The backend/frontend skills specify the token format and verification mechanism.
- The token payload is a **published language** — an explicit contract. It carries user ID, display name, email, and roles. Downstream contexts extract what they need from the token.
- If a downstream context needs user data beyond what's in the token (e.g., avatar URL for display), it subscribes to Identity's events and maintains a local projection.
- Identity does not know about Forum, Bills, or any other downstream context. It publishes events; it does not push data to specific consumers.

---

## Each Context Runs Its Own Pipeline

Every bounded context is a standalone app with its own full skill pipeline. The skills compose independently per context:

```
Identity app:   architecture → backend + database → database bridge → testing
Forum app:      architecture → backend + database + frontend → database bridge → testing
Bills app:      architecture → backend + database + frontend → database bridge → testing
```

Rules:
- Each context has its own codebase, its own persistence context (scoped to its schema), its own migrations, its own test suite.
- Contexts do not share code libraries. If two contexts need the same utility (e.g., a `Money` value object), each defines its own copy. Shared code is shared coupling.
- Exception: a thin **contracts package** containing event schemas may be shared via a package feed. This is a Published Language — keep it minimal and version it carefully.

---

## Multi-Context Repository Layout

When a system has multiple bounded contexts, organize the repository so each context is independently buildable and deployable.

### Mono-repo (Recommended for small-to-medium teams)

All contexts live in one repository. Each context is a separate folder with its own solution/project, its own Dockerfile, and its own test suite. The root contains only cross-cutting infrastructure files (Compose, proxy config, CI pipeline).

```
repo/
├── identity/                  ← Independent solution / app
│   ├── src/
│   ├── tests/
│   └── Dockerfile
├── forum/
│   ├── src/
│   ├── tests/
│   └── Dockerfile
├── frontend/
│   ├── app/
│   └── Dockerfile
├── contracts/                 ← Optional: shared event schemas (Published Language)
├── compose.yaml               ← Full local dev environment
├── nginx.conf                 ← Reverse proxy config
└── init-databases.sql         ← Database initialization script
```

Rules:
- Each context folder contains a complete, independently buildable application. A developer can `cd identity/ && dotnet build` without touching other folders.
- The `contracts/` folder is the **only** shared code. It contains event schema types (Published Language) and is versioned. If using .NET, publish it as a NuGet package. If using Node.js, publish as an npm package.
- CI pipelines build and test each context independently. A change in `identity/` does not trigger a rebuild of `forum/`.
- The root `compose.yaml` orchestrates all contexts for local development.

### Multi-repo (Large teams, many contexts)

Each context is its own repository. Use when teams need fully independent release cycles.

Rules:
- Event contracts are published as versioned packages to a shared registry.
- Compose files reference pre-built images from a container registry instead of build contexts.

---

## Anti-Patterns

### ❌ Shared persistence context across contexts
Two apps using the same persistence context with tables from both schemas. This couples migration ordering, deployment, and domain models. Each context gets its own persistence context.

### ❌ Cross-schema referential constraints
A foreign key from one context's schema to another context's schema. This prevents independent migration and creates a runtime dependency on another context's schema. Reference by UUID, verify at the application layer.

### ❌ God context
One context that owns "Users", "Orders", "Products", "Billing", and "Notifications". If a context has more than ~5 aggregates or serves more than one business capability, it's too large. Split by volatility.

### ❌ Synchronous chain for reads
Forum calls Identity API on every page load to get usernames. Use a local projection instead — subscribe to events, maintain a `forum.users` table.

### ❌ Shared code library between contexts
A `Common` or `Shared` project referenced by multiple contexts. Changes to the shared library force coordinated deployments across all consumers. Duplicate the code; it's cheaper than the coupling.

---

## Context Map Template

Use this table to document your system's context map. One row per integration.

| Upstream | Downstream | Relationship | Integration | Event / API |
|---|---|---|---|---|
| Identity | Forum | Conformist | Async event | `UserRegistered`, `UserProfileUpdated`, `UserDeleted` |
| Identity | Bills | Conformist | Async event | `UserRegistered`, `UserDeleted` |
| Identity | All | Published Language | Auth token | Token payload: user ID, email, roles |
| Forum | Audit | Upstream/Downstream | Async event | `PostCreated`, `PostDeleted` |

### Handling Upstream Entity Deletion

When an upstream context publishes a deletion event (e.g., `UserDeleted`), downstream contexts must handle cleanup in their own schema:

- **Soft-delete the local projection** — set `deleted_at` on the downstream's local copy. Do not hard-delete; posts and threads still reference the author ID.
- **Anonymize display data** — replace the display name with a placeholder (e.g., "Deleted User") and clear the avatar URL.
- **Do not cascade-delete domain entities** — a deleted user does not mean their forum posts disappear. The forum context decides its own retention policy.
- The cleanup consumer is idempotent — processing the same `UserDeleted` event twice produces the same result.
