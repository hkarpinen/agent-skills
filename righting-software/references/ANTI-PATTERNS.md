# Anti-Patterns and Fixes

## 1. Functional Decomposition

Services named after entities or CRUD operations (`OrderService`, `UserService`). Logic scattered across service classes. Domain objects are bags of data with no behavior.

**Fix**: Identify the volatility axes inside each monolithic service and extract each into a correctly named, correctly layered component.

```
OrderService  (❌)
  ↓ decompose by volatility
OrderWorkflowManager    (Application)    ← orchestration volatility
PricingEngine           (Domain)         ← pricing rule volatility
FraudDetectionEngine    (Domain)         ← fraud policy volatility
OrderRepository         (Infrastructure) ← persistence volatility
InventoryGateway        (Infrastructure) ← inventory system volatility
```

## 2. Anemic Domain Model

Domain objects with only data and no behavior. All business logic in service classes. No enforcement of invariants.

**Fix**: Move behavior into the domain model. The aggregate root controls all state transitions and enforces all invariants.

## 3. Business Rules in Managers

A Manager contains conditions that encode business policy.

**Fix**: Extract every business rule condition into a named Engine. The Manager calls the Engine and acts on the outcome — it does not decide the outcome itself.

## 4. I/O in Engines

An Engine reads from or writes to a database, calls an external service, or reads a file.

**Fix**: Move all I/O into Resource Access. The Engine receives the data it needs as input — the Manager retrieved it from Infrastructure and passed it in.

## 5. Engine-to-Engine Calls

One Engine directly calls another to complete its work.

**Fix**: Cross-Engine coordination belongs in a Manager. Engines remain independent.

## 6. God Manager

A single Manager handles dozens of unrelated use cases and grows without bound.

**Fix**: Decompose into multiple Managers by use case cluster.

## 7. Leaking Infrastructure

Domain objects, Engines, or Managers reference storage sessions, HTTP clients, message brokers, or framework-specific types directly.

**Fix**: All infrastructure references belong exclusively in the Infrastructure layer, behind contracts.

## 8. Premature Distribution

Every entity or bounded context immediately deployed as a separate service without volatility analysis justifying the distribution boundary.

**Fix**: Design the correct logical decomposition first. Then decide which logical services warrant separate deployment based on operational volatility — independent scaling, deployment cadence, or team ownership. Never let deployment topology drive design.

## 9. Organizing by Entity Instead of Volatility

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

- Always test against contracts, never implementations directly
- Never substitute the domain model with a test double — test it directly
- Infrastructure tests use real infrastructure — simulated storage does not behave identically
