---
name: ddd-idesign-bridge
description: Bridge between Domain-Driven Design tactical patterns and Juval Löwy's IDesign Method. Use when implementing the Domain Layer of an IDesign architecture using DDD patterns (Entities, Aggregates, Value Objects, Domain Events), or when applying IDesign's volatility-based decomposition to a DDD-modeled domain. Shows how DDD patterns map to IDesign layers.
---

## Integration Overview

**IDesign Method** provides volatility-based service decomposition and layer discipline.
**DDD Tactical Patterns** provide rich domain modeling within the Domain Layer.

Together: IDesign defines the architecture boundaries, DDD implements the domain within those boundaries.

---

## Layer Mapping

### Application Layer (IDesign Managers) → DDD Application Services

IDesign Managers orchestrate workflows and coordinate Domain Layer operations.

```csharp
// Application Layer — Manager orchestrates use case
public class OrderWorkflowManager : IOrderWorkflowManager
{
    private readonly IOrderRepository _orderRepo;
    private readonly IInventoryRepository _inventoryRepo;
    private readonly IDomainEventDispatcher _events;

    public async Task<OrderId> PlaceOrderAsync(PlaceOrderCommand cmd)
    {
        // 1. Load aggregates from repositories
        var customer = await _customerRepo.GetAsync(cmd.CustomerId);
        var product = await _inventoryRepo.GetProductAsync(cmd.ProductId);

        // 2. Execute domain logic (DDD aggregate methods)
        var order = Order.Create(customer.Id, cmd.Items);
        product.ReserveStock(cmd.Quantity);

        // 3. Persist aggregates
        await _orderRepo.SaveAsync(order);
        await _inventoryRepo.SaveAsync(product);

        // 4. Dispatch domain events
        foreach (var evt in order.DomainEvents)
            await _events.DispatchAsync(evt);
        
        order.ClearEvents();
        
        return order.Id;
    }
}
```

**Manager responsibilities**:
- Workflow orchestration (sequencing operations across aggregates)
- Transaction boundaries
- Event dispatching
- Error handling and compensation

**Manager does NOT**:
- Contain business rules (those belong in aggregates)
- Modify aggregate state directly (only through aggregate methods)

---

### Domain Layer → DDD Aggregates, Entities, Value Objects, Domain Services

IDesign's Domain Layer is where DDD patterns live.

#### Engines (Stateless Domain Services)

Engines encapsulate business rules that don't naturally belong to a single aggregate.

```csharp
// Domain Layer — Engine (DDD Domain Service)
public class PricingEngine : IPricingEngine
{
    public Money CalculateOrderTotal(IEnumerable<OrderLine> lines, Customer customer)
    {
        var subtotal = lines.Sum(line => line.UnitPrice.Multiply(line.Quantity));
        var discount = customer.LoyaltyTier.GetDiscountRate();
        return subtotal.Multiply(1 - discount);
    }
}
```

Use Engines (Domain Services) when:
- Logic spans multiple aggregates
- Logic doesn't naturally belong to any aggregate
- Logic requires external context (e.g., current date, pricing rules)

#### Aggregates (DDD Pattern)

Aggregates enforce invariants and protect consistency boundaries.

```csharp
// Domain Layer — Aggregate Root
public class Order
{
    private readonly List<OrderLine> _lines = new();
    private readonly List<IDomainEvent> _events = new();

    public OrderId Id { get; }
    public CustomerId CustomerId { get; }
    public OrderStatus Status { get; private set; }
    public IReadOnlyList<IDomainEvent> DomainEvents => _events.AsReadOnly();

    private Order(OrderId id, CustomerId customerId)
    {
        Id = id;
        CustomerId = customerId;
        Status = OrderStatus.Draft;
    }

    // Factory method enforces invariants
    public static Order Create(CustomerId customerId, IEnumerable<OrderLine> lines)
    {
        var order = new Order(OrderId.New(), customerId);
        
        if (!lines.Any())
            throw new DomainException("Order must have at least one line.");
        
        foreach (var line in lines)
            order._lines.Add(line);
        
        order._events.Add(new OrderCreated(order.Id, customerId));
        return order;
    }

    // Domain logic enforces state transitions
    public void Confirm()
    {
        if (Status != OrderStatus.Pending)
            throw new DomainException("Only pending orders can be confirmed.");
        
        Status = OrderStatus.Confirmed;
        _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
    }

    public void ClearEvents() => _events.Clear();
}
```

#### Value Objects (DDD Pattern)

Value Objects encapsulate concepts without identity.

```csharp
// Domain Layer — Value Object
public record Money(decimal Amount, Currency Currency)
{
    public Money Add(Money other)
    {
        if (other.Currency != Currency)
            throw new DomainException("Cannot add money with different currencies.");
        
        return this with { Amount = Amount + other.Amount };
    }

    public Money Multiply(decimal factor) => this with { Amount = Amount * factor };
}

public record Address(string Street, string City, string PostalCode, string Country);
```

---

### Infrastructure Layer (Resource Access) → DDD Repositories

IDesign Resource Access components implement DDD Repository interfaces.

```csharp
// Domain Layer — Repository interface (DDD pattern)
public interface IOrderRepository
{
    Task<Order?> GetAsync(OrderId id, CancellationToken ct = default);
    Task SaveAsync(Order order, CancellationToken ct = default);
}

// Infrastructure Layer — Repository implementation (IDesign Resource Access)
internal sealed class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;

    public async Task<Order?> GetAsync(OrderId id, CancellationToken ct = default)
    {
        // Load full aggregate (Order + OrderLines)
        var entity = await _db.Orders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id.Value, ct);
        
        return entity?.ToDomainModel();
    }

    public async Task SaveAsync(Order order, CancellationToken ct = default)
    {
        _db.Orders.Update(order.ToPersistenceModel());
        await _db.SaveChangesAsync(ct);
    }
}
```

**Repository pattern**:
- Interface in Domain Layer (part of domain contract)
- Implementation in Infrastructure Layer (IDesign Resource Access)
- One repository per aggregate root (not per entity)

---

## Volatility Analysis for DDD Aggregates

Use IDesign's volatility analysis to size aggregates correctly.

### High Volatility → Separate Aggregates

If two entities change at different rates or for different reasons, make them separate aggregates.

```csharp
// ❌ Wrong — Customer and Order have different volatility
Customer (aggregate root)
  ├── Orders (changes frequently)
  └── Profile (changes rarely)

// ✅ Correct — Separate aggregates by volatility
Customer (aggregate root)
  └── Profile

Order (aggregate root)
  └── CustomerId (reference)
```

### Shared Invariant → Same Aggregate

If two entities must be consistent transactionally, they belong to the same aggregate.

```csharp
// ✅ Correct — Order and OrderLines must be consistent
Order (aggregate root)
  └── OrderLines (same transaction, same volatility)
```

---

## Domain Events → IDesign Event Flow

DDD Domain Events flow through IDesign layers.

```csharp
// Domain Layer — Domain Event
public record OrderConfirmed(OrderId OrderId, DateTime ConfirmedAt) : IDomainEvent;

// Domain Layer — Aggregate raises event
public void Confirm()
{
    Status = OrderStatus.Confirmed;
    _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
}

// Application Layer — Manager dispatches events
public async Task ConfirmOrderAsync(OrderId orderId)
{
    var order = await _orderRepo.GetAsync(orderId);
    order.Confirm();
    await _orderRepo.SaveAsync(order);
    
    // Dispatch after successful persistence
    foreach (var evt in order.DomainEvents)
        await _eventDispatcher.DispatchAsync(evt);
    
    order.ClearEvents();
}

// Infrastructure Layer — Event dispatcher implementation
internal sealed class DomainEventDispatcher : IDomainEventDispatcher
{
    private readonly IMessageBus _bus;

    public async Task DispatchAsync(IDomainEvent evt)
    {
        await _bus.PublishAsync(evt);
    }
}
```

**Event flow**:
1. Aggregate raises event (Domain Layer)
2. Manager collects events after persistence (Application Layer)
3. Event dispatcher publishes to infrastructure (Infrastructure Layer)

---

## Call Direction Rules

```
Client Layer
  ↓ calls
Application Layer (Managers)
  ↓ calls
Domain Layer (Aggregates, Engines, Value Objects)
  ↓ references (interfaces only)
Infrastructure Layer (Repositories, Event Dispatchers)
```

**Critical**: Domain Layer never calls Infrastructure directly. It defines repository interfaces, and Infrastructure implements them.

---

## Example: Complete Flow

```csharp
// 1. Client Layer — API Controller
[HttpPost("orders/{id}/confirm")]
public async Task<IActionResult> ConfirmOrder(Guid id)
{
    await _orderManager.ConfirmOrderAsync(new OrderId(id));
    return Ok();
}

// 2. Application Layer — Manager
public async Task ConfirmOrderAsync(OrderId orderId)
{
    var order = await _orderRepo.GetAsync(orderId);  // Infrastructure call
    
    order.Confirm();  // Domain logic (aggregate method)
    
    await _orderRepo.SaveAsync(order);  // Infrastructure call
    
    foreach (var evt in order.DomainEvents)
        await _events.DispatchAsync(evt);  // Infrastructure call
    
    order.ClearEvents();
}

// 3. Domain Layer — Aggregate
public void Confirm()
{
    if (Status != OrderStatus.Pending)
        throw new DomainException("Only pending orders can be confirmed.");
    
    Status = OrderStatus.Confirmed;
    _events.Add(new OrderConfirmed(Id, DateTime.UtcNow));
}

// 4. Infrastructure Layer — Repository
public async Task SaveAsync(Order order, CancellationToken ct = default)
{
    _db.Orders.Update(order.ToPersistenceModel());
    await _db.SaveChangesAsync(ct);
}
```

---

**Required Skills**:
- [ddd-tactical-patterns](../ddd-tactical-patterns/SKILL.md) — Entities, Aggregates, Value Objects, Domain Events, Repositories
- [righting-software](../righting-software/SKILL.md) — Volatility analysis, layer model, call direction rules

See [references/AGGREGATE-SIZING.md](references/AGGREGATE-SIZING.md) for using volatility analysis to size aggregates.
