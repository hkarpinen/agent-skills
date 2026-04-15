# Aggregate Design Guidelines

## Sizing Principles

### Start Small
Begin with small aggregates and enlarge only when invariants demand it.

### One Consistency Rule = One Aggregate
If two objects must be consistent with each other transactionally, they belong to the same aggregate.

### Eventual Consistency Between Aggregates
If two objects can be eventually consistent (via domain events), they belong to different aggregates.

## Example: E-commerce Order

### ❌ Too Large
```csharp
// Everything in one aggregate
Order (root)
  ├── OrderLines
  ├── Customer  // ❌ Too large — customer is its own aggregate
  ├── Product   // ❌ Too large — product is its own aggregate
  ├── Payment   // ❌ May be separate aggregate
  └── Shipment  // ❌ May be separate aggregate
```

### ✅ Right Size
```csharp
// Order aggregate
Order (root)
  └── OrderLines  // Must be consistent with order

// Separate aggregates reference by ID only
Order.CustomerId → Customer aggregate
OrderLine.ProductId → Product aggregate
```

## Reference by ID, Not Object

```csharp
// ❌ Wrong — holding object reference
public class Order
{
    public Customer Customer { get; set; }  // ❌ Aggregate leak
}

// ✅ Correct — holding ID only
public class Order
{
    public CustomerId CustomerId { get; }  // ✅ Reference by ID
}
```

## Invariant Examples

### Must Be Transactional (Same Aggregate)
- Order total = sum of order lines → Order and OrderLines in same aggregate
- Meeting room not double-booked for same time slot → Meeting and TimeSlot in same aggregate

### Can Be Eventually Consistent (Different Aggregates)
- Customer credit limit vs. order amount → Customer and Order are separate aggregates; check at order placement
- Product inventory vs. order quantity → Product and Order are separate aggregates; reserve inventory asynchronously

## Loading and Saving

### Load Full Aggregate
```csharp
var order = await _db.Orders
    .Include(o => o.Lines)  // Load all parts
    .FirstOrDefaultAsync(o => o.Id == orderId);
```

### Save Full Aggregate
```csharp
_db.Orders.Update(order);  // Updates all parts transactionally
await _db.SaveChangesAsync();
```

## Large Collections Problem

If an aggregate root has thousands of child entities, loading the full aggregate becomes impractical.

**Solution**: Re-examine the aggregate boundary. Large collections often indicate the child should be a separate aggregate referenced by ID.

### ❌ Problem
```csharp
// Customer with 10,000 orders — loading all orders is impractical
Customer (root)
  └── Orders (10,000)  // ❌ Too large
```

### ✅ Solution
```csharp
// Customer and Order are separate aggregates
Customer (root)
  └── CustomerId

Order (root)
  └── CustomerId  // Reference to customer
```

Query orders by customer ID when needed, not by loading the customer aggregate.
