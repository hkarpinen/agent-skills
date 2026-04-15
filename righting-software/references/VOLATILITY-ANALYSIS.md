# Volatility Analysis

## Volatility Questions

### Per Use Case
1. What business rule governs this use case today — and what is likely to change it?
2. Where does the data come from, and could that source change independently?
3. What external systems are involved, and how stable are their contracts?
4. Are there regulatory or policy requirements that could shift?
5. Are there multiple variants of this behavior — by tenant, region, product tier?

### Across Use Cases
6. What is common to all use cases — and what differs?
7. Which volatility axes appear repeatedly? These are candidates for shared Engines or shared Infrastructure components.

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
