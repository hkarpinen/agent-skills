---
name: ddd-tactical-patterns
description: Domain-Driven Design tactical patterns — Entities, Value Objects, Aggregates, Domain Events, and Repositories. Use when modeling domain logic, designing aggregates, enforcing invariants, implementing entities and value objects, or structuring domain events. Patterns are language-agnostic; examples use pseudocode with C-family syntax. Apply the same rules in any object-oriented language.
---

## Entities

Entities have persistent identity that survives state changes. Identity is intrinsic, not derived from attributes.

**Rules**:
- Identity is immutable and established at creation
- State changes only through explicit methods that enforce invariants
- Equality by identity, not by attribute values
- Raise domain events at meaningful state transitions

```
class Order
    events: List<DomainEvent>

    Id: OrderId           // Identity — never changes
    CustomerId: CustomerId
    Status: OrderStatus
    DomainEvents: readonly list of events

    private constructor(id, customerId)
        Id = id
        CustomerId = customerId
        Status = Draft

    static Create(customerId, lines) -> Order
        order = new Order(OrderId.New(), customerId)
        for each line in lines
            order.AddLine(line)
        order.events.Add(OrderCreated(order.Id, customerId))
        return order

    Submit()
        if Status != Draft
            throw "Only draft orders can be submitted."
        Status = Pending
        events.Add(OrderSubmitted(Id, utcNow()))

    Confirm()
        if Status != Pending
            throw "Only pending orders can be confirmed."
        Status = Confirmed
        events.Add(OrderConfirmed(Id, utcNow()))

    ClearEvents()
        events.Clear()
```

---

## Value Objects

Value Objects have no identity. Defined entirely by their attribute values. Two value objects with identical attributes are interchangeable.

**Rules**:
- Immutable — operations return new instances
- Equality by value, not reference
- No identity property
- Can contain behavior operating on their values

```
value Money(Amount: decimal, Currency: Currency)
    Add(other: Money) -> Money
        if other.Currency != Currency
            throw "Cannot add money with different currencies."
        return Money(Amount + other.Amount, Currency)

    Multiply(factor: decimal) -> Money
        return Money(Amount * factor, Currency)

    static Zero(currency) -> Money
        return Money(0, currency)

value Address(Street, City, PostalCode, Country)
    IsInCountry(countryCode) -> bool
        return Country == countryCode (case-insensitive)
```

Use your language's value-equality mechanism (e.g. records, data classes, `__eq__` override).

---

## Aggregates

An Aggregate is a cluster of entities and value objects protecting a single consistency invariant. The Aggregate Root is the only entry point for modifications.

**Rules**:
- One consistency boundary = one aggregate
- External references hold only the aggregate root's ID — never object references
- Load the whole aggregate or none of it
- Persist the whole aggregate transactionally
- Only the aggregate root is a repository target

```
// Aggregate Root
class Order
    lines: List<OrderLine>
    Lines: readonly view of lines

    // Only the root can add lines — enforces "minimum one line" invariant
    AddLine(productId, quantity, unitPrice)
        if quantity <= 0
            throw "Quantity must be positive."
        lines.Add(OrderLine(productId, quantity, unitPrice))

    // Aggregate consistency: total is always sum of lines
    CalculateTotal() -> Money
        return lines
            .map(line -> line.UnitPrice.Multiply(line.Quantity))
            .reduce(Money.Zero(USD), (sum, price) -> sum.Add(price))

// Entity within aggregate — not directly accessible outside
class OrderLine (internal to Order)
    ProductId: ProductId
    Quantity: int
    UnitPrice: Money

    UpdateQuantity(newQuantity)
        if newQuantity <= 0
            throw "Quantity must be positive."
        Quantity = newQuantity
```

### Aggregate Sizing

**Too large**: Performance problems loading/saving, high contention on writes.
**Too small**: Invariants span multiple aggregates, causing consistency issues.

**Right size**: Contains exactly the objects needed to enforce one consistency rule.

---

## Domain Events

Domain Events are immutable facts about meaningful state transitions in the domain. Named in past tense.

**Rules**:
- Raised by the aggregate root, never by external callers
- Dispatched after state has been durably persisted — never before
- Carry only the data relevant to the event (IDs, timestamps, changed values)
- Never carry references to mutable objects

```
event OrderSubmitted(OrderId, SubmittedAt: datetime)
event OrderConfirmed(OrderId, ConfirmedAt: datetime)
event OrderShipped(OrderId, ShippingAddress: Address, ShippedAt: datetime)
event PaymentReceived(OrderId, Amount: Money, ReceivedAt: datetime)
```

**Raising Events**:
```
class Order
    events: List<DomainEvent>
    DomainEvents: readonly view of events

    Confirm()
        // State change first
        Status = Confirmed
        // Event records what happened
        events.Add(OrderConfirmed(Id, utcNow()))

    ClearEvents()
        events.Clear()
```

**Dispatching Events**: Events are dispatched in the application layer after the aggregate is durably persisted — never before. The architecture bridge specifies the dispatching pattern and layer flow.

---

## Repositories

Repositories provide the illusion of an in-memory collection of aggregate roots. They encapsulate all persistence concerns.

**Rules**:
- One repository per aggregate root — not per entity
- Return domain objects, not persistence objects
- Interface in the domain layer, implementation in infrastructure
- Methods use domain language: `Get`, `Save`, not `SelectById`, `Insert`

```
// Domain layer — interface only
interface OrderRepository
    GetAsync(id: OrderId) -> Order?
    GetByCustomerAsync(customerId: CustomerId) -> List<Order>
    SaveAsync(order: Order) -> void
    DeleteAsync(order: Order) -> void
```

The implementation lives in the infrastructure layer and depends on the persistence technology.

---

## Invariants

An invariant is a rule that must always be true. Aggregates exist to protect invariants.

**Examples**:
- An order must have at least one line
- A bank account balance cannot be negative
- A meeting cannot have overlapping time slots for the same room

**Enforcement**:
```
class Order
    lines: List<OrderLine>

    RemoveLine(line)
        if lines.Count == 1
            throw "Cannot remove the last line. Order must have at least one line."
        lines.Remove(line)
```

---

## Denormalized Read Models

Sometimes a query needs data that is expensive to compute from the canonical aggregates (e.g. a vote count, comment count, or hot-ranking score). Instead of computing on every read, maintain a **denormalized read model** — a pre-computed projection kept in sync with the source aggregates.

### Update Strategies

| Strategy | Consistency | When to use |
|---|---|---|
| **Synchronous in transaction** | Strong | The read model is in the same database and transaction as the write. Simple, no eventual consistency. |
| **Domain event → async projection** | Eventual | The read model is updated by a consumer listening to domain events. Decoupled, but the read model lags behind writes. |
| **Scheduled recalculation** | Periodic | A background job recalculates the read model on a schedule (e.g. hourly). For non-time-critical data. |

### Examples

```
// Thread aggregate stores canonical data
class Thread
    Id, Title, Body, AuthorId, CreatedAt

// Denormalized fields maintained alongside the aggregate
    Score: int           // sum of votes — updated when VoteCast event processed
    CommentCount: int    // count of comments — incremented when CommentAdded processed
    HotScore: float      // ranking score — recalculated after score or comment count changes
```

Rules:
- The denormalized field lives on the aggregate or a co-located read table — not in a separate bounded context.
- Document which events or operations trigger an update to each denormalized field.
- Accept eventual consistency for async projections. The UI can show slightly stale counts.
- For synchronous updates, update the read model in the same transaction as the write. If the write succeeds but the read model update fails, both roll back.
- Never use a denormalized field as a source of truth for business decisions. It is a performance optimization for reads only.

---

## Soft Delete as a Domain Pattern

Soft delete is not just a database column — it has domain semantics. An aggregate that supports soft delete transitions to a "deleted" state but remains in storage for audit, recovery, or referential integrity.

```
class Thread
    IsDeleted: bool
    DeletedAt: datetime?
    DeletedBy: UserId?

    Delete(deletedBy: UserId)
        if IsDeleted
            throw "Thread is already deleted."
        IsDeleted = true
        DeletedAt = utcNow()
        DeletedBy = deletedBy
        events.Add(ThreadDeleted(Id, deletedBy, DeletedAt))

    Restore(restoredBy: UserId)
        if not IsDeleted
            throw "Thread is not deleted."
        IsDeleted = false
        DeletedAt = null
        DeletedBy = null
        events.Add(ThreadRestored(Id, restoredBy, utcNow()))
```

Rules:
- Soft delete is a **state transition**, not a data access concern. Model it as a method on the aggregate root that raises a domain event.
- Track **who** deleted the entity (`DeletedBy`) — this distinguishes author self-deletion from moderator deletion.
- Repositories must **filter soft-deleted aggregates by default**. Provide an explicit `IncludeDeleted` option for admin/moderation queries.
- Cascading soft deletes (e.g. deleting a thread soft-deletes its comments) are orchestrated in the application layer, not by the database. Each aggregate manages its own `IsDeleted` flag.
- Periodically hard-delete ancient soft-deleted records via a scheduled job.

**Invariant = Aggregate Boundary**: If a rule must be enforced transactionally, all objects involved in that rule belong to the same aggregate.

---

See [references/IDENTITY-STRATEGIES.md](references/IDENTITY-STRATEGIES.md) for identity generation patterns, [references/AGGREGATE-DESIGN.md](references/AGGREGATE-DESIGN.md) for deeper guidance on sizing and designing aggregates, and [references/SCORING-ALGORITHMS.md](references/SCORING-ALGORITHMS.md) for ranking and scoring patterns (hot ranking, Wilson score).
