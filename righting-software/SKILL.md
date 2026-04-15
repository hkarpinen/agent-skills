---
name: righting-software
description: Apply Juval Löwy's IDesign Method and volatility-based architecture from Righting Software (Addison-Wesley, 2019). Use when designing systems, decomposing services, naming components, reviewing or critiquing architecture, writing contracts, discussing domain models, planning project structure, refactoring existing services, or any time entity-named services appear (e.g. UserService, OrderService). Apply regardless of language, platform, or technology stack.
---

## Core Principle

> **Decompose by what changes (volatility), not by what the system does (functionality).**

Every design decision must be justifiable by a specific axis of anticipated change.
If you cannot name the volatility being encapsulated, the design is suspect.

---

## The Design Process

Follow this sequence. Do not skip or reorder phases.

### Phase 1 — Identify Use Cases
Enumerate all system behaviors as verb-noun pairs: "Place Order", "Approve Loan", "Cancel Subscription".

### Phase 2 — Identify Volatility
For each use case ask: what is most likely to change? Least likely?

Common volatility axes:
- Business rules and algorithms
- Data formats and schemas
- Technology and infrastructure
- Third-party integrations
- Regulatory and policy requirements
- Security mechanisms
- Behavioral variations (per-tenant, per-region, per-product-tier)

### Phase 3 — Name Candidates for Encapsulation
Each identified axis of volatility becomes a candidate service, named after what it encapsulates — not after the entity it operates on.

| ✅ Volatility-named | ❌ Functionality-named |
|---|---|
| `PricingEngine` | `OrderService` |
| `OrderRepository` | `ProductManager` |
| `FraudDetectionEngine` | `UserHandler` |

When you see an entity-named service, stop and propose volatility decomposition before proceeding.

---

## Layer Model

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

**Call Direction Rules**:
```
Client       → Application
Application  → Domain, Infrastructure
Domain       → (nothing except Cross-cutting)
Infrastructure → (nothing except Cross-cutting)
```

Any call that violates these directions is an architectural defect.

---

## Layer Responsibilities

### Client Layer
Entry point (web API, console app, UI). Calls only Application layer. Contains zero business logic. Is the composition root where contracts bind to implementations.

### Application Layer — Managers
Orchestrate use case workflows. One Manager per use case cluster. Contains workflow logic (sequencing, branching, compensation). Contains zero business rules.

### Domain Layer
**Engines**: Stateless business rule encapsulation. One Engine per business rule volatility axis.

**Domain Model**: Business entities and rules. The specific implementation patterns (entities, aggregates, value objects) depend on your domain modeling approach.

### Infrastructure Layer — Resource Access
All I/O: persistence, external services, messaging. Presents domain-oriented interface, hides technology details.

### Cross-cutting — Utilities
Shared concerns with no domain knowledge: logging, configuration, error handling.

---

## The Contract Rule

Every service exposes only a contract (interface). Callers depend on contracts, never implementations. This makes each layer independently swappable and testable.

---

## Instant Design Checklist

- [ ] Each service encapsulates exactly one axis of volatility
- [ ] Service names reflect volatility, not entities or CRUD operations
- [ ] All calls flow in the correct direction through the layer model
- [ ] Contracts defined before implementations
- [ ] No Manager contains business rule logic
- [ ] No Engine calls another Engine directly
- [ ] No Engine performs I/O
- [ ] No Resource Access component contains business logic
- [ ] Implementations are hidden behind contracts

---

## When Reviewing a Design

1. Check every service name — flag any that are entity-named
2. Check every call direction — flag upward or lateral calls
3. Check every Manager for business rule logic
4. Check every Engine for I/O
5. Check every Resource Access component for business logic
6. Ask: can you name the volatility axis each service encapsulates?

---

## Naming Conventions

| Layer | Suffix | Example |
|---|---|---|
| Application | `...Manager` | `OrderWorkflowManager` |
| Domain — Engines | `...Engine` | `PricingEngine`, `FraudDetectionEngine` |
| Infrastructure | `...Repository`, `...Gateway`, `...Store` | `OrderRepository`, `PaymentGateway` |

---

See [references/ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) for detailed anti-patterns and fixes, and [references/VOLATILITY-ANALYSIS.md](references/VOLATILITY-ANALYSIS.md) for deeper guidance on identifying and decomposing by volatility.
