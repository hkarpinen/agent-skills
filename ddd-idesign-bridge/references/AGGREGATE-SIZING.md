# Aggregate Sizing with Volatility Analysis

## The Problem

DDD says "aggregate boundaries protect consistency invariants" but doesn't provide specific guidance on sizing.
IDesign's volatility analysis provides the missing heuristic.

---

## Volatility-Based Sizing Rule

**If two entities have different volatility profiles, make them separate aggregates.**

Volatility profile = combination of:
- Rate of change (how often does it change?)
- Reasons for change (what causes changes?)
- Change stakeholders (who requests changes?)

---

## Example 1: Customer and Orders

### Volatility Analysis

| Entity | Change Frequency | Change Reasons | Stakeholders |
|--------|------------------|----------------|--------------|
| Customer | Low (monthly) | Address updates, profile changes | Customer service, customers |
| Order | High (hourly) | New orders, status changes, cancellations | Customers, warehouse, shipping |

### Conclusion

Different volatility → Separate aggregates.

```
// ✅ Correct
Customer (aggregate root)
  └── Profile, Address

Order (aggregate root)
  └── CustomerId (reference)
  └── OrderLines
```

---

## Example 2: Order and OrderLines

### Volatility Analysis

| Entity | Change Frequency | Change Reasons | Stakeholders |
|--------|------------------|----------------|--------------|
| Order | Medium | Status changes, modifications | Customers, warehouse |
| OrderLine | Medium | Same as Order (lines change when order changes) | Same as Order |

### Invariant

Order total must always equal sum of line totals → Transactional consistency required.

### Conclusion

Same volatility + shared invariant → Same aggregate.

```
// ✅ Correct
Order (aggregate root)
  └── OrderLines (in same aggregate)
```

---

## Example 3: Product and Inventory

### Volatility Analysis

| Entity | Change Frequency | Change Reasons | Stakeholders |
|--------|------------------|----------------|--------------|
| Product | Low (weekly) | New products, price changes, descriptions | Product management |
| Inventory | High (per transaction) | Stock changes, reservations, replenishment | Warehouse, sales |

### Conclusion

Different volatility → Separate aggregates.

```
// ✅ Correct
Product (aggregate root)
  └── Name, Description, Price

Inventory (aggregate root)
  └── ProductId (reference)
  └── StockLevel, ReservedQuantity
```

Handle stock reservation via eventual consistency and domain events, not transactional consistency.

---

## Large Collections Problem

If an aggregate root references thousands of child entities, volatility analysis reveals the issue:

```
// ❌ Problem
Customer (aggregate root)
  └── Orders (10,000 orders)
```

**Volatility reveals**: Orders change constantly (high volatility), Customer profile changes rarely (low volatility).

**Solution**: Separate by volatility.

```
// ✅ Correct
Customer (aggregate root)
  └── Profile

Order (aggregate root)
  └── CustomerId (reference)
```

Query orders by customer ID when needed, not by loading the entire customer aggregate.

---

## Decision Framework

```
1. Identify candidate entities
     ↓
2. Analyze volatility for each
     ↓
3. Different volatility? → Separate aggregates
     ↓
4. Same volatility? → Check for shared invariant
     ↓
5. Shared invariant? → Same aggregate
     ↓
6. No shared invariant? → Separate aggregates
```

---

## Anti-Pattern: Entity-Based Aggregates

Don't size aggregates based on entity relationships alone.

```
// ❌ Wrong — Based on ER diagram, ignoring volatility
Customer
  ├── Orders
  │     └── OrderLines
  ├── Addresses
  └── PaymentMethods
```

This creates a massive aggregate with mixed volatility profiles, leading to:
- Performance problems (loading entire graph)
- Concurrency issues (high contention)
- Coupling unrelated concerns

**Fix**: Apply volatility analysis, create separate aggregates.
