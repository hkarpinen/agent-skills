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

The implementation lives in the infrastructure layer and depends on the persistence technology. The DB bridge skill owns the implementation.

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

## Companion Skills

| When you need | Skill |
|---|---|
| Map these patterns to a specific architecture methodology | The architecture bridge (e.g. `ddd-idesign-bridge`) |
| Implement repositories with a specific ORM/database | The DB bridge (e.g. `dotnet-efcore-postgres`) |
| Bounded context boundaries for multi-app systems | `ddd-strategic-patterns` |

**Invariant = Aggregate Boundary**: If a rule must be enforced transactionally, all objects involved in that rule belong to the same aggregate.

---

See [references/IDENTITY-STRATEGIES.md](references/IDENTITY-STRATEGIES.md) for identity generation patterns and [references/AGGREGATE-DESIGN.md](references/AGGREGATE-DESIGN.md) for deeper guidance on sizing and designing aggregates.
