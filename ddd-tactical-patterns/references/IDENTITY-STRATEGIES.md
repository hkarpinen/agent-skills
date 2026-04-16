# Identity Generation Strategies

## UUID/GUID (Recommended)

Generate identity in the domain layer before persistence. No database round-trip required.

```
value OrderId(Value: uuid)
    static New() -> OrderId
        return OrderId(newUuid())

// Usage
order = Order.Create(OrderId.New(), customerId, lines)
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

```
value UserId(Email: string)
    constructor(email)
        Email = lowercase(email)
```

**Use sparingly**: Natural keys can change due to domain rules, complicating updates.

## Strongly-Typed IDs

Wrap primitive types to prevent ID mixing.

```
value OrderId(Value: uuid)
value CustomerId(Value: uuid)
value ProductId(Value: uuid)

// Compiler/type error — cannot pass CustomerId where OrderId expected
ProcessOrder(orderId: OrderId) -> void
ProcessOrder(customerId)  // ❌ Type error
```
