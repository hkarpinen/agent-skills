# Identity Generation Strategies

## UUID/GUID (Recommended)

Generate identity in the domain layer before persistence. No database round-trip required.

```csharp
public record OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
}

// Usage
var order = Order.Create(OrderId.New(), customerId, lines);
```

**Advantages**:
- Identity known before persistence
- No coupling to database
- Works in distributed systems
- Can create object graphs before saving

## Database-Generated Identity

The database generates the ID on insert. Domain object receives ID after persistence.

**Disadvantages**:
- Cannot reference the entity until after persistence
- Tight coupling to database
- Complicates domain events (no ID to include)

**Avoid unless required by legacy constraints.**

## Natural Keys

Identity derived from domain-meaningful attributes (e.g., ISBN for books, email for users).

```csharp
public record UserId(string Email)
{
    public UserId(string email) : this(email.ToLowerInvariant()) { }
}
```

**Use sparingly**: Natural keys can change due to domain rules, complicating updates.

## Strongly-Typed IDs

Wrap primitive types to prevent ID mixing.

```csharp
public record OrderId(Guid Value);
public record CustomerId(Guid Value);
public record ProductId(Guid Value);

// Compiler error — cannot pass CustomerId where OrderId expected
void ProcessOrder(OrderId orderId) { }
ProcessOrder(customerId);  // ❌ Compile error
```
