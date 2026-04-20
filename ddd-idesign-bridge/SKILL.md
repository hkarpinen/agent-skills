---
name: ddd-idesign-bridge
description: Bridge between Domain-Driven Design tactical patterns and Juval Löwy's IDesign Method. Use when implementing the Domain Layer of an IDesign architecture using DDD patterns (Entities, Aggregates, Value Objects, Domain Events), or when applying IDesign's volatility-based decomposition to a DDD-modeled domain. Shows how DDD patterns map to IDesign layers. Does NOT re-teach DDD patterns or IDesign conventions.
---

## Scope

This skill owns the **mapping between DDD and IDesign**. It specifies:

- Terminology reconciliation (which IDesign term equals which DDD term)
- Where each DDD pattern physically lives in the IDesign layer model
- How IDesign's volatility analysis applies to DDD aggregate sizing
- How DDD domain events flow through IDesign layers

---

## Terminology Reconciliation

IDesign and DDD use different words for overlapping concepts. Pick one vocabulary per
codebase and stick to it. Use **IDesign** names in type/folder names
(because the layering and call-direction rules are IDesign's) and **DDD** names
when discussing modelling patterns.

| Concept | IDesign term (used in code) | DDD term (used in discussion) |
|---|---|---|
| Stateless business-rule component | **Engine** (`PricingEngine`) | Domain Service |
| Use-case orchestrator | **Manager** (`OrderWorkflowManager`) | Application Service |
| Persistence abstraction | **Repository** (`OrderRepository`) | Repository |
| External-system adapter | **Gateway** (`PaymentGateway`) | Anti-Corruption Layer / Gateway |
| Entry-point project | **Client** | (no canonical DDD term) |

When IDesign says "Engine" and DDD says "Domain
Service", they are describing the same component. Class names end in `Engine`;
conversational and documentation language may use either term.

---

## Layer Mapping

Where each DDD pattern lives in the IDesign layer model:

| DDD Pattern | IDesign Layer | IDesign Role |
|---|---|---|
| Aggregate, Entity, Value Object | Domain | Part of the domain model — alongside Engines |
| Domain Service | Domain | **Engine** — stateless, `internal sealed` |
| Domain Event (definition) | Domain | Record type in Domain; raised by aggregates |
| Repository interface | Domain | Public contract consumed by Managers |
| Repository implementation | Infrastructure | **Resource Access** — `internal sealed` |
| Application Service | Application | **Manager** — orchestrates aggregates + events |
| Domain Event dispatching | Application → Infrastructure | Manager collects events; dispatcher implementation is Resource Access |

Rules:
- Managers call aggregate methods — they never mutate aggregate state directly.
- Managers call Engines when business logic spans multiple aggregates.
- Engines never call Repositories. If an Engine needs data, the Manager loads it and passes it in.

---

## Volatility Analysis for DDD Aggregates

Use IDesign's volatility analysis to size aggregates. DDD says "aggregate boundaries protect consistency invariants" — volatility analysis provides the missing sizing heuristic.

**Rule**: If two entities have different volatility profiles (rate of change, reasons for change, change stakeholders), make them separate aggregates.

```
// ❌ Wrong — Customer and Order have different volatility
Customer (aggregate root)
  ├── Orders (changes frequently, driven by customers + warehouse)
  └── Profile (changes rarely, driven by customer service)

// ✅ Correct — Separate aggregates by volatility
Customer (aggregate root)
  └── Profile

Order (aggregate root)
  └── CustomerId (reference by ID only)
```

**Exception**: If two entities share a transactional invariant (e.g. order total must equal sum of lines), they belong in the same aggregate regardless of volatility.

See [references/AGGREGATE-SIZING.md](references/AGGREGATE-SIZING.md) for detailed examples.

---

## Domain Event Flow Through IDesign Layers

DDD defines *what* domain events are; this bridge defines *how they flow* through IDesign layers.

```
1. Domain Layer    — Aggregate raises event (adds to internal list)
2. Application Layer — Manager persists the aggregate, THEN collects and dispatches events
3. Infrastructure Layer — Event dispatcher implementation publishes to message bus
```

Rules:
- Events are dispatched **after** successful persistence — never before.
- The Manager owns the dispatch loop; the aggregate never dispatches its own events.
- `IDomainEventDispatcher` interface lives in Domain; implementation lives in Infrastructure.

```
// Application Layer — Manager dispatching pattern
ConfirmOrderAsync(orderId)
    order = orderRepo.Get(orderId)
    order.Confirm()                      // aggregate raises event internally
    orderRepo.Save(order)                // persist first

    for each event in order.DomainEvents // then dispatch
        eventDispatcher.Dispatch(event)

    order.ClearEvents()
```


