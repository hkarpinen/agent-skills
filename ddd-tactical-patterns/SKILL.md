---
name: ddd-tactical-patterns
description: Domain-Driven Design tactical patterns — Entities, Value Objects, Aggregates, Domain Events, and Repositories. Use when modeling domain logic, designing aggregates, enforcing invariants, implementing entities and value objects, or structuring domain events. Language and framework agnostic.
---

## Entities

Entities have persistent identity that survives state changes. Identity is intrinsic, not derived from attributes.

**Rules**:
- Identity is immutable and established at creation
- State changes only through explicit methods that enforce invariants
- Equality by identity, not by attribute values
- Raise domain events at meaningful state transitions

```csharp
public class Order
{
    private readonly List<IDomainEvent> _events = new();
    
    public OrderId Id { get; }  // Identity — never changes
    public CustomerId CustomerId { get; }
    public OrderStatus Status { get; private set; }
    public IReadOnlyList<IDomainEvent> DomainEvents => _events.AsReadOnly();

    private Order(OrderId id, CustomerId customerId)  // Private constructor
    {
        Id = id;
        CustomerId = customerId;
        Status = OrderStatus.Draft;
    }

    public static Order Create(CustomerId customerId, IEnumerable<OrderLine> lines)
    {
        var order = new Order(OrderId.New(), customerId);
        foreach (var line in lines)
            order.AddLine(line);
        order._events.Add(new OrderCreated(order.Id, customerId));
        return order;
    }

    public void Confirm()
    {
        if (Status != OrderStatus.Pending)
            throw new InvalidOperationException("Only pending orders can be confirmed.");
        
        Status = OrderStatus.Confirmed;
        _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
    }

    public void ClearEvents() => _events.Clear();
}
```

---

## Value Objects

Value Objects have no identity. Defined entirely by their attribute values. Two value objects with identical attributes are interchangeable.

**Rules**:
- Immutable — operations return new instances
- Equality by value, not reference
- No identity property
- Can contain behavior operating on their values

```csharp
public record Money(decimal Amount, Currency Currency)
{
    public Money Add(Money other)
    {
        if (other.Currency != Currency)
            throw new InvalidOperationException("Cannot add money with different currencies.");
        
        return this with { Amount = Amount + other.Amount };
    }

    public Money Multiply(decimal factor) => this with { Amount = Amount * factor };

    public static Money Zero(Currency currency) => new(0, currency);
}

public record Address(string Street, string City, string PostalCode, string Country)
{
    public bool IsInCountry(string countryCode) => Country.Equals(countryCode, StringComparison.OrdinalIgnoreCase);
}
```

Use `record` in C# for automatic value equality. In other languages, override equality methods.

---

## Aggregates

An Aggregate is a cluster of entities and value objects protecting a single consistency invariant. The Aggregate Root is the only entry point for modifications.

**Rules**:
- One consistency boundary = one aggregate
- External references hold only the aggregate root's ID — never object references
- Load the whole aggregate or none of it
- Persist the whole aggregate transactionally
- Only the aggregate root is a repository target

```csharp
// Aggregate Root
public class Order
{
    private readonly List<OrderLine> _lines = new();
    public IReadOnlyList<OrderLine> Lines => _lines.AsReadOnly();

    // Only the root can add lines — enforces "minimum one line" invariant
    public void AddLine(ProductId productId, int quantity, Money unitPrice)
    {
        if (quantity <= 0)
            throw new ArgumentException("Quantity must be positive.");
        
        _lines.Add(new OrderLine(productId, quantity, unitPrice));
    }

    // Aggregate consistency: total is always sum of lines
    public Money CalculateTotal() => _lines
        .Select(line => line.UnitPrice.Multiply(line.Quantity))
        .Aggregate(Money.Zero(Currency.USD), (sum, price) => sum.Add(price));
}

// Entity within aggregate — not directly accessible outside
public class OrderLine
{
    public ProductId ProductId { get; }
    public int Quantity { get; private set; }
    public Money UnitPrice { get; }

    internal OrderLine(ProductId productId, int quantity, Money unitPrice)
    {
        ProductId = productId;
        Quantity = quantity;
        UnitPrice = unitPrice;
    }

    // Only accessible through Order root
    internal void UpdateQuantity(int newQuantity)
    {
        if (newQuantity <= 0)
            throw new ArgumentException("Quantity must be positive.");
        Quantity = newQuantity;
    }
}
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

```csharp
public record OrderConfirmed(OrderId OrderId, DateTime ConfirmedAt) : IDomainEvent;

public record OrderShipped(OrderId OrderId, Address ShippingAddress, DateTime ShippedAt) : IDomainEvent;

public record PaymentReceived(OrderId OrderId, Money Amount, DateTime ReceivedAt) : IDomainEvent;
```

**Raising Events**:
```csharp
public class Order
{
    private readonly List<IDomainEvent> _events = new();
    public IReadOnlyList<IDomainEvent> DomainEvents => _events.AsReadOnly();

    public void Confirm()
    {
        // State change first
        Status = OrderStatus.Confirmed;
        
        // Event records what happened
        _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
    }

    public void ClearEvents() => _events.Clear();
}
```

**Dispatching Events** (happens in the application layer after persistence):
```csharp
// Application layer / Manager
public async Task ConfirmOrderAsync(OrderId orderId)
{
    var order = await _repository.GetAsync(orderId);
    order.Confirm();
    await _repository.SaveAsync(order);
    
    // Dispatch events after successful persistence
    foreach (var evt in order.DomainEvents)
        await _eventDispatcher.DispatchAsync(evt);
    
    order.ClearEvents();
}
```

---

## Repositories

Repositories provide the illusion of an in-memory collection of aggregate roots. They encapsulate all persistence concerns.

**Rules**:
- One repository per aggregate root — not per entity
- Return domain objects, not persistence objects
- Interface in the domain layer, implementation in infrastructure
- Methods use domain language: `GetAsync`, `SaveAsync`, not `SelectById`, `Insert`

```csharp
// Domain layer — interface
public interface IOrderRepository
{
    Task<Order?> GetAsync(OrderId id, CancellationToken ct = default);
    Task<IEnumerable<Order>> GetByCustomerAsync(CustomerId customerId, CancellationToken ct = default);
    Task SaveAsync(Order order, CancellationToken ct = default);
    Task DeleteAsync(Order order, CancellationToken ct = default);
}

// Infrastructure layer — implementation
internal sealed class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;

    public async Task<Order?> GetAsync(OrderId id, CancellationToken ct = default)
    {
        var entity = await _db.Orders
            .Include(o => o.Lines)  // Load full aggregate
            .FirstOrDefaultAsync(o => o.Id == id.Value, ct);
        
        return entity?.ToDomain();  // Map to domain model
    }

    public async Task SaveAsync(Order order, CancellationToken ct = default)
    {
        _db.Orders.Update(order.ToEntity());  // Map to persistence model
        await _db.SaveChangesAsync(ct);
    }
}
```

---

## Invariants

An invariant is a rule that must always be true. Aggregates exist to protect invariants.

**Examples**:
- An order must have at least one line
- A bank account balance cannot be negative
- A meeting cannot have overlapping time slots for the same room

**Enforcement**:
```csharp
public class Order
{
    private readonly List<OrderLine> _lines = new();

    public void RemoveLine(OrderLine line)
    {
        if (_lines.Count == 1)
            throw new InvalidOperationException("Cannot remove the last line. Order must have at least one line.");
        
        _lines.Remove(line);
    }
}
```

**Invariant = Aggregate Boundary**: If a rule must be enforced transactionally, all objects involved in that rule belong to the same aggregate.

---

See [references/IDENTITY-STRATEGIES.md](references/IDENTITY-STRATEGIES.md) for identity generation patterns and [references/AGGREGATE-DESIGN.md](references/AGGREGATE-DESIGN.md) for deeper guidance on sizing and designing aggregates.
