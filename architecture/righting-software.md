# righting-software

> Apply Juval Löwy's IDesign Method and volatility-based architecture from *Righting Software* (Addison-Wesley, 2019).

**When to use this skill**: designing systems, decomposing services, naming components,
reviewing or critiquing architecture, writing contracts, discussing domain models,
planning project structure, refactoring existing services, or any time entity-named
services appear (e.g. `UserService`, `OrderService`). Apply regardless of language,
platform, or technology stack.

---

## Core Principle

> **Decompose by what changes (volatility), not by what the system does (functionality).**

Every design decision must be justifiable by a specific axis of anticipated change.
If you cannot name the volatility being encapsulated, the design is suspect.

---

## The Design Process

Follow this sequence. Do not skip or reorder phases.

### Phase 1 — Identify Use Cases
- Enumerate all system behaviors as verb-noun pairs: "Place Order", "Approve Loan", "Cancel Subscription".
- Keep the list flat. Do not group by actor, role, or subsystem yet.

### Phase 2 — Identify Volatility
For each use case ask: what is most likely to change? Least likely?

Common volatility axes:
- Business rules and algorithms (pricing logic, approval workflows, tax calculations)
- Data formats and schemas (message shapes, API contracts)
- Technology and infrastructure (storage engine, messaging system, UI framework)
- Third-party integrations (payment providers, identity systems, external APIs)
- Regulatory and policy requirements
- Security mechanisms
- Behavioral variations (per-tenant, per-region, per-product-tier customizations)

### Phase 3 — Name Candidates for Encapsulation
Each identified axis of volatility becomes a candidate service, named after what it
encapsulates — not after the entity it operates on.

| ✅ Volatility-named | ❌ Functionality-named |
|---|---|
| `PricingEngine` | `OrderService` |
| `OrderRepository` | `ProductManager` |
| `FraudDetectionEngine` | `UserHandler` |
| `NotificationGateway` | `PaymentService` |

When you see an entity-named service, stop and propose volatility decomposition before proceeding.

### Phase 4 — Assign to Layers
See Layer Model section below.

### Phase 5 — Contracts First
Define the interface for every service before any implementation.
Callers depend on contracts, never on implementations.

---

## Layer Model

The IDesign method uses the four-layer DDD architecture. Löwy's contribution is the
precise placement of services within those layers and the volatility-based rules
governing what belongs where.

```
┌─────────────────────────────────────────────┐
│               CLIENT LAYER                  │
│  The entry point. Hosts, UIs, consumers.    │
├─────────────────────────────────────────────┤
│            APPLICATION LAYER                │
│  Managers. Use case orchestration.          │
├─────────────────────────────────────────────┤
│              DOMAIN LAYER                   │
│  Engines. Entities. Value objects.          │
│  Aggregates. Domain events.                 │
├─────────────────────────────────────────────┤
│           INFRASTRUCTURE LAYER              │
│  Resource Access. All I/O.                  │
└─────────────────────────────────────────────┘
         Cross-cutting (Utilities)
         spans all layers
```

Calls flow downward only. No layer may call upward.
No lateral calls between services within the same layer.

### Call Direction Rules

```
Client          → Application
Client          → (never Domain or Infrastructure directly)

Application     → Domain
Application     → Infrastructure
Application     → Cross-cutting

Domain          → Cross-cutting
Domain          → (never Application or Infrastructure)

Infrastructure  → Cross-cutting
Infrastructure  → (never Application or Domain logic)

Cross-cutting   → (never any domain layer)
```

Any call that violates these directions is an architectural defect.

### Client Layer

The entry point to the system — a web API, console app, desktop UI, worker, or any consumer.

- Calls only into the Application layer (Managers).
- Contains zero business logic and zero business rules.
- Translates between external representations and internal contracts.
- Is always swappable — changing the host must not require changes to any other layer.
- Is the composition root — the only place where contracts are bound to implementations.
- Nothing depends on the Client layer.

### Application Layer — Managers

Managers orchestrate use case workflows. They coordinate Domain and Infrastructure to
fulfill a use case or cluster of related use cases.

- One Manager per use case cluster — never one per entity.
- Contains workflow logic: sequencing, branching on outcomes, compensation on failure.
- Contains zero business rule logic. A condition encoding business policy belongs in an Engine.
- Managers never call other Managers.
- Managers are the sole entry point from the Client layer.

Examples: `OrderWorkflowManager`, `CustomerOnboardingManager`, `ClaimsProcessingManager`.

### Domain Layer — Engines, Entities, Value Objects, Aggregates

**Engines** encapsulate business rules and algorithms. Each Engine encapsulates exactly
one axis of business rule volatility.

- Stateless. No mutable state between calls.
- Independently swappable without changing Managers or other Engines.
- Never call other Engines directly — cross-Engine coordination belongs in a Manager.
- Never perform I/O of any kind — that belongs in Infrastructure.

Examples: `PricingEngine`, `FraudDetectionEngine`, `TaxEngine`, `EligibilityEngine`.

**Entities** have persistent identity that survives state changes. State changes only
through explicit methods. Every method enforces invariants before applying changes.
Entities raise domain events at the moment of meaningful state transitions.

**Value objects** have no identity. Defined entirely by attribute values. Always immutable
— operations return new instances rather than mutating in place. Equality by value.

**Aggregates** are clusters of entities and value objects protecting a single consistency
invariant. The aggregate root is the only entry point for modifications. Other parts of
the system reference aggregates by identity only — never by object reference. Load the
whole aggregate or none of it.

**Domain events** are immutable facts about meaningful state transitions. Named in past
tense. Raised by aggregate roots, never by Managers or external callers. Dispatched by
the Manager after the state has been durably persisted — never before.

### Infrastructure Layer — Resource Access

Resource Access components encapsulate all I/O: persistence, external services, messaging, files.

- Presents a domain-oriented interface; hides all technology details completely.
- Named as repositories, stores, or gateways.
- Contains zero business logic. Mapping data for storage is permitted; deriving business
  meaning is not.
- Independently swappable — changing the underlying technology must not require changes
  to any other layer.

Examples: `OrderRepository`, `CustomerStore`, `PaymentGateway`, `NotificationGateway`.

### Cross-cutting — Utilities

Shared concerns with no domain knowledge: logging, configuration, error handling,
date/time abstractions, serialization helpers.

- May be called by any layer.
- Must not reference domain concepts, aggregates, or business rules.
- Must not call into Application, Domain, or Infrastructure.

### The Contract Rule

Every service at every layer exposes only a contract — an interface describing what it
does without revealing how. Callers always depend on the contract, never the implementation.
This is what makes each layer independently swappable, testable, and genuinely encapsulated.

---

## Instant Design Checklist

- [ ] Each service encapsulates exactly one axis of volatility
- [ ] Service names reflect volatility, not entities or CRUD operations
- [ ] All calls flow in the correct direction through the layer model
- [ ] Contracts defined before implementations
- [ ] No Manager contains business rule logic — that belongs in an Engine
- [ ] No Engine calls another Engine directly
- [ ] No Engine performs I/O — that belongs in Infrastructure
- [ ] No Resource Access component contains business logic
- [ ] Implementations are hidden behind contracts; only contracts are visible to callers

---

## When Reviewing a Design

1. Check every service name — flag any that are entity-named.
2. Check every call direction — flag upward or lateral calls between services in the same layer.
3. Check every Manager for business rule logic — it belongs in an Engine.
4. Check every Engine for I/O — it belongs in Infrastructure.
5. Check every Resource Access component for business logic — it belongs in an Engine.
6. Ask: can you name the volatility axis each service encapsulates?

---

## Volatility Analysis Questions

### Per Use Case
1. What business rule governs this use case today — and what is likely to change it?
2. Where does the data come from, and could that source change independently?
3. What external systems are involved, and how stable are their contracts?
4. Are there regulatory or policy requirements that could shift?
5. Are there multiple variants of this behavior — by tenant, region, product tier?

### Across Use Cases
6. What is common to all use cases — and what differs?
7. Which volatility axes appear repeatedly? These are candidates for shared Engines or
   shared Infrastructure components.

---

## Contract-First Design Steps

When designing any new service:

1. **Name the volatility axis** being encapsulated. If you cannot name it, stop.
2. **Assign the layer**: Application (Manager), Domain (Engine or model), Infrastructure (Resource Access).
3. **Define the contract** with operations, inputs, outputs, and postconditions.
4. **Express inputs and outputs** in domain terms, not primitives where meaning matters.
5. **State at least one invariant** the service must uphold.
6. **Sketch the implementation structure** — collaborators and flow — without writing logic.
7. **Verify the dependency direction** — every dependency must point downward.

---

## Anti-Patterns

### 1. Functional Decomposition
Services named after entities or CRUD operations (`OrderService`, `UserService`).
Logic scattered across service classes. Domain objects are bags of data with no behavior.

**Fix**: Identify the volatility axes inside each monolithic service and extract each into
a correctly named, correctly layered component.

```
OrderService  (❌)
  ↓ decompose by volatility
OrderWorkflowManager    (Application)    ← orchestration volatility
PricingEngine           (Domain)         ← pricing rule volatility
FraudDetectionEngine    (Domain)         ← fraud policy volatility
OrderRepository         (Infrastructure) ← persistence volatility
InventoryGateway        (Infrastructure) ← inventory system volatility
```

### 2. Anemic Domain Model
Domain objects with only data and no behavior. All business logic in service classes.
No enforcement of invariants.

**Fix**: Move behavior into the domain model. The aggregate root controls all state
transitions and enforces all invariants.

### 3. Business Rules in Managers
A Manager contains conditions that encode business policy.

**Fix**: Extract every business rule condition into a named Engine. The Manager calls
the Engine and acts on the outcome — it does not decide the outcome itself.

### 4. I/O in Engines
An Engine reads from or writes to a database, calls an external service, or reads a file.

**Fix**: Move all I/O into Resource Access. The Engine receives the data it needs as
input — the Manager retrieved it from Infrastructure and passed it in.

### 5. Engine-to-Engine Calls
One Engine directly calls another to complete its work.

**Fix**: Cross-Engine coordination belongs in a Manager. Engines remain independent.

### 6. God Manager
A single Manager handles dozens of unrelated use cases and grows without bound.

**Fix**: Decompose into multiple Managers by use case cluster.

### 7. Leaking Infrastructure
Domain objects, Engines, or Managers reference storage sessions, HTTP clients,
message brokers, or framework-specific types directly.

**Fix**: All infrastructure references belong exclusively in the Infrastructure layer,
behind contracts.

### 8. Premature Distribution
Every entity or bounded context immediately deployed as a separate service without
volatility analysis justifying the distribution boundary.

**Fix**: Design the correct logical decomposition first. Then decide which logical
services warrant separate deployment based on operational volatility — independent
scaling, deployment cadence, or team ownership. Never let deployment topology drive design.

### 9. Organizing by Entity Instead of Volatility
Codebase organized into folders named after entities: `Orders/`, `Customers/`, `Products/`.

**Fix**: Organize by layer, then by volatility axis within each layer:
- Application: `OrderWorkflowManager/`, `CustomerOnboardingManager/`
- Domain — Engines: `PricingEngine/`, `FraudDetectionEngine/`
- Domain — Model: `Order/`, `Customer/`
- Infrastructure: `OrderRepository/`, `CustomerStore/`

---

## Testing Strategy

| Layer | Test approach | What to verify |
|---|---|---|
| Domain — model | Isolated unit tests | Aggregate invariants, state transitions, domain event emission |
| Domain — Engines | Isolated unit tests | Business rule correctness, all decision branches |
| Application — Managers | Tests with Infrastructure contracted out | Workflow sequencing, compensation paths |
| Infrastructure | Tests against real infrastructure | Query correctness, data mapping accuracy |
| Client | End-to-end or acceptance tests | Use case satisfaction from the consumer's perspective |

- Always test against contracts, never implementations directly.
- Never substitute the domain model with a test double — test it directly.
- Infrastructure tests use real infrastructure — simulated storage does not behave identically.

---

## Naming Conventions

| Layer | Suffix | Example |
|---|---|---|
| Application | `...Manager` | `OrderWorkflowManager` |
| Domain — Engines | `...Engine` | `PricingEngine`, `FraudDetectionEngine` |
| Infrastructure | `...Repository`, `...Gateway`, `...Store` | `OrderRepository`, `PaymentGateway` |

Contracts are named after the service they describe. The implementation name is an
internal detail hidden from callers.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Volatility** | An axis of anticipated change that must be encapsulated behind a contract |
| **Manager** | Application layer service orchestrating a use case workflow |
| **Engine** | Domain layer service encapsulating one business rule or algorithm axis |
| **Resource Access** | Infrastructure layer service encapsulating all I/O for one concern |
| **Contract** | An interface defining what a service does; the only thing callers depend on |
| **Decomposition** | Dividing a system — always by volatility, never by functionality |
| **Functional decomposition** | Anti-pattern: dividing by what the system does today |
| **Aggregate** | A cluster of domain objects protecting a single consistency invariant |
| **Domain event** | An immutable fact about a meaningful state transition in the domain |
| **Composition root** | The Client layer — the only place contracts are bound to implementations |
